# Mimasu — Build Instructions

This document is the build specification for Mimasu. It is written to be handed to a
developer (or a Claude Code session) who will implement the app from scratch.

Read this file end to end before writing code. Where it says **VERIFY**, the fact could not
be confirmed offline and must be checked against the real toolchain, a real extension APK,
or a real repository index before you rely on it. There are more of these than in an
ordinary spec, because this app deliberately targets a third-party extension format whose
details live in someone else's source tree.

The screen designs referenced throughout live in [`docs/design.pen`](docs/design.pen) —
23 artboards plus 3 shared components.

---

## 1. What we are building

An **Android video app that ships no content and no content sources.** It is an extension
host, compatible with the **Aniyomi anime extension format**.

Everything playable comes from extension APKs the user installs themselves after pasting in
a repository URL they found. On a fresh install the app is empty: no sources, nothing to
browse, nothing to play.

### In scope (v1)

- Add and remove extension repositories by URL, in **both** index formats (§6)
- Install, trust, update, enable/disable and remove extension APKs
- Browse through installed extensions: popular, latest, search, with the extension's own filters
- Anime detail and episode list, sourced entirely from the extension
- Video playback with quality, audio-track and subtitle selection
- **Episode downloads** and offline playback
- A **local** library of saved series and watch progress
- Per-extension preferences, generated from what the extension declares
- Per-extension request log

### Explicit non-goals

- **No account or tracking integration.** No AniList, no MAL, no Simkl. The library is local
  only. This is a deliberate reduction from an earlier draft of this spec; a tracker can be
  added later behind its own repository interface, but nothing in v1 depends on one.
- **No metadata service.** There is no AniList-style catalogue underneath. Every title,
  synopsis, thumbnail and episode number comes from an extension. The app shows what the
  extension gives it and nothing more.
- **No bundled extensions, and no curated index of repositories.** The app ships with an
  empty repository list. Document the format; do not ship or link a directory of sources.
- **No prebuilt APK releases.** Users fork the repo and run the pipeline themselves (§12).
- **No manga.** Video only. Manga extensions implement a different interface (`HttpSource`
  with `SManga`/`SChapter`/`Page`) and will not load. Refuse them with a clear message.
- No torrent streaming. No iOS, no desktop. Android only.

### The security posture, stated honestly

An earlier draft of this spec ran extensions as JavaScript in a QuickJS sandbox and promised
that extensions could not open sockets, read files, or import anything. **That is no longer
true and no document or screen may claim it.**

Aniyomi extensions are Android APKs containing compiled Kotlin. Once installed they run as
real Android code in the app's process with the app's permissions, including network access.
There is no sandbox. What the app can offer instead is:

- **Signing-key verification.** Every extension's signing certificate is checked against a
  trusted set. An unrecognised key triggers an explicit, informed prompt before install (§5.5).
- **Best-effort request logging.** Extensions obtain an OkHttp client from the host, and the
  host installs an interceptor on it. An extension that builds its own client bypasses this.
  The UI must describe the log as useful, not complete.
- **Visible provenance.** Which repository an extension came from, its package name, version
  and key fingerprint, all surfaced in the UI.

Every user-facing string about extension safety must be consistent with the three bullets
above. Do not write "sandboxed".

---

## 2. Tech stack

| Concern | Choice | Why |
|---|---|---|
| App framework | Flutter, Android only | Owns UI, local storage and orchestration |
| Language | Dart 3.x + **Kotlin** | The extension host cannot be anything but Kotlin (§5) |
| Dart↔Kotlin bridge | **`pigeon`** | Typed, generated channel. Only plain data crosses — see §3 |
| Extension host | Kotlin, `PathClassLoader` + reflection | The only way to load Aniyomi extension APKs (§5.3) |
| Extension HTTP | **OkHttp** (Kotlin side) | What extensions expect to be handed. Not `dio` |
| HTML parsing | **Jsoup** (Kotlin side) | Extensions call `asJsoup()` and expect Jsoup nodes |
| Extension DI | **Injekt** (`uy.kohesive.injekt`) | Extensions use `injectLazy()` to obtain the network client and preferences. **VERIFY** the exact artifact and version an extension expects |
| Reactive | **RxJava 1.x** shim | Older extensions return `rx.Observable`; newer ones are `suspend`. Support both. **VERIFY** which the current lib version uses |
| App-side HTTP | `dio` | Fetching repository indexes and downloading APKs only |
| `index.pb` decoding | `protobuf` Dart package, or a hand-rolled wire walker | See §6.2 |
| Video playback | **`media_kit`** (+ `media_kit_video`, `media_kit_libs_android_video`) | libmpv: HLS/DASH, custom headers, multiple audio tracks, external subtitles. Mitigate APK size with `--split-per-abi` (§12) |
| Downloads | **Kotlin foreground service** + `WorkManager` | Android kills background Dart isolates; a Dart-side download queue will not survive. Orchestrated from Dart, executed natively |
| State management | `flutter_bloc` (Cubits) + `rxdart` | Small, testable per-screen logic |
| DI (Dart side) | `get_it` | |
| Local storage | `hive_ce` (+ `hive_ce_generator`) | |
| Routing | `go_router` | Small nav graph, no codegen |
| Codegen | `freezed`, `json_serializable`, `build_runner`, `pigeon` | |
| Logging | `logger` | |

### Removed from the previous draft

`flutter_qjs` / `flutter_js` (no JavaScript runtime), `flutter_secure_storage` and
`app_links` (no OAuth), and the AniList GraphQL layer. If you find references to these
anywhere, they are stale.

### Toolchain

- **Flutter**: latest stable. Pin it in `.fvmrc` and in CI.
- **JDK 17 or 21 — not 25.** Flutter's bundled Gradle and AGP do not support JDK 25. Point
  Flutter at a supported one: `flutter config --jdk-dir=<path>`. Expect to hit this on the
  first Gradle build.
- **Android SDK**: accept licenses with `flutter doctor --android-licenses`.
- **minSdk 24**, targetSdk latest.
- The app needs `REQUEST_INSTALL_PACKAGES` to install extension APKs (§5.4).

---

## 3. Architecture

```
presentation  →  application  →  domain  ←  data
                                     ↑
                              extensions (Dart)
                                     ↑
                            Pigeon channel
                                     ↑
                          Kotlin extension host
```

| Layer | Contains | Rules |
|---|---|---|
| `domain/` | Entities, repository interfaces | Pure Dart. No Flutter, no platform channels, no `dart:io`. |
| `data/` | Repository implementations, DTOs, Hive adapters | Implements domain contracts. |
| `extensions/` | Dart side of the channel, extension manager, repo index parsing | Implements a domain contract like any other data source. |
| `application/` | Cubits + Freezed states | No channel types, no DTOs. |
| `presentation/` | Screens, widgets | Mobile-first. Reads cubit state only. |
| `android/.../host/` | Kotlin extension host and lib shim | Knows nothing about the UI. |

### The one hard rule

**No runtime-specific or wire-specific type may appear in a domain entity, a cubit, or a
state class.**

The Pigeon boundary helps you here: only plain serializable data can cross a platform
channel, so a Kotlin `SAnime` physically cannot end up in a Dart state class. Do not
undo that by passing Pigeon-generated classes upward — map them to domain entities at the
`extensions/` boundary and let nothing above that point know a channel exists.

This is what makes the content backend swappable and testable. Cubit tests must be able to
run with no Android host present at all.

---

## 4. Project layout

```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── di/locator.dart
│   ├── router/app_router.dart
│   ├── theme/                        # tokens mirror docs/design.pen (§10)
│   ├── log/
│   └── services/http/                # dio: repo indexes and APK downloads only
├── domain/
│   ├── entities/
│   │   ├── source/                   # SAnime, SEpisode, Video, Track, AnimeFilter
│   │   ├── extension/                # Extension, ExtensionRepo, TrustState, PreferenceItem
│   │   ├── library/                  # LibraryEntry, WatchProgress
│   │   └── download/                 # DownloadTask, DownloadState
│   └── repositories/                 # ContentSourceRepository, ExtensionRepository,
│                                     # LibraryRepository, DownloadRepository
├── data/
│   ├── repositories/
│   ├── models/
│   └── adapters/
├── extensions/
│   ├── host/
│   │   ├── extension_host.dart       # Dart side of the Pigeon channel
│   │   └── host_api.g.dart           # generated
│   ├── repo/
│   │   ├── repo_index_parser.dart    # interface
│   │   ├── json_index_parser.dart    # index.min.json
│   │   └── pb_index_parser.dart      # index.pb
│   ├── extension_manager.dart        # install / trust / update / remove / enable
│   └── content_source_native.dart    # implements ContentSourceRepository
├── application/{cubits,states}/
└── presentation/{screens,widgets}/

android/app/src/main/kotlin/<pkg>/
├── host/
│   ├── ExtensionLoader.kt            # PackageManager discovery + PathClassLoader
│   ├── ExtensionInstaller.kt         # installer intents, signature checks
│   ├── SourceRegistry.kt             # loaded source instances by id
│   ├── SourceCaller.kt               # invokes source methods, maps results to Pigeon
│   ├── PreferenceCollector.kt        # §5.6
│   └── HostApi.kt                    # generated Pigeon interface impl
├── shim/                             # the Aniyomi extensions-lib surface (§5.2)
│   └── eu/kanade/tachiyomi/...
└── download/
    └── DownloadService.kt            # foreground service + WorkManager

docs/
└── design.pen                        # 23 screens, 3 components

extension-format/
├── README.md                         # what Mimasu supports and what it does not
└── schema/                           # index.min.json shape, derived index.pb schema

test/
├── unit/
├── extensions/fixtures/              # saved index.min.json and index.pb payloads
└── integration/
```

---

## 5. Extension system

This is the heart of the app and by far the riskiest part. Build it first (§14 Phase 0).

### 5.1 What an Aniyomi extension actually is

A separate Android application package containing compiled Kotlin. It is **not** a script,
not a bundle, and not something the app can parse. It declares itself in its manifest with
metadata the host queries for, and it links against an `extensions-lib` API that the
extension itself does **not** ship — the library is `compileOnly` at extension build time,
so **the host must provide those exact classes at runtime**.

That last sentence is the whole design constraint. Get it wrong and every extension throws
`NoClassDefFoundError`.

### 5.2 The compatibility shim

The host must supply the Aniyomi anime extension API under its original package names.
**VERIFY every name below against the extensions-lib version you are targeting** — these are
recalled, not confirmed, and the API has versioned over time.

Expected surface, anime side:

- `eu.kanade.tachiyomi.animesource` — `AnimeSource`, `AnimeCatalogueSource`,
  `ConfigurableAnimeSource`, `AnimeSourceFactory`
- `eu.kanade.tachiyomi.animesource.online` — `AnimeHttpSource`, `ParsedAnimeHttpSource`
- `eu.kanade.tachiyomi.animesource.model` — `SAnime`, `SEpisode`, `Video`, `Track`,
  `AnimeFilter`, `AnimeFilterList`, `AnimesPage`
- `eu.kanade.tachiyomi.network` — `NetworkHelper`, `GET`, `POST`, `asObservableSuccess`,
  interceptor plumbing
- `eu.kanade.tachiyomi.util` — `asJsoup` and related response extensions
- `uy.kohesive.injekt` — `Injekt`, `injectLazy`, `get()`. Extensions use this to obtain
  `NetworkHelper` and `SharedPreferences`; the host must register both before any source
  class is instantiated.

**Do not copy Aniyomi's implementation.** Provide the API surface and your own behaviour
behind it. See §13 for the licensing consequence, which is real and must be honoured.

Record the `extensions-lib` version you target. An extension declares the lib version it
was built against; refuse anything outside the range you support and say so in the UI
naming the extension and both versions.

### 5.3 Discovery and loading

Follow the approach Aniyomi and Mihon use:

1. Query `PackageManager` for installed packages declaring the anime-extension feature.
   **VERIFY** the exact feature name and metadata keys — expect something in the shape of
   `tachiyomi.animeextension` with metadata giving the source class list, an NSFW flag, and
   the lib version.
2. For each match, build a class loader over the package's APK path
   (`PathClassLoader(apkPath, parentClassLoader)`).
3. Instantiate each declared class and cast to `AnimeSource` or `AnimeSourceFactory`.
   A factory yields several sources — usually one per language.
4. Register the resulting instances in `SourceRegistry` keyed by source id.

Notes that will bite you:

- Loading DEX from an arbitrary downloaded file is restricted on modern Android. The
  supported path is what Aniyomi does: the extension is genuinely **installed as a package**
  and loaded from its installed APK. Do not attempt to load an un-installed APK.
- One class loader per extension, discarded when the extension is disabled or removed.
- Source instantiation runs extension code. Treat it as fallible; a throwing constructor
  must surface as a typed failure naming the extension, never a crash.

### 5.4 Installing

1. Download the APK from the URL the repository index gave, over `dio`, into app storage.
2. Check the signing certificate before offering to install (§5.5).
3. Hand off to the system package installer via intent. The app needs
   `REQUEST_INSTALL_PACKAGES`, and the user must allow installs from Mimasu once, at OS level.
4. Observe the install result, then re-run discovery.

The UI for this is drawn: the Extensions screen, the untrusted prompt, and step 3 of the
add-a-source guide all describe exactly this flow, including the OS installer appearing.

### 5.5 Trust

- Read the APK's signing certificate and compute its fingerprint.
- Compare against the set of keys the user has already trusted. Mimasu ships **no**
  pre-trusted keys, because it endorses no repository.
- Unknown key → the extension is installed in an **untrusted** state and must not be loaded
  or instantiated until the user explicitly approves it.
- The prompt must show package name, version, key fingerprint and originating repository,
  and must say plainly that extensions run as real Android code with their own network
  access. The designed dialog does this; keep its wording.
- Trust is per key, revocable in settings. Revoking unloads every extension under that key.

### 5.6 Preferences

`ConfigurableAnimeSource` exposes `setupPreferenceScreen(screen)`, into which an extension
adds androidx `Preference` objects — typically list, switch and text preferences.

The host provides its own `PreferenceScreen` implementation that **records** what the
extension adds rather than rendering it, and exposes the result as serializable descriptors
(`key`, `type`, `title`, `summary`, `default`, `entries`). Flutter renders them; values are
written back into the `SharedPreferences` instance that extension was given via Injekt,
namespaced per extension.

This is fiddly and easy to get subtly wrong. **VERIFY** the preference classes an extension
actually constructs before designing the descriptor type.

### 5.7 Request logging

Register an interceptor on the `NetworkHelper` OkHttp client the host hands to extensions,
and record host, method, status and timing per extension. Surface it in the extension's
settings screen.

State the limitation in the UI: an extension that constructs its own client is not covered.
The designed copy already says "useful rather than complete" — do not upgrade that claim.

### 5.8 Failure handling

Errors are values. An extension that throws, hangs, or returns nonsense must surface as a
typed failure in the cubit state, with a readable message naming the extension and the call.
Never a crash, never a silent empty list.

Apply a wall-clock timeout per call. The designed error states show a 30-second budget and
name the failing method — `getEpisodeList · timed out at 30s` — so keep that shape.

---

## 6. Repository index formats

A repository is a file at a user-supplied URL listing the extensions it offers. The app
ships **no** default URLs.

Both formats must be supported, behind one `RepoIndexParser` interface, chosen by sniffing
the URL and the payload rather than trusting the extension of the filename.

### 6.1 `index.min.json`

The long-standing format. A JSON array of extension entries. Expected fields per entry —
**VERIFY against a real index before writing the model**: `name`, `pkg` (package name),
`apk` (filename, resolved relative to the index URL), `lang`, `code` (version code),
`version`, `nsfw`, and a nested `sources` array carrying each source's `name`, `lang`, `id`
and `baseUrl`.

Parse it as JSON. Never evaluate it.

### 6.2 `index.pb`

The newer protobuf-encoded index. A known live example, given by the project owner:

```
https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb
```

Note that this particular repository is **manga** extensions and its sources will not load
in Mimasu — it is a format reference only. Anime-side repository URLs are needed for
testing, and finding them is the user's job, not the project's.

**There is no published `.proto` to work from, so derive the schema empirically:**

1. Fetch both `index.min.json` and `index.pb` from the same repository.
2. Walk the protobuf wire format generically — every field carries a field number and wire
   type, so the structure can be decoded with no schema at all.
3. Match decoded values against the JSON entries to establish the field mapping.
4. Commit both payloads as fixtures and write the decoder against them.

Do not guess the schema and do not hand-write a `.proto` from memory. The derived mapping,
once confirmed, belongs in `extension-format/schema/` with the fixtures that prove it.

### 6.3 Rules for both

- An entry the app cannot install is a **value, not a parse error**. A manga extension, an
  unsupported lib version, an unreadable entry — all must appear in the list, marked
  unsupported, with the reason shown. The Extensions screen has a drawn state for this.
- Refusing an entry must never fail the whole index.
- Store the repository URL, its format, and the last fetch time. Re-fetch on demand.

---

## 7. Library (local)

- Saved series, watch progress and per-episode resume positions, all in Hive. No sync, no
  accounts, no network.
- A library entry records which extension it came from, plus the source's own url/id. If
  that extension is later removed, the entry must survive and say so rather than vanish.
- Progress is written on pause and on dispose, keyed by extension id + episode url.
- Watch state buckets match the designed tabs: Watching, Completed, Planning, Dropped.

---

## 8. Playback

- `media_kit` with `media_kit_video`.
- Pass the `headers` from the extension's `Video` through to the player. Many sources 403
  without a `Referer`. This is not optional.
- Support quality switching between returned `Video` entries, audio-track and subtitle-track
  selection from the returned `Track` lists, external subtitle URLs, seek/skip and speed.
- Landscape fullscreen, wakelock while playing, Android audio focus, PiP.
- Resume positions persisted per episode (§7).
- Playback failure must name the source and the actual HTTP status. The designed error
  screen shows `Example Source · HTTP 403 · cdn.example.test`; keep that specificity.

---

## 9. Downloads

New in this revision of the spec, and a phase of its own.

- A **Kotlin foreground service** owns the queue and performs the writes. Dart enqueues,
  cancels, reorders and observes; it does not download.
- Persist the queue so it survives process death. Resume partial files where the server
  supports ranges.
- Downloads use the same `Video` and headers the player would, obtained from the extension.
- Store under app-specific external storage, laid out by extension → series → episode.
- Settings, as drawn: location, quality, Wi-Fi-only, and delete-after-watching.
- The player must prefer a local file when one exists, transparently.
- Deleting an extension must not orphan its files silently — offer to remove them.

---

## 10. UI

The screens are already designed. **`docs/design.pen` is the reference; do not re-invent
layouts.** 23 artboards, 3 reusable components (Status Bar, Poster Card, Nav Bar).

Screens: Onboarding ×3, Home, Search, Library, Anime Details, Player, Extensions, Extension
Settings, Settings, Downloads, Help & Setup, Guide — Add a Source, Source Picker Sheet,
Untrusted Extension Prompt, and state variants — Home Loading, Search No Results, Library
Empty, Extensions Empty, Anime Details No Source, Anime Details Source Failed, Player
Playback Error.

Design system, as defined in the file's variables:

- Dark only. `ground #08090B`, `surface #121418`, `surfaceRaised #1A1D23`, `outline #2A2E36`,
  text `#F2F3F5` / `#9BA1AC` / `#6B7280`, accent `#FF5E5B`.
- A light theme is **not designed**. Derive one from `ColorScheme.fromSeed` if you ship one.
- Roboto Flex. Four sizes in practice: 28 / 20 / 15 / 13.
- No drop shadows; separation comes from surface steps plus hairline outlines. The only
  gradients are the Details banner scrim and the player control scrim, both functional.
- 48dp minimum touch targets, 16dp gutters, 8dp poster radius, 12dp card radius.
- Material 3 `NavigationBar`, flush to the bottom with a pill indicator — **not** the
  floating capsule bar the pen.dev mobile guide suggests.
- Build against `MediaQuery` and `LayoutBuilder`. Never adopt a fixed `designSize`; that is
  what makes an app structurally unable to render on a phone.
- Every list needs its loading, empty and error state. They are drawn. Use them.

### First-run

Onboarding is three screens and leads with what the app does, not what it lacks. It must
still make clear that a source is required before anything plays — otherwise a user reaches
Details and hits a dead end with no explanation. The Details no-source state is the backstop
for anyone who skips onboarding.

---

## 11. Storage

| Data | Where |
|---|---|
| Repository URLs, format, fetch times | Hive |
| Installed extension metadata, trust state, trusted keys | Hive |
| Per-extension preferences | Android `SharedPreferences`, namespaced per extension |
| Library entries, watch progress, resume positions | Hive |
| Download queue | Native, persisted; mirrored to Dart for display |
| Downloaded video files | App-specific external storage |
| Extension APKs | Installed as packages by the OS; the app keeps no copy |

There is nothing to keep in a keystore, because there are no tokens.

---

## 12. Build and CI

The distribution model is **source only; users fork and build**.

```sh
flutter pub get
dart run pigeon --input pigeons/host_api.dart
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --split-per-abi
```

`--split-per-abi` matters: `media_kit` bundles native libs and a universal APK gets large.

### CI (`.github/workflows/build.yml`)

- Triggers: `workflow_dispatch` and `push: tags`, so it runs in **the forker's** repo.
- Steps: checkout → JDK 17 → Flutter (pinned) → `pub get` → pigeon → `build_runner` →
  `flutter analyze` → `flutter test` → Kotlin unit tests → `flutter build apk --release
  --split-per-abi`.
- Publish APKs as **workflow artifacts**, never as a release on the upstream repo.
- **No signing keystore in the repository.** Debug signing by default. Document the optional
  path: a forker adds `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` as
  secrets and CI decodes them into `android/key.properties`. Changing keystore breaks
  in-place upgrades.
- Hold `flutter analyze` at zero warnings from the first commit.

---

## 13. Write from scratch — and the one honest exception

**No code is copied from any other project.** Mimasu is written fresh.

There is, however, an unavoidable exception that the earlier draft of this spec did not
anticipate. The compatibility shim in §5.2 **must reproduce Aniyomi's `extensions-lib` API
surface** — the same package names, class names and method signatures — or no extension will
load. That is interface compatibility, not copied implementation, but it is not "nothing
borrowed" either.

Consequences to honour:

- Aniyomi and its extensions library are Apache-2.0. Ship a `NOTICE` file with proper
  attribution, and state the compatibility relationship in the README.
- Reproduce **signatures only**. Behaviour behind them is ours.
- Mimasu is not affiliated with, endorsed by, or a fork of Aniyomi or Mihon. Say so.

Sources of truth to work from rather than code to copy: the Aniyomi extensions-lib API as
published, a real extension APK's manifest and class list, and a real repository index in
both formats.

Two design mistakes worth naming, because they are easy to repeat and expensive to undo:

1. **Runtime types leaking upward.** Keeping platform-channel or host types in state classes
   welds the app to one content backend. See the hard rule in §3.
2. **A fixed design size.** Hardcoding a `designSize` makes an app structurally unable to
   render on a phone. See §10.

---

## 14. Implementation order

Each phase ends with something runnable on a device. Do not start a phase before the
previous one runs.

**Phase 0 — Extension host spike. Do this first; it is the riskiest unknown and it gates
everything.**
In a bare Flutter Android app with a Kotlin host, prove end to end that you can: install a
**real Aniyomi anime extension APK**, discover it through `PackageManager`, provide enough of
the §5.2 shim for its classes to resolve, instantiate a source, call its popular-anime
method, and return the parsed result to Dart over Pigeon.
If the shim surface turns out to be larger than expected, or the lib version you target has
moved, find out now. Output: a throwaway spike plus a written note of the exact class list,
metadata keys and lib version that actually worked. **Everything in §5 depends on this.**

**Phase 1 — Scaffold + extension management**
Project structure, DI, routing, theme from §10, Hive, dio, Pigeon wiring. Repository add in
both formats (§6), extension list, install via installer intent, the trust prompt, and
enable/disable/remove. Onboarding.
*Done when:* you can paste a real anime repository URL, install an extension, trust it, and
see it listed as enabled.

**Phase 2 — Browse through extensions**
`ContentSourceRepository` over the host. Home with source switcher, popular and latest,
search with the extension's filters, details, episode list. The no-source and source-failed
states.
*Done when:* an installed extension populates Home and a real episode list.

**Phase 3 — Playback**
`media_kit`, headers passthrough, quality/audio/subtitle selection, resume positions, the
playback error state.
*Done when:* an episode plays start to finish with a subtitle track selected.

**Phase 4 — Downloads**
The Kotlin foreground service, queue persistence, the Downloads screen, offline playback,
download settings.
*Done when:* an episode downloads, survives a process kill, and plays with no network.

**Phase 5 — Library and preferences**
Local library and progress, the four watch buckets, per-extension preferences from §5.6, and
the per-extension request log.

**Phase 6 — Polish and pipeline**
Help & Setup and the guides, error and empty states throughout, the CI workflow of §12, the
docs of §15, and a `NOTICE` file per §13.

---

## 15. Documentation to write

- **`README.md`** — what the app is, that it ships no content and no sources, fork-and-build
  instructions, how extensions work including the honest security posture, the Aniyomi
  compatibility statement, disclaimer and credits.
- **`extension-format/README.md`** — which extension format Mimasu loads and which it does
  not, both repository index formats, the trust model, the lib version supported, and what
  makes an extension appear as unsupported.
- **`NOTICE`** — Apache-2.0 attribution per §13.

---

## 16. Testing

- **Unit**: entity mapping, both repo index parsers (including malformed input, a manga
  entry, an unsupported lib version, and a truncated protobuf), trust-state transitions,
  download queue state machine.
- **Index fixtures**: real `index.min.json` and `index.pb` payloads committed under
  `test/extensions/fixtures/`. These are the regression suite for §6 and must not require
  network access.
- **Kotlin host tests**: signature fingerprinting, metadata parsing, and the preference
  collector, against a checked-in test APK if one can be built.
- **Cubit tests**: `bloc_test` with `mocktail` repositories, no Android host present. Cover
  the failure paths explicitly: extension throws, extension times out, no extension
  installed, untrusted extension, network down, empty results.
- **Widget tests**: loading / empty / error states for the main screens.
- Name test files `*_test.dart`. Without the suffix `flutter test` silently collects nothing
  and the suite passes while testing zero code.

---

## 17. Open decisions

1. **The exact `extensions-lib` surface and version to target.** Resolve in Phase 0. Blocks
   all of §5. This has replaced the old JavaScript-runtime question as the project's single
   largest risk.
2. **Anime repository URLs for testing.** The project ships and recommends none, but
   development needs at least one real anime-side repository in each index format. Sourcing
   these is the owner's call, not the app's.
3. **`index.pb` schema**, to be derived per §6.2 and then frozen with fixtures.
4. **RxJava vs coroutines** in the shim — depends on the lib version from decision 1.
   Supporting both is likely.
5. **Tracker support** (AniList/MAL) is out of scope for v1. Decide later whether
   `LibraryRepository` should be shaped for it now or split when it arrives.
6. **`media_kit` vs `video_player`** — feature coverage against APK size. Defer to Phase 3;
   `Video` entities are player-agnostic either way.
