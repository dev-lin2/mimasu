import '../source/anime.dart';

/// What Mimasu remembers about a download that the host does not.
///
/// The split matters: the host owns transfer state, because a download
/// outlives the Flutter engine. This side owns everything needed to *show*
/// the download and to find it again later — which series, which episode —
/// none of which the host has any use for.
class DownloadRecord {
  const DownloadRecord({
    required this.id,
    required this.anime,
    required this.episodeUrl,
    required this.episodeName,
    required this.episodeNumber,
    required this.requestedAt,
  });

  final String id;
  final Anime anime;
  final String episodeUrl;
  final String episodeName;

  /// Negative when the source did not number it.
  final double episodeNumber;

  final DateTime requestedAt;

  /// Stable for a given episode, so asking twice is idempotent and the player
  /// can find the file without consulting the list.
  ///
  /// FNV-1a rather than a cryptographic hash: this is a filename, not a
  /// signature, and pulling in a hashing package for it would be silly.
  static String idFor(String animeId, String episodeUrl) {
    var hash = 0xcbf29ce484222325;
    for (final unit in '$animeId|$episodeUrl'.codeUnits) {
      hash ^= unit;
      hash = hash * 0x100000001b3;
    }
    // Dart ints are signed, so the top bit makes `toRadixString` emit a
    // leading minus — which then lands in a filename. Split into halves and
    // format each unsigned instead.
    final high = (hash >> 32) & 0xFFFFFFFF;
    final low = hash & 0xFFFFFFFF;
    return high.toRadixString(16).padLeft(8, '0') +
        low.toRadixString(16).padLeft(8, '0');
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'anime': anime.toJson(),
    'episodeUrl': episodeUrl,
    'episodeName': episodeName,
    'episodeNumber': episodeNumber,
    'requestedAt': requestedAt.toIso8601String(),
  };

  static DownloadRecord? fromJson(Map<dynamic, dynamic> json) {
    final id = json['id'];
    final episodeUrl = json['episodeUrl'];
    final rawAnime = json['anime'];
    if (id is! String || episodeUrl is! String || rawAnime is! Map) {
      return null;
    }
    final anime = Anime.fromJson(rawAnime);
    if (anime == null) return null;
    return DownloadRecord(
      id: id,
      anime: anime,
      episodeUrl: episodeUrl,
      episodeName: json['episodeName'] as String? ?? 'Episode',
      episodeNumber: (json['episodeNumber'] as num?)?.toDouble() ?? -1,
      requestedAt:
          DateTime.tryParse(json['requestedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// How a download is going, as the host reports it.
enum DownloadProgressState { queued, running, completed, failed, cancelled }

/// Why a download could not be started. Not a failure — the user asked at a
/// moment when it could not be honoured.
enum DownloadRefusalReason { metered, unsupportedFormat }

/// A record joined to its live state, which is what the list actually shows.
class DownloadItem {
  const DownloadItem({
    required this.record,
    required this.state,
    this.bytesDownloaded = 0,
    this.totalBytes = -1,
    this.filePath,
    this.error,
  });

  final DownloadRecord record;
  final DownloadProgressState state;
  final int bytesDownloaded;

  /// -1 when unknown, which is normal for a stream assembled from segments
  /// until enough of them have arrived to estimate from.
  final int totalBytes;

  final String? filePath;
  final String? error;

  bool get isFinished => state == DownloadProgressState.completed;
  bool get isActive =>
      state == DownloadProgressState.queued ||
      state == DownloadProgressState.running;

  /// Null when the total is not known yet — the bar should be indeterminate
  /// rather than pretending to sit at zero.
  double? get fraction => totalBytes > 0
      ? (bytesDownloaded / totalBytes).clamp(0.0, 1.0)
      : null;

  String get sizeLabel {
    if (bytesDownloaded <= 0) return '';
    final done = _mb(bytesDownloaded);
    return totalBytes > 0 ? '$done of ${_mb(totalBytes)}' : done;
  }

  static String _mb(int bytes) {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }
}
