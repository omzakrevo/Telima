import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../widgets/icon3d.dart';
import '../../widgets/payment_flow.dart';
import '../../widgets/point_form.dart';

const _servicePayments = [PaymentMethod.cash, PaymentMethod.wallet, PaymentMethod.orange_money, PaymentMethod.moov_money];

bool _validPoint(DeliveryPoint? p) => p != null && p.lat != 0 && p.lng != 0;

/// Après création : paiement Mobile Money éventuel puis suivi.
Future<void> _afterCreate(BuildContext context, WidgetRef ref, Delivery d, PaymentMethod payment) async {
  ref.invalidate(myActiveDeliveriesProvider);
  if (payment.isMobileMoney) {
    final p = await ref.read(deliveryRepositoryProvider).pendingPayment(d.id);
    if (p != null && context.mounted) await runMobileMoneyPayment(context, ref, p);
  }
  if (context.mounted) context.pushReplacement('/client/delivery/${d.id}');
}

/// En-tête illustré commun aux deux écrans.
class _ServiceHeader extends StatelessWidget {
  const _ServiceHeader({required this.image, required this.title, required this.text});
  final String image;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(color: AppColors.backdrop, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(text, style: const TextStyle(fontSize: 13, color: AppColors.primaryDark)),
            ]),
          ),
          const SizedBox(width: 8),
          Icon3D(image, size: 62, float: true),
        ]),
      );
}

/// Ligne de prix + bouton de validation.
class _PriceBar extends StatelessWidget {
  const _PriceBar({required this.price, required this.loading, required this.caption, required this.label, required this.onSubmit, this.error});
  final int? price;
  final bool loading;
  final String caption;
  final String label;
  final VoidCallback? onSubmit;
  final Object? error;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2))]),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (loading)
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Text(price == null ? '—' : fcfa(price!), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text(error != null ? 'Prix indisponible, réessayez' : caption,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: error != null ? AppColors.danger : AppColors.textMuted)),
              ]),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: onSubmit, child: Text(label)),
          ]),
        ),
      );
}

// ===========================================================================
// Course à faire : le livreur achète puis livre
// ===========================================================================
class ErrandScreen extends ConsumerStatefulWidget {
  const ErrandScreen({super.key});
  @override
  ConsumerState<ErrandScreen> createState() => _ErrandScreenState();
}

class _ErrandScreenState extends ConsumerState<ErrandScreen> {
  final _form = GlobalKey<FormState>();
  final _items = TextEditingController();
  final _budget = TextEditingController();
  String _category = 'repas';
  DeliveryPoint? _dropoff;
  PaymentMethod _payment = PaymentMethod.cash;
  int? _price;
  bool _quoting = false;
  Object? _quoteError;
  bool _submitting = false;

  static const _icons = {'repas': Ico3D.food, 'pharmacie': Ico3D.pill, 'marche': Ico3D.cart, 'boutique': Ico3D.store, 'autre': Ico3D.bags};
  static const _hints = {
    'repas': 'Ex. 2 plats de riz gras avec poulet, 1 bouteille de bissap',
    'pharmacie': 'Ex. 1 boîte de paracétamol 500 mg, 1 sirop contre la toux (ordonnance en photo via le chat)',
    'marche': 'Ex. 2 kg de tomates, 1 tas d’oignons, 1 litre d’huile',
    'boutique': 'Ex. 1 recharge Orange 1 000 F, 1 paquet de sucre, 6 œufs',
    'autre': 'Décrivez précisément ce qu’il faut acheter',
  };

  @override
  void initState() {
    super.initState();
    final u = ref.read(currentUserProvider);
    _dropoff = DeliveryPoint(address: '', lat: 0, lng: 0, contactName: u?.fullName ?? '', contactPhone: displayPhone(u?.phone));
  }

  Future<void> _quote() async {
    if (!_validPoint(_dropoff)) return;
    setState(() {
      _quoting = true;
      _quoteError = null;
    });
    try {
      final q = await ref.read(deliveryRepositoryProvider).quoteService('errand',
          fromLat: _dropoff!.lat, fromLng: _dropoff!.lng, toLat: _dropoff!.lat, toLng: _dropoff!.lng);
      if (mounted) setState(() => _price = q.total);
    } catch (e) {
      if (mounted) setState(() => _quoteError = e);
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_validPoint(_dropoff)) {
      showError(context, Exception('Indiquez où livrer (« Ma position » ou « Sur la carte »)'));
      return;
    }
    setState(() => _submitting = true);
    try {
      final d = await ref.read(deliveryRepositoryProvider).createErrand(
            dropoff: _dropoff!,
            items: _items.text.trim(),
            category: _category,
            budget: int.tryParse(_budget.text.replaceAll(RegExp(r'\D'), '')),
            payment: _payment,
          );
      if (mounted) await _afterCreate(context, ref, d, _payment);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(myWalletProvider).value;
    final addresses = ref.watch(savedAddressesProvider(null)).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Faire une course')),
      bottomNavigationBar: _PriceBar(
        price: _price,
        loading: _quoting,
        error: _quoteError,
        caption: _price == null ? 'Indiquez l’adresse pour voir le prix' : 'Frais de course · achats remboursés au livreur à la livraison',
        label: 'COMMANDER',
        onSubmit: _submitting ? null : _submit,
      ),
      body: Form(
        key: _form,
        child: Constrained(
          maxWidth: 720,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const _ServiceHeader(
              image: Ico3D.bags,
              title: 'On achète pour vous',
              text: 'Repas, médicaments, marché… Le livreur achète là où il trouve et vous livre à la maison.',
            ),
            const SectionTitle('Quoi ?'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (key, label) in errandCategories)
                ChoiceChip(
                  showCheckmark: false,
                  avatar: Image.asset(_icons[key]!, width: 22, height: 22),
                  label: Text(label),
                  selected: _category == key,
                  onSelected: (_) => setState(() => _category = key),
                ),
            ]),
            const SizedBox(height: 12),
            TextFormField(
              controller: _items,
              maxLines: 4,
              minLines: 3,
              maxLength: 1500,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Ce qu’il faut acheter', hintText: _hints[_category], alignLabelWithHint: true),
              validator: (v) => (v ?? '').trim().length < 3 ? 'Décrivez ce qu’il faut acheter' : null,
            ),
            TextFormField(
              controller: _budget,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Budget max. des achats (facultatif)',
                suffixText: 'FCFA',
                helperText: 'Le livreur vous appelle s’il doit dépasser ce montant',
              ),
            ),
            const SectionTitle('Où livrer ?'),
            DeliveryPointForm(
              point: _dropoff,
              isPickup: false,
              contactRequired: false,
              savedAddresses: addresses,
              mapTitle: 'Adresse de livraison',
              onChanged: (p) {
                final moved = _dropoff == null || p.lat != _dropoff!.lat || p.lng != _dropoff!.lng;
                setState(() => _dropoff = p);
                if (moved) _quote();
              },
            ),
            const SectionTitle('Paiement des frais'),
            PaymentMethodPicker(
              value: _payment,
              allowed: _servicePayments,
              walletBalance: wallet?.balance,
              onChanged: (m) => setState(() => _payment = m),
            ),
            const SizedBox(height: 8),
            const Text('Les achats eux-mêmes sont remboursés au livreur à la livraison, en espèces ou avec votre portefeuille, sur présentation du ticket.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}

// ===========================================================================
// Trajet : transport de personnes (moto-taxi ou voiture)
// ===========================================================================
class RideScreen extends ConsumerStatefulWidget {
  const RideScreen({super.key});
  @override
  ConsumerState<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends ConsumerState<RideScreen> {
  final _form = GlobalKey<FormState>();
  DeliveryPoint? _from;
  DeliveryPoint? _to;
  VehicleType _vehicle = VehicleType.moto;
  int _passengers = 1;
  PaymentMethod _payment = PaymentMethod.cash;
  Quote? _quote;
  double? _routeKm;
  bool _quoting = false;
  Object? _quoteError;
  bool _submitting = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _requote({bool routeChanged = false}) {
    if (routeChanged) _routeKm = null;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _doQuote);
  }

  Future<void> _doQuote() async {
    if (!_validPoint(_from) || !_validPoint(_to)) return;
    setState(() {
      _quoting = true;
      _quoteError = null;
    });
    try {
      if (_routeKm == null) {
        final r = await ref.read(routingServiceProvider).route([_from!.latLng, _to!.latLng]);
        if (!r.isEstimate) _routeKm = double.parse(r.distanceKm.toStringAsFixed(2));
      }
      final q = await ref.read(deliveryRepositoryProvider).quoteService('ride',
          fromLat: _from!.lat, fromLng: _from!.lng, toLat: _to!.lat, toLng: _to!.lng, vehicle: _vehicle, routeKm: _routeKm);
      if (mounted) setState(() => _quote = q);
    } catch (e) {
      if (mounted) setState(() => _quoteError = e);
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_validPoint(_from) || !_validPoint(_to)) {
      showError(context, Exception('Indiquez le départ et la destination'));
      return;
    }
    setState(() => _submitting = true);
    try {
      final d = await ref.read(deliveryRepositoryProvider).createRide(
            pickup: _from!,
            dropoff: _to!,
            vehicle: _vehicle,
            passengers: _vehicle == VehicleType.moto ? 1 : _passengers,
            payment: _payment,
            routeKm: _routeKm,
          );
      if (mounted) await _afterCreate(context, ref, d, _payment);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _vehicleCard(VehicleType v, String image, String title, String caption) {
    final selected = _vehicle == v;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() {
            _vehicle = v;
            if (v == VehicleType.moto) _passengers = 1;
          });
          _requote();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AppColors.primary : AppColors.line, width: selected ? 2 : 1),
          ),
          child: Column(children: [
            Icon3D(image, size: 46),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(caption, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(myWalletProvider).value;
    final addresses = ref.watch(savedAddressesProvider(null)).value ?? const [];
    final q = _quote;
    return Scaffold(
      appBar: AppBar(title: const Text('Trajet')),
      bottomNavigationBar: _PriceBar(
        price: q?.total,
        loading: _quoting,
        error: _quoteError,
        caption: q == null
            ? 'Indiquez le départ et la destination'
            : '${q.distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km · ${_vehicle == VehicleType.moto ? 'moto-taxi' : 'voiture'}',
        label: 'COMMANDER',
        onSubmit: _submitting ? null : _submit,
      ),
      body: Form(
        key: _form,
        child: Constrained(
          maxWidth: 720,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const _ServiceHeader(
              image: Ico3D.taxi,
              title: 'Où allez-vous ?',
              text: 'Un chauffeur proche vient vous chercher. Prix connu avant de partir.',
            ),
            const SizedBox(height: 14),
            Row(children: [
              _vehicleCard(VehicleType.moto, Ico3D.scooter, 'Moto-taxi', '1 passager · rapide'),
              const SizedBox(width: 10),
              _vehicleCard(VehicleType.voiture, Ico3D.car, 'Voiture', 'Jusqu’à 4 passagers'),
            ]),
            if (_vehicle == VehicleType.voiture)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(children: [
                  const Expanded(child: Text('Passagers', style: TextStyle(fontWeight: FontWeight.w600))),
                  IconButton.filledTonal(
                    onPressed: _passengers > 1 ? () => setState(() => _passengers--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(width: 36, child: Text('$_passengers', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                  IconButton.filledTonal(
                    onPressed: _passengers < 4 ? () => setState(() => _passengers++) : null,
                    icon: const Icon(Icons.add),
                  ),
                ]),
              ),
            const SectionTitle('Départ'),
            DeliveryPointForm(
              point: _from,
              isPickup: true,
              showContact: false,
              contactRequired: false,
              savedAddresses: addresses,
              mapTitle: 'Lieu de départ',
              addressLabel: 'Où le chauffeur vient vous chercher',
              onChanged: (p) {
                final moved = _from == null || p.lat != _from!.lat || p.lng != _from!.lng;
                setState(() => _from = p);
                if (moved) _requote(routeChanged: true);
              },
            ),
            const SectionTitle('Destination'),
            DeliveryPointForm(
              point: _to,
              isPickup: false,
              showContact: false,
              contactRequired: false,
              savedAddresses: addresses,
              mapTitle: 'Destination',
              addressLabel: 'Où allez-vous ?',
              onChanged: (p) {
                final moved = _to == null || p.lat != _to!.lat || p.lng != _to!.lng;
                setState(() => _to = p);
                if (moved) _requote(routeChanged: true);
              },
            ),
            const SectionTitle('Paiement'),
            PaymentMethodPicker(
              value: _payment,
              allowed: _servicePayments,
              walletBalance: wallet?.balance,
              onChanged: (m) => setState(() => _payment = m),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}
