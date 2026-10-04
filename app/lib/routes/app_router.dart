import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/enums.dart';
import '../providers/auth_providers.dart';
import '../screens/admin/admin_routes.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/welcome_screen.dart';
import '../screens/business/batch_delivery_screen.dart';
import '../screens/business/business_screens.dart';
import '../screens/client/client_home_screen.dart';
import '../screens/client/delivery_history_screen.dart';
import '../screens/client/delivery_tracking_screen.dart';
import '../screens/client/service_screens.dart';
import '../screens/client/new_delivery_screen.dart';
import '../screens/common/chat_screen.dart';
import '../screens/common/notifications_screen.dart';
import '../screens/common/profile_screen.dart';
import '../screens/common/support_screen.dart';
import '../screens/common/system_screens.dart';
import '../screens/common/wallet_screen.dart';
import '../screens/driver/driver_application_screen.dart';
import '../screens/driver/driver_course_screen.dart';
import '../screens/driver/driver_earnings_screen.dart';
import '../screens/driver/driver_home_screen.dart';
import '../screens/visitor/visitor_screen.dart';

const _publicPaths = {'/welcome', '/login', '/register', '/forgot'};

String homeFor(UserRole role) => switch (role) {
      UserRole.admin || UserRole.operator => '/admin',
      UserRole.driver => '/driver',
      UserRole.client => '/client',
    };

/// Routage : chaque rôle a son espace ; les accès non autorisés sont redirigés.
/// (La sécurité réelle est assurée côté serveur par la RLS et les fonctions.)
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final path = state.matchedLocation;

      if (auth.loading || (auth.session != null && auth.profile == null)) {
        return path == '/splash' ? null : '/splash';
      }
      if (!auth.isSignedIn) {
        if (auth.isGuest && (path == '/visitor' || path == '/support')) return null;
        if (_publicPaths.contains(path)) return null;
        return '/welcome';
      }

      final role = auth.profile!.role;
      final home = homeFor(role);
      if (path == '/splash' || path == '/visitor' || _publicPaths.contains(path)) return home;
      if (path.startsWith('/admin') && !role.isStaff) return home;
      if (path == '/driver' && role != UserRole.driver) return home;
      if (path.startsWith('/driver/') && role != UserRole.driver && path != '/driver/apply') return home;
      if ((path.startsWith('/client') || path.startsWith('/business')) && role == UserRole.driver) {
        // un livreur peut consulter le suivi d'une livraison qu'il a lui-même commandée
        if (!path.startsWith('/client/delivery/')) return home;
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, s) => RegisterScreen(asDriver: s.uri.queryParameters['driver'] == '1')),
      GoRoute(path: '/forgot', builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(path: '/visitor', builder: (_, _) => const VisitorScreen()),

      // Commun
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/profile/edit', builder: (_, _) => const EditProfileScreen()),
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: '/support', builder: (_, s) => SupportScreen(deliveryId: s.uri.queryParameters['delivery'])),
      GoRoute(path: '/chat/:id', builder: (_, s) => ChatScreen(deliveryId: s.pathParameters['id']!)),

      // Client
      GoRoute(path: '/client', builder: (_, _) => const ClientHomeScreen()),
      GoRoute(path: '/client/errand', builder: (_, _) => const ErrandScreen()),
      GoRoute(path: '/client/ride', builder: (_, _) => const RideScreen()),
      GoRoute(path: '/client/new', builder: (_, s) => NewDeliveryScreen(businessId: s.uri.queryParameters['business'])),
      GoRoute(path: '/client/history', builder: (_, _) => const DeliveryHistoryScreen()),
      GoRoute(path: '/client/wallet', builder: (_, _) => const WalletScreen()),
      GoRoute(path: '/client/delivery/:id', builder: (_, s) => DeliveryTrackingScreen(deliveryId: s.pathParameters['id']!)),

      // Professionnels
      GoRoute(path: '/business', builder: (_, _) => const BusinessListScreen()),
      GoRoute(path: '/business/:id', builder: (_, s) => BusinessDashboardScreen(businessId: s.pathParameters['id']!)),
      GoRoute(path: '/business/:id/batch', builder: (_, s) => BatchDeliveryScreen(businessId: s.pathParameters['id']!)),

      // Livreur
      GoRoute(path: '/driver', builder: (_, _) => const DriverShell()),
      GoRoute(path: '/driver/apply', builder: (_, _) => const DriverApplicationScreen()),
      GoRoute(path: '/driver/course/:id', builder: (_, s) => DriverCourseScreen(deliveryId: s.pathParameters['id']!)),
      GoRoute(path: '/driver/history', builder: (_, _) => const DriverHistoryScreen()),

      // Administration
      adminShellRoute(),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Page introuvable')),
      body: Center(
        child: TextButton(onPressed: () => context.go('/splash'), child: const Text('Retour à l\'accueil')),
      ),
    ),
  );
});
