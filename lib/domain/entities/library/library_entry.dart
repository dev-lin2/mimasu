import '../source/anime.dart';

/// Where a saved series sits in the user's own tracking.
///
/// These are the four tabs the library screen has always drawn. They are the
/// user's judgement, not the source's: a source's own `AnimeStatus` says
/// whether the *show* is finished, which is a different question from whether
/// this person is still watching it.
enum LibraryStatus {
  watching,
  completed,
  planning,
  dropped;

  String get label => switch (this) {
    watching => 'Watching',
    completed => 'Completed',
    planning => 'Planning',
    dropped => 'Dropped',
  };

  static LibraryStatus fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => watching);
}

/// One series the user saved, stored on this device only (INSTRUCTIONS.md §7).
class LibraryEntry {
  const LibraryEntry({
    required this.anime,
    required this.savedAt,
    this.status = LibraryStatus.watching,
  });

  final Anime anime;
  final DateTime savedAt;
  final LibraryStatus status;

  String get id => anime.id;

  LibraryEntry copyWith({LibraryStatus? status}) => LibraryEntry(
    anime: anime,
    savedAt: savedAt,
    status: status ?? this.status,
  );

  Map<String, dynamic> toJson() => {
    'anime': anime.toJson(),
    'savedAt': savedAt.toIso8601String(),
    'status': status.name,
  };

  /// Null rather than throwing: a corrupt entry is dropped and the rest of
  /// the library still loads.
  static LibraryEntry? fromJson(Map<dynamic, dynamic> json) {
    final rawAnime = json['anime'];
    if (rawAnime is! Map) return null;
    final anime = Anime.fromJson(rawAnime);
    if (anime == null) return null;
    return LibraryEntry(
      anime: anime,
      savedAt:
          DateTime.tryParse(json['savedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      status: LibraryStatus.fromName(json['status'] as String?),
    );
  }
}
