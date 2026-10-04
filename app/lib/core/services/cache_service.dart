import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Cache local léger (JSON dans SharedPreferences) pour afficher les dernières données
/// connues quand la connexion est lente ou coupée.
class CacheService {
  CacheService(this._prefs);
  final SharedPreferences _prefs;

  static const _prefix = 'cache:';

  Future<void> put(String key, Object? value) async {
    await _prefs.setString('$_prefix$key', jsonEncode({'t': DateTime.now().toIso8601String(), 'v': value}));
  }

  T? get<T>(String key) {
    final s = _prefs.getString('$_prefix$key');
    if (s == null) return null;
    try {
      final decoded = jsonDecode(s) as Map<String, dynamic>;
      return decoded['v'] as T?;
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) => _prefs.remove('$_prefix$key');

  Future<void> clearAll() async {
    for (final k in _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await _prefs.remove(k);
    }
  }

  SharedPreferences get prefs => _prefs;
}
