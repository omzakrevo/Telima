import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../data/models/enums.dart';
import '../../data/models/user.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import 'admin_drivers_screens.dart' show CreateUserDialog;

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  UserRole? _role = UserRole.client;
  final _query = TextEditingController();
  late Future<List<AppUser>> _future = _fetch();

  Future<List<AppUser>> _fetch() => ref.read(adminRepositoryProvider).users(role: _role, query: _query.text);
  void _reload() => setState(() => _future = _fetch());

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProvider);
    final isAdmin = me?.role == UserRole.admin;
    return Column(children: [
      Material(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final r in [UserRole.client, UserRole.driver, UserRole.operator, UserRole.admin, null])
              ChoiceChip(
                label: Text(r?.label ?? 'Tous'),
                selected: _role == r,
                onSelected: (_) {
                  _role = r;
                  _reload();
                },
              ),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _query,
                decoration: const InputDecoration(labelText: 'Nom ou téléphone', prefixIcon: Icon(Icons.search), isDense: true),
                onSubmitted: (_) => _reload(),
              ),
            ),
            if (isAdmin)
              FilledButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(context: context, builder: (_) => CreateUserDialog(role: _role ?? UserRole.client));
                  if (ok == true) _reload();
                },
                icon: const Icon(Icons.person_add),
                label: const Text('Créer un compte'),
              ),
          ]),
        ),
      ),
      Expanded(
        child: FutureBuilder<List<AppUser>>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
            if (!snap.hasData) return const LoadingView();
            final list = snap.data!;
            if (list.isEmpty) return const EmptyState(icon: Icons.people_outline, message: 'Aucun utilisateur');
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final u = list[i];
                return Card(
                  child: ListTile(
                    leading: UserAvatar(name: u.fullName, url: u.avatarUrl),
                    title: Text(u.fullName, style: TextStyle(fontWeight: FontWeight.w700, color: u.isActive ? null : AppColors.textMuted)),
                    subtitle: Text('${displayPhone(u.phone)} · inscrit le ${formatDate(u.createdAt)}'),
                    trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Pill(u.role.label, color: AppColors.info),
                      if (!u.isActive) const Pill('Désactivé', color: AppColors.danger),
                      PopupMenuButton<String>(
                        onSelected: (a) => _action(a, u),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'call', child: Text('Appeler')),
                          const PopupMenuItem(value: 'orders', child: Text('Voir ses commandes')),
                          if (u.role == UserRole.driver) const PopupMenuItem(value: 'driver', child: Text('Fiche livreur')),
                          if (isAdmin && u.id != me?.id) ...[
                            PopupMenuItem(value: 'toggle', child: Text(u.isActive ? 'Désactiver le compte' : 'Réactiver le compte')),
                            const PopupMenuItem(value: 'role', child: Text('Changer le rôle')),
                            if (u.role != UserRole.admin)
                              const PopupMenuItem(value: 'delete', child: Text('Supprimer définitivement', style: TextStyle(color: AppColors.danger))),
                          ],
                        ],
                      ),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }

  Future<void> _action(String a, AppUser u) async {
    final repo = ref.read(adminRepositoryProvider);
    switch (a) {
      case 'call':
        await callPhone(u.phone);
      case 'orders':
        context.go('/admin/orders');
        showSuccess(context, 'Filtrez par téléphone : ${displayPhone(u.phone)}');
      case 'driver':
        context.push('/admin/drivers/${u.id}');
      case 'toggle':
        if (!await confirmDialog(context, title: u.isActive ? 'Désactiver ${u.fullName} ?' : 'Réactiver ${u.fullName} ?', danger: u.isActive)) return;
        if (!mounted) return;
        await runWithLoader(context, () => repo.setUserActive(u.id, !u.isActive), success: 'Compte mis à jour');
        _reload();
      case 'delete':
        await _deleteUser(u);
      case 'role':
        final role = await showDialog<UserRole>(
          context: context,
          builder: (ctx) => SimpleDialog(title: Text('Rôle de ${u.fullName}'), children: [
            for (final r in UserRole.values)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, r),
                child: Row(children: [Icon(r == u.role ? Icons.radio_button_checked : Icons.radio_button_off), const SizedBox(width: 8), Text(r.label)]),
              ),
          ]),
        );
        if (role == null || role == u.role || !mounted) return;
        await runWithLoader(context, () => repo.setUserRole(u.id, role), success: 'Rôle modifié');
        _reload();
    }
  }

  /// Suppression définitive : vérifie d'abord ce qui bloque, affiche ce qui sera supprimé, demande de taper SUPPRIMER.
  Future<void> _deleteUser(AppUser u) async {
    final repo = ref.read(adminRepositoryProvider);
    final chk = await runWithLoader(context, () => repo.deleteUserCheck(u.id));
    if (chk == null || !mounted) return;
    final balance = (chk['wallet_balance'] as num?)?.toInt() ?? 0;
    final blockers = <String>[
      if (((chk['active_deliveries'] as num?) ?? 0) > 0) '${chk['active_deliveries']} livraison(s) en cours',
      if (((chk['active_orders'] as num?) ?? 0) > 0) '${chk['active_orders']} commande(s) de restaurant ou de gaz en cours',
      if (((chk['pending_withdrawals'] as num?) ?? 0) > 0) 'un retrait en attente de paiement',
    ];
    final force = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final confirm = TextEditingController();
        var acceptBalance = false;
        return StatefulBuilder(builder: (ctx, setS) {
          final ready = blockers.isEmpty && confirm.text.trim().toUpperCase() == 'SUPPRIMER' && (balance == 0 || acceptBalance);
          return AlertDialog(
            title: Text('Supprimer ${u.fullName} ?'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Cette suppression est définitive et ne peut pas être annulée.', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger)),
                const SizedBox(height: 10),
                const Text('Seront supprimés : le compte, le profil, la fiche livreur, le portefeuille, les adresses, les notifications et, '
                    'le cas échéant, ses restaurants, ses points de vente et ses commandes.'),
                const SizedBox(height: 8),
                Text('L’historique de ses ${chk['deliveries_total'] ?? 0} livraison(s) est conservé, sans lien avec le compte.'),
                if (((chk['restaurants'] as num?) ?? 0) > 0 || ((chk['places'] as num?) ?? 0) > 0) ...[
                  const SizedBox(height: 8),
                  Text('Également supprimés : ${chk['restaurants'] ?? 0} restaurant(s) et ${chk['places'] ?? 0} point(s) de vente.',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
                if (blockers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Suppression impossible pour le moment : ${blockers.join(', ')}.', style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                ],
                if (balance != 0 && blockers.isEmpty)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: acceptBalance,
                    onChanged: (v) => setS(() => acceptBalance = v ?? false),
                    title: Text('Le portefeuille contient ${fcfa(balance)}. Supprimer malgré ce solde.'),
                  ),
                if (blockers.isEmpty) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirm,
                    onChanged: (_) => setS(() {}),
                    decoration: const InputDecoration(labelText: 'Tapez SUPPRIMER pour confirmer', isDense: true),
                  ),
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: ready ? () => Navigator.pop(ctx, balance != 0) : null,
                child: const Text('Supprimer définitivement'),
              ),
            ],
          );
        });
      },
    );
    if (force == null || !mounted) return;
    await runWithLoader(context, () => repo.deleteUser(u.id, force: force), success: 'Compte supprimé');
    if (mounted) _reload();
  }
}
