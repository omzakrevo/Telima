import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../data/models/travel.dart';
import '../../providers/travel_providers.dart';
import '../../widgets/common.dart';
import '../travel/travel_company_screens.dart' show CompanyTile;
import '../travel/travel_widgets.dart' show copyCompanyLink;

/// Administration des voyages : toutes les compagnies, saisie d'une compagnie non inscrite,
/// gestion à sa place (départs, confirmations), suspension, attribution à un compte.
class AdminTransportScreen extends ConsumerWidget {
  const AdminTransportScreen({super.key});

  Future<void> _setStatus(BuildContext context, WidgetRef ref, TransportCompany c, String status) async {
    if (status == 'suspended' || status == 'rejected') {
      final ok = await confirmDialog(
        context,
        title: status == 'rejected' ? 'Refuser « ${c.name} » ?' : 'Suspendre « ${c.name} » ?',
        message: 'Son lien et ses départs ne seront plus visibles ; plus aucune réservation possible.',
        confirmLabel: status == 'rejected' ? 'Refuser' : 'Suspendre',
        danger: true,
      );
      if (!ok || !context.mounted) return;
    }
    await runWithLoader(context, () => ref.read(travelRepositoryProvider).adminSetStatus(c.id, status), success: 'Mis à jour');
    ref.invalidate(adminCompaniesProvider);
  }

  Future<void> _setOwner(BuildContext context, WidgetRef ref, TransportCompany c) async {
    final phone = await promptDialog(
      context,
      title: c.managedByTelima ? 'Confier « ${c.name} » à un compte' : 'Changer le responsable de « ${c.name} »',
      label: 'Téléphone du compte Telima (vide = gérée par Telima)',
      required: false,
    );
    if (phone == null || !context.mounted) return;
    await runWithLoader(context, () => ref.read(travelRepositoryProvider).adminSetOwner(c.id, phone.trim().isEmpty ? null : phone.trim()),
        success: phone.trim().isEmpty ? 'La compagnie est gérée par Telima' : 'Compagnie confiée');
    ref.invalidate(adminCompaniesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminCompaniesProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(adminCompaniesProvider),
      child: AsyncBody<List<TransportCompany>>(
        value: async,
        onRetry: () => ref.invalidate(adminCompaniesProvider),
        builder: (list) => ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            const Expanded(
              child: Text('Les compagnies inscrites gèrent leurs départs. Saisissez ici celles qui ne sont pas encore sur Telima : '
                  'vous publiez leurs départs et confirmez les réservations à leur place.',
                  style: TextStyle(color: AppColors.textMuted, height: 1.35)),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => context.push('/transport/new?admin=1'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Saisir une compagnie'),
            ),
          ]),
          const SizedBox(height: 16),
          if (list.isEmpty) const EmptyState(icon: Icons.directions_bus_rounded, message: 'Aucune compagnie pour le moment.'),
          for (final c in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(children: [
                CompanyTile(
                  company: c,
                  onTap: () => context.push('/transport/${c.id}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => switch (v) {
                      'manage' => context.push('/transport/${c.id}'),
                      'link' => copyCompanyLink(context, c),
                      'owner' => _setOwner(context, ref, c),
                      'suspend' => _setStatus(context, ref, c, 'suspended'),
                      'reject' => _setStatus(context, ref, c, 'rejected'),
                      _ => _setStatus(context, ref, c, 'approved'),
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'manage', child: Text('Gérer (départs, réservations)')),
                      const PopupMenuItem(value: 'link', child: Text('Copier le lien')),
                      PopupMenuItem(value: 'owner', child: Text(c.managedByTelima ? 'Confier à un compte' : 'Changer de responsable')),
                      if (c.pendingApproval) ...[
                        const PopupMenuItem(value: 'restore', child: Text('Valider')),
                        const PopupMenuItem(value: 'reject', child: Text('Refuser')),
                      ] else if (c.suspended)
                        const PopupMenuItem(value: 'restore', child: Text('Rétablir'))
                      else
                        const PopupMenuItem(value: 'suspend', child: Text('Suspendre')),
                    ],
                  ),
                ),
                if (c.managedByTelima)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(left: 8, top: 4),
                      child: Text('Gérée par l’équipe Telima', style: TextStyle(fontSize: 12, color: AppColors.info, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}
