import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../core/utils/validators.dart';
import '../../data/models/delivery.dart';
import '../../data/models/gas.dart';
import '../../providers/auth_providers.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/point_form.dart';
import '../gas/gas_widgets.dart';

/// Espace vendeur : mes points de vente de gaz / stations.
class VendorHomeScreen extends ConsumerWidget {
  const VendorHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myPlacesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mon commerce')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/vendor/register'),
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Ajouter un point'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myPlacesProvider),
        child: AsyncBody<List<Place>>(
          value: async,
          onRetry: () => ref.invalidate(myPlacesProvider),
          builder: (list) => list.isEmpty
              ? ListView(padding: const EdgeInsets.all(24), children: const [
                  SizedBox(height: 40),
                  Icon(Icons.storefront_rounded, size: 64, color: AppColors.primary),
                  SizedBox(height: 12),
                  Text('Vendez votre gaz avec Telima', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  Text(
                    'Ajoutez votre dépôt ou votre station : les clients proches vous trouvent, commandent, et un livreur Telima peut livrer chez eux. '
                    'Après vérification par l’équipe Telima, votre point apparaît sur la carte.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, height: 1.4),
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = list[i];
                    final pending = p.status != 'approved';
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => context.push('/vendor/place/${p.id}'),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
                        child: Row(children: [
                          PlaceIcon(isStation: p.isStation),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              Text(p.subtitle.isEmpty ? (p.isStation ? 'Station-service' : 'Point de vente de gaz') : p.subtitle, style: const TextStyle(color: AppColors.textMuted)),
                            ]),
                          ),
                          if (pending)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                              child: Text(p.status == 'pending' ? 'En vérification' : 'Non validé', style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 12)),
                            )
                          else
                            const Icon(Icons.chevron_right_rounded),
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

/// Enregistrer un point de vente ou une station.
class VendorRegisterScreen extends ConsumerStatefulWidget {
  const VendorRegisterScreen({super.key});
  @override
  ConsumerState<VendorRegisterScreen> createState() => _VendorRegisterScreenState();
}

class _VendorRegisterScreenState extends ConsumerState<VendorRegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _neighborhood = TextEditingController();
  final _phone = TextEditingController();
  final _hours = TextEditingController();
  final _radius = TextEditingController(text: '5');
  bool _station = false;
  bool _delivers = true;
  DeliveryPoint? _point = DeliveryPoint(address: '', lat: 0, lng: 0);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _phone.text = displayPhone(ref.read(currentUserProvider)?.phone);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_point == null || _point!.lat == 0) {
      showError(context, Exception('Placez votre point sur la carte (« Ma position » ou « Sur la carte »)'));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(gasRepositoryProvider).registerPlace({
        'kind': _station ? 'fuel_station' : 'gas_point',
        'name': _name.text.trim(),
        'brand_label': _brand.text.trim(),
        'neighborhood': _neighborhood.text.trim(),
        'address': _point!.address,
        'lat': _point!.lat,
        'lng': _point!.lng,
        'phone': normalizePhone(_phone.text),
        'opening_hours': _hours.text.trim(),
        'delivers': !_station && _delivers,
        'delivery_radius_km': double.tryParse(_radius.text.replaceAll(',', '.')) ?? 5,
      });
      ref.invalidate(myPlacesProvider);
      if (mounted) {
        showSuccess(context, 'Envoyé ! L’équipe Telima va vérifier votre point.');
        context.pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Ajouter mon point')),
        body: Form(
          key: _form,
          child: Constrained(
            maxWidth: 720,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Vente de gaz'), icon: Icon(Icons.local_fire_department_rounded)),
                  ButtonSegment(value: true, label: Text('Station-service'), icon: Icon(Icons.local_gas_station_rounded)),
                ],
                selected: {_station},
                onSelectionChanged: (s) => setState(() => _station = s.first),
              ),
              const SizedBox(height: 14),
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nom du point'), validator: (v) => (v ?? '').trim().length < 2 ? 'Indiquez le nom' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _brand, decoration: InputDecoration(labelText: _station ? 'Enseigne (Total, Oryx…)' : 'Marque principale (facultatif)')),
              const SizedBox(height: 12),
              TextFormField(controller: _neighborhood, decoration: const InputDecoration(labelText: 'Quartier')),
              const SizedBox(height: 12),
              TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone'), validator: Validators.phone),
              const SizedBox(height: 12),
              TextFormField(controller: _hours, decoration: const InputDecoration(labelText: 'Horaires', hintText: 'Ex. 7h – 20h, tous les jours')),
              if (!_station) ...[
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Je propose la livraison'), value: _delivers, onChanged: (v) => setState(() => _delivers = v)),
                if (_delivers)
                  TextFormField(controller: _radius, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rayon de livraison (km)')),
              ],
              const SectionTitle('Où se trouve votre point ?'),
              DeliveryPointForm(
                point: _point,
                isPickup: true,
                showContact: false,
                contactRequired: false,
                mapTitle: 'Position de votre point',
                addressLabel: 'Adresse ou repère',
                onChanged: (p) => setState(() => _point = p),
              ),
              const SizedBox(height: 20),
              BigActionButton(label: 'Envoyer pour vérification', icon: Icons.send_rounded, loading: _saving, onPressed: _save),
            ]),
          ),
        ),
      );
}

/// Tableau de bord d'un point : résumé, commandes, produits (gaz) ou carburants (station).
class VendorPlaceScreen extends ConsumerWidget {
  const VendorPlaceScreen({super.key, required this.placeId});
  final String placeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(myPlacesProvider).value?.where((p) => p.id == placeId).firstOrNull;
    if (place == null) return Scaffold(appBar: AppBar(title: const Text('Mon point')), body: const LoadingView());
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(place.name),
          bottom: TabBar(tabs: [
            const Tab(text: 'Résumé'),
            const Tab(text: 'Commandes'),
            Tab(text: place.isStation ? 'Carburants' : 'Produits'),
          ]),
        ),
        body: TabBarView(children: [
          _Summary(place: place),
          _Orders(place: place),
          place.isStation ? _Fuels(place: place) : _Products(place: place),
        ]),
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(vendorDashboardProvider(place.id));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(vendorDashboardProvider(place.id)),
      child: AsyncBody<Map<String, dynamic>>(
        value: async,
        onRetry: () => ref.invalidate(vendorDashboardProvider(place.id)),
        builder: (d) {
          Widget tile(String label, String value, IconData icon, Color c) => Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, color: c),
                  const Spacer(),
                  Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ]),
              );
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (place.status != 'approved')
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.butter, borderRadius: BorderRadius.circular(14)),
                child: const Text('Votre point est en cours de vérification : il n’apparaît pas encore aux clients.'),
              ),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.4,
              children: [
                tile('Commandes aujourd’hui', '${d['orders_today'] ?? 0}', Icons.receipt_long_rounded, AppColors.info),
                tile('Ventes aujourd’hui', fcfa(d['sales_today']), Icons.payments_rounded, AppColors.primary),
                tile('Commandes en attente', '${d['pending'] ?? 0}', Icons.hourglass_top_rounded, AppColors.accent),
                tile('Livraisons en cours', '${d['in_delivery'] ?? 0}', Icons.delivery_dining_rounded, AppColors.info),
                tile('Stock disponible', '${d['stock'] ?? 0}', Icons.inventory_2_rounded, AppColors.primary),
                tile('Produits en rupture', '${d['out_of_stock'] ?? 0}', Icons.warning_rounded, AppColors.danger),
              ],
            ),
          ]);
        },
      ),
    );
  }
}

class _Orders extends ConsumerWidget {
  const _Orders({required this.place});
  final Place place;

  Future<void> _act(BuildContext context, WidgetRef ref, GasOrder o, String action, {String? reason, String? ok}) async {
    await runWithLoader(context, () => ref.read(gasRepositoryProvider).orderAction(o.id, action, reason: reason), success: ok);
    ref.invalidate(placeOrdersProvider(place.id));
    ref.invalidate(vendorDashboardProvider(place.id));
    ref.invalidate(myPlacesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(placeOrdersProvider(place.id));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(placeOrdersProvider(place.id)),
      child: AsyncBody<List<GasOrder>>(
        value: async,
        onRetry: () => ref.invalidate(placeOrdersProvider(place.id)),
        builder: (list) => list.isEmpty
            ? ListView(children: const [SizedBox(height: 80), Center(child: Text('Aucune commande pour le moment', style: TextStyle(color: AppColors.textMuted)))])
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final o = list[i];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('${o.code} · ${o.customerName}', style: const TextStyle(fontWeight: FontWeight.w800))),
                        Text(o.statusLabel, style: TextStyle(color: o.statusColor, fontWeight: FontWeight.w700, fontSize: 12)),
                      ]),
                      const SizedBox(height: 4),
                      Text(o.items.map((e) => e.text).join(', ')),
                      Text('${o.isDelivery ? 'Livraison : ${o.dropoffAddress ?? ''}' : 'Retrait sur place'} · ${fcfa(o.total)}', style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        OutlinedButton.icon(onPressed: () => callPhone(o.customerPhone), icon: const Icon(Icons.call_rounded, size: 18), label: const Text('Client')),
                        if (o.status == 'sent') ...[
                          FilledButton(onPressed: () => _act(context, ref, o, 'accept', ok: 'Commande acceptée'), child: const Text('Accepter')),
                          OutlinedButton(
                            onPressed: () async {
                              final c = TextEditingController();
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Refuser la commande'),
                                  content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Raison (facultatif)')),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Retour')),
                                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Refuser')),
                                  ],
                                ),
                              );
                              if (ok == true && context.mounted) _act(context, ref, o, 'reject', reason: c.text, ok: 'Commande refusée');
                            },
                            child: const Text('Refuser', style: TextStyle(color: AppColors.danger)),
                          ),
                        ],
                        if (o.status == 'accepted') FilledButton(onPressed: () => _act(context, ref, o, 'preparing'), child: const Text('En préparation')),
                        if (const {'accepted', 'preparing'}.contains(o.status))
                          FilledButton(
                            onPressed: () => _act(context, ref, o, 'ready', ok: o.isDelivery ? 'Un livreur est recherché' : 'Client prévenu'),
                            child: Text(o.isDelivery ? 'Prête : appeler un livreur' : 'Prête à retirer'),
                          ),
                        if (!o.isDelivery && const {'ready'}.contains(o.status))
                          FilledButton(onPressed: () => _act(context, ref, o, 'handed', ok: 'Vente enregistrée'), child: const Text('Remise au client')),
                        if (o.deliveryId != null && o.isOpen)
                          OutlinedButton(onPressed: () => context.push('/client/delivery/${o.deliveryId}'), child: const Text('Suivre la livraison')),
                      ]),
                    ]),
                  );
                },
              ),
      ),
    );
  }
}

class _Products extends ConsumerWidget {
  const _Products({required this.place});
  final Place place;

  Future<void> _edit(BuildContext context, WidgetRef ref, [PlaceProduct? p]) async {
    final brands = ref.read(gasBrandsProvider).value ?? const [];
    String? brandId = p?.brandId ?? (brands.isNotEmpty ? brands.first.id : null);
    final size = TextEditingController(text: p == null ? '12.5' : '${p.sizeKg}');
    final price = TextEditingController(text: p == null ? '' : '${p.price}');
    final stock = TextEditingController(text: p == null ? '0' : '${p.stock}');
    var track = p?.trackStock ?? false;
    var avail = p == null || p.availability == Availability.unknown ? Availability.available : p.availability;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(p == null ? 'Ajouter une bouteille' : 'Modifier', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: brandId,
                decoration: const InputDecoration(labelText: 'Marque'),
                items: [for (final b in brands) DropdownMenuItem(value: b.id, child: Text(b.name))],
                onChanged: (v) => brandId = v,
              ),
              const SizedBox(height: 10),
              TextField(controller: size, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Poids (kg)', hintText: '6, 12.5…')),
              const SizedBox(height: 10),
              TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Prix (FCFA)')),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Suivre mon stock'), subtitle: const Text('Le stock baisse à chaque commande'), value: track, onChanged: (v) => setS(() => track = v)),
              if (track)
                TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantité en stock'))
              else
                Wrap(spacing: 8, children: [
                  for (final a in const [Availability.available, Availability.low, Availability.out])
                    ChoiceChip(label: Text(a.label), selected: avail == a, onSelected: (_) => setS(() => avail = a)),
                ]),
              const SizedBox(height: 14),
              BigActionButton(label: 'Enregistrer', onPressed: () => Navigator.pop(context, true)),
            ]),
          ),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final kg = double.tryParse(size.text.replaceAll(',', '.'));
    final pr = int.tryParse(price.text.replaceAll(RegExp(r'\D'), ''));
    if (kg == null || kg <= 0 || pr == null) {
      showError(context, Exception('Poids et prix obligatoires'));
      return;
    }
    await runWithLoader(
      context,
      () => ref.read(gasRepositoryProvider).saveProduct(
          id: p?.id, placeId: place.id, brandId: brandId, sizeKg: kg, price: pr, trackStock: track, stock: int.tryParse(stock.text) ?? 0, availability: avail),
      success: 'Enregistré',
    );
    ref.invalidate(myPlacesProvider);
    ref.invalidate(vendorDashboardProvider(place.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(onPressed: () => _edit(context, ref), child: const Icon(Icons.add_rounded)),
      body: place.products.isEmpty
          ? const Center(child: Text('Ajoutez vos bouteilles avec le bouton +', style: TextStyle(color: AppColors.textMuted)))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: place.products.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = place.products[i];
                return Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${p.brand} · ${p.sizeLabel}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('${fcfa(p.price)}${p.trackStock ? ' · stock ${p.stock}' : ''}', style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        AvailabilityChip(p.availability, at: p.confirmedAt, showAge: true),
                      ]),
                    ),
                    IconButton(onPressed: () => _edit(context, ref, p), icon: const Icon(Icons.edit_rounded)),
                    IconButton(
                      onPressed: () async {
                        await runWithLoader(context, () => ref.read(gasRepositoryProvider).deleteProduct(p.id));
                        ref.invalidate(myPlacesProvider);
                      },
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                    ),
                  ]),
                );
              },
            ),
    );
  }
}

class _Fuels extends ConsumerWidget {
  const _Fuels({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final fuel in const ['essence', 'gasoil'])
        Builder(builder: (_) {
          final f = place.fuels.where((x) => x.fuel == fuel).firstOrNull;
          final cur = f?.availability ?? Availability.unknown;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fuel == 'essence' ? 'Essence' : 'Gasoil', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              AvailabilityChip(cur, at: f?.confirmedAt, showAge: true),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                for (final a in const [Availability.available, Availability.low, Availability.out])
                  ChoiceChip(
                    label: Text(a.label),
                    selected: cur == a,
                    onSelected: (_) async {
                      await runWithLoader(context, () => ref.read(gasRepositoryProvider).setFuel(place.id, fuel, a, price: f?.price), success: 'Mis à jour');
                      ref.invalidate(myPlacesProvider);
                    },
                  ),
              ]),
            ]),
          );
        }),
      const Text('Touchez une disponibilité pour confirmer l’état actuel : les clients voient l’heure de la dernière confirmation.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
    ]);
  }
}
