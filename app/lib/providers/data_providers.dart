import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/config_models.dart';
import '../data/models/delivery.dart';
import '../data/models/driver.dart';
import '../data/models/wallet.dart';
import 'auth_providers.dart';
import 'core_providers.dart';

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// Livraisons en cours du client : cache local d'abord, puis mises à jour en temps réel.
final myActiveDeliveriesProvider = StreamProvider.autoDispose<List<Delivery>>((ref) async* {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    yield [];
    return;
  }
  final repo = ref.watch(deliveryRepositoryProvider);
  yield await repo.myDeliveries(activeOnly: true);
  final client = ref.watch(supabaseProvider);
  yield* client
      .from('deliveries')
      .stream(primaryKey: ['id'])
      .eq('customer_id', user.id)
      .order('created_at')
      .map((rows) => rows.map(Delivery.new).where((d) => d.status.isActive).toList().reversed.toList())
      .handleError((_) {});
});

final myDeliveriesProvider = FutureProvider.autoDispose<List<Delivery>>(
    (ref) => ref.watch(deliveryRepositoryProvider).myDeliveries(limit: 200));

final deliveryStreamProvider = StreamProvider.autoDispose.family<Delivery?, String>((ref, id) async* {
  final repo = ref.watch(deliveryRepositoryProvider);
  final initial = await repo.byId(id);
  yield initial;
  yield* repo.watch(id).handleError((_) {});
});

final deliveryHistoryProvider =
    FutureProvider.autoDispose.family<List<StatusHistoryEntry>, String>((ref, id) => ref.watch(deliveryRepositoryProvider).history(id));

final deliveryOtpProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, id) => ref.watch(deliveryRepositoryProvider).otp(id));

final batchProvider =
    FutureProvider.autoDispose.family<List<Delivery>, String>((ref, id) => ref.watch(deliveryRepositoryProvider).batch(id));

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------
final notificationsProvider = StreamProvider.autoDispose<List<AppNotification>>((ref) {
  if (ref.watch(currentUserProvider) == null) return Stream.value(const []);
  return ref.watch(communicationRepositoryProvider).watchNotifications();
});

final unreadCountProvider = Provider.autoDispose<int>(
    (ref) => ref.watch(notificationsProvider).value?.where((n) => !n.isRead).length ?? 0);

// ---------------------------------------------------------------------------
// Portefeuille (client et livreur)
// ---------------------------------------------------------------------------
final myWalletProvider = FutureProvider.autoDispose<Wallet?>((ref) => ref.watch(walletRepositoryProvider).myWallet());

final myWalletTransactionsProvider = FutureProvider.autoDispose<List<WalletTransaction>>((ref) async {
  final w = await ref.watch(myWalletProvider.future);
  if (w == null) return [];
  return ref.watch(walletRepositoryProvider).transactions(w.id);
});

final myWithdrawalsProvider =
    FutureProvider.autoDispose<List<Withdrawal>>((ref) => ref.watch(walletRepositoryProvider).myWithdrawals());

// ---------------------------------------------------------------------------
// Livreur
// ---------------------------------------------------------------------------
final myDriverProfileProvider =
    FutureProvider.autoDispose<DriverProfile?>((ref) => ref.watch(driverRepositoryProvider).myProfile());

final activeCoursesProvider = StreamProvider.autoDispose<List<Delivery>>((ref) async* {
  final repo = ref.watch(driverRepositoryProvider);
  yield await repo.myCourses(activeOnly: true);
  yield* repo.watchActiveCourses().handleError((_) {});
});

final driverEarningsProvider =
    FutureProvider.autoDispose<DriverEarnings>((ref) => ref.watch(driverRepositoryProvider).earnings());

final driverHistoryProvider =
    FutureProvider.autoDispose<List<Delivery>>((ref) => ref.watch(driverRepositoryProvider).myCourses(limit: 200));

final driverRatingsProvider = FutureProvider.autoDispose<List<Rating>>((ref) => ref.watch(driverRepositoryProvider).myRatings());

/// Demandes disponibles : rafraîchies toutes les 10 s et à chaque notification « nouvelle demande ».
final availableRequestsProvider = StreamProvider.autoDispose<List<AvailableRequest>>((ref) {
  final repo = ref.watch(driverRepositoryProvider);
  final controller = StreamController<List<AvailableRequest>>();
  var disposed = false;

  Future<void> load() async {
    try {
      final list = await repo.availableRequests();
      if (!disposed) controller.add(list);
    } catch (e, st) {
      if (!disposed) controller.addError(e, st);
    }
  }

  load();
  final timer = Timer.periodic(const Duration(seconds: 10), (_) => load());
  ref.listen(notificationsProvider, (prev, next) {
    final p = prev?.value?.firstOrNull?.id;
    final n = next.value?.firstOrNull;
    if (n != null && n.id != p && n.type == 'new_request') load();
  });
  ref.onDispose(() {
    disposed = true;
    timer.cancel();
    controller.close();
  });
  return controller.stream;
});

// ---------------------------------------------------------------------------
// Profil / entreprise
// ---------------------------------------------------------------------------
final myBusinessesProvider =
    FutureProvider.autoDispose<List<BusinessAccount>>((ref) => ref.watch(profileRepositoryProvider).myBusinesses());

final savedAddressesProvider = FutureProvider.autoDispose
    .family<List<SavedAddress>, String?>((ref, businessId) => ref.watch(profileRepositoryProvider).savedAddresses(businessId: businessId));

final mySupportRequestsProvider =
    FutureProvider.autoDispose<List<SupportRequest>>((ref) => ref.watch(communicationRepositoryProvider).mySupportRequests());
