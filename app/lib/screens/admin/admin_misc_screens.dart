import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../data/models/config_models.dart';
import '../../data/models/delivery.dart';
import '../../data/models/driver.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/admin_repository.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/map_widgets.dart';

// ---------------------------------------------------------------------------
// Carte en direct : livreurs en ligne + commandes en cours / en attente
// ---------------------------------------------------------------------------
final _liveProvider = FutureProvider.autoDispose<(List<DriverProfile>, List<Delivery>)>((ref) async {
  final repo = ref.watch(adminRepositoryProvider);
  final timer = Timer(const Duration(seconds: 15), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final drivers = await repo.drivers(status: DriverStatus.approved, onlineOnly: true);
  final pending = await repo.deliveries(DeliveryFilter(statusGroup: 'pending'), limit: 100);
  final active = await repo.deliveries(DeliveryFilter(statusGroup: 'active'), limit: 200);
  return (drivers, [...pending, ...active]);
});

class AdminLiveMapScreen extends ConsumerWidget {
  const AdminLiveMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_liveProvider);
    final cities = ref.watch(citiesProvider).value ?? const <City>[];
    return AsyncBody<(List<DriverProfile>, List<Delivery>)>(
      value: async,
      onRetry: () => ref.invalidate(_liveProvider),
      builder: (data) {
        final (drivers, deliveries) = data;
        final markers = <Marker>[
          for (final d in drivers.where((d) => d.lat != null))
            Marker(
              point: LatLng(d.lat!, d.lng!),
              width: 140,
              height: 60,
              child: GestureDetector(
                onTap: () => context.push('/admin/drivers/${d.userId}'),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.info, borderRadius: BorderRadius.circular(6)),
                    child: Text(d.user?.firstName ?? '', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                  Icon(d.activeVehicle?.type.icon ?? Icons.delivery_dining, color: AppColors.info, size: 30),
                ]),
              ),
            ),
          for (final d in deliveries.where((d) => d.status.isPending))
            Marker(
              point: d.pickup,
              width: 120,
              height: 60,
              child: GestureDetector(
                onTap: () => context.push('/admin/orders/${d.id}'),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
                    child: Text(d.code.split('-').last, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                  const Icon(Icons.inventory_2, color: AppColors.accent, size: 28),
                ]),
              ),
            ),
        ];
        final center = drivers.where((d) => d.lat != null).map((d) => LatLng(d.lat!, d.lng!)).firstOrNull ??
            (cities.isNotEmpty ? cities.first.center : const LatLng(12.3714, -1.5197));
        return Stack(children: [
          FlutterMap(
            options: MapOptions(initialCenter: center, initialZoom: 12),
            children: [osmTileLayer(), MarkerLayer(markers: markers), osmAttribution()],
          ),
          Positioned(
            left: 12,
            top: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Icon(Icons.delivery_dining, color: AppColors.info),
                    const SizedBox(width: 6),
                    Text('${drivers.length} livreur(s) en ligne'),
                  ]),
                  Row(children: [
                    const Icon(Icons.inventory_2, color: AppColors.accent),
                    const SizedBox(width: 6),
                    Text('${deliveries.where((d) => d.status.isPending).length} en attente de livreur'),
                  ]),
                  Row(children: [
                    const Icon(Icons.local_shipping, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text('${deliveries.where((d) => !d.status.isPending).length} en cours'),
                  ]),
                  if (cities.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Actualisation automatique (15 s)', style: TextStyle(fontSize: 11, color: AppColors.textMuted.withValues(alpha: 0.9))),
                    ),
                ]),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Support + codes de récupération (mode simulation SMS)
// ---------------------------------------------------------------------------
final _supportProvider = FutureProvider.autoDispose.family<List<SupportRequest>, bool>(
    (ref, openOnly) => ref.watch(adminRepositoryProvider).supportRequests(openOnly: openOnly));
final _resetsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(adminRepositoryProvider).passwordResets());

class AdminSupportScreen extends ConsumerStatefulWidget {
  const AdminSupportScreen({super.key});
  @override
  ConsumerState<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

class _AdminSupportScreenState extends ConsumerState<AdminSupportScreen> {
  bool _openOnly = true;

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(currentUserProvider)?.role == UserRole.admin;
    return DefaultTabController(
      length: isAdmin ? 2 : 1,
      child: Column(children: [
        Material(
          color: Colors.white,
          child: TabBar(tabs: [
            const Tab(text: 'Demandes'),
            if (isAdmin) const Tab(text: 'Récupération de compte'),
          ]),
        ),
        Expanded(
          child: TabBarView(children: [
            Column(children: [
              SwitchListTile(
                value: _openOnly,
                onChanged: (v) => setState(() => _openOnly = v),
                title: const Text('Seulement les demandes ouvertes'),
              ),
              Expanded(
                child: AsyncBody<List<SupportRequest>>(
                  value: ref.watch(_supportProvider(_openOnly)),
                  onRetry: () => ref.invalidate(_supportProvider(_openOnly)),
                  builder: (list) => list.isEmpty
                      ? const EmptyState(icon: Icons.support_agent, message: 'Aucune demande')
                      : ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                          for (final r in list)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(child: Text(r.subject, style: const TextStyle(fontWeight: FontWeight.w800))),
                                    Pill(r.statusLabel, color: r.status == 'closed' ? AppColors.textMuted : AppColors.accent),
                                  ]),
                                  Text('${r.userName ?? 'Visiteur'} · ${displayPhone(r.userPhone ?? r.phone)} · ${formatDateTime(r.createdAt)}',
                                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                  const SizedBox(height: 6),
                                  Text(r.message),
                                  if ((r.adminReply ?? '').isNotEmpty) Text('Réponse : ${r.adminReply}', style: const TextStyle(color: AppColors.primary)),
                                  const SizedBox(height: 8),
                                  Wrap(spacing: 8, children: [
                                    if ((r.userPhone ?? r.phone) != null)
                                      OutlinedButton.icon(
                                        onPressed: () => callPhone(r.userPhone ?? r.phone!),
                                        icon: const Icon(Icons.call),
                                        label: const Text('Appeler'),
                                      ),
                                    OutlinedButton.icon(
                                      onPressed: () async {
                                        final reply = await promptDialog(context, title: 'Répondre', label: 'Réponse', maxLines: 3);
                                        if (reply == null || !context.mounted) return;
                                        await runWithLoader(context, () => ref.read(adminRepositoryProvider).updateSupport(r.id, status: 'in_progress', reply: reply),
                                            success: 'Réponse enregistrée');
                                        ref.invalidate(_supportProvider);
                                      },
                                      icon: const Icon(Icons.reply),
                                      label: const Text('Répondre'),
                                    ),
                                    if (r.status != 'closed')
                                      TextButton(
                                        onPressed: () async {
                                          await runWithLoader(context,
                                              () => ref.read(adminRepositoryProvider).updateSupport(r.id, status: 'closed', reply: r.adminReply));
                                          ref.invalidate(_supportProvider);
                                        },
                                        child: const Text('Clore'),
                                      ),
                                  ]),
                                ]),
                              ),
                            ),
                        ]),
                ),
              ),
            ]),
            if (isAdmin)
              AsyncBody<List<Map<String, dynamic>>>(
                value: ref.watch(_resetsProvider),
                onRetry: () => ref.invalidate(_resetsProvider),
                builder: (list) => ListView(padding: const EdgeInsets.all(16), children: [
                  const Text('Mode simulation SMS : communiquez ce code à l\'utilisateur après avoir vérifié son identité par téléphone.',
                      style: TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 12),
                  if (list.isEmpty) const EmptyState(icon: Icons.lock_reset, message: 'Aucune demande en cours'),
                  for (final r in list)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.lock_reset),
                        title: Text('${(r['users'] as Map?)?['full_name'] ?? ''} · ${displayPhone(r['phone'] as String?)}'),
                        subtitle: Text('Expire ${formatTime(DateTime.tryParse(r['expires_at'].toString()))}'),
                        trailing: SelectableText(r['code_plain']?.toString() ?? '(envoyé par SMS)',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3)),
                      ),
                    ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Journal des actions administratives
// ---------------------------------------------------------------------------
final _logsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) => ref.watch(adminRepositoryProvider).adminLogs());

class AdminLogsScreen extends ConsumerWidget {
  const AdminLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncBody<List<Map<String, dynamic>>>(
        value: ref.watch(_logsProvider),
        onRetry: () => ref.invalidate(_logsProvider),
        builder: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.history_edu, message: 'Aucune action enregistrée')
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final l = list[i];
                  final details = l['details'];
                  return ExpansionTile(
                    leading: const Icon(Icons.history_edu_outlined),
                    title: Text('${l['action']} · ${l['entity']}'),
                    subtitle: Text('${(l['users'] as Map?)?['full_name'] ?? 'Système'} · ${formatDateTime(DateTime.tryParse(l['created_at'].toString()))}'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(const JsonEncoder.withIndent('  ').convert(details),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      ),
                    ],
                  );
                },
              ),
      );
}
