import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/extension/installed_extension.dart';
import '../../domain/entities/source/anime.dart';
import '../../domain/repositories/content_source_repository.dart';
import '../../domain/repositories/extension_manager.dart';

enum BrowseStatus { initial, loading, ready, failure, noSource }

/// Home and Search state. Everything shown here comes from one installed
/// source; there is no catalogue underneath (INSTRUCTIONS.md §1).
class BrowseState {
  const BrowseState({
    this.status = BrowseStatus.initial,
    this.sources = const [],
    this.selected,
    this.popular = const [],
    this.latest = const [],
    this.results = const [],
    this.query = '',
    this.error,
    this.searching = false,
  });

  final BrowseStatus status;

  /// Every usable source across installed extensions.
  final List<SourceRef> sources;
  final SourceRef? selected;

  final List<Anime> popular;
  final List<Anime> latest;

  /// Search results for [query].
  final List<Anime> results;
  final String query;

  /// Already phrased, and names the source.
  final String? error;
  final bool searching;

  bool get hasAnything => popular.isNotEmpty || latest.isNotEmpty;

  BrowseState copyWith({
    BrowseStatus? status,
    List<SourceRef>? sources,
    SourceRef? selected,
    List<Anime>? popular,
    List<Anime>? latest,
    List<Anime>? results,
    String? query,
    String? error,
    bool? searching,
    bool clearError = false,
  }) => BrowseState(
    status: status ?? this.status,
    sources: sources ?? this.sources,
    selected: selected ?? this.selected,
    popular: popular ?? this.popular,
    latest: latest ?? this.latest,
    results: results ?? this.results,
    query: query ?? this.query,
    error: clearError ? null : (error ?? this.error),
    searching: searching ?? this.searching,
  );
}

class BrowseCubit extends Cubit<BrowseState> {
  BrowseCubit(this._content, this._manager) : super(const BrowseState());

  final ContentSourceRepository _content;
  final ExtensionManager _manager;

  /// Finds usable sources, then loads the first one's shelves.
  Future<void> start() async {
    emit(state.copyWith(status: BrowseStatus.loading, clearError: true));

    final sources = await _usableSources();
    if (sources.isEmpty) {
      emit(const BrowseState(status: BrowseStatus.noSource));
      return;
    }

    final keep = sources.contains(state.selected) ? state.selected : sources.first;
    emit(state.copyWith(sources: sources, selected: keep));
    await load(keep!);
  }

  /// Re-reads installed extensions. Called when returning from Extensions,
  /// since installs complete in Android's UI.
  Future<void> refreshSources() async {
    final sources = await _usableSources();
    if (sources.isEmpty) {
      emit(const BrowseState(status: BrowseStatus.noSource));
      return;
    }
    final hadNone = state.selected == null;
    emit(state.copyWith(sources: sources));
    if (hadNone) await load(sources.first);
  }

  Future<void> select(SourceRef source) async {
    emit(
      state.copyWith(
        selected: source,
        popular: const [],
        latest: const [],
        clearError: true,
      ),
    );
    await load(source);
  }

  /// Loads both shelves. A source that cannot do "latest" is common and not
  /// an error, so a failure there is swallowed rather than shown.
  Future<void> load(SourceRef source) async {
    emit(state.copyWith(status: BrowseStatus.loading, clearError: true));
    try {
      final popular = await _content.popular(source);
      List<Anime> latest = const [];
      try {
        latest = (await _content.latest(source)).items;
      } on SourceFailure {
        // Not every source supports it.
      }
      emit(
        state.copyWith(
          status: BrowseStatus.ready,
          popular: popular.items,
          latest: latest,
        ),
      );
    } on SourceFailure catch (e) {
      emit(state.copyWith(status: BrowseStatus.failure, error: e.message));
    }
  }

  Future<void> search(String query) async {
    final source = state.selected;
    if (source == null || query.trim().isEmpty) return;

    emit(state.copyWith(searching: true, query: query, clearError: true));
    try {
      final page = await _content.search(source, query.trim());
      emit(state.copyWith(results: page.items, searching: false));
    } on SourceFailure catch (e) {
      emit(state.copyWith(searching: false, error: e.message));
    }
  }

  void clearSearch() =>
      emit(state.copyWith(results: const [], query: '', clearError: true));

  void dismissError() => emit(state.copyWith(clearError: true));

  /// One [SourceRef] per declared source class of every trusted anime
  /// extension. A factory extension exposes several, but the host resolves
  /// those itself, so one ref per class is the right granularity here.
  Future<List<SourceRef>> _usableSources() async {
    final installed = await _manager.installed();
    final out = <SourceRef>[];
    for (final e in installed.where((e) => e.isUsable)) {
      for (final className in e.sourceClasses) {
        out.add(
          SourceRef(
            packageName: e.packageName,
            className: className,
            sourceName: _prettyName(e),
          ),
        );
      }
    }
    return out;
  }

  /// Repository tooling prefixes labels with "Aniyomi: "; that is noise here.
  static String _prettyName(InstalledExtension e) {
    const prefixes = ['Aniyomi: ', 'Tachiyomi: ', 'Mimasu: '];
    for (final p in prefixes) {
      if (e.label.startsWith(p)) return e.label.substring(p.length);
    }
    return e.label;
  }
}
