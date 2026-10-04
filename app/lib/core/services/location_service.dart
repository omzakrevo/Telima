import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationException implements Exception {
  LocationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Géolocalisation économe : filtre de distance + intervalle minimal entre deux envois.
class LocationService {
  Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationException('Activez la localisation (GPS) de votre téléphone.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw LocationException('Autorisez l\'accès à votre position pour continuer.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw LocationException('Accès à la position refusé. Autorisez-le dans les paramètres du téléphone.');
    }
  }

  Future<LatLng> current() async {
    await ensurePermission();
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      return LatLng(p.latitude, p.longitude);
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return LatLng(last.latitude, last.longitude);
      throw LocationException('Position introuvable. Réessayez à découvert.');
    }
  }

  /// Flux de positions limité : au moins [distanceFilterM] mètres parcourus
  /// et au moins [minInterval] entre deux émissions (heartbeat toutes les 2 min à l'arrêt).
  Stream<Position> track({int distanceFilterM = 25, Duration minInterval = const Duration(seconds: 10)}) {
    late StreamController<Position> controller;
    StreamSubscription<Position>? sub;
    Timer? heartbeat;
    DateTime? lastSent;
    Position? lastPos;

    void emit(Position p) {
      final now = DateTime.now();
      if (lastSent == null || now.difference(lastSent!) >= minInterval) {
        lastSent = now;
        controller.add(p);
      }
    }

    controller = StreamController<Position>(
      onListen: () {
        sub = Geolocator.getPositionStream(
          locationSettings: LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: distanceFilterM),
        ).listen((p) {
          lastPos = p;
          emit(p);
        }, onError: controller.addError);
        heartbeat = Timer.periodic(const Duration(minutes: 2), (_) {
          if (lastPos != null) emit(lastPos!);
        });
      },
      onCancel: () async {
        heartbeat?.cancel();
        await sub?.cancel();
      },
    );
    return controller.stream;
  }
}
