import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/gas.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/common.dart';
import '../gas/gas_widgets.dart';

final _adminSubsProvider = FutureProvider.autoDispose<List<VendorSubscription>>((ref) => ref.watch(gasRepositoryProvider).adminSubscriptions());
final _adminPlansProvider = FutureProvider.autoDispose<List<VendorPlan>>((ref) => ref.watch(gasRepositoryProvider).plans());
final _adminReviewsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(gasRepositoryProvider).adminReviews());

/// Abonnements vendeur : demandes à valider + prix des forfaits.
class AdminSubscriptionsTab extends ConsumerWidget {
  const AdminSubscriptionsTab({super.key});

  Future<void> _editPlan(BuildContext context, WidgetRef ref, VendorPlan p) async {
    final price = TextEditingController(text: '${p.priceMonthly}');
    final products = TextEditingController(text: p.maxProducts?.toString() ?? '');
    final promos = TextEditingController(text: p.maxPromotions?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Forfait ${p.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Prix par mois (FCFA)')),
          TextField(controller: products, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Produits max (vide = illimité)')),
          TextField(controller: promos, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Promotions actives max (vide = illimité)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await runWithLoader(
      context,
      () => ref.read(gasRepositoryProvider).adminSavePlan(p.code,
          price: int.tryParse(price.text) ?? p.priceMonthly, maxProducts: int.tryParse(products.text), maxPromotions: int.tryParse(promos.text)),
      success: 'Forfait mis à jour',
    );
    ref.invalidate(_adminPlansProvider);
    ref.invalidate(vendorPlansProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(_adminSubsProvider);
    final plans = ref.watch(_adminPlansProvider).value ?? const <VendorPlan>[];
    return AsyncBody<List<VendorSubscription>>(
      value: subs,
      onRetry: () => ref.invalidate(_adminSubsProvider),
      builder: (list) => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Forfaits', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        for (final p in plans)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(p.name),
            subtitle: Text('${p.priceMonthly == 0 ? 'Gratuit' : '${fcfa(p.priceMonthly)} / mois'} · ${p.maxProducts ?? '∞'} produits · ${p.maxPromotions ?? '∞'} promotions'),
            trailing: IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => _editPlan(context, ref, p)),
          ),
        const Divider(height: 28),
        const Text('Demandes et abonnements', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        if (list.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Aucune demande', style: TextStyle(color: AppColors.textMuted))),
        for (final s in list)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s.placeName ?? ''} · ${plans.where((p) => p.code == s.planCode).firstOrNull?.name ?? s.planCode}', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${s.months} mois · ${fcfa(s.amount)} · réf. ${s.paymentRef ?? '—'}'),
                Text('Demandé ${relativeTime(s.createdAt)}${s.endsAt == null ? '' : ' · fin ${formatDate(s.endsAt)}'}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 6),
                if (s.status == 'pending')
                  Row(children: [
                    FilledButton(
                      onPressed: () async {
                        await runWithLoader(context, () => ref.read(gasRepositoryProvider).adminDecideSubscription(s.id, true), success: 'Abonnement activé');
                        ref.invalidate(_adminSubsProvider);
                      },
                      child: const Text('Activer'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        await runWithLoader(context, () => ref.read(gasRepositoryProvider).adminDecideSubscription(s.id, false), success: 'Demande refusée');
                        ref.invalidate(_adminSubsProvider);
                      },
                      child: const Text('Refuser'),
                    ),
                  ])
                else
                  SmallTag({'active': s.activeNow ? 'Actif' : 'Expiré', 'rejected': 'Refusé', 'ended': 'Terminé'}[s.status] ?? s.status,
                      s.activeNow ? AppColors.primaryDark : AppColors.textMuted),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Modération des avis.
class AdminReviewsTab extends ConsumerWidget {
  const AdminReviewsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_adminReviewsProvider);
    return AsyncBody<List<Map<String, dynamic>>>(
      value: async,
      onRetry: () => ref.invalidate(_adminReviewsProvider),
      builder: (list) => list.isEmpty
          ? const Center(child: Text('Aucun avis', style: TextStyle(color: AppColors.textMuted)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = list[i];
                return ListTile(
                  title: Text('${'★' * (r['rating'] as int)}${'☆' * (5 - (r['rating'] as int))}  ${(r['places'] as Map?)?['name'] ?? ''}'),
                  subtitle: Text('${(r['users'] as Map?)?['full_name'] ?? ''}${r['comment'] == null ? '' : ' : ${r['comment']}'}'),
                  trailing: IconButton(
                    tooltip: 'Supprimer',
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                    onPressed: () async {
                      await runWithLoader(context, () => ref.read(gasRepositoryProvider).adminDeleteReview('${r['id']}'), success: 'Avis supprimé');
                      ref.invalidate(_adminReviewsProvider);
                    },
                  ),
                );
              },
            ),
    );
  }
}
