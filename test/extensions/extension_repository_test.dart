import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimasu/application/extensions/extensions_cubit.dart';
import 'package:mimasu/core/services/http/repo_index_fetcher.dart';
import 'package:mimasu/data/repositories/extension_repository_impl.dart';
import 'package:mimasu/data/storage/repo_store.dart';
import 'package:mimasu/domain/entities/extension/extension_repo.dart';
import 'package:mimasu/domain/entities/extension/extension_repo_index.dart';
import 'package:mimasu/domain/repositories/extension_repository.dart';

List<int> _fixture(String name) =>
    File('test/extensions/fixtures/$name').readAsBytesSync();

/// Routes URLs to canned responses; anything unrouted is unreachable, which is
/// what a wrong guess at an index filename looks like in the wild.
class FakeFetcher implements RepoIndexFetcher {
  FakeFetcher(this._routes);
  final Map<String, FetchResult> _routes;
  final requested = <String>[];

  @override
  Future<FetchResult> get(String url) async {
    requested.add(url);
    final route = _routes[url];
    if (route == null) throw const FetchUnreachable('no route in fake');
    return route;
  }
}

FetchResult _ok(List<int> bytes) =>
    FetchResult(statusCode: 200, bytes: bytes);
FetchResult _status(int code) => FetchResult(statusCode: code, bytes: const []);

const _animeJson =
    '[{"name":"Anime One","pkg":"eu.kanade.tachiyomi.animeextension.en.one",'
    '"apk":"one.apk","version":"1.0.0","code":1,"lang":"en","nsfw":0,'
    '"sources":[{"name":"Anime One","lang":"en","id":"7","baseUrl":'
    '"https://one.test"}]}]';

void main() {
  group('RepoUrlResolver', () {
    test('uses a direct .pb url as given', () {
      expect(
        RepoUrlResolver.candidates('https://x.test/repo/index.pb'),
        ['https://x.test/repo/index.pb'],
      );
    });

    test('uses a direct .json url as given', () {
      expect(
        RepoUrlResolver.candidates('https://x.test/repo/index.min.json'),
        ['https://x.test/repo/index.min.json'],
      );
    });

    test('expands a folder url, protobuf first', () {
      // Order matters: section 6.1 records a repository that migrated to
      // protobuf and left the JSON index as a stub, so trying JSON first
      // would find two fake entries and no catalogue.
      expect(RepoUrlResolver.candidates('https://x.test/repo'), [
        'https://x.test/repo/index.pb',
        'https://x.test/repo/index.min.json',
      ]);
    });

    test('tolerates a trailing slash', () {
      expect(
        RepoUrlResolver.candidates('https://x.test/repo/').first,
        'https://x.test/repo/index.pb',
      );
    });

    test('assumes https when no scheme is given', () {
      expect(
        RepoUrlResolver.candidates('x.test/repo/index.pb'),
        ['https://x.test/repo/index.pb'],
      );
    });

    test('rejects unusable input', () {
      expect(RepoUrlResolver.candidates(''), isEmpty);
      expect(RepoUrlResolver.candidates('   '), isEmpty);
      expect(RepoUrlResolver.candidates('not a url'), isEmpty);
      expect(RepoUrlResolver.candidates('ftp://x.test/index.pb'), isEmpty);
    });
  });

  group('ExtensionRepositoryImpl', () {
    ExtensionRepositoryImpl build(
      FakeFetcher fetcher, {
      RepoStore? store,
      DateTime? now,
    }) => ExtensionRepositoryImpl(
      fetcher: fetcher,
      store: store ?? InMemoryRepoStore(),
      clock: () => now ?? DateTime(2026, 9, 8),
    );

    test('adds a protobuf repository and records its metadata', () async {
      final fetcher = FakeFetcher({
        'https://x.test/repo/index.pb': _ok(_fixture('keiyoushi_index.pb.gz')),
      });
      final store = InMemoryRepoStore();
      final repository = build(fetcher, store: store);

      final result = await repository.addRepo('https://x.test/repo/index.pb');

      expect(result.repo.name, 'Keiyoushi');
      expect(result.repo.format, RepoIndexFormat.protobuf);
      expect(result.repo.extensionCount, greaterThan(1000));
      // A manga repository: parsed fine, nothing installable.
      expect(result.repo.supportedCount, 0);
      expect(result.repo.hasNothingInstallable, isTrue);
      expect(await store.load(), hasLength(1));
    });

    test('falls back to the json index when protobuf is absent', () async {
      final fetcher = FakeFetcher({
        'https://x.test/repo/index.pb': _status(404),
        'https://x.test/repo/index.min.json': _ok(utf8.encode(_animeJson)),
      });
      final repository = build(fetcher);

      final result = await repository.addRepo('https://x.test/repo');

      expect(fetcher.requested, [
        'https://x.test/repo/index.pb',
        'https://x.test/repo/index.min.json',
      ]);
      expect(result.repo.format, RepoIndexFormat.json);
      expect(result.repo.supportedCount, 1);
    });

    test('resolves relative apk urls against the index url', () async {
      final fetcher = FakeFetcher({
        'https://x.test/repo/index.min.json': _ok(utf8.encode(_animeJson)),
      });
      final result = await build(
        fetcher,
      ).addRepo('https://x.test/repo/index.min.json');
      expect(
        result.index.extensions.single.apkUrl,
        'https://x.test/repo/one.apk',
      );
    });

    test('reports an unusable url without fetching', () async {
      final fetcher = FakeFetcher(const {});
      await expectLater(
        build(fetcher).addRepo('nonsense'),
        throwsA(
          isA<RepoFailure>().having(
            (f) => f.kind,
            'kind',
            RepoFailureKind.invalidUrl,
          ),
        ),
      );
      expect(fetcher.requested, isEmpty);
    });

    test('reports an unreachable host', () async {
      await expectLater(
        build(FakeFetcher(const {})).addRepo('https://x.test/repo/index.pb'),
        throwsA(
          isA<RepoFailure>().having(
            (f) => f.kind,
            'kind',
            RepoFailureKind.unreachable,
          ),
        ),
      );
    });

    test('reports an http status', () async {
      await expectLater(
        build(
          FakeFetcher({'https://x.test/repo/index.pb': _status(503)}),
        ).addRepo('https://x.test/repo/index.pb'),
        throwsA(
          isA<RepoFailure>()
              .having((f) => f.kind, 'kind', RepoFailureKind.httpError)
              .having((f) => f.statusCode, 'statusCode', 503),
        ),
      );
    });

    test('reports an unreadable payload', () async {
      await expectLater(
        build(
          FakeFetcher({
            'https://x.test/repo/index.pb': _ok(const [0xFF, 0xFF, 0xFF]),
          }),
        ).addRepo('https://x.test/repo/index.pb'),
        throwsA(
          isA<RepoFailure>().having(
            (f) => f.kind,
            'kind',
            RepoFailureKind.unreadable,
          ),
        ),
      );
    });

    test('reports an index that lists nothing', () async {
      await expectLater(
        build(
          FakeFetcher({
            'https://x.test/repo/index.min.json': _ok(utf8.encode('[]')),
          }),
        ).addRepo('https://x.test/repo/index.min.json'),
        throwsA(
          isA<RepoFailure>().having(
            (f) => f.kind,
            'kind',
            RepoFailureKind.emptyIndex,
          ),
        ),
      );
    });

    test('adding the same repository twice replaces rather than duplicates',
        () async {
      final fetcher = FakeFetcher({
        'https://x.test/repo/index.min.json': _ok(utf8.encode(_animeJson)),
      });
      final store = InMemoryRepoStore();
      final repository = build(fetcher, store: store);

      await repository.addRepo('https://x.test/repo/index.min.json');
      await repository.addRepo('https://x.test/repo/index.min.json');

      expect(await store.load(), hasLength(1));
    });

    test('removes a repository', () async {
      final fetcher = FakeFetcher({
        'https://x.test/repo/index.min.json': _ok(utf8.encode(_animeJson)),
      });
      final store = InMemoryRepoStore();
      final repository = build(fetcher, store: store);

      final added = await repository.addRepo(
        'https://x.test/repo/index.min.json',
      );
      await repository.removeRepo(added.repo.id);

      expect(await store.load(), isEmpty);
    });

    test('lists saved repositories most recently fetched first', () async {
      final store = InMemoryRepoStore();
      final fetcherA = FakeFetcher({
        'https://a.test/index.min.json': _ok(utf8.encode(_animeJson)),
      });
      final fetcherB = FakeFetcher({
        'https://b.test/index.min.json': _ok(utf8.encode(_animeJson)),
      });

      await build(
        fetcherA,
        store: store,
        now: DateTime(2026, 1, 1),
      ).addRepo('https://a.test/index.min.json');
      await build(
        fetcherB,
        store: store,
        now: DateTime(2026, 6, 1),
      ).addRepo('https://b.test/index.min.json');

      final saved = await build(fetcherA, store: store).savedRepos();
      expect(saved.map((r) => r.url), [
        'https://b.test/index.min.json',
        'https://a.test/index.min.json',
      ]);
    });

    test('a record missing its url decodes to null rather than throwing',
        () {
      // HiveRepoStore.load drops these, so a record written by an older build
      // cannot stop the app from starting.
      expect(ExtensionRepo.fromJson({'name': 'no url here'}), isNull);
      expect(ExtensionRepo.fromJson({'url': ''}), isNull);
      expect(ExtensionRepo.fromJson({'url': 42}), isNull);
    });

    test('a valid record round-trips through json', () {
      final original = ExtensionRepo(
        url: 'https://x.test/index.pb',
        enteredUrl: 'x.test',
        format: RepoIndexFormat.protobuf,
        extensionCount: 10,
        supportedCount: 3,
        fetchedAt: DateTime.utc(2026, 9, 8, 12),
        name: 'X',
        signingKeySha256: 'abc',
      );
      final restored = ExtensionRepo.fromJson(original.toJson());
      expect(restored, isNotNull);
      expect(restored!.url, original.url);
      expect(restored.format, RepoIndexFormat.protobuf);
      expect(restored.supportedCount, 3);
      expect(restored.fetchedAt, original.fetchedAt);
      expect(restored.signingKeySha256, 'abc');
    });
  });

  group('ExtensionsCubit', () {
    ExtensionsCubit cubitFor(FakeFetcher fetcher, {RepoStore? store}) =>
        ExtensionsCubit(
          ExtensionRepositoryImpl(
            fetcher: fetcher,
            store: store ?? InMemoryRepoStore(),
            clock: () => DateTime(2026, 9, 8),
          ),
        );

    test('starts ready and empty when nothing is saved', () async {
      final cubit = cubitFor(FakeFetcher(const {}));
      await cubit.start();
      expect(cubit.state.status, ExtensionsStatus.ready);
      expect(cubit.state.repos, isEmpty);
      expect(cubit.state.index, isNull);
      expect(cubit.state.error, isNull);
    });

    test('adding a repository selects it and exposes the catalogue', () async {
      final cubit = cubitFor(
        FakeFetcher({
          'https://x.test/repo/index.min.json': _ok(utf8.encode(_animeJson)),
        }),
      );
      await cubit.start();
      await cubit.addRepo('https://x.test/repo/index.min.json');

      expect(cubit.state.error, isNull);
      expect(cubit.state.busy, isFalse);
      expect(cubit.state.repos, hasLength(1));
      expect(cubit.state.selected, isNotNull);
      expect(cubit.state.supported, hasLength(1));
      expect(cubit.state.unsupported, isEmpty);
    });

    test('a failure surfaces a message and keeps the list', () async {
      final store = InMemoryRepoStore();
      final good = FakeFetcher({
        'https://x.test/repo/index.min.json': _ok(utf8.encode(_animeJson)),
      });
      final cubit = cubitFor(good, store: store);
      await cubit.start();
      await cubit.addRepo('https://x.test/repo/index.min.json');

      // Now a bad one, through a cubit sharing the same store.
      final failing = cubitFor(FakeFetcher(const {}), store: store);
      await failing.start();
      await failing.addRepo('https://gone.test/index.pb');

      expect(failing.state.error, isNotNull);
      expect(failing.state.busy, isFalse);
      expect(failing.state.repos, hasLength(1));
    });

    test('splits a manga catalogue into unsupported entries', () async {
      final cubit = cubitFor(
        FakeFetcher({
          'https://x.test/repo/index.pb': _ok(
            _fixture('keiyoushi_index.pb.gz'),
          ),
        }),
      );
      await cubit.start();
      await cubit.addRepo('https://x.test/repo/index.pb');

      expect(cubit.state.supported, isEmpty);
      expect(cubit.state.unsupported, isNotEmpty);
      expect(
        cubit.state.unsupported.first.unsupportedReason,
        contains('video only'),
      );
    });

    test('dismissing an error clears it', () async {
      final cubit = cubitFor(FakeFetcher(const {}));
      await cubit.start();
      await cubit.addRepo('https://gone.test/index.pb');
      expect(cubit.state.error, isNotNull);
      cubit.dismissError();
      expect(cubit.state.error, isNull);
    });

    test('removing the selected repository clears the catalogue', () async {
      final cubit = cubitFor(
        FakeFetcher({
          'https://x.test/repo/index.min.json': _ok(utf8.encode(_animeJson)),
        }),
      );
      await cubit.start();
      await cubit.addRepo('https://x.test/repo/index.min.json');
      await cubit.removeRepo(cubit.state.repos.single);

      expect(cubit.state.repos, isEmpty);
      expect(cubit.state.selected, isNull);
      expect(cubit.state.index, isNull);
    });
  });
}

