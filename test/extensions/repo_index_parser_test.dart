import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimasu/domain/entities/extension/extension_repo_index.dart';
import 'package:mimasu/extensions/repo/repo_index_parser.dart';

/// Fixtures are real payloads fetched from a live repository, committed so the
/// suite never touches the network (INSTRUCTIONS.md section 16).
List<int> _fixture(String name) =>
    File('test/extensions/fixtures/$name').readAsBytesSync();

void main() {
  const parser = RepoIndexParser();

  group('format sniffing', () {
    test('detects JSON regardless of leading whitespace', () {
      final index = parser.parse(utf8.encode('\n\t  []'));
      expect(index.format, RepoIndexFormat.json);
      expect(index.extensions, isEmpty);
    });

    test('inflates gzip transparently', () {
      final index = parser.parse(_fixture('keiyoushi_index.pb.gz'));
      expect(index.format, RepoIndexFormat.protobuf);
    });

    test('rejects an empty payload', () {
      expect(() => parser.parse(const []), throwsA(isA<RepoIndexException>()));
    });

    test('rejects whitespace-only payload', () {
      expect(
        () => parser.parse(utf8.encode('   \n  ')),
        throwsA(isA<RepoIndexException>()),
      );
    });

    test('rejects a JSON object where an array is required', () {
      expect(
        () => parser.parse(utf8.encode('{"nope": true}')),
        throwsA(isA<RepoIndexException>()),
      );
    });

    test('rejects undecodable bytes', () {
      // 0xFF is not a valid protobuf field key and not JSON.
      expect(
        () => parser.parse(const [0xFF, 0xFF, 0xFF, 0xFF]),
        throwsA(isA<RepoIndexException>()),
      );
    });

    test('rejects a truncated gzip payload', () {
      final full = _fixture('keiyoushi_index.pb.gz');
      expect(
        () => parser.parse(full.sublist(0, full.length ~/ 2)),
        throwsA(isA<RepoIndexException>()),
      );
    });
  });

  group('json index', () {
    test('parses the real stub index', () {
      final index = parser.parse(
        _fixture('keiyoushi_index.min.json'),
        baseUrl: 'https://example.test/repo/index.min.json',
      );
      expect(index.format, RepoIndexFormat.json);
      expect(index.extensions, hasLength(2));

      final first = index.extensions.first;
      expect(first.name, 'Outdated App');
      expect(first.packageName, 'eu.kanade.tachiyomi.extension.all.keiyoushi');
      expect(first.versionName, '1.4.1');
      expect(first.versionCode, 1);
      expect(first.sources.single.baseUrl, 'https://keiyoushi.github.io');
      expect(first.sources.single.id, '1');
    });

    test('resolves a relative apk filename against the index url', () {
      final index = parser.parse(
        _fixture('keiyoushi_index.min.json'),
        baseUrl: 'https://example.test/repo/index.min.json',
      );
      expect(
        index.extensions.first.apkUrl,
        'https://example.test/repo/tachiyomi-all.keiyoushi-v1.4.1.apk',
      );
    });

    test('leaves an absolute apk url alone', () {
      final index = parser.parse(
        utf8.encode(
          '[{"name":"A","pkg":"x.animeextension.en.a","apk":'
          '"https://cdn.test/a.apk","version":"1.0","code":1,"sources":[]}]',
        ),
        baseUrl: 'https://example.test/repo/index.min.json',
      );
      expect(index.extensions.single.apkUrl, 'https://cdn.test/a.apk');
    });

    test('skips malformed entries without failing the index', () {
      final index = parser.parse(
        utf8.encode(
          '[{"garbage":true},'
          '{"name":"Good","pkg":"x.animeextension.en.good","apk":'
          '"https://cdn.test/g.apk","version":"1.0","code":1,"sources":[]},'
          '"a bare string"]',
        ),
      );
      expect(index.extensions, hasLength(1));
      expect(index.extensions.single.name, 'Good');
    });
  });

  group('protobuf index', () {
    late ExtensionRepoIndex index;

    setUpAll(() {
      index = parser.parse(_fixture('keiyoushi_index.pb.gz'));
    });

    test('reads the repository header', () {
      expect(index.name, 'Keiyoushi');
      expect(index.shortName, 'KEI');
      expect(index.website, 'https://keiyoushi.github.io');
      expect(index.social, 'https://discord.gg/3FbCpdKbdY');
    });

    test('reads the declared signing key as 64 hex characters', () {
      expect(index.signingKeySha256, hasLength(64));
      expect(index.signingKeySha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('carries the full catalogue, unlike the json stub', () {
      // The point of the whole exercise: this repository migrated to protobuf
      // and left the JSON index as a two-entry stub.
      expect(index.extensions.length, greaterThan(1000));
    });

    test('maps every extension field', () {
      final e = index.extensions.firstWhere((e) => e.name == 'AHottie');
      expect(e.packageName, 'eu.kanade.tachiyomi.extension.all.ahottie');
      expect(e.versionName, '1.6.4');
      expect(e.versionCode, 106004);
      expect(e.libVersion, '1.6');
      expect(e.apkUrl, endsWith('.apk'));
      expect(e.iconUrl, contains('ic_launcher.png'));
      expect(e.jarUrl, endsWith('.jar'));
      expect(e.contentRating, isNotNull);
    });

    test('reads repeated sources with int64 ids', () {
      // One extension commonly exposes one source per language.
      final e = index.extensions.firstWhere((e) => e.name == 'Akuma');
      expect(e.sources, hasLength(27));
      expect(
        e.sources.map((s) => s.lang),
        containsAll(['all', 'en', 'id', 'ja', 'zh']),
      );
      // Every source of one extension gets its own distinct id.
      expect(e.sources.map((s) => s.id).toSet(), hasLength(e.sources.length));
      // Protobuf ids are 64-bit; the JSON format quotes much smaller ones.
      expect(e.sources.first.id, matches(RegExp(r'^\d{15,}$')));
    });

    test('single-source extensions parse too', () {
      final e = index.extensions.firstWhere((e) => e.name == 'AHottie');
      expect(e.sources, hasLength(1));
      expect(e.sources.single.baseUrl, 'https://ahottie.top');
    });

    test('every entry has a package name and at least one source', () {
      expect(index.extensions.every((e) => e.packageName.isNotEmpty), isTrue);
      expect(index.extensions.every((e) => e.sources.isNotEmpty), isTrue);
    });
  });

  group('supportability', () {
    test('manga extensions are refused as values, not errors', () {
      final index = parser.parse(_fixture('keiyoushi_index.pb.gz'));
      // This is a manga repository, so nothing in it is installable.
      expect(index.supported, isEmpty);
      expect(index.unsupported.length, index.extensions.length);
      expect(
        index.extensions.first.unsupportedReason,
        contains('video only'),
      );
    });

    test('an anime package with an apk is supported', () {
      final index = parser.parse(
        utf8.encode(
          '[{"name":"A","pkg":"eu.kanade.tachiyomi.animeextension.en.a",'
          '"apk":"https://cdn.test/a.apk","version":"1.0","code":1,'
          '"sources":[]}]',
        ),
      );
      final e = index.extensions.single;
      expect(e.mediaKind, ExtensionMediaKind.anime);
      expect(e.isSupported, isTrue);
      expect(e.unsupportedReason, isNull);
    });

    test('an anime package with no apk is refused', () {
      final index = parser.parse(
        utf8.encode(
          '[{"name":"A","pkg":"eu.kanade.tachiyomi.animeextension.en.a",'
          '"version":"1.0","code":1,"sources":[]}]',
        ),
      );
      expect(index.extensions.single.isSupported, isFalse);
      expect(index.extensions.single.unsupportedReason, contains('no APK'));
    });

    test('an unrecognised package shape is refused', () {
      final index = parser.parse(
        utf8.encode(
          '[{"name":"A","pkg":"com.example.whatever","apk":'
          '"https://cdn.test/a.apk","version":"1.0","code":1,"sources":[]}]',
        ),
      );
      expect(
        index.extensions.single.unsupportedReason,
        contains('Unrecognised'),
      );
    });
  });

  group('media kind inference', () {
    test('discriminates on the package name', () {
      expect(
        ExtensionMediaKind.fromPackage('eu.kanade.tachiyomi.animeextension.en.x'),
        ExtensionMediaKind.anime,
      );
      expect(
        ExtensionMediaKind.fromPackage('eu.kanade.tachiyomi.extension.en.x'),
        ExtensionMediaKind.manga,
      );
      expect(
        ExtensionMediaKind.fromPackage('org.other.thing'),
        ExtensionMediaKind.unknown,
      );
    });
  });
}
