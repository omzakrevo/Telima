import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

double haversineKm(LatLng a, LatLng b) {
  const r = 6371.0;
  final dLat = _rad(b.latitude - a.latitude);
  final dLng = _rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

double _rad(double d) => d * math.pi / 180;

/// Ouagadougou par défaut quand la position n'est pas disponible.
const defaultCenter = LatLng(12.3714, -1.5197);
