import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class PlaceResult {
  PlaceResult(this.label, this.point);
  final String label;
  final LatLng point;
}

/// Recherche d'adresses / adresse d'un point. Implémentation : Nominatim (OpenStreetMap).
/// En Afrique de l'Ouest les adresses sont souvent imprécises : le texte libre du client
/// (« Maison derrière la station ») reste l'information principale, la carte fait foi pour la position.
abstract class GeocodingService {
  Future<String?> reverse(LatLng point);
  Future<List<PlaceResult>> search(String query, {LatLng? near});
}

class NominatimGeocodingService implements GeocodingService {
  static const _base = 'https://nominatim.openstreetmap.org';
  static const _headers = {'User-Agent': 'Telima/1.0 (app.telima)', 'Accept-Language': 'fr'};

  @override
  Future<String?> reverse(LatLng point) async {
    try {
      final uri = Uri.parse('$_base/reverse?format=jsonv2&zoom=17&lat=${point.latitude}&lon=${point.longitude}');
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final a = (j['address'] as Map?) ?? {};
      final parts = [
        a['road'],
        a['neighbourhood'] ?? a['suburb'] ?? a['quarter'],
        a['city'] ?? a['town'] ?? a['village'],
      ].whereType<String>().toList();
      return parts.isEmpty ? j['display_name'] as String? : parts.join(', ');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<PlaceResult>> search(String query, {LatLng? near}) async {
    if (query.trim().length < 3) return [];
    try {
      var url = '$_base/search?format=jsonv2&limit=6&countrycodes=bf&q=${Uri.encodeQueryComponent(query)}';
      if (near != null) {
        url += '&viewbox=${near.longitude - 0.3},${near.latitude + 0.3},${near.longitude + 0.3},${near.latitude - 0.3}';
      }
      final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return [];
      return (jsonDecode(res.body) as List)
          .map((e) => PlaceResult(
                e['display_name'] as String,
                LatLng(double.parse(e['lat'] as String), double.parse(e['lon'] as String)),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
