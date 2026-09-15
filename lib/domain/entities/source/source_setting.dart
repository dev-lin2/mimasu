/// The kind of control a source asked for.
enum SourceSettingKind { list, multiList, toggle, text, unsupported }

/// One setting an extension declared for itself (INSTRUCTIONS.md §5.6).
///
/// Values are strings whatever the kind — a toggle carries "true" — because
/// the extension's own store decides the real type, and only the host knows
/// what that is.
class SourceSetting {
  const SourceSetting({
    required this.key,
    required this.kind,
    required this.title,
    this.summary,
    this.value,
    this.entries = const [],
    this.entryValues = const [],
  });

  final String key;
  final SourceSettingKind kind;
  final String title;
  final String? summary;

  /// Current value, or the extension's default when nothing is stored yet.
  final String? value;

  /// Labels shown to the user, and the values actually stored.
  final List<String> entries;
  final List<String> entryValues;

  bool get isOn => value?.toLowerCase() == 'true';

  /// Selected values for a multi-select, split on the separator both sides
  /// agree on.
  Set<String> get selected =>
      (value ?? '').split(separator).where((v) => v.isNotEmpty).toSet();

  /// The label matching the stored value, falling back to the raw value so a
  /// setting whose entries have changed still shows something truthful.
  String get displayValue {
    final index = entryValues.indexOf(value ?? '');
    if (index >= 0 && index < entries.length) return entries[index];
    return value ?? '';
  }

  /// Matches `PreferenceCollector.SEPARATOR` on the Kotlin side.
  static const separator = '';
}
