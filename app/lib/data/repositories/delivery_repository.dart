import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/env.dart';

import '../../core/services/cache_service.dart';
import '../models/delivery.dart';
import '../models/enums.dart';
import '../models/wallet.dart';

/// Livraisons côté client / entreprise.
class DeliveryRepository {
  DeliveryRepository(this._client, this._cache);
  final SupabaseClient _client;
  final CacheService _cache;

  String? get _uid => _client.auth.currentUser?.id;

  Future<Delivery> create({
    required DeliveryPoint pickup,
    required DeliveryPoint dropoff,
    required PackageInfo package,
    required VehicleType vehicle,
    required PaymentMethod payment,
    double? routeKm,
    String? businessId,
  }) async {
    final res = await _client.rpc('create_delivery', params: {
      'p': {
        'pickup': pickup.toJson(),
        'dropoff': dropoff.toJson(),
        'package': package.toJson(),
        'vehicle_type': vehicle.name,
        'payment_method': payment.name,
        'route_km': routeKm,
        'business_id': businessId,
      }
    });
    return Delivery(Map<String, dynamic>.from(res as Map));
  }

  /// Prix d'une course à faire ou d'un trajet (transport de personnes).
  Future<Quote> quoteService(String kind, {required double fromLat, required double fromLng,
      required double toLat, required double toLng, VehicleType vehicle = VehicleType.moto, double? routeKm}) async {
    final res = await _client.rpc('quote_service', params: {
      'p_kind': kind, 'p_from_lat': fromLat, 'p_from_lng': fromLng, 'p_to_lat': toLat, 'p_to_lng': toLng,
      'p_vehicle': vehicle.name, 'p_route_km': routeKm,
    });
    return Quote(Map<String, dynamic>.from(res as Map));
  }

  /// Course à faire : le livreur achète (repas, médicaments…) puis livre à l'adresse.
  Future<Delivery> createErrand({required DeliveryPoint dropoff, required String items, required String category,
      int? budget, required PaymentMethod payment}) async {
    final res = await _client.rpc('create_errand', params: {
      'p': {'dropoff': dropoff.toJson(), 'items': items, 'category': category, 'budget': budget, 'payment_method': payment.name}
    });
    return Delivery(Map<String, dynamic>.from(res as Map));
  }

  /// Transport de personnes (moto-taxi ou voiture).
  Future<Delivery> createRide({required DeliveryPoint pickup, required DeliveryPoint dropoff, required VehicleType vehicle,
      required int passengers, required PaymentMethod payment, double? routeKm}) async {
    final res = await _client.rpc('create_ride', params: {
      'p': {'pickup': pickup.toJson(), 'dropoff': dropoff.toJson(), 'vehicle_type': vehicle.name,
            'passengers': passengers, 'payment_method': payment.name, 'route_km': routeKm}
    });
    return Delivery(Map<String, dynamic>.from(res as Map));
  }

  /// Rembourse les achats d'une course à faire avec le portefeuille.
  Future<void> settlePurchaseWithWallet(String id) =>
      _client.rpc('settle_purchase', params: {'p_delivery_id': id, 'p_method': 'wallet'});

  /// Plusieurs destinations depuis un même point de récupération.
  Future<List<Delivery>> createBatch({
    required DeliveryPoint pickup,
    required List<({DeliveryPoint dropoff, PackageInfo package})> stops,
    required VehicleType vehicle,
    required PaymentMethod payment,
    String? businessId,
  }) async {
    final res = await _client.rpc('create_delivery_batch', params: {
      'p': {
        'pickup': pickup.toJson(),
        'vehicle_type': vehicle.name,
        'payment_method': payment.name,
        'business_id': businessId,
        'stops': [
          for (final s in stops) {'dropoff': s.dropoff.toJson(), 'package': s.package.toJson()}
        ],
      }
    });
    return (res as List).map((r) => Delivery(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<List<Delivery>> myDeliveries({bool activeOnly = false, int limit = 50, String? businessId}) async {
    final key = 'deliveries:${businessId ?? _uid}:$activeOnly';
    try {
      var q = _client.from('deliveries').select();
      q = businessId != null ? q.eq('business_id', businessId) : q.eq('customer_id', _uid!);
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

  Future<List<Delivery>> businessDeliveriesBetween(String businessId, DateTime from, DateTime to) async {
    final rows = await _client
        .from('deliveries')
        .select()
        .eq('business_id', businessId)
        .gte('created_at', from.toUtc().toIso8601String())
        .lt('created_at', to.toUtc().toIso8601String())
        .order('created_at');
    return rows.map(Delivery.new).toList();
  }

  Future<Delivery?> byId(String id) async {
    try {
      final row = await _client.from('deliveries').select().eq('id', id).maybeSingle();
      if (row != null) await _cache.put('delivery:$id', row);
      return row == null ? null : Delivery(row);
    } catch (e) {
      final cached = _cache.get<Map>('delivery:$id');
      if (cached != null) return Delivery(Map<String, dynamic>.from(cached));
      rethrow;
    }
  }

  Future<List<Delivery>> batch(String batchId) async {
    final rows = await _client.from('deliveries').select().eq('batch_id', batchId).order('stop_order');
    return rows.map(Delivery.new).toList();
  }

  /// Suivi en temps réel d'une livraison (statut, livreur…).
  Stream<Delivery?> watch(String id) => _client
      .from('deliveries')
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .map((rows) => rows.isEmpty ? null : Delivery(rows.first));

  Future<List<StatusHistoryEntry>> history(String id) async {
    final rows = await _client.from('delivery_status_history').select().eq('delivery_id', id).order('created_at');
    return rows.map(StatusHistoryEntry.fromJson).toList();
  }

  Future<AssignedDriver?> driverInfo(String id) async {
    final res = await _client.rpc('get_delivery_driver', params: {'p_delivery_id': id});
    return res == null ? null : AssignedDriver(Map<String, dynamic>.from(res as Map));
  }

  Future<String?> otp(String id) async => (await _client.rpc('get_delivery_otp', params: {'p_delivery_id': id})) as String?;

  Future<Delivery> cancel(String id, String reason) async {
    final res = await _client.rpc('cancel_delivery', params: {'p_delivery_id': id, 'p_reason': reason});
    return Delivery(Map<String, dynamic>.from(res as Map));
  }

  Future<void> rate(String id, int stars, String? comment) =>
      _client.rpc('rate_delivery', params: {'p_delivery_id': id, 'p_stars': stars, 'p_comment': comment});

  Future<Map<String, dynamic>?> myRating(String id) =>
      _client.from('ratings').select().eq('delivery_id', id).maybeSingle();

  Future<Payment?> pendingPayment(String deliveryId) async {
    final row = await _client
        .from('payments')
        .select()
        .eq('delivery_id', deliveryId)
        .inFilter('status', ['pending', 'failed'])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : Payment(row);
  }

  Future<void> markPaymentFailed(String paymentId, String reason) =>
      _client.rpc('mark_payment_failed', params: {'p_payment_id': paymentId, 'p_reason': reason});

  Future<Delivery> changePaymentMethod(String deliveryId, PaymentMethod method) async {
    final res = await _client.rpc('change_payment_method', params: {'p_delivery_id': deliveryId, 'p_method': method.name});
    return Delivery(Map<String, dynamic>.from(res as Map));
  }

  /// Positions GPS du livreur en temps réel.
  RealtimeChannel subscribeLocations(String deliveryId, void Function(double lat, double lng) onPosition) {
    return _client
        .channel('locations:$deliveryId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: Env.dbSchema,
          table: 'delivery_locations',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'delivery_id', value: deliveryId),
          callback: (p) {
            final r = p.newRecord;
            onPosition((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble());
          },
        )
        .subscribe();
  }

  Future<Map<String, dynamic>?> lastLocation(String deliveryId) => _client
      .from('delivery_locations')
      .select('lat, lng, recorded_at')
      .eq('delivery_id', deliveryId)
      .order('recorded_at', ascending: false)
      .limit(1)
      .maybeSingle();

  Future<void> removeChannel(RealtimeChannel channel) => _client.removeChannel(channel);
}
