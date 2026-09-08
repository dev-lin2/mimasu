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

  /// Builds a PathClassLoader over [packageName]'s APK and tries to load each
  /// of [classNames], reporting ancestry and errors rather than throwing.
  List<ClassProbeResult?> probeClasses(
    String packageName,
    List<String?> classNames,
  );
}
