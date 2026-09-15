import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/source/anime.dart';
import '../../domain/entities/source/source_setting.dart';
import '../../domain/repositories/content_source_repository.dart';

enum SourceSettingsStatus { loading, ready, failure }

class SourceSettingsState {
  const SourceSettingsState({
    required this.source,
    this.status = SourceSettingsStatus.loading,
    this.settings = const [],
    this.error,
  });

  final SourceRef source;
  final SourceSettingsStatus status;
  final List<SourceSetting> settings;
  final String? error;

  /// A source that declares nothing is the normal case, not a failure.
  bool get hasNone =>
      status == SourceSettingsStatus.ready && settings.isEmpty;

  SourceSettingsState copyWith({
    SourceSettingsStatus? status,
    List<SourceSetting>? settings,
    String? error,
    bool clearError = false,
  }) => SourceSettingsState(
    source: source,
    status: status ?? this.status,
    settings: settings ?? this.settings,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Settings an extension declared for itself (INSTRUCTIONS.md §5.6).
class SourceSettingsCubit extends Cubit<SourceSettingsState> {
  SourceSettingsCubit(this._content, SourceRef source)
    : super(SourceSettingsState(source: source));

  final ContentSourceRepository _content;

  Future<void> load() async {
    emit(state.copyWith(status: SourceSettingsStatus.loading, clearError: true));
    try {
      final settings = await _content.preferences(state.source);
      emit(
        state.copyWith(
          status: SourceSettingsStatus.ready,
          settings: settings,
        ),
      );
    } on SourceFailure catch (e) {
      emit(state.copyWith(status: SourceSettingsStatus.failure, error: e.message));
    }
  }

  /// Writes, then reloads from the source rather than patching state locally.
  ///
  /// An extension can change what it offers in response to a setting — a
  /// server choice that reveals further options, say — so the truth is
  /// whatever it reports next, not what was just sent.
  Future<void> set(SourceSetting setting, String value) async {
    await _content.setPreference(state.source, setting.key, value);
    await load();
  }
}
