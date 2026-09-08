import 'extension_repo_index.dart';

/// A repository the user has added. Mimasu ships none (INSTRUCTIONS.md section 6).
///
/// [url] is the resolved index URL, not necessarily what the user typed — see
/// `RepoUrlResolver`.
class ExtensionRepo {
  const ExtensionRepo({
    required this.url,
    required this.enteredUrl,
    required this.format,
    required this.extensionCount,
    required this.supportedCount,
    required this.fetchedAt,
    this.name,
    this.shortName,
    this.signingKeySha256,
    this.website,
  });

  /// The URL the index was actually read from.
  final String url;

  /// What the user pasted, kept so the UI can show it back to them and so a
  /// refresh can re-resolve if a repository changes format.
  final String enteredUrl;

  final RepoIndexFormat format;
  final int extensionCount;

  /// How many entries Mimasu could actually install. For a manga repository
  /// this is zero, which is a legitimate state to display.
  final int supportedCount;

  final DateTime fetchedAt;
  final String? name;
  final String? shortName;

  /// The key the repository claims to sign with. A convenience for the trust
  /// prompt, never a substitute for fingerprinting the APK (section 5.5).
  final String? signingKeySha256;

  final String? website;

  /// Repositories are identified by their resolved URL; adding the same one
  /// twice replaces rather than duplicates.
  String get id => url;

  /// A repository whose index parsed but offers nothing installable. Worth
  /// distinguishing from an empty repository in the UI.
  bool get hasNothingInstallable => extensionCount > 0 && supportedCount == 0;

  String get displayName => name?.trim().isNotEmpty == true ? name! : url;

  Map<String, dynamic> toJson() => {
    'url': url,
    'enteredUrl': enteredUrl,
    'format': format.name,
    'extensionCount': extensionCount,
    'supportedCount': supportedCount,
    'fetchedAt': fetchedAt.toIso8601String(),
    'name': name,
    'shortName': shortName,
    'signingKeySha256': signingKeySha256,
    'website': website,
  };

  /// Returns null rather than throwing on a malformed record: a corrupt
  /// persisted entry must not stop the app from starting.
  static ExtensionRepo? fromJson(Map<dynamic, dynamic> json) {
    final url = json['url'];
    if (url is! String || url.isEmpty) return null;
    return ExtensionRepo(
      url: url,
      enteredUrl: json['enteredUrl'] as String? ?? url,
      format: RepoIndexFormat.values.firstWhere(
        (f) => f.name == json['format'],
        orElse: () => RepoIndexFormat.json,
      ),
      extensionCount: (json['extensionCount'] as num?)?.toInt() ?? 0,
      supportedCount: (json['supportedCount'] as num?)?.toInt() ?? 0,
      fetchedAt:
          DateTime.tryParse(json['fetchedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      name: json['name'] as String?,
      shortName: json['shortName'] as String?,
      signingKeySha256: json['signingKeySha256'] as String?,
      website: json['website'] as String?,
    );
  }

  static ExtensionRepo fromIndex({
    required String url,
    required String enteredUrl,
    required ExtensionRepoIndex index,
    required DateTime fetchedAt,
  }) => ExtensionRepo(
    url: url,
    enteredUrl: enteredUrl,
    format: index.format,
    extensionCount: index.extensions.length,
    supportedCount: index.supported.length,
    fetchedAt: fetchedAt,
    name: index.name,
    shortName: index.shortName,
    signingKeySha256: index.signingKeySha256,
    website: index.website,
  );
}
