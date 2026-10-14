import 'package:flutter_test/flutter_test.dart';
import 'package:telima/data/models/travel.dart';
import 'package:telima/screens/travel/travel_widgets.dart';

Map<String, dynamic> _trip({Duration in_ = const Duration(days: 1), int seats = 30, bool delivers = true, String status = 'scheduled'}) => {
      'id': 't1',
      'company_id': 'c1',
      'company_name': 'TSR',
      'company_slug': 'tsr',
      'delivers_tickets': delivers,
      'accepting_bookings': true,
      'from_city': 'Ouagadougou',
      'to_city': 'Bobo-Dioulasso',
      'departure_at': DateTime.now().add(in_).toUtc().toIso8601String(),
      'duration_minutes': 330,
      'bus_class': 'VIP',
      'price': 7500,
      'seats_total': 50,
      'seats_available': seats,
      'station_lat': 12.36,
      'station_lng': -1.52,
      'status': status,
    };

Map<String, dynamic> _booking({String status = 'pending', String mode = 'eticket', String? deliveryId, Duration in_ = const Duration(days: 1)}) => {
      'id': 'b1',
      'code': 'VOY-2026-000012',
      'qr_token': 'abc123',
      'trip_id': 't1',
      'company_id': 'c1',
      'customer_id': 'u1',
      'status': status,
      'passengers': 2,
      'passenger_names': ['Awa', 'Ali'],
      'customer_name': 'Awa',
      'customer_phone': '+22670000000',
      'ticket_mode': mode,
      'unit_price': 7500,
      'tickets_total': 15000,
      'delivery_fee': mode == 'delivery' ? 2000 : 0,
      'total': mode == 'delivery' ? 17000 : 15000,
      'payment_status': 'unpaid',
      'delivery_id': deliveryId,
      'travel_trips': _trip(in_: in_),
      'transport_companies': {'name': 'TSR', 'phone': '+22625000000', 'slug': 'tsr'},
    };

void main() {
  test('liens et QR code', () {
    expect(companyShareLink('tsr'), 'https://telimatchi.com/v/tsr');
    expect(TravelBooking(_booking()).qrData, 'TELIMA-VOY:VOY-2026-000012:abc123');
  });

  test('un départ est lu depuis la réponse du serveur', () {
    final t = TravelTrip(_trip());
    expect(t.route, 'Ouagadougou → Bobo-Dioulasso');
    expect(t.arrivalAt!.difference(t.departureAt).inMinutes, 330);
    expect(t.bookable, isTrue);
    expect(t.canDeliverTicket, isTrue);
    expect(t.seatsSold, 20);
    expect(travelDuration(330), '5 h 30');
    expect(travelDuration(45), '45 min');
    expect(travelDuration(120), '2 h');
  });

  test('statut d\'une compagnie : en attente, suspendue, refusée', () {
    TransportCompany c(String status) => TransportCompany({
          'id': 'c1', 'slug': 'x', 'name': 'X', 'lat': 12.0, 'lng': -1.0, 'status': status, 'trips': const [],
        });
    expect(c('pending').pendingApproval, isTrue);
    expect(c('pending').suspended, isFalse);
    expect(c('suspended').suspended, isTrue);
    expect(c('rejected').suspended, isTrue);
    expect(c('approved').pendingApproval, isFalse);
    expect(c('approved').suspended, isFalse);
  });

  test('frais de réservation Telima : à payer, en vérification, payés, refusés', () {
    TravelBooking b(String fee, {String status = 'pending'}) =>
        TravelBooking({..._booking(status: status), 'service_fee': 500, 'service_fee_status': fee});
    expect(b('unpaid').feeDue, isTrue);
    expect(b('failed').feeDue, isTrue);
    expect(b('verifying').feeDue, isFalse);
    expect(b('paid').feeDue, isFalse);
    expect(b('paid').feePaid, isTrue);
    expect(b('unpaid', status: 'cancelled').feeDue, isFalse);
    expect(TravelBooking(_booking()).serviceFee, 0);
    expect(TravelBooking(_booking()).feeDue, isFalse);
    expect(b('verifying').feeLabel, 'Frais de réservation en cours de vérification');

    // Réservation payée en ligne : un seul paiement (billets + frais), remboursement suivi
    TravelBooking online(String fee, {String refund = 'none'}) => TravelBooking({
          ..._booking(status: 'pending'),
          'prepaid': true,
          'service_fee': 500,
          'service_fee_status': fee,
          'refund_status': refund,
          'refund_amount': 7500,
        });
    expect(online('unpaid').onlineAmount, online('unpaid').ticketsTotal + 500);
    expect(online('unpaid').feeLabel, 'Paiement à faire');
    expect(online('paid').feePaid, isTrue);
    expect(online('paid', refund: 'due').refundDue, isTrue);
    expect(online('paid', refund: 'done').refundDone, isTrue);
    expect(TravelBooking(_booking()).prepaid, isFalse);
    expect(TravelBooking(_booking()).onlineAmount, 0);
    expect(travelServiceFee, 500);
  });

  test('départ complet, annulé, ou trop proche', () {
    expect(TravelTrip(_trip(seats: 0)).bookable, isFalse);
    expect(TravelTrip(_trip(status: 'cancelled')).bookable, isFalse);
    expect(TravelTrip(_trip(in_: const Duration(minutes: 10))).bookable, isFalse);
    // livraison du ticket impossible à moins de 3 h du départ (même règle que le serveur)
    expect(TravelTrip(_trip(in_: const Duration(hours: 2))).canDeliverTicket, isFalse);
    expect(TravelTrip(_trip(delivers: false)).canDeliverTicket, isFalse);
  });

  test('étapes et e-ticket selon le mode', () {
    final e = TravelBooking(_booking());
    expect(e.steps.map((s) => s.$1), ['pending', 'confirmed', 'boarded']);
    expect(e.hasETicket, isFalse);
    expect(e.paymentHint, contains('au guichet'));
    final d = TravelBooking(_booking(status: 'confirmed', mode: 'delivery', deliveryId: 'd1'));
    expect(d.steps.map((s) => s.$1), ['pending', 'confirmed', 'out_for_delivery', 'delivered', 'boarded']);
    expect(d.hasETicket, isTrue);
    expect(d.paymentHint, contains('au livreur'));
    expect(d.statusLabel, 'Confirmée · ticket en préparation');
  });

  test('annulation par le client : en attente, ou e-ticket confirmé à plus de 2 h du départ', () {
    expect(TravelBooking(_booking()).customerCanCancel, isTrue);
    expect(TravelBooking(_booking(status: 'confirmed')).customerCanCancel, isTrue);
    expect(TravelBooking(_booking(status: 'confirmed', in_: const Duration(hours: 1))).customerCanCancel, isFalse);
    expect(TravelBooking(_booking(status: 'confirmed', mode: 'delivery', deliveryId: 'd1')).customerCanCancel, isFalse);
    expect(TravelBooking(_booking(status: 'boarded')).customerCanCancel, isFalse);
  });
}
