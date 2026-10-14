import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/env.dart';
import '../config/theme.dart';

/// Couche de tuiles OpenStreetMap (gratuite, sans clé). Les tuiles sont mises en cache par le moteur.
TileLayer osmTileLayer() => TileLayer(
      urlTemplate: Env.tileUrl,
      userAgentPackageName: 'app.telima',
      maxZoom: 19,
    );

Widget osmAttribution() => const RichAttributionWidget(
      attributions: [TextSourceAttribution('© contributeurs OpenStreetMap')],
    );

Marker pinMarker(LatLng point, {required Color color, IconData icon = Icons.location_on, String? label}) => Marker(
      point: point,
      width: 120,
      height: 64,
      alignment: Alignment.topCenter,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (label != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        Icon(icon, color: color, size: 36),
      ]),
    );

Marker driverMarker(LatLng point, {String? label}) => Marker(
      point: point,
      width: 52,
      height: 52,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.info, width: 3),
          boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
        ),
        child: const Icon(Icons.delivery_dining, color: AppColors.info, size: 28),
      ),
    );

Marker pickupMarker(LatLng p) => pinMarker(p, color: AppColors.primary, label: 'Départ', icon: Icons.store_mall_directory);
Marker dropoffMarker(LatLng p, {String label = 'Arrivée'}) => pinMarker(p, color: AppColors.danger, label: label, icon: Icons.flag);

/// Cadre la carte sur un ensemble de points.
/// Départ et arrivée au même endroit (ou points invalides) : un cadrage « boîte » aurait une taille nulle,
/// donc un zoom infini qui gèle l'écran. Dans ce cas on centre simplement la carte, et le zoom est plafonné.
MapOptions fitOptions(List<LatLng> points, {double zoom = 14}) {
  final valid = points.where((p) => p.latitude.isFinite && p.longitude.isFinite && !(p.latitude == 0 && p.longitude == 0)).toList();
  const ouagadougou = LatLng(12.3714, -1.5197);
  if (valid.length < 2) {
    return MapOptions(initialCenter: valid.isEmpty ? ouagadougou : valid.first, initialZoom: zoom);
  }
  final b = LatLngBounds.fromPoints(valid);
  if ((b.north - b.south).abs() < 0.0008 && (b.east - b.west).abs() < 0.0008) {
    return MapOptions(initialCenter: b.center, initialZoom: zoom);
  }
  return MapOptions(
    initialCameraFit: CameraFit.bounds(bounds: b, padding: const EdgeInsets.all(56), maxZoom: 17),
  );
}
