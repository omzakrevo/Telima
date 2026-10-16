import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../data/models/delivery.dart';
import '../../data/models/restaurant.dart';
import '../../data/models/shop.dart';
import '../../data/models/travel.dart';
import '../../providers/data_providers.dart';
import '../../providers/restaurant_providers.dart';
import '../../providers/shop_providers.dart';
import '../../providers/travel_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/icon3d.dart';
import '../restaurant/restaurant_widgets.dart';
import '../shop/shop_widgets.dart';

/// Un raccourci de service retrouvable par mots-clés (gaz, voyage, taxi…).
class _Svc {
  const _Svc(this.label, this.hint, this.asset, this.route, this.words);
  final String label;
  final String hint;
  final String asset;
  final String route;
  final String words;
}

const _services = [
  _Svc(
    'Envoyer un colis',
    'Livraison par coursier',
    Ico3D.package,
    '/client/new',
    'colis envoyer livraison livrer coursier paquet courrier',
  ),
  _Svc(
    'Course',
    'On achète et on vous livre',
    Ico3D.bags,
    '/client/errand',
    'course achat acheter commission marché',
  ),
  _Svc(
    'Trajet moto / taxi',
    'Un chauffeur vous transporte',
    Ico3D.taxi,
    '/client/ride',
    'trajet taxi moto transport déplacement course chauffeur',
  ),
  _Svc(
    'Voyages en car',
    'Billets de compagnies',
    Ico3D.map,
    '/client/voyages',
    'voyage voyages car bus billet ticket ticket compagnie trajet ville',
  ),
  _Svc(
    'Restaurants',
    'Plats livrés chez vous',
    Ico3D.food,
    '/client/restaurants',
    'restaurant repas plat manger nourriture faim cuisine',
  ),
  _Svc(
    'Boutiques',
    'Vêtements, chaussures, accessoires',
    Ico3D.bags,
    '/client/shops',
    'boutique boutiques vêtement habit chaussure mode magasin shopping',
  ),
  _Svc(
    'Gaz',
    'Trouver et se faire livrer du gaz',
    Ico3D.package,
    '/client/gas',
    'gaz bouteille butane cuisine',
  ),
  _Svc(
    'Stations-service',
    'Carburant près de vous',
    Ico3D.pin,
    '/client/fuel',
    'station carburant essence gasoil pompe',
  ),
  _Svc(
    'Portefeuille',
    'Solde et recharges',
    Ico3D.purse,
    '/client/wallet',
    'portefeuille solde recharge argent paiement wallet',
  ),
  _Svc(
    'Historique',
    'Mes commandes passées',
    Ico3D.receipt,
    '/client/history',
    'historique commandes passées reçu facture',
  ),
  _Svc(
    'Support',
    'Une question ? Écrivez-nous',
    Ico3D.headphone,
    '/support',
    'support aide contact problème assistance',
  ),
];

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[àâä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùûü]'), 'u')
    .replaceAll('ç', 'c');

bool _hit(String query, Iterable<String?> fields) {
  final q = _norm(query);
  return fields.any((f) => f != null && _norm(f).contains(q));
}

/// Recherche unique : services, mes commandes (par code), restaurants, boutiques, compagnies de voyage.
class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key, this.initialQuery = ''});
  final String initialQuery;

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  late final _c = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  late String _q = widget.initialQuery.trim();

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _q = v.trim());
    });
    setState(() {}); // met à jour la croix
  }

  @override
  Widget build(BuildContext context) {
    final searching = _q.length >= 2;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _c,
            autofocus: widget.initialQuery.isEmpty,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (v) => setState(() => _q = v.trim()),
            decoration: InputDecoration(
              hintText: 'Boutique, restaurant, compagnie, service, code…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _c.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _c.clear();
                        setState(() => _q = '');
                      },
                    ),
              filled: true,
              fillColor: AppColors.field,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ),
      body: Constrained(
        maxWidth: 560,
        child: searching ? _Results(query: _q) : const _Suggestions(),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    children: [
      const _Title('Tous les services'),
      for (final s in _services) _SvcRow(svc: s),
    ],
  );
}

class _Results extends ConsumerWidget {
  const _Results({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = _services
        .where((s) => _hit(query, [s.label, s.hint, s.words]))
        .toList();
    final deliveries =
        (ref.watch(myDeliveriesProvider).value ?? const <Delivery>[])
            .where(
              (d) => _hit(query, [
                d.code,
                d.dropoffAddress,
                d.pickupAddress,
                d.packageDescription,
              ]),
            )
            .take(5)
            .toList();
    final restaurants = ref.watch(nearbyRestaurantsProvider(query));
    final shops = ref.watch(nearbyShopsProvider(query));
    final companies = ref.watch(travelCompaniesProvider);
    final comps = (companies.value ?? const <TransportCompany>[])
        .where((c) => _hit(query, [c.name, c.city, c.description]))
        .toList();
    final loading =
        restaurants.isLoading || shops.isLoading || companies.isLoading;
    final rList = restaurants.value ?? const <Restaurant>[];
    final sList = shops.value ?? const <Shop>[];
    final empty =
        services.isEmpty &&
        deliveries.isEmpty &&
        rList.isEmpty &&
        sList.isEmpty &&
        comps.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (services.isNotEmpty) ...[
          const _Title('Services'),
          for (final s in services) _SvcRow(svc: s),
        ],
        if (deliveries.isNotEmpty) ...[
          const _Title('Mes commandes'),
          for (final d in deliveries)
            _Row(
              leading: const Icon3D(Ico3D.package, size: 36, shadow: false),
              title: '#${d.code}',
              subtitle: d.dropoffAddress,
              onTap: () => context.push('/client/delivery/${d.id}'),
            ),
        ],
        if (rList.isNotEmpty) ...[
          const _Title('Restaurants'),
          for (final r in rList.take(6))
            _Row(
              leading: PhotoBox(url: r.logoUrl, size: 44, radius: 12),
              title: r.name,
              subtitle: r.subtitle,
              onTap: () => context.push('/r/${r.slug}'),
            ),
        ],
        if (sList.isNotEmpty) ...[
          const _Title('Boutiques'),
          for (final s in sList.take(6))
            _Row(
              leading: ShopPhotoBox(url: s.logoUrl, size: 44, radius: 12),
              title: s.name,
              subtitle: [
                if ((s.shopType ?? '').isNotEmpty) s.shopType!,
                if ((s.neighborhood ?? '').isNotEmpty) s.neighborhood!,
              ].join(' · '),
              onTap: () => context.push('/b/${s.slug}'),
            ),
        ],
        if (comps.isNotEmpty) ...[
          const _Title('Compagnies de voyage'),
          for (final c in comps.take(6))
            _Row(
              leading: PhotoBox(
                url: c.logoUrl,
                size: 44,
                radius: 12,
                icon: Icons.directions_bus_rounded,
              ),
              title: c.name,
              subtitle: c.city ?? '',
              onTap: () => context.push('/v/${c.slug}'),
            ),
        ],
        if (loading && empty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: LoadingView(),
          ),
        if (!loading && empty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: EmptyState(
              icon: Icons.search_off_rounded,
              message:
                  'Aucun résultat pour « $query ».\nEssayez un autre mot : gaz, voyage, pizza, boutique…',
            ),
          ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: AppColors.textMuted,
      ),
    ),
  );
}

class _SvcRow extends StatelessWidget {
  const _SvcRow({required this.svc});
  final _Svc svc;

  @override
  Widget build(BuildContext context) => _Row(
    leading: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.mint,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon3D(svc.asset, size: 30, shadow: false),
    ),
    title: svc.label,
    subtitle: svc.hint,
    onTap: () => context.push(svc.route),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    ),
  );
}
