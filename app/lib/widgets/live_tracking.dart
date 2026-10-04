import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../config/theme.dart';
import '../core/utils/formatters.dart';
import '../core/utils/geo.dart';
import '../data/models/delivery.dart';
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
    } else {
      // estimation locale sans requête réseau
      final straight = haversineKm(from, _target) * 1.3;
      setState(() {
        _remainingKm = straight;
        _remainingMin = straight / speed * 60;
      });
    }
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
          child: FlutterMap(
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
              osmAttribution(),
            ],
          ),
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
