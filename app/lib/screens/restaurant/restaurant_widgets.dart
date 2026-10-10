import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/theme.dart';
import '../../data/models/restaurant.dart';
import '../../widgets/common.dart';

/// Photo réseau avec repli (icône) si l'image est absente ou ne charge pas.
class PhotoBox extends StatelessWidget {
  const PhotoBox({super.key, required this.url, required this.size, this.icon = Icons.restaurant_rounded, this.radius = 14, this.height});
  final String? url;
  final double size;
  final double? height;
  final IconData icon;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final h = height ?? size;
    final fallback = Container(
      width: size,
      height: h,
      color: AppColors.peach,
      child: Icon(icon, color: AppColors.accent, size: (size < h ? size : h) * 0.45),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: h,
        child: url == null
            ? fallback
            : Image.network(url!, fit: BoxFit.cover, width: size, height: h, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}

/// Petite étiquette arrondie (Ouvert, Livraison, Retrait…).
class InfoTag extends StatelessWidget {
  const InfoTag(this.text, {super.key, this.color = AppColors.textMuted, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Étiquettes de service d'un restaurant (ouvert, délai, livraison, retrait, minimum).
List<Widget> restaurantTags(Restaurant r) => [
      InfoTag(r.acceptingOrders ? 'Ouvert' : 'Fermé', color: r.acceptingOrders ? AppColors.primary : AppColors.danger,
          icon: r.acceptingOrders ? Icons.check_circle_rounded : Icons.cancel_rounded),
      InfoTag('~${r.prepMinutes} min', icon: Icons.schedule_rounded),
      if (r.delivers) InfoTag('Livraison · ${r.deliveryRadiusKm.toStringAsFixed(r.deliveryRadiusKm.truncateToDouble() == r.deliveryRadiusKm ? 0 : 1)} km', color: AppColors.info, icon: Icons.delivery_dining_rounded),
      if (r.acceptsPickup) const InfoTag('Retrait sur place', icon: Icons.storefront_rounded),
      if (r.minOrder > 0) InfoTag('Minimum ${r.minOrder} FCFA', color: AppColors.accent),
    ];

/// Partage le lien du restaurant (feuille de partage du téléphone, sinon copie dans le presse-papiers).
Future<void> shareRestaurantLink(BuildContext context, Restaurant r) async {
  final link = restaurantShareLink(r.slug);
  final text = 'Commandez chez ${r.name} sur Telima : $link';
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: r.name));
  } catch (_) {
    if (!context.mounted) return;
    await copyRestaurantLink(context, r);
  }
}

Future<void> copyRestaurantLink(BuildContext context, Restaurant r) async {
  await Clipboard.setData(ClipboardData(text: restaurantShareLink(r.slug)));
  if (context.mounted) showSuccess(context, 'Lien copié');
}

/// Carte « Votre lien » du restaurateur : le lien, copier, partager.
class ShareLinkCard extends StatelessWidget {
  const ShareLinkCard({super.key, required this.restaurant});
  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final link = restaurantShareLink(restaurant.slug);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.link_rounded, color: AppColors.primaryDark),
          SizedBox(width: 8),
          Text('Le lien de votre restaurant', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 6),
        SelectableText(link, style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Envoyez-le à vos clients (WhatsApp, Facebook, TikTok…) : ils voient votre menu et commandent directement.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.3)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => copyRestaurantLink(context, restaurant),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copier'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => shareRestaurantLink(context, restaurant),
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('Partager'),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Boutons – / + d'un plat dans le panier.
class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.qty, required this.onAdd, required this.onRemove});
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => qty == 0
      ? IconButton.filled(onPressed: onAdd, icon: const Icon(Icons.add_rounded), tooltip: 'Ajouter')
      : Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton.filledTonal(onPressed: onRemove, icon: const Icon(Icons.remove_rounded), tooltip: 'Retirer'),
          SizedBox(width: 30, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          IconButton.filled(onPressed: qty >= 50 ? null : onAdd, icon: const Icon(Icons.add_rounded), tooltip: 'Ajouter'),
        ]);
}
