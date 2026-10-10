import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/config_models.dart';
import '../../data/models/gas.dart';
import '../../providers/core_providers.dart';
import '../client/location_picker_screen.dart' show geocodingProvider;
import '../../providers/gas_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/map_widgets.dart';
import '../../widgets/motion.dart';
import 'gas_widgets.dart';

/// « Gaz & carburant » : points de vente de gaz et stations-service autour de moi.
class GasHomeScreen extends ConsumerStatefulWidget {
  const GasHomeScreen({super.key, this.stations = false});
  final bool stations;

  @override
  ConsumerState<GasHomeScreen> createState() => _GasHomeScreenState();
}

class _GasHomeScreenState extends ConsumerState<GasHomeScreen> {
  bool _map = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(gasFiltersProvider.notifier).set(GasFilters(stations: widget.stations)));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _update(GasFilters Function(GasFilters) f) => ref.read(gasFiltersProvider.notifier).set(f(ref.read(gasFiltersProvider)));

  /// Texte saisi : d'abord comme un quartier (on recentre la recherche dessus), sinon comme un nom / une enseigne.
  Future<void> _submitSearch(String text) async {
    final v = text.trim();
    if (v.isEmpty) {
      _update((f) => f.copyWith(query: '', clearArea: true));
      return;
    }
    final f = ref.read(gasFiltersProvider);
    final cities = ref.read(citiesProvider).value ?? const <City>[];
    final city = cities.where((c) => c.id == f.cityId).firstOrNull;
    final near = city?.center ?? ref.read(myPositionProvider).value;
    final label = city == null ? v : '$v, ${city.name}';
    final hits = await ref.read(geocodingProvider).search('$label, Burkina Faso', near: near);
    if (!mounted) return;
    if (hits.isNotEmpty) {
      _update((x) => x.copyWith(query: '', area: hits.first.point, areaLabel: v, clearRadius: true));
    } else {
      _update((x) => x.copyWith(query: v, clearArea: true));
    }
  }

  Future<void> _pickCity() async {
    final cities = (ref.read(citiesProvider).value ?? const <City>[]).where((c) => c.isActive).toList();
    final f = ref.read(gasFiltersProvider);
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            leading: const Icon(Icons.my_location),
            title: const Text('Autour de ma position'),
            selected: f.cityId == null,
            onTap: () => Navigator.pop(context, ''),
          ),
          for (final c in cities)
            ListTile(leading: const Icon(Icons.location_city), title: Text(c.name), selected: f.cityId == c.id, onTap: () => Navigator.pop(context, c.id)),
        ]),
      ),
    );
    if (id == null) return;
    _search.clear();
    _update((x) => id.isEmpty
        ? x.copyWith(clearCity: true, clearArea: true, clearRadius: true, query: '')
        : x.copyWith(cityId: id, clearArea: true, clearRadius: true, query: ''));
  }

  Future<void> _filters() async {
    final brands = ref.read(gasBrandsProvider).value ?? const [];
    final f = ref.read(gasFiltersProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: StatefulBuilder(builder: (context, setS) {
          final cur = ref.read(gasFiltersProvider);
          void set(GasFilters n) {
            ref.read(gasFiltersProvider.notifier).set(n);
            setS(() {});
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Filtres', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              const Text('Marque', style: TextStyle(fontWeight: FontWeight.w700)),
              Wrap(spacing: 8, children: [
                ChoiceChip(label: const Text('Toutes'), selected: cur.brandId == null, onSelected: (_) => set(cur.copyWith(clearBrand: true))),
                for (final b in brands)
                  ChoiceChip(label: Text(b.name), selected: cur.brandId == b.id, onSelected: (_) => set(cur.copyWith(brandId: b.id))),
              ]),
              const SizedBox(height: 12),
              const Text('Bouteille', style: TextStyle(fontWeight: FontWeight.w700)),
              Wrap(spacing: 8, children: [
                ChoiceChip(label: const Text('Toutes'), selected: cur.size == null, onSelected: (_) => set(cur.copyWith(clearSize: true))),
                for (final s in const [3.0, 6.0, 12.5, 38.0])
                  ChoiceChip(label: Text('${s == s.roundToDouble() ? s.toInt() : s} kg'), selected: cur.size == s, onSelected: (_) => set(cur.copyWith(size: s))),
              ]),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Seulement disponible'), value: cur.onlyAvailable, onChanged: (v) => set(cur.copyWith(onlyAvailable: v))),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Livraison à domicile'), value: cur.delivers, onChanged: (v) => set(cur.copyWith(delivers: v))),
              const SizedBox(height: 4),
              BigActionButton(label: 'Voir les résultats', onPressed: () => Navigator.pop(context)),
            ]),
          );
        }),
      ),
    );
    if (f != ref.read(gasFiltersProvider)) ref.invalidate(nearbyPlacesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(gasFiltersProvider);
    final places = ref.watch(nearbyPlacesProvider);
    final pos = ref.watch(myPositionProvider).value;
    final stations = widget.stations;
    final activeFilters = (filters.brandId != null ? 1 : 0) + (filters.size != null ? 1 : 0) + (filters.onlyAvailable ? 1 : 0) + (filters.delivers ? 1 : 0);
    return Scaffold(
      appBar: AppBar(
        title: Text(stations ? 'Stations-service' : 'Trouver du gaz'),
        actions: [
          IconButton(
            tooltip: 'Mes favoris',
            onPressed: () => context.push('/client/gas/favorites'),
            icon: const Icon(Icons.star_rounded),
          ),
          IconButton(
            tooltip: 'Mes commandes de gaz',
            onPressed: () => context.push('/client/gas/orders'),
            icon: const Icon(Icons.receipt_long_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _map = !_map),
        icon: Icon(_map ? Icons.list_alt : Icons.map_outlined),
        label: Text(_map ? 'Liste' : 'Carte'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Quartier, nom, enseigne…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () {
                          _search.clear();
                          _update((f) => f.copyWith(query: ''));
                        }),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: _submitSearch,
              ),
            ),
            if (!stations) ...[
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: activeFilters > 0,
                label: Text('$activeFilters'),
                child: IconButton.filledTonal(onPressed: _filters, icon: const Icon(Icons.tune)),
              ),
            ],
          ]),
        ),
        _ZoneBar(onPickCity: _pickCity, onClearArea: () {
          _search.clear();
          _update((f) => f.copyWith(clearArea: true, query: ''));
        }),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myPositionProvider);
              ref.invalidate(nearbyPlacesProvider);
            },
            child: AsyncBody<List<Place>>(
              value: places,
              onRetry: () => ref.invalidate(nearbyPlacesProvider),
              builder: (list) {
                if (_map) {
                  final center = filters.customCenter ? ref.watch(searchCenterProvider).value : pos;
                  return _PlacesMap(key: ValueKey('${list.length}-${center?.latitude}-${center?.longitude}'), places: list, me: center);
                }
                if (list.isEmpty) {
                  return ListView(children: [
                    const SizedBox(height: 60),
                    Icon(stations ? Icons.directions_car : Icons.inventory_2, size: 56, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    const Center(child: Text('Aucun résultat dans ce rayon', style: TextStyle(fontWeight: FontWeight.w700))),
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Agrandissez le rayon, changez de ville, ou enlevez un filtre. De nouveaux points sont ajoutés régulièrement : de nouveaux points sont ajoutés régulièrement.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
                    ),
                  ]);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => FadeSlideIn.staggered(index: i.clamp(0, 6), child: PlaceCard(place: list[i], fromLabel: filters.customCenter ? 'du centre' : 'de vous')),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

/// Carte d'un point dans la liste « Autour de moi ».
class PlaceCard extends StatelessWidget {
  const PlaceCard({super.key, required this.place, this.fromLabel = 'de vous'});
  final Place place;
  final String fromLabel;

  @override
  Widget build(BuildContext context) {
    final p = place;
    return Pressable(
      onTap: () => context.push('/client/gas/place/${p.id}', extra: p),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: AppShadows.soft),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            PlaceIcon(isStation: p.isStation),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                if (p.subtitle.isNotEmpty) Text(p.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ]),
            ),
            if (p.distanceKm != null)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(km(p.distanceKm), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
                Text(fromLabel, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ]),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            RatingBadge(avg: p.ratingAvg, count: p.ratingCount),
            if (p.hasQueue) QueueChip(place: p),
            if (p.promoTitle != null) SmallTag(p.promoTitle!, AppColors.danger, icon: Icons.tag),
            if (p.boost >= 2) const SmallTag('Sponsorisé', AppColors.info) else if (p.boost == 1) const SmallTag('Recommandé', AppColors.primaryDark, icon: Icons.verified_rounded),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (p.isStation)
              for (final f in p.fuels) AvailabilityChip(f.availability, at: f.confirmedAt, label: '${f.label} · ${f.shown.label}')
            else
              for (final pr in p.products.take(4))
                AvailabilityChip(pr.availability, at: pr.confirmedAt, label: '${pr.sizeLabel} · ${fcfa(pr.finalPrice)}${pr.onPromo ? ' 🏷' : ''}'),
            if (p.isStation && p.fuels.isEmpty) const AvailabilityChip(Availability.unknown),
            if (!p.isStation && p.products.isEmpty) const AvailabilityChip(Availability.unknown),
            if (p.delivers)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.delivery_dining_rounded, size: 14, color: AppColors.info),
                  SizedBox(width: 4),
                  Text('Livraison', style: TextStyle(color: AppColors.info, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _PlacesMap extends StatelessWidget {
  const _PlacesMap({super.key, required this.places, required this.me});
  final List<Place> places;
  final LatLng? me;

  @override
  Widget build(BuildContext context) {
    final pts = [?me, ...places.take(30).map((p) => p.position)];
    return FlutterMap(
      options: fitOptions(pts, zoom: 14),
      children: [
        osmTileLayer(),
        MarkerLayer(markers: [
          if (me != null) Marker(point: me!, width: 22, height: 22, child: Container(
            decoration: BoxDecoration(color: AppColors.info, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)]),
          )),
          for (final p in places)
            Marker(
              point: p.position,
              width: 44,
              height: 52,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                onTap: () => context.push('/client/gas/place/${p.id}', extra: p),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: p.summary == Availability.unknown ? (p.isStation ? AppColors.info : AppColors.accent) : p.summary.color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)]),
                    child: Icon(p.isStation ? Icons.directions_car : Icons.inventory_2, color: Colors.white, size: 20),
                  ),
                  Icon(Icons.arrow_drop_down, color: p.summary.color, size: 18),
                ]),
              ),
            ),
        ]),
        osmAttribution(),
      ],
    );
  }
}

/// Ville, quartier et rayon de recherche.
class _ZoneBar extends ConsumerWidget {
  const _ZoneBar({required this.onPickCity, required this.onClearArea});
  final VoidCallback onPickCity;
  final VoidCallback onClearArea;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(gasFiltersProvider);
    final radius = ref.watch(searchRadiusProvider);
    final cities = ref.watch(citiesProvider).value ?? const <City>[];
    final city = cities.where((c) => c.id == f.cityId).firstOrNull;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: Icon(city == null ? Icons.my_location : Icons.location_city, size: 18),
              label: Text(city?.name ?? 'Ma position'),
              onPressed: onPickCity,
            ),
          ),
          if (f.area != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InputChip(
                avatar: const Icon(Icons.place_outlined, size: 18),
                label: Text(f.areaLabel ?? 'Quartier'),
                onDeleted: onClearArea,
              ),
            ),
          for (final r in const [1.0, 3.0, 5.0, 10.0, 25.0, 50.0])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text('${r.toInt()} km'),
                selected: (radius - r).abs() < 0.01,
                onSelected: (_) => ref.read(gasFiltersProvider.notifier).set(f.copyWith(radiusKm: r)),
              ),
            ),
        ],
      ),
    );
  }
}
