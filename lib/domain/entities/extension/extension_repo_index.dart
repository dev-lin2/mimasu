/// Domain entities for a parsed extension repository index.
///
/// Pure Dart: no Flutter, no platform channels, no wire types
/// (INSTRUCTIONS.md section 3, the one hard rule).
library;

/// Which index format a repository served.
enum RepoIndexFormat { json, protobuf }

/// What kind of content an extension serves. The index carries no media-type
/// field, so this is inferred from the package name — see
/// [ExtensionMediaKind.fromPackage]. Marked VERIFY against a real anime
/// repository (INSTRUCTIONS.md section 6.1).
enum ExtensionMediaKind {
  anime,
  manga,
  unknown;

  static ExtensionMediaKind fromPackage(String packageName) {
    if (packageName.contains('.animeextension.')) return anime;
    if (packageName.contains('.extension.')) return manga;
    return unknown;
  }
}

/// One source exposed by an extension. An extension may expose several,
/// usually one per language.
class ExtensionSourceInfo {
  const ExtensionSourceInfo({
    required this.id,
    required this.name,
    required this.lang,
    required this.baseUrl,
    this.altBaseUrl,
  });

  /// Kept as a string: the JSON format quotes it, the protobuf format uses a
  /// 64-bit integer, and nothing here needs to do arithmetic on it.
  final String id;
  final String name;
  final String lang;
  final String baseUrl;

  /// A second URL some sources carry. In every sampled case it was identical
  /// to [baseUrl]; its purpose is unconfirmed. Protobuf field 8.5.
  final String? altBaseUrl;
}

/// One installable (or refused) extension listed by a repository.
class ExtensionEntry {
  const ExtensionEntry({
    required this.name,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.mediaKind,
    required this.sources,
    this.libVersion,
    this.apkUrl,
    this.iconUrl,
    this.jarUrl,
    this.contentRating,
    this.unsupportedReason,
  });

  final String name;
  final String packageName;
  final String versionName;
  final int versionCode;
  final ExtensionMediaKind mediaKind;
  final List<ExtensionSourceInfo> sources;

  /// The `extensions-lib` version this extension was built against, e.g.
  /// "1.6". The host must provide a compatible shim (section 5.2).
  final String? libVersion;

  /// Absolute URL of the APK to install.
  final String? apkUrl;
  final String? iconUrl;

  /// Some repositories publish a `.jar` alongside the APK. Mimasu does not use
  /// it; recorded because it exists.
  final String? jarUrl;

  /// Raw value of protobuf field 7, a three-valued enum. Observed spread across
  /// 1396 entries was 1:580, 2:430, 3:386, uncorrelated with source or
  /// artifact counts. Both adult extensions sampled carried 3, so this is
  /// almost certainly a content rating with 3 meaning NSFW — but that is a
  /// hypothesis, not a confirmed mapping, so the raw value is kept and no
  /// behaviour depends on it yet.
  final int? contentRating;

  /// Null when the extension can be installed. Non-null values are shown in
  /// the UI as an unsupported entry (section 6.4) — never an error.
  final String? unsupportedReason;

  bool get isSupported => unsupportedReason == null;
}

/// A whole repository index.
class ExtensionRepoIndex {
  const ExtensionRepoIndex({
    required this.format,
    required this.extensions,
    this.name,
    this.shortName,
    this.signingKeySha256,
    this.website,
    this.social,
  });

  final RepoIndexFormat format;
  final List<ExtensionEntry> extensions;

  /// Present in the protobuf format only; the JSON format is a bare array.
  final String? name;
  final String? shortName;

  /// SHA-256 of the key this repository signs its extensions with, lowercase
  /// hex. This is the repository's own declaration, so it is a convenience for
  /// the trust prompt, never a substitute for checking the APK (section 5.5).
  final String? signingKeySha256;

  final String? website;
  final String? social;

  Iterable<ExtensionEntry> get supported => extensions.where((e) => e.isSupported);
  Iterable<ExtensionEntry> get unsupported =>
      extensions.where((e) => !e.isSupported);
}
