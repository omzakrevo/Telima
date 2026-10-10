import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/gas.dart';
import '../../providers/core_providers.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/common.dart';
import '../gas/gas_widgets.dart';

/// Onglet « Promotions » d'un point de gaz.
class VendorPromos extends ConsumerWidget {
  const VendorPromos({super.key, required this.place});
  final Place place;

  Future<void> _edit(BuildContext context, WidgetRef ref, [PlacePromo? promo]) async {
    final title = TextEditingController(text: promo?.title ?? '');
    final value = TextEditingController(text: promo == null ? '10' : '${promo.value}');
    var percent = promo?.percent ?? true;
    var days = 7;
    String? productId = promo?.productId;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(promo == null ? 'Nouvelle promotion' : 'Modifier la promotion', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextField(controller: title, maxLength: 80, decoration: const InputDecoration(labelText: 'Titre', hintText: 'Ex. Spécial week-end')),
              DropdownButtonFormField<String?>(
                initialValue: productId,
                decoration: const InputDecoration(labelText: 'Produit concerné'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Toutes mes bouteilles')),
                  for (final p in place.products) DropdownMenuItem<String?>(value: p.id, child: Text('${p.brand} · ${p.sizeLabel}')),
                ],
                onChanged: (v) => productId = v,
              ),
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: true, label: Text('En %')), ButtonSegment(value: false, label: Text('En FCFA'))],
                selected: {percent},
                onSelectionChanged: (s) => setS(() => percent = s.first),
              ),
              const SizedBox(height: 10),
              TextField(controller: value, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: percent ? 'Réduction (%)' : 'Réduction par bouteille (FCFA)')),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final d in const [1, 3, 7, 14, 30])
                  ChoiceChip(label: Text(d == 1 ? '1 jour' : '$d jours'), selected: days == d, onSelected: (_) => setS(() => days = d)),
              ]),
              const SizedBox(height: 14),
              BigActionButton(label: 'Enregistrer', onPressed: () => Navigator.pop(context, true)),
            ]),
          ),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final v = int.tryParse(value.text.replaceAll(RegExp(r'\D'), ''));
    if (title.text.trim().length < 2 || v == null || v <= 0 || (percent && v > 90)) {
      showError(context, Exception('Titre et réduction valides obligatoires (90 % maximum)'));
      return;
    }
    try {
      await runWithLoader(
        context,
        () => ref.read(gasRepositoryProvider).savePromo(
            id: promo?.id, placeId: place.id, productId: productId, title: title.text.trim(), percent: percent, value: v, endsAt: DateTime.now().add(Duration(days: days))),
        success: 'Promotion enregistrée',
      );
    } catch (_) {}
    ref.invalidate(placePromosProvider(place.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(placePromosProvider(place.id));
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(context, ref), child: const Icon(Icons.add)),
      body: AsyncBody<List<PlacePromo>>(
        value: async,
        onRetry: () => ref.invalidate(placePromosProvider(place.id)),
        builder: (list) => list.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Créez une promotion avec le bouton +.\nLe prix réduit s’affiche aux clients et s’applique à la commande.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted))))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final p = list[i];
                  final product = place.products.where((x) => x.id == p.productId).firstOrNull;
                  return Container(
                    padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text('${p.label} · ${product == null ? 'toutes les bouteilles' : '${product.brand} ${product.sizeLabel}'}',
                              style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          SmallTag(p.running ? 'En cours · jusqu’au ${formatDate(p.endsAt)}' : (p.isActive ? 'Terminée le ${formatDate(p.endsAt)}' : 'Désactivée'),
                              p.running ? AppColors.primaryDark : AppColors.textMuted),
                        ]),
                      ),
                      Switch(
                        value: p.isActive,
                        onChanged: (v) async {
                          try {
                            await ref.read(gasRepositoryProvider).savePromo(
                                id: p.id, placeId: place.id, productId: p.productId, title: p.title, percent: p.percent, value: p.value,
                                endsAt: p.endsAt ?? DateTime.now().add(const Duration(days: 7)), active: v);
                          } catch (e) {
                            if (context.mounted) showError(context, e);
                          }
                          ref.invalidate(placePromosProvider(place.id));
                        },
                      ),
                      IconButton(
                        onPressed: () async {
                          await runWithLoader(context, () => ref.read(gasRepositoryProvider).deletePromo(p.id));
                          ref.invalidate(placePromosProvider(place.id));
                        },
                        icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                      ),
                    ]),
                  );
                },
              ),
      ),
    );
  }
}

/// Onglet « Abonnement » : forfait en cours, forfaits disponibles, demande avec référence Orange Money.
class VendorSubscriptionTab extends ConsumerWidget {
  const VendorSubscriptionTab({super.key, required this.place});
  final Place place;

  Future<void> _subscribe(BuildContext context, WidgetRef ref, VendorPlan plan) async {
    final settings = ref.read(settingsProvider).value;
    final om = settings?.mobileMoneyAccount('orange_money');
    final ref0 = TextEditingController();
    var months = 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: Text('Forfait ${plan.name}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, children: [
                for (final m in const [1, 3, 6, 12]) ChoiceChip(label: Text('$m mois'), selected: months == m, onSelected: (_) => setS(() => months = m)),
              ]),
              const SizedBox(height: 12),
              Text('Montant : ${fcfa(plan.priceMonthly * months)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                om != null && om.number.isNotEmpty
                    ? 'Envoyez ce montant par Orange Money au ${displayPhone(om.number)}${om.name.isEmpty ? '' : ' (${om.name})'}, puis saisissez la référence de la transaction.'
                    : 'Payez par Orange Money (numéro communiqué par le support), puis saisissez la référence de la transaction.',
                style: const TextStyle(color: AppColors.textMuted, height: 1.4),
              ),
              const SizedBox(height: 8),
              TextField(controller: ref0, decoration: const InputDecoration(labelText: 'Référence du paiement')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Envoyer la demande')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await runWithLoader(context, () => ref.read(gasRepositoryProvider).requestSubscription(place.id, plan.code, months, ref0.text),
          success: 'Demande envoyée : l’administration valide après vérification du paiement.');
    } catch (_) {}
    ref.invalidate(placeSubscriptionsProvider(place.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(vendorPlansProvider).value ?? const <VendorPlan>[];
    final subs = ref.watch(placeSubscriptionsProvider(place.id)).value ?? const <VendorSubscription>[];
    final active = subs.where((s) => s.activeNow).firstOrNull;
    final pending = subs.where((s) => s.status == 'pending').firstOrNull;
    final current = active == null ? null : plans.where((p) => p.code == active.planCode).firstOrNull;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Forfait actuel', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          Text(current?.name ?? 'Gratuit', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          if (active != null) Text('Valable jusqu’au ${formatDate(active.endsAt)}'),
          if (pending != null) const Padding(padding: EdgeInsets.only(top: 6), child: SmallTag('Demande en attente de validation', AppColors.accent, icon: Icons.hourglass_top_rounded)),
        ]),
      ),
      const SectionTitle('Choisir un forfait'),
      for (final p in plans)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.code == (current?.code ?? 'free') ? AppColors.primary : AppColors.line, width: 1.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              Text(p.priceMonthly == 0 ? 'Gratuit' : '${fcfa(p.priceMonthly)} / mois', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
            ]),
            const SizedBox(height: 6),
            for (final f in p.features)
              Padding(padding: const EdgeInsets.only(bottom: 3), child: Row(children: [const Icon(Icons.check_rounded, size: 16, color: AppColors.primary), const SizedBox(width: 6), Expanded(child: Text(f))])),
            if (p.priceMonthly > 0 && p.code != current?.code) ...[
              const SizedBox(height: 8),
              FilledButton(onPressed: pending != null ? null : () => _subscribe(context, ref, p), child: Text(pending != null ? 'Demande en cours' : 'Choisir ce forfait')),
            ],
          ]),
        ),
      if (subs.isNotEmpty) ...[
        const SectionTitle('Historique'),
        for (final s in subs)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${plans.where((p) => p.code == s.planCode).firstOrNull?.name ?? s.planCode} · ${s.months} mois · ${fcfa(s.amount)}'),
            subtitle: Text(formatDate(s.createdAt)),
            trailing: Text({'pending': 'En attente', 'active': 'Actif', 'rejected': 'Refusé', 'ended': 'Terminé'}[s.status] ?? s.status),
          ),
      ],
    ]);
  }
}
