import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../data/models/config_models.dart';
import '../../data/models/enums.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import '../client/location_picker_screen.dart';

final _pricingProvider = FutureProvider.autoDispose<List<PricingRule>>((ref) => ref.watch(configRepositoryProvider).pricingRules());
final _allCitiesProvider = FutureProvider.autoDispose<List<City>>((ref) => ref.watch(configRepositoryProvider).cities(includeInactive: true));
final _zonesProvider = FutureProvider.autoDispose.family<List<DeliveryZone>, String>((ref, cityId) => ref.watch(configRepositoryProvider).zones(cityId: cityId));

// ---------------------------------------------------------------------------
// Tarifs
// ---------------------------------------------------------------------------
class AdminPricingScreen extends ConsumerWidget {
  const AdminPricingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(_pricingProvider);
    final cities = ref.watch(_allCitiesProvider).value ?? const <City>[];
    String cityName(String? id) => id == null ? 'Toutes villes (défaut)' : (cities.where((c) => c.id == id).firstOrNull?.name ?? '?');

    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Prix = prix de départ + (distance − km inclus) × prix/km + options (taille, fragile) + frais de zone, '
          'arrondi au supérieur. Un tarif de ville remplace le tarif par défaut pour cette ville.',
          style: TextStyle(color: AppColors.textMuted)),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: () async {
            final ok = await showDialog<bool>(context: context, builder: (_) => _PricingDialog(cities: cities));
            if (ok == true) ref.invalidate(_pricingProvider);
          },
          icon: const Icon(Icons.add),
          label: const Text('Nouveau tarif'),
        ),
      ),
      const SizedBox(height: 12),
      AsyncBody<List<PricingRule>>(
        value: rules,
        onRetry: () => ref.invalidate(_pricingProvider),
        builder: (list) => Wrap(spacing: 12, runSpacing: 12, children: [
          for (final r in list)
            SizedBox(
              width: 340,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Icon(r.vehicleType.icon, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r.vehicleType.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                      if (!r.isActive) const Pill('Inactif', color: AppColors.danger),
                    ]),
                    Text(cityName(r.cityId), style: const TextStyle(color: AppColors.textMuted)),
                    const Divider(),
                    InfoRow(label: 'Prix de départ', value: fcfa(r.basePrice)),
                    InfoRow(label: 'Km inclus', value: '${r.includedKm}'),
                    InfoRow(label: 'Prix par km', value: fcfa(r.pricePerKm)),
                    InfoRow(label: 'Minimum', value: fcfa(r.minPrice)),
                    InfoRow(label: 'Fragile', value: '+${fcfa(r.fragileFee)}'),
                    InfoRow(label: 'Moyen / Grand / Très grand', value: '${r.sizeFeeMoyen} / ${r.sizeFeeGrand} / ${r.sizeFeeTresGrand}'),
                    InfoRow(label: 'Arrêt supplémentaire', value: fcfa(r.extraStopFee)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(context: context, builder: (_) => _PricingDialog(cities: cities, rule: r));
                            if (ok == true) ref.invalidate(_pricingProvider);
                          },
                          child: const Text('Modifier'),
                        ),
                      ),
                      if (r.cityId != null)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                          onPressed: () async {
                            if (!await confirmDialog(context, title: 'Supprimer ce tarif ?', danger: true)) return;
                            if (!context.mounted) return;
                            await runWithLoader(context, () => ref.read(configRepositoryProvider).deletePricing(r.id));
                            ref.invalidate(_pricingProvider);
                          },
                        ),
                    ]),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }
}

class _PricingDialog extends ConsumerStatefulWidget {
  const _PricingDialog({required this.cities, this.rule});
  final List<City> cities;
  final PricingRule? rule;
  @override
  ConsumerState<_PricingDialog> createState() => _PricingDialogState();
}

class _PricingDialogState extends ConsumerState<_PricingDialog> {
  final _form = GlobalKey<FormState>();
  late VehicleType _vehicle = widget.rule?.vehicleType ?? VehicleType.moto;
  late String? _cityId = widget.rule?.cityId;
  late bool _active = widget.rule?.isActive ?? true;
  late final _c = {
    'base_price': TextEditingController(text: '${widget.rule?.basePrice ?? 500}'),
    'included_km': TextEditingController(text: '${widget.rule?.includedKm ?? 1}'),
    'price_per_km': TextEditingController(text: '${widget.rule?.pricePerKm ?? 200}'),
    'min_price': TextEditingController(text: '${widget.rule?.minPrice ?? 500}'),
    'fragile_fee': TextEditingController(text: '${widget.rule?.fragileFee ?? 0}'),
    'size_fee_moyen': TextEditingController(text: '${widget.rule?.sizeFeeMoyen ?? 0}'),
    'size_fee_grand': TextEditingController(text: '${widget.rule?.sizeFeeGrand ?? 0}'),
    'size_fee_tres_grand': TextEditingController(text: '${widget.rule?.sizeFeeTresGrand ?? 0}'),
    'extra_stop_fee': TextEditingController(text: '${widget.rule?.extraStopFee ?? 0}'),
  };
  static const _labels = {
    'base_price': 'Prix de départ (FCFA)',
    'included_km': 'Km inclus dans le prix de départ',
    'price_per_km': 'Prix par km (FCFA)',
    'min_price': 'Prix minimum (FCFA)',
    'fragile_fee': 'Supplément fragile',
    'size_fee_moyen': 'Supplément taille moyenne',
    'size_fee_grand': 'Supplément grande taille',
    'size_fee_tres_grand': 'Supplément très grande taille',
    'extra_stop_fee': 'Frais par arrêt supplémentaire',
  };

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final data = <String, dynamic>{
      if (widget.rule != null) 'id': widget.rule!.id,
      'vehicle_type': _vehicle.name,
      'city_id': _cityId,
      'is_active': _active,
      for (final e in _c.entries)
        e.key: e.key == 'included_km' ? double.parse(e.value.text.replaceAll(',', '.')) : int.parse(e.value.text),
    };
    try {
      await ref.read(configRepositoryProvider).upsertPricing(data);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.rule == null ? 'Nouveau tarif' : 'Modifier le tarif'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<VehicleType>(
                  initialValue: _vehicle,
                  decoration: const InputDecoration(labelText: 'Véhicule'),
                  items: [for (final v in VehicleType.values) DropdownMenuItem(value: v, child: Text(v.label))],
                  onChanged: widget.rule == null ? (v) => setState(() => _vehicle = v ?? _vehicle) : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: _cityId,
                  decoration: const InputDecoration(labelText: 'Ville'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Toutes villes (défaut)')),
                    for (final c in widget.cities) DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: widget.rule == null ? (v) => setState(() => _cityId = v) : null,
                ),
                for (final e in _c.entries) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: e.value,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: InputDecoration(labelText: _labels[e.key]),
                    validator: (v) => Validators.number(v),
                  ),
                ],
                SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Actif')),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
        ],
      );
}

// ---------------------------------------------------------------------------
// Villes et zones
// ---------------------------------------------------------------------------
class AdminZonesScreen extends ConsumerWidget {
  const AdminZonesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cities = ref.watch(_allCitiesProvider);
    return ListView(padding: const EdgeInsets.all(20), children: [
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: () async {
            final ok = await showDialog<bool>(context: context, builder: (_) => const _CityDialog());
            if (ok == true) ref.invalidate(_allCitiesProvider);
          },
          icon: const Icon(Icons.add_location_alt),
          label: const Text('Nouvelle ville'),
        ),
      ),
      const SizedBox(height: 12),
      AsyncBody<List<City>>(
        value: cities,
        onRetry: () => ref.invalidate(_allCitiesProvider),
        builder: (list) => Column(children: [
          for (final c in list)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ExpansionTile(
                leading: Icon(Icons.location_city, color: c.isActive ? AppColors.primary : AppColors.textMuted),
                title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('Rayon ${c.radiusKm} km${c.isActive ? '' : ' · inactive'}'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final ok = await showDialog<bool>(context: context, builder: (_) => _CityDialog(city: c));
                    if (ok == true) ref.invalidate(_allCitiesProvider);
                  },
                ),
                children: [_ZonesList(city: c)],
              ),
            ),
        ]),
      ),
    ]);
  }
}

class _ZonesList extends ConsumerWidget {
  const _ZonesList({required this.city});
  final City city;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zones = ref.watch(_zonesProvider(city.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: AsyncBody<List<DeliveryZone>>(
        value: zones,
        builder: (list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final z in list)
            ListTile(
              dense: true,
              leading: const Icon(Icons.map_outlined),
              title: Text(z.name),
              subtitle: Text('Rayon ${z.radiusKm} km · frais ${fcfa(z.extraFee)} · ×${z.multiplier}${z.isActive ? '' : ' · inactive'}'),
              trailing: Wrap(children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final ok = await showDialog<bool>(context: context, builder: (_) => _ZoneDialog(city: city, zone: z));
                    if (ok == true) ref.invalidate(_zonesProvider(city.id));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                  onPressed: () async {
                    if (!await confirmDialog(context, title: 'Supprimer la zone ${z.name} ?', danger: true)) return;
                    if (!context.mounted) return;
                    await runWithLoader(context, () => ref.read(configRepositoryProvider).deleteZone(z.id));
                    ref.invalidate(_zonesProvider(city.id));
                  },
                ),
              ]),
            ),
          if (list.isEmpty) const Text('Aucune zone : le tarif de base s\'applique à toute la ville.'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(context: context, builder: (_) => _ZoneDialog(city: city));
                if (ok == true) ref.invalidate(_zonesProvider(city.id));
              },
              icon: const Icon(Icons.add),
              label: const Text('Ajouter une zone'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CityDialog extends ConsumerStatefulWidget {
  const _CityDialog({this.city});
  final City? city;
  @override
  ConsumerState<_CityDialog> createState() => _CityDialogState();
}

class _CityDialogState extends ConsumerState<_CityDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.city?.name);
  late final _radius = TextEditingController(text: '${widget.city?.radiusKm ?? 20}');
  late var _center = widget.city?.center;
  late bool _active = widget.city?.isActive ?? true;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_center == null) {
      showError(context, Exception('Choisissez le centre de la ville sur la carte'));
      return;
    }
    try {
      await ref.read(configRepositoryProvider).upsertCity({
        if (widget.city != null) 'id': widget.city!.id,
        'name': _name.text.trim(),
        'center_lat': _center!.latitude,
        'center_lng': _center!.longitude,
        'radius_km': double.parse(_radius.text.replaceAll(',', '.')),
        'is_active': _active,
      });
      ref.invalidate(citiesProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.city == null ? 'Nouvelle ville' : 'Modifier ${widget.city!.name}'),
        content: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nom'), validator: Validators.name),
            const SizedBox(height: 10),
            TextFormField(
              controller: _radius,
              decoration: const InputDecoration(labelText: 'Rayon couvert (km)'),
              validator: (v) => Validators.number(v, min: 1),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final r = await Navigator.of(context).push<PickedLocation>(
                    MaterialPageRoute(builder: (_) => LocationPickerScreen(initial: _center, title: 'Centre de la ville')));
                if (r != null) setState(() => _center = r.point);
              },
              icon: Icon(_center == null ? Icons.map_outlined : Icons.check_circle),
              label: Text(_center == null ? 'Centre sur la carte' : '${_center!.latitude.toStringAsFixed(4)}, ${_center!.longitude.toStringAsFixed(4)}'),
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Active')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
        ],
      );
}

class _ZoneDialog extends ConsumerStatefulWidget {
  const _ZoneDialog({required this.city, this.zone});
  final City city;
  final DeliveryZone? zone;
  @override
  ConsumerState<_ZoneDialog> createState() => _ZoneDialogState();
}

class _ZoneDialogState extends ConsumerState<_ZoneDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.zone?.name);
  late final _radius = TextEditingController(text: '${widget.zone?.radiusKm ?? 3}');
  late final _fee = TextEditingController(text: '${widget.zone?.extraFee ?? 0}');
  late final _mult = TextEditingController(text: '${widget.zone?.multiplier ?? 1}');
  late var _center = widget.zone?.center;
  late bool _active = widget.zone?.isActive ?? true;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_center == null) {
      showError(context, Exception('Choisissez le centre de la zone'));
      return;
    }
    try {
      await ref.read(configRepositoryProvider).upsertZone({
        if (widget.zone != null) 'id': widget.zone!.id,
        'city_id': widget.city.id,
        'name': _name.text.trim(),
        'center_lat': _center!.latitude,
        'center_lng': _center!.longitude,
        'radius_km': double.parse(_radius.text.replaceAll(',', '.')),
        'extra_fee': int.parse(_fee.text),
        'multiplier': double.parse(_mult.text.replaceAll(',', '.')),
        'is_active': _active,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.zone == null ? 'Nouvelle zone · ${widget.city.name}' : 'Modifier ${widget.zone!.name}'),
        content: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nom (ex. Ouaga 2000)'), validator: Validators.name),
              const SizedBox(height: 10),
              TextFormField(controller: _radius, decoration: const InputDecoration(labelText: 'Rayon (km)'), validator: (v) => Validators.number(v, min: 0.1)),
              const SizedBox(height: 10),
              TextFormField(
                controller: _fee,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Frais de zone (FCFA)'),
                validator: (v) => Validators.positiveInt(v, min: 0),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _mult,
                decoration: const InputDecoration(labelText: 'Coefficient de prix (1 = normal, 1,2 = +20 %)'),
                validator: (v) => Validators.number(v, min: 0.1),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final r = await Navigator.of(context).push<PickedLocation>(MaterialPageRoute(
                      builder: (_) => LocationPickerScreen(initial: _center ?? widget.city.center, title: 'Centre de la zone')));
                  if (r != null) setState(() => _center = r.point);
                },
                icon: Icon(_center == null ? Icons.map_outlined : Icons.check_circle),
                label: Text(_center == null ? 'Centre sur la carte' : 'Centre défini'),
              ),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Active')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
        ],
      );
}

// ---------------------------------------------------------------------------
// Paramètres de la plateforme
// ---------------------------------------------------------------------------
class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});
  @override
  ConsumerState<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  final _form = GlobalKey<FormState>();
  bool _loaded = false;
  String _commissionType = 'percent';
  final _commissionValue = TextEditingController();
  String _paymentMode = 'simulation';
  String _smsMode = 'simulation';
  String _proofMode = 'otp';
  final Set<PaymentMethod> _methods = {};
  final _num = <String, TextEditingController>{
    'dispatch_radius_km': TextEditingController(),
    'avg_speed_kmh': TextEditingController(),
    'location_min_interval_s': TextEditingController(),
    'near_pickup_km': TextEditingController(),
    'road_factor': TextEditingController(),
    'price_rounding': TextEditingController(),
    'driver_max_debt': TextEditingController(),
    'withdrawal_min': TextEditingController(),
    'otp_max_attempts': TextEditingController(),
    'errand_service_fee': TextEditingController(),
    'ride_price_multiplier': TextEditingController(),
  };
  final _omNumber = TextEditingController();
  final _omName = TextEditingController();
  final _moovNumber = TextEditingController();
  final _moovName = TextEditingController();
  static const _numLabels = {
    'dispatch_radius_km': 'Rayon de recherche des livreurs (km)',
    'avg_speed_kmh': 'Vitesse moyenne pour les estimations (km/h)',
    'location_min_interval_s': 'Intervalle minimal entre deux positions GPS (s)',
    'near_pickup_km': 'Distance pour « livreur arrive dans quelques minutes » (km)',
    'road_factor': 'Coefficient route / vol d\'oiseau',
    'price_rounding': 'Arrondi des prix (FCFA)',
    'driver_max_debt': 'Commissions dues maximales avant blocage (FCFA)',
    'withdrawal_min': 'Retrait minimum (FCFA)',
    'otp_max_attempts': 'Essais maximum du code de livraison',
    'errand_service_fee': 'Frais de service des courses à faire (FCFA)',
    'ride_price_multiplier': 'Multiplicateur du tarif des trajets (1 = tarif colis)',
  };
  final _supportPhone = TextEditingController();
  final _supportWhatsapp = TextEditingController();
  final _supportEmail = TextEditingController();
  final _supportHours = TextEditingController();

  void _load(AppSettings s) {
    if (_loaded) return;
    _loaded = true;
    _commissionType = s.commission['type']?.toString() ?? 'percent';
    _commissionValue.text = '${s.commission['value'] ?? 15}';
    _paymentMode = const ['manual', 'simulation', 'live'].contains(s.paymentMode) ? s.paymentMode : 'simulation';
    final om = s.mobileMoneyAccount('orange_money'), moov = s.mobileMoneyAccount('moov_money');
    _omNumber.text = displayPhone(om.number);
    _omName.text = om.name;
    _moovNumber.text = displayPhone(moov.number);
    _moovName.text = moov.name;
    _smsMode = s.smsSimulation ? 'simulation' : 'live';
    _proofMode = s.proofMode;
    _methods.addAll(s.paymentMethods);
    for (final e in _num.entries) {
      e.value.text = '${s.values[e.key] ?? ''}';
    }
    _supportPhone.text = s.supportPhone;
    _supportWhatsapp.text = s.supportWhatsapp;
    _supportEmail.text = s.supportEmail;
    _supportHours.text = s.supportHours;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final repo = ref.read(configRepositoryProvider);
    await runWithLoader(context, () async {
      await repo.updateSetting('commission', {'type': _commissionType, 'value': num.parse(_commissionValue.text.replaceAll(',', '.'))});
      await repo.updateSetting('payment_mode', _paymentMode);
      String num0(TextEditingController c) => c.text.trim().isEmpty ? '' : normalizePhone(c.text);
      await repo.updateSetting('mobile_money_accounts', {
        'orange_money': {'number': num0(_omNumber), 'name': _omName.text.trim()},
        'moov_money': {'number': num0(_moovNumber), 'name': _moovName.text.trim()},
      });
      await repo.updateSetting('sms_mode', _smsMode);
      await repo.updateSetting('proof_mode', _proofMode);
      await repo.updateSetting('payment_methods', [for (final m in PaymentMethod.values.where(_methods.contains)) m.name]);
      for (final e in _num.entries) {
        await repo.updateSetting(e.key, num.parse(e.value.text.replaceAll(',', '.')));
      }
      await repo.updateSetting('support', {
        'phone': normalizePhone(_supportPhone.text),
        'whatsapp': normalizePhone(_supportWhatsapp.text),
        'email': _supportEmail.text.trim(),
        'hours': _supportHours.text.trim(),
      });
    }, success: 'Paramètres enregistrés');
    ref.invalidate(settingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(settingsProvider);
    return AsyncBody<AppSettings>(
      value: async,
      onRetry: () => ref.invalidate(settingsProvider),
      builder: (s) {
        _load(s);
        return Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Constrained(
              maxWidth: 760,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SectionTitle('Commission de la plateforme'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'percent', label: Text('Pourcentage')),
                          ButtonSegment(value: 'fixed', label: Text('Montant fixe')),
                        ],
                        selected: {_commissionType},
                        onSelectionChanged: (v) => setState(() => _commissionType = v.first),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _commissionValue,
                        decoration: InputDecoration(labelText: _commissionType == 'percent' ? 'Commission (%)' : 'Commission (FCFA par course)'),
                        validator: (v) => Validators.number(v),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Builder(builder: (_) {
                        final v = num.tryParse(_commissionValue.text.replaceAll(',', '.')) ?? 0;
                        final c = _commissionType == 'percent' ? (2000 * v / 100).round() : v.round().clamp(0, 2000);
                        return Text('Exemple : course 2 000 FCFA → plateforme ${fcfa(c)} · livreur ${fcfa(2000 - c)}',
                            style: const TextStyle(color: AppColors.textMuted));
                      }),
                      const Text('S\'applique aux nouvelles commandes.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ]),
                  ),
                ),
                const SectionTitle('Paiements'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('Moyens de paiement actifs'),
                      Wrap(spacing: 8, children: [
                        for (final m in PaymentMethod.values)
                          FilterChip(
                            label: Text(m.label),
                            selected: _methods.contains(m),
                            onSelected: (v) => setState(() => v ? _methods.add(m) : _methods.remove(m)),
                          ),
                      ]),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _paymentMode,
                        decoration: const InputDecoration(labelText: 'Mobile Money'),
                        items: const [
                          DropdownMenuItem(value: 'manual', child: Text('Manuel : envoi au numéro Telima, validé par l’admin')),
                          DropdownMenuItem(value: 'simulation', child: Text('Simulation (tests, aucun argent réel)')),
                          DropdownMenuItem(value: 'live', child: Text('Réel (API Orange / Moov via fonction mobile-money-init)')),
                        ],
                        onChanged: (v) => setState(() => _paymentMode = v ?? _paymentMode),
                      ),
                      if (_paymentMode == 'manual') ...[
                        const SizedBox(height: 12),
                        const Text('Numéros qui reçoivent les paiements des clients', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: TextFormField(controller: _omNumber, keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(labelText: 'Numéro Orange Money'),
                              validator: (v) => (v ?? '').trim().isEmpty || isValidPhone(v!) ? null : 'Numéro invalide')),
                          const SizedBox(width: 10),
                          Expanded(child: TextFormField(controller: _omName, decoration: const InputDecoration(labelText: 'Nom du titulaire'))),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(child: TextFormField(controller: _moovNumber, keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(labelText: 'Numéro Moov Money'),
                              validator: (v) => (v ?? '').trim().isEmpty || isValidPhone(v!) ? null : 'Numéro invalide')),
                          const SizedBox(width: 10),
                          Expanded(child: TextFormField(controller: _moovName, decoration: const InputDecoration(labelText: 'Nom du titulaire'))),
                        ]),
                      ],
                    ]),
                  ),
                ),
                const SectionTitle('Livraison et sécurité'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      DropdownButtonFormField<String>(
                        initialValue: _proofMode,
                        decoration: const InputDecoration(labelText: 'Preuve de livraison'),
                        items: const [
                          DropdownMenuItem(value: 'otp', child: Text('Code OTP obligatoire')),
                          DropdownMenuItem(value: 'any', child: Text('Code, photo, signature ou nom')),
                        ],
                        onChanged: (v) => setState(() => _proofMode = v ?? _proofMode),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _smsMode,
                        decoration: const InputDecoration(labelText: 'SMS (récupération de compte)'),
                        items: const [
                          DropdownMenuItem(value: 'simulation', child: Text('Simulation : codes visibles dans Support')),
                          DropdownMenuItem(value: 'live', child: Text('Fournisseur SMS configuré')),
                        ],
                        onChanged: (v) => setState(() => _smsMode = v ?? _smsMode),
                      ),
                      for (final e in _num.entries) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: e.value,
                          decoration: InputDecoration(labelText: _numLabels[e.key]),
                          validator: (v) => Validators.number(v),
                        ),
                      ],
                    ]),
                  ),
                ),
                const SectionTitle('Support'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      TextFormField(controller: _supportPhone, decoration: const InputDecoration(labelText: 'Téléphone'), validator: Validators.phone),
                      const SizedBox(height: 12),
                      TextFormField(controller: _supportWhatsapp, decoration: const InputDecoration(labelText: 'WhatsApp'), validator: Validators.phone),
                      const SizedBox(height: 12),
                      TextFormField(controller: _supportEmail, decoration: const InputDecoration(labelText: 'E-mail')),
                      const SizedBox(height: 12),
                      TextFormField(controller: _supportHours, decoration: const InputDecoration(labelText: 'Horaires')),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                BigActionButton(label: 'Enregistrer les paramètres', icon: Icons.save, onPressed: _save),
                const SizedBox(height: 20),
              ]),
            ),
          ]),
        );
      },
    );
  }
}
