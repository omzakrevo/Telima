// Captures « vraies » de l'application pour la vidéo TicketsVertical (usage ponctuel, volontairement hors de app/test pour ne pas tourner en CI).
// Utilisation : copier ce fichier dans app/test/, puis  flutter test test/video_shots_test.dart --update-goldens --dart-define=SHOTS_DIR=/chemin/absolu
// et supprimer la copie. Les images sont ensuite réduites (780 px de large, JPEG) dans video/public/ecrans/.
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

const _shots = String.fromEnvironment('SHOTS_DIR');

DateTime _at(int days, int h, int m) {
  final n = DateTime.now().add(Duration(days: days));
  return DateTime(n.year, n.month, n.day, h, m);
}

const _co = {
  'rahimo-transport': ('Rahimo Transport', 9000),
  'tsr-express': ('TSR Express', 7000),
  'rakieta-transport': ('Rakieta Transport', 7500),
  'elitis-express': ('Elitis Express', 9000),
  'staf': ('STAF Transport', 7500),
  'saramaya-transport': ('Saramaya Transport', 7500),
};

Map<String, dynamic> _trip(String id, String slug, DateTime at, {String from = 'Ouagadougou', String to = 'Bobo-Dioulasso', int seats = 23, String? cls = 'VIP', int? price}) => {
      'id': id,
      'company_id': 'c-$slug',
      'company_name': _co[slug]!.$1,
      'company_slug': slug,
      'delivers_tickets': false,
      'accepting_bookings': true,
      'from_city': from,
      'to_city': to,
      'departure_at': at.toUtc().toIso8601String(),
      'duration_minutes': 330,
      'bus_class': cls,
      'price': price ?? _co[slug]!.$2,
      'seats_total': 50,
      'seats_available': seats,
      'departure_station': 'Gare routière',
      'station_lat': 12.36,
      'station_lng': -1.52,
      'status': 'scheduled',
    };

TransportCompany _company(String slug) {
  final trips = <Map<String, dynamic>>[];
  var i = 0;
  for (final d in [0, 1, 2]) {
    for (final h in [7, 10, 14, 18]) {
      trips.add(_trip('${slug}o$d$h', slug, _at(d + 1, h, 30), seats: 8 + (i++ * 7) % 40));
      trips.add(_trip('${slug}b$d$h', slug, _at(d + 1, h, 0), from: 'Bobo-Dioulasso', to: 'Ouagadougou', seats: 12 + (i++ * 5) % 30));
    }
  }
  for (final h in [8, 15]) {
    trips.add(_trip('${slug}x$h', slug, _at(1, h, 0), from: 'Bobo-Dioulasso', to: 'Banfora', price: 2000, cls: null));
  }
  return TransportCompany({
    'id': 'c-$slug',
    'slug': slug,
    'name': _co[slug]!.$1,
    'description': 'Lignes Ouagadougou · Bobo-Dioulasso · Banfora. Cars climatisés, départs tous les jours.',
    'phone': '+22664863755',
    'city': 'Ouagadougou',
    'station_address': 'Gare routière de Ouagadougou',
    'lat': 12.36,
    'lng': -1.52,
    'accepting_bookings': true,
    'delivers_tickets': false,
    'status': 'approved',
    'trips': trips,
  });
}

TransportCompany _plain(String slug) => TransportCompany({
      'id': 'c-$slug', 'slug': slug, 'name': _co[slug]!.$1, 'city': 'Ouagadougou', 'station_address': 'Gare routière',
      'lat': 12.36, 'lng': -1.52, 'accepting_bookings': true, 'delivers_tickets': false, 'status': 'approved',
    });

TravelBooking _booking(String status) => TravelBooking({
      'id': 'b-$status',
      'code': 'VOY-2026-000042',
      'qr_token': 'abc123def456ghi789',
      'trip_id': 'rahimo-transport',
      'company_id': 'c-rahimo-transport',
      'customer_id': 'u1',
      'status': status,
      'passengers': 2,
      'passenger_names': ['Awa Ouédraogo', 'Ali Ouédraogo'],
      'customer_name': 'Awa Ouédraogo',
      'customer_phone': '+22670000000',
      'ticket_mode': 'eticket',
      'unit_price': 9000,
      'tickets_total': 18000,
      'delivery_fee': 0,
      'total': 18000,
      'service_fee': 500,
      'service_fee_status': 'paid',
      'prepaid': true,
      'payment_status': 'paid',
      'seat_numbers': '12, 13',
      'created_at': DateTime.now().subtract(const Duration(minutes: 8)).toIso8601String(),
      'travel_trips': _trip('t1', 'rahimo-transport', _at(1, 18, 30)),
      'transport_companies': {'name': 'Rahimo Transport', 'phone': '+22664863755', 'slug': 'rahimo-transport'},
    });

final _user = AppUser(id: 'u1', phone: '+22670000000', fullName: 'Awa Ouédraogo', role: UserRole.client, isActive: true);

List _overrides() {
  final results = [
    _trip('r1', 'tsr-express', _at(1, 18, 0)),
    _trip('r2', 'rahimo-transport', _at(1, 18, 30)),
    _trip('r3', 'rakieta-transport', _at(1, 19, 0), seats: 4, cls: null),
    _trip('r4', 'elitis-express', _at(1, 22, 0)),
    _trip('r5', 'staf', _at(2, 18, 30), cls: null),
  ];
  return [
    currentUserProvider.overrideWithValue(_user),
    savedAddressesProvider.overrideWith((ref, _) async => const []),
    tripSearchProvider.overrideWith((ref, _) async => [for (final t in results) TravelTrip(t)]),
    travelCitiesProvider.overrideWith((ref) async => ['Banfora', 'Bobo-Dioulasso', 'Ouagadougou', 'Niangoloko', 'Ouahigouya']),
    travelCompaniesProvider.overrideWith((ref) async => [for (final s in _co.keys) _plain(s)]),
    travelTripProvider.overrideWith((ref, _) async => TravelTrip(_trip('t1', 'rahimo-transport', _at(1, 18, 30)))),
    companyBySlugProvider.overrideWith((ref, slug) async => _company(slug)),
    travelBookingProvider.overrideWith((ref, id) async => _booking('confirmed')),
  ];
}

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

Future<void> _shot(WidgetTester tester, Widget screen, String name, double height,
    {Future<void> Function(WidgetTester)? then}) async {
  tester.view.physicalSize = Size(390, height) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [..._overrides()],
    child: MaterialApp(theme: AppTheme.light(), debugShowCheckedModeBanner: false, home: screen),
  ));
  Future<void> settle() async {
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(MaterialApp));
      for (final f in Directory('assets/voyages').listSync(recursive: true).whereType<File>()) {
        await precacheImage(AssetImage(f.path.replaceAll('\\', '/')), ctx);
      }
    });
    for (var k = 0; k < 18; k++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  await settle();
  if (then != null) {
    await then(tester);
    await settle();
  }
  expect(tester.takeException(), isNull, reason: name);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(Uri.file('$_shots/$name.png')));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    Intl.defaultLocale = 'fr_FR';
    await _loadFonts();
  });

  testWidgets('1 recherche vide', (t) => _shot(t, const TravelSearchScreen(), 's1-recherche', 900));

  testWidgets('2 recherche avec choix', (t) => _shot(t, const TravelSearchScreen(), 's2-choix', 1500, then: (t) async {
        Future<void> pick(String hint, String city) async {
          await t.ensureVisible(find.text(hint));
          await t.tap(find.text(hint));
          await t.pump(const Duration(milliseconds: 500));
          await t.pump(const Duration(milliseconds: 500));
          await t.tap(find.text(city).last);
          await t.pump(const Duration(milliseconds: 500));
          await t.pump(const Duration(milliseconds: 500));
        }

        await pick('Choisir la ville de départ', 'Ouagadougou');
        await pick('Choisir la ville d’arrivée', 'Bobo-Dioulasso');
        await t.ensureVisible(find.text('Soir · 18h–24h'));
        await t.tap(find.text('Soir · 18h–24h'));
        await t.pump(const Duration(milliseconds: 500));
      }));

  testWidgets('3 compagnie', (t) => _shot(t, const CompanyPublicScreen(slug: 'rahimo-transport'), 's3-compagnie', 1700));
  testWidgets('3b compagnie tsr', (t) => _shot(t, const CompanyPublicScreen(slug: 'tsr-express'), 's3b-tsr', 1700));

  testWidgets('4 reservation', (t) => _shot(t, const TravelBookScreen(tripId: 't1'), 's4-reservation', 1500, then: (t) async {
        await t.tap(find.byIcon(Icons.add_rounded).first);
        await t.pump(const Duration(milliseconds: 400));
        await t.enterText(find.byType(TextField).at(1), 'Ali Ouédraogo');
        await t.pump(const Duration(milliseconds: 400));
      }));

  testWidgets('5 ticket', (t) => _shot(t, const TravelBookingDetailScreen(bookingId: 'b-confirmed'), 's5-ticket', 1900));
}
