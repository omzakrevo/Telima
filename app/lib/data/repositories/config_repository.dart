import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/cache_service.dart';
import '../models/config_models.dart';
import '../models/delivery.dart';
import '../models/enums.dart';

/// Villes, zones, tarifs et paramètres (lecture publique, avec cache hors-ligne).
class ConfigRepository {
  ConfigRepository(this._client, this._cache);
  final SupabaseClient _client;
  final CacheService _cache;

  Future<List<City>> cities({bool includeInactive = false}) async {
    try {
      var q = _client.from('cities').select();
      if (!includeInactive) q = q.eq('is_active', true);
      final rows = await q.order('name');
      if (!includeInactive) await _cache.put('cities', rows);
      return rows.map(City.new).toList();
    } catch (e) {
      final cached = _cache.get<List>('cities');
      if (cached != null && !includeInactive) {
        return cached.map((r) => City(Map<String, dynamic>.from(r as Map))).toList();
      }
      rethrow;
    }
  }

  Future<AppSettings> settings() async {
    try {
      final rows = await _client.from('app_settings').select('key, value');
      final map = {for (final r in rows) r['key'] as String: r['value']};
      await _cache.put('settings', map);
      return AppSettings(map);
    } catch (e) {
      final cached = _cache.get<Map>('settings');
      if (cached != null) return AppSettings(Map<String, dynamic>.from(cached));
      return AppSettings({});
    }
  }

  Future<Quote> quote({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    VehicleType? vehicle,
    PackageSize size = PackageSize.petit,
    bool fragile = false,
    double? weightKg,
    PackageCategory category = PackageCategory.petit_colis,
    double? routeKm,
    bool extraStop = false,
  }) async {
    final res = await _client.rpc('quote_delivery', params: {
      'p_pickup_lat': pickupLat,
      'p_pickup_lng': pickupLng,
      'p_dropoff_lat': dropoffLat,
      'p_dropoff_lng': dropoffLng,
      'p_vehicle_type': vehicle?.name,
      'p_size': size.name,
      'p_fragile': fragile,
      'p_weight_kg': weightKg,
      'p_category': category.name,
      'p_route_km': routeKm,
      'p_is_extra_stop': extraStop,
    });
    return Quote(Map<String, dynamic>.from(res as Map));
  }

  // ---- Administration (RLS : administrateur) ----
  Future<List<DeliveryZone>> zones({String? cityId}) async {
    var q = _client.from('delivery_zones').select();
    if (cityId != null) q = q.eq('city_id', cityId);
    final rows = await q.order('name');
    return rows.map(DeliveryZone.new).toList();
  }

  Future<List<PricingRule>> pricingRules() async {
    final rows = await _client.from('pricing_rules').select().order('vehicle_type');
    return rows.map(PricingRule.new).toList();
  }

  Future<void> upsertCity(Map<String, dynamic> data) => _client.from('cities').upsert(data);
  Future<void> upsertZone(Map<String, dynamic> data) => _client.from('delivery_zones').upsert(data);
  Future<void> deleteZone(String id) => _client.from('delivery_zones').delete().eq('id', id);
  Future<void> upsertPricing(Map<String, dynamic> data) => _client.from('pricing_rules').upsert(data);
  Future<void> deletePricing(String id) => _client.from('pricing_rules').delete().eq('id', id);
  Future<void> updateSetting(String key, Object value) =>
      _client.from('app_settings').update({'value': value, 'updated_by': _client.auth.currentUser?.id}).eq('key', key);
}
