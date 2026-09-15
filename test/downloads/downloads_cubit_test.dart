import 'package:flutter_test/flutter_test.dart';
import 'package:mimasu/application/downloads/downloads_cubit.dart';
import 'package:mimasu/data/storage/app_prefs.dart';
import 'package:mimasu/domain/entities/downloads/download_record.dart';
import 'package:mimasu/domain/entities/source/anime.dart';
import 'package:mimasu/domain/repositories/content_source_repository.dart';
import 'package:mimasu/domain/repositories/download_repository.dart';

const _source = SourceRef(
  packageName: 'com.example.ext',
  className: '.Example',
  sourceName: 'Example',
);
const _anime = Anime(url: '/show/', title: 'A Show', source: _source);
const _episode = Episode(url: '/show/ep-1/', name: 'Episode 1', number: 1);

/// Records what it was asked to do and answers with whatever it was set up
/// to answer. Nothing here touches a platform channel.
class _FakeDownloads implements DownloadRepository {
  _FakeDownloads({this.refuse});

  final DownloadRefusalReason? refuse;

  final List<DownloadItem> items = [];
  final List<String> cancelled = [];
  final List<String> removed = [];
  bool? lastWifiOnly;

  @override
  Future<void> enqueue({
    required Anime anime,
    required Episode episode,
    required VideoStream stream,
    required bool wifiOnly,
  }) async {
    lastWifiOnly = wifiOnly;
    if (refuse != null) throw DownloadRefused(refuse!);
    items.add(
      DownloadItem(
        record: DownloadRecord(
          id: DownloadRecord.idFor(anime.id, episode.url),
          anime: anime,
          episodeUrl: episode.url,
          episodeName: episode.name,
          episodeNumber: episode.number,
          requestedAt: DateTime(2026),
        ),
        state: DownloadProgressState.running,
      ),
    );
  }

  @override
  Future<void> cancel(String id) async => cancelled.add(id);

  @override
  Future<void> remove(String id) async {
    removed.add(id);
    items.removeWhere((i) => i.record.id == id);
  }

  @override
  Future<List<DownloadItem>> list() async => List.of(items);

  @override
  Future<bool> isMetered() async => false;
}

class _FakeContent implements ContentSourceRepository {
  _FakeContent(this.streams);

  final List<VideoStream> streams;

  @override
  Future<List<VideoStream>> videos(SourceRef source, String episodeUrl) async {
    if (streams.isEmpty) {
      throw const SourceFailure(
        SourceFailureKind.empty,
        'Example returned no playable streams for this episode.',
      );
    }
    return streams;
  }

  @override
  Future<Anime> details(SourceRef source, String animeUrl) =>
      throw UnimplementedError();

  @override
  Future<List<Episode>> episodes(SourceRef source, String animeUrl) =>
      throw UnimplementedError();

  @override
  Future<AnimePage> popular(SourceRef source, {int page = 1}) =>
      throw UnimplementedError();

  @override
  Future<AnimePage> latest(SourceRef source, {int page = 1}) =>
      throw UnimplementedError();

  @override
  Future<AnimePage> search(SourceRef source, String query, {int page = 1}) =>
      throw UnimplementedError();

  @override
  Future<void> invalidate() async {}
}

void main() {
  group('DownloadRecord.idFor', () {
    test('is stable and filename-safe', () {
      final id = DownloadRecord.idFor(_anime.id, _episode.url);
      expect(id, DownloadRecord.idFor(_anime.id, _episode.url));
      expect(id, hasLength(16));
      // The regression this guards: Dart ints are signed, so an unmasked
      // FNV hash produced ids like "-2beab274095d2150", and that minus sign
      // went straight into a filename on disk.
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(id), isTrue, reason: id);
    });

    test('differs per episode and per series', () {
      final a = DownloadRecord.idFor(_anime.id, '/ep-1/');
      final b = DownloadRecord.idFor(_anime.id, '/ep-2/');
      final c = DownloadRecord.idFor('other', '/ep-1/');
      expect({a, b, c}, hasLength(3));
    });
  });

  group('DownloadItem', () {
    DownloadItem item({
      required DownloadProgressState state,
      int bytes = 0,
      int total = -1,
    }) => DownloadItem(
      record: DownloadRecord(
        id: 'x',
        anime: _anime,
        episodeUrl: _episode.url,
        episodeName: _episode.name,
        episodeNumber: 1,
        requestedAt: DateTime(2026),
      ),
      state: state,
      bytesDownloaded: bytes,
      totalBytes: total,
    );

    test('has no fraction until the total is known', () {
      expect(
        item(state: DownloadProgressState.running, bytes: 1000).fraction,
        isNull,
        reason: 'an indeterminate bar beats one stuck at zero',
      );
    });

    test('reports a fraction once the total is known', () {
      final i = item(
        state: DownloadProgressState.running,
        bytes: 50,
        total: 100,
      );
      expect(i.fraction, 0.5);
    });

    test('labels size in human units', () {
      final i = item(
        state: DownloadProgressState.running,
        bytes: 26 * 1024 * 1024,
        total: 463 * 1024 * 1024,
      );
      expect(i.sizeLabel, '26 MB of 463 MB');
    });
  });

  group('DownloadsCubit', () {
    test('queues a download at the preferred quality', () async {
      final downloads = _FakeDownloads();
      final cubit = DownloadsCubit(
        downloads,
        _FakeContent(const [
          VideoStream(url: 'a', quality: '1080p'),
          VideoStream(url: 'b', quality: '480p'),
        ]),
        InMemoryAppPrefs()..preferredQuality = '480p',
      );
      addTearDown(cubit.close);

      await cubit.download(_anime, _episode);

      expect(cubit.state.items, hasLength(1));
      expect(
        cubit.state.stateFor(_anime.id, _episode.url),
        DownloadProgressState.running,
      );
    });

    test('passes the Wi-Fi preference through', () async {
      final downloads = _FakeDownloads();
      final cubit = DownloadsCubit(
        downloads,
        _FakeContent(const [VideoStream(url: 'a', quality: '720p')]),
        InMemoryAppPrefs()..downloadOnWifiOnly = true,
      );
      addTearDown(cubit.close);

      await cubit.download(_anime, _episode);
      expect(downloads.lastWifiOnly, isTrue);
    });

    test('reports a refusal as a notice, not a crash', () async {
      final cubit = DownloadsCubit(
        _FakeDownloads(refuse: DownloadRefusalReason.metered),
        _FakeContent(const [VideoStream(url: 'a', quality: '720p')]),
        InMemoryAppPrefs(),
      );
      addTearDown(cubit.close);

      await cubit.download(_anime, _episode);
      expect(cubit.state.notice, contains('Wi-Fi'));
      expect(cubit.state.items, isEmpty);
    });

    test('reports a source failure in the source\'s own words', () async {
      final cubit = DownloadsCubit(
        _FakeDownloads(),
        _FakeContent(const []),
        InMemoryAppPrefs(),
      );
      addTearDown(cubit.close);

      await cubit.download(_anime, _episode);
      expect(cubit.state.notice, contains('no playable streams'));
    });

    test('finds a finished download for the player', () async {
      final downloads = _FakeDownloads();
      final cubit = DownloadsCubit(
        downloads,
        _FakeContent(const [VideoStream(url: 'a', quality: '720p')]),
        InMemoryAppPrefs(),
      );
      addTearDown(cubit.close);

      final id = DownloadRecord.idFor(_anime.id, _episode.url);
      downloads.items.add(
        DownloadItem(
          record: DownloadRecord(
            id: id,
            anime: _anime,
            episodeUrl: _episode.url,
            episodeName: _episode.name,
            episodeNumber: 1,
            requestedAt: DateTime(2026),
          ),
          state: DownloadProgressState.completed,
          filePath: '/data/files/downloads/$id.mp4',
        ),
      );
      await cubit.refresh();

      expect(cubit.state.isDownloaded(_anime.id, _episode.url), isTrue);
      expect(
        cubit.state.filePathFor(_anime.id, _episode.url),
        endsWith('.mp4'),
      );
    });

    test('an unfinished download is not offered as playable', () async {
      final downloads = _FakeDownloads();
      final cubit = DownloadsCubit(
        downloads,
        _FakeContent(const [VideoStream(url: 'a', quality: '720p')]),
        InMemoryAppPrefs(),
      );
      addTearDown(cubit.close);

      await cubit.download(_anime, _episode);
      expect(
        cubit.state.filePathFor(_anime.id, _episode.url),
        isNull,
        reason: 'half a file would fail at the worst moment',
      );
    });

    group('delete after watching', () {
      test('removes the file when the setting is on', () async {
        final downloads = _FakeDownloads();
        final cubit = DownloadsCubit(
          downloads,
          _FakeContent(const [VideoStream(url: 'a', quality: '720p')]),
          InMemoryAppPrefs()..deleteAfterWatching = true,
        );
        addTearDown(cubit.close);

        await cubit.download(_anime, _episode);
        await cubit.onEpisodeFinished(_anime.id, _episode.url);

        expect(downloads.removed, hasLength(1));
      });

      test('leaves it alone when the setting is off', () async {
        final downloads = _FakeDownloads();
        final cubit = DownloadsCubit(
          downloads,
          _FakeContent(const [VideoStream(url: 'a', quality: '720p')]),
          InMemoryAppPrefs()..deleteAfterWatching = false,
        );
        addTearDown(cubit.close);

        await cubit.download(_anime, _episode);
        await cubit.onEpisodeFinished(_anime.id, _episode.url);

        expect(downloads.removed, isEmpty);
      });

      test('does nothing for an episode that was never downloaded', () async {
        final downloads = _FakeDownloads();
        final cubit = DownloadsCubit(
          downloads,
          _FakeContent(const [VideoStream(url: 'a', quality: '720p')]),
          InMemoryAppPrefs()..deleteAfterWatching = true,
        );
        addTearDown(cubit.close);

        await cubit.onEpisodeFinished(_anime.id, _episode.url);
        expect(downloads.removed, isEmpty);
      });
    });
  });

  group('pickPreferredStream', () {
    const streams = [
      VideoStream(url: 'a', quality: 'Dailymotion (English)1080p'),
      VideoStream(url: 'b', quality: 'Dailymotion (English)720p'),
      VideoStream(url: 'c', quality: 'Dailymotion (English)480p'),
    ];

    test('matches inside a long source-written label', () {
      expect(pickPreferredStream(streams, '720p').url, 'b');
    });

    test('auto keeps the source order', () {
      expect(pickPreferredStream(streams, 'Auto').url, 'a');
    });

    test('falls back to the source order when nothing matches', () {
      expect(pickPreferredStream(streams, '4K').url, 'a');
    });
  });
}
