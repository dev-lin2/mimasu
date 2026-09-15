import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/storage/app_prefs.dart';
import '../../domain/entities/source/anime.dart';
import '../../domain/repositories/content_source_repository.dart';

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
  });

  final Anime anime;
  final Episode episode;
  final PlayerStatus status;

  /// Every stream the source offered, in the order it gave them.
  final List<VideoStream> streams;

  /// Which one is playing.
  final VideoStream? selected;

  final String? error;

  bool get hasChoices => streams.length > 1;

  PlaybackState copyWith({
    PlayerStatus? status,
    List<VideoStream>? streams,
    VideoStream? selected,
    String? error,
    bool clearError = false,
  }) => PlaybackState(
    anime: anime,
    episode: episode,
    status: status ?? this.status,
    streams: streams ?? this.streams,
    selected: selected ?? this.selected,
    error: clearError ? null : (error ?? this.error),
  );
}

class PlayerCubit extends Cubit<PlaybackState> {
  PlayerCubit(this._content, this._prefs, Anime anime, Episode episode)
    : super(PlaybackState(anime: anime, episode: episode));

  final ContentSourceRepository _content;
  final AppPrefs _prefs;

  Future<void> resolve() async {
    emit(state.copyWith(status: PlayerStatus.resolving, clearError: true));
    try {
      final streams = await _content.videos(
        state.anime.source,
        state.episode.url,
      );
      emit(
        state.copyWith(
          status: PlayerStatus.ready,
          streams: streams,
          selected: _pick(streams),
        ),
      );
    } on SourceFailure catch (e) {
      emit(state.copyWith(status: PlayerStatus.failure, error: e.message));
    }
  }

  /// Honours the quality preference when a stream's label plausibly matches
  /// it, and otherwise falls back to the source's own ordering — the first
  /// entry is the source's preference, which beats guessing from labels it
  /// wrote for itself.
  VideoStream _pick(List<VideoStream> streams) {
    final wanted = _prefs.preferredQuality;
    if (wanted.isEmpty || wanted.toLowerCase() == 'auto') return streams.first;
    for (final stream in streams) {
      if (stream.quality.toLowerCase().contains(wanted.toLowerCase())) {
        return stream;
      }
    }
    return streams.first;
  }

  void selectStream(VideoStream stream) =>
      emit(state.copyWith(selected: stream));
}
