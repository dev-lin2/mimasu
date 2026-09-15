import 'package:hive_ce/hive.dart';

import '../../domain/entities/downloads/download_record.dart';

/// Persistence for download metadata.
///
/// Keyed per record because downloads are added and removed one at a time,
/// unlike the library, which is rewritten as a list.
abstract interface class DownloadStore {
  Future<List<DownloadRecord>> load();
  Future<void> put(DownloadRecord record);
  Future<void> remove(String id);
}

class HiveDownloadStore implements DownloadStore {
  HiveDownloadStore(this._box);

  static const boxName = 'downloads';

  final Box<dynamic> _box;

  static Future<HiveDownloadStore> open() async =>
      HiveDownloadStore(await Hive.openBox<dynamic>(boxName));

  @override
  Future<List<DownloadRecord>> load() async {
    final out = <DownloadRecord>[];
    for (final key in _box.keys) {
      final raw = _box.get(key);
      if (raw is! Map) continue;
      final record = DownloadRecord.fromJson(raw);
      if (record != null) out.add(record);
    }
    out.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    return out;
  }

  @override
  Future<void> put(DownloadRecord record) =>
      _box.put(record.id, record.toJson());

  @override
  Future<void> remove(String id) => _box.delete(id);
}

/// Used by tests, and as a fallback if Hive cannot be opened.
class InMemoryDownloadStore implements DownloadStore {
  InMemoryDownloadStore([List<DownloadRecord>? initial])
    : _records = {for (final r in initial ?? const []) r.id: r};

  final Map<String, DownloadRecord> _records;

  @override
  Future<List<DownloadRecord>> load() async =>
      _records.values.toList()
        ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

  @override
  Future<void> put(DownloadRecord record) async => _records[record.id] = record;

  @override
  Future<void> remove(String id) async => _records.remove(id);
}
