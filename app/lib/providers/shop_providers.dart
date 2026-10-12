import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/shop.dart';
import '../data/repositories/shop_repository.dart';
import 'core_providers.dart';
import 'gas_providers.dart' show myPositionProvider;

export 'restaurant_providers.dart' show pendingRouteProvider;

final shopRepositoryProvider =
    Provider((ref) => ShopRepository(ref.watch(supabaseProvider), ref.watch(storageServiceProvider)));

/// Page publique d'une boutique (lien partagé) : lisible sans compte.
final shopBySlugProvider =
    FutureProvider.autoDispose.family<Shop?, String>((ref, slug) => ref.watch(shopRepositoryProvider).bySlug(slug));

/// Boutiques autour de moi ; [query] = texte recherché (nom, type de boutique, quartier, article).
final nearbyShopsProvider = FutureProvider.autoDispose.family<List<Shop>, String>((ref, query) async {
  final pos = await ref.watch(myPositionProvider.future);
  final repo = ref.watch(shopRepositoryProvider);
  final near = await repo.search(lat: pos.latitude, lng: pos.longitude, query: query);
  // Rien dans le rayon par défaut : on élargit pour ne jamais afficher un écran vide.
  return near.isNotEmpty || query.trim().isNotEmpty ? near : repo.search(lat: pos.latitude, lng: pos.longitude, maxKm: 150);
});

/// Avis d'une boutique (productId null) ou d'un article : (shopId, productId).
final shopReviewsProvider = FutureProvider.autoDispose.family<List<ShopReview>, (String, String?)>(
    (ref, k) => ref.watch(shopRepositoryProvider).reviews(k.$1, productId: k.$2));

final myShopOrdersProvider = FutureProvider.autoDispose<List<ShopOrder>>((ref) => ref.watch(shopRepositoryProvider).myOrders());
final shopOrderProvider =
    FutureProvider.autoDispose.family<ShopOrder, String>((ref, id) => ref.watch(shopRepositoryProvider).order(id));

final myShopsProvider = FutureProvider.autoDispose<List<Shop>>((ref) => ref.watch(shopRepositoryProvider).myShops());
final myShopProvider =
    FutureProvider.autoDispose.family<Shop?, String>((ref, id) => ref.watch(shopRepositoryProvider).mine(id));
final shopOrdersProvider =
    FutureProvider.autoDispose.family<List<ShopOrder>, String>((ref, id) => ref.watch(shopRepositoryProvider).shopOrders(id));
final shopDashboardProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) => ref.watch(shopRepositoryProvider).dashboard(id));

/// Une ligne du panier : un article dans une taille et une couleur données.
class CartLine {
  const CartLine({required this.itemId, this.size, this.color, required this.qty});
  final String itemId;
  final String? size;
  final String? color;
  final int qty;

  String get key => CartState.keyOf(itemId, size, color);
  CartLine withQty(int q) => CartLine(itemId: itemId, size: size, color: color, qty: q);
}

/// Panier d'une seule boutique à la fois ; une même robe en taille M puis en taille L fait deux lignes.
class CartState {
  const CartState({this.shopId, this.lines = const {}});
  final String? shopId;
  final Map<String, CartLine> lines;

  static String keyOf(String itemId, String? size, String? color) => '$itemId|${size ?? ''}|${color ?? ''}';

  int get count => lines.values.fold(0, (a, l) => a + l.qty);
  bool get isEmpty => lines.isEmpty;

  /// Quantité totale d'un article, toutes tailles et couleurs confondues.
  int quantityOf(String itemId) => lines.values.where((l) => l.itemId == itemId).fold(0, (a, l) => a + l.qty);
  int lineQty(String key) => lines[key]?.qty ?? 0;

  int total(Shop r) {
    var sum = 0;
    for (final l in lines.values) {
      for (final i in r.items) {
        if (i.id == l.itemId) sum += i.price * l.qty;
      }
    }
    return sum;
  }

  /// Lignes envoyées au serveur (les prix sont relus côté serveur).
  List<Map<String, dynamic>> toOrderItems() => [
        for (final l in lines.values)
          {'item_id': l.itemId, 'qty': l.qty, if (l.size != null) 'size': l.size, if (l.color != null) 'color': l.color},
      ];
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  /// Ajoute une unité ; [maxQty] (stock) limite la quantité d'un même article, toutes variantes confondues.
  void add(String shopId, String itemId, {String? size, String? color, int? maxQty}) {
    final base = state.shopId == shopId ? state.lines : const <String, CartLine>{};
    final next = {...base};
    final key = CartState.keyOf(itemId, size, color);
    final current = next[key];
    final totalForItem = next.values.where((l) => l.itemId == itemId).fold(0, (a, l) => a + l.qty);
    if (maxQty != null && totalForItem >= maxQty) return;
    if (totalForItem >= 50) return;
    next[key] = (current ?? CartLine(itemId: itemId, size: size, color: color, qty: 0)).withQty((current?.qty ?? 0) + 1);
    state = CartState(shopId: shopId, lines: next);
  }

  void remove(String key) {
    final next = {...state.lines};
    final l = next[key];
    if (l == null) return;
    if (l.qty <= 1) {
      next.remove(key);
    } else {
      next[key] = l.withQty(l.qty - 1);
    }
    state = next.isEmpty ? const CartState() : CartState(shopId: state.shopId, lines: next);
  }

  /// Retire une unité de l'article, quelle que soit la variante (dernière ajoutée en premier).
  void removeOneOf(String itemId) {
    final keys = state.lines.keys.where((k) => state.lines[k]!.itemId == itemId).toList();
    if (keys.isNotEmpty) remove(keys.last);
  }

  void clear() => state = const CartState();
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);
