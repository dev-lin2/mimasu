# Phase 0 findings — extension host

The written output Phase 0 asks for (`INSTRUCTIONS.md` §14): the exact feature
name, metadata keys, lib versions and class surface that a real extension
actually needs. Everything here was read off a device, not recalled.

**Method.** Two real Tachiyomi-family extension APKs were installed on a Pixel 5
emulator (Android 12, API 31) and inspected with the in-app host probe, plus
static inspection of `classes.dex`.

| | |
|---|---|
| Probed | `eu.kanade.tachiyomi.extension.en.tapastic` v1.4.24 (104024), lib 1.4 |
| | `eu.kanade.tachiyomi.extension.en.webtoonscan` v1.6.54 (106054), lib 1.6 |
| Source | `keiyoushi/extensions` release artifacts |
| Host | `com.handypick.mimasu`, Android 12 / API 31 |
| Date | 2026-09-08 |

Both are **manga** extensions. They exercise discovery, metadata, signature
verification and class loading identically to anime ones; only the source
interface differs. Anime-specific names remain unconfirmed and are flagged as
such below.

---

## 1. Discovery — CONFIRMED

**Manifest feature name:** `tachiyomi.extension`

`PackageManager.getInstalledPackages` with `GET_CONFIGURATIONS |
GET_META_DATA | GET_SIGNING_CERTIFICATES` finds them, and
`packageInfo.reqFeatures` carries the name. `QUERY_ALL_PACKAGES` is required on
API 30+ or the scan returns nothing.

For anime, expect `tachiyomi.animeextension` by the same pattern. **Not
confirmed.** Do not hardcode it — the probe takes its search terms as a
parameter precisely so this can be answered rather than assumed.

## 2. Manifest metadata — CONFIRMED

Read from `applicationInfo.metaData`:

| Key | Example | Meaning |
|---|---|---|
| `tachiyomi.extension.class` | `keiyoushi.source.Generated` | Source class(es). Semicolon-separated when there are several. |
| `tachiyomi.extension.nsfw` | `1` | NSFW flag. |
| `tachiyomix.extensionLib` | `1.4`, `1.6` | The `extensions-lib` version. |
| `tachiyomix.contentWarning` | `1` | Repository-specific. |
| `tachiyomix.name` | `Tapas` | Repository-specific display name. |

Two things worth noting:

- The `tachiyomi.extension.*` keys are the upstream contract. The
  `tachiyomix.*` keys are **not** — they are added by this repository's build
  tooling, so treat them as optional and never require them.
- The class name is the same (`keiyoushi.source.Generated`) in both
  extensions. This repository generates a fixed-name wrapper rather than
  exposing the underlying source class, so **the class name is not a stable
  identifier** and must always be read from metadata.

Both extensions declared `tachiyomix.contentWarning = 1` while the repository
index gave `content_rating` 2 for both, so **those two fields are not the same
thing.** The index field remains unidentified
(`extension-format/schema/index-pb.md`).

## 3. Signature verification — CONFIRMED, end to end

APK signing certificate SHA-256, as computed by the host:

```
9A:DD:65:5A:78:E9:6C:4E:C7:A5:3E:F8:9D:CC:B5:57:
CB:5D:76:74:89:FA:C5:E7:85:D6:71:A5:A7:5D:4D:A2
```

Lowercased and stripped of separators that is
`9add655a78e96c4ec7a53ef89dccb557cb5d767489fac5e785d671a5a75d4da2` — **exactly**
the signing key the repository index declares in its header.

So the trust model of §5.5 works: a repository's declared key can be checked
against the certificate of the APK it serves, and the host's fingerprinting
produces the matching value. Use `signingInfo.signingCertificateHistory` (or
`apkContentsSigners` when `hasMultipleSigners()`) on API 28+.

This does not make the repository's claim trustworthy — it only proves the APK
came from whoever holds that key. The prompt of §5.5 is still required.

## 4. Class loading — the shim is now the blocking work

`PathClassLoader(sourceDir, parentClassLoader)` constructs fine, and the app
can read another package's `base.apk` (verified: 80,795 bytes read as the app's
own UID via `run-as`). So neither the path nor permissions are the problem.

`Class.forName("keiyoushi.source.Generated", false, loader)` nonetheless fails.
That is **the expected result**, and it is the whole point of §5.2: the class
extends and references library types that the extension does not ship, so
resolving it requires the host to provide them first. Until the shim exists, no
extension class can load.

### The surface an extension actually expects — CONFIRMED

Extracted from `classes.dex`. This is the concrete, ordered work list that
replaces §5.2's recalled guess.

**The library itself** (`eu.kanade.tachiyomi.*`), manga flavour:

```
eu.kanade.tachiyomi.source.online.HttpSource
eu.kanade.tachiyomi.source.ConfigurableSource
eu.kanade.tachiyomi.source.model.SManga        (+ Companion)
eu.kanade.tachiyomi.source.model.SChapter      (+ Companion)
eu.kanade.tachiyomi.source.model.Page
eu.kanade.tachiyomi.source.model.MangasPage
eu.kanade.tachiyomi.source.model.Filter
eu.kanade.tachiyomi.source.model.FilterList
eu.kanade.tachiyomi.network.NetworkHelper
eu.kanade.tachiyomi.network.RequestsKt
```

Note this is `eu.kanade.tachiyomi.source.*`, **not** `...animesource.*`. The
anime flavour is expected to mirror it with `AnimeHttpSource`,
`ConfigurableAnimeSource`, `SAnime`, `SEpisode`, `Video`, `AnimesPage`,
`AnimeFilter`, `AnimeFilterList` — still unconfirmed.

**Third-party libraries the host must also supply on the classpath:**

| Library | Referenced |
|---|---|
| OkHttp 4 | `okhttp3.*` extensively — `OkHttpClient`, `Request`, `Response`, `Headers`, `HttpUrl`, `Interceptor`, `MediaType`, `ResponseBody`, `CacheControl`, `Call` |
| Okio | `okio.BufferedSource` |
| Jsoup | `org.jsoup.Jsoup`, `.nodes`, `.select` |
| **RxJava 1** | `rx.Observable` |
| **Injekt** | `uy.kohesive.injekt.InjektKt`, `.api.InjektScope`, `.api.InjektFactory`, `.api.FullTypeReference` |
| AndroidX Preference | `Preference`, `PreferenceScreen`, `SwitchPreferenceCompat`, `Preference.OnPreferenceChangeListener` |
| kotlinx.serialization | serializers and descriptors |

**§5.2's guesses about Injekt and RxJava were right.** A lib-1.4 extension
still uses `rx.Observable` and obtains its dependencies through Injekt, so both
must be on the classpath and Injekt must have `NetworkHelper` and
`SharedPreferences` registered *before* any source class is instantiated.

The AndroidX Preference references confirm §5.6: preferences really are built
as `androidx.preference` objects, so the host's `PreferenceScreen` stand-in has
to satisfy that API.

## 5. Install permission — a gap in the spec and the design

`canRequestPackageInstalls()` returns **false** on a fresh install.

§5.4 reads as though declaring `REQUEST_INSTALL_PACKAGES` is sufficient. It is
not: the grant is per-app and made by the user in system settings. Until then
the installer intent cannot succeed.

The install flow therefore needs a permission gate before the installer is
launched, and **the design has no screen for it** — worth adding to
`docs/design.pen` before Phase 1's install work.

---

## What this changes

1. §5.2's class list moves from recalled to confirmed, for manga. Write the
   shim against §4 above, in that dependency order: model types, then
   `HttpSource`, then `NetworkHelper` and Injekt registration.
2. The lib version comes from **both** the index and the APK metadata, so it
   can be checked before download and again after install.
3. Signature verification is proven and can be built now.
4. §17 open decision 1 narrows from "what is the surface?" to "does the anime
   flavour mirror it?", which needs one anime extension to answer.
5. §5.4 needs a permission gate, and the design needs a screen for it.

## Still unknown

- **The anime class names.** Everything above is the manga flavour. One anime
  extension APK resolves it.
- **Which `extensions-lib` versions to support.** 1.4 and 1.6 were both seen in
  the wild, and a 1.4 extension uses RxJava. Supporting both means the shim
  needs the union of their APIs.
- **Whether `keiyoushi.source.Generated` is repository-specific.** Other
  repositories may expose real source class names. Since the class is always
  read from metadata this does not matter functionally, but it means the class
  name cannot be used to identify or de-duplicate a source.
