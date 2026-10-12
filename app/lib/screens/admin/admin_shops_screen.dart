import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../data/models/shop.dart';
import '../../providers/shop_providers.dart';
import '../../widgets/common.dart';
import '../shop/shop_widgets.dart';

final _adminShopsProvider =
    FutureProvider.autoDispose<List<Shop>>((ref) => ref.watch(shopRepositoryProvider).adminShops());

/// Administration des boutiques : voir toutes les boutiques, suspendre ou rétablir.
class AdminShopsScreen extends ConsumerWidget {
  const AdminShopsScreen({super.key});

  Future<void> _setStatus(BuildContext context, WidgetRef ref, Shop r, String status) async {
    if (status == 'suspended') {
      final ok = await confirmDialog(
        context,
        title: 'Suspendre « ${r.name} » ?',
        message: 'Son lien ne sera plus accessible et plus aucune commande ne pourra être passée. Le commerçant est prévenu.',
        confirmLabel: 'Suspendre',
        danger: true,
      );
      if (!ok || !context.mounted) return;
    }
    await runWithLoader(context, () => ref.read(shopRepositoryProvider).adminSetStatus(r.id, status), success: 'Mis à jour');
    ref.invalidate(_adminShopsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_adminShopsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_adminShopsProvider),
      child: AsyncBody<List<Shop>>(
        value: async,
        onRetry: () => ref.invalidate(_adminShopsProvider),
        builder: (list) => list.isEmpty
            ? ListView(children: const [
                SizedBox(height: 80),
                EmptyState(icon: Icons.storefront_rounded, message: 'Aucune boutique pour le moment.'),
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
                        ShopPhotoBox(url: r.logoUrl, size: 44, radius: 12),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                            Text([if (r.subtitle.isNotEmpty) r.subtitle, if ((r.phone ?? '').isNotEmpty) r.phone!].join(' · '),
                                style: const TextStyle(color: AppColors.textMuted)),
                          ]),
                        ),
                        ShopInfoTag(r.suspended ? 'Suspendu' : (r.acceptingOrders ? 'Ouvert' : 'Fermé'),
                            color: r.suspended ? AppColors.danger : (r.acceptingOrders ? AppColors.primary : AppColors.textMuted)),
                      ]),
                      const SizedBox(height: 8),
                      SelectableText(shopShareLink(r.slug), style: const TextStyle(color: AppColors.primaryDark, fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(children: [
                        TextButton.icon(
                          onPressed: () => copyShopLink(context, r),
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
