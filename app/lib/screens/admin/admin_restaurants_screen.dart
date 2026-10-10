import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../data/models/restaurant.dart';
import '../../providers/restaurant_providers.dart';
import '../../widgets/common.dart';
import '../restaurant/restaurant_widgets.dart';

final _adminRestaurantsProvider =
    FutureProvider.autoDispose<List<Restaurant>>((ref) => ref.watch(restaurantRepositoryProvider).adminRestaurants());

/// Administration des restaurants : voir tous les restaurants, suspendre ou rétablir.
class AdminRestaurantsScreen extends ConsumerWidget {
  const AdminRestaurantsScreen({super.key});

  Future<void> _setStatus(BuildContext context, WidgetRef ref, Restaurant r, String status) async {
    if (status == 'suspended') {
      final ok = await confirmDialog(
        context,
        title: 'Suspendre « ${r.name} » ?',
        message: 'Son lien ne sera plus accessible et plus aucune commande ne pourra être passée. Le restaurateur est prévenu.',
        confirmLabel: 'Suspendre',
        danger: true,
      );
      if (!ok || !context.mounted) return;
    }
    await runWithLoader(context, () => ref.read(restaurantRepositoryProvider).adminSetStatus(r.id, status), success: 'Mis à jour');
    ref.invalidate(_adminRestaurantsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_adminRestaurantsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_adminRestaurantsProvider),
      child: AsyncBody<List<Restaurant>>(
        value: async,
        onRetry: () => ref.invalidate(_adminRestaurantsProvider),
        builder: (list) => list.isEmpty
            ? ListView(children: const [
                SizedBox(height: 80),
                EmptyState(icon: Icons.restaurant_rounded, message: 'Aucun restaurant pour le moment.'),
              ])
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final r = list[i];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        PhotoBox(url: r.logoUrl, size: 44, radius: 12),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            Text([if (r.subtitle.isNotEmpty) r.subtitle, if ((r.phone ?? '').isNotEmpty) r.phone!].join(' · '),
                                style: const TextStyle(color: AppColors.textMuted)),
                          ]),
                        ),
                        InfoTag(r.suspended ? 'Suspendu' : (r.acceptingOrders ? 'Ouvert' : 'Fermé'),
                            color: r.suspended ? AppColors.danger : (r.acceptingOrders ? AppColors.primary : AppColors.textMuted)),
                      ]),
                      const SizedBox(height: 8),
                      SelectableText(restaurantShareLink(r.slug), style: const TextStyle(color: AppColors.primaryDark, fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(children: [
                        TextButton.icon(
                          onPressed: () => copyRestaurantLink(context, r),
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('Copier le lien'),
                        ),
                        const Spacer(),
                        if (r.suspended)
                          FilledButton(onPressed: () => _setStatus(context, ref, r, 'approved'), child: const Text('Rétablir'))
                        else
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                            onPressed: () => _setStatus(context, ref, r, 'suspended'),
                            child: const Text('Suspendre'),
                          ),
                      ]),
                    ]),
                  );
                },
              ),
      ),
    );
  }
}
