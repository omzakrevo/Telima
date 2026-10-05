import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../config/theme.dart';
import '../core/utils/formatters.dart';
import '../core/utils/geo.dart';
import '../data/models/delivery.dart';
import '../data/models/gas.dart';
import '../core/utils/launchers.dart';
import '../providers/gas_providers.dart';
import '../providers/core_providers.dart';
import 'map_widgets.dart';

/// Carte de suivi : position du livreur, départ, destination, itinéraire,
/// distance et temps restants. L'itinéraire n'est recalculé qu'en cas de changement
/// d'étape, de déplacement important (> 300 m) ou toutes les 2 minutes.
class LiveTrackingMap extends ConsumerStatefulWidget {
  const LiveTrackingMap({super.key, required this.delivery, this.driverPosition, this.height = 300, this.showStats = true});
  final Delivery delivery;
  final LatLng? driverPosition;
  final double height;
  final bool showStats;

  @override
  ConsumerState<LiveTrackingMap> createState() => _LiveTrackingMapState();
}

class _LiveTrackingMapState extends ConsumerState<LiveTrackingMap> {
  final _map = MapController();
  List<LatLng> _route = [];
  double? _remainingKm;
  double? _remainingMin;
  LatLng? _routedFrom;
  DateTime? _routedAt;
  String? _routedPhase;
  List<Place> _stations = [];
  bool _showStations = true;
  String? _stationsKey;

  LatLng get _target => widget.delivery.status.headingToPickup ? widget.delivery.pickup : widget.delivery.dropoff;

  @override
  void initState() {
    super.initState();
    _maybeReroute();
  }

  @override
  void didUpdateWidget(covariant LiveTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeReroute();
  }

  Future<void> _maybeReroute() async {
    final d = widget.delivery;
    final from = widget.driverPosition;
    final phase = d.status.headingToPickup ? 'pickup' : 'dropoff';
    final settings = ref.read(settingsProvider).value;
    final speed = settings?.avgSpeedKmh ?? 25;

    if (from == null || !d.status.hasDriver || d.status.isFinished) {
      // pas encore de livreur : on affiche le trajet colis
      if (_routedPhase != 'overview') {
        _routedPhase = 'overview';
        final r = await ref.read(routingServiceProvider).route([d.pickup, d.dropoff]);
        if (mounted) setState(() => _route = r.points);
        _loadStations();
      }
      return;
    }

    final moved = _routedFrom == null ? double.infinity : haversineKm(_routedFrom!, from);
    final stale = _routedAt == null || DateTime.now().difference(_routedAt!) > const Duration(minutes: 2);
    if (phase != _routedPhase || moved > 0.3 || stale) {
      _routedPhase = phase;
      _routedFrom = from;
      _routedAt = DateTime.now();
      final r = await ref.read(routingServiceProvider).route([from, _target]);
      if (!mounted) return;
      setState(() {
        _route = r.points;
        _remainingKm = r.distanceKm;
        _remainingMin = r.durationMin;
      });
      _loadStations();
    } else {
      // estimation locale sans requête réseau
      final straight = haversineKm(from, _target) * 1.3;
      setState(() {
        _remainingKm = straight;
        _remainingMin = straight / speed * 60;
      });
    }
  }

  /// Stations-service à moins de 1 km de l'itinéraire affiché.
  Future<void> _loadStations() async {
    final pts = _route.length >= 2 ? _route : [widget.delivery.pickup, widget.delivery.dropoff];
    final b = LatLngBounds.fromPoints(pts);
    final key = '${b.center.latitude.toStringAsFixed(2)},${b.center.longitude.toStringAsFixed(2)},${pts.length ~/ 20}';
    if (key == _stationsKey) return;
    _stationsKey = key;
    try {
      final radius = (haversineKm(b.southWest, b.northEast) / 2 + 1.5).clamp(2.0, 40.0);
      final found = await ref.read(gasRepositoryProvider).search(
          lat: b.center.latitude, lng: b.center.longitude, stations: true, maxKm: radius, useCache: false, limit: 200);
      final step = (pts.length / 150).ceil().clamp(1, 1000);
      final sampled = [for (var i = 0; i < pts.length; i += step) pts[i], pts.last];
      final near = found.where((s) => sampled.any((q) => haversineKm(q, s.position) <= 1.0)).take(25).toList();
      if (mounted) setState(() => _stations = near);
    } catch (_) {}
  }

  void _stationSheet(Place s) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (s.subtitle.isNotEmpty) Text(s.subtitle, style: const TextStyle(color: AppColors.textMuted)),
            if (s.hours != null && s.hours!.isNotEmpty) Text(s.hours!),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: () => openNavigation(s.position), icon: const Icon(Icons.directions_rounded), label: const Text('Itinéraire vers cette station')),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.delivery;
    final driver = widget.driverPosition;
    final points = [d.pickup, d.dropoff, ?driver];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: widget.height,
          child: Stack(children: [
            FlutterMap(
            mapController: _map,
            options: fitOptions(points),
            children: [
              osmTileLayer(),
              if (_route.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(points: _route, strokeWidth: 5, color: AppColors.info.withValues(alpha: 0.8)),
                ]),
              MarkerLayer(markers: [
                pickupMarker(d.pickup),
                dropoffMarker(d.dropoff),
                if (driver != null) driverMarker(driver),
              ]),
              if (_showStations)
                MarkerLayer(markers: [
                  for (final s in _stations)
                    Marker(
                      point: s.position,
                      width: 34,
                      height: 34,
                      child: GestureDetector(
                        onTap: () => _stationSheet(s),
                        child: Container(
                          decoration: BoxDecoration(color: AppColors.info, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)]),
                          child: const Icon(Icons.local_gas_station_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                ]),
              osmAttribution(),
            ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: FilterChip(
                visualDensity: VisualDensity.compact,
                backgroundColor: Colors.white,
                selectedColor: AppColors.info.withValues(alpha: 0.2),
                avatar: const Icon(Icons.local_gas_station_rounded, size: 16, color: AppColors.info),
                label: Text(_stations.isEmpty ? 'Stations' : 'Stations (${_stations.length})'),
                selected: _showStations,
                onSelected: (v) => setState(() => _showStations = v),
              ),
            ),
          ]),
        ),
      ),
      if (widget.showStats && driver != null && d.status.hasDriver && !d.status.isFinished && _remainingKm != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            Expanded(child: _stat(Icons.route, 'Distance restante', km(_remainingKm))),
            const SizedBox(width: 10),
            Expanded(child: _stat(Icons.schedule, d.status.headingToPickup ? 'Arrivée du livreur' : 'Arrivée du colis', '≈ ${minutes(_remainingMin)}')),
          ]),
        ),
    ]);
  }

  Widget _stat(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE5E7EB))),
        child: Row(children: [
          Icon(icon, color: AppColors.info),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
          ),
        ]),
      );
}

/// Abonnement aux positions du livreur pour une livraison (temps réel + position initiale).
class DriverPositionNotifier extends Notifier<LatLng?> {
  DriverPositionNotifier(this.deliveryId);
  final String deliveryId;
  Object? _channel;

  @override
  LatLng? build() {
    final repo = ref.watch(deliveryRepositoryProvider);
    final channel = repo.subscribeLocations(deliveryId, (lat, lng) => state = LatLng(lat, lng));
    _channel = channel;
    ref.onDispose(() => repo.removeChannel(channel));
    unawaited(_initial());
    return null;
  }

  Future<void> _initial() async {
    try {
      final last = await ref.read(deliveryRepositoryProvider).lastLocation(deliveryId);
      if (last != null && state == null) {
        state = LatLng((last['lat'] as num).toDouble(), (last['lng'] as num).toDouble());
        return;
      }
      final info = await ref.read(deliveryRepositoryProvider).driverInfo(deliveryId);
      if (info?.position != null && state == null) state = info!.position;
    } catch (_) {}
  }

  bool get subscribed => _channel != null;
}

final driverPositionProvider =
    NotifierProvider.autoDispose.family<DriverPositionNotifier, LatLng?, String>(DriverPositionNotifier.new);
