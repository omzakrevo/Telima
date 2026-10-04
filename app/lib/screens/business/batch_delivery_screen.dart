import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/config_models.dart';
import '../../data/models/delivery.dart';
import '../../data/models/enums.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/package_form.dart';
import '../../widgets/payment_flow.dart';
import '../../widgets/point_form.dart';

class _Stop {
  DeliveryPoint? dropoff;
  PackageInfo package = PackageInfo();
}

/// Livraison multi-destinations : Boutique A → Client 1 → Client 2 → Client 3.
class BatchDeliveryScreen extends ConsumerStatefulWidget {
  const BatchDeliveryScreen({super.key, required this.businessId});
  final String businessId;
  @override
  ConsumerState<BatchDeliveryScreen> createState() => _BatchDeliveryScreenState();
}

class _BatchDeliveryScreenState extends ConsumerState<BatchDeliveryScreen> {
  final _pickupForm = GlobalKey<FormState>();
  DeliveryPoint? _pickup;
  final List<_Stop> _stops = [_Stop()];
  VehicleType _vehicle = VehicleType.moto;
  PaymentMethod _payment = PaymentMethod.cash;
  int? _estimate;
  double? _estimateKm;
  bool _estimating = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _pickup = DeliveryPoint(address: '', lat: 0, lng: 0, contactName: user?.fullName ?? '', contactPhone: user?.phone ?? '');
    ref.read(myBusinessesProvider.future).then((list) {
      final b = list.where((x) => x.id == widget.businessId).firstOrNull;
      if (b != null && b.lat != null && mounted) {
        setState(() => _pickup = DeliveryPoint(
              address: b.address ?? b.name,
              lat: b.lat!,
              lng: b.lng!,
              contactName: b.name,
              contactPhone: b.phone ?? user?.phone ?? '',
            ));
      }
    });
  }

  bool _valid(DeliveryPoint? p) => p != null && p.lat != 0;

  Future<void> _editStop(int i, List<SavedAddress> addresses) async {
    final stop = _stops[i];
    final formKey = GlobalKey<FormState>();
    final res = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Scaffold(
          appBar: AppBar(title: Text('Destination ${i + 1}')),
          body: Constrained(
            child: Form(
              key: formKey,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                DeliveryPointForm(
                  point: stop.dropoff,
                  isPickup: false,
                  savedAddresses: addresses,
                  onChanged: (p) => setLocal(() => stop.dropoff = p),
                ),
                const SectionTitle('Colis'),
                PackageForm(package: stop.package, compact: true, onChanged: () => setLocal(() {})),
              ]),
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: BigActionButton(
                label: 'Valider cette destination',
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  if (!_valid(stop.dropoff)) {
                    showError(ctx, Exception('Indiquez la position de la destination'));
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
              ),
            ),
          ),
        ),
      ),
    ));
    if (res == true) {
      setState(() {});
      _computeEstimate();
    }
  }

  Future<void> _computeEstimate() async {
    if (!_valid(_pickup) || _stops.any((s) => !_valid(s.dropoff))) return;
    setState(() => _estimating = true);
    try {
      final repo = ref.read(configRepositoryProvider);
      var prev = _pickup!;
      var total = 0;
      var dist = 0.0;
      for (var i = 0; i < _stops.length; i++) {
        final s = _stops[i];
        final q = await repo.quote(
          pickupLat: prev.lat,
          pickupLng: prev.lng,
          dropoffLat: s.dropoff!.lat,
          dropoffLng: s.dropoff!.lng,
          vehicle: _vehicle,
          size: s.package.size,
          fragile: s.package.fragile,
          category: s.package.category,
          extraStop: i > 0,
        );
        if (i == 0 && q.vehicleType != _vehicle) _vehicle = q.vehicleType;
        total += q.total;
        dist += q.distanceKm;
        prev = s.dropoff!;
      }
      setState(() {
        _estimate = total;
        _estimateKm = dist;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  Future<void> _submit() async {
    if (!_pickupForm.currentState!.validate() || !_valid(_pickup)) {
      showError(context, Exception('Complétez le point de récupération'));
      return;
    }
    if (_stops.any((s) => !_valid(s.dropoff))) {
      showError(context, Exception('Complétez toutes les destinations'));
      return;
    }
    setState(() => _submitting = true);
    try {
      final list = await ref.read(deliveryRepositoryProvider).createBatch(
            pickup: _pickup!,
            stops: [for (final s in _stops) (dropoff: s.dropoff!, package: s.package)],
            vehicle: _vehicle,
            payment: _payment,
            businessId: widget.businessId,
          );
      if (mounted) {
        showSuccess(context, '${list.length} livraisons créées (${list.first.code} …)');
        context.pushReplacement('/client/delivery/${list.first.id}');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final addresses = ref.watch(savedAddressesProvider(widget.businessId)).value ?? const [];
    final wallet = ref.watch(myWalletProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Multi-destinations')),
      body: Constrained(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
          const Text('1. Point de récupération', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Form(
            key: _pickupForm,
            child: DeliveryPointForm(
              key: ValueKey('pickup-${_pickup?.lat}'),
              point: _pickup,
              isPickup: true,
              onChanged: (p) => setState(() => _pickup = p),
            ),
          ),
          const SizedBox(height: 20),
          const Text('2. Destinations (dans l\'ordre de passage)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            onReorderItem: (a, b) {
              setState(() => _stops.insert(b, _stops.removeAt(a)));
              _computeEstimate();
            },
            children: [
              for (var i = 0; i < _stops.length; i++)
                Card(
                  key: ObjectKey(_stops[i]),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(child: Text('${i + 1}')),
                    title: Text(_stops[i].dropoff?.contactName.isNotEmpty == true ? _stops[i].dropoff!.contactName : 'Client ${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(_valid(_stops[i].dropoff)
                        ? '${_stops[i].dropoff!.address} · ${_stops[i].package.category.label}'
                        : 'À compléter'),
                    onTap: () => _editStop(i, addresses),
                    trailing: _stops.length > 1
                        ? IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() => _stops.removeAt(i));
                              _computeEstimate();
                            },
                          )
                        : null,
                  ),
                ),
            ],
          ),
          if (_stops.length < 15)
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _stops.add(_Stop()));
                _editStop(_stops.length - 1, addresses);
              },
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Ajouter une destination'),
            ),
          const SectionTitle('Véhicule'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in VehicleType.values)
              ChoiceChip(
                avatar: Icon(v.icon, size: 18),
                label: Text(v.label),
                selected: _vehicle == v,
                onSelected: (_) {
                  setState(() => _vehicle = v);
                  _computeEstimate();
                },
              ),
          ]),
          const SectionTitle('Paiement'),
          PaymentMethodPicker(
            value: _payment,
            allowed: const [PaymentMethod.cash, PaymentMethod.cash_on_delivery, PaymentMethod.wallet],
            walletBalance: wallet?.balance,
            onChanged: (m) => setState(() => _payment = m),
          ),
          const SectionTitle('Estimation'),
          if (_estimating)
            const LoadingView()
          else if (_estimate != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  InfoRow(label: 'Arrêts', value: '${_stops.length}'),
                  InfoRow(label: 'Distance totale', value: km(_estimateKm)),
                  InfoRow(label: 'Total', value: fcfa(_estimate), bold: true),
                  const Text('Un seul livreur effectue toute la tournée. L\'optimisation automatique de l\'ordre sera proposée prochainement.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ]),
              ),
            )
          else
            const Text('Complétez les destinations pour voir le prix.'),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Constrained(
            child: BigActionButton(
              label: 'CONFIRMER LES ${_stops.length} LIVRAISONS',
              color: AppColors.accent,
              loading: _submitting,
              onPressed: _estimate == null ? null : _submit,
            ),
          ),
        ),
      ),
    );
  }
}
