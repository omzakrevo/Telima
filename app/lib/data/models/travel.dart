import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../config/env.dart';
import '../../config/theme.dart';
import '../../core/services/storage_service.dart';
import '../../core/utils/formatters.dart';
import 'json.dart';
import 'restaurant.dart' show kSiteUrl;

/// Adresse publique d'un logo du compartiment « voyages » (lisible sans compte).
String? travelPhotoUrl(String? path) {
  if (path == null || path.isEmpty) return null;
  return '${Env.supabaseUrl}/storage/v1/object/public/${StorageService.bucket('voyages')}/$path';
}

/// Lien public d'une compagnie (ses prochains départs). Même principe que /r/ et /b/ : ouvre l'app Android ou le site.
String companyShareLink(String slug) => '$kSiteUrl/v/$slug';

/// Contenu du QR code d'un e-ticket : `TELIMA-VOY:<code>:<secret>`. Le secret empêche de fabriquer un faux ticket
/// à partir du seul code ; la compagnie peut aussi saisir le code à la main.
String eticketQrData(String code, String token) => 'TELIMA-VOY:$code:$token';

/// Frais de réservation Telima (FCFA par réservation) : même valeur que `telima.travel_service_fee()` côté serveur.
const int travelServiceFee = 500;

class TransportCompany {
  TransportCompany(Json j)
      : id = '${j['id']}',
        slug = '${j['slug']}',
        name = '${j['name']}',
        description = asStr(j['description']),
        phone = asStr(j['phone']),
        city = asStr(j['city']),
        stationAddress = asStr(j['station_address']),
        position = LatLng(asDouble(j['lat']) ?? 0, asDouble(j['lng']) ?? 0),
        logoPath = asStr(j['logo_path']),
        acceptingBookings = asBool(j['accepting_bookings'], true),
        deliversTickets = asBool(j['delivers_tickets'], true),
        deliveryRadiusKm = asDouble(j['ticket_delivery_radius_km']) ?? 20,
        status = asStr(j['status']) ?? 'approved',
        ownerId = asStr(j['owner_id']),
        trips = [for (final t in (j['trips'] as List? ?? const [])) TravelTrip(Map<String, dynamic>.from(t as Map))];

  final String id;
  final String slug;
  final String name;
  final String? description;
  final String? phone;
  final String? city;
  final String? stationAddress;
  final LatLng position;
  final String? logoPath;
  final bool acceptingBookings;
  final bool deliversTickets;
  final double deliveryRadiusKm;
  final String status;
  final String? ownerId;
  final List<TravelTrip> trips;

  String? get logoUrl => travelPhotoUrl(logoPath);
  /// Suspendue ou refusée par l'équipe Telima : lien et départs invisibles.
  bool get suspended => status == 'suspended' || status == 'rejected';
  /// Inscrite par la compagnie, pas encore validée par l'équipe Telima.
  bool get pendingApproval => status == 'pending';
  /// Compagnie saisie et gérée par l'équipe Telima (pas encore de compte propriétaire).
  bool get managedByTelima => ownerId == null;
  String get subtitle => [if ((city ?? '').isNotEmpty) city!, if ((stationAddress ?? '').isNotEmpty) stationAddress!].join(' · ');
}

class TravelTrip {
  TravelTrip(Json j)
      : id = '${j['id']}',
        companyId = '${j['company_id']}',
        companyName = asStr(j['company_name']),
        companySlug = asStr(j['company_slug']),
        companyLogo = asStr(j['company_logo']),
        companyPhone = asStr(j['company_phone']),
        deliversTickets = asBool(j['delivers_tickets'], false),
        acceptingBookings = asBool(j['accepting_bookings'], true),
        fromCity = '${j['from_city']}',
        toCity = '${j['to_city']}',
        departureAt = asDate(j['departure_at']) ?? DateTime.now(),
        durationMinutes = j['duration_minutes'] == null ? null : asInt(j['duration_minutes']),
        busClass = asStr(j['bus_class']),
        price = asInt(j['price']),
        seatsTotal = asInt(j['seats_total']),
        seatsAvailable = asInt(j['seats_available']),
        departureStation = asStr(j['departure_station']),
        stationPosition = j['station_lat'] == null ? null : LatLng(asDouble(j['station_lat'])!, asDouble(j['station_lng']) ?? 0),
        notes = asStr(j['notes']),
        status = asStr(j['status']) ?? 'scheduled',
        cancelReason = asStr(j['cancel_reason']);

  final String id;
  final String companyId;
  final String? companyName;
  final String? companySlug;
  final String? companyLogo;
  final String? companyPhone;
  final bool deliversTickets;
  final bool acceptingBookings;
  final String fromCity;
  final String toCity;
  final DateTime departureAt;
  final int? durationMinutes;
  final String? busClass;
  final int price;
  final int seatsTotal;
  final int seatsAvailable;
  final String? departureStation;
  final LatLng? stationPosition;
  final String? notes;
  final String status;
  final String? cancelReason;

  String get route => '$fromCity → $toCity';
  bool get cancelled => status == 'cancelled';
  bool get departed => departureAt.isBefore(DateTime.now());
  bool get full => seatsAvailable <= 0;
  int get seatsSold => seatsTotal - seatsAvailable;
  /// Le ticket papier ne peut être livré que si le départ est dans plus de 3 heures (même règle que le serveur).
  bool get canDeliverTicket => deliversTickets && departureAt.isAfter(DateTime.now().add(const Duration(hours: 3)));
  bool get bookable => !cancelled && !full && acceptingBookings && departureAt.isAfter(DateTime.now().add(const Duration(minutes: 15)));
  DateTime? get arrivalAt => durationMinutes == null ? null : departureAt.add(Duration(minutes: durationMinutes!));
}

class TravelBooking {
  TravelBooking(Json j)
      : id = '${j['id']}',
        code = '${j['code']}',
        qrToken = '${j['qr_token']}',
        tripId = '${j['trip_id']}',
        companyId = '${j['company_id']}',
        customerId = asStr(j['customer_id']),
        status = asStr(j['status']) ?? 'pending',
        passengers = asInt(j['passengers'], 1),
        passengerNames = [for (final n in (j['passenger_names'] as List? ?? const [])) '$n'],
        customerName = '${j['customer_name'] ?? ''}',
        customerPhone = '${j['customer_phone'] ?? ''}',
        note = asStr(j['note']),
        ticketMode = asStr(j['ticket_mode']) ?? 'eticket',
        dropoffAddress = asStr(j['dropoff_address']),
        unitPrice = asInt(j['unit_price']),
        ticketsTotal = asInt(j['tickets_total']),
        deliveryFee = asInt(j['delivery_fee']),
        total = asInt(j['total']),
        serviceFee = asInt(j['service_fee']),
        serviceFeeStatus = asStr(j['service_fee_status']) ?? 'none',
        feePaymentId = asStr(j['fee_payment_id']),
        prepaid = asBool(j['prepaid']),
        refundStatus = asStr(j['refund_status']) ?? 'none',
        refundAmount = asInt(j['refund_amount']),
        paymentStatus = asStr(j['payment_status']) ?? 'unpaid',
        seatNumbers = asStr(j['seat_numbers']),
        ticketNumber = asStr(j['ticket_number']),
        companyMessage = asStr(j['company_message']),
        rejectReason = asStr(j['reject_reason']),
        deliveryId = asStr(j['delivery_id']),
        createdAt = asDate(j['created_at']),
        confirmedAt = asDate(j['confirmed_at']),
        boardedAt = asDate(j['boarded_at']),
        trip = j['travel_trips'] is Map ? TravelTrip(Map<String, dynamic>.from(j['travel_trips'] as Map)) : null,
        companyName = (j['transport_companies'] as Map?)?['name']?.toString(),
        companyPhone = (j['transport_companies'] as Map?)?['phone']?.toString(),
        companySlug = (j['transport_companies'] as Map?)?['slug']?.toString(),
        companyLogo = (j['transport_companies'] as Map?)?['logo_path']?.toString();

  final String id;
  final String code;
  final String qrToken;
  final String tripId;
  final String companyId;
  final String? customerId;
  final String status;
  final int passengers;
  final List<String> passengerNames;
  final String customerName;
  final String customerPhone;
  final String? note;
  final String ticketMode;
  final String? dropoffAddress;
  final int unitPrice;
  final int ticketsTotal;
  final int deliveryFee;
  final int total;
  /// Frais de réservation Telima, payés par Mobile Money (`none`, `unpaid`, `verifying`, `paid`, `failed`).
  final int serviceFee;
  final String serviceFeeStatus;
  final String? feePaymentId;

  /// Billets payés en ligne avec les frais (réservations récentes) ; sinon ancien fonctionnement : billets payés au guichet.
  final bool prepaid;

  /// Remboursement : `none`, `due` (à faire par l'équipe Telima), `done`.
  final String refundStatus;
  final int refundAmount;
  final String paymentStatus;
  final String? seatNumbers;
  final String? ticketNumber;
  final String? companyMessage;
  final String? rejectReason;
  final String? deliveryId;
  final DateTime? createdAt;
  final DateTime? confirmedAt;
  final DateTime? boardedAt;
  final TravelTrip? trip;
  final String? companyName;
  final String? companyPhone;
  final String? companySlug;
  final String? companyLogo;

  bool get isDelivery => ticketMode == 'delivery';
  bool get isOpen => const {'pending', 'confirmed', 'out_for_delivery', 'delivered'}.contains(status);
  bool get failed => status == 'rejected' || status == 'cancelled';
  /// L'e-ticket (QR code) est valable dès la confirmation, jusqu'à l'embarquement.
  bool get hasETicket => const {'confirmed', 'out_for_delivery', 'delivered', 'boarded'}.contains(status);
  String get qrData => eticketQrData(code, qrToken);
  bool get paid => paymentStatus == 'paid';

  /// Frais de réservation encore à payer (ou paiement refusé) : le voyageur doit payer pour que la compagnie confirme.
  bool get feeDue => serviceFee > 0 && (serviceFeeStatus == 'unpaid' || serviceFeeStatus == 'failed') && !failed;
  bool get feePaid => serviceFeeStatus == 'paid';

  /// Montant du paiement Mobile Money : billets + frais de réservation (ou les frais seuls pour une ancienne réservation).
  int get onlineAmount => prepaid ? ticketsTotal + serviceFee : serviceFee;
  bool get refundDue => refundStatus == 'due';
  bool get refundDone => refundStatus == 'done';
  String get feeLabel => prepaid
      ? switch (serviceFeeStatus) {
          'paid' => 'Paiement reçu',
          'verifying' => 'Paiement en cours de vérification',
          'failed' => 'Paiement refusé : à refaire',
          'unpaid' => 'Paiement à faire',
          _ => '',
        }
      : _feeOnlyLabel;

  String get _feeOnlyLabel => switch (serviceFeeStatus) {
        'paid' => 'Frais de réservation payés',
        'verifying' => 'Frais de réservation en cours de vérification',
        'failed' => 'Paiement des frais refusé : à refaire',
        'unpaid' => 'Frais de réservation à payer',
        _ => '',
      };

  /// Le client peut annuler tant que ce n'est pas confirmé, ou un e-ticket confirmé jusqu'à 2 h avant le départ.
  bool get customerCanCancel =>
      status == 'pending' ||
      (status == 'confirmed' && deliveryId == null && (trip?.departureAt.isAfter(DateTime.now().add(const Duration(hours: 2))) ?? false));

  String get statusLabel => switch (status) {
        'pending' => 'En attente de confirmation',
        'confirmed' => isDelivery ? 'Confirmée · ticket en préparation' : 'Confirmée · e-ticket prêt',
        'out_for_delivery' => 'Ticket en route',
        'delivered' => 'Ticket livré',
        'boarded' => 'Embarqué',
        'rejected' => 'Refusée',
        'cancelled' => 'Annulée',
        _ => status,
      };

  Color get statusColor => switch (status) {
        'pending' => AppColors.accent,
        'confirmed' || 'out_for_delivery' || 'delivered' => AppColors.primary,
        'boarded' => AppColors.info,
        _ => AppColors.danger,
      };

  /// Étapes affichées au client.
  List<(String, String)> get steps => [
        ('pending', 'Réservation envoyée'),
        ('confirmed', 'Confirmée par la compagnie'),
        if (isDelivery) ('out_for_delivery', 'Ticket en route'),
        if (isDelivery) ('delivered', 'Ticket livré'),
        ('boarded', 'Embarqué'),
      ];

  /// Message de paiement adapté au mode de ticket.
  String get paymentHint => prepaid
      ? '${paid ? 'Billets payés en ligne' : 'Billets à payer en ligne'}${isDelivery ? ' · ${fcfa(deliveryFee)} de livraison à payer au livreur' : ''}'
      : paid
      ? 'Payé'
      : isDelivery
          ? '${fcfa(total)} à payer en espèces au livreur (billets + livraison)'
          : '${fcfa(ticketsTotal)} à payer au guichet avant le départ';
}

/// Résultat du contrôle d'un ticket à l'embarquement.
class TicketCheck {
  TicketCheck(Json j)
      : valid = asBool(j['valid']),
        message = '${j['message'] ?? ''}',
        bookingId = asStr(j['booking_id']),
        code = asStr(j['code']),
        status = asStr(j['status']),
        customerName = asStr(j['customer_name']),
        customerPhone = asStr(j['customer_phone']),
        passengers = asInt(j['passengers']),
        passengerNames = [for (final n in (j['passenger_names'] as List? ?? const [])) '$n'],
        seatNumbers = asStr(j['seat_numbers']),
        ticketMode = asStr(j['ticket_mode']),
        paid = asStr(j['payment_status']) == 'paid',
        ticketsTotal = asInt(j['tickets_total']),
        trip = asStr(j['trip']);

  final bool valid;
  final String message;
  final String? bookingId;
  final String? code;
  final String? status;
  final String? customerName;
  final String? customerPhone;
  final int passengers;
  final List<String> passengerNames;
  final String? seatNumbers;
  final String? ticketMode;
  final bool paid;
  final int ticketsTotal;
  final String? trip;
}
