import 'package:get_it/get_it.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/repositories/extension_repository_impl.dart';
import '../../data/storage/app_prefs.dart';
import '../../data/storage/repo_store.dart';
import '../../domain/repositories/extension_repository.dart';
import '../services/http/repo_index_fetcher.dart';

final locator = GetIt.instance;

Future<void> configureDependencies() async {
  final (store, prefs) = await _openStorage();

  locator
    ..registerLazySingleton<RepoIndexFetcher>(DioRepoIndexFetcher.new)
    ..registerLazySingleton<RepoStore>(() => store)
    ..registerLazySingleton<AppPrefs>(() => prefs)
    ..registerLazySingleton<ExtensionRepository>(
      () => ExtensionRepositoryImpl(
        fetcher: locator<RepoIndexFetcher>(),
        store: locator<RepoStore>(),
      ),
    );
}

/// Falls back to in-memory storage rather than failing to start. Losing the
/// saved repository list is a far better outcome than an app that will not
/// open, and the user can paste the URL again.
Future<(RepoStore, AppPrefs)> _openStorage() async {
  try {
    final dir = await getApplicationSupportDirectory();
    Hive.init(dir.path);
    return (await HiveRepoStore.open(), await HiveAppPrefs.open());
  } catch (_) {
    return (InMemoryRepoStore(), InMemoryAppPrefs());
  }
}
