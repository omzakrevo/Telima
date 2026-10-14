import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/travel.dart';
import '../data/repositories/travel_repository.dart';
import 'core_providers.dart';

export 'restaurant_providers.dart' show pendingRouteProvider;

final travelRepositoryProvider =
    Provider((ref) => TravelRepository(ref.watch(supabaseProvider), ref.watch(storageServiceProvider)));

/// Critères de recherche d'un voyage.
typedef TripQuery = ({String from, String to, DateTime? date, String? companyId, int? hourFrom, int? hourTo});

/// Aucun critère : la page n'affiche pas encore d'horaires.
const TripQuery emptyTripQuery = (from: '', to: '', date: null, companyId: null, hourFrom: null, hourTo: null);

final tripSearchProvider = FutureProvider.autoDispose.family<List<TravelTrip>, TripQuery>((ref, q) =>
    ref.watch(travelRepositoryProvider).search(
        from: q.from, to: q.to, date: q.date, companyId: q.companyId, hourFrom: q.hourFrom, hourTo: q.hourTo));

/// Compagnies visibles par tous (bandeau et filtre de la page Voyages).
final travelCompaniesProvider =
    FutureProvider.autoDispose<List<TransportCompany>>((ref) => ref.watch(travelRepositoryProvider).publicCompanies());

final travelCitiesProvider = FutureProvider.autoDispose<List<String>>((ref) => ref.watch(travelRepositoryProvider).cities());

final travelTripProvider =
    FutureProvider.autoDispose.family<TravelTrip?, String>((ref, id) => ref.watch(travelRepositoryProvider).trip(id));

/// Page publique d'une compagnie (lien partagé) : lisible sans compte.
final companyBySlugProvider =
    FutureProvider.autoDispose.family<TransportCompany?, String>((ref, slug) => ref.watch(travelRepositoryProvider).companyBySlug(slug));

final myTravelBookingsProvider =
    FutureProvider.autoDispose<List<TravelBooking>>((ref) => ref.watch(travelRepositoryProvider).myBookings());
final travelBookingProvider =
    FutureProvider.autoDispose.family<TravelBooking, String>((ref, id) => ref.watch(travelRepositoryProvider).booking(id));

final myCompaniesProvider =
    FutureProvider.autoDispose<List<TransportCompany>>((ref) => ref.watch(travelRepositoryProvider).myCompanies());
final companyProvider =
    FutureProvider.autoDispose.family<TransportCompany?, String>((ref, id) => ref.watch(travelRepositoryProvider).company(id));
final companyTripsProvider =
    FutureProvider.autoDispose.family<List<TravelTrip>, String>((ref, id) => ref.watch(travelRepositoryProvider).companyTrips(id));
final companyBookingsProvider =
    FutureProvider.autoDispose.family<List<TravelBooking>, String>((ref, id) => ref.watch(travelRepositoryProvider).companyBookings(id));
final companyDashboardProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) => ref.watch(travelRepositoryProvider).dashboard(id));

final adminCompaniesProvider =
    FutureProvider.autoDispose<List<TransportCompany>>((ref) => ref.watch(travelRepositoryProvider).adminCompanies());
