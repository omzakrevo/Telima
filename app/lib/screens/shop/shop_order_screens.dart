import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../data/models/delivery.dart';
import '../../data/models/shop.dart';
import '../../providers/auth_providers.dart';
import '../../providers/data_providers.dart';
import '../../providers/shop_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/point_form.dart';
import 'shop_widgets.dart';

/// Panier et confirmation de la commande d'une boutique (ouvert depuis le lien partagé).
class ShopCheckoutScreen extends ConsumerStatefulWidget {
  const ShopCheckoutScreen({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<ShopCheckoutScreen> createState() => _ShopCheckoutScreenState();
}

class _ShopCheckoutScreenState extends ConsumerState<ShopCheckoutScreen> {
  final _note = TextEditingController();
  String _mode = 'pickup';
  DeliveryPoint? _drop;
  int? _fee;
  double? _km;
  Object? _feeError;
  bool _feeLoading = false;
  bool _submitting = false;
  bool _modeChosen = false;

  @override
  void initState() {
    super.initState();
    final u = ref.read(currentUserProvider);
    _drop = DeliveryPoint(address: '', lat: 0, lng: 0, contactName: u?.fullName ?? '', contactPhone: displayPhone(u?.phone));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _dropValid => _drop != null && _drop!.address.trim().isNotEmpty && _drop!.lat != 0 && _drop!.lng != 0;

  Future<void> _computeFee(Shop r) async {
    if (!_dropValid) return;
    setState(() {
      _feeLoading = true;
      _feeError = null;
      _fee = null;
    });
    try {
      final res = await ref.read(shopRepositoryProvider).deliveryFee(r.id, _drop!.lat, _drop!.lng);
      if (mounted) {
        setState(() {
          _fee = res.fee;
          _km = res.km;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _feeError = e);
    } finally {
      if (mounted) setState(() => _feeLoading = false);
    }
  }

  Future<void> _submit(Shop r, List<({CartLine line, ShopProduct item})> lines) async {
    if (lines.isEmpty) {
      showError(context, Exception('Choisissez au moins un article'));
      return;
    }
    if (_mode == 'delivery' && (!_dropValid || _fee == null)) {
      showError(context, _feeError ?? Exception('Indiquez l’adresse de livraison'));
      return;
    }
    setState(() => _submitting = true);
    try {
      final o = await ref.read(shopRepositoryProvider).createOrder(
            shopId: r.id,
            mode: _mode,
            items: [
              for (final e in lines)
                {'item_id': e.line.itemId, 'qty': e.line.qty, if (e.line.size != null) 'size': e.line.size, if (e.line.color != null) 'color': e.line.color},
            ],
            note: _note.text,
            dropoff: _mode == 'delivery'
                ? {'address': _drop!.address, 'lat': _drop!.lat, 'lng': _drop!.lng, 'note': _drop!.instructions}
                : null,
          );
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(myShopOrdersProvider);
      if (mounted) {
        showSuccess(context, 'Commande envoyée à la boutique');
        context.go('/client/shops/orders/${o.id}');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(shopBySlugProvider(widget.slug));
    final cart = ref.watch(cartProvider);
    final r = async.value;
    if (r == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ma commande')),
        body: async.isLoading
            ? const LoadingView()
            : const EmptyState(icon: Icons.storefront_outlined, message: 'Cette boutique n’est plus disponible.'),
      );
    }

    // Les articles retirés ou épuisés depuis l'ajout au panier sont écartés ici ; le serveur revérifie de toute façon.
    final lines = <({CartLine line, ShopProduct item})>[];
    if (cart.shopId == r.id) {
      for (final l in cart.lines.values) {
        final matches = r.items.where((i) => i.id == l.itemId);
        if (matches.isNotEmpty && matches.first.inStock) lines.add((line: l, item: matches.first));
      }
    }
    final itemsTotal = lines.fold<int>(0, (s, e) => s + e.item.price * e.line.qty);

    // Mode par défaut : celui que la boutique propose.
    if (!_modeChosen) {
      _mode = r.acceptsPickup ? 'pickup' : 'delivery';
    }
    final fee = _mode == 'delivery' ? (_fee ?? 0) : 0;
    final total = itemsTotal + fee;
    final belowMin = itemsTotal < r.minOrder;
    final addresses = ref.watch(savedAddressesProvider(null)).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text('Commander · ${r.name}')),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _TotalLine('Articles', fcfa(itemsTotal)),
            if (_mode == 'delivery')
              _TotalLine('Livraison${_km == null ? '' : ' (${km(_km)})'}', _feeLoading ? '…' : (_fee == null ? 'à calculer' : fcfa(_fee))),
            const Divider(height: 14),
            _TotalLine('TOTAL À PAYER', fcfa(total), bold: true),
            if (belowMin)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Commande minimum : ${fcfa(r.minOrder)}', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 8),
            BigActionButton(
              label: 'CONFIRMER LA COMMANDE',
              icon: Icons.check_rounded,
              loading: _submitting,
              onPressed: belowMin || lines.isEmpty || !r.acceptingOrders
                  ? null
                  : () => _submit(r, lines),
            ),
          ]),
        ),
      ),
      body: Constrained(
        maxWidth: 720,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (!r.acceptingOrders)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: const Text('Cette boutique ne prend plus de commande pour le moment.',
                  style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
            ),
          const SectionTitle('Votre panier'),
          if (lines.isEmpty)
            Column(children: [
              const Text('Votre panier est vide.', style: TextStyle(color: AppColors.textMuted)),
              TextButton(onPressed: () => context.go('/b/${r.slug}'), child: const Text('Retour au catalogue')),
            ]),
          for (final e in lines)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.item.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    if ([if (e.line.size != null) 'Taille ${e.line.size}', if (e.line.color != null) e.line.color!].isNotEmpty)
                      Text([if (e.line.size != null) 'Taille ${e.line.size}', if (e.line.color != null) e.line.color!].join(' · '),
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    Text(fcfa(e.item.price * e.line.qty), style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
                  ]),
                ),
                ShopQtyStepper(
                  qty: e.line.qty,
                  onAdd: () => ref.read(cartProvider.notifier).add(r.id, e.line.itemId, size: e.line.size, color: e.line.color, maxQty: e.item.stock),
                  onRemove: () => ref.read(cartProvider.notifier).remove(e.line.key),
                ),
              ]),
            ),
          if (lines.isNotEmpty) ...[
            const SectionTitle('Comment la recevoir ?'),
            Row(children: [
              Expanded(
                child: _ModeCard(
                  icon: Icons.storefront_rounded,
                  title: 'Retrait',
                  caption: r.acceptsPickup ? 'Sur place' : 'Non proposé',
                  selected: _mode == 'pickup',
                  onTap: r.acceptsPickup ? () => setState(() { _mode = 'pickup'; _modeChosen = true; }) : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ModeCard(
                  icon: Icons.delivery_dining_rounded,
                  title: 'Livraison',
                  caption: r.delivers ? 'À domicile' : 'Non proposée',
                  selected: _mode == 'delivery',
                  onTap: r.delivers ? () => setState(() { _mode = 'delivery'; _modeChosen = true; }) : null,
                ),
              ),
            ]),
            if (_mode == 'pickup' && (r.address ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.place_rounded, size: 18, color: AppColors.primaryDark),
                const SizedBox(width: 8),
                Expanded(child: Text('À retirer chez ${r.name} : ${r.address}')),
              ]),
            ],
            if (_mode == 'delivery') ...[
              const SectionTitle('Adresse de livraison'),
              DeliveryPointForm(
                point: _drop,
                isPickup: false,
                savedAddresses: addresses,
                showContact: false,
                addressLabel: 'Quartier, repère',
                contactRequired: false,
                mapTitle: 'Adresse de livraison',
                onChanged: (p) {
                  final moved = _drop == null || p.lat != _drop!.lat || p.lng != _drop!.lng;
                  setState(() => _drop = p);
                  if (moved) _computeFee(r);
                },
              ),
              if (_feeError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(friendlyError(_feeError!), style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                ),
            ],
            const SectionTitle('Un message pour la boutique ? (taille, couleur, précision)'),
            TextField(
              controller: _note,
              maxLines: 2,
              maxLength: 200,
              decoration: const InputDecoration(hintText: 'Ex. sans piment, bien cuit…'),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(14)),
              child: const Row(children: [
                Icon(Icons.payments_rounded, color: AppColors.primaryDark),
                SizedBox(width: 10),
                Expanded(child: Text('Paiement en espèces à la remise (boutique ou livreur).', style: TextStyle(height: 1.3))),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: bold ? 18 : 14, color: bold ? AppColors.primaryDark : null)),
        ]),
      );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.icon, required this.title, required this.caption, required this.selected, required this.onTap});
  final IconData icon;
  final String title;
  final String caption;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? AppColors.mint : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? AppColors.primary : AppColors.line, width: selected ? 2 : 1),
            ),
            child: Column(children: [
              Icon(icon, size: 30, color: AppColors.primaryDark),
              const SizedBox(height: 6),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(caption, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ),
        ),
      );
}

/// Étiquette colorée du statut d'une commande.
class ShopOrderStatusChip extends StatelessWidget {
  const ShopOrderStatusChip(this.order, {super.key});
  final ShopOrder order;
  @override
  Widget build(BuildContext context) => ShopInfoTag(order.statusLabel, color: order.statusColor);
}

/// Mes commandes de boutiques.
class ShopOrdersScreen extends ConsumerWidget {
  const ShopOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myShopOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes commandes en boutique')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myShopOrdersProvider),
        child: AsyncBody<List<ShopOrder>>(
          value: async,
          onRetry: () => ref.invalidate(myShopOrdersProvider),
          builder: (list) => list.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  Icon(Icons.storefront_rounded, size: 56, color: AppColors.textMuted),
                  SizedBox(height: 12),
                  Center(child: Text('Aucune commande en boutique', style: TextStyle(fontWeight: FontWeight.w700))),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final o = list[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => context.push('/client/shops/orders/${o.id}'),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(o.shopName ?? o.code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                            ShopOrderStatusChip(o),
                          ]),
                          const SizedBox(height: 6),
                          Text(o.items.map((e) => e.text).join(', '), style: const TextStyle(color: AppColors.textMuted)),
                          const SizedBox(height: 4),
                          Text('${o.code} · ${fcfa(o.total)} · ${relativeTime(o.createdAt)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// Suivi d'une commande de boutique (se met à jour toutes les 15 secondes).
class ShopOrderDetailScreen extends ConsumerStatefulWidget {
  const ShopOrderDetailScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<ShopOrderDetailScreen> createState() => _ShopOrderDetailScreenState();
}

class _ShopOrderDetailScreenState extends ConsumerState<ShopOrderDetailScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) ref.invalidate(shopOrderProvider(widget.orderId));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderId = widget.orderId;
    final async = ref.watch(shopOrderProvider(orderId));
    final me = ref.watch(currentUserProvider)?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Ma commande')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(shopOrderProvider(orderId)),
        child: AsyncBody<ShopOrder>(
          value: async,
          onRetry: () => ref.invalidate(shopOrderProvider(orderId)),
          builder: (o) {
            final failed = o.status == 'rejected' || o.status == 'cancelled';
            final idx = o.steps.indexWhere((s) => s.$1 == o.status);
            final isCustomer = o.customerId == null || o.customerId == me;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Constrained(
                maxWidth: 720,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(o.shopName ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
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
                          Icon(i <= idx ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                              color: i <= idx ? AppColors.primary : AppColors.line, size: 26),
                          const SizedBox(width: 12),
                          Text(s.$2, style: TextStyle(fontWeight: i == idx ? FontWeight.w800 : FontWeight.w500, color: i > idx ? AppColors.textMuted : null)),
                        ]),
                      ),
                  const SectionTitle('Détail'),
                  for (final i in o.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [Expanded(child: Text(i.text)), Text(fcfa(i.unitPrice * i.qty))]),
                    ),
                  if (o.isDelivery) Row(children: [const Expanded(child: Text('Livraison')), Text(fcfa(o.deliveryFee))]),
                  const Divider(),
                  Row(children: [
                    const Expanded(child: Text('TOTAL À PAYER', style: TextStyle(fontWeight: FontWeight.w800))),
                    Text(fcfa(o.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.primaryDark)),
                  ]),
                  Text(o.paymentStatus == 'paid' ? 'Payé' : 'À régler en espèces à la remise', style: const TextStyle(color: AppColors.textMuted)),
                  if ((o.note ?? '').isNotEmpty) ...[
                    const SectionTitle('Votre message'),
                    Text(o.note!),
                  ],
                  if (o.isDelivery && o.dropoffAddress != null) ...[
                    const SectionTitle('Livraison à'),
                    Text(o.dropoffAddress!),
                  ],
                  const SizedBox(height: 16),
                  if (o.deliveryId != null && o.isOpen && isCustomer)
                    BigActionButton(
                      label: 'SUIVRE MON LIVREUR',
                      icon: Icons.delivery_dining_rounded,
                      onPressed: () => context.push('/client/delivery/${o.deliveryId}'),
                    ),
                  if (!o.isDelivery && o.shopPosition != null && o.isOpen) ...[
                    BigActionButton(label: 'ITINÉRAIRE', icon: Icons.directions_rounded, onPressed: () => openNavigation(o.shopPosition!)),
                  ],
                  if ((o.shopPhone ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () => callPhone(o.shopPhone!),
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('APPELER LA BOUTIQUE'),
                    ),
                  ],
                  if (o.shopSlug != null) ...[
                    const SizedBox(height: 6),
                    TextButton(onPressed: () => context.push('/b/${o.shopSlug}'), child: const Text('Commander à nouveau')),
                  ],
                  if (o.status == 'sent' && isCustomer) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () async {
                        final ok = await confirmDialog(context, title: 'Annuler la commande ?', confirmLabel: 'Annuler la commande', danger: true);
                        if (!ok || !context.mounted) return;
                        await runWithLoader(context, () => ref.read(shopRepositoryProvider).cancelOrder(o.id), success: 'Commande annulée');
                        ref.invalidate(shopOrderProvider(orderId));
                        ref.invalidate(myShopOrdersProvider);
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
