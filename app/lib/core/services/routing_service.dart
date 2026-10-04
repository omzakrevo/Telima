import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../config/env.dart';
import '../utils/geo.dart';

class RouteResult {
  RouteResult({required this.points, required this.distanceKm, required this.durationMin, this.isEstimate = false});
  final List<LatLng> points;
  final double distanceKm;
  final double durationMin;

  /// Vrai si l'itinéraire est une estimation (ligne droite) faute de service.
  final bool isEstimate;
}

/// Calcul d'itinéraire. Implémentation par défaut : OSRM, avec repli en ligne droite.
abstract class RoutingService {
  Future<RouteResult> route(List<LatLng> waypoints);
}

class OsrmRoutingService implements RoutingService {
  OsrmRoutingService({this.avgSpeedKmh = 25, this.roadFactor = 1.3});
  final double avgSpeedKmh;
  final double roadFactor;

  // Petit cache mémoire pour éviter les requêtes répétées sur le même trajet.
  final _cache = <String, RouteResult>{};

  @override
  Future<RouteResult> route(List<LatLng> waypoints) async {
    final key = waypoints.map((p) => '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}').join('|');
    final cached = _cache[key];
    if (cached != null) return cached;
    try {
      final coords = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
      final uri = Uri.parse('${Env.osrmUrl}/route/v1/driving/$coords?overview=simplified&geometries=geojson');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) throw Exception('OSRM ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) throw Exception('Aucun itinéraire');
      final r = routes.first as Map<String, dynamic>;
      final coordsList = ((r['geometry'] as Map)['coordinates'] as List)
          .map((c) => LatLng((c as List)[1].toDouble(), c[0].toDouble()))
          .toList();
      final result = RouteResult(
        points: coordsList,
        distanceKm: (r['distance'] as num).toDouble() / 1000,
        // les durées OSRM (voiture) sont optimistes en ville : on prend la plus prudente
        durationMin: [((r['duration'] as num).toDouble() / 60), (r['distance'] as num) / 1000 / avgSpeedKmh * 60]
            .reduce((a, b) => a > b ? a : b)
            .toDouble(),
      );
      if (_cache.length > 50) _cache.clear();
      _cache[key] = result;
      return result;
    } catch (_) {
      return estimate(waypoints);
    }
  }

  RouteResult estimate(List<LatLng> waypoints) {
    var d = 0.0;
    for (var i = 1; i < waypoints.length; i++) {
      d += haversineKm(waypoints[i - 1], waypoints[i]);
    }
    d *= roadFactor;
    return RouteResult(points: waypoints, distanceKm: d, durationMin: d / avgSpeedKmh * 60, isEstimate: true);
  }
}
