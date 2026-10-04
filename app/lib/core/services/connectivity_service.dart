import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService() {
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online != _online) {
        _online = online;
        _controller.add(online);
      }
    });
    _connectivity.checkConnectivity().then((results) {
      _online = results.any((r) => r != ConnectivityResult.none);
      _controller.add(_online);
    });
  }

  final _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();
  late final StreamSubscription _sub;
  bool _online = true;

  bool get isOnline => _online;
  Stream<bool> get onStatusChange => _controller.stream;

  void dispose() {
    _sub.cancel();
    _controller.close();
  }
}
