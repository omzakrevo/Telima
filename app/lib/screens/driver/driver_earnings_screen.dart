import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/delivery.dart';
import '../../data/models/driver.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/delivery_widgets.dart';

/// Revenus du livreur : aujourd'hui, semaine, mois, nombre de livraisons, commissions, solde.
class DriverEarningsScreen extends ConsumerWidget {
  const DriverEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(driverEarningsProvider);
    final ratings = ref.watch(driverRatingsProvider).value ?? const <Rating>[];
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(driverEarningsProvider);
        ref.invalidate(driverRatingsProvider);
      },
      child: Constrained(
        maxWidth: 720,
        child: AsyncBody<DriverEarnings>(
          value: async,
          onRetry: () => ref.invalidate(driverEarningsProvider),
          builder: (e) => ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Revenus aujourd\'hui', style: TextStyle(color: Colors.white70)),
                Text(fcfa(e.today), style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
                Text('${e.countToday} livraison(s)', style: const TextStyle(color: Colors.white)),
              ]),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.7,
              children: [
                StatCard(label: 'Cette semaine (${e.countWeek})', value: fcfa(e.week), icon: Icons.date_range),
                StatCard(label: 'Ce mois (${e.countMonth})', value: fcfa(e.month), icon: Icons.calendar_month),
                StatCard(label: 'Commissions ce mois', value: fcfa(e.commissionMonth), icon: Icons.percent, color: AppColors.accent),
                StatCard(
                  label: 'Solde disponible',
                  value: fcfa(e.balance),
                  icon: Icons.account_balance_wallet,
                  color: e.balance < 0 ? AppColors.danger : AppColors.info,
                ),
                StatCard(label: 'Livraisons au total', value: '${e.countTotal}', icon: Icons.check_circle_outline),
                StatCard(label: 'Gains au total', value: fcfa(e.earningTotal), icon: Icons.savings_outlined, color: const Color(0xFF7C3AED)),
              ],
            ),
            if (e.pendingWithdrawals > 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Retraits en attente : ${fcfa(e.pendingWithdrawals)}', style: const TextStyle(color: AppColors.textMuted)),
              ),
            if (ratings.isNotEmpty) ...[
              const SectionTitle('Avis des clients'),
              for (final r in ratings.take(5))
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${r.stars}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      const Icon(Icons.star_rounded, color: AppColors.accent),
                    ]),
                    title: Text(r.comment ?? 'Sans commentaire'),
                    subtitle: Text(formatDate(r.createdAt)),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => context.push('/driver/history'), icon: const Icon(Icons.list_alt), label: const Text('Historique détaillé des courses')),
          ]),
        ),
      ),
    );
  }
}

class DriverHistoryScreen extends ConsumerWidget {
  const DriverHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(driverHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Historique des courses')),
      body: Constrained(
        maxWidth: 720,
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(driverHistoryProvider),
          child: AsyncBody<List<Delivery>>(
            value: async,
            onRetry: () => ref.invalidate(driverHistoryProvider),
            builder: (list) => list.isEmpty
                ? ListView(children: const [EmptyState(icon: Icons.history, message: 'Aucune course pour le moment')])
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => DeliveryListTile(
                      delivery: list[i],
                      showEarning: true,
                      onTap: () => context.push('/driver/course/${list[i].id}'),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
