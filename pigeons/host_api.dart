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
