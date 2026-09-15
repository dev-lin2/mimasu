import 'package:hive_ce/hive.dart';

import '../../domain/entities/library/library_entry.dart';

/// Persistence for saved series.
///
/// An interface so cubit tests never touch Hive (INSTRUCTIONS.md §11, §16).
abstract interface class LibraryStore {
  Future<List<LibraryEntry>> load();
  Future<void> save(List<LibraryEntry> entries);
}

class HiveLibraryStore implements LibraryStore {
  HiveLibraryStore(this._box);

  static const boxName = 'library';
  static const _key = 'entries';

  final Box<dynamic> _box;

  static Future<HiveLibraryStore> open() async =>
      HiveLibraryStore(await Hive.openBox<dynamic>(boxName));

  @override
  Future<List<LibraryEntry>> load() async {
    final raw = _box.get(_key);
    if (raw is! List) return [];
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(LibraryEntry.fromJson)
        .whereType<LibraryEntry>()
        .toList();
  }

  @override
  Future<void> save(List<LibraryEntry> entries) =>
      _box.put(_key, entries.map((e) => e.toJson()).toList());
}

/// Used by tests, and as a fallback if Hive cannot be opened.
class InMemoryLibraryStore implements LibraryStore {
  InMemoryLibraryStore([List<LibraryEntry>? initial]) : _entries = [...?initial];

  List<LibraryEntry> _entries;

  @override
  Future<List<LibraryEntry>> load() async => List.unmodifiable(_entries);

  @override
  Future<void> save(List<LibraryEntry> entries) async => _entries = [...entries];
}
