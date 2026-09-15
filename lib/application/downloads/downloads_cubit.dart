import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/storage/app_prefs.dart';
import '../../domain/entities/downloads/download_record.dart';
import '../../domain/entities/source/anime.dart';
import '../../domain/repositories/content_source_repository.dart';
import '../../domain/repositories/download_repository.dart';

enum DownloadsLoad { initial, loading, ready }

class DownloadsState {
  const DownloadsState({
    this.load = DownloadsLoad.initial,
    this.items = const [],
    this.notice,
  });

  final DownloadsLoad load;
  final List<DownloadItem> items;

  /// A refusal or error to show once, then clear.
  final String? notice;

  List<DownloadItem> get active => items.where((i) => i.isActive).toList();
  List<DownloadItem> get finished => items.where((i) => i.isFinished).toList();
  List<DownloadItem> get problems => items
      .where((i) => !i.isActive && !i.isFinished)
      .toList();

  bool get isEmpty => items.isEmpty;

  /// Where a downloaded episode lives, if it is fully downloaded.
  String? filePathFor(String animeId, String episodeUrl) {
    final id = DownloadRecord.idFor(animeId, episodeUrl);
    for (final item in items) {
      if (item.record.id == id && item.isFinished) return item.filePath;
    }
    return null;
  }

  bool isDownloaded(String animeId, String episodeUrl) =>
      filePathFor(animeId, episodeUrl) != null;

  DownloadProgressState? stateFor(String animeId, String episodeUrl) {
    final id = DownloadRecord.idFor(animeId, episodeUrl);
    for (final item in items) {
      if (item.record.id == id) return item.state;
    }
    return null;
  }

  DownloadsState copyWith({
    DownloadsLoad? load,
    List<DownloadItem>? items,
    String? notice,
    bool clearNotice = false,
  }) => DownloadsState(
    load: load ?? this.load,
    items: items ?? this.items,
    notice: clearNotice ? null : (notice ?? this.notice),
  );
}

/// Downloads state, polled from the host.
///
/// Polling rather than a push channel because the host is the authority and
/// outlives the engine: a stream would have to be rebuilt on every restart
/// and reconciled anyway, and this is a list the user is looking at for
/// seconds at a time.
class DownloadsCubit extends Cubit<DownloadsState> {
  DownloadsCubit(this._downloads, this._content, this._prefs)
    : super(const DownloadsState());

  final DownloadRepository _downloads;
  final ContentSourceRepository _content;
  final AppPrefs _prefs;

  Timer? _poll;

  Future<void> start() async {
    emit(state.copyWith(load: DownloadsLoad.loading));
    await refresh();
  }

  Future<void> refresh() async {
    final items = await _downloads.list();
    if (isClosed) return;
    emit(state.copyWith(load: DownloadsLoad.ready, items: items));
    _schedule(items);
  }

  /// Only polls while something is moving. A finished list is static, and a
  /// timer that never stops would keep waking the app for nothing.
  void _schedule(List<DownloadItem> items) {
    _poll?.cancel();
    if (items.any((i) => i.isActive)) {
      _poll = Timer(const Duration(seconds: 1), refresh);
    }
  }

  /// Resolves the episode to a stream and queues it.
  ///
  /// The resolve is a network call to the source, exactly as pressing play
  /// would be, so this can fail for all the same reasons and says so in the
  /// same words.
  Future<void> download(Anime anime, Episode episode) async {
    emit(state.copyWith(notice: 'Finding a stream for ${episode.name}…'));
    try {
      final streams = await _content.videos(anime.source, episode.url);
      await _downloads.enqueue(
        anime: anime,
        episode: episode,
        stream: pickPreferredStream(streams, _prefs.preferredQuality),
        wifiOnly: _prefs.downloadOnWifiOnly,
      );
      emit(state.copyWith(notice: 'Downloading ${episode.name}'));
      await refresh();
    } on DownloadRefused catch (e) {
      emit(state.copyWith(notice: e.message));
    } on SourceFailure catch (e) {
      emit(state.copyWith(notice: e.message));
    }
  }

  Future<void> cancel(String id) async {
    await _downloads.cancel(id);
    await refresh();
  }

  Future<void> remove(String id) async {
    await _downloads.remove(id);
    await refresh();
  }

  /// Honours "delete after watching". Called when an episode finishes, not
  /// when the player closes: leaving part way through is not watching it.
  Future<void> onEpisodeFinished(String animeId, String episodeUrl) async {
    if (!_prefs.deleteAfterWatching) return;
    final id = DownloadRecord.idFor(animeId, episodeUrl);
    if (state.items.every((i) => i.record.id != id)) return;
    await remove(id);
  }

  void dismissNotice() => emit(state.copyWith(clearNotice: true));

  @override
  Future<void> close() {
    _poll?.cancel();
    return super.close();
  }
}
