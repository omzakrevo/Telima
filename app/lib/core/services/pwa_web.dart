import 'dart:js_interop';

/// Pont vers `window.telimaPwa`, défini dans web/index.html : il garde l'évènement
/// « beforeinstallprompt » du navigateur pour proposer l'installation au bon moment.
@JS('telimaPwa')
external _Pwa? get _pwa;

extension type _Pwa._(JSObject _) implements JSObject {
  external bool canInstall();
  external bool isStandalone();
  external String platform();
  external JSPromise<JSString> install();
}

bool pwaIsStandalone() => _pwa?.isStandalone() ?? false;

bool pwaCanPrompt() => _pwa?.canInstall() ?? false;

/// 'ios', 'android' ou 'desktop'.
String pwaPlatform() => _pwa?.platform() ?? 'desktop';

/// Affiche la fenêtre d'installation du navigateur : 'accepted', 'dismissed' ou 'unavailable'.
Future<String> pwaPrompt() async {
  final p = _pwa;
  if (p == null) return 'unavailable';
  try {
    return (await p.install().toDart).toDart;
  } catch (_) {
    return 'unavailable';
  }
}
