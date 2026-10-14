import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/storage_service.dart';
import '../models/json.dart';
import '../models/travel.dart';
import '../models/wallet.dart';

/// Module « Voyages » : recherche de départs, réservation de tickets, espace compagnie, administration.
class TravelRepository {
  TravelRepository(this._client, this._storage);
  final SupabaseClient _client;
  final StorageService _storage;

  static const _bookingSelect = '*, travel_trips(*), transport_companies(name, phone, slug, logo_path)';

  // ----- Lecture publique (sans compte) -----

  /// [hourFrom] inclus, [hourTo] exclu : tranche horaire de départ (heure du Burkina).
  Future<List<TravelTrip>> search({String? from, String? to, DateTime? date, String? companyId, int? hourFrom, int? hourTo}) async {
    String? clean(String? s) => (s ?? '').trim().isEmpty ? null : s!.trim();
    final rows = await _client.rpc('search_travel_trips', params: {
      'p_from': clean(from),
      'p_to': clean(to),
      'p_date': date == null ? null : _day(date),
      'p_limit': 150,
      'p_company': companyId,
      'p_hour_from': hourFrom,
      'p_hour_to': hourTo,
    });
    return [for (final r in (rows as List)) TravelTrip(Map<String, dynamic>.from(r as Map))];
  }

  /// Compagnies approuvées (sans leurs départs).
  Future<List<TransportCompany>> publicCompanies() async => [
        for (final r in (await _client.rpc('travel_companies') as List)) TransportCompany(Map<String, dynamic>.from(r as Map))
      ];

  Future<List<String>> cities() async => [for (final c in (await _client.rpc('travel_cities') as List)) '$c'];

  Future<TravelTrip?> trip(String id) async {
    final res = await _client.rpc('travel_trip', params: {'p_trip_id': id});
    return res == null ? null : TravelTrip(Map<String, dynamic>.from(res as Map));
  }

  /// Page publique d'une compagnie (lien `/v/<slug>`) ; null si le lien n'existe pas ou si la compagnie est suspendue.
  Future<TransportCompany?> companyBySlug(String slug) async {
    final res = await _client.rpc('transport_company_by_slug', params: {'p_slug': slug});
    return res == null ? null : TransportCompany(Map<String, dynamic>.from(res as Map));
  }

  // ----- Voyageur -----

  Future<({int fee, double km})> ticketDeliveryFee(String tripId, double lat, double lng) async {
    final r = Map<String, dynamic>.from(await _client.rpc('travel_ticket_delivery_fee',
        params: {'p_trip_id': tripId, 'p_lat': lat, 'p_lng': lng}) as Map);
    return (fee: asInt(r['fee']), km: asDouble(r['distance_km']) ?? 0);
  }

  /// Réserve [passengers] places ; le prix est relu par le serveur.
  Future<TravelBooking> book({
    required String tripId,
    required int passengers,
    List<String> passengerNames = const [],
    required String ticketMode,
    String? note,
    Map<String, dynamic>? dropoff,
    String feeMethod = 'orange_money',
  }) async {
    final row = await _client.rpc('create_travel_booking', params: {
      'p': {
        'trip_id': tripId,
        'passengers': passengers,
        'passenger_names': [for (final n in passengerNames) if (n.trim().isNotEmpty) n.trim()],
        'ticket_mode': ticketMode,
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'dropoff': dropoff,
        'fee_method': feeMethod,
      },
    });
    return TravelBooking(Map<String, dynamic>.from(row as Map));
  }

  /// Paiement Mobile Money des frais de réservation (500 F), à faire régler par le voyageur.
  Future<Payment?> feePayment(String? paymentId) async {
    if (paymentId == null) return null;
    final row = await _client.from('payments').select().eq('id', paymentId).maybeSingle();
    return row == null ? null : Payment(Map<String, dynamic>.from(row));
  }

  /// Nouvel essai (ou changement d'opérateur) pour payer les frais d'une réservation.
  Future<Payment> retryFee(String bookingId, {String? method}) async => Payment(Map<String, dynamic>.from(
      await _client.rpc('retry_travel_fee', params: {'p_booking_id': bookingId, 'p_method': method}) as Map));

  Future<TravelBooking> booking(String id) async =>
      TravelBooking(await _client.from('travel_bookings').select(_bookingSelect).eq('id', id).single());

  Future<List<TravelBooking>> myBookings() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from('travel_bookings')
        .select(_bookingSelect)
        .eq('customer_id', uid)
        .order('created_at', ascending: false)
        .limit(60);
    return [for (final r in rows) TravelBooking(r)];
  }

  Future<void> cancelBooking(String id) => _client.rpc('cancel_travel_booking', params: {'p_booking_id': id});

  // ----- Compagnie -----

  Future<List<TransportCompany>> myCompanies() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client.from('transport_companies').select().eq('owner_id', uid).order('created_at');
    return [for (final r in rows) TransportCompany(r)];
  }

  Future<TransportCompany?> company(String id) async {
    final row = await _client.from('transport_companies').select().eq('id', id).maybeSingle();
    return row == null ? null : TransportCompany(row);
  }

  /// [asAdmin] : compagnie saisie par l'équipe Telima, sans propriétaire.
  Future<TransportCompany> createCompany(Map<String, dynamic> data, {bool asAdmin = false}) async => TransportCompany(
      Map<String, dynamic>.from(await _client.rpc(asAdmin ? 'admin_create_transport_company' : 'register_transport_company',
          params: {'p': data}) as Map));

  Future<void> updateCompany(String id, Map<String, dynamic> data) => _client.from('transport_companies').update(data).eq('id', id);

  Future<void> setAcceptingBookings(String id, bool value) => updateCompany(id, {'accepting_bookings': value});

  Future<String?> pickAndUploadLogo() async {
    final XFile? file = await _storage.pickImage(maxWidth: 512);
    if (file == null) return null;
    return _storage.uploadXFile('voyages', file);
  }

  /// Départs de la compagnie (à venir d'abord, puis les 30 derniers jours).
  Future<List<TravelTrip>> companyTrips(String companyId) async {
    final rows = await _client
        .from('travel_trips')
        .select()
        .eq('company_id', companyId)
        .gte('departure_at', DateTime.now().subtract(const Duration(days: 30)).toUtc().toIso8601String())
        .order('departure_at')
        .limit(200);
    return [for (final r in rows) TravelTrip(r)];
  }

  Future<void> saveTrip({
    String? id,
    required String companyId,
    required String fromCity,
    required String toCity,
    required DateTime departureAt,
    int? durationMinutes,
    String? busClass,
    required int price,
    required int seatsTotal,
    String? departureStation,
    String? notes,
  }) async {
    final row = {
      'from_city': fromCity.trim(),
      'to_city': toCity.trim(),
      'departure_at': departureAt.toUtc().toIso8601String(),
      'duration_minutes': durationMinutes,
      'bus_class': (busClass ?? '').trim().isEmpty ? null : busClass!.trim(),
      'price': price,
      'seats_total': seatsTotal,
      'departure_station': (departureStation ?? '').trim().isEmpty ? null : departureStation!.trim(),
      'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
    };
    if (id == null) {
      // seats_available est recalculé par le serveur (= seats_total à la création)
      await _client.from('travel_trips').insert({...row, 'company_id': companyId, 'seats_available': seatsTotal});
    } else {
      await _client.from('travel_trips').update(row).eq('id', id);
    }
  }

  Future<void> cancelTrip(String id, {String? reason}) =>
      _client.rpc('travel_trip_cancel', params: {'p_trip_id': id, 'p_reason': reason});

  Future<void> deleteTrip(String id) => _client.from('travel_trips').delete().eq('id', id);

  Future<List<TravelBooking>> companyBookings(String companyId) async {
    final rows = await _client
        .from('travel_bookings')
        .select(_bookingSelect)
        .eq('company_id', companyId)
        .order('created_at', ascending: false)
        .limit(150);
    return [for (final r in rows) TravelBooking(r)];
  }

  /// [action] : confirm | reject | board | paid. [data] : {seat_numbers, ticket_number, message} ou {reason}.
  Future<void> bookingAction(String id, String action, [Map<String, dynamic>? data]) =>
      _client.rpc('travel_booking_action', params: {'p_booking_id': id, 'p_action': action, 'p': data ?? {}});

  /// Contrôle d'un ticket : contenu du QR code ou code VOY-… saisi.
  Future<TicketCheck> checkTicket(String companyId, String value) async => TicketCheck(Map<String, dynamic>.from(
      await _client.rpc('check_travel_ticket', params: {'p_company_id': companyId, 'p_value': value.trim()}) as Map));

  Future<Json> dashboard(String companyId) async =>
      Map<String, dynamic>.from(await _client.rpc('transport_company_dashboard', params: {'p_company_id': companyId}) as Map);

  // ----- Administration -----

  Future<List<TransportCompany>> adminCompanies() async {
    final rows = await _client.from('transport_companies').select().order('created_at', ascending: false).limit(200);
    return [for (final r in rows) TransportCompany(r)];
  }

  Future<void> adminSetStatus(String id, String status) =>
      _client.rpc('admin_set_transport_company_status', params: {'p_company_id': id, 'p_status': status});

  /// Confie la compagnie au compte de ce numéro ; numéro vide = l'équipe Telima la reprend.
  Future<void> adminSetOwner(String id, String? phone) =>
      _client.rpc('admin_set_company_owner', params: {'p_company_id': id, 'p_phone': phone});
}

String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
