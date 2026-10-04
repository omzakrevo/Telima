import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/errors.dart';
import 'connectivity_service.dart';

/// Conserve les opérations importantes (étapes de livraison, dernière position)
/// lorsqu'elles échouent faute de réseau, puis les rejoue automatiquement.
/// Les fonctions serveur concernées sont idempotentes.
class OfflineQueue {
  OfflineQueue(this._prefs, this._client, this._connectivity) {
    _sub = _connectivity.onStatusChange.listen((online) {
      if (online) flush();
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => flush());
  }

  final SharedPreferences _prefs;
  final SupabaseClient _client;
  final ConnectivityService _connectivity;
  late final StreamSubscription _sub;
  late final Timer _timer;
  bool _flushing = false;

  static const _key = 'offline_queue';
  final _pendingController = StreamController<int>.broadcast();
  Stream<int> get pendingCount => _pendingController.stream;

  List<Map<String, dynamic>> _read() {
    final s = _prefs.getString(_key);
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<Map<String, dynamic>> ops) async {
    await _prefs.setString(_key, jsonEncode(ops));
    _pendingController.add(ops.length);
  }

  int get length => _read().length;

  /// Exécute l'appel RPC ; en cas de coupure réseau, il est mis en file et `true` est renvoyé
  /// pour indiquer une mise en attente (l'interface peut afficher l'état de manière optimiste).
  Future<bool> runOrQueue(String fn, Map<String, dynamic> params, {String? dedupeKey}) async {
    try {
      await _client.rpc(fn, params: params).timeout(const Duration(seconds: 15));
      return false;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await enqueue(fn, params, dedupeKey: dedupeKey);
      return true;
    }
  }

  Future<void> enqueue(String fn, Map<String, dynamic> params, {String? dedupeKey}) async {
    final ops = _read();
    if (dedupeKey != null) ops.removeWhere((o) => o['dedupe'] == dedupeKey);
    ops.add({'fn': fn, 'params': params, 'dedupe': dedupeKey, 'at': DateTime.now().toIso8601String()});
    await _write(ops);
  }

  Future<void> flush() async {
    if (_flushing) return;
    final ops = _read();
    if (ops.isEmpty) return;
    _flushing = true;
    try {
      final remaining = <Map<String, dynamic>>[];
      for (var i = 0; i < ops.length; i++) {
        final op = ops[i];
        try {
          await _client
              .rpc(op['fn'] as String, params: Map<String, dynamic>.from(op['params'] as Map))
              .timeout(const Duration(seconds: 15));
        } catch (e) {
          if (isNetworkError(e)) {
            remaining.addAll(ops.sublist(i));
            break;
          }
          // erreur métier (étape déjà franchie, etc.) : l'opération est abandonnée
        }
      }
      await _write(remaining);
    } finally {
      _flushing = false;
    }
  }

  void dispose() {
    _sub.cancel();
    _timer.cancel();
    _pendingController.close();
  }
}
