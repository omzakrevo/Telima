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
  const GasFilters({this.stations = false, this.brandId, this.size, this.onlyAvailable = false, this.delivers = false, this.query = ''});
  final bool stations;
  final String? brandId;
  final double? size;
  final bool onlyAvailable;
  final bool delivers;
  final String query;

  GasFilters copyWith({bool? stations, String? brandId, double? size, bool? onlyAvailable, bool? delivers, String? query,
          bool clearBrand = false, bool clearSize = false}) =>
      GasFilters(
        stations: stations ?? this.stations,
        brandId: clearBrand ? null : (brandId ?? this.brandId),
        size: clearSize ? null : (size ?? this.size),
        onlyAvailable: onlyAvailable ?? this.onlyAvailable,
        delivers: delivers ?? this.delivers,
        query: query ?? this.query,
      );
}

class GasFiltersNotifier extends Notifier<GasFilters> {
  @override
  GasFilters build() => const GasFilters();
  void set(GasFilters f) => state = f;
}

final gasFiltersProvider = NotifierProvider<GasFiltersNotifier, GasFilters>(GasFiltersNotifier.new);

final gasBrandsProvider = FutureProvider<List<GasBrand>>((ref) => ref.watch(gasRepositoryProvider).brands());

final nearbyPlacesProvider = FutureProvider<List<Place>>((ref) async {
  final pos = await ref.watch(myPositionProvider.future);
  final f = ref.watch(gasFiltersProvider);
  return ref.watch(gasRepositoryProvider).search(
        lat: pos.latitude,
        lng: pos.longitude,
        stations: f.stations,
        brandId: f.stations ? null : f.brandId,
        size: f.stations ? null : f.size,
        onlyAvailable: f.onlyAvailable && !f.stations,
        delivers: f.delivers && !f.stations,
        query: f.query,
      );
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
