import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/storage/app_prefs.dart';
import '../../domain/entities/source/anime.dart';
import '../../domain/repositories/content_source_repository.dart';
import '../../domain/repositories/download_repository.dart';

enum PlayerStatus { resolving, ready, failure }

/// Resolving an episode into something playable.
///
/// Kept separate from the player widget's own state: `media_kit` owns
/// position, buffering and play/pause, and duplicating those here would mean
/// two sources of truth for the same facts.
class PlaybackState {
  const PlaybackState({
    required this.anime,
    required this.episode,
    this.status = PlayerStatus.resolving,
    this.streams = const [],
    this.selected,
    this.error,
    this.offline = false,
  });

  final Anime anime;
  final Episode episode;
  final PlayerStatus status;

  /// Every stream the source offered, in the order it gave them.
  final List<VideoStream> streams;

  /// Which one is playing.
  final VideoStream? selected;

  final String? error;

  /// Playing a downloaded file rather than a stream. The quality menu is
  /// meaningless then — there is exactly one copy on disk.
  final bool offline;

  bool get hasChoices => streams.length > 1 && !offline;

  PlaybackState copyWith({
    PlayerStatus? status,
    List<VideoStream>? streams,
    VideoStream? selected,
    String? error,
    bool? offline,
    bool clearError = false,
  }) => PlaybackState(
    anime: anime,
    episode: episode,
    status: status ?? this.status,
    streams: streams ?? this.streams,
    selected: selected ?? this.selected,
    error: clearError ? null : (error ?? this.error),
    offline: offline ?? this.offline,
  );
}

class PlayerCubit extends Cubit<PlaybackState> {
  PlayerCubit(
    this._content,
    this._downloads,
    this._prefs,
    Anime anime,
    Episode episode,
  ) : super(PlaybackState(anime: anime, episode: episode));

  final ContentSourceRepository _content;
  final DownloadRepository _downloads;
  final AppPrefs _prefs;

  Future<void> resolve() async {
    emit(state.copyWith(status: PlayerStatus.resolving, clearError: true));

    // A downloaded episode is the whole point of downloading it: play the
    // file and never touch the network, so this works with no connection at
    // all — which is when it matters.
    final local = await _localStream();
    if (local != null) {
      emit(
        state.copyWith(
          status: PlayerStatus.ready,
          streams: [local],
          selected: local,
          offline: true,
        ),
      );
      return;
    }

    try {
      final streams = await _content.videos(
        state.anime.source,
        state.episode.url,
      );
      emit(
        state.copyWith(
          status: PlayerStatus.ready,
          streams: streams,
          selected: pickPreferredStream(streams, _prefs.preferredQuality),
        ),
      );
    } on SourceFailure catch (e) {
      emit(state.copyWith(status: PlayerStatus.failure, error: e.message));
    }
  }

  /// The downloaded file as a stream, or null if there is not one.
  Future<VideoStream?> _localStream() async {
    try {
      final items = await _downloads.list();
      for (final item in items) {
        if (!item.isFinished) continue;
        if (item.record.anime.id != state.anime.id) continue;
        if (item.record.episodeUrl != state.episode.url) continue;
        final path = item.filePath;
        if (path == null) continue;
        return VideoStream(url: path, quality: 'Downloaded');
      }
    } catch (_) {
      // A download list that cannot be read is not a reason to refuse to
      // play; fall through and ask the source.
    }
    return null;
  }

  void selectStream(VideoStream stream) =>
      emit(state.copyWith(selected: stream));
}
