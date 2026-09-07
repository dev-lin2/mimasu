# Mimasu — Build Instructions

This document is the build specification for Mimasu. It is written to be handed to a
developer (or a Claude Code session) who will implement the app from scratch.

Read this file end to end before writing code. Where it says **VERIFY**, the fact could
not be confirmed offline and must be checked against pub.dev / the toolchain before you
rely on it.

---

## 1. What we are building

An **Android anime-watching app** that ships **no content and no content sources**.

The app is an extension host. All content comes from JavaScript extensions that the user
installs themselves by pasting in a repository URL. On a fresh install the app has an
empty source list and can browse nothing but public metadata.

### In scope (v1)

- Anime metadata browsing, search, and details (AniList)
- User library / list sync (AniList OAuth)
- JS extension runtime: install, update, remove, configure extensions
- Content discovery through installed extensions (popular, latest, search, details)
- Episode listing and video playback with quality, audio-track, and subtitle selection
- Release calendar

### Explicit non-goals

- **No bundled extensions, and no curated index of content-source repositories.** The app
  ships with an empty repository list. Document the *format* so anyone can write and host
  a source; do not ship or link a directory of sources.
- **No prebuilt APK releases.** Users fork the repo and run the pipeline themselves.
  See §11.
- No manga reading in v1. The architecture should not preclude it, but do not build it.
- No torrent streaming. (The reference implementation had this; it does not port to
  Android and is out of scope.)
- No iOS, no desktop. Android only.

---

## 2. Tech stack

| Concern | Choice | Why |
|---|---|---|
| Framework | Flutter, Android only | Single language across app and extension bridge |
| Language | Dart 3.x | |
| JS runtime | **`flutter_qjs`** (QuickJS over `dart:ffi`) | Promise/async support and two-way Dart↔JS function bridging, which the extension API needs. **VERIFY** current maintenance status and Android build on pub.dev. Fallback: `flutter_js` (QuickJS on Android). **Wrap it behind a `JsRuntime` interface (§5.6) so it is swappable in one file.** |
| HTTP | **`dio`** + `dio_cookie_manager` + `cookie_jar` | Extensions need cookies, redirect control, and per-request headers. `package:http` is too thin for this. |
| HTML parsing | **`package:html`** (`querySelectorAll`, CSS selectors) | Host-side parsing exposed to JS as bridge functions — see §5.4 |
| Video playback | **`media_kit`** (+ `media_kit_video`, `media_kit_libs_android_video`) | libmpv: HLS/DASH, custom headers, multiple audio tracks, external subtitles — matches what extensions return. Costs APK size; mitigate with `--split-per-abi` (§11). Alternative: `video_player` (ExoPlayer) is smaller and more battery-friendly but has weaker track/subtitle control. |
| State management | `flutter_bloc` (Cubits) + `rxdart` | Matches the reference implementation, so its cubits can be seeded (§12) |
| DI | `get_it` | Same reason |
| Local storage | `hive_ce` (+ `hive_ce_generator`) | Same reason |
| Routing | `go_router` | Simpler than `auto_route` for a small mobile nav graph and needs no codegen. **If you seed cubits/screens from the reference (§12), it uses `auto_route` — pick one and be consistent.** |
| Codegen | `freezed`, `json_serializable`, `build_runner` | |
| Metadata API | AniList GraphQL | |
| Logging | `logger` | |
| Secure token storage | `flutter_secure_storage` | OAuth tokens must not sit in Hive in plaintext |
| Deep links | `app_links` | AniList OAuth redirect (§7.2) |

### Toolchain

- **Flutter**: latest stable. Pin it in `.fvmrc` and in CI so builds are reproducible.
- **JDK 17 or 21 — not 25.** Flutter's bundled Gradle and the Android Gradle Plugin do not
  support JDK 25. If the machine has a newer JDK, install 17 or 21 and point Flutter at it:
  `flutter config --jdk-dir=<path>`. Expect to hit this on the very first Gradle build.
- **Android SDK**: accept licenses first with `flutter doctor --android-licenses`.
- **minSdk 24**, targetSdk latest. `media_kit` needs 21+; 24 avoids a pile of legacy paths.

---

## 3. Architecture

Clean layering, dependencies pointing inward:

```
presentation  →  application  →  domain  ←  data
                                     ↑
                                extensions
```

| Layer | Contains | Rules |
|---|---|---|
| `domain/` | Entities, repository interfaces | Pure Dart. No Flutter, no JS, no HTTP, no `dart:io`. |
| `data/` | Repository implementations, DTOs, Hive adapters | Implements domain contracts. Maps external shapes to entities at the boundary. |
| `extensions/` | JS runtime, bridge, extension manager | Implements a domain contract like any other data source. |
| `application/` | Cubits + Freezed states | No `dart:io`, no JS types. See the hard rule below. |
| `presentation/` | Screens, widgets | Mobile-first. Reads cubit state only. |

### The one hard rule

**No runtime-specific type may appear in a domain entity, a cubit, or a state class.**

The reference implementation violated this: JNI types (`JVideo`, `JPage`, `JSManga`,
`JSChapter`) leaked into its Freezed state classes, which is precisely why its content
layer could not be swapped or reused. Extensions must produce plain Dart entities at the
`data`/`extensions` boundary and nothing above that boundary may know JS exists.

If you find yourself writing `import 'package:flutter_qjs/...'` anywhere outside
`lib/extensions/`, stop — the design has gone wrong.

---

## 4. Project layout

```
lib/
├── main.dart
├── app.dart                          # MaterialApp.router, theme, localization
├── core/
│   ├── di/locator.dart               # get_it registrations
│   ├── router/app_router.dart
│   ├── theme/
│   ├── log/
│   └── services/
│       ├── http/                     # dio client, retry, cookie jar
│       └── api/
│           ├── graphql/queries/      # AniList GraphQL documents
│           └── dto/                  # wire-format DTOs (never leave data/)
├── domain/
│   ├── entities/
│   │   ├── media/                    # Anime, Episode, MediaList, MediaListEntry
│   │   ├── source/                   # SAnime, SEpisode, Video, Track, Headers, Page
│   │   └── extension/                # Extension, ExtensionRepo, PreferenceItem
│   └── repositories/                 # AnimeRepository, UserRepository,
│                                     # ExtensionRepository, ContentSourceRepository
├── data/
│   ├── repositories/
│   ├── models/
│   └── adapters/                     # Hive type adapters
├── extensions/                       # ← the only place that knows JS exists
│   ├── runtime/
│   │   ├── js_runtime.dart           # abstract interface (§5.6)
│   │   └── quickjs_runtime.dart      # flutter_qjs implementation
│   ├── bridge/
│   │   ├── bridge_registry.dart      # installs all bridge functions
│   │   ├── http_bridge.dart
│   │   ├── html_bridge.dart
│   │   ├── crypto_bridge.dart
│   │   └── prefs_bridge.dart
│   ├── extension_manager.dart        # install / update / remove / enable
│   ├── extension_loader.dart         # fetch repo index, download .js, hash, store
│   └── content_source_js.dart        # implements ContentSourceRepository
├── application/
│   ├── cubits/
│   └── states/
└── presentation/
    ├── screens/
    └── widgets/

extensions-spec/
├── README.md                         # the public extension authoring guide
├── example/example_source.js         # runs against test fixtures only
└── schema/repo-index.schema.json

test/
├── unit/
├── extensions/
│   └── fixtures/                     # saved HTML/JSON; extension tests hit these
└── integration/
```

---

## 5. Extension system

This is the heart of the app. Design it first, and design it so an Aniyomi-style source is
a mechanical port.

### 5.1 Guiding principle — the host does all I/O

Extensions **cannot** open sockets, touch the filesystem, or import modules. They receive
a bridge object and call it. Everything an extension does goes through Dart, which means:

- You control headers, user-agent, timeouts, retries, and caching in one place
- You can log and show the user exactly which URLs were requested
- A malicious extension has a small, auditable attack surface
- Extensions stay short and are mostly parsing logic

### 5.2 Repository index format

A repository is a single JSON file at a user-supplied URL. The app ships **no** default URLs.

```json
{
  "specVersion": 1,
  "name": "Example Repo",
  "extensions": [
    {
      "id": "com.example.source.en",
      "name": "Example Source",
      "lang": "en",
      "version": "1.0.0",
      "apiVersion": 1,
      "nsfw": false,
      "iconUrl": "https://.../icon.png",
      "sourceUrl": "https://.../example_source.js",
      "sha256": "<hex digest of the .js file>"
    }
  ]
}
```

- `apiVersion` must match the host's supported version, else refuse to install and say why.
- `sha256` is verified after download. Mismatch = refuse, do not run.
- Store the downloaded `.js` under the app support directory keyed by `id@version`.

### 5.3 Extension contract

An extension is one JS file that assigns a factory to a well-known global. Keep it simple —
no ES modules, no bundler required.

```js
// example_source.js
mimasu.register({
  metadata: {
    id: "com.example.source.en",
    name: "Example Source",
    lang: "en",
    baseUrl: "https://example.test",
    apiVersion: 1,
    nsfw: false,
  },

  // All methods are async and return plain JSON-serialisable objects.

  async getPopular(page) { /* → { items: [SAnime], hasNextPage: bool } */ },
  async getLatestUpdates(page) { /* → { items: [SAnime], hasNextPage: bool } */ },
  async search(query, page, filters) { /* → { items: [SAnime], hasNextPage: bool } */ },
  async getDetail(url) { /* → SAnime (full) */ },
  async getEpisodeList(url) { /* → [SEpisode] */ },
  async getVideoList(episodeUrl) { /* → [Video] */ },

  getFilterList() { /* → [Filter] — sync, describes the search UI */ },
  getPreferences() { /* → [PreferenceItem] — sync, describes the settings UI */ },
});
```

**Wire shapes** (these map 1:1 onto domain entities in `domain/entities/source/`):

```ts
SAnime    { url, title, thumbnailUrl?, description?, author?, status?,
            genres?: string[], episodes?: SEpisode[] }
SEpisode  { url, name, episodeNumber?: number, dateUpload?: number, scanlator? }
Video     { url, title, quality, videoUrl, headers?: Headers,
            audioTracks?: Track[], subtitleTracks?: Track[],
            bitrate?: number, resolution?: number }
Track     { url, label }
Headers   { <string>: <string> }
Filter    { type: "select"|"text"|"checkbox"|"group", key, label, values? }
PreferenceItem
          { type: "select"|"text"|"switch", key, title, summary?, default?, values? }
```

Note `Video` deliberately matches the reference implementation's `Video` entity field for
field — it already has `fromJson`/`toJson`, so it can be seeded verbatim once its
`fromJVideo` factory is deleted (§12).

### 5.4 The bridge API exposed to JS

Install these on the `mimasu` global before evaluating extension code:

```js
// Network — all requests go through Dart's dio client
mimasu.http.get(url, { headers, params })    → Promise<{ status, body, headers, finalUrl }>
mimasu.http.post(url, { headers, body, form })→ Promise<{ status, body, headers, finalUrl }>

// HTML — parsing happens in Dart (package:html); JS gets handles and strings
mimasu.html.parse(htmlString)                → docHandle
mimasu.html.select(handle, cssSelector)      → [nodeHandle]
mimasu.html.selectFirst(handle, cssSelector) → nodeHandle | null
mimasu.html.text(nodeHandle)                 → string
mimasu.html.attr(nodeHandle, name)           → string | null
mimasu.html.html(nodeHandle)                 → string
mimasu.html.release(handle)                  → void   // free the Dart-side node

// Utilities
mimasu.json.parse / mimasu.json.stringify
mimasu.crypto.md5(s) / sha256(s) / base64Encode(s) / base64Decode(s)
mimasu.prefs.get(key) / mimasu.prefs.set(key, value)   // scoped per extension id
mimasu.log(level, message)
```

Handles are integer keys into a per-extension Dart-side map. **Free them**: give every
extension invocation a scope and drop the whole map when the call returns, so a leaky
extension cannot grow memory without bound.

### 5.5 Sandboxing and safety requirements

These are requirements, not suggestions:

1. **One runtime instance per extension**, disposed when the extension is disabled.
2. **Wall-clock timeout per call** (default 30s). On timeout, kill the runtime and surface
   an error naming the extension.
3. **No ambient globals**: remove or stub anything the runtime exposes by default that
   touches I/O. QuickJS is already minimal — verify what `flutter_qjs` injects.
4. **Domain logging**: record every host that an extension requested, and show it in the
   extension's detail screen. Users should be able to see what a source is talking to.
5. **Never `eval` a repo index.** It is JSON; parse it as JSON.
6. **Verify `sha256`** before first execution and on every update.
7. **Errors are values.** An extension throwing must surface as a typed failure in the
   cubit state and a readable message in the UI — never a crash, never a silent empty list.

### 5.6 Swappable runtime interface

```dart
abstract class JsRuntime {
  Future<void> initialize();
  Future<void> evaluate(String code, {String? name});
  Future<Object?> callMethod(String method, List<Object?> args);
  void registerHostFunction(String name, Future<Object?> Function(List<Object?>) fn);
  Future<void> dispose();
}
```

`flutter_qjs`'s maintenance status is the single largest third-party risk in this project.
Everything else in the app must talk to `JsRuntime` only, so replacing QuickJS with
`flutter_js`, a WebView-based runtime, or a Rust/JNI engine is a one-file change.

---

## 6. Metadata layer (AniList)

- GraphQL over `dio`, documents as string constants under `core/services/api/graphql/queries/`.
- Queries needed: trending/popular/seasonal lists, search with filters, media details
  (+characters, +recommendations), airing schedule, user lists, list-entry mutations.
- DTOs in `data/`, mapped to `domain/entities/media/` at the repository boundary. DTOs must
  never escape `data/`.
- Cache list responses in Hive with a TTL; the app should open to content offline.

**Metadata and content are independent.** AniList gives titles, art, and episode counts;
extensions give playable video. Matching between them is by title and episode number and
will sometimes be wrong — make the chosen source and episode mapping visible and
user-correctable rather than silently guessing.

---

## 7. Auth

### 7.1 What to support

AniList OAuth for list sync, plus a fully functional **anonymous mode** — the app must be
usable with no account at all.

### 7.2 Do not copy the reference implementation's OAuth flow

It ran a `shelf` HTTP server on localhost to catch the redirect, which is a desktop
pattern. On Android use **App Links / a custom scheme** via `app_links`, registered in
`AndroidManifest.xml`. Store tokens in `flutter_secure_storage`, not Hive.

---

## 8. Playback

- `media_kit` with `media_kit_video`.
- Pass the `headers` from the extension's `Video` object through to the player; many sources
  require a `Referer` and will 403 without it.
- Support: quality switching between returned `Video` entries, audio-track and subtitle-track
  selection from `Track` lists, external subtitle URLs, seek/skip, playback-speed control.
- Landscape fullscreen, wakelock while playing (`wakelock_plus`), Android audio focus, PiP.
- Persist resume position per episode in Hive; write it on pause and on dispose.
- Sync progress back to AniList when an episode passes a completion threshold (~85%),
  and let the user turn that off.

---

## 9. UI

Mobile-first, built for touch. Do not port desktop layouts.

- **Shell**: bottom `NavigationBar` — Home, Library, Search, Settings.
- **Home**: vertically stacked horizontal carousels (Continue Watching, Trending, Popular
  This Season, Recently Updated).
- **Details**: collapsing `SliverAppBar` with banner art, metadata, then a source selector
  and episode list.
- **Player**: fullscreen landscape, tap-to-toggle controls, gesture seek and brightness/volume drags.
- **Extensions**: a screen to add a repo URL, browse that repo's extensions, install/update/
  remove, and open a per-extension settings page generated from `getPreferences()`.

Design notes:

- Material 3, `useMaterial3: true`, `ColorScheme.fromSeed`, with dynamic color via
  `dynamic_color` where the device supports it. Support dark and light.
- Build against `MediaQuery` and `LayoutBuilder`. Do **not** use a fixed design size —
  the reference implementation hardcoded `designSize: Size(1280, 720)` and that is exactly
  what made it unusable on a phone.
- Minimum 48dp touch targets. Assume one-handed use: primary actions in the lower half.
- Every list has explicit loading (skeletons), empty, and error states. Empty states must
  say what to do next — a fresh install with no extensions should explain that, not show
  a blank screen.

---

## 10. Storage

| Data | Where |
|---|---|
| OAuth tokens | `flutter_secure_storage` |
| User settings, extension repo URLs | Hive |
| Installed extension metadata | Hive |
| Extension `.js` files | App support dir, `extensions/<id>@<version>.js` |
| Per-extension preferences | Hive, namespaced by extension id |
| Metadata cache, resume positions | Hive, with TTL |

---

## 11. Build and CI

The distribution model is **source only; users fork and build**.

### Local build

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --split-per-abi
```

`--split-per-abi` matters: `media_kit` bundles native libs and a universal APK gets large.

### CI (`.github/workflows/build.yml`)

- Triggers: `workflow_dispatch` and `push: tags` — so it runs in **the forker's** repo.
- Steps: checkout → set up JDK 17 → set up Flutter (pinned) → `pub get` → `build_runner`
  → `flutter analyze` → `flutter test` → `flutter build apk --release --split-per-abi`.
- Publish the APKs as **workflow artifacts**, not as a release on the upstream repo.
- **No signing keystore in the repository.** Debug signing by default. Document the
  optional path: a forker adds `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`,
  `KEY_PASSWORD` as repo secrets and CI decodes them into `android/key.properties`.
  Note in the docs that changing keystore breaks in-place upgrades.
- Keep a `flutter analyze` gate at zero warnings from the first commit. It is far cheaper
  to hold that line than to reclaim it later.

---

## 12. Seeding from the reference implementation (optional but recommended)

A working desktop app with the same metadata layer is checked out at
`C:\Heysara\projects\unyo-app-mobile` (branch `rewrite`). It is the upstream author's
unreleased WIP. Roughly 13,000 lines of it are source-agnostic and worth copying rather
than retyping:

| From the reference | Lines | Notes |
|---|---|---|
| `lib/core/services/api/` | ~3,900 | AniList GraphQL (1,122 lines across 6 files), Shikimori, AniZip, HTTP+retry, DTOs |
| `lib/data/` | ~3,700 | Repositories, Hive adapters, models |
| `lib/domain/` | ~1,500 | Entities and contracts |
| `lib/application/` | ~4,300 | 12 of its 15 cubits are clean and reusable |

**Do not copy** its `lib/presentation/` (~9,300 lines of desktop UI), its platform folders,
or anything touching `window_manager`, `shelf`, `fvp`, or `torrserver`.

Three files need one deletion each — the factories are the entire coupling to the private
`unyo_lib` package, and everything else in them is plain Dart with working `fromJson`/`toJson`:

```
domain/entities/extension/video.dart:33     delete factory Video.fromJVideo
domain/entities/extension/headers.dart:8    delete factory Headers.fromJHeaders
domain/entities/extension/track.dart:16     delete factory Track.fromJTrack
```

Its three contaminated cubits (`anime_details_cubit`, `manga_details_cubit`, `video_cubit`)
and their states reference JNI types directly and must be retyped to the plain entities
before reuse — see the hard rule in §3.

**Attribution:** the reference repo's `LICENSE` file is BSD 3-Clause while its `README`
claims GPL-3.0 with an added attribution clause. Those imply different obligations and only
the upstream author can resolve which applies. Until then, satisfy both readings: retain the
original copyright notice for any copied file and credit the project prominently in
`README.md`. Confirm the license before publishing.

---

## 13. Implementation order

Each phase ends with something runnable on a device. Do not start a phase before the
previous one runs.

**Phase 0 — Toolchain spike (do this first, it is the riskiest unknown)**
Scaffold a bare Flutter Android app, add `flutter_qjs`, and prove you can: evaluate JS,
call a JS async function from Dart, and have that JS call back into a registered Dart
function. Pin the JDK. If `flutter_qjs` does not build or is abandoned, evaluate
`flutter_js` or a WebView runtime **now** — this decision blocks everything in §5.
Output: a throwaway spike plus a written note of what worked.

**Phase 1 — Scaffold + metadata**
Project structure, DI, routing, theme, Hive, dio. AniList browse/search/details. Bottom-nav
shell, home carousels, details screen. Anonymous mode only.
*Done when:* an APK installs and you can browse and search real anime metadata.

**Phase 2 — Extension infrastructure**
`JsRuntime`, the bridge (§5.4), extension manager and loader, repo-index parsing with
sha256 verification, the extensions UI. The example extension (§14) plus fixture-based tests.
*Done when:* you can add a repo URL, install the example extension, and call `getPopular`
against local fixtures.

**Phase 3 — Content through extensions**
`ContentSourceRepository` backed by JS. Source selector on the details screen, episode lists,
title/episode matching against AniList metadata.
*Done when:* an installed extension populates a real episode list.

**Phase 4 — Playback**
`media_kit` player, headers passthrough, quality/audio/subtitle selection, resume positions.
*Done when:* an episode plays start to finish with a subtitle track selected.

**Phase 5 — Accounts and library**
AniList OAuth over App Links, secure token storage, library screen, progress sync.

**Phase 6 — Polish and pipeline**
Extension preferences UI, per-extension request log, calendar, settings, error states,
the CI workflow of §11, and the docs of §14.

---

## 14. Documentation to write

- **`README.md`** — what the app is, the no-content stance, fork-and-build instructions,
  how extensions work, disclaimer, credits, license.
- **`extensions-spec/README.md`** — the extension authoring guide: the full contract from
  §5.3, the bridge API from §5.4, the repo index format from §5.2, versioning rules, and a
  walkthrough of the example extension.
- **`extensions-spec/example/example_source.js`** — a complete, working extension that
  parses the HTML fixtures in `test/extensions/fixtures/`. It must not target a real site;
  its job is to document the API and to be the test subject.
- **`CONTRIBUTING.md`** — setup, codegen, the `flutter analyze` gate, testing.

---

## 15. Testing

- **Unit**: entity mapping, title/episode matching, repo-index parsing (including malformed
  input and sha256 mismatch), each bridge function.
- **Extension harness**: run `example_source.js` against saved fixtures and assert the parsed
  entities. This is the regression suite for the bridge and the contract — it must not
  require network access.
- **Cubit tests**: `bloc_test`, with `mocktail` repositories. Cover the failure paths
  explicitly: extension throws, extension times out, network down, empty results.
- **Widget tests**: loading / empty / error states for the main screens.
- Name test files `*_test.dart`. The reference implementation has two files under `test/`
  that lack the suffix, so `flutter test` silently collects nothing — don't inherit that.

---

## 16. Open decisions

Flag these to the project owner rather than guessing:

1. **`flutter_qjs` viability** — resolve in Phase 0. Blocks §5.
2. **Upstream license** — BSD-3 or GPL-3? Determines obligations for seeded code (§12).
3. **`media_kit` vs `video_player`** — feature coverage against APK size. Defer to Phase 4;
   the `JsRuntime`-style separation is not needed here since `Video` entities are player-agnostic.
4. **Manga support** — out of scope for v1, but decide whether `ContentSourceRepository` should
   be generic over media type now, or be split later.
