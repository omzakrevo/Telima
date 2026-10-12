import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/storage_service.dart';
import '../models/json.dart';
import '../models/shop.dart';

/// Module « Boutiques » : page publique, recherche, commandes, espace commerçant.
class ShopRepository {
  ShopRepository(this._client, this._storage);
  final SupabaseClient _client;
  final StorageService _storage;

  static const _orderSelect = '*, shops(name, phone, slug, lat, lng), shop_order_items(*)';

  // ----- Clients (lecture publique, sans compte) -----

  /// Page d'une boutique à partir de son lien. Renvoie null si le lien n'existe pas ou si la boutique est suspendu.
  Future<Shop?> bySlug(String slug) async {
    final res = await _client.rpc('shop_by_slug', params: {'p_slug': slug});
    if (res == null) return null;
    return Shop(Map<String, dynamic>.from(res as Map));
  }

  Future<List<Shop>> search({
    required double lat,
    required double lng,
    double maxKm = 15,
    String? query,
    bool delivers = false,
  }) async {
    final rows = await _client.rpc('find_shops', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_max_km': maxKm,
      'p_query': (query ?? '').trim().isEmpty ? null : query!.trim(),
      'p_delivers': delivers,
      'p_limit': 60,
    });
    return [for (final r in (rows as List)) Shop(Map<String, dynamic>.from(r as Map))];
  }

  Future<({int fee, double km})> deliveryFee(String shopId, double lat, double lng) async {
    final r = Map<String, dynamic>.from(await _client.rpc('shop_delivery_fee',
        params: {'p_shop_id': shopId, 'p_lat': lat, 'p_lng': lng}) as Map);
    return (fee: asInt(r['fee']), km: asDouble(r['distance_km']) ?? 0);
  }

  /// [items] : lignes {item_id, qty, size?, color?} (voir CartState.toOrderItems). Les prix sont relus par le serveur.
  Future<ShopOrder> createOrder({
    required String shopId,
    required String mode,
    required List<Map<String, dynamic>> items,
    String? note,
    Map<String, dynamic>? dropoff,
  }) async {
    final row = await _client.rpc('create_shop_order', params: {
      'p': {
        'shop_id': shopId,
        'mode': mode,
        'items': items,
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'dropoff': dropoff,
        'payment_method': 'cash_on_delivery',
      },
    });
    return ShopOrder(Map<String, dynamic>.from(row as Map));
  }

  Future<ShopOrder> order(String id) async =>
      ShopOrder(await _client.from('shop_orders').select(_orderSelect).eq('id', id).single());

  Future<List<ShopOrder>> myOrders() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client.from('shop_orders').select(_orderSelect).eq('customer_id', uid).order('created_at', ascending: false).limit(60);
    return [for (final r in rows) ShopOrder(r)];
  }

  Future<void> cancelOrder(String id) => _client.rpc('cancel_shop_order', params: {'p_order_id': id});

  // ----- Commerçant -----

  Future<List<Shop>> myShops() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client.from('shops').select().eq('owner_id', uid).order('created_at');
    return [for (final r in rows) Shop(r)];
  }

  /// Boutique et catalogue complets, y compris les articles épuisés (espace commerçant).
  Future<Shop?> mine(String id) async {
    final row = await _client
        .from('shops')
        .select('*, categories:shop_categories(*), items:shop_products(*)')
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final j = Map<String, dynamic>.from(row);
    int bySort(dynamic a, dynamic b) => asInt((a as Map)['sort_order']).compareTo(asInt((b as Map)['sort_order']));
    j['categories'] = [...(j['categories'] as List)]..sort(bySort);
    j['items'] = [...(j['items'] as List)]..sort(bySort);
    return Shop(j);
  }

  Future<Shop> create(Map<String, dynamic> data) async =>
      Shop(Map<String, dynamic>.from(await _client.rpc('register_shop', params: {'p': data}) as Map));

  Future<void> update(String id, Map<String, dynamic> data) => _client.from('shops').update(data).eq('id', id);

  Future<void> setAccepting(String id, bool value) => update(id, {'accepting_orders': value});

  Future<void> deleteShop(String id) => _client.from('shops').delete().eq('id', id);

  /// Envoie une photo (logo, couverture, article) dans le compartiment public et renvoie son chemin.
  Future<String?> pickAndUploadPhoto({double maxWidth = 1280}) async {
    final XFile? file = await _storage.pickImage(maxWidth: maxWidth);
    if (file == null) return null;
    return _storage.uploadXFile('shops', file);
  }

  Future<void> saveCategory({String? id, required String shopId, required String name, int sortOrder = 0}) async {
    final row = {'shop_id': shopId, 'name': name.trim(), 'sort_order': sortOrder};
    if (id == null) {
      await _client.from('shop_categories').insert(row);
    } else {
      await _client.from('shop_categories').update({'name': name.trim()}).eq('id', id);
    }
  }

  Future<void> deleteCategory(String id) => _client.from('shop_categories').delete().eq('id', id);

  Future<void> saveItem({
    String? id,
    required String shopId,
    String? categoryId,
    required String name,
    String? description,
    required int price,
    String? photoPath,
    bool isAvailable = true,
    List<String> sizes = const [],
    List<String> colors = const [],
    int? stock,
    int sortOrder = 0,
  }) async {
    final row = {
      'shop_id': shopId,
      'category_id': categoryId,
      'name': name.trim(),
      'description': (description ?? '').trim().isEmpty ? null : description!.trim(),
      'price': price,
      'photo_path': photoPath,
      'is_available': isAvailable,
      'sizes': sizes,
      'colors': colors,
      'stock': stock,
    };
    if (id == null) {
      await _client.from('shop_products').insert({...row, 'sort_order': sortOrder});
    } else {
      await _client.from('shop_products').update(row).eq('id', id);
    }
  }

  Future<void> setItemAvailable(String id, bool value) => _client.from('shop_products').update({'is_available': value}).eq('id', id);

  /// Met à jour la quantité en stock (null = quantité non suivie).
  Future<void> setStock(String id, int? stock) => _client.from('shop_products').update({'stock': stock}).eq('id', id);

  Future<void> deleteItem(String id) => _client.from('shop_products').delete().eq('id', id);

  Future<List<ShopOrder>> shopOrders(String shopId) async {
    final rows = await _client
        .from('shop_orders')
        .select(_orderSelect)
        .eq('shop_id', shopId)
        .order('created_at', ascending: false)
        .limit(80);
    return [for (final r in rows) ShopOrder(r)];
  }

  Future<void> orderAction(String id, String action, {String? reason}) =>
      _client.rpc('shop_order_action', params: {'p_order_id': id, 'p_action': action, 'p_reason': reason});

  Future<Json> dashboard(String shopId) async =>
      Map<String, dynamic>.from(await _client.rpc('shop_dashboard', params: {'p_shop_id': shopId}) as Map);

  // ----- Administration -----

  Future<List<Shop>> adminShops() async {
    final rows = await _client.from('shops').select().order('created_at', ascending: false).limit(200);
    return [for (final r in rows) Shop(r)];
  }

  Future<void> adminSetStatus(String id, String status) =>
      _client.rpc('admin_set_shop_status', params: {'p_shop_id': id, 'p_status': status});
}
