<p align="center">
  <h1 align="center">Mimasu</h1>
</p>

<p align="center">An Android video app that plays what you bring to it.</p>

---

## What this is

Mimasu is an **extension host** for video. It provides the app — browsing, search, your
library, downloads, and the player — and nothing else.

It contains no content, no scrapers, and no list of places to get either. On a fresh install
it is empty: there is nothing to browse and nothing to play until you install an extension
yourself by pasting in the URL of a repository you chose.

Mimasu loads **Aniyomi-format anime extensions**. It is not affiliated with, endorsed by, or
a fork of Aniyomi or Mihon — it implements a compatible extension interface so that
extensions written for that format can run.

If you are looking for an app that works out of the box, this is not it, and that is
deliberate.

## Status

Early development. Not yet usable.

## Installing

**There are no downloads.** No APK is published here, and none will be.

To get a build, fork this repository and run the pipeline yourself:

1. Fork the repo to your own GitHub account.
2. Open the **Actions** tab and enable workflows.
3. Run the **Build APK** workflow (`workflow_dispatch`).
4. Download the APK from the workflow run's artifacts.
5. Install it on your device — you will need to allow installation from unknown sources.

Builds are debug-signed by default. To make a release-signed build, supply your own keystore
via repository secrets — see §12 of [`INSTRUCTIONS.md`](INSTRUCTIONS.md). Note that switching
keystores breaks in-place upgrades.

### Building locally

Requires the Flutter SDK (version pinned in `.fvmrc`), the Android SDK, and **JDK 17 or 21**
— newer JDKs are not supported by Flutter's Gradle toolchain.

```sh
flutter pub get
dart run pigeon --input pigeons/host_api.dart
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --split-per-abi
```

## How extensions work

An extension is an Android app of its own, containing compiled code that knows how to read
one website. You add a **repository** — a file at a URL you supply, in either the
`index.min.json` or the newer `index.pb` format — and Mimasu lists what that repository
offers. Installing one hands the APK to Android's package installer, so you will see the
system install prompt and need to allow installs from Mimasu once.

Mimasu ships **no** repository URLs and **no** pre-trusted signing keys, because it endorses
no repository.

### What this means for your security — read this part

Extensions are not sandboxed. Once installed, an extension runs as real Android code inside
the app, with the app's permissions, including full network access. There is no mechanism
that prevents an extension from doing whatever its author wrote.

What Mimasu does instead:

- **Checks signing keys.** Every extension's signing certificate is fingerprinted and
  checked against the keys you have already trusted. An unrecognised key gets an explicit
  prompt showing the package name, version, fingerprint and originating repository, before
  anything is installed or loaded. Trust is per key and revocable.
- **Logs requests, best effort.** Extensions are handed a network client that Mimasu
  instruments, so you can see which hosts a given extension has contacted. An extension that
  builds its own client will not appear in that log — treat it as useful, not complete.
- **Shows provenance.** Where each extension came from is always visible.

**Only install extensions you have reason to trust.** That judgement is yours; the app can
inform it but cannot make it for you.

**Finding extensions:** that is up to you. This project does not maintain or recommend a
directory of repositories. What you point the app at, and whether doing so is lawful where
you live, is your responsibility. Requests to add specific content sources will be closed —
the extension format is public precisely so that nobody has to ask.

Note that manga extensions will not work. Mimasu is video only, and manga extensions
implement a different interface; they will appear in a repository listing marked as
unsupported.

## Contributing

Bug reports and pull requests are welcome. [`INSTRUCTIONS.md`](INSTRUCTIONS.md) has the
architecture and the build specification, and [`docs/design.pen`](docs/design.pen) has the
screen designs.

## Disclaimer

- Mimasu contains no content and provides no means of obtaining any. It is a client
  application that loads third-party extensions.
- The developers of Mimasu are not responsible for any content accessed through
  third-party extensions, nor for the extensions themselves, and have no control over what
  any extension does or where it connects.
- Users are responsible for complying with the laws and regulations of their own
  jurisdiction, and for the licensing of any media they access.
- No warranty of any kind. Use at your own risk.

## Credits

The extension format Mimasu is compatible with was designed by
[Aniyomi](https://github.com/aniyomiorg/aniyomi), itself a fork of
[Tachiyomi](https://github.com/tachiyomiorg/tachiyomi) and a sibling of
[Mihon](https://github.com/mihonapp/mihon). Those projects pioneered this approach.
Mimasu reproduces the extension API surface for compatibility and shares no implementation
code with any of them. See [`NOTICE`](NOTICE) for attribution.
