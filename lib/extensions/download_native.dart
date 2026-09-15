import '../data/storage/download_store.dart';
import '../domain/entities/downloads/download_record.dart';
import '../domain/entities/source/anime.dart';
import '../domain/repositories/download_repository.dart';
import 'host/host_api.g.dart' as host;

/// [DownloadRepository] over the platform download service.
///
/// This is the only place that knows the host's wire types exist
/// (INSTRUCTIONS.md §5): everything above it sees domain entities.
class DownloadNative implements DownloadRepository {
  DownloadNative(this._store, [host.DownloadHostApi? api])
    : _api = api ?? host.DownloadHostApi();

  final host.DownloadHostApi _api;
  final DownloadStore _store;

  @override
  Future<void> enqueue({
    required Anime anime,
    required Episode episode,
    required VideoStream stream,
    required bool wifiOnly,
  }) async {
    final id = DownloadRecord.idFor(anime.id, episode.url);

    final accepted = await _api.enqueueDownload(
      host.DownloadRequest(
        id: id,
        url: stream.playbackUrl,
        headers: stream.headers,
        fileName: id,
        title: anime.title,
        subtitle: episode.name,
      ),
      wifiOnly,
    );

    if (!accepted.accepted) {
      throw DownloadRefused(_reason(accepted.refusal));
    }

    // Written only after the host agrees to take it, so a refused request
    // leaves no orphan record behind.
    await _store.put(
      DownloadRecord(
        id: id,
        anime: anime,
        episodeUrl: episode.url,
        episodeName: episode.name,
        episodeNumber: episode.number,
        requestedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> cancel(String id) => _api.cancelDownload(id);

  @override
  Future<void> remove(String id) async {
    await _api.removeDownload(id);
    await _store.remove(id);
  }

  @override
  Future<bool> isMetered() => _api.isMeteredConnection();

  @override
  Future<List<DownloadItem>> list() async {
    final records = await _store.load();
    final statuses = <String, host.DownloadStatus>{
      for (final s in await _api.listDownloads()) s.id: s,
    };

    return [
      for (final record in records)
        if (statuses[record.id] case final status?)
          DownloadItem(
            record: record,
            state: _state(status.state),
            bytesDownloaded: status.bytesDownloaded,
            totalBytes: status.totalBytes,
            filePath: status.filePath,
            error: status.error,
          )
        else
          // The host has forgotten it — its index was lost, or the file was
          // cleared. Reporting that plainly beats showing a download that
          // will never move.
          DownloadItem(
            record: record,
            state: DownloadProgressState.failed,
            error: 'This download is no longer on the device.',
          ),
    ];
  }

  DownloadProgressState _state(host.DownloadState state) => switch (state) {
    host.DownloadState.queued => DownloadProgressState.queued,
    host.DownloadState.running => DownloadProgressState.running,
    host.DownloadState.completed => DownloadProgressState.completed,
    host.DownloadState.failed => DownloadProgressState.failed,
    host.DownloadState.cancelled => DownloadProgressState.cancelled,
  };

  DownloadRefusalReason _reason(host.DownloadRefusal refusal) =>
      switch (refusal) {
        host.DownloadRefusal.metered => DownloadRefusalReason.metered,
        host.DownloadRefusal.unsupportedFormat ||
        host.DownloadRefusal.none => DownloadRefusalReason.unsupportedFormat,
      };
}
