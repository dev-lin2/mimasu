import 'package:get_it/get_it.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/repositories/extension_repository_impl.dart';
import '../../data/storage/app_prefs.dart';
import '../../data/repositories/extension_manager_impl.dart';
import '../../data/storage/download_store.dart';
import '../../data/storage/library_store.dart';
import '../../data/storage/progress_store.dart';
import '../../data/storage/repo_store.dart';
import '../../data/storage/trust_store.dart';
import '../../domain/repositories/content_source_repository.dart';
import '../../domain/repositories/download_repository.dart';
import '../../extensions/download_native.dart';
import '../../extensions/content_source_native.dart';
import '../../domain/repositories/extension_manager.dart';
import '../../domain/repositories/extension_repository.dart';
import '../services/http/repo_index_fetcher.dart';

final locator = GetIt.instance;

Future<void> configureDependencies() async {
  final (store, prefs, trust, library, progress, downloads) =
      await _openStorage();

  locator
    ..registerLazySingleton<RepoIndexFetcher>(DioRepoIndexFetcher.new)
    ..registerLazySingleton<RepoStore>(() => store)
    ..registerLazySingleton<AppPrefs>(() => prefs)
    ..registerLazySingleton<TrustStore>(() => trust)
    ..registerLazySingleton<LibraryStore>(() => library)
    ..registerLazySingleton<ProgressStore>(() => progress)
    ..registerLazySingleton<DownloadStore>(() => downloads)
    ..registerLazySingleton<DownloadRepository>(
      () => DownloadNative(locator<DownloadStore>()),
    )
    ..registerLazySingleton<ContentSourceRepository>(ContentSourceNative.new)
    ..registerLazySingleton<ExtensionManager>(
      () => ExtensionManagerImpl(trustStore: locator<TrustStore>()),
    )
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
Future<
  (
    RepoStore,
    AppPrefs,
    TrustStore,
    LibraryStore,
    ProgressStore,
    DownloadStore,
  )
>
_openStorage() async {
  try {
    final dir = await getApplicationSupportDirectory();
    Hive.init(dir.path);
    return (
      await HiveRepoStore.open(),
      await HiveAppPrefs.open(),
      await HiveTrustStore.open(),
      await HiveLibraryStore.open(),
      await HiveProgressStore.open(),
      await HiveDownloadStore.open(),
    );
  } catch (_) {
    return (
      InMemoryRepoStore(),
      InMemoryAppPrefs(),
      InMemoryTrustStore(),
      InMemoryLibraryStore(),
      InMemoryProgressStore(),
      InMemoryDownloadStore(),
    );
  }
}
