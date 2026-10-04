import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';
import 'ad_banner_stub.dart' if (dart.library.js_interop) 'ad_banner_web.dart';

/// Bloc publicitaire Google AdSense : seulement sur la version web, et seulement si
/// l'administrateur a saisi son identifiant éditeur et activé les publicités.
class AdBanner extends ConsumerWidget {
  const AdBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kIsWeb) return const SizedBox.shrink();
    final g = ref.watch(settingsProvider).value?.google;
    if (g == null || !g.adsEnabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(height: 110, width: double.infinity, child: buildAdView(g.adsenseId, g.adSlot)),
    );
  }
}
