import 'package:flutter_test/flutter_test.dart';
import 'package:mimasu/application/library/library_cubit.dart';
import 'package:mimasu/data/storage/library_store.dart';
import 'package:mimasu/data/storage/progress_store.dart';
import 'package:mimasu/domain/entities/library/library_entry.dart';
import 'package:mimasu/domain/entities/library/watch_progress.dart';
import 'package:mimasu/domain/entities/source/anime.dart';

const _source = SourceRef(
  packageName: 'com.example.ext',
  className: '.Example',
  sourceName: 'Example',
);

const _anime = Anime(url: '/show/', title: 'A Show', source: _source);
const _episodeUrl = '/show/ep-1/';

WatchProgress _progress(Duration position, [Duration? duration]) =>
    WatchProgress(
      animeId: _anime.id,
      episodeUrl: _episodeUrl,
      position: position,
      duration: duration ?? const Duration(minutes: 20),
      updatedAt: DateTime(2026),
    );

void main() {
  group('WatchProgress', () {
    test('is not started below the threshold', () {
      expect(_progress(const Duration(seconds: 5)).started, isFalse);
      expect(_progress(const Duration(seconds: 5)).resumeAt, isNull);
    });

    test('is started past the threshold', () {
      final p = _progress(const Duration(minutes: 3));
      expect(p.started, isTrue);
      expect(p.resumeAt, const Duration(minutes: 3));
    });

    test('counts as finished inside the credits', () {
      expect(_progress(const Duration(minutes: 19)).finished, isTrue);
    });

    test('offers no resume point once finished', () {
      final p = _progress(const Duration(minutes: 19));
      expect(p.started, isFalse);
      expect(p.resumeAt, isNull, reason: 'a rewatch must not open the credits');
    });

    test('treats an unknown duration as unfinished', () {
      final p = _progress(const Duration(minutes: 5), Duration.zero);
      expect(p.finished, isFalse);
      expect(p.fraction, 0);
    });

    test('survives a round trip', () {
      final restored = WatchProgress.fromJson(
        _progress(const Duration(minutes: 3)).toJson(),
      );
      expect(restored!.position, const Duration(minutes: 3));
      expect(restored.episodeUrl, _episodeUrl);
    });
  });

  group('Anime serialization', () {
    test('keeps the fields the library card shows', () {
      const saved = Anime(
        url: '/show/',
        title: 'A Show',
        source: _source,
        thumbnailUrl: 'https://example.test/a.jpg',
        status: AnimeStatus.completed,
      );

      final restored = Anime.fromJson(saved.toJson())!;

      expect(restored.url, saved.url);
      expect(restored.title, saved.title);
      expect(restored.thumbnailUrl, saved.thumbnailUrl);
      expect(restored.source, saved.source);
      // The regression this guards: status was left out, so a saved title
      // lost its "Completed" line the first time the app restarted.
      expect(restored.status, AnimeStatus.completed);
    });

    test('an unknown status survives as unknown', () {
      const saved = Anime(url: '/a/', title: 'A', source: _source);
      expect(Anime.fromJson(saved.toJson())!.status, AnimeStatus.unknown);
    });
  });

  group('LibraryCubit', () {
    late LibraryCubit cubit;
    late InMemoryLibraryStore library;
    late InMemoryProgressStore progress;

    setUp(() {
      library = InMemoryLibraryStore();
      progress = InMemoryProgressStore();
      cubit = LibraryCubit(library, progress);
    });

    tearDown(() => cubit.close());

    test('saving and removing persists', () async {
      await cubit.start();
      await cubit.save(_anime);
      expect(cubit.state.isSaved(_anime.id), isTrue);
      expect(await library.load(), hasLength(1));

      await cubit.remove(_anime.id);
      expect(cubit.state.isSaved(_anime.id), isFalse);
      expect(await library.load(), isEmpty);
    });

    test('saving the same title twice does not duplicate it', () async {
      await cubit.start();
      await cubit.save(_anime);
      await cubit.save(_anime);
      expect(cubit.state.entries, hasLength(1));
    });

    test('status moves an entry between tabs', () async {
      await cubit.start();
      await cubit.save(_anime);
      await cubit.setStatus(_anime.id, LibraryStatus.completed);

      expect(cubit.state.countFor(LibraryStatus.watching), 0);
      expect(cubit.state.countFor(LibraryStatus.completed), 1);
    });

    test('toggling watched sets, then clears, the record', () async {
      await cubit.start();
      await cubit.toggleWatched(animeId: _anime.id, episodeUrl: _episodeUrl);
      expect(cubit.state.progressFor(_anime.id, _episodeUrl)!.finished, isTrue);
      expect(cubit.state.watchedCount(_anime.id), 1);

      await cubit.toggleWatched(animeId: _anime.id, episodeUrl: _episodeUrl);
      expect(cubit.state.progressFor(_anime.id, _episodeUrl), isNull);
      expect(await progress.loadAll(), isEmpty);
    });

    test('keeps writing as playback advances', () async {
      await cubit.start();
      for (var second = 0; second <= 60; second += 1) {
        await cubit.recordProgress(
          animeId: _anime.id,
          episodeUrl: _episodeUrl,
          position: Duration(seconds: second),
          duration: const Duration(minutes: 20),
        );
      }

      // The regression this guards: comparing each tick against the one
      // before it means the ten-second rule never fires again after the
      // first write, and the stored position sticks near zero.
      final stored = (await progress.loadAll()).values.single;
      expect(
        stored.position.inSeconds,
        greaterThanOrEqualTo(50),
        reason: 'disk should track playback, not stall at the first write',
      );
    });

    test('opening an episode briefly does not erase a resume point', () async {
      await progress.put(_progress(const Duration(minutes: 8)));
      await cubit.start();

      // What a second play looks like before the user gives up on it.
      for (final second in [0, 1, 2, 3]) {
        await cubit.recordProgress(
          animeId: _anime.id,
          episodeUrl: _episodeUrl,
          position: Duration(seconds: second),
          duration: const Duration(minutes: 20),
        );
      }

      expect(
        cubit.state.progressFor(_anime.id, _episodeUrl)!.position,
        const Duration(minutes: 8),
      );
    });

    test('a genuine restart does overwrite once it passes the threshold',
        () async {
      await progress.put(_progress(const Duration(minutes: 8)));
      await cubit.start();

      await cubit.recordProgress(
        animeId: _anime.id,
        episodeUrl: _episodeUrl,
        position: const Duration(minutes: 1),
        duration: const Duration(minutes: 20),
      );

      expect(
        cubit.state.progressFor(_anime.id, _episodeUrl)!.position,
        const Duration(minutes: 1),
      );
    });

    test('a corrupt stored entry is skipped, not fatal', () async {
      expect(LibraryEntry.fromJson({'anime': 'not a map'}), isNull);
      expect(Anime.fromJson({'url': 42}), isNull);
      expect(WatchProgress.fromJson({'animeId': 7}), isNull);
    });
  });
}
