import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../core/utils/validators.dart';
import '../../data/models/delivery.dart';
import '../../data/models/driver.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/admin_repository.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/delivery_widgets.dart';
import '../../widgets/live_tracking.dart';
import '../../widgets/package_form.dart';
import '../../widgets/point_form.dart';
import '../client/new_delivery_screen.dart' show vehicleRank;

// ---------------------------------------------------------------------------
// Liste des commandes avec filtres
// ---------------------------------------------------------------------------
class AdminOrdersScreen extends ConsumerStatefulWidget {
  const AdminOrdersScreen({super.key});
  @override
  ConsumerState<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends ConsumerState<AdminOrdersScreen> {
  final _filter = DeliveryFilter(statusGroup: 'all');
  String _period = 'today';
  final _search = TextEditingController();
  final _code = TextEditingController();
  late Future<List<Delivery>> _future;
  List<DriverProfile> _drivers = [];

  @override
  void initState() {
    super.initState();
    _applyPeriod('today');
    _load();
    ref.read(adminRepositoryProvider).drivers(status: DriverStatus.approved).then((d) {
      if (mounted) setState(() => _drivers = d);
    }).ignore();
  }

  void _applyPeriod(String p) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _period = p;
    switch (p) {
      case 'today':
        _filter.from = today;
        _filter.to = today.add(const Duration(days: 1));
      case '7d':
        _filter.from = today.subtract(const Duration(days: 6));
        _filter.to = today.add(const Duration(days: 1));
      case '30d':
        _filter.from = today.subtract(const Duration(days: 29));
        _filter.to = today.add(const Duration(days: 1));
      case 'all':
        _filter.from = null;
        _filter.to = null;
    }
  }

  void _load() {
    _filter.customerQuery = _search.text;
    _filter.code = _code.text;
    setState(() => _future = ref.read(adminRepositoryProvider).deliveries(_filter));
  }

  Future<void> _customRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Période personnalisée',
    );
    if (r == null) return;
    _period = 'custom';
    _filter.from = r.start;
    _filter.to = r.end.add(const Duration(days: 1));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Material(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final p in const [('today', 'Aujourd\'hui'), ('7d', '7 jours'), ('30d', '30 jours'), ('all', 'Tout')])
                ChoiceChip(
                  label: Text(p.$2),
                  selected: _period == p.$1,
                  onSelected: (_) {
                    _applyPeriod(p.$1);
                    _load();
                  },
                ),
              ChoiceChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(_period == 'custom' ? '${formatDate(_filter.from)} → ${formatDate(_filter.to?.subtract(const Duration(days: 1)))}' : 'Période…'),
                selected: _period == 'custom',
                onSelected: (_) => _customRange(),
              ),
              const SizedBox(width: 12),
              for (final s in const [('all', 'Tous'), ('pending', 'En attente'), ('active', 'En cours'), ('completed', 'Terminées'), ('cancelled', 'Annulées')])
                FilterChip(
                  label: Text(s.$2),
                  selected: _filter.statusGroup == s.$1,
                  onSelected: (_) {
                    _filter.statusGroup = s.$1;
                    _load();
                  },
                ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _code,
                  decoration: const InputDecoration(labelText: 'N° commande', prefixIcon: Icon(Icons.tag), isDense: true),
                  onSubmitted: (_) => _load(),
                ),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(labelText: 'Client (nom ou téléphone)', prefixIcon: Icon(Icons.search), isDense: true),
                  onSubmitted: (_) => _load(),
                ),
              ),
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String?>(
                  initialValue: _filter.driverId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Livreur', isDense: true),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Tous les livreurs')),
                    for (final d in _drivers) DropdownMenuItem<String?>(value: d.userId, child: Text(d.user?.fullName ?? d.userId)),
                  ],
                  onChanged: (v) {
                    _filter.driverId = v;
                    _load();
                  },
                ),
              ),
              FilledButton.icon(onPressed: _load, icon: const Icon(Icons.search), label: const Text('Filtrer')),
              OutlinedButton.icon(onPressed: () => context.go('/admin/orders/new'), icon: const Icon(Icons.add_call), label: const Text('Commande téléphone')),
            ]),
          ]),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: FutureBuilder<List<Delivery>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _load);
            if (!snap.hasData) return const LoadingView();
            final list = snap.data!;
            if (list.isEmpty) return const EmptyState(icon: Icons.inbox_outlined, message: 'Aucune commande pour ces filtres');
            final total = list.where((d) => d.status == DeliveryStatus.completed).fold<int>(0, (a, d) => a + d.totalPrice);
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(children: [
                  Text('${list.length} commande(s)', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('Terminées : ${fcfa(total)}', style: const TextStyle(color: AppColors.textMuted)),
                ]),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _load(),
                  child: LayoutBuilder(builder: (context, c) {
                    final cols = c.maxWidth > 1200 ? 3 : (c.maxWidth > 760 ? 2 : 1);
                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        mainAxisExtent: 150,
                      ),
                      itemCount: list.length,
                      itemBuilder: (_, i) => DeliveryListTile(
                        delivery: list[i],
                        showDriver: true,
                        onTap: () => context.push('/admin/orders/${list[i].id}').then((_) => _load()),
                      ),
                    );
                  }),
                ),
              ),
            ]);
          },
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Détail d'une commande : attribution manuelle, annulation, clôture
// ---------------------------------------------------------------------------
class AdminOrderDetailScreen extends ConsumerWidget {
  const AdminOrderDetailScreen({super.key, required this.deliveryId});
  final String deliveryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(deliveryStreamProvider(deliveryId));
    return AsyncBody<Delivery?>(
      value: async,
      onRetry: () => ref.invalidate(deliveryStreamProvider(deliveryId)),
      builder: (d) {
        if (d == null) return const EmptyState(icon: Icons.search_off, message: 'Commande introuvable');
        final driverPos = d.status.hasDriver && d.status.isActive ? ref.watch(driverPositionProvider(d.id)) : null;
        final otp = ref.watch(deliveryOtpProvider(d.id)).value;
        final wide = MediaQuery.sizeOf(context).width > 1100;

        final actions = Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(d.code, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
                StatusChip(d.status),
              ]),
              const SizedBox(height: 4),
              Text('Créée le ${formatDateTime(d.createdAt)} · via ${d.createdVia == 'admin' ? 'opérateur' : (d.createdVia == 'business' ? 'compte pro' : 'application')}',
                  style: const TextStyle(color: AppColors.textMuted)),
              if (d.driverName != null) ...[
                const SizedBox(height: 8),
                Text('Livreur : ${d.driverName}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
              if (otp != null && d.status.isActive) Text('Code de livraison : $otp', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (d.status.isActive && d.status.step <= 5)
                  FilledButton.icon(
                    onPressed: () => _assign(context, ref, d),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: Text(d.driverId == null ? 'Attribuer à un livreur' : 'Réattribuer'),
                  ),
                OutlinedButton.icon(onPressed: () => callPhone(d.customerPhone), icon: const Icon(Icons.call), label: const Text('Appeler le client')),
                if (d.status == DeliveryStatus.in_transit || d.status == DeliveryStatus.at_dropoff)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final name = await promptDialog(context, title: 'Clôturer la livraison', label: 'Nom du réceptionnaire (confirmé par téléphone)');
                      if (name == null || !context.mounted) return;
                      await runWithLoader(context, () => ref.read(adminRepositoryProvider).forceComplete(d.id, name), success: 'Livraison clôturée');
                    },
                    icon: const Icon(Icons.verified),
                    label: const Text('Clôturer'),
                  ),
                if (d.status.isActive)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                    onPressed: () async {
                      final reason = await promptDialog(context, title: 'Annuler ${d.code}', label: 'Motif');
                      if (reason == null || !context.mounted) return;
                      await runWithLoader(context, () => ref.read(adminRepositoryProvider).cancel(d.id, reason), success: 'Commande annulée');
                    },
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Annuler'),
                  ),
              ]),
            ]),
          ),
        );

        final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          actions,
          const SizedBox(height: 12),
          LiveTrackingMap(delivery: d, driverPosition: driverPos, height: 320),
          const SectionTitle('Étapes'),
          StatusTimeline(deliveryId: d.id, current: d.status),
        ]);
        final right = DeliveryDetailsCard(delivery: d, showCommission: true, showCustomer: true);

        return ListView(padding: const EdgeInsets.all(20), children: [
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: left),
              const SizedBox(width: 20),
              Expanded(flex: 2, child: right),
            ])
          else ...[
            left,
            const SectionTitle('Détails'),
            right,
          ],
        ]);
      },
    );
  }

  Future<void> _assign(BuildContext context, WidgetRef ref, Delivery d) async {
    final driverId = await showDialog<String>(context: context, builder: (_) => _AssignDialog(delivery: d));
    if (driverId == null || !context.mounted) return;
    await runWithLoader(context, () => ref.read(adminRepositoryProvider).assign(d.id, driverId), success: 'Livraison attribuée');
    ref.invalidate(deliveryStreamProvider(d.id));
    ref.invalidate(deliveryHistoryProvider(d.id));
  }
}

class _AssignDialog extends ConsumerWidget {
  const _AssignDialog({required this.delivery});
  final Delivery delivery;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AlertDialog(
        title: Text('Attribuer ${delivery.code}'),
        content: SizedBox(
          width: 520,
          height: 480,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: ref.read(adminRepositoryProvider).assignableDrivers(delivery.id),
            builder: (context, snap) {
              if (snap.hasError) return ErrorView(error: snap.error!);
              if (!snap.hasData) return const LoadingView();
              final list = snap.data!;
              if (list.isEmpty) return const EmptyState(icon: Icons.person_off, message: 'Aucun livreur approuvé avec véhicule');
              return ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = list[i];
                  final vehicle = VehicleType.parse(r['vehicle_type'] as String?);
                  final busy = r['busy'] == true;
                  final tooSmall = vehicleRank(vehicle) < vehicleRank(delivery.vehicleType);
                  return ListTile(
                    enabled: !tooSmall,
                    leading: Badge(
                      backgroundColor: r['is_online'] == true ? AppColors.primary : Colors.grey,
                      smallSize: 12,
                      child: Icon(vehicle.icon),
                    ),
                    title: Text(r['full_name'] as String? ?? ''),
                    subtitle: Text([
                      displayPhone(r['phone'] as String?),
                      if (r['distance_km'] != null) '${km(r['distance_km'] as num)} du départ',
                      r['is_online'] == true ? 'en ligne' : 'hors ligne',
                      if (busy) 'déjà en course',
                      if (tooSmall) 'véhicule trop petit',
                    ].join(' · ')),
                    trailing: RatingDisplay(rating: (r['rating_avg'] as num?)?.toDouble() ?? 0),
                    onTap: () async {
                      if (busy &&
                          !await confirmDialog(context, title: 'Livreur déjà en course', message: 'Attribuer quand même cette commande ?')) {
                        return;
                      }
                      if (context.mounted) Navigator.pop(context, r['driver_id'] as String);
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
      );
}

// ---------------------------------------------------------------------------
// Commande saisie par un opérateur (client au téléphone)
// ---------------------------------------------------------------------------
class AdminCreateOrderScreen extends ConsumerStatefulWidget {
  const AdminCreateOrderScreen({super.key});
  @override
  ConsumerState<AdminCreateOrderScreen> createState() => _AdminCreateOrderScreenState();
}

class _AdminCreateOrderScreenState extends ConsumerState<AdminCreateOrderScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _price = TextEditingController();
  DeliveryPoint? _pickup;
  DeliveryPoint? _dropoff;
  final _package = PackageInfo();
  VehicleType? _vehicle;
  PaymentMethod _payment = PaymentMethod.cash;
  String? _driverId;
  Quote? _quote;
  bool _saving = false;
  List<DriverProfile> _drivers = [];
  int _formVersion = 0;

  @override
  void initState() {
    super.initState();
    ref.read(adminRepositoryProvider).drivers(status: DriverStatus.approved).then((d) {
      if (mounted) setState(() => _drivers = d);
    }).ignore();
  }

  bool _valid(DeliveryPoint? p) => p != null && p.lat != 0;

  Future<void> _quoteNow() async {
    if (!_valid(_pickup) || !_valid(_dropoff)) return;
    try {
      final route = await ref.read(routingServiceProvider).route([_pickup!.latLng, _dropoff!.latLng]);
      final q = await ref.read(configRepositoryProvider).quote(
            pickupLat: _pickup!.lat,
            pickupLng: _pickup!.lng,
            dropoffLat: _dropoff!.lat,
            dropoffLng: _dropoff!.lng,
            vehicle: _vehicle,
            size: _package.size,
            fragile: _package.fragile,
            category: _package.category,
            routeKm: route.isEstimate ? null : route.distanceKm,
          );
      setState(() {
        _quote = q;
        _vehicle = q.vehicleType;
        _price.text = '${q.total}';
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_valid(_pickup) || !_valid(_dropoff)) {
      showError(context, Exception('Positions de récupération et de destination obligatoires'));
      return;
    }
    setState(() => _saving = true);
    try {
      final override = int.tryParse(_price.text.replaceAll(' ', ''));
      final d = await ref.read(adminRepositoryProvider).createPhoneOrder({
        'customer_phone': normalizePhone(_phone.text),
        'customer_name': _name.text.trim(),
        'pickup': _pickup!.toJson(),
        'dropoff': _dropoff!.toJson(),
        'package': _package.toJson(),
        'vehicle_type': _vehicle?.name,
        'payment_method': _payment.name,
        'price_override': (override != null && override != _quote?.total) ? override : null,
        'driver_id': _driverId,
      });
      if (mounted) {
        showSuccess(context, 'Commande ${d.code} créée');
        context.go('/admin/orders/${d.id}');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 1100;
    final pickupForm = DeliveryPointForm(
      key: ValueKey('p$_formVersion'),
      point: _pickup,
      isPickup: true,
      onChanged: (p) {
        setState(() => _pickup = p);
        _quoteNow();
      },
    );
    final dropoffForm = DeliveryPointForm(
      key: ValueKey('d$_formVersion'),
      point: _dropoff,
      isPickup: false,
      onChanged: (p) {
        setState(() => _dropoff = p);
        _quoteNow();
      },
    );
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Saisir la commande d\'un client qui appelle', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(
            width: 300,
            child: TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
              decoration: const InputDecoration(labelText: 'Téléphone du client', prefixIcon: Icon(Icons.phone)),
              validator: Validators.phone,
              onChanged: (v) {
                if (_pickup == null || _pickup!.contactPhone.isEmpty) {
                  _pickup = (_pickup ?? DeliveryPoint(address: '', lat: 0, lng: 0))..contactPhone = v;
                }
              },
            ),
          ),
          SizedBox(
            width: 300,
            child: TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nom du client', prefixIcon: Icon(Icons.person)),
              validator: Validators.name,
              onChanged: (v) {
                if (_pickup == null || _pickup!.contactName.isEmpty) {
                  _pickup = (_pickup ?? DeliveryPoint(address: '', lat: 0, lng: 0))..contactName = v;
                }
              },
            ),
          ),
        ]),
        const SizedBox(height: 20),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const SectionTitle('Récupération'), pickupForm])),
            const SizedBox(width: 24),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const SectionTitle('Destination'), dropoffForm])),
          ])
        else ...[
          const SectionTitle('Récupération'),
          pickupForm,
          const SectionTitle('Destination'),
          dropoffForm,
        ],
        const SectionTitle('Colis'),
        PackageForm(package: _package, compact: true, onChanged: () {
          setState(() {});
          _quoteNow();
        }),
        const SectionTitle('Véhicule, prix et paiement'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in VehicleType.values)
            ChoiceChip(
              avatar: Icon(v.icon, size: 18),
              label: Text(v.label),
              selected: _vehicle == v,
              onSelected: (_) {
                setState(() => _vehicle = v);
                _quoteNow();
              },
            ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 220,
            child: TextFormField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Prix (FCFA)',
                helperText: _quote == null ? 'Calculé automatiquement' : 'Tarif : ${fcfa(_quote!.total)} · ${km(_quote!.distanceKm)}',
              ),
              validator: (v) => Validators.positiveInt(v, min: 0),
            ),
          ),
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<PaymentMethod>(
              initialValue: _payment,
              decoration: const InputDecoration(labelText: 'Paiement'),
              items: [
                for (final m in PaymentMethod.values.where((m) => m != PaymentMethod.wallet))
                  DropdownMenuItem(value: m, child: Text(m.label)),
              ],
              onChanged: (v) => setState(() => _payment = v ?? _payment),
            ),
          ),
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<String?>(
              initialValue: _driverId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Livreur (facultatif)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Recherche automatique')),
                for (final d in _drivers)
                  DropdownMenuItem<String?>(
                    value: d.userId,
                    child: Text('${d.user?.fullName ?? ''}${d.isOnline ? ' · en ligne' : ''}'),
                  ),
              ],
              onChanged: (v) => setState(() => _driverId = v),
            ),
          ),
        ]),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: BigActionButton(label: 'Créer la commande', icon: Icons.check, loading: _saving, onPressed: _submit)),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () => setState(() {
              _phone.clear();
              _name.clear();
              _price.clear();
              _pickup = null;
              _dropoff = null;
              _quote = null;
              _formVersion++;
            }),
            child: const Text('Réinitialiser'),
          ),
        ]),
      ]),
    );
  }
}
