import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/cache_service.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/location_service.dart';
import '../core/services/offline_queue.dart';
import '../core/services/payment/payment_provider.dart';
import '../core/services/push_service.dart';
import '../core/services/routing_service.dart';
import '../core/services/storage_service.dart';
import '../data/models/config_models.dart';
import '../data/repositories/admin_repository.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/communication_repository.dart';
import '../data/repositories/config_repository.dart';
import '../data/repositories/delivery_repository.dart';
import '../data/repositories/driver_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/wallet_repository.dart';

// ---- Infrastructure ----
final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Remplacé dans main() par l'instance réelle.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

final messengerKeyProvider = Provider((ref) => GlobalKey<ScaffoldMessengerState>());

final cacheProvider = Provider((ref) => CacheService(ref.watch(sharedPrefsProvider)));

final connectivityProvider = Provider((ref) {
  final s = ConnectivityService();
  ref.onDispose(s.dispose);
  return s;
});

final isOnlineProvider = StreamProvider<bool>((ref) => ref.watch(connectivityProvider).onStatusChange);

final offlineQueueProvider = Provider((ref) {
  final q = OfflineQueue(ref.watch(sharedPrefsProvider), ref.watch(supabaseProvider), ref.watch(connectivityProvider));
  ref.onDispose(q.dispose);
  return q;
});

final pendingOpsProvider = StreamProvider<int>((ref) async* {
  final q = ref.watch(offlineQueueProvider);
  yield q.length;
  yield* q.pendingCount;
});

final locationServiceProvider = Provider((ref) => LocationService());
final storageServiceProvider = Provider((ref) => StorageService(ref.watch(supabaseProvider)));

final inAppNotifierProvider = Provider((ref) => InAppNotifier(ref.watch(messengerKeyProvider)));
final pushServiceProvider = Provider((ref) {
  final s = PushService(ref.watch(supabaseProvider), ref.watch(inAppNotifierProvider));
  ref.onDispose(s.stop);
  return s;
});

// ---- Dépôts ----
final authRepositoryProvider = Provider((ref) => AuthRepository(ref.watch(supabaseProvider)));
final configRepositoryProvider = Provider((ref) => ConfigRepository(ref.watch(supabaseProvider), ref.watch(cacheProvider)));
final deliveryRepositoryProvider =
    Provider((ref) => DeliveryRepository(ref.watch(supabaseProvider), ref.watch(cacheProvider)));
final driverRepositoryProvider = Provider(
    (ref) => DriverRepository(ref.watch(supabaseProvider), ref.watch(cacheProvider), ref.watch(offlineQueueProvider)));
final walletRepositoryProvider = Provider((ref) => WalletRepository(ref.watch(supabaseProvider)));
final communicationRepositoryProvider = Provider((ref) => CommunicationRepository(ref.watch(supabaseProvider)));
final profileRepositoryProvider = Provider((ref) => ProfileRepository(ref.watch(supabaseProvider)));
final adminRepositoryProvider = Provider((ref) => AdminRepository(ref.watch(supabaseProvider)));

// ---- Configuration de la plateforme ----
final settingsProvider = FutureProvider<AppSettings>((ref) => ref.watch(configRepositoryProvider).settings());
final citiesProvider = FutureProvider<List<City>>((ref) => ref.watch(configRepositoryProvider).cities());

final routingServiceProvider = Provider<RoutingService>((ref) {
  final settings = ref.watch(settingsProvider).value;
  return OsrmRoutingService(avgSpeedKmh: settings?.avgSpeedKmh ?? 25);
});

final paymentGatewayProvider = Provider((ref) {
  final settings = ref.watch(settingsProvider).value;
  return PaymentGateway(ref.watch(supabaseProvider), simulation: settings?.paymentSimulation ?? true);
});
