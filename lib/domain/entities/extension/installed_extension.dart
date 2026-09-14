/// Entities for extensions that are installed, or about to be.
library;

/// Where an extension's signing key stands with the user.
enum TrustState {
  /// The key is on the user's trusted list.
  trusted,

  /// Installed, but signed by a key the user has not approved. The source must
  /// not be loaded in this state (INSTRUCTIONS.md §5.5).
  untrusted,
}

/// An extension package present on the device.
class InstalledExtension {
  const InstalledExtension({
    required this.packageName,
    required this.label,
    required this.versionName,
    required this.versionCode,
    required this.signatureSha256,
    required this.trust,
    required this.isAnime,
    this.libVersion,
    this.sourceClasses = const [],
  });

  final String packageName;
  final String label;
  final String versionName;
  final int versionCode;

  /// Lowercase hex, comparable against a repository's declared key.
  final String signatureSha256;

  final TrustState trust;

  /// Manga extensions can be installed by the user independently of Mimasu;
  /// they are listed but never loaded.
  final bool isAnime;

  final String? libVersion;

  /// Declared in `…extension.class`, possibly relative to the package.
  final List<String> sourceClasses;

  bool get isUsable => trust == TrustState.trusted && isAnime;

  String get shortKey => signatureSha256.length < 12
      ? signatureSha256
      : '${signatureSha256.substring(0, 8)}…'
            '${signatureSha256.substring(signatureSha256.length - 4)}';
}

/// An APK downloaded and inspected, waiting on the user's decision.
class PendingInstall {
  const PendingInstall({
    required this.filePath,
    required this.packageName,
    required this.label,
    required this.versionName,
    required this.signatureSha256,
    required this.repositoryUrl,
    required this.keyIsTrusted,
    required this.declaredKeyMatches,
  });

  final String filePath;
  final String packageName;
  final String label;
  final String versionName;
  final String signatureSha256;
  final String repositoryUrl;

  /// The user has already trusted this key for another extension.
  final bool keyIsTrusted;

  /// The APK's actual key matches the one the repository index declared.
  ///
  /// A mismatch is worth showing prominently: it means the file did not come
  /// from who the index says it did. Null when the index declared no key.
  final bool? declaredKeyMatches;

  /// Whether the user must be asked before this can be installed (§5.5).
  bool get needsPrompt => !keyIsTrusted;

  String get shortKey => signatureSha256.length < 12
      ? signatureSha256
      : '${signatureSha256.substring(0, 8)}…'
            '${signatureSha256.substring(signatureSha256.length - 4)}';
}
