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
MapOptions fitOptions(List<LatLng> points, {double zoom = 14}) {
  if (points.length < 2) {
    return MapOptions(initialCenter: points.isEmpty ? const LatLng(12.3714, -1.5197) : points.first, initialZoom: zoom);
  }
  return MapOptions(
    initialCameraFit: CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(56)),
  );
}
