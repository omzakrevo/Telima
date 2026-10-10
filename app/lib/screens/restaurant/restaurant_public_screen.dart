import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../data/models/restaurant.dart';
import '../../providers/auth_providers.dart';
import '../../providers/restaurant_providers.dart';
import '../../widgets/common.dart';
import 'restaurant_widgets.dart';

/// Page publique d'un restaurant (lien partagé) : visible SANS compte ; la commande demande de se connecter.
class RestaurantPublicScreen extends ConsumerWidget {
  const RestaurantPublicScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(restaurantBySlugProvider(slug));
    final cart = ref.watch(cartProvider);
    final signedIn = ref.watch(authControllerProvider).isSignedIn;
    final restaurant = async.value;
    final cartCount = restaurant != null && cart.restaurantId == restaurant.id ? cart.count : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(restaurant?.name ?? 'Restaurant'),
        actions: [
          if (restaurant != null)
            IconButton(tooltip: 'Partager', icon: const Icon(Icons.share_rounded), onPressed: () => shareRestaurantLink(context, restaurant)),
          if (!signedIn)
            TextButton(
              onPressed: () {
                ref.read(pendingRouteProvider.notifier).set('/r/$slug');
                context.push('/login');
              },
              child: const Text('Se connecter'),
            )
          else if (!context.canPop())
            IconButton(tooltip: 'Accueil Telima', icon: const Icon(Icons.home_rounded), onPressed: () => context.go('/splash')),
        ],
      ),
      bottomNavigationBar: restaurant == null || !restaurant.acceptingOrders || cartCount == 0
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
                child: Constrained(
                  maxWidth: 720,
                  child: BigActionButton(
                    label: 'VOIR MON PANIER · $cartCount · ${fcfa(cart.total(restaurant))}',
                    icon: Icons.shopping_basket_rounded,
                    onPressed: () => context.push('/r/${restaurant.slug}/order'),
                  ),
                ),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(restaurantBySlugProvider(slug)),
        child: AsyncBody<Restaurant?>(
          value: async,
          onRetry: () => ref.invalidate(restaurantBySlugProvider(slug)),
          builder: (r) {
            if (r == null) {
              return ListView(children: const [
                SizedBox(height: 120),
                EmptyState(icon: Icons.storefront_outlined, message: 'Ce restaurant n’existe pas ou n’est plus disponible.'),
              ]);
            }
            return _Content(restaurant: r);
          },
        ),
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.restaurant});
  final Restaurant restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = restaurant;
    final cart = ref.watch(cartProvider);
    final sections = r.sections;
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      Constrained(
        maxWidth: 720,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PhotoBox(url: r.coverUrl, size: double.infinity, height: 150, radius: 0),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                PhotoBox(url: r.logoUrl, size: 64, radius: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    if (r.subtitle.isNotEmpty) Text(r.subtitle, style: const TextStyle(color: AppColors.textMuted)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: restaurantTags(r)),
              if ((r.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(r.description!, style: const TextStyle(height: 1.4)),
              ],
              const SizedBox(height: 10),
              if ((r.hours ?? '').isNotEmpty) _Line(Icons.access_time_rounded, r.hours!),
              if ((r.address ?? '').isNotEmpty) _Line(Icons.place_rounded, r.address!, onTap: () => openNavigation(r.position)),
              if ((r.phone ?? '').isNotEmpty) _Line(Icons.call_rounded, displayPhone(r.phone), onTap: () => callPhone(r.phone!)),
              if (!r.acceptingOrders)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Text('Ce restaurant ne prend pas de commande pour le moment. Vous pouvez consulter son menu.',
                      style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
          if (sections.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Le menu n’est pas encore disponible.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
            ),
          for (final s in sections)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SectionTitle(s.name),
                for (final item in s.items)
                  _ItemTile(
                    item: item,
                    orderable: r.acceptingOrders && item.isAvailable,
                    qty: cart.restaurantId == r.id ? cart.quantityOf(item.id) : 0,
                    onAdd: () => ref.read(cartProvider.notifier).add(r.id, item.id),
                    onRemove: () => ref.read(cartProvider.notifier).remove(item.id),
                  ),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text, {this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Icon(icon, size: 18, color: AppColors.primaryDark),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: onTap != null ? AppColors.primaryDark : null, fontWeight: onTap != null ? FontWeight.w600 : null))),
          ]),
        ),
      );
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.orderable, required this.qty, required this.onAdd, required this.onRemove});
  final MenuItem item;
  final bool orderable;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: item.isAvailable ? 1 : 0.55,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            if (item.photoUrl != null) ...[PhotoBox(url: item.photoUrl, size: 72, radius: 12), const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                if ((item.description ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(item.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.3)),
                  ),
                const SizedBox(height: 6),
                Text(fcfa(item.price), style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(width: 8),
            if (!item.isAvailable)
              const InfoTag('Épuisé', color: AppColors.danger)
            else if (orderable)
              QtyStepper(qty: qty, onAdd: onAdd, onRemove: onRemove),
          ]),
        ),
      );
}
