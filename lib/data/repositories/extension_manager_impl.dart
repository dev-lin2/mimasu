import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/extension/extension_repo_index.dart';
import '../../domain/entities/extension/installed_extension.dart';
import '../../domain/repositories/extension_manager.dart';
import '../../extensions/host/host_api.g.dart';
import '../storage/trust_store.dart';

/// Metadata keys an extension declares. Confirmed on device — see
/// `docs/phase-0-findings.md`. Anime and manga use different prefixes, which
/// is also how the two are told apart.
abstract final class ExtensionMetaKeys {
  static const animeFeature = 'tachiyomi.animeextension';
  static const mangaFeature = 'tachiyomi.extension';

  static const animeClass = 'tachiyomi.animeextension.class';
  static const mangaClass = 'tachiyomi.extension.class';

  /// Added by one repository's build tooling, not upstream, so optional.
  static const libVersion = 'tachiyomix.extensionLib';
}

class ExtensionManagerImpl implements ExtensionManager {
  ExtensionManagerImpl({
    required TrustStore trustStore,
    ExtensionHostApi? host,
    Dio? dio,
  }) : _trust = trustStore,
       _host = host ?? ExtensionHostApi(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(minutes: 2),
               followRedirects: true,
               maxRedirects: 5,
             ),
           );

  final TrustStore _trust;
  final ExtensionHostApi _host;
  final Dio _dio;

  @override
  Future<bool> canInstall() => _host.canInstallPackages();

  @override
  Future<List<InstalledExtension>> installed() async {
    final candidates = await _host.scanForExtensions(const [
      ExtensionMetaKeys.animeFeature,
      ExtensionMetaKeys.mangaFeature,
    ]);
    final trusted = await _trust.trustedKeys();

    final out = <InstalledExtension>[];
    for (final c in candidates) {
      if (c == null) continue;
      final features = c.features.whereType<String>().toSet();
      final isAnime = features.contains(ExtensionMetaKeys.animeFeature) ||
          c.packageName.contains('.animeextension.');

      final classValue = c.metadata[ExtensionMetaKeys.animeClass] ??
          c.metadata[ExtensionMetaKeys.mangaClass];

      // Fingerprints arrive colon-separated and uppercase from the host's
      // scan; the trust store and repository indexes both use bare lowercase.
      final key = c.signatureSha256.replaceAll(':', '').toLowerCase();

      out.add(
        InstalledExtension(
          packageName: c.packageName,
          label: c.label,
          versionName: c.versionName,
          versionCode: c.versionCode,
          signatureSha256: key,
          trust: trusted.contains(key)
              ? TrustState.trusted
              : TrustState.untrusted,
          isAnime: isAnime,
          libVersion: c.metadata[ExtensionMetaKeys.libVersion],
          sourceClasses: (classValue ?? '')
              .split(';')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
        ),
      );
    }
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  @override
  Future<PendingInstall> beginInstall(
    ExtensionEntry entry, {
    required String repositoryUrl,
    String? declaredRepoKey,
  }) async {
    if (!await canInstall()) {
      throw const InstallFailure(
        InstallFailureKind.permissionMissing,
        'Android has not been allowed to install apps from Mimasu yet.',
      );
    }

    final url = entry.apkUrl;
    if (url == null || url.isEmpty) {
      throw const InstallFailure(
        InstallFailureKind.noApkUrl,
        'The repository listed no APK for this extension.',
      );
    }

    final file = await _download(url, entry.packageName);
    final info = await _host.inspectApk(file.path);
    if (!info.ok) {
      await _discard(file);
      throw InstallFailure(
        InstallFailureKind.notAnApk,
        'That download is not a readable APK. ${info.error ?? ''}'.trim(),
      );
    }

    final features = info.features.whereType<String>().toSet();
    final isAnime = features.contains(ExtensionMetaKeys.animeFeature) ||
        info.packageName.contains('.animeextension.');
    if (!isAnime) {
      await _discard(file);
      throw const InstallFailure(
        InstallFailureKind.wrongKind,
        'That is not an anime extension. Mimasu plays video only.',
      );
    }

    final key = info.signatureSha256.toLowerCase();
    final declared = declaredRepoKey?.toLowerCase();

    return PendingInstall(
      filePath: file.path,
      packageName: info.packageName,
      label: info.label.isEmpty ? entry.name : info.label,
      versionName: info.versionName,
      signatureSha256: key,
      repositoryUrl: repositoryUrl,
      keyIsTrusted: await _trust.isTrusted(key),
      declaredKeyMatches: (declared == null || declared.isEmpty)
          ? null
          : declared == key,
    );
  }

  @override
  Future<void> trustKey(String sha256) => _trust.trust(sha256);

  @override
  Future<void> completeInstall(PendingInstall pending) async {
    final launched = await _host.installApk(pending.filePath);
    if (!launched) {
      throw const InstallFailure(
        InstallFailureKind.installerUnavailable,
        "Android's package installer could not be opened.",
      );
    }
  }

  @override
  Future<void> remove(String packageName) async {
    await _host.uninstallPackage(packageName);
  }

  /// Downloads into the cache directory shared with the package installer by
  /// the FileProvider — the installer cannot read an arbitrary path.
  Future<File> _download(String url, String packageName) async {
    final dir = Directory(
      '${(await getApplicationCacheDirectory()).path}/extensions',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}/$packageName.apk');

    try {
      await _dio.download(url, file.path);
    } catch (e) {
      await _discard(file);
      throw InstallFailure(
        InstallFailureKind.downloadFailed,
        'Could not download the extension from $url.',
      );
    }
    if (!file.existsSync() || file.lengthSync() == 0) {
      throw const InstallFailure(
        InstallFailureKind.downloadFailed,
        'The download finished but produced no file.',
      );
    }
    return file;
  }

  Future<void> _discard(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // A leftover file in the cache is harmless.
    }
  }
}
