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

  Map<String, dynamic> toJson() => {
    'packageName': packageName,
    'className': className,
    'sourceName': sourceName,
  };

  /// Null rather than throwing on a malformed record: one corrupt library
  /// entry must not stop the library from loading.
  static SourceRef? fromJson(Map<dynamic, dynamic> json) {
    final package = json['packageName'];
    final className = json['className'];
    if (package is! String || className is! String) return null;
    return SourceRef(
      packageName: package,
      className: className,
      sourceName: json['sourceName'] as String? ?? package,
    );
  }
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

  /// Only the listing-level fields are persisted. Details are re-fetched from
  /// the source when the title is opened, so storing a stale synopsis would
  /// buy nothing and could contradict what the source now says.
  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'source': source.toJson(),
    'thumbnailUrl': thumbnailUrl,
  };

  static Anime? fromJson(Map<dynamic, dynamic> json) {
    final url = json['url'];
    final title = json['title'];
    final rawSource = json['source'];
    if (url is! String || title is! String) return null;
    if (rawSource is! Map) return null;
    final source = SourceRef.fromJson(rawSource);
    if (source == null) return null;
    return Anime(
      url: url,
      title: title,
      source: source,
      thumbnailUrl: json['thumbnailUrl'] as String?,
    );
  }
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

/// One external track offered alongside a video.
class MediaTrack {
  const MediaTrack({required this.url, required this.label});

  final String url;

  /// The source's own wording — "English", "en", "eng", or nothing at all.
  final String label;

  /// Whether this track plausibly matches a language the user asked for.
  ///
  /// Deliberately loose. Sources label tracks however they like, and a
  /// preference of "English" should still match "en" or "English [CC]". A
  /// false positive here costs the user one tap; being strict costs them the
  /// feature entirely.
  bool matches(String language) {
    if (language.isEmpty || label.isEmpty) return false;
    final a = label.toLowerCase();
    final b = language.toLowerCase();
    return a.contains(b) || b.contains(a);
  }
}

/// One playable stream. [headers] must reach the player: many sources 403
/// without a Referer (INSTRUCTIONS.md §8).
class VideoStream {
  const VideoStream({
    required this.url,
    required this.quality,
    this.videoUrl,
    this.headers = const {},
    this.subtitleTracks = const [],
    this.audioTracks = const [],
  });

  final String url;
  final String quality;
  final String? videoUrl;
  final Map<String, String> headers;
  final List<MediaTrack> subtitleTracks;
  final List<MediaTrack> audioTracks;

  /// The track to show, given a preferred language. Falls back to the first
  /// the source offered, because a source that supplies exactly one subtitle
  /// track usually means it.
  MediaTrack? preferredSubtitle(String language) {
    if (subtitleTracks.isEmpty) return null;
    for (final track in subtitleTracks) {
      if (track.matches(language)) return track;
    }
    return subtitleTracks.first;
  }

  /// What the player should actually open.
  String get playbackUrl => (videoUrl?.isNotEmpty ?? false) ? videoUrl! : url;
}

/// The stream to use for a given quality preference.
///
/// Shared by playback and downloads so an episode is saved at the same
/// quality it would have been watched at. Falls back to the source's own
/// ordering: its first entry is its own preference, which beats guessing from
/// labels it wrote for itself.
VideoStream pickPreferredStream(
  List<VideoStream> streams,
  String preferredQuality,
) {
  final wanted = preferredQuality.trim().toLowerCase();
  if (wanted.isEmpty || wanted == 'auto') return streams.first;
  for (final stream in streams) {
    if (stream.quality.toLowerCase().contains(wanted)) return stream;
  }
  return streams.first;
}
