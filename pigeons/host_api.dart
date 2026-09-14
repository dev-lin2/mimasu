import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/extensions/host/host_api.g.dart',
    kotlinOut:
        'android/app/src/main/kotlin/com/handypick/mimasu/host/HostApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.handypick.mimasu.host'),
    dartPackageName: 'mimasu',
  ),
)
/// Basic environment facts, used to prove the channel round-trips before any
/// extension work is attempted.
class HostInfo {
  HostInfo({
    required this.androidRelease,
    required this.sdkInt,
    required this.hostPackage,
    required this.canRequestPackageInstalls,
  });

  final String androidRelease;
  final int sdkInt;
  final String hostPackage;

  /// Whether the user has granted "install unknown apps" for this app.
  /// Extension installs (INSTRUCTIONS.md 5.4) are impossible until this is true.
  final bool canRequestPackageInstalls;
}

/// An installed package that looks like it might be a Tachiyomi-family
/// extension. Deliberately unopinionated: the scan does not assume a feature
/// name or metadata key, it reports whatever the package actually declares so
/// the real values can be read off a device instead of guessed.
class ExtensionCandidate {
  ExtensionCandidate({
    required this.packageName,
    required this.label,
    required this.versionName,
    required this.versionCode,
    required this.apkPath,
    required this.features,
    required this.metadata,
    required this.signatureSha256,
  });

  final String packageName;
  final String label;
  final String versionName;
  final int versionCode;

  /// Absolute path of the installed APK, the input to PathClassLoader.
  final String apkPath;

  /// Every feature name the package declares in its manifest.
  final List<String?> features;

  /// Every application-level manifest metadata entry, stringified.
  final Map<String?, String?> metadata;

  /// SHA-256 of the signing certificate, uppercase hex, colon-separated.
  final String signatureSha256;
}

/// One title as an extension reported it.
class FetchedAnime {
  FetchedAnime({
    required this.title,
    required this.url,
    required this.thumbnailUrl,
    required this.description,
  });

  final String title;
  final String url;
  final String? thumbnailUrl;
  final String? description;
}

/// The outcome of asking a source for a page of titles.
class FetchResult {
  FetchResult({
    required this.ok,
    required this.sourceName,
    required this.items,
    required this.hasNextPage,
    required this.millis,
    required this.error,
  });

  final bool ok;
  final String sourceName;
  final List<FetchedAnime?> items;
  final bool hasNextPage;
  final int millis;
  final String? error;
}

/// What an APK on disk declares about itself, read before installing.
class ApkInfo {
  ApkInfo({
    required this.ok,
    required this.packageName,
    required this.label,
    required this.versionName,
    required this.versionCode,
    required this.signatureSha256,
    required this.features,
    required this.metadata,
    required this.error,
  });

  final bool ok;
  final String packageName;
  final String label;
  final String versionName;
  final int versionCode;

  /// Lowercase hex, no separators, so it compares directly against the key a
  /// repository index declares.
  final String signatureSha256;

  final List<String?> features;
  final Map<String?, String?> metadata;
  final String? error;
}

/// A source instance the host managed to load, interrogated through the
/// shim interfaces.
class LoadedSource {
  LoadedSource({
    required this.className,
    required this.ok,
    required this.sourceId,
    required this.name,
    required this.lang,
    required this.baseUrl,
    required this.supportsLatest,
    required this.configurable,
    required this.filterCount,
    required this.error,
  });

  final String className;
  final bool ok;

  /// 64-bit, so carried as a string.
  final String sourceId;
  final String name;
  final String lang;
  final String baseUrl;
  final bool supportsLatest;
  final bool configurable;

  /// How many filters the source declares for its search UI.
  final int filterCount;
  final String? error;
}

/// The result of attempting to load one class out of an extension APK.
/// Failures are values, not exceptions (INSTRUCTIONS.md 5.8).
class ClassProbeResult {
  ClassProbeResult({
    required this.className,
    required this.loaded,
    required this.instantiated,
    required this.superclasses,
    required this.error,
  });

  final String className;

  /// Class.forName succeeded.
  final bool loaded;

  /// A no-arg instance was constructed. Usually false until the
  /// extensions-lib shim is present.
  final bool instantiated;

  /// The class's ancestry and interfaces, which is how we discover the exact
  /// extensions-lib type names an extension expects the host to provide.
  final List<String?> superclasses;

  /// Null when nothing went wrong.
  final String? error;
}

@HostApi()
abstract class ExtensionHostApi {
  HostInfo getHostInfo();

  /// Scans installed packages and returns any whose declared features or
  /// metadata keys contain one of [needles] (case-insensitive).
  /// Pass something like ["tachiyomi", "aniyomi", "extension"].
  List<ExtensionCandidate?> scanForExtensions(List<String?> needles);

  /// Whether the user has granted "install unknown apps" for this app.
  /// Checked live rather than cached: the user can revoke it at any time.
  bool canInstallPackages();

  /// Opens the system settings page where that grant is made. Returns false
  /// if no such screen could be launched.
  bool openInstallPermissionSettings();

  /// What a successfully loaded source reports about itself. Proves the host
  /// can talk to an extension through the shim, not merely construct it.
  List<LoadedSource?> loadSources(String packageName, List<String?> classNames);

  /// Calls a loaded source for real: one page of popular titles.
  ///
  /// Async because Pigeon dispatches host calls on the platform main
  /// thread, and Android throws NetworkOnMainThreadException for network
  /// work there. Confirmed the hard way.
  @async
  FetchResult fetchPopular(String packageName, String className, int page);

  /// Performs a plain GET through the same OkHttp client extensions are
  /// given. Distinguishes "the shim is broken" from "this device does not
  /// trust that site" — the only question a TLS failure leaves open.
  @async
  String hostHttpCheck(String url);

  /// Reads an APK on disk without installing it: package, version, signing
  /// key and manifest metadata. This is what the trust prompt is built from
  /// (INSTRUCTIONS.md 5.5) — the key must be checked BEFORE install.
  ApkInfo inspectApk(String filePath);

  /// Hands the APK to the system package installer. Returns false if no
  /// installer could be launched. Android, not Mimasu, performs the install
  /// and shows its own confirmation.
  bool installApk(String filePath);

  /// Launches the system uninstall prompt for an installed extension.
  bool uninstallPackage(String packageName);

  /// Hosts an extension has contacted through the client the host provides.
  /// Best-effort: an extension using its own client is not covered (5.7).
  Map<String?, int?> requestLogHostCounts();

  /// Builds a PathClassLoader over [packageName]'s APK and tries to load each
  /// of [classNames], reporting ancestry and errors rather than throwing.
  List<ClassProbeResult?> probeClasses(
    String packageName,
    List<String?> classNames,
  );
}

// --- Browsing through a loaded source (INSTRUCTIONS.md section 5, Phase 2) ---

/// One title as a source reported it. Only what `SAnime` carries: there is no
/// metadata service underneath, so this is all the app will ever know.
class AnimeItem {
  AnimeItem({
    required this.url,
    required this.title,
    required this.thumbnailUrl,
    required this.description,
    required this.author,
    required this.genre,
    required this.status,
  });

  final String url;
  final String title;
  final String? thumbnailUrl;
  final String? description;
  final String? author;
  final String? genre;

  /// SAnime's status constants: 0 unknown, 1 ongoing, 2 completed, and so on.
  final int status;
}

class EpisodeItem {
  EpisodeItem({
    required this.url,
    required this.name,
    required this.episodeNumber,
    required this.dateUpload,
    required this.scanlator,
  });

  final String url;
  final String name;
  final double episodeNumber;

  /// Epoch millis, 0 when the source did not say.
  final int dateUpload;
  final String? scanlator;
}

/// A playable stream. [headers] matters: many sources 403 without a Referer,
/// and section 8 requires passing them to the player.
class VideoItem {
  VideoItem({
    required this.url,
    required this.videoUrl,
    required this.quality,
    required this.headers,
    required this.subtitleUrls,
    required this.audioUrls,
  });

  final String url;
  final String? videoUrl;
  final String quality;
  final Map<String?, String?> headers;
  final List<String?> subtitleUrls;
  final List<String?> audioUrls;
}

/// How the catalogue is being asked for.
enum BrowseMode { popular, latest, search }

class BrowseResult {
  BrowseResult({
    required this.ok,
    required this.sourceName,
    required this.items,
    required this.hasNextPage,
    required this.millis,
    required this.error,
  });

  final bool ok;
  final String sourceName;
  final List<AnimeItem?> items;
  final bool hasNextPage;
  final int millis;
  final String? error;
}

class DetailsResult {
  DetailsResult({required this.ok, required this.anime, required this.error});
  final bool ok;
  final AnimeItem? anime;
  final String? error;
}

class EpisodesResult {
  EpisodesResult({required this.ok, required this.items, required this.error});
  final bool ok;
  final List<EpisodeItem?> items;
  final String? error;
}

class VideosResult {
  VideosResult({required this.ok, required this.items, required this.error});
  final bool ok;
  final List<VideoItem?> items;
  final String? error;
}

/// Browsing and playback through a loaded source.
///
/// Every method is async: extension code performs network work, which Android
/// refuses on the platform thread that Pigeon dispatches host calls on.
@HostApi()
abstract class SourceApi {
  /// One page of titles. [query] is ignored unless [mode] is search.
  @async
  BrowseResult browse(
    String packageName,
    String className,
    BrowseMode mode,
    int page,
    String query,
  );

  @async
  DetailsResult animeDetails(
    String packageName,
    String className,
    String animeUrl,
  );

  @async
  EpisodesResult episodes(
    String packageName,
    String className,
    String animeUrl,
  );

  @async
  VideosResult videos(
    String packageName,
    String className,
    String episodeUrl,
  );

  /// Drops cached source instances, e.g. after an extension is updated.
  void clearSourceCache();
}
