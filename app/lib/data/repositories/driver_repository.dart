import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/cache_service.dart';
import '../../core/services/offline_queue.dart';
import '../models/delivery.dart';
import '../models/driver.dart';
import '../models/enums.dart';

/// Espace livreur : statut en ligne, demandes, étapes, preuve, revenus.
class DriverRepository {
  DriverRepository(this._client, this._cache, this._queue);
  final SupabaseClient _client;
  final CacheService _cache;
  final OfflineQueue _queue;

  String? get _uid => _client.auth.currentUser?.id;

  Future<DriverProfile?> myProfile() async {
    final row = await _client.from('drivers').select('*, vehicles(*)').eq('user_id', _uid!).maybeSingle();
    return row == null ? null : DriverProfile(row);
  }

  Future<void> submitApplication(Map<String, dynamic> data) =>
      _client.rpc('submit_driver_application', params: {'p': data});

  Future<DriverProfile> setOnline(bool online, {double? lat, double? lng}) async {
    final res = await _client.rpc('set_driver_online', params: {'p_online': online, 'p_lat': lat, 'p_lng': lng});
    return DriverProfile(Map<String, dynamic>.from(res as Map));
  }

  Future<List<AvailableRequest>> availableRequests() async {
    final res = await _client.rpc('get_available_requests_v2');
    return (res as List).map((r) => AvailableRequest(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<DriverProfile> setServices(List<String> services) async {
    final res = await _client.rpc('set_driver_services', params: {'p_services': services});
    return DriverProfile(Map<String, dynamic>.from(res as Map));
  }

  /// Course à faire : montant payé chez le commerçant (+ photo du ticket).
  Future<Delivery> setPurchase(String id, int amount, {String? shop, String? receiptPath}) async {
    final res = await _client.rpc('driver_set_purchase',
        params: {'p_delivery_id': id, 'p_amount': amount, 'p_shop': shop, 'p_receipt_path': receiptPath});
    return Delivery(Map<String, dynamic>.from(res as Map));
  }

  /// Le client a remboursé les achats en espèces.
  Future<void> settlePurchaseCash(String id) =>
      _client.rpc('settle_purchase', params: {'p_delivery_id': id, 'p_method': 'cash'});

  Future<Delivery> accept(String id) async {
    final res = await _client.rpc('accept_delivery', params: {'p_delivery_id': id});
    return Delivery(Map<String, dynamic>.from(res as Map));
  }

  Future<void> decline(String id) => _client.rpc('decline_delivery', params: {'p_delivery_id': id});

  /// Étape suivante. Hors connexion, l'étape est mise en file et rejouée automatiquement.
  /// Renvoie `true` si l'opération a été mise en attente.
  Future<bool> advance(String id, DeliveryStatus status, {double? lat, double? lng}) => _queue.runOrQueue(
        'driver_advance_status',
        {'p_delivery_id': id, 'p_status': status.name, 'p_lat': lat, 'p_lng': lng},
      );

  Future<void> release(String id, String reason) =>
      _client.rpc('driver_release_delivery', params: {'p_delivery_id': id, 'p_reason': reason});

  /// Position : seule la plus récente est conservée hors connexion.
  Future<void> sendLocation(double lat, double lng, {double? heading, double? speed}) => _queue.runOrQueue(
        'driver_update_location',
        {'p_lat': lat, 'p_lng': lng, 'p_heading': heading, 'p_speed': speed},
        dedupeKey: 'location',
      );

  /// Renvoie null si le code est incorrect.
  Future<Delivery?> complete(
    String id, {
    String? otp,
    String? receiverName,
    String? photoPath,
    String? signaturePath,
    double? lat,
    double? lng,
  }) async {
    final res = await _client.rpc('complete_delivery', params: {
      'p_delivery_id': id,
      'p_otp': otp,
      'p_receiver_name': receiverName,
      'p_photo_path': photoPath,
      'p_signature_path': signaturePath,
      'p_lat': lat,
      'p_lng': lng,
    });
    if (res == null || (res is Map && res['id'] == null)) return null;
    return Delivery(Map<String, dynamic>.from(res as Map));
  }

  Future<List<Delivery>> myCourses({bool activeOnly = false, int limit = 100}) async {
    final key = 'courses:$_uid:$activeOnly';
    try {
      var q = _client.from('deliveries').select().eq('driver_id', _uid!);
      if (activeOnly) q = q.not('status', 'in', '(completed,cancelled)');
      final rows = await q.order('created_at', ascending: false).limit(limit);
      await _cache.put(key, rows);
      return rows.map(Delivery.new).toList();
    } catch (e) {
      final cached = _cache.get<List>(key);
      if (cached != null) return cached.map((r) => Delivery(Map<String, dynamic>.from(r as Map))).toList();
      rethrow;
    }
  }

  Stream<List<Delivery>> watchActiveCourses() => _client
      .from('deliveries')
      .stream(primaryKey: ['id'])
      .eq('driver_id', _uid!)
      .map((rows) => rows.map(Delivery.new).where((d) => d.status.isActive).toList()
        ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder)));

  Future<DriverEarnings> earnings() async {
    try {
      final res = await _client.rpc('get_driver_earnings');
      await _cache.put('earnings:$_uid', res);
      return DriverEarnings(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      final cached = _cache.get<Map>('earnings:$_uid');
      if (cached != null) return DriverEarnings(Map<String, dynamic>.from(cached));
      rethrow;
    }
  }

  Future<List<Rating>> myRatings() async {
    final rows = await _client.from('ratings').select().eq('driver_id', _uid!).order('created_at', ascending: false).limit(50);
    return rows.map(Rating.new).toList();
  }
}
