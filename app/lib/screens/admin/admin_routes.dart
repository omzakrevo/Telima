import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../data/models/enums.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/brand.dart';
import '../common/notifications_screen.dart';
import 'admin_config_screens.dart';
import 'admin_dashboard_screen.dart';
import 'admin_drivers_screens.dart';
import 'admin_gas_screen.dart';
import 'admin_finance_screen.dart';
import 'admin_misc_screens.dart';
import 'admin_orders_screens.dart';
import 'admin_payments_screen.dart';
import 'admin_push_screen.dart';
import 'admin_restaurants_screen.dart';
import 'admin_releases_screen.dart';
import 'admin_users_screen.dart';

class _NavItem {
  const _NavItem(this.path, this.label, this.icon, {this.adminOnly = false});
  final String path;
  final String label;
  final IconData icon;
  final bool adminOnly;
}

const _items = [
  _NavItem('/admin', 'Tableau de bord', Icons.dashboard_outlined),
  _NavItem('/admin/orders', 'Commandes', Icons.receipt_long_outlined),
  _NavItem('/admin/orders/new', 'Commande téléphone', Icons.add_call),
  _NavItem('/admin/map', 'Carte en direct', Icons.map_outlined),
  _NavItem('/admin/drivers', 'Livreurs', Icons.delivery_dining_outlined),
  _NavItem('/admin/users', 'Utilisateurs', Icons.people_outline),
  _NavItem('/admin/gas', 'Gaz & carburant', Icons.inventory_2_outlined),
  _NavItem('/admin/restaurants', 'Restaurants', Icons.restaurant_outlined),
  _NavItem('/admin/payments', 'Paiements à vérifier', Icons.fact_check_outlined, adminOnly: true),
  _NavItem('/admin/finance', 'Paiements & retraits', Icons.payments_outlined),
  _NavItem('/admin/pricing', 'Tarifs', Icons.price_change_outlined, adminOnly: true),
  _NavItem('/admin/zones', 'Villes & zones', Icons.location_city_outlined, adminOnly: true),
  _NavItem('/admin/settings', 'Paramètres', Icons.tune, adminOnly: true),
  _NavItem('/admin/releases', 'Application mobile', Icons.system_update_rounded, adminOnly: true),
  _NavItem('/admin/push', 'Notifications push', Icons.notifications_active_rounded, adminOnly: true),
  _NavItem('/admin/support', 'Support', Icons.support_agent),
  _NavItem('/admin/logs', 'Journal', Icons.history_edu_outlined, adminOnly: true),
];

ShellRoute adminShellRoute() => ShellRoute(
      builder: (context, state, child) => AdminShell(location: state.matchedLocation, child: child),
      routes: [
        GoRoute(path: '/admin', builder: (_, _) => const AdminDashboardScreen()),
        GoRoute(path: '/admin/orders', builder: (_, _) => const AdminOrdersScreen()),
        GoRoute(path: '/admin/orders/new', builder: (_, _) => const AdminCreateOrderScreen()),
        GoRoute(path: '/admin/orders/:id', builder: (_, s) => AdminOrderDetailScreen(deliveryId: s.pathParameters['id']!)),
        GoRoute(path: '/admin/map', builder: (_, _) => const AdminLiveMapScreen()),
        GoRoute(path: '/admin/drivers', builder: (_, _) => const AdminDriversScreen()),
        GoRoute(path: '/admin/drivers/:id', builder: (_, s) => AdminDriverDetailScreen(driverId: s.pathParameters['id']!)),
        GoRoute(path: '/admin/users', builder: (_, _) => const AdminUsersScreen()),
        GoRoute(path: '/admin/finance', builder: (_, _) => const AdminFinanceScreen()),
        GoRoute(path: '/admin/pricing', builder: (_, _) => const AdminPricingScreen()),
        GoRoute(path: '/admin/zones', builder: (_, _) => const AdminZonesScreen()),
        GoRoute(path: '/admin/settings', builder: (_, _) => const AdminSettingsScreen()),
        GoRoute(path: '/admin/releases', builder: (_, _) => const AdminReleasesScreen()),
        GoRoute(path: '/admin/push', builder: (_, _) => const AdminPushScreen()),
        GoRoute(path: '/admin/gas', builder: (_, _) => const AdminGasScreen()),
        GoRoute(path: '/admin/restaurants', builder: (_, _) => const AdminRestaurantsScreen()),
        GoRoute(path: '/admin/payments', builder: (_, _) => const AdminPaymentsScreen()),
        GoRoute(path: '/admin/support', builder: (_, _) => const AdminSupportScreen()),
        GoRoute(path: '/admin/logs', builder: (_, _) => const AdminLogsScreen()),
      ],
    );

/// Coquille du tableau de bord : rail de navigation sur grand écran, tiroir sur mobile.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isAdmin = user?.role == UserRole.admin;
    final items = _items.where((i) => !i.adminOnly || isAdmin).toList();
    var selected = 0;
    for (var i = 0; i < items.length; i++) {
      final p = items[i].path;
      if (location == p || (p != '/admin' && location.startsWith(p) && !(p == '/admin/orders' && location == '/admin/orders/new'))) {
        selected = i;
      }
    }
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    Widget navList({bool closeOnTap = false}) => ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: BrandMark(size: 30, badge: user?.role.label),
          ),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
              child: ListTile(
                dense: true,
                selected: i == selected,
                selectedColor: AppColors.ink,
                selectedTileColor: AppColors.field,
                iconColor: AppColors.textMuted,
                leading: Icon(items[i].icon, size: 21),
                title: Text(items[i].label,
                    style: TextStyle(fontSize: 14, fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500)),
                onTap: () {
                  if (closeOnTap) Navigator.pop(context);
                  context.go(items[i].path);
                },
              ),
            ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20), child: Divider()),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(user?.fullName ?? ''),
            subtitle: const Text('Mon profil'),
            onTap: () => context.push('/profile'),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.danger),
            title: const Text('Déconnexion', style: TextStyle(color: AppColors.danger)),
            onTap: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ]);

    final page = Scaffold(
      appBar: AppBar(
        title: Text(items[selected].label),
        automaticallyImplyLeading: !wide,
        actions: const [NotificationBell(), SizedBox(width: 8)],
      ),
      drawer: wide ? null : Drawer(backgroundColor: Colors.white, child: navList(closeOnTap: true)),
      body: child,
    );
    if (!wide) return page;
    return Row(children: [
      Container(
        width: 260,
        decoration: const BoxDecoration(color: Colors.white, border: Border(right: BorderSide(color: AppColors.line))),
        child: Material(color: Colors.white, child: navList()),
      ),
      Expanded(child: page),
    ]);
  }
}
