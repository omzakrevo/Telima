import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/services/push_service.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/config_models.dart';
import '../../data/models/enums.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';

/// Route de détail d'une livraison selon le rôle.
String deliveryRouteFor(UserRole? role, String id) => switch (role) {
  UserRole.driver => '/driver/course/$id',
  UserRole.admin || UserRole.operator => '/admin/orders/$id',
  _ => '/client/delivery/$id',
};

void openNotification(BuildContext context, WidgetRef ref, AppNotification n) {
  final role = ref.read(currentUserProvider)?.role;
  ref.read(communicationRepositoryProvider).markNotificationRead(n.id).ignore();
  if (n.type == 'new_request' && role == UserRole.driver) {
    context.go('/driver');
  } else if (n.type == 'driver_application' && (role?.isStaff ?? false)) {
    final id = n.data['driver_id']?.toString();
    context.push(id == null ? '/admin/drivers' : '/admin/drivers/$id');
  } else if (n.type == 'withdrawal' && (role?.isStaff ?? false)) {
    context.push('/admin/finance');
  } else if (n.type == 'password_reset' && (role?.isStaff ?? false)) {
    context.push('/admin/support');
  } else if (n.deliveryId != null) {
    context.push(deliveryRouteFor(role, n.deliveryId!));
  }
}

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadCountProvider);
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: Icon(Icons.notifications_outlined, color: color),
      ),
    );
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () => ref.read(communicationRepositoryProvider).markAllNotificationsRead(),
            child: const Text('Tout marquer lu'),
          ),
        ],
      ),
      body: Constrained(
        maxWidth: 720,
        child: Column(
          children: [
            const _PermissionBanner(),
            Expanded(
              child: AsyncBody<List<AppNotification>>(
                value: async,
                onRetry: () => ref.invalidate(notificationsProvider),
                builder: (list) => list.isEmpty
                    ? const EmptyState(icon: Icons.notifications_none, message: 'Aucune notification')
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final n = list[i];
                          return Dismissible(
                            key: ValueKey(n.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: AppColors.danger,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) => ref.read(communicationRepositoryProvider).deleteNotification(n.id),
                            child: ListTile(
                              tileColor: n.isRead ? null : AppColors.primary.withValues(alpha: 0.05),
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                child: Icon(_icon(n.type), color: AppColors.primary),
                              ),
                              title: Text(n.title, style: TextStyle(fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w800)),
                              subtitle: Text('${n.body}\n${relativeTime(n.createdAt)}'),
                              isThreeLine: true,
                              onTap: () => openNotification(context, ref, n),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _icon(String type) => switch (type) {
    'delivery_status' => Icons.local_shipping_outlined,
    'driver_near' => Icons.near_me,
    'message' => Icons.chat_bubble_outline,
    'new_request' => Icons.add_alert_outlined,
    'withdrawal' => Icons.payments_outlined,
    'driver_status' || 'driver_application' => Icons.badge_outlined,
    _ => Icons.notifications_outlined,
  };
}

/// Bandeau affiché si l'utilisateur a refusé les notifications sur ce téléphone.
class _PermissionBanner extends StatefulWidget {
  const _PermissionBanner();
  @override
  State<_PermissionBanner> createState() => _PermissionBannerState();
}

class _PermissionBannerState extends State<_PermissionBanner> {
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final ok = await SystemNotifications.enabled();
    if (mounted) setState(() => _enabled = ok);
  }

  @override
  Widget build(BuildContext context) {
    if (_enabled) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: AppColors.accent.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.notifications_off_rounded, color: AppColors.accent),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Les notifications sont désactivées sur ce téléphone : vous ne verrez pas les alertes de courses et de messages.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () async {
                final ok = await SystemNotifications.requestPermission();
                if (!ok && context.mounted) {
                  showError(context, Exception('Autorisez-les dans Paramètres → Applications → Telima → Notifications.'));
                }
                await _refresh();
              },
              child: const Text('Activer'),
            ),
          ],
        ),
      ),
    );
  }
}
