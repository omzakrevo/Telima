// Écrans du module Voyages avec des données fictives : aucun débordement de mise en page, en mobile et en grand écran.
// Captures (pour vérification visuelle) : flutter test test/travel_screens_test.dart --update-goldens --dart-define=SHOTS_DIR=/chemin
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:telima/config/theme.dart';
import 'package:telima/data/models/enums.dart';
import 'package:telima/data/models/travel.dart';
import 'package:telima/data/models/user.dart';
import 'package:telima/providers/auth_providers.dart';
import 'package:telima/providers/data_providers.dart';
import 'package:telima/providers/travel_providers.dart';
import 'package:telima/screens/travel/travel_client_screens.dart';
import 'package:telima/screens/travel/travel_company_screens.dart';

const _shots = String.fromEnvironment('SHOTS_DIR');

Map<String, dynamic> _trip(String id, {int h = 30, int seats = 23, String to = 'Bobo-Dioulasso', String? cls = 'VIP'}) => {
      'id': id,
      'company_id': 'c1',
      'company_name': 'Voyages du Kadiogo',
      'company_slug': 'voyages-du-kadiogo',
      'delivers_tickets': true,
      'accepting_bookings': true,
      'from_city': 'Ouagadougou',
      'to_city': to,
      'departure_at': DateTime.now().add(Duration(hours: h)).toUtc().toIso8601String(),
      'duration_minutes': 330,
      'bus_class': cls,
      'price': 7500,
      'seats_total': 50,
      'seats_available': seats,
      'departure_station': 'Gare de Ouagadougou, avenue Kadiogo',
      'station_lat': 12.36,
      'station_lng': -1.52,
      'status': 'scheduled',
    };

final _company = TransportCompany({
  'id': 'c1',
  'slug': 'voyages-du-kadiogo',
  'name': 'Voyages du Kadiogo',
  'description': 'Lignes Ouaga – Bobo – Banfora, cars climatisés.',
  'phone': '+22625000000',
  'city': 'Ouagadougou',
  'station_address': 'Gare de Ouagadougou',
  'lat': 12.36,
  'lng': -1.52,
  'accepting_bookings': true,
  'delivers_tickets': true,
  'status': 'approved',
  'owner_id': 'u1',
  'trips': [_trip('t1'), _trip('t2', h: 54, seats: 0, to: 'Banfora', cls: null)],
});

TravelBooking _booking(String status, {String mode = 'eticket'}) => TravelBooking({
      'id': 'b-$status-$mode',
      'code': 'VOY-2026-000012',
      'qr_token': 'abc123def456',
      'trip_id': 't1',
      'company_id': 'c1',
      'customer_id': 'u1',
      'status': status,
      'passengers': 2,
      'passenger_names': ['Awa Ouédraogo', 'Ali Ouédraogo'],
      'customer_name': 'Awa Ouédraogo',
      'customer_phone': '+22670000000',
      'ticket_mode': mode,
      'dropoff_address': mode == 'delivery' ? 'Ouaga 2000, près du rond-point' : null,
      'unit_price': 7500,
      'tickets_total': 15000,
      'delivery_fee': mode == 'delivery' ? 2000 : 0,
      'total': mode == 'delivery' ? 17000 : 15000,
      'payment_status': 'unpaid',
      'seat_numbers': status == 'pending' ? null : '12, 13',
      'note': 'Une grosse valise',
      'created_at': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
      'travel_trips': _trip('t1'),
      'transport_companies': {'name': 'Voyages du Kadiogo', 'phone': '+22625000000', 'slug': 'voyages-du-kadiogo'},
    });

final _user = AppUser(id: 'u1', phone: '+22670000000', fullName: 'Awa Ouédraogo', role: UserRole.client, isActive: true);

List _overrides() => [
      currentUserProvider.overrideWithValue(_user),
      savedAddressesProvider.overrideWith((ref, _) async => const []),
      tripSearchProvider.overrideWith((ref, _) async => [TravelTrip(_trip('t1')), TravelTrip(_trip('t2', h: 54, seats: 3, to: 'Banfora', cls: null))]),
      travelCitiesProvider.overrideWith((ref) async => ['Banfora', 'Bobo-Dioulasso', 'Ouagadougou']),
      travelTripProvider.overrideWith((ref, _) async => TravelTrip(_trip('t1'))),
      companyBySlugProvider.overrideWith((ref, _) async => _company),
      companyProvider.overrideWith((ref, _) async => _company),
      companyTripsProvider.overrideWith((ref, _) async => [TravelTrip(_trip('t1')), TravelTrip(_trip('t2', h: 54, seats: 0, to: 'Banfora'))]),
      companyBookingsProvider.overrideWith((ref, _) async => [_booking('pending'), _booking('pending', mode: 'delivery'), _booking('confirmed')]),
      companyDashboardProvider.overrideWith((ref, _) async => {'pending': 2, 'today': 5, 'seats_sold_week': 37}),
      travelBookingProvider.overrideWith((ref, id) async => id == 'eticket' ? _booking('confirmed') : _booking('out_for_delivery', mode: 'delivery')),
      myTravelBookingsProvider.overrideWith((ref) async => [_booking('confirmed'), _booking('pending', mode: 'delivery')]),
    ];

Future<void> _loadFonts() async {
  final font = FontLoader('PlusJakartaSans');
  for (final w in [400, 500, 600, 700, 800]) {
    font.addFont(File('assets/fonts/PlusJakartaSans-$w.ttf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await font.load();
  final home = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = File('$home/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(icons.readAsBytes().then((b) => ByteData.view(b.buffer)))).load();
  }
}

Future<void> _pump(WidgetTester tester, Widget screen, String name,
    {Size size = const Size(390, 844), Future<void> Function(WidgetTester)? then}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [..._overrides()],
    child: MaterialApp(theme: AppTheme.light(), debugShowCheckedModeBanner: false, home: screen),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
  if (then != null) {
    await then(tester);
    await tester.pump(const Duration(milliseconds: 600));
  }
  expect(tester.takeException(), isNull, reason: name);
  if (_shots.isNotEmpty) {
    await expectLater(find.byType(MaterialApp), matchesGoldenFile(Uri.file('$_shots/$name.png')));
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    Intl.defaultLocale = 'fr_FR';
    await _loadFonts();
  });

  testWidgets('recherche', (t) => _pump(t, const TravelSearchScreen(), '1-recherche'));
  testWidgets('page compagnie', (t) => _pump(t, const CompanyPublicScreen(slug: 'voyages-du-kadiogo'), '2-compagnie'));
  testWidgets('réservation', (t) => _pump(t, const TravelBookScreen(tripId: 't1'), '3-reservation'));
  testWidgets('mes tickets', (t) => _pump(t, const MyTravelBookingsScreen(), '4-mes-tickets'));
  testWidgets('e-ticket', (t) => _pump(t, const TravelBookingDetailScreen(bookingId: 'eticket'), '5-eticket', size: const Size(390, 1500)));
  testWidgets('ticket livré', (t) => _pump(t, const TravelBookingDetailScreen(bookingId: 'delivery'), '6-ticket-livre', size: const Size(390, 1500)));
  testWidgets('compagnie : réservations', (t) => _pump(t, const CompanyManageScreen(companyId: 'c1'), '7-compagnie-reservations', size: const Size(390, 1200)));
  testWidgets('compagnie : grand écran', (t) => _pump(t, const CompanyManageScreen(companyId: 'c1'), '8-compagnie-large', size: const Size(1280, 800)));
  for (final (i, tab) in ['Départs', 'Contrôle', 'Mon lien'].indexed) {
    testWidgets('compagnie : onglet $tab', (t) => _pump(t, const CompanyManageScreen(companyId: 'c1'), 'a${i + 1}-onglet-$tab',
        size: const Size(390, 1000), then: (t) async {
          await t.tap(find.text(tab));
          for (var k = 0; k < 10; k++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }));
  }
  testWidgets('formulaire de départ', (t) => _pump(t, const Scaffold(body: TripFormSheet(companyId: 'c1')), 'a4-formulaire-depart'));
  testWidgets('recherche : grand écran', (t) => _pump(t, const TravelSearchScreen(), '9-recherche-large', size: const Size(1280, 800)));
}
