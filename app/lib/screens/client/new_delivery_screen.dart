import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/delivery.dart';
import '../../data/models/enums.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/package_form.dart';
import '../../widgets/payment_flow.dart';
import '../../widgets/point_form.dart';

int vehicleRank(VehicleType v) => switch (v) {
      VehicleType.moto => 1,
      VehicleType.tricycle || VehicleType.voiture => 2,
      VehicleType.utilitaire => 3,
    };

class NewDeliveryScreen extends ConsumerStatefulWidget {
  const NewDeliveryScreen({super.key, this.businessId});
  final String? businessId;

  @override
  ConsumerState<NewDeliveryScreen> createState() => _NewDeliveryScreenState();
}

class _NewDeliveryScreenState extends ConsumerState<NewDeliveryScreen> {
  int _step = 0;
  final _forms = [GlobalKey<FormState>(), GlobalKey<FormState>(), GlobalKey<FormState>()];
  DeliveryPoint? _pickup;
  DeliveryPoint? _dropoff;
  PackageInfo _package = PackageInfo();
  VehicleType? _vehicle;
  PaymentMethod _payment = PaymentMethod.cash;
  Quote? _quote;
  double? _routeKm;
  Object? _quoteError;
  bool _quoting = false;
  bool _submitting = false;

  String get _draftKey => 'draft:new_delivery:${widget.businessId ?? 'perso'}';

  static const _titles = ['Point de récupération', 'Destination', 'Le colis', 'Confirmation'];

  @override
  void initState() {
    super.initState();
    _restoreDraft();
  }

  void _restoreDraft() {
    final user = ref.read(currentUserProvider);
    final raw = ref.read(cacheProvider).prefs.getString(_draftKey);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        DeliveryPoint? point(Map? m) => m == null
            ? null
            : DeliveryPoint(
                address: m['address'] ?? '',
                lat: (m['lat'] as num).toDouble(),
                lng: (m['lng'] as num).toDouble(),
                contactName: m['contact_name'] ?? '',
                contactPhone: m['contact_phone'] ?? '',
                instructions: m['instructions'] ?? '',
              );
        _pickup = point(j['pickup'] as Map?);
        _dropoff = point(j['dropoff'] as Map?);
        final pk = j['package'] as Map?;
        if (pk != null) {
          _package = PackageInfo(
            category: PackageCategory.parse(pk['category'] as String?),
            description: pk['description'] as String? ?? '',
            quantity: (pk['quantity'] as num?)?.toInt() ?? 1,
            fragile: pk['fragile'] == true,
            size: PackageSize.parse(pk['size'] as String?),
            weightKg: (pk['weight_kg'] as num?)?.toDouble(),
            photoPath: pk['photo_path'] as String?,
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showSuccess(context, 'Votre demande précédente a été restaurée.');
        });
      } catch (_) {}
    }
    _pickup ??= DeliveryPoint(address: '', lat: 0, lng: 0, contactName: user?.fullName ?? '', contactPhone: displayPhone(user?.phone));
  }

  void _saveDraft() {
    ref.read(cacheProvider).prefs.setString(
        _draftKey,
        jsonEncode({
          'pickup': _pickup?.toJson(),
          'dropoff': _dropoff?.toJson(),
          'package': _package.toJson(),
        }));
  }

  void _clearDraft() => ref.read(cacheProvider).prefs.remove(_draftKey);

  bool _validPoint(DeliveryPoint? p) => p != null && p.lat != 0 && p.lng != 0;

  void _next() {
    if (_step < 3) {
      if (!_forms[_step].currentState!.validate()) return;
      if (_step == 0 && !_validPoint(_pickup)) {
        showError(context, Exception('Indiquez la position du point de récupération'));
        return;
      }
      if (_step == 1 && !_validPoint(_dropoff)) {
        showError(context, Exception('Indiquez la position de la destination'));
        return;
      }
      _saveDraft();
      setState(() => _step++);
      if (_step == 3) _computeQuote(resetVehicle: true);
    }
  }

  void _back() {
    if (_step == 0) {
      context.pop();
    } else {
      setState(() => _step--);
    }
  }

  Future<void> _computeQuote({bool resetVehicle = false}) async {
    setState(() {
      _quoting = true;
      _quoteError = null;
    });
    try {
      if (_routeKm == null) {
        final route = await ref.read(routingServiceProvider).route([_pickup!.latLng, _dropoff!.latLng]);
        if (!route.isEstimate) _routeKm = double.parse(route.distanceKm.toStringAsFixed(2));
      }
      final q = await ref.read(configRepositoryProvider).quote(
            pickupLat: _pickup!.lat,
            pickupLng: _pickup!.lng,
            dropoffLat: _dropoff!.lat,
            dropoffLng: _dropoff!.lng,
            vehicle: resetVehicle ? null : _vehicle,
            size: _package.size,
            fragile: _package.fragile,
            weightKg: _package.weightKg,
            category: _package.category,
            routeKm: _routeKm,
          );
      if (!mounted) return;
      setState(() {
        _quote = q;
        _vehicle = q.vehicleType;
      });
    } catch (e) {
      if (mounted) setState(() => _quoteError = e);
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _confirm() async {
    if (_quote == null || _vehicle == null) return;
    setState(() => _submitting = true);
    try {
      final repo = ref.read(deliveryRepositoryProvider);
      final delivery = await repo.create(
        pickup: _pickup!,
        dropoff: _dropoff!,
        package: _package,
        vehicle: _vehicle!,
        payment: _payment,
        routeKm: _routeKm,
        businessId: widget.businessId,
      );
      _clearDraft();
      ref.invalidate(myActiveDeliveriesProvider);
      if (_payment.isMobileMoney && mounted) {
        final payment = await repo.pendingPayment(delivery.id);
        if (payment != null && mounted) await runMobileMoneyPayment(context, ref, payment);
      }
      if (mounted) context.pushReplacement('/client/delivery/${delivery.id}');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final addresses = ref.watch(savedAddressesProvider(widget.businessId)).value ?? const [];
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.businessId != null ? 'Livraison (pro)' : 'Nouvelle livraison'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(36),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: Container(
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i <= _step ? AppColors.primary : const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        body: Constrained(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
            Text('${_step + 1}/4 · ${_titles[_step]}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            if (_step == 0)
              Form(
                key: _forms[0],
                child: DeliveryPointForm(
                  key: const ValueKey('pickup'),
                  point: _pickup,
                  isPickup: true,
                  savedAddresses: addresses,
                  onChanged: (p) => setState(() {
                    _pickup = p;
                    _routeKm = null;
                  }),
                ),
              ),
            if (_step == 1)
              Form(
                key: _forms[1],
                child: DeliveryPointForm(
                  key: const ValueKey('dropoff'),
                  point: _dropoff,
                  isPickup: false,
                  savedAddresses: addresses,
                  onChanged: (p) => setState(() {
                    _dropoff = p;
                    _routeKm = null;
                  }),
                ),
              ),
            if (_step == 2) Form(key: _forms[2], child: PackageForm(package: _package, onChanged: () => setState(() {}))),
            if (_step == 3) _summary(),
          ]),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Constrained(
              child: _step < 3
                  ? BigActionButton(label: 'Continuer', icon: Icons.arrow_forward, onPressed: _next)
                  : BigActionButton(
                      label: 'Confirmer la livraison',
                      icon: Icons.check_circle,
                      color: AppColors.accent,
                      loading: _submitting,
                      onPressed: (_quote == null || _quoting) ? null : _confirm,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary() {
    final wallet = ref.watch(myWalletProvider).value;
    final suggested = _quote?.suggestedVehicle ?? VehicleType.moto;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            _routeLine(Icons.store_mall_directory, AppColors.primary, _pickup!.address, _pickup!.contactName),
            const Padding(padding: EdgeInsets.only(left: 11), child: Align(alignment: Alignment.centerLeft, child: SizedBox(height: 16, child: VerticalDivider()))),
            _routeLine(Icons.flag, AppColors.danger, _dropoff!.address, _dropoff!.contactName),
            const Divider(),
            Row(children: [
              Icon(_package.category.icon, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    '${_package.category.label} · ${_package.size.label} · x${_package.quantity}${_package.fragile ? ' · Fragile' : ''}'),
              ),
            ]),
          ]),
        ),
      ),
      const SectionTitle('Moyen de transport'),
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8,
        childAspectRatio: 0.95,
        children: [
          for (final v in VehicleType.values)
            Opacity(
              opacity: vehicleRank(v) < vehicleRank(suggested) ? 0.35 : 1,
              child: ChoiceTile(
                label: v.label,
                subtitle: v == suggested ? 'Conseillé' : null,
                icon: v.icon,
                selected: _vehicle == v,
                onTap: () {
                  if (vehicleRank(v) < vehicleRank(suggested)) {
                    showError(context, Exception('Ce véhicule est trop petit pour votre colis.'));
                    return;
                  }
                  setState(() => _vehicle = v);
                  _computeQuote();
                },
              ),
            ),
        ],
      ),
      const SectionTitle('Prix estimé'),
      if (_quoting)
        const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())))
      else if (_quoteError != null)
        ErrorView(error: _quoteError!, onRetry: _computeQuote)
      else if (_quote != null)
        PriceSummary(
          distanceKm: _quote!.distanceKm,
          total: _quote!.total,
          base: _quote!.priceBase,
          distancePrice: _quote!.priceDistance,
          extras: _quote!.priceExtras,
          zone: _quote!.priceZone,
          zoneName: _quote!.zoneName,
        ),
      const SectionTitle('Paiement'),
      PaymentMethodPicker(
        value: _payment,
        walletBalance: wallet?.balance,
        onChanged: (m) {
          if (m == PaymentMethod.wallet && _quote != null && (wallet?.balance ?? 0) < _quote!.total) {
            showError(context, Exception('Solde insuffisant (${fcfa(wallet?.balance ?? 0)}). Rechargez votre portefeuille.'));
            return;
          }
          setState(() => _payment = m);
        },
      ),
    ]);
  }

  Widget _routeLine(IconData icon, Color color, String address, String contact) => Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(address, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (contact.isNotEmpty) Text(contact, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ]),
        ),
      ]);
}
