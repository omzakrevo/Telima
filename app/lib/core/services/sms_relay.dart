import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../config/env.dart';

/// Relais des SMS Mobile Money reçus sur le téléphone administrateur (Android uniquement).
/// Le récepteur natif (SmsRelayReceiver) transmet chaque SMS Orange Money / Moov Money au serveur,
/// même application fermée. Les SMS ne valident jamais un paiement : ils aident l'administrateur à vérifier.
class SmsRelay {
  SmsRelay._();
  static const _channel = MethodChannel('telima/sms_relay');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static String get endpoint => '${Env.supabaseUrl}/functions/v1/telima-sms-relay';

  /// Enregistre la clé du téléphone et demande l'autorisation de recevoir les SMS.
  static Future<bool> enable(String token) async =>
      await _channel.invokeMethod<bool>('enable', {'token': token, 'url': endpoint}) ?? false;

  /// Désactive et renvoie la clé (pour la révoquer côté serveur).
  static Future<String?> disable() => _channel.invokeMethod<String>('disable');

  static Future<bool> requestPermission() async => await _channel.invokeMethod<bool>('requestPermission') ?? false;

  static Future<({bool enabled, bool granted})> status() async {
    if (!supported) return (enabled: false, granted: false);
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('status') ?? const {};
      return (enabled: m['enabled'] == true, granted: m['granted'] == true);
    } catch (_) {
      return (enabled: false, granted: false);
    }
  }

  /// Renvoie les SMS restés en attente (pas de réseau au moment de la réception).
  static Future<void> flush() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('flush');
    } catch (_) {}
  }
}
