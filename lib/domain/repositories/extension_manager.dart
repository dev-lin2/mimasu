import '../entities/extension/extension_repo_index.dart';
import '../entities/extension/installed_extension.dart';

/// Why an install could not proceed. Typed so the UI says something specific
/// rather than surfacing an exception (INSTRUCTIONS.md §5.8).
enum InstallFailureKind {
  /// The user has not granted "install unknown apps" yet (§5.4).
  permissionMissing,

  /// The repository listed no APK for this entry.
  noApkUrl,

  /// The download did not complete.
  downloadFailed,

  /// Downloaded, but not a readable APK.
  notAnApk,

  /// The APK is not an anime extension, so Mimasu cannot use it.
  wrongKind,

  /// Android refused to launch its package installer.
  installerUnavailable,
}

class InstallFailure implements Exception {
  const InstallFailure(this.kind, this.message);
  final InstallFailureKind kind;

  /// Already phrased for display.
  final String message;

  @override
  String toString() => 'InstallFailure($kind): $message';
}

/// Installing, trusting and removing extensions (INSTRUCTIONS.md §5.4, §5.5).
///
/// Mimasu never installs silently: [beginInstall] downloads and inspects, and
/// [completeInstall] hands the file to Android, which shows its own prompt.
abstract interface class ExtensionManager {
  /// Extensions present on the device, whether usable or not.
  Future<List<InstalledExtension>> installed();

  /// Downloads [entry]'s APK and reads its signing key, without installing.
  ///
  /// Throws [InstallFailure] and nothing else.
  Future<PendingInstall> beginInstall(
    ExtensionEntry entry, {
    required String repositoryUrl,
    String? declaredRepoKey,
  });

  /// Records the key as trusted. Call only after the user has agreed (§5.5).
  Future<void> trustKey(String sha256);

  /// Hands the downloaded APK to the system installer.
  Future<void> completeInstall(PendingInstall pending);

  /// Launches Android's uninstall prompt.
  Future<void> remove(String packageName);

  /// Whether Android will let Mimasu install packages at all.
  Future<bool> canInstall();
}
