import 'package:hive_ce/hive.dart';

import '../../domain/entities/library/watch_progress.dart';

/// Persistence for how far into each episode the user got.
///
/// Keyed per record rather than held as one list: the player writes here every
/// few seconds during playback, and rewriting the whole history on each tick
/// would get worse the more the user has watched.
abstract interface class ProgressStore {
  Future<Map<String, WatchProgress>> loadAll();
  Future<void> put(WatchProgress progress);
  Future<void> remove(String key);
}

class HiveProgressStore implements ProgressStore {
  HiveProgressStore(this._box);

  static const boxName = 'watch_progress';

  final Box<dynamic> _box;

  static Future<HiveProgressStore> open() async =>
      HiveProgressStore(await Hive.openBox<dynamic>(boxName));

  @override
  Future<Map<String, WatchProgress>> loadAll() async {
    final out = <String, WatchProgress>{};
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is! Map) continue;
      final progress = WatchProgress.fromJson(raw);
      if (progress != null) out[progress.key] = progress;
    }
    return out;
  }

  @override
  Future<void> put(WatchProgress progress) =>
      _box.put(progress.key, progress.toJson());

  @override
  Future<void> remove(String key) => _box.delete(key);
}

/// Used by tests, and as a fallback if Hive cannot be opened.
class InMemoryProgressStore implements ProgressStore {
  InMemoryProgressStore([Map<String, WatchProgress>? initial])
    : _entries = {...?initial};

  final Map<String, WatchProgress> _entries;

  @override
  Future<Map<String, WatchProgress>> loadAll() async =>
      Map.unmodifiable(_entries);

  @override
  Future<void> put(WatchProgress progress) async =>
      _entries[progress.key] = progress;

  @override
  Future<void> remove(String key) async => _entries.remove(key);
}
