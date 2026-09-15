import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/storage/library_store.dart';
import '../../data/storage/progress_store.dart';
import '../../domain/entities/library/library_entry.dart';
import '../../domain/entities/library/watch_progress.dart';
import '../../domain/entities/source/anime.dart';

enum LibraryLoad { initial, loading, ready }

/// Saved series and watch progress.
///
/// These live together because they are read together: the library grid wants
/// to know how far through a series the user is, and the episode list wants
/// both "is this saved" and "have I seen this". Splitting them would mean two
/// cubits above the router that always change in step.
class LibraryState {
  const LibraryState({
    this.load = LibraryLoad.initial,
    this.entries = const [],
    this.progress = const {},
  });

  final LibraryLoad load;

  /// Newest first.
  final List<LibraryEntry> entries;

  /// Keyed by `WatchProgress.key`.
  final Map<String, WatchProgress> progress;

  List<LibraryEntry> forStatus(LibraryStatus status) =>
      entries.where((e) => e.status == status).toList();

  int countFor(LibraryStatus status) =>
      entries.where((e) => e.status == status).length;

  bool isSaved(String animeId) => entries.any((e) => e.id == animeId);

  LibraryEntry? entryFor(String animeId) {
    for (final e in entries) {
      if (e.id == animeId) return e;
    }
    return null;
  }

  WatchProgress? progressFor(String animeId, String episodeUrl) =>
      progress['$animeId|$episodeUrl'];

  /// How many episodes of this series have been watched through. Counts every
  /// recorded episode, including ones the source has since removed — the
  /// alternative is a number that silently shrinks.
  int watchedCount(String animeId) => progress.values
      .where((p) => p.animeId == animeId && p.finished)
      .length;

  LibraryState copyWith({
    LibraryLoad? load,
    List<LibraryEntry>? entries,
    Map<String, WatchProgress>? progress,
  }) => LibraryState(
    load: load ?? this.load,
    entries: entries ?? this.entries,
    progress: progress ?? this.progress,
  );
}

class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit(this._library, this._progress) : super(const LibraryState());

  final LibraryStore _library;
  final ProgressStore _progress;

  /// Position last written to disk, per progress key. Without this, a "has it
  /// moved ten seconds" test compares each tick to the one a second before it
  /// and so never fires after the first write.
  final Map<String, Duration> _persisted = {};

  Future<void> start() async {
    emit(state.copyWith(load: LibraryLoad.loading));
    final entries = await _library.load();
    final progress = await _progress.loadAll();
    emit(
      LibraryState(
        load: LibraryLoad.ready,
        entries: _sorted(entries),
        progress: progress,
      ),
    );
  }

  /// Newest save first, which is what the grid shows.
  List<LibraryEntry> _sorted(List<LibraryEntry> entries) =>
      [...entries]..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  Future<void> toggleSaved(Anime anime) =>
      state.isSaved(anime.id) ? remove(anime.id) : save(anime);

  Future<void> save(Anime anime) async {
    if (state.isSaved(anime.id)) return;
    final entries = _sorted([
      ...state.entries,
      LibraryEntry(anime: anime, savedAt: DateTime.now()),
    ]);
    emit(state.copyWith(entries: entries));
    await _library.save(entries);
  }

  Future<void> remove(String animeId) async {
    final entries = state.entries.where((e) => e.id != animeId).toList();
    emit(state.copyWith(entries: entries));
    await _library.save(entries);
  }

  Future<void> setStatus(String animeId, LibraryStatus status) async {
    final entries = [
      for (final e in state.entries)
        if (e.id == animeId) e.copyWith(status: status) else e,
    ];
    emit(state.copyWith(entries: entries));
    await _library.save(entries);
  }

  /// Called from the player as it plays, so it must stay cheap and must not
  /// hit storage on every tick — see [_shouldPersist].
  Future<void> recordProgress({
    required String animeId,
    required String episodeUrl,
    required Duration position,
    required Duration duration,
  }) async {
    final entry = WatchProgress(
      animeId: animeId,
      episodeUrl: episodeUrl,
      position: position,
      duration: duration,
      updatedAt: DateTime.now(),
    );
    final previous = state.progress[entry.key];

    // Playback always reports position zero before it reports anything
    // useful, so opening an episode and backing out a few seconds later would
    // otherwise erase a real resume point. Someone who genuinely restarts an
    // episode climbs back past the threshold and overwrites it then.
    if (previous != null &&
        (previous.started || previous.finished) &&
        position < WatchProgress.startedThreshold) {
      return;
    }

    emit(state.copyWith(progress: {...state.progress, entry.key: entry}));
    if (_shouldPersist(previous, entry)) await _write(entry);
  }

  Future<void> _write(WatchProgress entry) async {
    _persisted[entry.key] = entry.position;
    await _progress.put(entry);
  }

  /// Writing to disk every tick would be wasteful, but writing only on dispose
  /// loses everything if the app is killed. Ten seconds of playback since the
  /// last write, or any change in whether the episode counts as finished, is
  /// the compromise.
  bool _shouldPersist(WatchProgress? previous, WatchProgress next) {
    if (previous != null && previous.finished != next.finished) return true;
    final written = _persisted[next.key];
    if (written == null) return true;
    return (next.position - written).abs() >= const Duration(seconds: 10);
  }

  /// Marks an episode watched, or clears it if it already is.
  Future<void> toggleWatched({
    required String animeId,
    required String episodeUrl,
  }) async {
    final key = '$animeId|$episodeUrl';
    final existing = state.progress[key];
    if (existing?.finished ?? false) {
      emit(state.copyWith(progress: {...state.progress}..remove(key)));
      _persisted.remove(key);
      await _progress.remove(key);
      return;
    }
    // No real duration is known from the list, so a nominal one is stored
    // purely to make `finished` true. The player overwrites it on next play.
    const nominal = Duration(minutes: 24);
    final entry = WatchProgress(
      animeId: animeId,
      episodeUrl: episodeUrl,
      position: nominal,
      duration: nominal,
      updatedAt: DateTime.now(),
    );
    emit(state.copyWith(progress: {...state.progress, key: entry}));
    await _write(entry);
  }

  /// Flushes whatever is in memory. The player calls this on dispose so the
  /// last few seconds before a back-press are not lost.
  Future<void> flush(String animeId, String episodeUrl) async {
    final entry = state.progress['$animeId|$episodeUrl'];
    if (entry != null) await _write(entry);
  }
}
