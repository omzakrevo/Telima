import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/shop.dart';
import '../../providers/shop_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import 'shop_widgets.dart';

/// Boutiques autour de moi : recherche par nom, type de boutique, quartier ou article.
class ShopsHomeScreen extends ConsumerStatefulWidget {
  const ShopsHomeScreen({super.key});

  @override
  ConsumerState<ShopsHomeScreen> createState() => _ShopsHomeScreenState();
}

class _ShopsHomeScreenState extends ConsumerState<ShopsHomeScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _apply(String v) => setState(() => _query = v.trim());

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(nearbyShopsProvider(_query));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Boutiques'),
        actions: [
          IconButton(
            tooltip: 'Mes commandes en boutique',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () => context.push('/client/shops/orders'),
          ),
        ],
      ),
      body: Constrained(
        maxWidth: 720,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: _apply,
              decoration: InputDecoration(
                hintText: 'Boutique, article, quartier…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          _apply('');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(nearbyShopsProvider(_query)),
              child: AsyncBody<List<Shop>>(
                value: async,
                onRetry: () => ref.invalidate(nearbyShopsProvider(_query)),
                builder: (list) => list.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 60),
                        EmptyState(
                          icon: Icons.storefront_rounded,
                          message: _query.isEmpty
                              ? 'Aucune boutique sur Telima pour le moment.\nVous tenez une boutique ? Créez la vôtre gratuitement.'
                              : 'Aucun résultat pour « $_query ».',
                          action: _query.isEmpty
                              ? FilledButton(onPressed: () => context.push('/shop/new'), child: const Text('Créer ma boutique'))
                              : null,
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => FadeSlideIn.staggered(index: i.clamp(0, 6), child: _ShopCard(shop: list[i])),
                      ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.shop});
  final Shop shop;

  @override
  Widget build(BuildContext context) {
    final r = shop;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push('/b/${r.slug}'),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (r.coverUrl != null) ShopPhotoBox(url: r.coverUrl, size: double.infinity, height: 110, radius: 0),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ShopPhotoBox(url: r.logoUrl, size: 54, radius: 14),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  if (r.subtitle.isNotEmpty) Text(r.subtitle, style: const TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    ShopInfoTag(r.acceptingOrders ? 'Ouvert' : 'Fermé', color: r.acceptingOrders ? AppColors.primary : AppColors.danger),
                    if (r.distanceKm != null) ShopInfoTag(km(r.distanceKm), icon: Icons.near_me_rounded),
                    if (r.delivers) const ShopInfoTag('Livraison', color: AppColors.info, icon: Icons.delivery_dining_rounded),
                  ]),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
