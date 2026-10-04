import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'core_providers.dart';

class DriverTrackingState {
  const DriverTrackingState({this.active = false, this.lastPosition, this.error});
  final bool active;
  final LatLng? lastPosition;
  final String? error;
}

/// Envoi de la position du livreur pendant qu'il est EN LIGNE.
/// Économe : filtre de 25 m + intervalle minimal défini par l'administrateur (10 s par défaut).
class DriverTrackingController extends Notifier<DriverTrackingState> {
  StreamSubscription? _sub;

  @override
  DriverTrackingState build() {
    ref.onDispose(() => _sub?.cancel());
    return const DriverTrackingState();
  }

  Future<void> start() async {
    if (_sub != null) return;
    final settings = await ref.read(settingsProvider.future);
    final location = ref.read(locationServiceProvider);
    final repo = ref.read(driverRepositoryProvider);
    try {
      await location.ensurePermission();
    } catch (e) {
      state = DriverTrackingState(error: e.toString());
      return;
    }
    _sub = location
        .track(minInterval: Duration(seconds: settings.locationIntervalSeconds))
        .listen((p) {
      state = DriverTrackingState(active: true, lastPosition: LatLng(p.latitude, p.longitude));
      repo.sendLocation(p.latitude, p.longitude, heading: p.heading, speed: p.speed).ignore();
    }, onError: (Object e) {
      state = DriverTrackingState(active: false, lastPosition: state.lastPosition, error: e.toString());
    });
    state = DriverTrackingState(active: true, lastPosition: state.lastPosition);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    state = DriverTrackingState(lastPosition: state.lastPosition);
  }
}

final driverTrackingProvider = NotifierProvider<DriverTrackingController, DriverTrackingState>(DriverTrackingController.new);
