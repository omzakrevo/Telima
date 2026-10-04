import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/env.dart';
import 'config/theme.dart';
import 'core/services/push_service.dart';
import 'providers/core_providers.dart';
import 'routes/app_router.dart';
import 'screens/common/system_screens.dart';
import 'widgets/common.dart';
import 'widgets/update_gate.dart';

class TelimaApp extends ConsumerWidget {
  const TelimaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Env.isConfigured) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const ConfigMissingScreen(),
      );
    }
    final router = ref.watch(routerProvider);
    // Notification touchée : ouvre la page correspondante
    SystemNotifications.onOpen = (route) => router.push(route);
    WidgetsBinding.instance.addPostFrameCallback((_) => SystemNotifications.flushPending());
    // Démarre la file hors-ligne (rejoue les opérations en attente au retour du réseau)
    ref.watch(offlineQueueProvider);
    return MaterialApp.router(
      title: 'Telima',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      scaffoldMessengerKey: ref.watch(messengerKeyProvider),
      routerConfig: router,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => UpdateGate(
        child: Column(children: [
          const OfflineBanner(),
          Expanded(child: child ?? const SizedBox()),
        ]),
      ),
    );
  }
}
