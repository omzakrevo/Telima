import 'dart:math';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Compte les visiteurs du site web et de l'application (connectés ou non).
/// Un identifiant aléatoire est gardé sur l'appareil : aucune donnée personnelle n'est envoyée.
/// Appelé à chaque ouverture ; ne bloque jamais le démarrage et ignore toute erreur.
class VisitTracker {
  static const _key = 'telima_visitor_id';

  static String platform() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'autre',
    };
  }

  static String _newId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static Future<void> track(SharedPreferences prefs, SupabaseClient client) async {
    try {
      var id = prefs.getString(_key);
      if (id == null) {
        id = _newId();
        await prefs.setString(_key, id);
      }
      await client.rpc('track_visit', params: {'p_visitor': id, 'p_platform': platform()}).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }
}
