import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/shop.dart';
import '../../widgets/common.dart';
import '../../widgets/icon3d.dart';
import '../../widgets/qr_link_sheet.dart';

/// Photo réseau avec repli (icône) si l'image est absente ou ne charge pas.
class ShopPhotoBox extends StatelessWidget {
  const ShopPhotoBox({super.key, required this.url, required this.size, this.icon = Icons.storefront_rounded, this.radius = 14, this.height});
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
      color: AppColors.mint,
      alignment: Alignment.center,
      child: icon == Icons.storefront_rounded
          ? Icon3D(Ico3D.bags, size: (size < h ? size : h) * 0.62, shadow: false)
          : Icon(icon, color: AppColors.accent, size: (size < h ? size : h) * 0.45),
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
class ShopInfoTag extends StatelessWidget {
  const ShopInfoTag(this.text, {super.key, this.color = AppColors.textMuted, this.icon});
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

/// Étiquettes de service d'une boutique (ouvert, délai, livraison, retrait, minimum).
List<Widget> shopTags(Shop r) => [
      ShopInfoTag(r.acceptingOrders ? 'Ouvert' : 'Fermé', color: r.acceptingOrders ? AppColors.primary : AppColors.danger,
          icon: r.acceptingOrders ? Icons.check_circle_rounded : Icons.cancel_rounded),
      ShopInfoTag('~${r.prepMinutes} min', icon: Icons.schedule_rounded),
      if (r.delivers) ShopInfoTag('Livraison · ${r.deliveryRadiusKm.toStringAsFixed(r.deliveryRadiusKm.truncateToDouble() == r.deliveryRadiusKm ? 0 : 1)} km', color: AppColors.info, icon: Icons.delivery_dining_rounded),
      if (r.acceptsPickup) const ShopInfoTag('Retrait sur place', icon: Icons.storefront_rounded),
      if (r.minOrder > 0) ShopInfoTag('Minimum ${r.minOrder} FCFA', color: AppColors.accent),
    ];

/// Partage le lien de la boutique (feuille de partage du téléphone, sinon copie dans le presse-papiers).
Future<void> shareShopLink(BuildContext context, Shop r) async {
  final link = shopShareLink(r.slug);
  final text = 'Commandez chez ${r.name} sur Telima : $link';
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: r.name));
  } catch (_) {
    if (!context.mounted) return;
    await copyShopLink(context, r);
  }
}

Future<void> showShopQr(BuildContext context, Shop r) =>
    showQrLinkSheet(context, title: r.name, link: shopShareLink(r.slug), slug: r.slug);

Future<void> copyShopLink(BuildContext context, Shop r) async {
  await Clipboard.setData(ClipboardData(text: shopShareLink(r.slug)));
  if (context.mounted) showSuccess(context, 'Lien copié');
}

/// Carte « Votre lien » du commerçant : le lien, copier, partager.
class ShopShareLinkCard extends StatelessWidget {
  const ShopShareLinkCard({super.key, required this.shop});
  final Shop shop;

  @override
  Widget build(BuildContext context) {
    final link = shopShareLink(shop.slug);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.link_rounded, color: AppColors.primaryDark),
          SizedBox(width: 8),
          Text('Le lien de votre boutique', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 6),
        SelectableText(link, style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Envoyez-le à vos clients (WhatsApp, Facebook, TikTok…) : ils voient votre catalogue et commandent directement.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.3)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => copyShopLink(context, shop),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copier'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => shareShopLink(context, shop),
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('Partager'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => showShopQr(context, shop),
            icon: const Icon(Icons.qr_code_2_rounded, size: 20),
            label: const Text('QR code à télécharger'),
          ),
        ),
      ]),
    );
  }
}

/// Boutons – / + d'un article dans le panier.
class ShopQtyStepper extends StatelessWidget {
  const ShopQtyStepper({super.key, required this.qty, required this.onAdd, required this.onRemove});
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

/// Fenêtre de choix de la taille et de la couleur d'un article avant de l'ajouter au panier.
Future<({String? size, String? color})?> pickShopVariant(BuildContext context, ShopProduct item) {
  String? size = item.sizes.length == 1 ? item.sizes.first : null;
  String? color = item.colors.length == 1 ? item.colors.first : null;
  return showModalBottomSheet<({String? size, String? color})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final ready = (item.sizes.isEmpty || size != null) && (item.colors.isEmpty || color != null);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(fcfa(item.price), style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800, fontSize: 16)),
              if (item.sizes.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Taille', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final x in item.sizes) ChoiceChip(label: Text(x), selected: size == x, onSelected: (_) => setS(() => size = x)),
                ]),
              ],
              if (item.colors.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Couleur', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final x in item.colors) ChoiceChip(label: Text(x), selected: color == x, onSelected: (_) => setS(() => color = x)),
                ]),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: ready ? () => Navigator.pop(ctx, (size: size, color: color)) : null,
                  child: Text(ready ? 'Ajouter au panier' : 'Choisissez ${item.sizes.isNotEmpty && size == null ? 'une taille' : 'une couleur'}'),
                ),
              ),
            ]),
          ),
        );
      },
    ),
  );
}
