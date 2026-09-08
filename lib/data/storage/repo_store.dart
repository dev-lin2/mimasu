import 'package:hive_ce/hive.dart';

import '../../domain/entities/extension/extension_repo.dart';

/// Persistence for the list of repositories the user has added.
///
/// An interface so cubit and repository tests never touch Hive
/// (INSTRUCTIONS.md 11, 16).
abstract interface class RepoStore {
  Future<List<ExtensionRepo>> load();
  Future<void> save(List<ExtensionRepo> repos);
}

class HiveRepoStore implements RepoStore {
  HiveRepoStore(this._box);

  static const boxName = 'extension_repos';
  static const _key = 'repos';

  final Box<dynamic> _box;

  static Future<HiveRepoStore> open() async =>
      HiveRepoStore(await Hive.openBox<dynamic>(boxName));

  @override
  Future<List<ExtensionRepo>> load() async {
    final raw = _box.get(_key);
    if (raw is! List) return [];
    // A corrupt record is skipped, not fatal: the app must still start.
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map(ExtensionRepo.fromJson)
        .whereType<ExtensionRepo>()
        .toList();
  }

  @override
  Future<void> save(List<ExtensionRepo> repos) =>
      _box.put(_key, repos.map((r) => r.toJson()).toList());
}

/// Used by tests, and as a fallback if Hive cannot be opened.
class InMemoryRepoStore implements RepoStore {
  InMemoryRepoStore([List<ExtensionRepo>? initial])
    : _repos = [...?initial];

  List<ExtensionRepo> _repos;

  @override
  Future<List<ExtensionRepo>> load() async => List.unmodifiable(_repos);

  @override
  Future<void> save(List<ExtensionRepo> repos) async => _repos = [...repos];
}
