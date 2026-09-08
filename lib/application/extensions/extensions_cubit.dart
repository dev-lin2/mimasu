import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/extension/extension_repo.dart';
import '../../domain/entities/extension/extension_repo_index.dart';
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

  List<ExtensionEntry> get supported =>
      index?.supported.toList() ?? const [];
  List<ExtensionEntry> get unsupported =>
      index?.unsupported.toList() ?? const [];

  ExtensionsState copyWith({
    ExtensionsStatus? status,
    List<ExtensionRepo>? repos,
    ExtensionRepo? selected,
    ExtensionRepoIndex? index,
    String? error,
    bool? busy,
    bool clearError = false,
    bool clearSelection = false,
  }) => ExtensionsState(
    status: status ?? this.status,
    repos: repos ?? this.repos,
    selected: clearSelection ? null : (selected ?? this.selected),
    index: clearSelection ? null : (index ?? this.index),
    error: clearError ? null : (error ?? this.error),
    busy: busy ?? this.busy,
  );
}

class ExtensionsCubit extends Cubit<ExtensionsState> {
  ExtensionsCubit(this._repository) : super(const ExtensionsState());

  final ExtensionRepository _repository;

  /// Loads saved repositories, and the catalogue of the most recent one.
  Future<void> start() async {
    emit(state.copyWith(status: ExtensionsStatus.loading, clearError: true));
    final repos = await _repository.savedRepos();
    if (repos.isEmpty) {
      emit(
        const ExtensionsState(status: ExtensionsStatus.ready, repos: []),
      );
      return;
    }
    emit(state.copyWith(status: ExtensionsStatus.ready, repos: repos));
    await select(repos.first);
  }

  Future<void> addRepo(String enteredUrl) async {
    emit(state.copyWith(busy: true, clearError: true));
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

  void dismissError() => emit(state.copyWith(clearError: true));
}
