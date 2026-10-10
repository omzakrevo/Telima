import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../data/models/delivery.dart';
import '../../data/models/restaurant.dart';
import '../../providers/auth_providers.dart';
import '../../providers/data_providers.dart';
import '../../providers/restaurant_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/point_form.dart';
import 'restaurant_widgets.dart';

/// Panier et confirmation de la commande d'un restaurant (ouvert depuis le lien partagé).
class RestaurantCheckoutScreen extends ConsumerStatefulWidget {
  const RestaurantCheckoutScreen({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<RestaurantCheckoutScreen> createState() => _RestaurantCheckoutScreenState();
}

class _RestaurantCheckoutScreenState extends ConsumerState<RestaurantCheckoutScreen> {
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

  Future<void> _computeFee(Restaurant r) async {
    if (!_dropValid) return;
    setState(() {
      _feeLoading = true;
      _feeError = null;
      _fee = null;
    });
    try {
      final res = await ref.read(restaurantRepositoryProvider).deliveryFee(r.id, _drop!.lat, _drop!.lng);
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

  Future<void> _submit(Restaurant r, Map<String, int> lines) async {
    if (lines.isEmpty) {
      showError(context, Exception('Choisissez au moins un plat'));
      return;
    }
    if (_mode == 'delivery' && (!_dropValid || _fee == null)) {
      showError(context, _feeError ?? Exception('Indiquez l’adresse de livraison'));
      return;
    }
    setState(() => _submitting = true);
    try {
      final o = await ref.read(restaurantRepositoryProvider).createOrder(
            restaurantId: r.id,
            mode: _mode,
            items: lines,
            note: _note.text,
            dropoff: _mode == 'delivery'
                ? {'address': _drop!.address, 'lat': _drop!.lat, 'lng': _drop!.lng, 'note': _drop!.instructions}
                : null,
          );
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(myRestaurantOrdersProvider);
      if (mounted) {
        showSuccess(context, 'Commande envoyée au restaurant');
        context.go('/client/restaurants/orders/${o.id}');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(restaurantBySlugProvider(widget.slug));
    final cart = ref.watch(cartProvider);
    final r = async.value;
    if (r == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ma commande')),
        body: async.isLoading
            ? const LoadingView()
            : const EmptyState(icon: Icons.storefront_outlined, message: 'Ce restaurant n’est plus disponible.'),
      );
    }

    // Les plats retirés ou épuisés depuis l'ajout au panier sont écartés ici ; le serveur revérifie de toute façon.
    final lines = <MenuItem, int>{};
    if (cart.restaurantId == r.id) {
      for (final i in r.items) {
        final q = cart.quantityOf(i.id);
        if (q > 0 && i.isAvailable) lines[i] = q;
      }
    }
    final itemsTotal = lines.entries.fold<int>(0, (s, e) => s + e.key.price * e.value);

    // Mode par défaut : celui que le restaurant propose.
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
            _TotalLine('Plats', fcfa(itemsTotal)),
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
                  : () => _submit(r, {for (final e in lines.entries) e.key.id: e.value}),
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
              child: const Text('Ce restaurant ne prend plus de commande pour le moment.',
                  style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
            ),
          const SectionTitle('Votre panier'),
          if (lines.isEmpty)
            Column(children: [
              const Text('Votre panier est vide.', style: TextStyle(color: AppColors.textMuted)),
              TextButton(onPressed: () => context.go('/r/${r.slug}'), child: const Text('Retour au menu')),
            ]),
          for (final e in lines.entries)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.key.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(fcfa(e.key.price * e.value), style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
                  ]),
                ),
                QtyStepper(
                  qty: e.value,
                  onAdd: () => ref.read(cartProvider.notifier).add(r.id, e.key.id),
                  onRemove: () => ref.read(cartProvider.notifier).remove(e.key.id),
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
            const SectionTitle('Un message pour le restaurant ?'),
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
                Expanded(child: Text('Paiement en espèces à la remise (restaurant ou livreur).', style: TextStyle(height: 1.3))),
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
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip(this.order, {super.key});
  final RestaurantOrder order;
  @override
  Widget build(BuildContext context) => InfoTag(order.statusLabel, color: order.statusColor);
}

/// Mes commandes de restaurants.
class RestaurantOrdersScreen extends ConsumerWidget {
  const RestaurantOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myRestaurantOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes commandes de repas')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myRestaurantOrdersProvider),
        child: AsyncBody<List<RestaurantOrder>>(
          value: async,
          onRetry: () => ref.invalidate(myRestaurantOrdersProvider),
          builder: (list) => list.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 80),
                  Icon(Icons.restaurant_rounded, size: 56, color: AppColors.textMuted),
                  SizedBox(height: 12),
                  Center(child: Text('Aucune commande de repas', style: TextStyle(fontWeight: FontWeight.w700))),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final o = list[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => context.push('/client/restaurants/orders/${o.id}'),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(o.restaurantName ?? o.code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                            OrderStatusChip(o),
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

/// Suivi d'une commande de restaurant (se met à jour toutes les 15 secondes).
class RestaurantOrderDetailScreen extends ConsumerStatefulWidget {
  const RestaurantOrderDetailScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<RestaurantOrderDetailScreen> createState() => _RestaurantOrderDetailScreenState();
}

class _RestaurantOrderDetailScreenState extends ConsumerState<RestaurantOrderDetailScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) ref.invalidate(restaurantOrderProvider(widget.orderId));
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
    final async = ref.watch(restaurantOrderProvider(orderId));
    final me = ref.watch(currentUserProvider)?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Ma commande')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(restaurantOrderProvider(orderId)),
        child: AsyncBody<RestaurantOrder>(
          value: async,
          onRetry: () => ref.invalidate(restaurantOrderProvider(orderId)),
          builder: (o) {
            final failed = o.status == 'rejected' || o.status == 'cancelled';
            final idx = o.steps.indexWhere((s) => s.$1 == o.status);
            final isCustomer = o.customerId == null || o.customerId == me;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Constrained(
                maxWidth: 720,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(o.restaurantName ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
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
                  if (!o.isDelivery && o.restaurantPosition != null && o.isOpen) ...[
                    BigActionButton(label: 'ITINÉRAIRE', icon: Icons.directions_rounded, onPressed: () => openNavigation(o.restaurantPosition!)),
                  ],
                  if ((o.restaurantPhone ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () => callPhone(o.restaurantPhone!),
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('APPELER LE RESTAURANT'),
                    ),
                  ],
                  if (o.restaurantSlug != null) ...[
                    const SizedBox(height: 6),
                    TextButton(onPressed: () => context.push('/r/${o.restaurantSlug}'), child: const Text('Commander à nouveau')),
                  ],
                  if (o.status == 'sent' && isCustomer) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () async {
                        final ok = await confirmDialog(context, title: 'Annuler la commande ?', confirmLabel: 'Annuler la commande', danger: true);
                        if (!ok || !context.mounted) return;
                        await runWithLoader(context, () => ref.read(restaurantRepositoryProvider).cancelOrder(o.id), success: 'Commande annulée');
                        ref.invalidate(restaurantOrderProvider(orderId));
                        ref.invalidate(myRestaurantOrdersProvider);
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
