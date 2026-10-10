import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/restaurant.dart';
import '../../providers/restaurant_providers.dart';
import '../../widgets/common.dart';
import 'restaurant_widgets.dart';

/// Restaurants autour de moi : recherche par nom, cuisine, quartier ou plat.
class RestaurantsHomeScreen extends ConsumerStatefulWidget {
  const RestaurantsHomeScreen({super.key});

  @override
  ConsumerState<RestaurantsHomeScreen> createState() => _RestaurantsHomeScreenState();
}

class _RestaurantsHomeScreenState extends ConsumerState<RestaurantsHomeScreen> {
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
    final async = ref.watch(nearbyRestaurantsProvider(_query));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurants'),
        actions: [
          IconButton(
            tooltip: 'Mes commandes de repas',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () => context.push('/client/restaurants/orders'),
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
                hintText: 'Restaurant, plat, quartier…',
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
              onRefresh: () async => ref.invalidate(nearbyRestaurantsProvider(_query)),
              child: AsyncBody<List<Restaurant>>(
                value: async,
                onRetry: () => ref.invalidate(nearbyRestaurantsProvider(_query)),
                builder: (list) => list.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 60),
                        EmptyState(
                          icon: Icons.restaurant_rounded,
                          message: _query.isEmpty
                              ? 'Aucun restaurant sur Telima pour le moment.\nVous tenez un restaurant ? Créez le vôtre gratuitement.'
                              : 'Aucun résultat pour « $_query ».',
                          action: _query.isEmpty
                              ? FilledButton(onPressed: () => context.push('/restaurant/new'), child: const Text('Créer mon restaurant'))
                              : null,
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _RestaurantCard(restaurant: list[i]),
                      ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RestaurantCard extends StatelessWidget {
  const _RestaurantCard({required this.restaurant});
  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.push('/r/${r.slug}'),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (r.coverUrl != null) PhotoBox(url: r.coverUrl, size: double.infinity, height: 110, radius: 0),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              PhotoBox(url: r.logoUrl, size: 54, radius: 14),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  if (r.subtitle.isNotEmpty) Text(r.subtitle, style: const TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    InfoTag(r.acceptingOrders ? 'Ouvert' : 'Fermé', color: r.acceptingOrders ? AppColors.primary : AppColors.danger),
                    if (r.distanceKm != null) InfoTag(km(r.distanceKm), icon: Icons.near_me_rounded),
                    if (r.delivers) const InfoTag('Livraison', color: AppColors.info, icon: Icons.delivery_dining_rounded),
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
