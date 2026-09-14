/// Content entities, as a source reports them.
///
/// There is no metadata service underneath Mimasu (INSTRUCTIONS.md §1), so
/// these carry exactly what the extension gave us and nothing more. Absent
/// fields stay absent rather than being filled in from elsewhere.
library;

/// Which source an item came from. Titles are only meaningful together with
/// their source: two sources can describe the same show differently, and a url
/// is only resolvable by the source that produced it.
class SourceRef {
  const SourceRef({
    required this.packageName,
    required this.className,
    required this.sourceName,
  });

  final String packageName;
  final String className;
  final String sourceName;

  String get key => '$packageName|$className';

  @override
  bool operator ==(Object other) =>
      other is SourceRef &&
      other.packageName == packageName &&
      other.className == className;

  @override
  int get hashCode => Object.hash(packageName, className);
}

enum AnimeStatus {
  unknown,
  ongoing,
  completed,
  licensed,
  publishingFinished,
  cancelled,
  onHiatus;

  /// SAnime's constants, confirmed against the shim.
  static AnimeStatus fromCode(int code) => switch (code) {
    1 => ongoing,
    2 => completed,
    3 => licensed,
    4 => publishingFinished,
    5 => cancelled,
    6 => onHiatus,
    _ => unknown,
  };

  String get label => switch (this) {
    ongoing => 'Ongoing',
    completed => 'Completed',
    licensed => 'Licensed',
    publishingFinished => 'Finished',
    cancelled => 'Cancelled',
    onHiatus => 'On hiatus',
    unknown => '',
  };
}

class Anime {
  const Anime({
    required this.url,
    required this.title,
    required this.source,
    this.thumbnailUrl,
    this.description,
    this.author,
    this.genre,
    this.status = AnimeStatus.unknown,
  });

  /// Source-relative; only the producing source can resolve it.
  final String url;
  final String title;
  final SourceRef source;
  final String? thumbnailUrl;
  final String? description;
  final String? author;
  final String? genre;
  final AnimeStatus status;

  List<String> get genres => (genre ?? '')
      .split(RegExp(r'[,،]'))
      .map((g) => g.trim())
      .where((g) => g.isNotEmpty)
      .toList();

  /// Stable across sessions, and distinct per source.
  String get id => '${source.key}|$url';
}

class Episode {
  const Episode({
    required this.url,
    required this.name,
    required this.number,
    this.uploadedAt,
    this.scanlator,
  });

  final String url;
  final String name;

  /// Negative when the source did not number it.
  final double number;

  final DateTime? uploadedAt;
  final String? scanlator;

  bool get hasNumber => number >= 0;
}

/// One playable stream. [headers] must reach the player: many sources 403
/// without a Referer (INSTRUCTIONS.md §8).
class VideoStream {
  const VideoStream({
    required this.url,
    required this.quality,
    this.videoUrl,
    this.headers = const {},
    this.subtitleUrls = const [],
    this.audioUrls = const [],
  });

  final String url;
  final String quality;
  final String? videoUrl;
  final Map<String, String> headers;
  final List<String> subtitleUrls;
  final List<String> audioUrls;

  /// What the player should actually open.
  String get playbackUrl => (videoUrl?.isNotEmpty ?? false) ? videoUrl! : url;
}
