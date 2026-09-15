/// How far into an episode the user got.
///
/// Kept per episode rather than per series: sources renumber and reorder, and
/// an episode url is the only identifier that stays meaningful between the
/// list and the player.
class WatchProgress {
  const WatchProgress({
    required this.animeId,
    required this.episodeUrl,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  final String animeId;
  final String episodeUrl;
  final Duration position;

  /// Zero while the player is still working it out. Treated as "unknown"
  /// rather than "instant", which is why [finished] checks it.
  final Duration duration;

  final DateTime updatedAt;

  String get key => '$animeId|$episodeUrl';

  /// The last stretch of an episode is credits, so requiring 100% would mean
  /// almost nothing ever counted as watched.
  static const _finishedFraction = 0.9;

  /// Below this, the user has effectively not started: offering to resume
  /// twenty seconds in is worse than just starting over.
  static const startedThreshold = Duration(seconds: 30);

  bool get finished =>
      duration > Duration.zero &&
      position.inMilliseconds >= duration.inMilliseconds * _finishedFraction;

  bool get started => position >= startedThreshold && !finished;

  /// What the player should seek to. Never a resume point for something
  /// finished — that would make a rewatch start at the credits.
  Duration? get resumeAt => started ? position : null;

  double get fraction => duration <= Duration.zero
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
    'animeId': animeId,
    'episodeUrl': episodeUrl,
    'positionMs': position.inMilliseconds,
    'durationMs': duration.inMilliseconds,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static WatchProgress? fromJson(Map<dynamic, dynamic> json) {
    final animeId = json['animeId'];
    final episodeUrl = json['episodeUrl'];
    if (animeId is! String || episodeUrl is! String) return null;
    return WatchProgress(
      animeId: animeId,
      episodeUrl: episodeUrl,
      position: Duration(
        milliseconds: (json['positionMs'] as num?)?.toInt() ?? 0,
      ),
      duration: Duration(
        milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
      ),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
