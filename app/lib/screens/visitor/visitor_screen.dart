import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../data/models/delivery.dart';
import '../../data/models/enums.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/nav.dart';
import '../client/location_picker_screen.dart';
import '../common/support_screen.dart';

/// Mode visiteur : estimer le prix d'une livraison et contacter le support, sans compte.
class VisitorScreen extends ConsumerStatefulWidget {
  const VisitorScreen({super.key});
  @override
  ConsumerState<VisitorScreen> createState() => _VisitorScreenState();
}

class _VisitorScreenState extends ConsumerState<VisitorScreen> {
  int _tab = 0;
  PickedLocation? _from;
  PickedLocation? _to;
  PackageSize _size = PackageSize.petit;
  VehicleType? _vehicle;
  Quote? _quote;
  bool _loading = false;

  Future<void> _pick(bool from) async {
    final r = await Navigator.of(context).push<PickedLocation>(MaterialPageRoute(
      builder: (_) => LocationPickerScreen(title: from ? 'Point de récupération' : 'Destination', initial: (from ? _from : _to)?.point),
    ));
    if (r == null) return;
    setState(() => from ? _from = r : _to = r);
    _estimate();
  }

  Future<void> _estimate() async {
    if (_from == null || _to == null) return;
    setState(() => _loading = true);
    try {
      final route = await ref.read(routingServiceProvider).route([_from!.point, _to!.point]);
      final q = await ref.read(configRepositoryProvider).quote(
            pickupLat: _from!.point.latitude,
            pickupLng: _from!.point.longitude,
            dropoffLat: _to!.point.latitude,
            dropoffLng: _to!.point.longitude,
            vehicle: _vehicle,
            size: _size,
            routeKm: route.isEstimate ? null : route.distanceKm,
          );
      setState(() => _quote = q);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Estimer un prix' : 'Support'),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(authControllerProvider.notifier).leaveGuest();
              context.go('/welcome');
            },
            child: const Text('Se connecter'),
          ),
        ],
      ),
      body: _tab == 0 ? _simulator() : const SupportScreen(embedded: true),
      bottomNavigationBar: FloatingNavBar(
        index: _tab,
        onChanged: (i) => setState(() => _tab = i),
        items: const [
          NavItem(Icons.calculate_outlined, 'Estimer un prix', selectedIcon: Icons.calculate),
          NavItem(Icons.support_agent_outlined, 'Support', selectedIcon: Icons.support_agent),
        ],
      ),
    );
  }

  Widget _place(String label, PickedLocation? p, IconData icon, Color color, VoidCallback onTap) => Card(
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          subtitle: Text(
            p == null ? 'Choisir sur la carte' : (p.address ?? '${p.point.latitude.toStringAsFixed(4)}, ${p.point.longitude.toStringAsFixed(4)}'),
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          trailing: const Icon(Icons.map_outlined),
          onTap: onTap,
        ),
      );

  Widget _simulator() => Constrained(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Combien coûte ma livraison ?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          _place('Départ', _from, Icons.store_mall_directory, AppColors.primary, () => _pick(true)),
          const SizedBox(height: 8),
          _place('Arrivée', _to, Icons.flag, AppColors.danger, () => _pick(false)),
          const SectionTitle('Taille du colis'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in PackageSize.values)
              ChoiceChip(
                label: Text(s.label),
                selected: _size == s,
                onSelected: (_) {
                  setState(() => _size = s);
                  _estimate();
                },
              ),
          ]),
          const SectionTitle('Véhicule'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              label: const Text('Automatique'),
              selected: _vehicle == null,
              onSelected: (_) {
                setState(() => _vehicle = null);
                _estimate();
              },
            ),
            for (final v in VehicleType.values)
              ChoiceChip(
                avatar: Icon(v.icon, size: 18),
                label: Text(v.label),
                selected: _vehicle == v,
                onSelected: (_) {
                  setState(() => _vehicle = v);
                  _estimate();
                },
              ),
          ]),
          const SizedBox(height: 16),
          if (_loading) const LoadingView(),
          if (!_loading && _quote != null) ...[
            PriceSummary(
              distanceKm: _quote!.distanceKm,
              total: _quote!.total,
              base: _quote!.priceBase,
              distancePrice: _quote!.priceDistance,
              extras: _quote!.priceExtras,
              zone: _quote!.priceZone,
              zoneName: _quote!.zoneName,
            ),
            const SizedBox(height: 6),
            Text('Véhicule : ${_quote!.vehicleType.label}', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            BigActionButton(
              label: 'Créer un compte pour commander',
              color: AppColors.accent,
              onPressed: () {
                ref.read(authControllerProvider.notifier).leaveGuest();
                context.go('/register');
              },
            ),
          ],
          if (_from == null || _to == null)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Choisissez un départ et une arrivée pour voir le prix.', textAlign: TextAlign.center),
            ),
        ]),
      );
}
