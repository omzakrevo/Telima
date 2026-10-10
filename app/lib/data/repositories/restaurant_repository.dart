import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/storage_service.dart';
import '../models/json.dart';
import '../models/restaurant.dart';

/// Module « Restaurants » : page publique, recherche, commandes, espace restaurateur.
class RestaurantRepository {
  RestaurantRepository(this._client, this._storage);
  final SupabaseClient _client;
  final StorageService _storage;

  static const _orderSelect = '*, restaurants(name, phone, slug, lat, lng), restaurant_order_items(*)';

  // ----- Clients (lecture publique, sans compte) -----

  /// Page d'un restaurant à partir de son lien. Renvoie null si le lien n'existe pas ou si le restaurant est suspendu.
  Future<Restaurant?> bySlug(String slug) async {
    final res = await _client.rpc('restaurant_by_slug', params: {'p_slug': slug});
    if (res == null) return null;
    return Restaurant(Map<String, dynamic>.from(res as Map));
  }

  Future<List<Restaurant>> search({
    required double lat,
    required double lng,
    double maxKm = 15,
    String? query,
    bool delivers = false,
  }) async {
    final rows = await _client.rpc('find_restaurants', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_max_km': maxKm,
      'p_query': (query ?? '').trim().isEmpty ? null : query!.trim(),
      'p_delivers': delivers,
      'p_limit': 60,
    });
    return [for (final r in (rows as List)) Restaurant(Map<String, dynamic>.from(r as Map))];
  }

  Future<({int fee, double km})> deliveryFee(String restaurantId, double lat, double lng) async {
    final r = Map<String, dynamic>.from(await _client.rpc('restaurant_delivery_fee',
        params: {'p_restaurant_id': restaurantId, 'p_lat': lat, 'p_lng': lng}) as Map);
    return (fee: asInt(r['fee']), km: asDouble(r['distance_km']) ?? 0);
  }

  /// [items] : plat -> quantité. Les prix sont relus par le serveur.
  Future<RestaurantOrder> createOrder({
    required String restaurantId,
    required String mode,
    required Map<String, int> items,
    String? note,
    Map<String, dynamic>? dropoff,
  }) async {
    final row = await _client.rpc('create_restaurant_order', params: {
      'p': {
        'restaurant_id': restaurantId,
        'mode': mode,
        'items': [for (final e in items.entries) {'item_id': e.key, 'qty': e.value}],
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'dropoff': dropoff,
        'payment_method': 'cash_on_delivery',
      },
    });
    return RestaurantOrder(Map<String, dynamic>.from(row as Map));
  }

  Future<RestaurantOrder> order(String id) async =>
      RestaurantOrder(await _client.from('restaurant_orders').select(_orderSelect).eq('id', id).single());

  Future<List<RestaurantOrder>> myOrders() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client.from('restaurant_orders').select(_orderSelect).eq('customer_id', uid).order('created_at', ascending: false).limit(60);
    return [for (final r in rows) RestaurantOrder(r)];
  }

  Future<void> cancelOrder(String id) => _client.rpc('cancel_restaurant_order', params: {'p_order_id': id});

  // ----- Restaurateur -----

  Future<List<Restaurant>> myRestaurants() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client.from('restaurants').select().eq('owner_id', uid).order('created_at');
    return [for (final r in rows) Restaurant(r)];
  }

  /// Restaurant et menu complets, y compris les plats épuisés (espace restaurateur).
  Future<Restaurant?> mine(String id) async {
    final row = await _client
        .from('restaurants')
        .select('*, categories:restaurant_menu_categories(*), items:restaurant_menu_items(*)')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final j = Map<String, dynamic>.from(row);
    int bySort(dynamic a, dynamic b) => asInt((a as Map)['sort_order']).compareTo(asInt((b as Map)['sort_order']));
    j['categories'] = [...(j['categories'] as List)]..sort(bySort);
    j['items'] = [...(j['items'] as List)]..sort(bySort);
    return Restaurant(j);
  }

  Future<Restaurant> create(Map<String, dynamic> data) async =>
      Restaurant(Map<String, dynamic>.from(await _client.rpc('register_restaurant', params: {'p': data}) as Map));

  Future<void> update(String id, Map<String, dynamic> data) => _client.from('restaurants').update(data).eq('id', id);

  Future<void> setAccepting(String id, bool value) => update(id, {'accepting_orders': value});

  Future<void> deleteRestaurant(String id) => _client.from('restaurants').delete().eq('id', id);

  /// Envoie une photo (logo, couverture, plat) dans le compartiment public et renvoie son chemin.
  Future<String?> pickAndUploadPhoto({double maxWidth = 1280}) async {
    final XFile? file = await _storage.pickImage(maxWidth: maxWidth);
    if (file == null) return null;
    return _storage.uploadXFile('restaurants', file);
  }

  Future<void> saveCategory({String? id, required String restaurantId, required String name, int sortOrder = 0}) async {
    final row = {'restaurant_id': restaurantId, 'name': name.trim(), 'sort_order': sortOrder};
    if (id == null) {
      await _client.from('restaurant_menu_categories').insert(row);
    } else {
      await _client.from('restaurant_menu_categories').update({'name': name.trim()}).eq('id', id);
    }
  }

  Future<void> deleteCategory(String id) => _client.from('restaurant_menu_categories').delete().eq('id', id);

  Future<void> saveItem({
    String? id,
    required String restaurantId,
    String? categoryId,
    required String name,
    String? description,
    required int price,
    String? photoPath,
    bool isAvailable = true,
    int sortOrder = 0,
  }) async {
    final row = {
      'restaurant_id': restaurantId,
      'category_id': categoryId,
      'name': name.trim(),
      'description': (description ?? '').trim().isEmpty ? null : description!.trim(),
      'price': price,
      'photo_path': photoPath,
      'is_available': isAvailable,
    };
    if (id == null) {
      await _client.from('restaurant_menu_items').insert({...row, 'sort_order': sortOrder});
    } else {
      await _client.from('restaurant_menu_items').update(row).eq('id', id);
    }
  }

  Future<void> setItemAvailable(String id, bool value) => _client.from('restaurant_menu_items').update({'is_available': value}).eq('id', id);

  Future<void> deleteItem(String id) => _client.from('restaurant_menu_items').delete().eq('id', id);

  Future<List<RestaurantOrder>> restaurantOrders(String restaurantId) async {
    final rows = await _client
        .from('restaurant_orders')
        .select(_orderSelect)
        .eq('restaurant_id', restaurantId)
        .order('created_at', ascending: false)
        .limit(80);
    return [for (final r in rows) RestaurantOrder(r)];
  }

  Future<void> orderAction(String id, String action, {String? reason}) =>
      _client.rpc('restaurant_order_action', params: {'p_order_id': id, 'p_action': action, 'p_reason': reason});

  Future<Json> dashboard(String restaurantId) async =>
      Map<String, dynamic>.from(await _client.rpc('restaurant_dashboard', params: {'p_restaurant_id': restaurantId}) as Map);

  // ----- Administration -----

  Future<List<Restaurant>> adminRestaurants() async {
    final rows = await _client.from('restaurants').select().order('created_at', ascending: false).limit(200);
    return [for (final r in rows) Restaurant(r)];
  }

  Future<void> adminSetStatus(String id, String status) =>
      _client.rpc('admin_set_restaurant_status', params: {'p_restaurant_id': id, 'p_status': status});
}
