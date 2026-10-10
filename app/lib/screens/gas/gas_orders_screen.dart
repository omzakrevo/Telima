import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../data/models/gas.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/common.dart';

/// Mes commandes de gaz.
class GasOrdersScreen extends ConsumerWidget {
  const GasOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myGasOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes commandes de gaz')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myGasOrdersProvider),
        child: AsyncBody<List<GasOrder>>(
          value: async,
          onRetry: () => ref.invalidate(myGasOrdersProvider),
          builder: (list) => list.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  Icon(Icons.inventory_2, size: 56, color: AppColors.textMuted),
                  SizedBox(height: 12),
                  Center(child: Text('Aucune commande de gaz', style: TextStyle(fontWeight: FontWeight.w700))),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => GasOrderTile(order: list[i], onTap: () => context.push('/client/gas/orders/${list[i].id}')),
                ),
        ),
      ),
    );
  }
}

class GasOrderTile extends StatelessWidget {
  const GasOrderTile({super.key, required this.order, required this.onTap});
  final GasOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(order.placeName ?? order.code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: order.statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(order.statusLabel, style: TextStyle(color: order.statusColor, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(order.items.map((i) => i.text).join(', '), style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 4),
            Text('${order.code} · ${fcfa(order.total)} · ${relativeTime(order.createdAt)}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ),
      );
}

/// Suivi d'une commande de gaz.
class GasOrderDetailScreen extends ConsumerWidget {
  const GasOrderDetailScreen({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(gasOrderProvider(orderId));
    return Scaffold(
      appBar: AppBar(title: const Text('Ma commande de gaz')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(gasOrderProvider(orderId)),
        child: AsyncBody<GasOrder>(
          value: async,
          onRetry: () => ref.invalidate(gasOrderProvider(orderId)),
          builder: (o) {
            final failed = o.status == 'rejected' || o.status == 'cancelled';
            final idx = o.steps.indexWhere((s) => s.$1 == o.status);
            return ListView(padding: const EdgeInsets.all(16), children: [
              Constrained(
                maxWidth: 720,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(o.placeName ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text('${o.code} · ${relativeTime(o.createdAt)}', style: const TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 14),
                  if (failed)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                      child: Text('${o.statusLabel}${o.rejectReason == null ? '' : ' : ${o.rejectReason}'}',
                          style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                    )
                  else
                    for (final (i, s) in o.steps.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          Icon(i <= idx ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                              color: i <= idx ? AppColors.primary : AppColors.line, size: 26),
                          const SizedBox(width: 12),
                          Text(s.$2, style: TextStyle(fontWeight: i == idx ? FontWeight.w800 : FontWeight.w500, color: i > idx ? AppColors.textMuted : null)),
                        ]),
                      ),
                  const SectionTitle('Détail'),
                  for (final i in o.items) Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [Expanded(child: Text(i.text)), Text(fcfa(i.unitPrice * i.qty))])),
                  if (o.isDelivery) Row(children: [const Expanded(child: Text('Livraison')), Text(fcfa(o.deliveryFee))]),
                  const Divider(),
                  Row(children: [
                    const Expanded(child: Text('TOTAL À PAYER', style: TextStyle(fontWeight: FontWeight.w800))),
                    Text(fcfa(o.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.primaryDark)),
                  ]),
                  Text(o.paymentStatus == 'paid' ? 'Payé' : 'À régler en espèces à la remise', style: const TextStyle(color: AppColors.textMuted)),
                  if (o.isDelivery && o.dropoffAddress != null) ...[
                    const SectionTitle('Livraison à'),
                    Text(o.dropoffAddress!),
                  ],
                  const SizedBox(height: 16),
                  if (o.deliveryId != null && o.isOpen)
                    BigActionButton(label: 'SUIVRE MON LIVREUR', icon: Icons.delivery_dining_rounded, onPressed: () => context.push('/client/delivery/${o.deliveryId}')),
                  if (!o.isDelivery && o.placePosition != null && o.isOpen) ...[
                    BigActionButton(label: 'ITINÉRAIRE', icon: Icons.navigation, onPressed: () => openNavigation(o.placePosition!)),
                  ],
                  if (o.placePhone != null && o.placePhone!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () => callPhone(o.placePhone!),
                      icon: const Icon(Icons.call),
                      label: const Text('APPELER LE VENDEUR'),
                    ),
                  ],
                  if (o.status == 'sent') ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () async {
                        await runWithLoader(context, () => ref.read(gasRepositoryProvider).cancelOrder(o.id), success: 'Commande annulée');
                        ref.invalidate(gasOrderProvider(orderId));
                        ref.invalidate(myGasOrdersProvider);
                      },
                      child: const Text('Annuler la commande', style: TextStyle(color: AppColors.danger)),
                    ),
                  ],
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
