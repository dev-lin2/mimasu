import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/extension/extension_repo.dart';
import '../../domain/entities/extension/extension_repo_index.dart';
import '../../domain/entities/extension/installed_extension.dart';
import '../../domain/repositories/extension_manager.dart';
import '../../domain/repositories/extension_repository.dart';

enum ExtensionsStatus { initial, loading, ready, failure }

/// State for the Extensions screen. Carries only domain types — no Dio, Hive
/// or channel types (INSTRUCTIONS.md section 3).
class ExtensionsState {
  const ExtensionsState({
    this.status = ExtensionsStatus.initial,
    this.repos = const [],
    this.selected,
    this.index,
    this.error,
    this.busy = false,
    this.installed = const [],
    this.pending,
    this.canInstall = true,
    this.notice,
    this.installingPackage,
  });

  final ExtensionsStatus status;
  final List<ExtensionRepo> repos;

  /// Which repository's catalogue is on screen.
  final ExtensionRepo? selected;
  final ExtensionRepoIndex? index;

  /// Already phrased for display.
  final String? error;

  /// An add or refresh is in flight. Distinct from [status] so the list stays
  /// visible while a new repository is being fetched.
  final bool busy;

  /// Extensions present on the device.
  final List<InstalledExtension> installed;

  /// A downloaded APK awaiting the user's trust decision (section 5.5).
  final PendingInstall? pending;

  /// Whether Android will let Mimasu install packages at all (section 5.4).
  final bool canInstall;

  /// Transient, non-error feedback.
  final String? notice;

  /// Package currently downloading, so its row can show progress.
  final String? installingPackage;

  List<ExtensionEntry> get supported => index?.supported.toList() ?? const [];
  List<ExtensionEntry> get unsupported =>
      index?.unsupported.toList() ?? const [];

  /// At least one anime extension installed and trusted — the precondition
  /// for browsing anything.
  bool get hasUsableSource => installed.any((e) => e.isUsable);

  Set<String> get installedPackages =>
      installed.map((e) => e.packageName).toSet();

  ExtensionsState copyWith({
    ExtensionsStatus? status,
    List<ExtensionRepo>? repos,
    ExtensionRepo? selected,
    ExtensionRepoIndex? index,
    String? error,
    bool? busy,
    List<InstalledExtension>? installed,
    PendingInstall? pending,
    bool? canInstall,
    String? notice,
    String? installingPackage,
    bool clearError = false,
    bool clearSelection = false,
    bool clearPending = false,
    bool clearNotice = false,
    bool clearInstalling = false,
  }) => ExtensionsState(
    status: status ?? this.status,
    repos: repos ?? this.repos,
    selected: clearSelection ? null : (selected ?? this.selected),
    index: clearSelection ? null : (index ?? this.index),
    error: clearError ? null : (error ?? this.error),
    busy: busy ?? this.busy,
    installed: installed ?? this.installed,
    pending: clearPending ? null : (pending ?? this.pending),
    canInstall: canInstall ?? this.canInstall,
    notice: clearNotice ? null : (notice ?? this.notice),
    installingPackage: clearInstalling
        ? null
        : (installingPackage ?? this.installingPackage),
  );
}

class ExtensionsCubit extends Cubit<ExtensionsState> {
  ExtensionsCubit(this._repository, this._manager)
    : super(const ExtensionsState());

  final ExtensionRepository _repository;
  final ExtensionManager _manager;

  /// Loads installed extensions and saved repositories.
  Future<void> start() async {
    emit(state.copyWith(status: ExtensionsStatus.loading, clearError: true));
    await refreshInstalled();

    final repos = await _repository.savedRepos();
    if (repos.isEmpty) {
      emit(state.copyWith(status: ExtensionsStatus.ready, repos: const []));
      return;
    }
    emit(state.copyWith(status: ExtensionsStatus.ready, repos: repos));
    await select(repos.first);
  }

  /// Re-reads what is on the device. Called after any install or removal, and
  /// on resume, since the user completes both in Android's own UI.
  Future<void> refreshInstalled() async {
    final installed = await _manager.installed();
    final canInstall = await _manager.canInstall();
    emit(state.copyWith(installed: installed, canInstall: canInstall));
  }

  Future<void> addRepo(String enteredUrl) async {
    emit(state.copyWith(busy: true, clearError: true, clearNotice: true));
    try {
      final result = await _repository.addRepo(enteredUrl);
      final repos = await _repository.savedRepos();
      emit(
        state.copyWith(
          status: ExtensionsStatus.ready,
          repos: repos,
          selected: result.repo,
          index: result.index,
          busy: false,
        ),
      );
    } on RepoFailure catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    }
  }

  Future<void> select(ExtensionRepo repo) async {
    emit(state.copyWith(busy: true, clearError: true));
    try {
      final result = await _repository.catalogue(repo);
      emit(
        state.copyWith(
          status: ExtensionsStatus.ready,
          selected: result.repo,
          index: result.index,
          busy: false,
        ),
      );
    } on RepoFailure catch (e) {
      emit(state.copyWith(busy: false, selected: repo, error: e.message));
    }
  }

  Future<void> removeRepo(ExtensionRepo repo) async {
    await _repository.removeRepo(repo.id);
    final repos = await _repository.savedRepos();
    final wasSelected = state.selected?.id == repo.id;
    emit(
      state.copyWith(
        repos: repos,
        clearSelection: wasSelected,
        clearError: true,
      ),
    );
    if (wasSelected && repos.isNotEmpty) await select(repos.first);
  }

  /// Downloads and inspects, then stops. Installing only proceeds once the
  /// user has seen the key (section 5.5).
  Future<void> beginInstall(ExtensionEntry entry) async {
    final repo = state.selected;
    if (repo == null) return;

    emit(
      state.copyWith(
        installingPackage: entry.packageName,
        clearError: true,
        clearNotice: true,
      ),
    );
    try {
      final pending = await _manager.beginInstall(
        entry,
        repositoryUrl: repo.url,
        declaredRepoKey: repo.signingKeySha256,
      );
      emit(state.copyWith(pending: pending, clearInstalling: true));

      // A key the user already trusts needs no second prompt.
      if (!pending.needsPrompt) await confirmInstall(trustKey: false);
    } on InstallFailure catch (e) {
      emit(state.copyWith(clearInstalling: true, error: e.message));
    }
  }

  /// Proceeds with an install the user has seen and accepted.
  Future<void> confirmInstall({required bool trustKey}) async {
    final pending = state.pending;
    if (pending == null) return;
    try {
      if (trustKey) await _manager.trustKey(pending.signatureSha256);
      await _manager.completeInstall(pending);
      emit(
        state.copyWith(
          clearPending: true,
          notice:
              'Android is installing ${pending.label}. '
              'It appears here once that finishes.',
        ),
      );
    } on InstallFailure catch (e) {
      emit(state.copyWith(clearPending: true, error: e.message));
    }
  }

  void cancelInstall() => emit(state.copyWith(clearPending: true));

  Future<void> removeExtension(InstalledExtension extension) async {
    await _manager.remove(extension.packageName);
    emit(
      state.copyWith(
        notice: 'Android is removing ${extension.label}.',
        clearError: true,
      ),
    );
  }

  /// Trusting an already-installed extension's key, from the installed list.
  Future<void> trustInstalled(InstalledExtension extension) async {
    await _manager.trustKey(extension.signatureSha256);
    await refreshInstalled();
  }

  void dismissError() => emit(state.copyWith(clearError: true));
  void dismissNotice() => emit(state.copyWith(clearNotice: true));
}
