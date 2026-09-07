<p align="center">
  <h1 align="center">Mimasu</h1>
</p>

<p align="center">An Android anime app that ships no content.</p>

---

## What this is

Mimasu is an **extension host**. It provides the app — browsing, your library, the video
player, AniList sync — and nothing else. It contains no content, no scrapers, and no list
of places to get either.

On a fresh install, Mimasu can show you public anime metadata from AniList and that is all.
To play anything, you install a JavaScript extension yourself by pasting in the URL of a
repository you choose. The project does not host, bundle, curate, or link to any content
source.

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
via repository secrets — see §11 of [`INSTRUCTIONS.md`](INSTRUCTIONS.md). Note that switching
keystores breaks in-place upgrades.

### Building locally

Requires the Flutter SDK (version pinned in `.fvmrc`), the Android SDK, and **JDK 17 or 21**
— newer JDKs are not supported by Flutter's Gradle toolchain.

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --split-per-abi
```

## How extensions work

An extension is a single JavaScript file that knows how to read one website. It runs in a
sandboxed QuickJS interpreter inside the app and **cannot open network connections, read
files, or import anything**. Instead it calls a small bridge the app provides — fetch this
URL, parse this HTML, read this CSS selector — so every request an extension makes goes
through the app, where it is logged and visible to you.

An extension implements a fixed contract:

```js
mimasu.register({
  metadata: { id, name, lang, baseUrl, apiVersion },
  async getPopular(page)          { /* ... */ },
  async search(query, page)       { /* ... */ },
  async getDetail(url)            { /* ... */ },
  async getEpisodeList(url)       { /* ... */ },
  async getVideoList(episodeUrl)  { /* ... */ },
});
```

Extensions are fetched from a repository — a JSON index at a URL you supply — and verified
against a SHA-256 digest before they are ever executed.

**Writing your own:** see [`extensions-spec/README.md`](extensions-spec/README.md) for the
full contract and bridge API, and `extensions-spec/example/` for a complete working
extension. The example runs against local test fixtures rather than any real website, so
you can develop and test an extension offline.

**Finding extensions:** that is up to you. This project does not maintain or recommend a
directory of repositories. What you point the app at, and whether doing so is lawful where
you live, is your responsibility. Requests to add specific content sources will be closed —
the extension format is public precisely so that nobody has to ask.

## Contributing

Bug reports and pull requests are welcome. [`INSTRUCTIONS.md`](INSTRUCTIONS.md) has the
architecture and the build specification.

## Disclaimer

- Mimasu contains no content and provides no means of obtaining any. It is a client
  application with a documented plugin interface.
- The developers of Mimasu are not responsible for any content accessed through
  third-party extensions, nor for the extensions themselves, and have no control over what
  any extension does or where it connects.
- Users are responsible for complying with the laws and regulations of their own
  jurisdiction, and for the licensing of any media they access.
- No warranty of any kind. Use at your own risk.

## Credits

Metadata is provided by [AniList](https://anilist.co).

The extension model is inspired by [Aniyomi](https://github.com/aniyomiorg/aniyomi) and
[Mangayomi](https://github.com/kodjodevf/mangayomi), which pioneered this approach. No code
is shared with either.
