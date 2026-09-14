import 'package:hive_ce/hive.dart';

/// Signing keys the user has agreed to trust (INSTRUCTIONS.md §5.5).
///
/// Mimasu ships **no** pre-trusted keys, because it endorses no repository.
/// Trust is per key, not per extension: approving one extension's signer means
/// every extension signed by that key is accepted, which is how a repository's
/// whole catalogue becomes usable after one decision.
abstract interface class TrustStore {
  Future<Set<String>> trustedKeys();
  Future<bool> isTrusted(String sha256);
  Future<void> trust(String sha256);

  /// Revoking unloads every extension under that key.
  Future<void> revoke(String sha256);
}

class HiveTrustStore implements TrustStore {
  HiveTrustStore(this._box);

  static const boxName = 'trusted_keys';
  static const _key = 'keys';

  final Box<dynamic> _box;

  static Future<HiveTrustStore> open() async =>
      HiveTrustStore(await Hive.openBox<dynamic>(boxName));

  Set<String> _read() {
    final raw = _box.get(_key);
    if (raw is! List) return <String>{};
    return raw.whereType<String>().map((k) => k.toLowerCase()).toSet();
  }

  @override
  Future<Set<String>> trustedKeys() async => _read();

  @override
  Future<bool> isTrusted(String sha256) async =>
      sha256.isNotEmpty && _read().contains(sha256.toLowerCase());

  @override
  Future<void> trust(String sha256) async {
    if (sha256.isEmpty) return;
    await _box.put(_key, {..._read(), sha256.toLowerCase()}.toList());
  }

  @override
  Future<void> revoke(String sha256) async {
    final keys = _read()..remove(sha256.toLowerCase());
    await _box.put(_key, keys.toList());
  }
}

class InMemoryTrustStore implements TrustStore {
  InMemoryTrustStore([Set<String>? initial])
    : _keys = {...?initial?.map((k) => k.toLowerCase())};

  final Set<String> _keys;

  @override
  Future<Set<String>> trustedKeys() async => {..._keys};

  @override
  Future<bool> isTrusted(String sha256) async =>
      sha256.isNotEmpty && _keys.contains(sha256.toLowerCase());

  @override
  Future<void> trust(String sha256) async {
    if (sha256.isNotEmpty) _keys.add(sha256.toLowerCase());
  }

  @override
  Future<void> revoke(String sha256) async => _keys.remove(sha256.toLowerCase());
}
