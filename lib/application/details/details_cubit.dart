import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/source/anime.dart';
import '../../domain/repositories/content_source_repository.dart';

enum DetailsStatus { loading, ready, failure }

/// Details and episodes for one title, from the source that produced it.
class DetailsState {
  const DetailsState({
    required this.anime,
    this.status = DetailsStatus.loading,
    this.episodes = const [],
    this.error,
    this.episodesError,
  });

  /// Starts as the listing entry, and is replaced once details load. Showing
  /// the partial version immediately beats an empty screen.
  final Anime anime;

  final DetailsStatus status;
  final List<Episode> episodes;

  /// Details failed; the listing data is still on screen.
  final String? error;

  /// Episodes failed independently — details can succeed while the episode
  /// list does not, and the screen says so without losing the rest.
  final String? episodesError;

  DetailsState copyWith({
    Anime? anime,
    DetailsStatus? status,
    List<Episode>? episodes,
    String? error,
    String? episodesError,
    bool clearErrors = false,
  }) => DetailsState(
    anime: anime ?? this.anime,
    status: status ?? this.status,
    episodes: episodes ?? this.episodes,
    error: clearErrors ? null : (error ?? this.error),
    episodesError: clearErrors ? null : (episodesError ?? this.episodesError),
  );
}

class DetailsCubit extends Cubit<DetailsState> {
  DetailsCubit(this._content, Anime anime) : super(DetailsState(anime: anime));

  final ContentSourceRepository _content;

  Future<void> load() async {
    emit(state.copyWith(status: DetailsStatus.loading, clearErrors: true));
    final anime = state.anime;

    // Details and episodes are requested independently so one failing does
    // not take the other down with it.
    Anime full = anime;
    String? detailsError;
    try {
      full = await _content.details(anime.source, anime.url);
    } on SourceFailure catch (e) {
      detailsError = e.message;
    }

    List<Episode> episodes = const [];
    String? episodesError;
    try {
      episodes = await _content.episodes(anime.source, anime.url);
    } on SourceFailure catch (e) {
      episodesError = e.message;
    }

    emit(
      DetailsState(
        // Keep whichever title is non-empty: some sources return details
        // without echoing the title back.
        anime: full.title.isEmpty ? anime : full,
        status: (detailsError != null && episodesError != null)
            ? DetailsStatus.failure
            : DetailsStatus.ready,
        episodes: episodes,
        error: detailsError,
        episodesError: episodesError,
      ),
    );
  }
}
