import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/delivery.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/delivery_widgets.dart';

class DeliveryHistoryScreen extends ConsumerStatefulWidget {
  const DeliveryHistoryScreen({super.key});
  @override
  ConsumerState<DeliveryHistoryScreen> createState() => _DeliveryHistoryScreenState();
}

class _DeliveryHistoryScreenState extends ConsumerState<DeliveryHistoryScreen> {
  String _filter = 'all';

  bool _match(Delivery d) => switch (_filter) {
        'active' => d.status.isActive,
        'completed' => d.status.name == 'completed',
        'cancelled' => d.status.name == 'cancelled',
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myDeliveriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Historique')),
      body: Constrained(
        maxWidth: 720,
        child: Column(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              for (final f in const [('all', 'Toutes'), ('active', 'En cours'), ('completed', 'Terminées'), ('cancelled', 'Annulées')])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
                ),
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(myDeliveriesProvider),
              child: AsyncBody<List<Delivery>>(
                value: async,
                onRetry: () => ref.invalidate(myDeliveriesProvider),
                builder: (all) {
                  final list = all.where(_match).toList();
                  if (list.isEmpty) {
                    return ListView(children: const [EmptyState(icon: Icons.inventory_2_outlined, message: 'Aucune livraison')]);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) =>
                        DeliveryListTile(delivery: list[i], onTap: () => context.push('/client/delivery/${list[i].id}')),
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
