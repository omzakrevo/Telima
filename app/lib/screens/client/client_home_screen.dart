import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../providers/auth_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/delivery_widgets.dart';
import '../../widgets/icon3d.dart';
import '../../widgets/motion.dart';
import '../../widgets/nav.dart';
import '../common/notifications_screen.dart';

class ClientHomeScreen extends ConsumerWidget {
  const ClientHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final active = ref.watch(myActiveDeliveriesProvider);
    final businesses = ref.watch(myBusinessesProvider).value ?? const [];

    final wide = MediaQuery.sizeOf(context).width > 600;
    final wallet = ref.watch(myWalletProvider);
    final services = <_Service>[
      _Service(Ico3D.package, 'Nouvel envoi', 'Prix immédiat', AppColors.mint, AppColors.primary, () => context.push('/client/new')),
      _Service(Ico3D.receipt, 'Historique', 'Mes envois', AppColors.sky, AppColors.info, () => context.push('/client/history')),
      _Service(Ico3D.store, businesses.isEmpty ? 'Compte pro' : 'Espace pro', 'Plusieurs arrêts', AppColors.lilac,
          const Color(0xFF6B4FD0), () => context.push('/business')),
      _Service(Ico3D.moneyBag, 'Recharger', 'Orange · Moov', AppColors.butter, const Color(0xFFB7860B),
          () => context.push('/client/wallet')),
      _Service(Ico3D.headphone, 'Support', 'Une question ?', AppColors.peach, AppColors.accent, () => context.push('/support')),
      _Service(Ico3D.bell, 'Alertes', 'Notifications', AppColors.rose, AppColors.danger, () => context.push('/notifications')),
    ];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 16,
        title: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () => context.push('/profile'),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            UserAvatar(name: user?.fullName ?? '?', url: user?.avatarUrl, radius: 22),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user?.fullName ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Text('Client Telima', style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
            ]),
          ]),
        ),
        actions: const [NotificationBell(), SizedBox(width: 8)],
      ),
      bottomNavigationBar: FloatingNavBar(
        index: 0,
        onChanged: (i) => switch (i) {
          1 => context.push('/client/history'),
          2 => context.push('/client/wallet'),
          3 => context.push('/profile'),
          _ => null,
        },
        items: const [
          NavItem(Icons.home_outlined, 'Accueil', selectedIcon: Icons.home_rounded),
          NavItem(Icons.receipt_long_outlined, 'Historique'),
          NavItem(Icons.account_balance_wallet_outlined, 'Portefeuille'),
          NavItem(Icons.person_outline_rounded, 'Profil'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myActiveDeliveriesProvider);
          ref.invalidate(myBusinessesProvider);
          ref.invalidate(myWalletProvider);
        },
        child: Constrained(
          maxWidth: 720,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            // Carte « solde » teintée
            FadeSlideIn(
              child: Material(
                color: AppColors.backdrop,
                borderRadius: BorderRadius.circular(18),
                elevation: 3,
                shadowColor: const Color(0x332B6B48),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => context.push('/client/wallet'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.soft),
                        alignment: Alignment.center,
                        child: const Icon3D(Ico3D.purse, size: 34, shadow: false),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Mon solde', style: TextStyle(fontSize: 12.5, color: AppColors.primaryDark, fontWeight: FontWeight.w600)),
                          wallet.when(
                            data: (w) => CountUpFcfa(value: w?.balance ?? 0,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
                            loading: () => const Text('…', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                            error: (_, _) => const Text('Voir le portefeuille', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      ),
                      const Icon(Icons.keyboard_double_arrow_right_rounded, color: AppColors.primaryDark),
                      const SizedBox(width: 6),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Appel à l'action principal
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: Pressable(
                onTap: () => context.push('/client/new'),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 14, 10, 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: AppShadows.raised,
                  ),
                  child: const Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Envoyer un colis', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                        SizedBox(height: 4),
                        Text('Un livreur proche le récupère en quelques minutes.',
                            style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ]),
                    ),
                    SizedBox(width: 10),
                    Icon3D(Ico3D.scooter, size: 76, float: true),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Deux autres grandes fonctions : courses à faire et transport de personnes
            FadeSlideIn(
              delay: const Duration(milliseconds: 140),
              child: Row(children: [
                Expanded(
                  child: _MainAction(
                    image: Ico3D.bags,
                    title: 'Faire une course',
                    caption: 'Repas, pharmacie, marché',
                    color: AppColors.accent,
                    onTap: () => context.push('/client/errand'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MainAction(
                    image: Ico3D.taxi,
                    title: 'Trajet',
                    caption: 'Moto-taxi ou voiture',
                    color: AppColors.ink,
                    onTap: () => context.push('/client/ride'),
                  ),
                ),
              ]),
            ),
            const SectionTitle('Services'),
            GridView.count(
              crossAxisCount: wide ? 6 : 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.92,
              children: [
                for (final (i, sv) in services.indexed) FadeSlideIn.staggered(index: i + 2, child: _ServiceCard(service: sv)),
              ],
            ),
            SectionTitle('En cours',
                trailing: TextButton(onPressed: () => context.push('/client/history'), child: const Text('Tout voir'))),
            active.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myActiveDeliveriesProvider)),
              data: (list) => list.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(16)),
                      child: const Row(children: [
                        Icon3D(Ico3D.package, size: 34),
                        SizedBox(width: 12),
                        Expanded(child: Text('Aucune livraison en cours', style: TextStyle(color: AppColors.textMuted))),
                      ]),
                    )
                  : Column(children: [
                      for (final (i, d) in list.indexed)
                        FadeSlideIn.staggered(
                          index: i + 1,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: DeliveryListTile(delivery: d, onTap: () => context.push('/client/delivery/${d.id}')),
                          ),
                        ),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Grande carte d'action secondaire (courses, trajets).
class _MainAction extends StatelessWidget {
  const _MainAction({required this.image, required this.title, required this.caption, required this.color, required this.onTap});
  final String image;
  final String title;
  final String caption;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.soft),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Icon3D(image, size: 34, shadow: false),
              ),
              const Spacer(),
              Icon(Icons.arrow_forward_rounded, size: 20, color: color),
            ]),
            const SizedBox(height: 10),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ]),
        ),
      );
}

class _Service {
  const _Service(this.image, this.label, this.caption, this.bg, this.fg, this.onTap);
  final String image;
  final String label;
  final String caption;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;
}

/// Carte de service : pastille illustrée + titre + légende.
class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service});
  final _Service service;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: service.onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: AppShadows.soft,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [service.bg, Color.lerp(service.bg, Colors.white, 0.55)!],
                  begin: Alignment.bottomRight,
                  end: Alignment.topLeft,
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Icon3D(service.image, size: 40),
            ),
            const SizedBox(height: 8),
            Text(service.label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            Text(service.caption, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          ]),
        ),
      );
}
