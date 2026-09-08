import 'package:hive_ce/hive.dart';

/// Small app-level flags. Deliberately separate from the repository store so
/// a corrupt repository list cannot take the first-run flag with it.
abstract interface class AppPrefs {
  bool get onboardingSeen;
  Future<void> setOnboardingSeen();
}

class HiveAppPrefs implements AppPrefs {
  HiveAppPrefs(this._box);

  static const boxName = 'app_prefs';
  static const _onboardingSeen = 'onboardingSeen';

  final Box<dynamic> _box;

  static Future<HiveAppPrefs> open() async =>
      HiveAppPrefs(await Hive.openBox<dynamic>(boxName));

  @override
  bool get onboardingSeen => _box.get(_onboardingSeen) == true;

  @override
  Future<void> setOnboardingSeen() => _box.put(_onboardingSeen, true);
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
}
