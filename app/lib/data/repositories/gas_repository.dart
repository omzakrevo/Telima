import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/cache_service.dart';
import '../models/gas.dart';
import '../models/json.dart';

/// Module « Gaz & carburant » : recherche, signalements, commandes, espace vendeur.
class GasRepository {
  GasRepository(this._client, this._cache);
  final SupabaseClient _client;
  final CacheService _cache;

  static const _orderSelect = '*, places(name, phone, lat, lng), gas_order_items(*)';

  List<Place> _places(dynamic rows) =>
      [for (final r in (rows as List)) Place(Map<String, dynamic>.from(r as Map))];

  /// Points autour d'une position. Le dernier résultat est gardé en cache pour la faible connexion.
  Future<List<Place>> search({
    required double lat,
    required double lng,
    bool? stations,
    double maxKm = 15,
    String? brandId,
    double? size,
    bool onlyAvailable = false,
    bool delivers = false,
    String? query,
    bool useCache = true,
    int limit = 60,
  }) async {
    final cacheKey = 'places_${stations == null ? 'all' : stations ? 'fuel' : 'gas'}';
    try {
      final rows = await _client.rpc('search_places', params: {
        'p_lat': lat,
        'p_lng': lng,
        'p_kind': stations == null ? null : (stations ? 'fuel_station' : 'gas_point'),
        'p_max_km': maxKm,
        'p_brand': brandId,
        'p_size': size,
        'p_only_available': onlyAvailable,
        'p_delivers': delivers,
        'p_query': (query ?? '').trim().isEmpty ? null : query!.trim(),
        'p_limit': limit,
      });
      if (useCache && brandId == null && size == null && !onlyAvailable && !delivers && (query ?? '').isEmpty) {
        await _cache.put(cacheKey, rows);
      }
      return _places(rows);
    } catch (e) {
      final cached = useCache ? _cache.get<List>(cacheKey) : null;
      if (cached != null) return _places(cached);
      rethrow;
    }
  }

  Future<Place?> placeById(String id) async {
    final row = await _client.from('places').select('*, products:place_products(*, gas_brands(name)), fuels:place_fuels(*)').eq('id', id).maybeSingle();
    if (row == null) return null;
    final place = Place(Map<String, dynamic>.from(row));
    if (!place.isStation) await _applyPromos(place);
    return place;
  }

  /// Applique les promotions en cours aux produits (le serveur recalcule le prix à la commande).
  Future<void> _applyPromos(Place place) async {
    final promos = (await promotions(place.id)).where((p) => p.running).toList();
    for (final pr in place.products) {
      PlacePromo? best;
      for (final promo in promos.where((p) => p.productId == null || p.productId == pr.id)) {
        if (best == null || promo.priceFor(pr.price) < best.priceFor(pr.price)) best = promo;
      }
      if (best != null) {
        pr.promoPrice = best.priceFor(pr.price);
        pr.promoTitle = best.title;
      }
    }
    place.promoTitle = promos.isEmpty ? null : promos.first.title;
  }

  // ----- Avis -----

  Future<List<PlaceReview>> reviews(String placeId) async {
    final rows = await _client.rpc('place_reviews_list', params: {'p_place_id': placeId, 'p_limit': 40});
    return [for (final r in (rows as List)) PlaceReview(Map<String, dynamic>.from(r as Map))];
  }

  Future<void> reviewPlace(String placeId, int rating, String? comment) =>
      _client.rpc('review_place', params: {'p_place_id': placeId, 'p_rating': rating, 'p_comment': comment});

  Future<void> deleteMyReview(String placeId) => _client.rpc('delete_my_review', params: {'p_place_id': placeId});

  Future<List<Json>> adminReviews() async {
    final rows = await _client.from('place_reviews').select('*, places(name), users(full_name)').order('created_at', ascending: false).limit(100);
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  }

  Future<void> adminDeleteReview(String id) => _client.from('place_reviews').delete().eq('id', id);

  // ----- Favoris -----

  Future<List<Place>> favorites(double lat, double lng) async =>
      _places(await _client.rpc('favorite_places', params: {'p_lat': lat, 'p_lng': lng}));

  // ----- Promotions -----

  Future<List<PlacePromo>> promotions(String placeId) async {
    final rows = await _client.from('place_promotions').select().eq('place_id', placeId).order('ends_at', ascending: false);
    return [for (final r in rows) PlacePromo(r)];
  }

  Future<void> savePromo({String? id, required String placeId, String? productId, required String title, required bool percent,
      required int value, required DateTime endsAt, bool active = true}) async {
    final row = {
      'place_id': placeId,
      'product_id': productId,
      'title': title,
      'discount_type': percent ? 'percent' : 'amount',
      'discount_value': value,
      'ends_at': endsAt.toUtc().toIso8601String(),
      'is_active': active,
    };
    if (id == null) {
      await _client.from('place_promotions').insert(row);
    } else {
      await _client.from('place_promotions').update(row).eq('id', id);
    }
  }

  Future<void> deletePromo(String id) => _client.from('place_promotions').delete().eq('id', id);

  // ----- Abonnements vendeur -----

  Future<List<VendorPlan>> plans() async {
    final rows = await _client.from('vendor_plans').select().eq('is_active', true).order('sort_order');
    return [for (final r in rows) VendorPlan(r)];
  }

  Future<List<VendorSubscription>> subscriptions(String placeId) async {
    final rows = await _client.from('vendor_subscriptions').select().eq('place_id', placeId).order('created_at', ascending: false).limit(20);
    return [for (final r in rows) VendorSubscription(r)];
  }

  Future<void> requestSubscription(String placeId, String plan, int months, String paymentRef) => _client.rpc('vendor_request_subscription',
      params: {'p_place_id': placeId, 'p_plan': plan, 'p_months': months, 'p_payment_ref': paymentRef});

  Future<List<VendorSubscription>> adminSubscriptions() async {
    final rows = await _client.from('vendor_subscriptions').select('*, places(name)').order('created_at', ascending: false).limit(100);
    return [for (final r in rows) VendorSubscription(r)];
  }

  Future<void> adminDecideSubscription(String id, bool approve) =>
      _client.rpc('admin_decide_subscription', params: {'p_id': id, 'p_approve': approve});

  Future<void> adminSavePlan(String code, {required int price, required int? maxProducts, required int? maxPromotions}) =>
      _client.from('vendor_plans').update({'price_monthly': price, 'max_products': maxProducts, 'max_promotions': maxPromotions}).eq('code', code);

  Future<List<GasBrand>> brands() async {
    final rows = await _client.from('gas_brands').select().eq('is_active', true).order('name');
    return [for (final r in rows) GasBrand(r)];
  }

  Future<Map<String, dynamic>> report(String placeId, String target, {Availability? value, String? productId, String? note}) async {
    final res = await _client.rpc('report_place', params: {
      'p_place_id': placeId,
      'p_target': target,
      'p_value': value?.name,
      'p_product_id': productId,
      'p_note': note,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Set<String>> favoriteIds() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return {};
    final rows = await _client.from('place_favorites').select('place_id').eq('user_id', uid);
    return {for (final r in rows) '${r['place_id']}'};
  }

  Future<bool> toggleFavorite(String placeId) async => (await _client.rpc('toggle_favorite_place', params: {'p_place_id': placeId})) == true;

  Future<({int fee, double km})> deliveryFee(String placeId, double lat, double lng) async {
    final r = Map<String, dynamic>.from(await _client.rpc('gas_delivery_fee', params: {'p_place_id': placeId, 'p_lat': lat, 'p_lng': lng}) as Map);
    return (fee: asInt(r['fee']), km: asDouble(r['distance_km']) ?? 0);
  }

  Future<GasOrder> createOrder({
    required String placeId,
    required String mode,
    required Map<String, int> items, // produit -> quantité
    Map<String, dynamic>? dropoff,
  }) async {
    final res = await _client.rpc('create_gas_order', params: {
      'p': {
        'place_id': placeId,
        'mode': mode,
        'payment_method': 'cash_on_delivery',
        'items': [for (final e in items.entries) {'product_id': e.key, 'qty': e.value}],
        'dropoff': dropoff,
      }
    });
    return order('${(res as Map)['id']}');
  }

  Future<GasOrder> order(String id) async => GasOrder(await _client.from('gas_orders').select(_orderSelect).eq('id', id).single());

  Future<List<GasOrder>> myOrders() async {
    final uid = _client.auth.currentUser?.id;
    final rows = await _client.from('gas_orders').select(_orderSelect).eq('customer_id', uid ?? '').order('created_at', ascending: false).limit(50);
    return [for (final r in rows) GasOrder(r)];
  }

  Future<void> cancelOrder(String id) => _client.rpc('cancel_gas_order', params: {'p_order_id': id});

  // ----- Espace vendeur -----

  Future<List<Place>> myPlaces() async {
    final uid = _client.auth.currentUser?.id;
    final rows = await _client.from('places').select('*, products:place_products(*, gas_brands(name)), fuels:place_fuels(*)').eq('owner_id', uid ?? '').order('created_at');
    return _places(rows);
  }

  Future<void> registerPlace(Map<String, dynamic> data) => _client.rpc('vendor_register_place', params: {'p': data});

  Future<void> updatePlace(String id, Map<String, dynamic> data) => _client.from('places').update(data).eq('id', id);

  Future<void> saveProduct({String? id, required String placeId, String? brandId, required double sizeKg, required int price,
      required bool trackStock, required int stock, Availability? availability}) async {
    final row = {
      'place_id': placeId,
      'brand_id': brandId,
      'size_kg': sizeKg,
      'price': price,
      'track_stock': trackStock,
      'stock_available': trackStock ? stock : 0,
      if (!trackStock && availability != null) 'availability': availability.name,
    };
    if (id == null) {
      await _client.from('place_products').insert(row);
    } else {
      await _client.from('place_products').update(row).eq('id', id);
    }
  }

  Future<void> deleteProduct(String id) => _client.from('place_products').delete().eq('id', id);

  Future<void> setFuel(String placeId, String fuel, Availability a, {int? price}) => _client.from('place_fuels').upsert({
        'place_id': placeId,
        'fuel': fuel,
        'availability': a.name,
        'price': price,
        'confirmed_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

  Future<List<GasOrder>> placeOrders(String placeId) async {
    final rows = await _client.from('gas_orders').select(_orderSelect).eq('place_id', placeId).order('created_at', ascending: false).limit(60);
    return [for (final r in rows) GasOrder(r)];
  }

  Future<void> orderAction(String id, String action, {String? reason}) =>
      _client.rpc('gas_order_action', params: {'p_order_id': id, 'p_action': action, 'p_reason': reason});

  Future<Json> dashboard(String placeId) async => Map<String, dynamic>.from(await _client.rpc('vendor_dashboard', params: {'p_place_id': placeId}) as Map);

  // ----- Administration -----

  Future<List<Place>> adminPlaces({String? status}) async {
    var q = _client.from('places').select('*, products:place_products(*, gas_brands(name)), fuels:place_fuels(*)');
    if (status != null) q = q.eq('status', status);
    return _places(await q.order('created_at', ascending: false).limit(200));
  }

  Future<void> adminSetStatus(String id, String status) => _client.rpc('admin_set_place_status', params: {'p_place_id': id, 'p_status': status});

  Future<void> adminSavePlace(Map<String, dynamic> row, {String? id}) async {
    if (id == null) {
      await _client.from('places').insert(row);
    } else {
      await _client.from('places').update(row).eq('id', id);
    }
  }

  Future<void> adminSaveBrand(String name, {String? id, bool active = true}) async {
    if (id == null) {
      await _client.from('gas_brands').insert({'name': name});
    } else {
      await _client.from('gas_brands').update({'name': name, 'is_active': active}).eq('id', id);
    }
  }

  Future<List<Json>> adminReports() async {
    final rows = await _client.from('place_reports').select('*, places(name), users(full_name)').order('created_at', ascending: false).limit(100);
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  }
}
