import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/delivery.dart';
import '../../data/models/enums.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';
import '../../widgets/icon3d.dart';
import '../../widgets/motion.dart';
import '../common/notifications_screen.dart';

/// Accueil client : en-tête sombre avec suivi par code, raccourcis, livraison en cours, bannières, navigation avec bouton « Envoyer ».
/// Style épuré : fond blanc cassé, orange pour l'action principale, texte anthracite, grands arrondis.
class _H {
  static const bg = Color(0xFFFAFAF8);
  static const gray = Color(0xFFF2F2EF); // surfaces douces
  static const line = Color(0xFFE9E9E5);
  static const hero = Color(0xFF181A19);
  static const orange = AppColors.accent;
  static const cream = Color(0xFFFFF3E6);
  static const muted = Color(0xFF8A8F8C);
  static const ok = Color(0xFF0B7A4B);
  static const sheetBg = Colors.white;
}

class ClientHomeScreen extends ConsumerStatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen> {
  final _code = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  /// Cherche une de mes commandes par son code (ex. LIV-2026-000012 ou seulement 000012).
  Future<void> _track() async {
    final q = _code.text.trim().toUpperCase().replaceAll('#', '');
    if (q.isEmpty || _searching) return;
    setState(() => _searching = true);
    try {
      final list = await ref.read(deliveryRepositoryProvider).myDeliveries(limit: 100);
      final found = list.where((d) => d.code.toUpperCase() == q || d.code.toUpperCase().endsWith(q)).toList();
      if (!mounted) return;
      if (found.isEmpty) {
        _msg('Aucune commande avec ce code');
      } else {
        _code.clear();
        context.push('/client/delivery/${found.first.id}');
      }
    } catch (_) {
      if (mounted) _msg('Recherche impossible pour le moment');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _more() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _H.sheetBg,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        final businesses = ref.read(myBusinessesProvider).value ?? const [];
        void go(String route) {
          Navigator.pop(ctx);
          context.push(route);
        }

        final items = <(IconData, String, String)>[
          (Icons.inventory_2_outlined, 'Trouver du gaz', '/client/gas'),
          (Icons.local_gas_station_outlined, 'Stations-service', '/client/fuel'),
          (Icons.restaurant_outlined, 'Restaurants', '/client/restaurants'),
          (Icons.storefront_outlined, 'Mon restaurant', '/restaurant'),
          (Icons.checkroom_outlined, 'Boutiques', '/client/shops'),
          (Icons.add_business_outlined, 'Ma boutique', '/shop'),
          (Icons.directions_bus_outlined, 'Voyages', '/client/voyages'),
          (Icons.airport_shuttle_outlined, 'Ma compagnie', '/transport'),
          (Icons.business_center_outlined, businesses.isEmpty ? 'Compte pro' : 'Espace pro', '/business'),
          (Icons.receipt_long_outlined, 'Historique', '/client/history'),
          (Icons.account_balance_wallet_outlined, 'Portefeuille', '/client/wallet'),
          (Icons.headset_mic_outlined, 'Support', '/support'),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tous les services', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 14,
                crossAxisSpacing: 8,
                childAspectRatio: 0.82,
                children: [for (final (icon, label, route) in items) _Tile(icon: icon, label: label, onTap: () => go(route))],
              ),
            ]),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final active = ref.watch(myActiveDeliveriesProvider);
    final wallet = ref.watch(myWalletProvider);
    final first = (user?.fullName ?? '').trim().split(RegExp(r'\s+')).first;

    return Scaffold(
      backgroundColor: _H.bg,
      bottomNavigationBar: _HomeNav(
        onHistory: () => context.push('/client/history'),
        onSend: () => context.push('/client/new'),
        onWallet: () => context.push('/client/wallet'),
        onProfile: () => context.push('/profile'),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: _H.orange,
          onRefresh: () async {
            ref.invalidate(myActiveDeliveriesProvider);
            ref.invalidate(myBusinessesProvider);
            ref.invalidate(myWalletProvider);
          },
          child: Constrained(
            maxWidth: 560,
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 28), children: [
              // En-tête : marque, solde, alertes, avatar
              Row(children: [
                const BrandMark(size: 30),
                const Spacer(),
                wallet.maybeWhen(
                  data: (w) => Pressable(
                    onTap: () => context.push('/client/wallet'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: _H.gray, borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.account_balance_wallet_outlined, size: 16),
                        const SizedBox(width: 6),
                        Text(fcfa(w?.balance ?? 0), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
                const SizedBox(width: 2),
                const NotificationBell(),
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => context.push('/profile'),
                  child: Stack(clipBehavior: Clip.none, children: [
                    UserAvatar(name: user?.fullName ?? '?', url: user?.avatarUrl, radius: 20),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),

              // Carte sombre : accueil + suivi d'une commande par son code
              FadeSlideIn(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                  decoration: BoxDecoration(color: _H.hero, borderRadius: BorderRadius.circular(28)),
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Transform.rotate(angle: 0.12, child: const Icon3D(Ico3D.package, size: 104, float: true)),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('LIVRAISON ET SERVICES',
                          style: TextStyle(color: Color(0xFFA7ADA9), fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
                      const SizedBox(height: 8),
                      Text(first.isEmpty ? 'Bonjour 👋' : 'Bonjour, $first 👋',
                          style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                      const SizedBox(height: 6),
                      const SizedBox(
                        width: 190,
                        child: Text('Envoyez, suivez et recevez en toute simplicité.',
                            style: TextStyle(color: Color(0xFFB9BEBB), fontSize: 13, height: 1.35)),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        height: 52,
                        padding: const EdgeInsets.only(left: 16, right: 6),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                        child: Row(children: [
                          const Icon(Icons.search_rounded, color: _H.muted, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _code,
                              textInputAction: TextInputAction.search,
                              textCapitalization: TextCapitalization.characters,
                              onSubmitted: (_) => _track(),
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                              decoration: const InputDecoration(
                                hintText: 'Suivre un colis (code de commande)',
                                hintStyle: TextStyle(color: _H.muted, fontSize: 14, fontWeight: FontWeight.w500),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: IconButton.filled(
                              onPressed: _searching ? null : _track,
                              style: IconButton.styleFrom(backgroundColor: _H.hero, foregroundColor: Colors.white),
                              tooltip: 'Suivre',
                              icon: _searching
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.arrow_forward_rounded, size: 20),
                            ),
                          ),
                        ]),
                      ),
                    ]),
                  ]),
                ),
              ),
              const SizedBox(height: 20),

              // Raccourcis
              FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _Tile(icon: Icons.near_me_rounded, label: 'Envoyer', primary: true, onTap: () => context.push('/client/new')),
                  _Tile(icon: Icons.shopping_basket_outlined, label: 'Course', onTap: () => context.push('/client/errand')),
                  _Tile(icon: Icons.two_wheeler_outlined, label: 'Trajet', onTap: () => context.push('/client/ride')),
                  _Tile(icon: Icons.directions_bus_outlined, label: 'Voyages', onTap: () => context.push('/client/voyages')),
                  _Tile(icon: Icons.more_horiz_rounded, label: 'Plus', onTap: _more),
                ]),
              ),
              const SizedBox(height: 26),

              // Livraison en cours
              _Heading('Livraison en cours', action: 'Tout voir', onAction: () => context.push('/client/history')),
              const SizedBox(height: 12),
              active.when(
                loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: LoadingView()),
                error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myActiveDeliveriesProvider)),
                data: (list) => list.isEmpty
                    ? _EmptyShipment(onSend: () => context.push('/client/new'))
                    : Column(children: [
                        for (final (i, d) in list.take(3).indexed)
                          FadeSlideIn.staggered(
                            index: i + 1,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ShipmentCard(delivery: d, onTap: () => context.push('/client/delivery/${d.id}')),
                            ),
                          ),
                      ]),
              ),
              const SizedBox(height: 14),

              // Bannières
              SizedBox(
                height: 138,
                child: PageView(controller: PageController(viewportFraction: 0.94), padEnds: false, children: [
                  _Promo(
                    label: 'RAPIDE. SÛR. FIABLE.',
                    headline: 'Un colis à envoyer ?\nOn vient le chercher.',
                    image: Ico3D.package,
                    onTap: () => context.push('/client/new'),
                  ),
                  _Promo(
                    label: 'RESTAURANTS',
                    headline: 'Faim ? Commandez\net suivez votre repas.',
                    image: Ico3D.food,
                    onTap: () => context.push('/client/restaurants'),
                  ),
                  _Promo(
                    label: 'VOYAGES',
                    headline: 'Votre ticket de car,\nréservé en ligne.',
                    image: Ico3D.pin,
                    onTap: () => context.push('/client/voyages'),
                  ),
                ]),
              ),
              const AdBanner(),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Raccourci : pastille grise (orange pour l'action principale) + libellé.
class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: SizedBox(
          width: 62,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: primary ? _H.orange : _H.gray,
                borderRadius: BorderRadius.circular(20),
                boxShadow: primary ? const [BoxShadow(color: Color(0x40F08A3C), blurRadius: 16, offset: Offset(0, 8))] : null,
              ),
              child: Icon(icon, size: 26, color: primary ? Colors.white : AppColors.ink),
            ),
            const SizedBox(height: 7),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, fontWeight: primary ? FontWeight.w800 : FontWeight.w600, color: AppColors.ink)),
          ]),
        ),
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, {this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3))),
        if (action != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text('$action ›', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _H.muted)),
            ),
          ),
      ]);
}

/// Les quatre étapes d'une livraison : commandée, récupérée, en route, livrée.
const _stages = ['Commandée', 'Récupérée', 'En route', 'Livrée'];

int _doneStages(DeliveryStatus s) {
  if (s == DeliveryStatus.completed) return 4;
  if (s.step >= DeliveryStatus.in_transit.step) return 3;
  if (s.step >= DeliveryStatus.picked_up.step) return 2;
  return 1;
}

class _ShipmentCard extends StatelessWidget {
  const _ShipmentCard({required this.delivery, required this.onTap});
  final Delivery delivery;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    final done = _doneStages(d.status);
    final title = d.isRide
        ? 'Trajet'
        : d.isErrand
            ? 'Course'
            : (d.packageDescription?.trim().isNotEmpty == true ? d.packageDescription!.trim() : d.packageCategory.label);
    final chipColor = d.status.isPending ? _H.orange : (d.status == DeliveryStatus.cancelled ? AppColors.danger : _H.ok);
    return Pressable(
      onTap: onTap,
      scale: 0.985,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _H.line),
          boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 8))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: _H.cream, borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: Icon3D(d.isRide ? Ico3D.taxi : d.isErrand ? Ico3D.bags : Ico3D.package, size: 30, shadow: false),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('#${d.code}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  [title, if (d.dropoffAddress.isNotEmpty) 'vers ${d.dropoffAddress}'].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: _H.muted),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: chipColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: chipColor, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(d.statusLabel(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: chipColor)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          _Progress(done: done),
          if (d.driverName != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.two_wheeler_outlined, size: 16, color: _H.muted),
              const SizedBox(width: 6),
              Expanded(child: Text('Livreur : ${d.driverName}', style: const TextStyle(fontSize: 12, color: _H.muted, fontWeight: FontWeight.w600))),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Barre d'avancement : étapes terminées en orange, à venir en gris clair.
class _Progress extends StatelessWidget {
  const _Progress({required this.done});
  final int done;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < _stages.length; i++) ...[
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: i < done ? _H.orange : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: i < done ? _H.orange : const Color(0xFFD3D5D2), width: 2),
                  ),
                  child: i < done ? const Icon(Icons.check_rounded, size: 9, color: Colors.white) : null,
                ),
                if (i < _stages.length - 1)
                  Expanded(child: Container(height: 2.5, margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(color: i < done - 1 ? _H.orange : const Color(0xFFE4E6E3), borderRadius: BorderRadius.circular(2)))),
              ]),
              const SizedBox(height: 6),
              Text(_stages[i],
                  maxLines: 1,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: i < done ? AppColors.ink : _H.muted)),
            ]),
          ),
        ],
      ]);
}

class _EmptyShipment extends StatelessWidget {
  const _EmptyShipment({required this.onSend});
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: _H.gray, borderRadius: BorderRadius.circular(22)),
        child: Row(children: [
          const Icon3D(Ico3D.package, size: 44),
          const SizedBox(width: 14),
          const Expanded(
            child: Text('Aucune livraison en cours.\nEnvoyez votre premier colis en 2 minutes.',
                style: TextStyle(fontSize: 13, color: _H.muted, height: 1.4, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onSend,
            style: FilledButton.styleFrom(
                backgroundColor: _H.orange, foregroundColor: Colors.white, shape: const StadiumBorder(), minimumSize: const Size(0, 40)),
            child: const Text('Envoyer', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}

/// Bannière crème : petit titre, accroche, grande illustration et bouton rond orange.
class _Promo extends StatelessWidget {
  const _Promo({required this.label, required this.headline, required this.image, required this.onTap});
  final String label;
  final String headline;
  final String image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Pressable(
          onTap: onTap,
          scale: 0.985,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
            decoration: BoxDecoration(color: _H.cream, borderRadius: BorderRadius.circular(24)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Color(0xFFB8651F))),
                  const SizedBox(height: 7),
                  Text(headline, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.3)),
                  const Spacer(),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(color: _H.orange, shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                  ),
                ]),
              ),
              Icon3D(image, size: 92, float: true),
            ]),
          ),
        ),
      );
}

/// Navigation du bas : Accueil, Commandes, grand bouton « Envoyer » surélevé, Portefeuille, Profil.
class _HomeNav extends StatelessWidget {
  const _HomeNav({required this.onHistory, required this.onSend, required this.onWallet, required this.onProfile});
  final VoidCallback onHistory;
  final VoidCallback onSend;
  final VoidCallback onWallet;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _H.line)),
          boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 20, offset: Offset(0, -6))],
        ),
        child: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SizedBox(
                height: 66,
                child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                  Row(children: [
                    Expanded(child: _NavItem(icon: Icons.home_rounded, label: 'Accueil', active: true, onTap: () {})),
                    Expanded(child: _NavItem(icon: Icons.receipt_long_outlined, label: 'Commandes', onTap: onHistory)),
                    const Expanded(child: SizedBox()),
                    Expanded(child: _NavItem(icon: Icons.account_balance_wallet_outlined, label: 'Portefeuille', onTap: onWallet)),
                    Expanded(child: _NavItem(icon: Icons.person_outline_rounded, label: 'Profil', onTap: onProfile)),
                  ]),
                  Positioned(
                    top: -22,
                    child: Semantics(
                      button: true,
                      label: 'Envoyer un colis',
                      child: Pressable(
                        onTap: onSend,
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 62,
                            height: 62,
                            decoration: BoxDecoration(
                              color: _H.orange,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              boxShadow: const [BoxShadow(color: Color(0x59F08A3C), blurRadius: 18, offset: Offset(0, 8))],
                            ),
                            child: Transform.rotate(angle: -0.5, child: const Icon(Icons.send_rounded, color: Colors.white, size: 26)),
                          ),
                          const SizedBox(height: 2),
                          const Text('Envoyer', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(children: [
            Icon(icon, size: 24, color: active ? _H.orange : _H.muted),
            const SizedBox(height: 3),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: active ? _H.orange : _H.muted)),
          ]),
        ),
      );
}
