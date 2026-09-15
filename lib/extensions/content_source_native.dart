import '../domain/entities/source/anime.dart';
import '../domain/repositories/content_source_repository.dart';
import 'host/host_api.g.dart';

/// [ContentSourceRepository] over the Kotlin host.
///
/// This is the `extensions/` boundary of INSTRUCTIONS.md §3: channel types
/// stop here and domain entities go up. Nothing above this file knows a
/// platform channel exists.
class ContentSourceNative implements ContentSourceRepository {
  ContentSourceNative({SourceApi? api}) : _api = api ?? SourceApi();

  final SourceApi _api;

  @override
  Future<AnimePage> popular(SourceRef source, {int page = 1}) =>
      _browse(source, BrowseMode.popular, page, '');

  @override
  Future<AnimePage> latest(SourceRef source, {int page = 1}) =>
      _browse(source, BrowseMode.latest, page, '');

  @override
  Future<AnimePage> search(SourceRef source, String query, {int page = 1}) =>
      _browse(source, BrowseMode.search, page, query);

  Future<AnimePage> _browse(
    SourceRef source,
    BrowseMode mode,
    int page,
    String query,
  ) async {
    final result = await _api.browse(
      source.packageName,
      source.className,
      mode,
      page,
      query,
    );
    if (!result.ok) throw _failure(source, result.error);
    return AnimePage(
      items: result.items
          .whereType<AnimeItem>()
          .map((i) => _toAnime(i, source))
          .toList(),
      hasNextPage: result.hasNextPage,
    );
  }

  @override
  Future<Anime> details(SourceRef source, String animeUrl) async {
    final result = await _api.animeDetails(
      source.packageName,
      source.className,
      animeUrl,
    );
    final anime = result.anime;
    if (!result.ok || anime == null) throw _failure(source, result.error);
    // Sources sometimes return details without echoing the url back.
    return _toAnime(anime, source, fallbackUrl: animeUrl);
  }

  @override
  Future<List<Episode>> episodes(SourceRef source, String animeUrl) async {
    final result = await _api.episodes(
      source.packageName,
      source.className,
      animeUrl,
    );
    if (!result.ok) throw _failure(source, result.error);
    return result.items.whereType<EpisodeItem>().map((e) {
      return Episode(
        url: e.url,
        name: e.name,
        number: e.episodeNumber,
        uploadedAt: e.dateUpload > 0
            ? DateTime.fromMillisecondsSinceEpoch(e.dateUpload)
            : null,
        scanlator: (e.scanlator?.isEmpty ?? true) ? null : e.scanlator,
      );
    }).toList();
  }

  @override
  Future<List<VideoStream>> videos(SourceRef source, String episodeUrl) async {
    final result = await _api.videos(
      source.packageName,
      source.className,
      episodeUrl,
    );
    if (!result.ok) throw _failure(source, result.error);
    final streams = result.items.whereType<VideoItem>().map((v) {
      return VideoStream(
        url: v.url,
        quality: v.quality,
        videoUrl: v.videoUrl,
        headers: {
          for (final e in v.headers.entries)
            if (e.key != null && e.value != null) e.key!: e.value!,
        },
        subtitleUrls: v.subtitleUrls.whereType<String>().toList(),
        audioUrls: v.audioUrls.whereType<String>().toList(),
      );
    }).toList();

    if (streams.isEmpty) {
      throw SourceFailure(
        SourceFailureKind.empty,
        '${source.sourceName} returned no playable streams for this episode.',
        sourceName: source.sourceName,
      );
    }
    return streams;
  }

  @override
  Future<void> invalidate() => _api.clearSourceCache();

  Anime _toAnime(AnimeItem item, SourceRef source, {String? fallbackUrl}) =>
      Anime(
        url: item.url.isEmpty ? (fallbackUrl ?? '') : item.url,
        title: item.title,
        source: source,
        thumbnailUrl: (item.thumbnailUrl?.isEmpty ?? true)
            ? null
            : item.thumbnailUrl,
        description: (item.description?.isEmpty ?? true)
            ? null
            : item.description,
        author: (item.author?.isEmpty ?? true) ? null : item.author,
        genre: (item.genre?.isEmpty ?? true) ? null : item.genre,
        status: AnimeStatus.fromCode(item.status),
      );

  /// Turns a host error string into something a person can act on. The raw
  /// text is kept for the less recognisable cases rather than replaced with
  /// something vague.
  SourceFailure _failure(SourceRef source, String? raw) {
    final text = raw ?? 'unknown error';
    final name = source.sourceName.isEmpty ? 'The source' : source.sourceName;

    if (text.contains('SSLHandshakeException') ||
        text.contains('CertPathValidator') ||
        text.contains('Trust anchor')) {
      return SourceFailure(
        SourceFailureKind.network,
        "$name's certificate was not accepted by this device. Something "
            'between the app and the source is presenting its own '
            'certificate, or the source is using one this device does not '
            'trust.',
        sourceName: source.sourceName,
      );
    }
    if (text.contains('UnknownHostException') ||
        text.contains('ConnectException') ||
        text.contains('SocketTimeout')) {
      return SourceFailure(
        SourceFailureKind.network,
        '$name could not be reached. Check your connection.',
        sourceName: source.sourceName,
      );
    }
    if (text.contains('ClassNotFoundException') ||
        text.contains('NoClassDefFoundError') ||
        text.contains('no APK for')) {
      return SourceFailure(
        SourceFailureKind.notLoaded,
        '$name could not be loaded. It may need updating for this version '
            'of Mimasu.',
        sourceName: source.sourceName,
      );
    }
    return SourceFailure(
      SourceFailureKind.sourceThrew,
      '$name failed: $text',
      sourceName: source.sourceName,
    );
  }
}
