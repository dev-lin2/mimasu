import '../entities/downloads/download_record.dart';
import '../entities/source/anime.dart';

/// Refused before anything was attempted. Carries no stack trace on purpose:
/// nothing went wrong, the request just could not be honoured now.
class DownloadRefused implements Exception {
  const DownloadRefused(this.reason);

  final DownloadRefusalReason reason;

  String get message => switch (reason) {
    DownloadRefusalReason.metered =>
      'Not on Wi-Fi. Change this in Settings if you want to use mobile data.',
    DownloadRefusalReason.unsupportedFormat =>
      'This source streams in a format Mimasu cannot save offline yet.',
  };
}

/// Saving episodes for offline (INSTRUCTIONS.md §9).
abstract interface class DownloadRepository {
  /// Throws [DownloadRefused] when the request is declined rather than failed.
  Future<void> enqueue({
    required Anime anime,
    required Episode episode,
    required VideoStream stream,
    required bool wifiOnly,
  });

  Future<void> cancel(String id);

  /// Cancels if it is running, deletes the file, and forgets it.
  Future<void> remove(String id);

  /// Every download, live state joined to remembered metadata.
  Future<List<DownloadItem>> list();

  Future<bool> isMetered();
}
