import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/restaurant.dart';
import '../data/repositories/restaurant_repository.dart';
import 'core_providers.dart';
import 'gas_providers.dart' show myPositionProvider;

final restaurantRepositoryProvider =
    Provider((ref) => RestaurantRepository(ref.watch(supabaseProvider), ref.watch(storageServiceProvider)));

/// Page publique d'un restaurant (lien partagé) : lisible sans compte.
final restaurantBySlugProvider =
    FutureProvider.autoDispose.family<Restaurant?, String>((ref, slug) => ref.watch(restaurantRepositoryProvider).bySlug(slug));

/// Restaurants autour de moi ; [query] = texte recherché (nom, cuisine, quartier, plat).
final nearbyRestaurantsProvider = FutureProvider.autoDispose.family<List<Restaurant>, String>((ref, query) async {
  final pos = await ref.watch(myPositionProvider.future);
  final repo = ref.watch(restaurantRepositoryProvider);
  final near = await repo.search(lat: pos.latitude, lng: pos.longitude, query: query);
  // Rien dans le rayon par défaut : on élargit pour ne jamais afficher un écran vide.
  return near.isNotEmpty || query.trim().isNotEmpty ? near : repo.search(lat: pos.latitude, lng: pos.longitude, maxKm: 150);
});

final myRestaurantOrdersProvider = FutureProvider.autoDispose<List<RestaurantOrder>>((ref) => ref.watch(restaurantRepositoryProvider).myOrders());
final restaurantOrderProvider =
    FutureProvider.autoDispose.family<RestaurantOrder, String>((ref, id) => ref.watch(restaurantRepositoryProvider).order(id));

final myRestaurantsProvider = FutureProvider.autoDispose<List<Restaurant>>((ref) => ref.watch(restaurantRepositoryProvider).myRestaurants());
final myRestaurantProvider =
    FutureProvider.autoDispose.family<Restaurant?, String>((ref, id) => ref.watch(restaurantRepositoryProvider).mine(id));
final restaurantOrdersProvider =
    FutureProvider.autoDispose.family<List<RestaurantOrder>, String>((ref, id) => ref.watch(restaurantRepositoryProvider).restaurantOrders(id));
final restaurantDashboardProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) => ref.watch(restaurantRepositoryProvider).dashboard(id));

/// Page à rouvrir après connexion (un visiteur qui touche « Commander » sur un lien partagé).
class PendingRouteNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? route) => state = route;

  /// Renvoie la page en attente et l'efface.
  String? take() {
    final r = state;
    state = null;
    return r;
  }
}

final pendingRouteProvider = NotifierProvider<PendingRouteNotifier, String?>(PendingRouteNotifier.new);

/// Panier d'un seul restaurant à la fois : plat -> quantité.
class CartState {
  const CartState({this.restaurantId, this.qty = const {}});
  final String? restaurantId;
  final Map<String, int> qty;

  int get count => qty.values.fold(0, (a, b) => a + b);
  bool get isEmpty => qty.isEmpty;
  int quantityOf(String itemId) => qty[itemId] ?? 0;

  int total(Restaurant r) => r.items.fold(0, (s, i) => s + i.price * quantityOf(i.id));
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  void add(String restaurantId, String itemId) {
    final base = state.restaurantId == restaurantId ? state.qty : const <String, int>{};
    final next = {...base};
    next[itemId] = ((next[itemId] ?? 0) + 1).clamp(1, 50);
    state = CartState(restaurantId: restaurantId, qty: next);
  }

  void remove(String itemId) {
    final next = {...state.qty};
    final q = (next[itemId] ?? 0) - 1;
    if (q <= 0) {
      next.remove(itemId);
    } else {
      next[itemId] = q;
    }
    state = next.isEmpty ? const CartState() : CartState(restaurantId: state.restaurantId, qty: next);
  }

  void clear() => state = const CartState();
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);
