/// Repository index parsing (INSTRUCTIONS.md section 6).
///
/// Two formats are supported behind one entry point, selected by sniffing the
/// payload rather than trusting the filename — a URL ending in `.json` can
/// serve protobuf and vice versa.
library;

import 'dart:convert';
import 'dart:io';

import '../../domain/entities/extension/extension_repo_index.dart';
import 'protobuf_reader.dart';

/// Raised only when a payload is not a repository index in any supported
/// format. Individual entries that cannot be installed are values, not
/// exceptions (section 6.4).
class RepoIndexException implements Exception {
  RepoIndexException(this.message);
  final String message;
  @override
  String toString() => 'RepoIndexException: $message';
}

/// `extensions-lib` major versions this build can host.
///
/// VERIFY: the observed values in a manga repository were "1.4" and "1.6". The
/// anime-side range is unknown until Phase 0 completes against a real anime
/// extension, so nothing is refused on this basis yet — see
/// [ExtensionEntry.libVersion].
const supportedLibMajors = <int>{1};

class RepoIndexParser {
  const RepoIndexParser();

  /// Parses [payload], transparently inflating gzip.
  ///
  /// [baseUrl] is the URL the payload came from, used to resolve relative APK
  /// filenames in the JSON format.
  ExtensionRepoIndex parse(List<int> payload, {String? baseUrl}) {
    if (payload.isEmpty) throw RepoIndexException('empty payload');

    final bytes = _isGzip(payload) ? _inflate(payload) : payload;
    return switch (_sniff(bytes)) {
      RepoIndexFormat.json => _parseJson(bytes, baseUrl),
      RepoIndexFormat.protobuf => _parseProtobuf(bytes),
    };
  }

  static bool _isGzip(List<int> b) =>
      b.length > 2 && b[0] == 0x1F && b[1] == 0x8B;

  List<int> _inflate(List<int> b) {
    try {
      return gzip.decode(b);
    } catch (e) {
      throw RepoIndexException('gzip payload could not be inflated: $e');
    }
  }

  /// JSON indexes are a bare array; anything else is treated as protobuf.
  RepoIndexFormat _sniff(List<int> bytes) {
    for (final byte in bytes.take(64)) {
      if (byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D) {
        continue;
      }
      return (byte == 0x5B || byte == 0x7B)
          ? RepoIndexFormat.json
          : RepoIndexFormat.protobuf;
    }
    throw RepoIndexException('payload is entirely whitespace');
  }

  // ---------------------------------------------------------------- json

  ExtensionRepoIndex _parseJson(List<int> bytes, String? baseUrl) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (e) {
      throw RepoIndexException('not valid JSON: $e');
    }
    if (decoded is! List) {
      throw RepoIndexException(
        'expected a JSON array of extensions, got ${decoded.runtimeType}',
      );
    }

    final entries = <ExtensionEntry>[];
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final pkg = raw['pkg'];
      final name = raw['name'];
      if (pkg is! String || name is! String) continue;

      final apk = raw['apk'];
      entries.add(
        _classify(
          ExtensionEntry(
            name: name,
            packageName: pkg,
            versionName: raw['version'] as String? ?? '',
            versionCode: (raw['code'] as num?)?.toInt() ?? 0,
            mediaKind: ExtensionMediaKind.fromPackage(pkg),
            libVersion: null,
            apkUrl: apk is String ? _resolve(apk, baseUrl) : null,
            contentRating: (raw['nsfw'] as num?)?.toInt(),
            sources: _jsonSources(raw['sources']),
          ),
        ),
      );
    }
    return ExtensionRepoIndex(
      format: RepoIndexFormat.json,
      extensions: entries,
    );
  }

  List<ExtensionSourceInfo> _jsonSources(Object? raw) {
    if (raw is! List) return const [];
    final out = <ExtensionSourceInfo>[];
    for (final s in raw) {
      if (s is! Map) continue;
      out.add(
        ExtensionSourceInfo(
          id: '${s['id'] ?? ''}',
          name: s['name'] as String? ?? '',
          lang: s['lang'] as String? ?? '',
          baseUrl: s['baseUrl'] as String? ?? '',
        ),
      );
    }
    return out;
  }

  /// JSON indexes give a bare APK filename relative to the index URL.
  String _resolve(String apk, String? baseUrl) {
    if (apk.startsWith('http://') || apk.startsWith('https://')) return apk;
    if (baseUrl == null) return apk;
    final cut = baseUrl.lastIndexOf('/');
    return cut < 0 ? apk : '${baseUrl.substring(0, cut + 1)}$apk';
  }

  // ------------------------------------------------------------ protobuf

  // Field numbers recovered by walking a real payload; see
  // extension-format/schema/index-pb.md for how, and for the evidence.
  static const _fRepoName = 1;
  static const _fRepoShortName = 2;
  static const _fRepoSigningKey = 3;
  static const _fRepoLinks = 4;
  static const _fLinkWebsite = 1;
  static const _fLinkSocial = 2;
  static const _fCatalog = 101;
  static const _fCatalogEntry = 1;

  static const _fExtName = 1;
  static const _fExtPackage = 2;
  static const _fExtArtifacts = 3;
  static const _fExtLibVersion = 4;
  static const _fExtVersionCode = 5;
  static const _fExtVersionName = 6;
  static const _fExtContentRating = 7;
  static const _fExtSource = 8;

  static const _fArtifactApk = 1;
  static const _fArtifactIcon = 2;
  static const _fArtifactJar = 501;

  static const _fSourceId = 1;
  static const _fSourceName = 2;
  static const _fSourceLang = 3;
  static const _fSourceBaseUrl = 4;
  static const _fSourceAltBaseUrl = 5;

  ExtensionRepoIndex _parseProtobuf(List<int> bytes) {
    final List<WireField> root;
    try {
      root = readMessage(bytes);
    } catch (e) {
      throw RepoIndexException('not a decodable protobuf index: $e');
    }

    final links = root.bytesOf(_fRepoLinks);
    final linkFields = links == null ? const <WireField>[] : readMessage(links);

    final catalog = root.bytesOf(_fCatalog);
    final entries = <ExtensionEntry>[];
    if (catalog != null) {
      for (final raw in readMessage(catalog).allBytesOf(_fCatalogEntry)) {
        final entry = _protobufEntry(raw);
        if (entry != null) entries.add(entry);
      }
    }

    return ExtensionRepoIndex(
      format: RepoIndexFormat.protobuf,
      name: _str(root.bytesOf(_fRepoName)),
      shortName: _str(root.bytesOf(_fRepoShortName)),
      signingKeySha256: _str(root.bytesOf(_fRepoSigningKey)),
      website: _str(linkFields.bytesOf(_fLinkWebsite)),
      social: _str(linkFields.bytesOf(_fLinkSocial)),
      extensions: entries,
    );
  }

  ExtensionEntry? _protobufEntry(List<int> raw) {
    final List<WireField> f;
    try {
      f = readMessage(raw);
    } catch (_) {
      // A single corrupt entry must not fail the index (section 6.4).
      return null;
    }

    final pkg = _str(f.bytesOf(_fExtPackage));
    final name = _str(f.bytesOf(_fExtName));
    if (pkg == null || name == null) return null;

    final artifactBytes = f.bytesOf(_fExtArtifacts);
    final artifacts = artifactBytes == null
        ? const <WireField>[]
        : readMessage(artifactBytes);

    final sources = <ExtensionSourceInfo>[];
    for (final s in f.allBytesOf(_fExtSource)) {
      final sf = readMessage(s);
      sources.add(
        ExtensionSourceInfo(
          id: '${sf.intOf(_fSourceId) ?? ''}',
          name: _str(sf.bytesOf(_fSourceName)) ?? '',
          lang: _str(sf.bytesOf(_fSourceLang)) ?? '',
          baseUrl: _str(sf.bytesOf(_fSourceBaseUrl)) ?? '',
          altBaseUrl: _str(sf.bytesOf(_fSourceAltBaseUrl)),
        ),
      );
    }

    return _classify(
      ExtensionEntry(
        name: name,
        packageName: pkg,
        versionName: _str(f.bytesOf(_fExtVersionName)) ?? '',
        versionCode: f.intOf(_fExtVersionCode) ?? 0,
        mediaKind: ExtensionMediaKind.fromPackage(pkg),
        libVersion: _str(f.bytesOf(_fExtLibVersion)),
        apkUrl: _str(artifacts.bytesOf(_fArtifactApk)),
        iconUrl: _str(artifacts.bytesOf(_fArtifactIcon)),
        jarUrl: _str(artifacts.bytesOf(_fArtifactJar)),
        contentRating: f.intOf(_fExtContentRating),
        sources: sources,
      ),
    );
  }

  static String? _str(List<int>? bytes) {
    if (bytes == null) return null;
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------- shared

  /// Decides whether an entry is installable, and if not, why. The reason is
  /// user-facing (section 6.4).
  ExtensionEntry _classify(ExtensionEntry e) {
    final reason = switch (e) {
      _ when e.mediaKind == ExtensionMediaKind.manga =>
        'Manga extension. Mimasu plays video only.',
      _ when e.mediaKind == ExtensionMediaKind.unknown =>
        'Unrecognised extension package.',
      _ when e.apkUrl == null || e.apkUrl!.isEmpty =>
        'The repository listed no APK for this extension.',
      _ when !_libSupported(e.libVersion) =>
        'Needs extensions-lib ${e.libVersion}, which this build does not host.',
      _ => null,
    };
    if (reason == null) return e;
    return ExtensionEntry(
      name: e.name,
      packageName: e.packageName,
      versionName: e.versionName,
      versionCode: e.versionCode,
      mediaKind: e.mediaKind,
      sources: e.sources,
      libVersion: e.libVersion,
      apkUrl: e.apkUrl,
      iconUrl: e.iconUrl,
      jarUrl: e.jarUrl,
      contentRating: e.contentRating,
      unsupportedReason: reason,
    );
  }

  /// An absent lib version is not grounds for refusal — the JSON format never
  /// carries one.
  bool _libSupported(String? libVersion) {
    if (libVersion == null || libVersion.isEmpty) return true;
    final major = int.tryParse(libVersion.split('.').first);
    return major == null || supportedLibMajors.contains(major);
  }
}
