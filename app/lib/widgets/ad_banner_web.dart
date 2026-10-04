import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

final _registered = <String>{};

/// Intègre un bloc `<ins class="adsbygoogle">` dans la page et demande à AdSense de le remplir.
Widget buildAdView(String client, String slot) {
  final viewType = 'telima-ad-$client-$slot';
  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      final box = web.document.createElement('div') as web.HTMLDivElement;
      box.style.width = '100%';
      box.style.height = '100%';
      final ins = web.document.createElement('ins') as web.HTMLElement;
      ins.className = 'adsbygoogle';
      ins.style.display = 'block';
      ins.style.width = '100%';
      ins.style.height = '100%';
      ins.setAttribute('data-ad-client', client);
      if (slot.isNotEmpty) ins.setAttribute('data-ad-slot', slot);
      ins.setAttribute('data-ad-format', 'auto');
      ins.setAttribute('data-full-width-responsive', 'true');
      box.append(ins);
      try {
        (web.window as JSObject).callMethod<JSAny?>('telimaAdPush'.toJS);
      } catch (_) {}
      return box;
    });
  }
  return HtmlElementView(viewType: viewType);
}
