import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/delivery.dart';
import '../../data/models/gas.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/point_form.dart';
import '../gas/gas_widgets.dart';

final _adminPlacesProvider = FutureProvider<List<Place>>((ref) => ref.watch(gasRepositoryProvider).adminPlaces());
final _adminReportsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) => ref.watch(gasRepositoryProvider).adminReports());

/// Administration du module Gaz & carburant : validation des points, ajout, marques, signalements.
class AdminGasScreen extends ConsumerWidget {
  const AdminGasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const DefaultTabController(
      length: 4,
      child: Column(children: [
        TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
          Tab(text: 'À valider'),
          Tab(text: 'Tous les points'),
          Tab(text: 'Marques'),
          Tab(text: 'Signalements'),
        ]),
        Expanded(child: TabBarView(children: [_PlacesTab(onlyPending: true), _PlacesTab(onlyPending: false), _BrandsTab(), _ReportsTab()])),
      ]),
    );
  }
}

class _PlacesTab extends ConsumerWidget {
  const _PlacesTab({required this.onlyPending});
  final bool onlyPending;

  Future<void> _status(BuildContext context, WidgetRef ref, Place p, String status) async {
    await runWithLoader(context, () => ref.read(gasRepositoryProvider).adminSetStatus(p.id, status), success: 'Mis à jour');
    ref.invalidate(_adminPlacesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_adminPlacesProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: onlyPending
          ? null
          : FloatingActionButton.extended(onPressed: () => _add(context, ref), icon: const Icon(Icons.add_location_alt_rounded), label: const Text('Ajouter un point')),
      body: AsyncBody<List<Place>>(
        value: async,
        onRetry: () => ref.invalidate(_adminPlacesProvider),
        builder: (all) {
          final list = onlyPending ? all.where((p) => p.status == 'pending').toList() : all;
          if (list.isEmpty) return Center(child: Text(onlyPending ? 'Aucun point à valider' : 'Aucun point enregistré', style: const TextStyle(color: AppColors.textMuted)));
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final p = list[i];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    PlaceIcon(isStation: p.isStation, size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text([p.subtitle, p.phone != null ? displayPhone(p.phone) : ''].where((e) => e.isNotEmpty).join(' · '), style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                      ]),
                    ),
                    Text(switch (p.status) { 'approved' => 'Validé', 'pending' => 'À valider', 'rejected' => 'Refusé', _ => 'Suspendu' },
                        style: TextStyle(fontWeight: FontWeight.w700, color: p.status == 'approved' ? AppColors.primary : AppColors.accent)),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (p.status != 'approved') FilledButton(onPressed: () => _status(context, ref, p, 'approved'), child: const Text('Valider')),
                    if (p.status == 'pending') OutlinedButton(onPressed: () => _status(context, ref, p, 'rejected'), child: const Text('Refuser')),
                    if (p.status == 'approved') OutlinedButton(onPressed: () => _status(context, ref, p, 'suspended'), child: const Text('Suspendre')),
                  ]),
                ]),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController(), brand = TextEditingController(), quartier = TextEditingController(), phone = TextEditingController();
    var station = false;
    DeliveryPoint? point = DeliveryPoint(address: '', lat: 0, lng: 0);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Ajouter un point', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: false, label: Text('Gaz')), ButtonSegment(value: true, label: Text('Station'))],
                selected: {station},
                onSelectionChanged: (s) => setS(() => station = s.first),
              ),
              const SizedBox(height: 10),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom')),
              const SizedBox(height: 8),
              TextField(controller: brand, decoration: const InputDecoration(labelText: 'Enseigne / marque')),
              const SizedBox(height: 8),
              TextField(controller: quartier, decoration: const InputDecoration(labelText: 'Quartier')),
              const SizedBox(height: 8),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Téléphone')),
              const SizedBox(height: 8),
              DeliveryPointForm(point: point, isPickup: true, showContact: false, contactRequired: false, mapTitle: 'Position', onChanged: (p) => point = p),
              const SizedBox(height: 12),
              BigActionButton(label: 'Ajouter (validé)', onPressed: () => Navigator.pop(context, true)),
            ]),
          ),
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    if (name.text.trim().length < 2 || point == null || point!.lat == 0) {
      showError(context, Exception('Nom et position obligatoires'));
      return;
    }
    await runWithLoader(
      context,
      () => ref.read(gasRepositoryProvider).adminSavePlace({
        'kind': station ? 'fuel_station' : 'gas_point',
        'name': name.text.trim(),
        'brand_label': brand.text.trim().isEmpty ? null : brand.text.trim(),
        'neighborhood': quartier.text.trim().isEmpty ? null : quartier.text.trim(),
        'phone': phone.text.trim().isEmpty ? null : normalizePhone(phone.text),
        'address': point!.address,
        'lat': point!.lat,
        'lng': point!.lng,
        'status': 'approved',
        'source': 'admin',
      }),
      success: 'Point ajouté',
    );
    ref.invalidate(_adminPlacesProvider);
  }
}

class _BrandsTab extends ConsumerWidget {
  const _BrandsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(gasBrandsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final c = TextEditingController();
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Nouvelle marque de gaz'),
              content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Nom')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ajouter')),
              ],
            ),
          );
          if (ok == true && c.text.trim().length >= 2 && context.mounted) {
            await runWithLoader(context, () => ref.read(gasRepositoryProvider).adminSaveBrand(c.text.trim()), success: 'Marque ajoutée');
            ref.invalidate(gasBrandsProvider);
          }
        },
        child: const Icon(Icons.add_rounded),
      ),
      body: AsyncBody<List<GasBrand>>(
        value: async,
        onRetry: () => ref.invalidate(gasBrandsProvider),
        builder: (list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [for (final b in list) ListTile(leading: const Icon(Icons.local_fire_department_rounded, color: AppColors.accent), title: Text(b.name))],
        ),
      ),
    );
  }
}

class _ReportsTab extends ConsumerWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_adminReportsProvider);
    return AsyncBody<List<Map<String, dynamic>>>(
      value: async,
      onRetry: () => ref.invalidate(_adminReportsProvider),
      builder: (list) => list.isEmpty
          ? const Center(child: Text('Aucun signalement', style: TextStyle(color: AppColors.textMuted)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = list[i];
                final target = switch ('${r['target']}') { 'gas' => 'Gaz', 'essence' => 'Essence', 'gasoil' => 'Gasoil', 'closed' => 'Point fermé', _ => 'Prix' };
                final value = r['value'] == null ? '' : ' : ${Availability.parse(r['value']).label}';
                return ListTile(
                  title: Text('${(r['places'] as Map?)?['name'] ?? ''} · $target$value'),
                  subtitle: Text('${(r['users'] as Map?)?['full_name'] ?? ''} · ${relativeTime(DateTime.tryParse('${r['created_at']}'))}${r['note'] == null ? '' : ' · ${r['note']}'}'),
                );
              },
            ),
    );
  }
}
