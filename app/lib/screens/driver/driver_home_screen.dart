import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/delivery.dart';
import '../../data/models/driver.dart';
import '../../data/models/enums.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../providers/driver_tracking.dart';
import '../../widgets/common.dart';
import '../../widgets/icon3d.dart';
import '../../widgets/motion.dart';
import '../../widgets/nav.dart';
import '../common/notifications_screen.dart';
import '../common/profile_screen.dart';
import '../common/wallet_screen.dart';
import 'driver_earnings_screen.dart';

/// Coquille de l'espace livreur : Courses · Revenus · Portefeuille · Profil.
class DriverShell extends ConsumerStatefulWidget {
  const DriverShell({super.key});
  @override
  ConsumerState<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends ConsumerState<DriverShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final titles = ['Mes courses', 'Mes revenus', 'Portefeuille', 'Mon profil'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[_tab]), actions: const [NotificationBell(), SizedBox(width: 8)]),
      body: IndexedStack(index: _tab, children: const [
        _DriverHomeTab(),
        DriverEarningsScreen(),
        WalletScreen(isDriver: true, embedded: true),
        ProfileScreen(embedded: true),
      ]),
      bottomNavigationBar: FloatingNavBar(
        index: _tab,
        onChanged: (i) {
          setState(() => _tab = i);
          if (i == 1) ref.invalidate(driverEarningsProvider);
          if (i == 2) {
            ref.invalidate(myWalletProvider);
            ref.invalidate(myWalletTransactionsProvider);
          }
        },
        items: const [
          NavItem(Icons.delivery_dining_outlined, 'Courses', selectedIcon: Icons.delivery_dining),
          NavItem(Icons.bar_chart_outlined, 'Revenus', selectedIcon: Icons.bar_chart),
          NavItem(Icons.account_balance_wallet_outlined, 'Portefeuille', selectedIcon: Icons.account_balance_wallet),
          NavItem(Icons.person_outline, 'Profil', selectedIcon: Icons.person),
        ],
      ),
    );
  }
}

class _DriverHomeTab extends ConsumerWidget {
  const _DriverHomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(myDriverProfileProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myDriverProfileProvider);
        ref.invalidate(activeCoursesProvider);
        ref.invalidate(availableRequestsProvider);
      },
      child: AsyncBody<DriverProfile?>(
        value: profileAsync,
        onRetry: () => ref.invalidate(myDriverProfileProvider),
        builder: (profile) {
          if (profile == null || !profile.hasApplied) return const _ApplicationNeeded();
          if (profile.status != DriverStatus.approved) return _NotApproved(profile: profile);
          return _ApprovedHome(profile: profile);
        },
      ),
    );
  }
}

class _ApplicationNeeded extends StatelessWidget {
  const _ApplicationNeeded();
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.badge_outlined, size: 72, color: AppColors.primary),
        const SizedBox(height: 16),
        const Text('Complétez votre dossier livreur', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('CNIB, permis si nécessaire et informations sur votre véhicule. '
            'Votre compte sera vérifié par notre équipe.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        BigActionButton(label: 'Compléter mon dossier', icon: Icons.arrow_forward, onPressed: () => context.push('/driver/apply')),
      ]);
}

class _NotApproved extends StatelessWidget {
  const _NotApproved({required this.profile});
  final DriverProfile profile;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, text) = switch (profile.status) {
      DriverStatus.pending => (Icons.hourglass_top, AppColors.accent, 'Dossier en cours de vérification',
          'Notre équipe vérifie vos documents. Vous serez notifié dès l\'approbation.'),
      DriverStatus.suspended => (Icons.block, AppColors.danger, 'Compte suspendu', profile.statusNote ?? 'Contactez le support.'),
      _ => (Icons.cancel_outlined, AppColors.danger, 'Inscription refusée', profile.statusNote ?? 'Contactez le support pour plus d\'informations.'),
    };
    return ListView(padding: const EdgeInsets.all(24), children: [
      Icon(icon, size: 72, color: color),
      const SizedBox(height: 16),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(text, textAlign: TextAlign.center),
      const SizedBox(height: 24),
      OutlinedButton.icon(onPressed: () => context.push('/driver/apply'), icon: const Icon(Icons.edit), label: const Text('Modifier mon dossier')),
      const SizedBox(height: 8),
      TextButton.icon(onPressed: () => context.push('/support'), icon: const Icon(Icons.support_agent), label: const Text('Contacter le support')),
    ]);
  }
}

class _ApprovedHome extends ConsumerStatefulWidget {
  const _ApprovedHome({required this.profile});
  final DriverProfile profile;
  @override
  ConsumerState<_ApprovedHome> createState() => _ApprovedHomeState();
}

class _ApprovedHomeState extends ConsumerState<_ApprovedHome> {
  late bool _online = widget.profile.isOnline;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    // Reprise automatique du suivi GPS si le livreur était déjà en ligne (redémarrage, coupure)
    if (_online) Future.microtask(() => ref.read(driverTrackingProvider.notifier).start());
  }

  Future<void> _toggle(bool value) async {
    setState(() => _switching = true);
    try {
      double? lat, lng;
      if (value) {
        final p = await ref.read(locationServiceProvider).current();
        lat = p.latitude;
        lng = p.longitude;
      }
      await ref.read(driverRepositoryProvider).setOnline(value, lat: lat, lng: lng);
      if (value) {
        await ref.read(driverTrackingProvider.notifier).start();
      } else if ((ref.read(activeCoursesProvider).value ?? const []).isEmpty) {
        await ref.read(driverTrackingProvider.notifier).stop();
      }
      setState(() => _online = value);
      ref.invalidate(availableRequestsProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final active = ref.watch(activeCoursesProvider);
    final hasActive = (active.value ?? const []).isNotEmpty;

    return Constrained(
      maxWidth: 720,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        // Grand interrupteur En ligne / Hors ligne
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            color: _online ? AppColors.mint : AppColors.ink,
            borderRadius: BorderRadius.circular(28),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: _switching ? null : () => _toggle(!_online),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Row(children: [
                PulseRing(
                  active: _online,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: _online ? AppColors.primary : Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: _online
                        ? const Icon3D(Ico3D.scooter, size: 36, shadow: false)
                        : const Icon(Icons.power_settings_new_rounded, color: Colors.white, size: 26),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_online ? 'En ligne' : 'Hors ligne',
                        style: TextStyle(color: _online ? AppColors.ink : Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    const SizedBox(height: 2),
                    Text(_online ? 'Vous recevez les nouvelles demandes' : 'Touchez pour recevoir des courses',
                        style: TextStyle(color: _online ? AppColors.textMuted : Colors.white60, fontSize: 13)),
                  ]),
                ),
                _switching
                    ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: _online ? AppColors.ink : Colors.white))
                    : Switch(value: _online, onChanged: _toggle),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _MiniStat(image: Ico3D.star, label: 'Note', child: RatingDisplay(rating: widget.profile.ratingAvg, count: widget.profile.ratingCount))),
          const SizedBox(width: 10),
          Expanded(child: _MiniStat(image: Ico3D.package, label: 'Courses', child: Text('${widget.profile.totalDeliveries}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)))),
          if (widget.profile.activeVehicle != null) ...[
            const SizedBox(width: 10),
            Expanded(child: _MiniStat(image: Ico3D.scooter, label: widget.profile.activeVehicle!.type.label,
                child: Text(widget.profile.activeVehicle!.plateNumber ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)))),
          ],
        ]),
        const SizedBox(height: 12),
        _ServicesCard(profile: widget.profile),
        if (ref.watch(driverTrackingProvider).error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(ref.watch(driverTrackingProvider).error!, style: const TextStyle(color: AppColors.danger)),
          ),
        // Course(s) en cours
        if (hasActive) ...[
          const SectionTitle('Course en cours'),
          for (final d in active.value!)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ActiveCourseCard(delivery: d),
            ),
        ],
        if (_online && !hasActive) ...[
          SectionTitle('Demandes disponibles',
              trailing: IconButton(onPressed: () => ref.invalidate(availableRequestsProvider), icon: const Icon(Icons.refresh))),
          ref.watch(availableRequestsProvider).when(
                skipLoadingOnRefresh: true,
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(availableRequestsProvider)),
                data: (list) => list.isEmpty
                    ? const Card(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Column(children: [
                            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                            SizedBox(height: 12),
                            Text('En attente de demandes autour de vous…', textAlign: TextAlign.center),
                          ]),
                        ),
                      )
                    : Column(children: [for (final (i, r) in list.indexed) FadeSlideIn.staggered(index: i, child: _RequestCard(request: r))]),
              ),
        ],
        if (!_online && !hasActive)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Text('Bonjour ${user?.firstName ?? ''} ! Passez en ligne pour recevoir des courses.',
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 16)),
          ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => context.push('/driver/history'),
          icon: const Icon(Icons.history),
          label: const Text('Historique de mes courses'),
        ),
      ]),
    );
  }
}

/// Services proposés par le livreur : colis, courses à faire, transport de personnes (chauffeur).
class _ServicesCard extends ConsumerStatefulWidget {
  const _ServicesCard({required this.profile});
  final DriverProfile profile;
  @override
  ConsumerState<_ServicesCard> createState() => _ServicesCardState();
}

class _ServicesCardState extends ConsumerState<_ServicesCard> {
  late List<String> _services = [...widget.profile.services];
  bool _busy = false;

  Future<void> _toggle(String s, bool on) async {
    final next = on ? {..._services, s}.toList() : _services.where((e) => e != s).toList();
    if (next.isEmpty) {
      showError(context, Exception('Gardez au moins un service actif'));
      return;
    }
    final before = _services;
    setState(() {
      _services = next;
      _busy = true;
    });
    try {
      await ref.read(driverRepositoryProvider).setServices(next);
      ref.invalidate(availableRequestsProvider);
    } catch (e) {
      if (mounted) {
        setState(() => _services = before);
        showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.profile.activeVehicle?.type;
    final canRide = vehicle == VehicleType.moto || vehicle == VehicleType.voiture;
    Widget chip(String key, String label, String image) => FilterChip(
          showCheckmark: false,
          avatar: Image.asset(image, width: 20, height: 20),
          label: Text(label),
          selected: _services.contains(key),
          onSelected: _busy || (key == 'ride' && !canRide) ? null : (v) => _toggle(key, v),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: AppShadows.soft),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Je propose', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          chip('parcel', 'Colis', Ico3D.package),
          chip('errand', 'Courses', Ico3D.bags),
          chip('ride', 'Passagers', Ico3D.taxi),
        ]),
        if (!canRide)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Transport de passagers : moto ou voiture uniquement.', style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
          ),
      ]),
    );
  }
}

class _ActiveCourseCard extends StatelessWidget {
  const _ActiveCourseCard({required this.delivery});
  final Delivery delivery;

  @override
  Widget build(BuildContext context) => Card(
        color: delivery.status.color.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: delivery.status.color, width: 2)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/driver/course/${delivery.id}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(delivery.code, style: const TextStyle(fontWeight: FontWeight.w800)),
                if (delivery.isBatch) ...[const SizedBox(width: 6), Pill('Arrêt ${delivery.stopOrder}')],
                const Spacer(),
                StatusChip(delivery.status, label: delivery.statusLabel()),
              ]),
              const SizedBox(height: 8),
              Text(delivery.status.headingToPickup
                      ? '${delivery.isRide ? '🧍' : delivery.isErrand ? '🛍️' : '📦'} ${delivery.isErrand ? 'Achats : ${delivery.errandItems ?? ''}' : delivery.pickupAddress}'
                      : '🏁 ${delivery.dropoffAddress}',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(children: [
                Text(fcfa(delivery.driverEarning), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                const Spacer(),
                const Text('Ouvrir', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                const Icon(Icons.chevron_right, color: AppColors.primary),
              ]),
            ]),
          ),
        ),
      );
}

class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({required this.request});
  final AvailableRequest request;
  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final d = await ref.read(driverRepositoryProvider).accept(widget.request.id);
      ref.invalidate(activeCoursesProvider);
      ref.invalidate(availableRequestsProvider);
      if (mounted) context.push('/driver/course/${d.id}');
    } catch (e) {
      if (mounted) showError(context, e);
      ref.invalidate(availableRequestsProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    setState(() => _busy = true);
    try {
      await ref.read(driverRepositoryProvider).decline(widget.request.id);
      ref.invalidate(availableRequestsProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              if (r.kind == 'parcel') Icon(r.category.icon, color: AppColors.primary)
              else Icon3D(r.kind == 'ride' ? Ico3D.taxi : Ico3D.bags, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    switch (r.kind) {
                      'ride' => 'Passager${r.ridePassengers > 1 ? 's : ${r.ridePassengers}' : ''} · ${r.vehicleType.label}',
                      'errand' => 'Course à faire · ${errandCategoryLabel(r.errandCategory)}',
                      _ => '${r.category.label}${r.fragile ? ' · Fragile' : ''}${r.quantity > 1 ? ' · x${r.quantity}' : ''}',
                    },
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(fcfa(r.stopsCount > 1 ? r.batchEarning : r.earning),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primary)),
            ]),
            if (r.stopsCount > 1) Padding(padding: const EdgeInsets.only(top: 4), child: Pill('Tournée de ${r.stopsCount} arrêts', color: AppColors.info)),
            const SizedBox(height: 12),
            if (r.kind == 'errand') ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
                child: Text('🛍️ ${r.errandItems ?? ''}${r.errandBudget != null ? '\nBudget max : ${fcfa(r.errandBudget!)}' : ''}',
                    maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.35)),
              ),
              const SizedBox(height: 8),
              _place(Icons.flag, AppColors.danger, 'Livrer à', r.dropoffAddress, '${km(r.distanceToPickupKm)} de vous'),
              const SizedBox(height: 4),
              const Text('Vous avancez l’argent des achats : le client vous rembourse à la livraison.',
                  style: TextStyle(fontSize: 12, color: AppColors.accent)),
            ] else ...[
              _place(r.kind == 'ride' ? Icons.person_pin_circle_rounded : Icons.store_mall_directory, AppColors.primary,
                  r.kind == 'ride' ? 'Prise en charge' : 'Récupération', r.pickupAddress, '${km(r.distanceToPickupKm)} de vous'),
              const SizedBox(height: 8),
              _place(Icons.flag, AppColors.danger, 'Destination', r.dropoffAddress, 'Trajet ${km(r.distanceKm)}'),
            ],
            const SizedBox(height: 8),
            Text('Course : ${fcfa(r.totalPrice)} · ${r.paymentMethod.label} · ${r.vehicleType.label}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size.fromHeight(56)),
                  onPressed: _busy ? null : _decline,
                  child: const Text('Refuser'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _busy ? null : _accept,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                      : const Text('Accepter'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _place(IconData icon, Color color, String label, String address, String extra) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$label · $extra', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            Text(address, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]);
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.child, required this.image});
  final String label;
  final Widget child;
  final String image;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: AppShadows.soft),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon3D(image, size: 20, shadow: false),
            const SizedBox(width: 6),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
          ]),
          const SizedBox(height: 4),
          child,
        ]),
      );
}
