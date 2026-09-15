import 'package:hive_ce/hive.dart';

/// Small app-level flags. Deliberately separate from the repository store so
/// a corrupt repository list cannot take the first-run flag with it.
///
/// Every setting here is read by something — a preference that changes nothing
/// is worse than no preference at all, because it tells the user a lie they
/// cannot check.
abstract interface class AppPrefs {
  bool get onboardingSeen;
  Future<void> setOnboardingSeen();

  /// Whether sources marked 18+ by their extension are offered.
  bool get showNsfwSources;
  Future<void> setShowNsfwSources(bool value);

  /// Matched loosely against each stream's quality label by the player.
  String get preferredQuality;
  Future<void> setPreferredQuality(String value);

  /// Matched loosely against each subtitle track's label.
  String get subtitleLanguage;
  Future<void> setSubtitleLanguage(String value);

  bool get downloadOnWifiOnly;
  Future<void> setDownloadOnWifiOnly(bool value);

  bool get deleteAfterWatching;
  Future<void> setDeleteAfterWatching(bool value);
}

/// The options the settings screen offers. `auto` means "whatever the source
/// listed first", which is its own preference order and usually sensible.
const kQualityOptions = <String>['Auto', '1080p', '720p', '480p', '360p'];

const kSubtitleLanguages = <String>[
  'English',
  'Spanish',
  'Portuguese',
  'Arabic',
  'French',
  'German',
  'Italian',
  'Off',
];

class HiveAppPrefs implements AppPrefs {
  HiveAppPrefs(this._box);

  static const boxName = 'app_prefs';
  static const _onboardingSeen = 'onboardingSeen';
  static const _nsfw = 'showNsfwSources';
  static const _quality = 'preferredQuality';
  static const _subtitles = 'subtitleLanguage';
  static const _wifiOnly = 'downloadOnWifiOnly';
  static const _deleteAfterWatching = 'deleteAfterWatching';

  final Box<dynamic> _box;

  static Future<HiveAppPrefs> open() async =>
      HiveAppPrefs(await Hive.openBox<dynamic>(boxName));

  bool _bool(String key, {required bool fallback}) {
    final raw = _box.get(key);
    return raw is bool ? raw : fallback;
  }

  String _string(String key, String fallback) {
    final raw = _box.get(key);
    return raw is String && raw.isNotEmpty ? raw : fallback;
  }

  @override
  bool get onboardingSeen => _box.get(_onboardingSeen) == true;

  @override
  Future<void> setOnboardingSeen() => _box.put(_onboardingSeen, true);

  @override
  bool get showNsfwSources => _bool(_nsfw, fallback: false);

  @override
  Future<void> setShowNsfwSources(bool value) => _box.put(_nsfw, value);

  @override
  String get preferredQuality => _string(_quality, kQualityOptions.first);

  @override
  Future<void> setPreferredQuality(String value) => _box.put(_quality, value);

  @override
  String get subtitleLanguage => _string(_subtitles, kSubtitleLanguages.first);

  @override
  Future<void> setSubtitleLanguage(String value) =>
      _box.put(_subtitles, value);

  @override
  bool get downloadOnWifiOnly => _bool(_wifiOnly, fallback: true);

  @override
  Future<void> setDownloadOnWifiOnly(bool value) => _box.put(_wifiOnly, value);

  @override
  bool get deleteAfterWatching => _bool(_deleteAfterWatching, fallback: false);

  @override
  Future<void> setDeleteAfterWatching(bool value) =>
      _box.put(_deleteAfterWatching, value);
}

/// Fallback when Hive cannot be opened, and the test double. Onboarding then
/// shows every launch, which is a better failure than not starting.
class InMemoryAppPrefs implements AppPrefs {
  InMemoryAppPrefs({bool seen = false}) : _seen = seen;

  bool _seen;

  @override
  bool get onboardingSeen => _seen;

  @override
  Future<void> setOnboardingSeen() async => _seen = true;

  @override
  bool showNsfwSources = false;

  @override
  Future<void> setShowNsfwSources(bool value) async => showNsfwSources = value;

  @override
  String preferredQuality = kQualityOptions.first;

  @override
  Future<void> setPreferredQuality(String value) async =>
      preferredQuality = value;

  @override
  String subtitleLanguage = kSubtitleLanguages.first;

  @override
  Future<void> setSubtitleLanguage(String value) async =>
      subtitleLanguage = value;

  @override
  bool downloadOnWifiOnly = true;

  @override
  Future<void> setDownloadOnWifiOnly(bool value) async =>
      downloadOnWifiOnly = value;

  @override
  bool deleteAfterWatching = false;

  @override
  Future<void> setDeleteAfterWatching(bool value) async =>
      deleteAfterWatching = value;
}
