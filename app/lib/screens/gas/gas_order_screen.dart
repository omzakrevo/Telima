import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/delivery.dart';
import '../../data/models/gas.dart';
import '../../providers/auth_providers.dart';
import '../../providers/data_providers.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/point_form.dart';
import 'gas_widgets.dart';

/// Commande de gaz : bouteilles, retrait ou livraison, total clair avant de confirmer.
class GasOrderScreen extends ConsumerStatefulWidget {
  const GasOrderScreen({super.key, required this.placeId, this.initial});
  final String placeId;
  final Place? initial;

  @override
  ConsumerState<GasOrderScreen> createState() => _GasOrderScreenState();
}

class _GasOrderScreenState extends ConsumerState<GasOrderScreen> {
  final _qty = <String, int>{};
  String _mode = 'pickup';
  DeliveryPoint? _drop;
  int? _fee;
  double? _km;
  Object? _feeError;
  bool _feeLoading = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final u = ref.read(currentUserProvider);
    _drop = DeliveryPoint(address: '', lat: 0, lng: 0, contactName: u?.fullName ?? '', contactPhone: displayPhone(u?.phone));
  }

  bool get _dropValid => _drop != null && _drop!.address.trim().isNotEmpty && _drop!.lat != 0 && _drop!.lng != 0;

  Future<void> _computeFee(Place place) async {
    if (!_dropValid) return;
    setState(() {
      _feeLoading = true;
      _feeError = null;
      _fee = null;
    });
    try {
      final r = await ref.read(gasRepositoryProvider).deliveryFee(place.id, _drop!.lat, _drop!.lng);
      if (mounted) {
        setState(() {
          _fee = r.fee;
          _km = r.km;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _feeError = e);
    } finally {
      if (mounted) setState(() => _feeLoading = false);
    }
  }

  int _items(Place place) => place.products.fold(0, (s, p) => s + p.finalPrice * (_qty[p.id] ?? 0));

  Future<void> _submit(Place place) async {
    final items = {for (final e in _qty.entries) if (e.value > 0) e.key: e.value};
    if (items.isEmpty) {
      showError(context, Exception('Choisissez au moins une bouteille'));
      return;
    }
    if (_mode == 'delivery' && (!_dropValid || _fee == null)) {
      showError(context, Exception('Indiquez l’adresse de livraison'));
      return;
    }
    setState(() => _submitting = true);
    try {
      final o = await ref.read(gasRepositoryProvider).createOrder(
            placeId: place.id,
            mode: _mode,
            items: items,
            dropoff: _mode == 'delivery'
                ? {'address': _drop!.address, 'lat': _drop!.lat, 'lng': _drop!.lng, 'note': _drop!.instructions}
                : null,
          );
      ref.invalidate(myGasOrdersProvider);
      ref.invalidate(placeProvider(place.id));
      if (mounted) {
        showSuccess(context, 'Commande envoyée au vendeur');
        context.go('/client/gas/orders/${o.id}');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(placeProvider(widget.placeId));
    final place = async.value ?? widget.initial;
    if (place == null) return Scaffold(appBar: AppBar(title: const Text('Commander')), body: const LoadingView());
    final addresses = ref.watch(savedAddressesProvider(null)).value ?? const [];
    final items = _items(place);
    final fee = _mode == 'delivery' ? (_fee ?? 0) : 0;
    final total = items + fee;
    final sellable = place.products.where((p) => p.availability.orderable).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Commander · ${place.name}')),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Line('Gaz', fcfa(items)),
            if (_mode == 'delivery') _Line('Livraison${_km == null ? '' : ' (${km(_km)})'}', _feeLoading ? '…' : (_fee == null ? 'à calculer' : fcfa(_fee))),
            const Divider(height: 14),
            _Line('TOTAL À PAYER', fcfa(total), bold: true),
            const SizedBox(height: 8),
            BigActionButton(label: 'CONFIRMER LA COMMANDE', icon: Icons.check_rounded, loading: _submitting, onPressed: () => _submit(place)),
          ]),
        ),
      ),
      body: Constrained(
        maxWidth: 720,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const SectionTitle('Quelles bouteilles ?'),
          if (sellable.isEmpty) const Text('Aucune bouteille disponible.', style: TextStyle(color: AppColors.textMuted)),
          for (final p in sellable)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${p.brand} · ${p.sizeLabel}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(p.onPromo ? '${fcfa(p.finalPrice)} (au lieu de ${fcfa(p.price)})' : fcfa(p.finalPrice), style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    AvailabilityChip(p.availability, at: p.confirmedAt),
                  ]),
                ),
                IconButton.filledTonal(
                  onPressed: (_qty[p.id] ?? 0) > 0 ? () => setState(() => _qty[p.id] = (_qty[p.id] ?? 0) - 1) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(width: 28, child: Text('${_qty[p.id] ?? 0}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                IconButton.filled(
                  onPressed: (_qty[p.id] ?? 0) < 10 ? () => setState(() => _qty[p.id] = (_qty[p.id] ?? 0) + 1) : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ]),
            ),
          const SectionTitle('Comment la recevoir ?'),
          Row(children: [
            Expanded(child: _ModeCard(icon: Icons.storefront_rounded, title: 'Retrait', caption: 'Sur place', selected: _mode == 'pickup', onTap: () => setState(() => _mode = 'pickup'))),
            const SizedBox(width: 10),
            Expanded(
              child: _ModeCard(
                icon: Icons.delivery_dining_rounded,
                title: 'Livraison',
                caption: place.delivers ? 'À domicile' : 'Non proposée',
                selected: _mode == 'delivery',
                onTap: place.delivers ? () => setState(() => _mode = 'delivery') : null,
              ),
            ),
          ]),
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
                if (moved) _computeFee(place);
              },
            ),
            if (_feeError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(friendlyError(_feeError!), style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(14)),
            child: const Row(children: [
              Icon(Icons.payments_rounded, color: AppColors.primaryDark),
              SizedBox(width: 10),
              Expanded(child: Text('Paiement en espèces à la remise (vendeur ou livreur).', style: TextStyle(height: 1.3))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.bold = false});
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
