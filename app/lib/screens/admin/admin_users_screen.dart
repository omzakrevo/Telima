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
}
