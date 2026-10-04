import 'dart:js_interop';

@JS('telimaTrack')
external void _track(String name, JSAny? params);

/// Envoie un évènement à Google Analytics (si le site en a un d'actif).
void trackEvent(String name, [Map<String, Object?> params = const {}]) {
  try {
    _track(name, params.jsify());
  } catch (_) {}
}
