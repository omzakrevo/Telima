import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/utils/geo.dart';
import '../data/models/config_models.dart';
import '../data/models/gas.dart';
import '../data/repositories/gas_repository.dart';
import 'auth_providers.dart';
import 'core_providers.dart';

final gasRepositoryProvider = Provider((ref) => GasRepository(ref.watch(supabaseProvider), ref.watch(cacheProvider)));

/// Position de la personne ; à défaut (GPS refusé), le centre de sa ville.
final myPositionProvider = FutureProvider<LatLng>((ref) async {
  try {
    return await ref.read(locationServiceProvider).current();
  } catch (_) {
    final user = ref.read(currentUserProvider);
    final cities = await ref.read(citiesProvider.future).catchError((_) => <City>[]);
    for (final c in cities) {
      if (c.id == user?.cityId) return c.center;
    }
    return cities.isNotEmpty ? cities.first.center : defaultCenter;
  }
});

class GasFilters {
  const GasFilters({
    this.stations = false,
    this.brandId,
    this.size,
    this.onlyAvailable = false,
    this.delivers = false,
    this.query = '',
    this.cityId,
    this.radiusKm,
    this.area,
    this.areaLabel,
  });
  final bool stations;
  final String? brandId;
  final double? size;
  final bool onlyAvailable;
  final bool delivers;
  final String query;
  final String? cityId; // null = autour de ma position
  final double? radiusKm; // null = rayon par défaut
  final LatLng? area; // quartier choisi (centre de la recherche)
  final String? areaLabel;

  bool get customCenter => cityId != null || area != null;

  GasFilters copyWith({
    bool? stations,
    String? brandId,
    double? size,
    bool? onlyAvailable,
    bool? delivers,
    String? query,
    String? cityId,
    double? radiusKm,
    LatLng? area,
    String? areaLabel,
    bool clearBrand = false,
    bool clearSize = false,
    bool clearCity = false,
    bool clearArea = false,
    bool clearRadius = false,
  }) =>
      GasFilters(
        stations: stations ?? this.stations,
        brandId: clearBrand ? null : (brandId ?? this.brandId),
        size: clearSize ? null : (size ?? this.size),
        onlyAvailable: onlyAvailable ?? this.onlyAvailable,
        delivers: delivers ?? this.delivers,
        query: query ?? this.query,
        cityId: clearCity ? null : (cityId ?? this.cityId),
        radiusKm: clearRadius ? null : (radiusKm ?? this.radiusKm),
        area: clearArea ? null : (area ?? this.area),
        areaLabel: clearArea ? null : (areaLabel ?? this.areaLabel),
      );
}

class GasFiltersNotifier extends Notifier<GasFilters> {
  @override
  GasFilters build() => const GasFilters();
  void set(GasFilters f) => state = f;
}

final gasFiltersProvider = NotifierProvider<GasFiltersNotifier, GasFilters>(GasFiltersNotifier.new);

final gasBrandsProvider = FutureProvider<List<GasBrand>>((ref) => ref.watch(gasRepositoryProvider).brands());

/// Centre de la recherche : quartier choisi, sinon centre de la ville choisie, sinon ma position.
final searchCenterProvider = FutureProvider<LatLng>((ref) async {
  final f = ref.watch(gasFiltersProvider);
  if (f.area != null) return f.area!;
  if (f.cityId != null) {
    final cities = await ref.watch(citiesProvider.future);
    for (final c in cities) {
      if (c.id == f.cityId) return c.center;
    }
  }
  return ref.watch(myPositionProvider.future);
});

/// Rayon réellement utilisé (choix de la personne, sinon rayon de la ville, sinon 3 km pour un quartier, sinon 15 km).
final searchRadiusProvider = Provider<double>((ref) {
  final f = ref.watch(gasFiltersProvider);
  if (f.radiusKm != null) return f.radiusKm!;
  if (f.area != null) return 3;
  if (f.cityId != null) {
    final cities = ref.watch(citiesProvider).value ?? const <City>[];
    for (final c in cities) {
      if (c.id == f.cityId && c.radiusKm > 0) return c.radiusKm;
    }
    return 20;
  }
  return 15;
});

final nearbyPlacesProvider = FutureProvider<List<Place>>((ref) async {
  final center = await ref.watch(searchCenterProvider.future);
  final f = ref.watch(gasFiltersProvider);
  final radius = ref.watch(searchRadiusProvider);
  final repo = ref.watch(gasRepositoryProvider);
  Future<List<Place>> run(double maxKm) => repo.search(
        lat: center.latitude,
        lng: center.longitude,
        stations: f.stations,
        brandId: f.stations ? null : f.brandId,
        size: f.stations ? null : f.size,
        onlyAvailable: f.onlyAvailable && !f.stations,
        delivers: f.delivers && !f.stations,
        query: f.query,
        maxKm: maxKm,
        useCache: !f.customCenter,
      );
  final near = await run(radius);
  // Autour de ma position et rien dans le rayon par défaut : on élargit pour ne jamais afficher un écran vide.
  return near.isNotEmpty || f.customCenter || f.radiusKm != null || f.query.isNotEmpty ? near : run(150);
});

final favoritePlaceIdsProvider = FutureProvider<Set<String>>((ref) => ref.watch(gasRepositoryProvider).favoriteIds());
final myGasOrdersProvider = FutureProvider<List<GasOrder>>((ref) => ref.watch(gasRepositoryProvider).myOrders());
final gasOrderProvider = FutureProvider.family<GasOrder, String>((ref, id) => ref.watch(gasRepositoryProvider).order(id));
final myPlacesProvider = FutureProvider<List<Place>>((ref) => ref.watch(gasRepositoryProvider).myPlaces());
final placeOrdersProvider = FutureProvider.family<List<GasOrder>, String>((ref, id) => ref.watch(gasRepositoryProvider).placeOrders(id));
final vendorDashboardProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) => ref.watch(gasRepositoryProvider).dashboard(id));
final placeProvider = FutureProvider.family<Place?, String>((ref, id) => ref.watch(gasRepositoryProvider).placeById(id));

final placeReviewsProvider = FutureProvider.autoDispose.family<List<PlaceReview>, String>((ref, id) => ref.watch(gasRepositoryProvider).reviews(id));
final favoritePlacesProvider = FutureProvider.autoDispose<List<Place>>((ref) async {
  final pos = await ref.watch(myPositionProvider.future);
  return ref.watch(gasRepositoryProvider).favorites(pos.latitude, pos.longitude);
});
final placePromosProvider = FutureProvider.autoDispose.family<List<PlacePromo>, String>((ref, id) => ref.watch(gasRepositoryProvider).promotions(id));
final vendorPlansProvider = FutureProvider.autoDispose<List<VendorPlan>>((ref) => ref.watch(gasRepositoryProvider).plans());
final placeSubscriptionsProvider =
    FutureProvider.autoDispose.family<List<VendorSubscription>, String>((ref, id) => ref.watch(gasRepositoryProvider).subscriptions(id));
