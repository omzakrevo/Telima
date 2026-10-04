import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/env.dart';
import 'core/services/push_service.dart';
import 'providers/core_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  final prefs = await SharedPreferences.getInstance();

  if (Env.isConfigured) {
    // Le démarrage ne doit jamais rester bloqué par une connexion lente :
    // au-delà de 8 s l'application s'affiche quand même et termine l'initialisation en arrière-plan.
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
      postgrestOptions: const PostgrestClientOptions(schema: Env.dbSchema),
      realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 5),
    ).timeout(const Duration(seconds: 8), onTimeout: () => Supabase.instance);
  }

  // Notifications système : canal « Alertes Telima » + autorisation demandée dès le premier lancement
  unawaited(SystemNotifications.init().catchError((Object e) => debugPrint('Notifications : $e')));

  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const TelimaApp(),
  ));
}
