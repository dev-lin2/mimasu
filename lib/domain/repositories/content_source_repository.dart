import '../entities/source/anime.dart';

/// Why a source call failed. Typed so the UI names the source and the reason
/// rather than dumping an exception (INSTRUCTIONS.md §5.8).
enum SourceFailureKind {
  /// The extension is not installed, or its class could not be loaded.
  notLoaded,

  /// The source threw while building or parsing.
  sourceThrew,

  /// The site did not answer, or the device refused its certificate.
  network,

  /// Answered, but with no usable content.
  empty,
}

class SourceFailure implements Exception {
  const SourceFailure(this.kind, this.message, {this.sourceName});
  final SourceFailureKind kind;

  /// Already phrased for display, and names the source where it can.
  final String message;
  final String? sourceName;

  @override
  String toString() => 'SourceFailure($kind): $message';
}

class AnimePage {
  const AnimePage({required this.items, required this.hasNextPage});
  final List<Anime> items;
  final bool hasNextPage;
}

/// Reading content through an installed extension.
///
/// Implemented over the Kotlin host, but nothing above this interface knows
/// that — the hard rule of §3.
abstract interface class ContentSourceRepository {
  Future<AnimePage> popular(SourceRef source, {int page = 1});
  Future<AnimePage> latest(SourceRef source, {int page = 1});
  Future<AnimePage> search(SourceRef source, String query, {int page = 1});

  /// Fills in what the catalogue listing omitted.
  Future<Anime> details(SourceRef source, String animeUrl);

  Future<List<Episode>> episodes(SourceRef source, String animeUrl);

  /// Streams for one episode, best quality first is not guaranteed — the
  /// source decides the order.
  Future<List<VideoStream>> videos(SourceRef source, String episodeUrl);

  /// Drops cached source instances, after an extension is updated or removed.
  Future<void> invalidate();
}
