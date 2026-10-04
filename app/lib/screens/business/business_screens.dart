import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../config/theme.dart';
import '../../core/services/file_export.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../data/models/config_models.dart';
import '../../data/models/delivery.dart';
import '../../data/models/enums.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/delivery_widgets.dart';
import '../../widgets/live_tracking.dart';
import '../../widgets/map_widgets.dart';
import '../client/location_picker_screen.dart';

final _businessProvider = FutureProvider.autoDispose.family<BusinessAccount?, String>((ref, id) async {
  final list = await ref.watch(myBusinessesProvider.future);
  return list.where((b) => b.id == id).firstOrNull;
});

final _businessDeliveriesProvider = FutureProvider.autoDispose
    .family<List<Delivery>, String>((ref, id) => ref.watch(deliveryRepositoryProvider).myDeliveries(businessId: id, limit: 200));

final _businessMonthSummaryProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) {
  final now = DateTime.now();
  return ref.watch(profileRepositoryProvider).businessSummary(id, DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
});

/// Liste des comptes professionnels + création.
class BusinessListScreen extends ConsumerWidget {
  const BusinessListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myBusinessesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Espace professionnel')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add_business),
        label: const Text('Créer un compte pro'),
      ),
      body: Constrained(
        maxWidth: 720,
        child: AsyncBody<List<BusinessAccount>>(
          value: async,
          onRetry: () => ref.invalidate(myBusinessesProvider),
          builder: (list) => list.isEmpty
              ? const EmptyState(
                  icon: Icons.storefront_outlined,
                  message: 'Boutique, restaurant, pharmacie, vendeur Facebook/WhatsApp ?\n'
                      'Créez un compte professionnel pour envoyer plusieurs colis, enregistrer vos clients '
                      'et suivre vos dépenses.',
                )
              : ListView(padding: const EdgeInsets.all(16), children: [
                  for (final b in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: const CircleAvatar(child: Icon(Icons.storefront)),
                          title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text('${b.type.label}${b.address != null ? ' · ${b.address}' : ''}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/business/${b.id}'),
                        ),
                      ),
                    ),
                ]),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<bool>(context: context, builder: (_) => const _BusinessFormDialog());
    if (created == true) ref.invalidate(myBusinessesProvider);
  }
}

class _BusinessFormDialog extends ConsumerStatefulWidget {
  const _BusinessFormDialog();
  @override
  ConsumerState<_BusinessFormDialog> createState() => _BusinessFormDialogState();
}

class _BusinessFormDialogState extends ConsumerState<_BusinessFormDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  BusinessType _type = BusinessType.boutique;
  PickedLocation? _loc;
  bool _saving = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).createBusiness({
        'name': _name.text.trim(),
        'type': _type.name,
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        'lat': _loc?.point.latitude,
        'lng': _loc?.point.longitude,
        'city_id': ref.read(currentUserProvider)?.cityId,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Compte professionnel'),
        content: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nom de l\'activité'), validator: Validators.name),
              const SizedBox(height: 10),
              DropdownButtonFormField<BusinessType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [for (final t in BusinessType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Téléphone (facultatif)'),
                validator: Validators.optionalPhone,
              ),
              const SizedBox(height: 10),
              TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Adresse')),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final r = await Navigator.of(context).push<PickedLocation>(
                      MaterialPageRoute(builder: (_) => const LocationPickerScreen(title: 'Position de l\'activité')));
                  if (r != null) {
                    setState(() => _loc = r);
                    if (_address.text.isEmpty && r.address != null) _address.text = r.address!;
                  }
                },
                icon: Icon(_loc == null ? Icons.map_outlined : Icons.check_circle, color: _loc == null ? null : AppColors.primary),
                label: Text(_loc == null ? 'Position sur la carte' : 'Position enregistrée'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: _saving ? null : _save, child: const Text('Créer')),
        ],
      );
}

/// Tableau de bord d'un compte professionnel.
class BusinessDashboardScreen extends ConsumerWidget {
  const BusinessDashboardScreen({super.key, required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(_businessProvider(businessId)).value;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(business?.name ?? 'Espace pro'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Livraisons'),
            Tab(text: 'Suivi en direct'),
            Tab(text: 'Mes clients'),
            Tab(text: 'Équipe'),
          ]),
        ),
        floatingActionButton: _NewMenu(businessId: businessId),
        body: TabBarView(children: [
          _BusinessDeliveriesTab(businessId: businessId),
          _BusinessLiveTab(businessId: businessId),
          _SavedClientsTab(businessId: businessId),
          _MembersTab(businessId: businessId, business: business),
        ]),
      ),
    );
  }
}

class _NewMenu extends StatelessWidget {
  const _NewMenu({required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: const Icon(Icons.local_shipping),
                title: const Text('Une livraison'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/client/new?business=$businessId');
                },
              ),
              ListTile(
                leading: const Icon(Icons.alt_route),
                title: const Text('Plusieurs colis (multi-destinations)'),
                subtitle: const Text('Un point de récupération, plusieurs clients'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/business/$businessId/batch');
                },
              ),
            ]),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Envoyer'),
      );
}

class _BusinessDeliveriesTab extends ConsumerStatefulWidget {
  const _BusinessDeliveriesTab({required this.businessId});
  final String businessId;
  @override
  ConsumerState<_BusinessDeliveriesTab> createState() => _BusinessDeliveriesTabState();
}

class _BusinessDeliveriesTabState extends ConsumerState<_BusinessDeliveriesTab> {
  Future<void> _export() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: DateTime(DateTime.now().year, DateTime.now().month), end: DateTime.now()),
      helpText: 'Période du relevé',
    );
    if (range == null || !mounted) return;
    await runWithLoader(context, () async {
      final list = await ref
          .read(deliveryRepositoryProvider)
          .businessDeliveriesBetween(widget.businessId, range.start, range.end.add(const Duration(days: 1)));
      final rows = <List<String>>[
        ['Code', 'Date', 'Statut', 'Récupération', 'Destination', 'Destinataire', 'Téléphone', 'Distance (km)', 'Montant (FCFA)', 'Paiement'],
        for (final d in list)
          [
            d.code,
            formatDateTime(d.createdAt),
            d.status.label,
            d.pickupAddress,
            d.dropoffAddress,
            d.dropoffContactName,
            d.dropoffContactPhone,
            d.distanceKm.toStringAsFixed(1).replaceAll('.', ','),
            '${d.totalPrice}',
            d.paymentMethod.label,
          ],
      ];
      final total = list.where((d) => d.status == DeliveryStatus.completed).fold<int>(0, (a, d) => a + d.totalPrice);
      rows.add(['', '', '', '', '', '', '', 'TOTAL (terminées)', '$total', '']);
      final csv = rows.map((r) => r.map((c) => '"${c.replaceAll('"', '""')}"').join(';')).join('\n');
      await exportTextFile('releve_${formatDate(range.start).replaceAll('/', '-')}_${formatDate(range.end).replaceAll('/', '-')}.csv', csv);
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(_businessMonthSummaryProvider(widget.businessId)).value;
    final async = ref.watch(_businessDeliveriesProvider(widget.businessId));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_businessDeliveriesProvider(widget.businessId));
        ref.invalidate(_businessMonthSummaryProvider(widget.businessId));
      },
      child: Constrained(
        maxWidth: 820,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
          if (summary != null)
            GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.6,
              children: [
                StatCard(label: 'Envois ce mois', value: '${summary['count']}', icon: Icons.inventory_2_outlined),
                StatCard(label: 'Livrés', value: '${summary['completed']}', icon: Icons.check_circle_outline),
                StatCard(label: 'En cours', value: '${summary['active']}', icon: Icons.local_shipping_outlined, color: AppColors.info),
                StatCard(label: 'Dépenses du mois', value: fcfa(summary['spent'] as num?), icon: Icons.payments_outlined, color: AppColors.accent),
              ],
            ),
          SectionTitle('Historique',
              trailing: TextButton.icon(onPressed: _export, icon: const Icon(Icons.download), label: const Text('Relevé CSV'))),
          AsyncBody<List<Delivery>>(
            value: async,
            onRetry: () => ref.invalidate(_businessDeliveriesProvider(widget.businessId)),
            builder: (list) => list.isEmpty
                ? const EmptyState(icon: Icons.inbox_outlined, message: 'Aucune livraison pour ce compte')
                : Column(children: [
                    for (final d in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: DeliveryListTile(delivery: d, onTap: () => context.push('/client/delivery/${d.id}')),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

/// Suivi simultané de plusieurs livreurs sur une carte.
class _BusinessLiveTab extends ConsumerWidget {
  const _BusinessLiveTab({required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_businessDeliveriesProvider(businessId));
    return AsyncBody<List<Delivery>>(
      value: async,
      builder: (all) {
        final active = all.where((d) => d.status.hasDriver && d.status.isActive).toList();
        if (active.isEmpty) {
          return const EmptyState(icon: Icons.map_outlined, message: 'Aucun livreur en course pour le moment');
        }
        return Column(children: [
          Expanded(
            flex: 3,
            child: _MultiDriverMap(deliveries: active),
          ),
          Expanded(
            flex: 2,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              for (final d in active)
                ListTile(
                  leading: Icon(d.vehicleType.icon, color: d.status.color),
                  title: Text('${d.code} → ${d.dropoffContactName}'),
                  subtitle: Text(d.dropoffAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: StatusChip(d.status),
                  onTap: () => context.push('/client/delivery/${d.id}'),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}

class _MultiDriverMap extends ConsumerWidget {
  const _MultiDriverMap({required this.deliveries});
  final List<Delivery> deliveries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final markers = <Marker>[];
    final points = <LatLng>[];
    for (final d in deliveries) {
      final pos = ref.watch(driverPositionProvider(d.id));
      points.add(d.dropoff);
      markers.add(dropoffMarker(d.dropoff, label: d.dropoffContactName));
      if (pos != null) {
        points.add(pos);
        markers.add(driverMarker(pos));
      }
    }
    return FlutterMap(
      options: fitOptions(points),
      children: [osmTileLayer(), MarkerLayer(markers: markers), osmAttribution()],
    );
  }
}

/// Carnet de clients / adresses du compte professionnel.
class _SavedClientsTab extends ConsumerWidget {
  const _SavedClientsTab({required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(savedAddressesProvider(businessId));
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AsyncBody<List<SavedAddress>>(
        value: async,
        onRetry: () => ref.invalidate(savedAddressesProvider(businessId)),
        builder: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.contacts_outlined, message: 'Enregistrez vos clients réguliers pour commander plus vite.')
            : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
                for (final a in list)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${a.contactName ?? ''} · ${displayPhone(a.contactPhone)}\n${a.address}'),
                      isThreeLine: true,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (!await confirmDialog(context, title: 'Supprimer ${a.label} ?', danger: true)) return;
                          await ref.read(profileRepositoryProvider).deleteAddress(a.id);
                          ref.invalidate(savedAddressesProvider(businessId));
                        },
                      ),
                    ),
                  ),
              ]),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'addclient',
        tooltip: 'Ajouter un client',
        onPressed: () async {
          final ok = await showDialog<bool>(context: context, builder: (_) => SavedAddressDialog(businessId: businessId));
          if (ok == true) ref.invalidate(savedAddressesProvider(businessId));
        },
        child: const Icon(Icons.person_add),
      ),
    );
  }
}

class SavedAddressDialog extends ConsumerStatefulWidget {
  const SavedAddressDialog({super.key, this.businessId});
  final String? businessId;
  @override
  ConsumerState<SavedAddressDialog> createState() => _SavedAddressDialogState();
}

class _SavedAddressDialogState extends ConsumerState<SavedAddressDialog> {
  final _form = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _instructions = TextEditingController();
  PickedLocation? _loc;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_loc == null) {
      showError(context, Exception('Indiquez la position sur la carte'));
      return;
    }
    try {
      await ref.read(profileRepositoryProvider).saveAddress({
        'label': _label.text.trim(),
        'contact_name': _name.text.trim(),
        'contact_phone': normalizePhone(_phone.text),
        'address': _address.text.trim(),
        'lat': _loc!.point.latitude,
        'lng': _loc!.point.longitude,
        'instructions': _instructions.text.trim(),
      }, businessId: widget.businessId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nouveau client / adresse'),
        content: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: _label, decoration: const InputDecoration(labelText: 'Libellé (ex. Mme Kaboré)'), validator: Validators.name),
              const SizedBox(height: 8),
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nom du contact')),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                decoration: const InputDecoration(labelText: 'Téléphone'),
                validator: Validators.phone,
              ),
              const SizedBox(height: 8),
              TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Adresse / description'), validator: Validators.required),
              const SizedBox(height: 8),
              TextFormField(controller: _instructions, decoration: const InputDecoration(labelText: 'Indications')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final r = await Navigator.of(context).push<PickedLocation>(MaterialPageRoute(builder: (_) => const LocationPickerScreen()));
                  if (r != null) {
                    setState(() => _loc = r);
                    if (_address.text.isEmpty && r.address != null) _address.text = r.address!;
                  }
                },
                icon: Icon(_loc == null ? Icons.map_outlined : Icons.check_circle),
                label: Text(_loc == null ? 'Position sur la carte' : 'Position enregistrée'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: _save, child: const Text('Enregistrer')),
        ],
      );
}

class _MembersTab extends ConsumerStatefulWidget {
  const _MembersTab({required this.businessId, required this.business});
  final String businessId;
  final BusinessAccount? business;
  @override
  ConsumerState<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<_MembersTab> {
  late Future<List<BusinessMember>> _future = ref.read(profileRepositoryProvider).members(widget.businessId);

  void _reload() => setState(() => _future = ref.read(profileRepositoryProvider).members(widget.businessId));

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final isOwner = widget.business?.ownerId == me?.id;
    return FutureBuilder<List<BusinessMember>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
        if (!snap.hasData) return const LoadingView();
        return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
          const Text('Les membres peuvent envoyer des colis et suivre les livraisons de ce compte.'),
          const SizedBox(height: 12),
          for (final m in snap.data!)
            Card(
              child: ListTile(
                leading: UserAvatar(name: m.name),
                title: Text(m.name),
                subtitle: Text('${displayPhone(m.phone)} · ${m.role.label}'),
                trailing: isOwner && m.role != MemberRole.owner
                    ? IconButton(
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: () async {
                          await runWithLoader(context, () => ref.read(profileRepositoryProvider).removeMember(widget.businessId, m.userId));
                          _reload();
                        },
                      )
                    : null,
              ),
            ),
          if (isOwner) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final phone = await promptDialog(context, title: 'Ajouter un membre', label: 'Téléphone du compte Telima', keyboard: TextInputType.phone);
                if (phone == null || !context.mounted) return;
                await runWithLoader(context, () => ref.read(profileRepositoryProvider).addMember(widget.businessId, phone, MemberRole.member),
                    success: 'Membre ajouté');
                _reload();
              },
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Ajouter un membre'),
            ),
          ],
        ]);
      },
    );
  }
}
