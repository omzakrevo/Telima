// Captures « vraies » de l'application pour les vidéos LivreurVertical et CommanderVertical (usage ponctuel, hors de app/test).
// Utilisation : copier ce fichier dans app/test/, puis
//   flutter test test/livreur_commande_shots_test.dart --update-goldens --dart-define=SHOTS_DIR=/chemin/absolu
// et supprimer la copie. Les tuiles de carte ne se chargent pas dans flutter test : la caméra de chaque carte est notée (lignes CARTE)
// et video/capture/poser_tuiles.py pose ensuite les vraies tuiles OpenStreetMap sous la carte.
// Les images sont ensuite réduites (780 px de large, JPEG) dans video/public/ecrans/.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:telima/config/theme.dart';
import 'package:telima/core/services/routing_service.dart';
import 'package:telima/data/models/config_models.dart';
import 'package:telima/data/models/delivery.dart';
import 'package:telima/data/models/driver.dart';
import 'package:telima/data/models/enums.dart';
import 'package:telima/data/models/restaurant.dart';
import 'package:telima/data/models/shop.dart';
import 'package:telima/data/models/user.dart';
import 'package:telima/data/models/wallet.dart';
import 'package:telima/data/repositories/config_repository.dart';
import 'package:telima/data/repositories/delivery_repository.dart';
import 'package:telima/providers/auth_providers.dart';
import 'package:telima/providers/core_providers.dart';
import 'package:telima/providers/data_providers.dart';
import 'package:telima/providers/driver_tracking.dart';
import 'package:telima/providers/restaurant_providers.dart';
import 'package:telima/providers/shop_providers.dart';
import 'package:telima/providers/travel_providers.dart';
import 'package:telima/screens/auth/register_screen.dart';
import 'package:telima/screens/auth/welcome_screen.dart';
import 'package:telima/screens/client/client_home_screen.dart';
import 'package:telima/screens/client/delivery_tracking_screen.dart';
import 'package:telima/screens/client/new_delivery_screen.dart';
import 'package:telima/screens/driver/driver_application_screen.dart';
import 'package:telima/screens/driver/driver_home_screen.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show MapCamera, MarkerLayer, FlutterMap;

const _shots = String.fromEnvironment('SHOTS_DIR');

final _fakeClient = SupabaseClient('https://exemple.supabase.co', 'cle-publique-factice');
late SharedPreferences _prefs;

final _client = AppUser(id: 'u1', phone: '+22670000000', fullName: 'Awa Ouédraogo', role: UserRole.client, isActive: true);
final _driverUser = AppUser(id: 'u2', phone: '+22670123456', fullName: 'Ali Sawadogo', role: UserRole.driver, isActive: true);

const _gounghin = LatLng(12.3712, -1.5490);
const _ouaga2000 = LatLng(12.3265, -1.4995);

DriverProfile _profile(String status, {bool online = false}) => DriverProfile({
      'user_id': 'u2',
      'status': status,
      'is_online': online,
      'id_document_number': 'B12345678',
      'rating_avg': 4.8,
      'rating_count': 36,
      'total_deliveries': 128,
      'services': ['parcel', 'errand'],
      'vehicles': [
        {'id': 'v1', 'type': 'moto', 'brand': 'Yamaha', 'model': 'Crypton', 'color': 'Rouge', 'plate_number': '11 KK 2345', 'is_active': true},
      ],
    });

final _requests = [
  AvailableRequest({
    'id': 'r1',
    'code': 'LIV-2026-000231',
    'vehicle_type': 'moto',
    'pickup_address': 'Marché de Gounghin',
    'dropoff_address': 'Ouaga 2000, rue 15.18',
    'pickup_lat': _gounghin.latitude,
    'pickup_lng': _gounghin.longitude,
    'dropoff_lat': _ouaga2000.latitude,
    'dropoff_lng': _ouaga2000.longitude,
    'package_category': 'petit_colis',
    'package_size': 'petit',
    'package_quantity': 1,
    'distance_km': 10.3,
    'total_price': 2000,
    'driver_earning': 1700,
    'payment_method': 'cash',
    'distance_to_pickup_km': 0.8,
  }),
  AvailableRequest({
    'id': 'r2',
    'code': 'LIV-2026-000232',
    'vehicle_type': 'moto',
    'pickup_address': 'Zogona, près de l’université',
    'dropoff_address': 'Patte d’Oie',
    'pickup_lat': 12.379,
    'pickup_lng': -1.499,
    'dropoff_lat': 12.335,
    'dropoff_lng': -1.522,
    'package_category': 'document',
    'package_size': 'petit',
    'package_quantity': 1,
    'distance_km': 5.1,
    'total_price': 1200,
    'driver_earning': 1020,
    'payment_method': 'orange_money',
    'distance_to_pickup_km': 1.6,
  }),
];

final _delivery = Delivery({
  'id': 'd1',
  'code': 'LIV-2026-000231',
  'status': 'in_transit',
  'customer_id': 'u1',
  'customer_name': 'Awa Ouédraogo',
  'driver_id': 'u2',
  'vehicle_type': 'moto',
  'pickup_address': 'Marché de Gounghin',
  'pickup_contact_name': 'Awa Ouédraogo',
  'pickup_contact_phone': '70 00 00 00',
  'pickup_lat': _gounghin.latitude,
  'pickup_lng': _gounghin.longitude,
  'dropoff_address': 'Ouaga 2000, rue 15.18',
  'dropoff_contact_name': 'Moussa Kaboré',
  'dropoff_contact_phone': '76 45 12 89',
  'dropoff_lat': _ouaga2000.latitude,
  'dropoff_lng': _ouaga2000.longitude,
  'package_category': 'petit_colis',
  'package_description': '2 paires de chaussures',
  'package_size': 'petit',
  'package_quantity': 1,
  'distance_km': 10.3,
  'price_base': 500,
  'price_distance': 1500,
  'total_price': 2000,
  'payment_method': 'cash',
  'payment_status': 'pending',
  'eta_minutes': 12,
  'created_at': DateTime.now().subtract(const Duration(minutes: 9)).toIso8601String(),
});

class _FakeConfig extends ConfigRepository {
  _FakeConfig(super.client, super.cache);
  @override
  Future<Quote> quote({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    VehicleType? vehicle,
    PackageSize size = PackageSize.petit,
    bool fragile = false,
    double? weightKg,
    PackageCategory category = PackageCategory.petit_colis,
    double? routeKm,
    bool extraStop = false,
  }) async =>
      Quote({
        'distance_km': 10.3,
        'vehicle_type': (vehicle ?? VehicleType.moto).name,
        'suggested_vehicle': 'moto',
        'price_base': 500,
        'price_distance': 1500,
        'price_extras': 0,
        'price_zone': 0,
        'total_price': 2000,
      });
}

class _FakeDeliveries extends DeliveryRepository {
  _FakeDeliveries(super.client, super.cache);
  @override
  Future<AssignedDriver?> driverInfo(String id) async => AssignedDriver({
        'first_name': 'Ali',
        'full_name': 'Ali Sawadogo',
        'phone': '+22670123456',
        'rating_avg': 4.8,
        'rating_count': 36,
        'vehicle_type': 'moto',
        'vehicle_label': 'Yamaha Crypton rouge',
        'plate_number': '11 KK 2345',
        'lat': 12.360426,
        'lng': -1.528502,
      });
  @override
  Future<String?> otp(String id) async => '4827';
  @override
  Future<List<StatusHistoryEntry>> history(String id) async => const [];
  @override
  RealtimeChannel subscribeLocations(String deliveryId, void Function(double lat, double lng) onPosition) =>
      _fakeClient.channel('faux-$deliveryId');
  @override
  Future<Map<String, dynamic>?> lastLocation(String deliveryId) async => {'lat': 12.360426, 'lng': -1.528502};
  @override
  Future<void> removeChannel(RealtimeChannel channel) async {}
}

class _FakeRouting implements RoutingService {
  // Itinéraire réel Gounghin → Ouaga 2000 (OSRM), figé pour la capture
  static const _pts = [
    [-1.548985, 12.371024], [-1.545576, 12.371239], [-1.546213, 12.374508], [-1.542105, 12.375478], [-1.531006, 12.367837],
    [-1.529978, 12.36807], [-1.529759, 12.36646], [-1.529218, 12.366544], [-1.528502, 12.360426], [-1.527296, 12.358443],
    [-1.525997, 12.333], [-1.504522, 12.332686], [-1.501174, 12.331275], [-1.498295, 12.328654], [-1.498859, 12.327893],
    [-1.498426, 12.327375], [-1.49951, 12.326683],
  ];
  @override
  Future<RouteResult> route(List<LatLng> waypoints) async {
    final all = [for (final p in _pts) LatLng(p[1], p[0])];
    // depuis la position du livreur : on garde la fin du trajet
    final from = waypoints.first.latitude < 12.3615 && waypoints.first.latitude > 12.355 ? all.sublist(8) : all;
    return RouteResult(points: from, distanceKm: from.length == all.length ? 10.3 : 5.5, durationMin: from.length == all.length ? 24 : 13);
  }
}

class _FakeTracking extends DriverTrackingController {
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

List _overrides({AppUser? user, DriverProfile? driver, bool requests = false}) => [
      sharedPrefsProvider.overrideWithValue(_prefs),
      supabaseProvider.overrideWithValue(_fakeClient),
      currentUserProvider.overrideWithValue(user ?? _client),
      configRepositoryProvider.overrideWith((ref) => _FakeConfig(_fakeClient, ref.watch(cacheProvider))),
      deliveryRepositoryProvider.overrideWith((ref) => _FakeDeliveries(_fakeClient, ref.watch(cacheProvider))),
      routingServiceProvider.overrideWithValue(_FakeRouting()),
      driverTrackingProvider.overrideWith(_FakeTracking.new),
      citiesProvider.overrideWith((ref) async => [
            City({'id': 'ouaga', 'name': 'Ouagadougou', 'center_lat': 12.37, 'center_lng': -1.52}),
            City({'id': 'bobo', 'name': 'Bobo-Dioulasso', 'center_lat': 11.18, 'center_lng': -4.29}),
            City({'id': 'banfora', 'name': 'Banfora', 'center_lat': 10.63, 'center_lng': -4.76}),
          ]),
      myDriverProfileProvider.overrideWith((ref) async => driver),
      activeCoursesProvider.overrideWith((ref) => Stream.value(<Delivery>[])),
      availableRequestsProvider.overrideWith((ref) => Stream.value(requests ? _requests : <AvailableRequest>[])),
      driverEarningsProvider.overrideWith((ref) async => DriverEarnings({
            'today': 6375, 'week': 38250, 'month': 152400, 'count_today': 5, 'count_week': 30, 'count_month': 118,
            'count_total': 128, 'balance': 24500,
          })),
      driverRatingsProvider.overrideWith((ref) async => <Rating>[]),
      myActiveDeliveriesProvider.overrideWith((ref) => Stream.value(<Delivery>[])),
      myDeliveriesProvider.overrideWith((ref) async => <Delivery>[]),
      myWalletProvider.overrideWith((ref) async => Wallet(id: 'w1', balance: 12500)),
      myBusinessesProvider.overrideWith((ref) async => []),
      notificationsProvider.overrideWith((ref) => Stream.value([])),
      nearbyRestaurantsProvider.overrideWith((ref, _) async => <Restaurant>[]),
      nearbyShopsProvider.overrideWith((ref, _) async => <Shop>[]),
      travelCompaniesProvider.overrideWith((ref) async => []),
      savedAddressesProvider.overrideWith((ref, _) async => [
            SavedAddress({
              'id': 'a1', 'label': 'Ma boutique', 'address': 'Marché de Gounghin, boutique 12', 'contact_name': 'Awa Ouédraogo',
              'contact_phone': '70 00 00 00', 'lat': _gounghin.latitude, 'lng': _gounghin.longitude,
            }),
            SavedAddress({
              'id': 'a2', 'label': 'Chez Moussa', 'address': 'Ouaga 2000, rue 15.18', 'contact_name': 'Moussa Kaboré',
              'contact_phone': '76 45 12 89', 'lat': _ouaga2000.latitude, 'lng': _ouaga2000.longitude,
            }),
          ]),
      deliveryStreamProvider.overrideWith((ref, _) => Stream.value(_delivery)),
      deliveryOtpProvider.overrideWith((ref, _) async => '4827'),
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

Future<void> _settle(WidgetTester tester, {int waitMs = 400}) async {
  for (var k = 0; k < 10; k++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: waitMs)));
  for (var k = 0; k < 10; k++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(WidgetTester tester, Widget screen, String name, double height,
    {List extra = const [], Future<void> Function(WidgetTester)? then, int mapWaitMs = 0}) async {
  tester.view.physicalSize = Size(430, height) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  HttpOverrides.global = null; // vraies tuiles OpenStreetMap
  await tester.pumpWidget(ProviderScope(
    overrides: [...extra],
    child: MaterialApp(theme: AppTheme.light(), debugShowCheckedModeBanner: false, home: screen),
  ));
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(MaterialApp));
    for (final f in Directory('assets/3d').listSync().whereType<File>().where((f) => f.path.endsWith('.webp'))) {
      await precacheImage(AssetImage(f.path.replaceAll('\\', '/')), ctx);
    }
  });
  await _settle(tester);
  if (then != null) {
    await then(tester);
    await _settle(tester);
  }
  if (mapWaitMs > 0) {
    // laisse le temps aux tuiles OpenStreetMap d'arriver puis d'être décodées
    for (var i = 0; i < 4; i++) {
      await _settle(tester, waitMs: mapWaitMs);
    }
  }
  tester.takeException();
  // Les tuiles ne se chargent pas dans flutter test : on note la caméra de chaque carte pour poser les tuiles OSM après coup
  for (final e in find.byType(MarkerLayer).evaluate()) {
    final cam = MapCamera.of(e);
    final r = tester.getRect(find.ancestor(of: find.byWidget(e.widget), matching: find.byType(FlutterMap)).first);
    debugPrint('CARTE $name ${cam.center.latitude} ${cam.center.longitude} ${cam.zoom} ${r.left} ${r.top} ${r.width} ${r.height}');
  }
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(Uri.file('$_shots/$name.png')));
  if (const bool.fromEnvironment('DUMP')) {
    for (final e in find.byType(RichText).evaluate()) {
      final w = e.widget as RichText;
      final r = tester.getRect(find.byWidget(w));
      debugPrint('TXT $name ${r.left.round()} ${r.top.round()} ${r.width.round()} ${r.height.round()} ${w.text.toPlainText().replaceAll('\n', ' ')}');
    }
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}

Future<void> _type(WidgetTester t, String label, String text) async {
  final f = find.widgetWithText(TextFormField, label);
  await t.ensureVisible(f.first);
  await t.enterText(f.first, text);
  await t.pump(const Duration(milliseconds: 200));
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.pump(const Duration(milliseconds: 200));
  await t.tap(f.first, warnIfMissed: false);
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    Intl.defaultLocale = 'fr_FR';
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
    HttpOverrides.global = null; // vraies tuiles de carte
  });

  // ───────── Devenir livreur ─────────
  testWidgets('l1 accueil', (t) => _shot(t, const WelcomeScreen(), 'l1-accueil', 844, extra: _overrides(), then: (t) async {
        await _tap(t, find.text('Passer'));
        await t.pump(const Duration(seconds: 1));
      }));

  testWidgets('l2 inscription', (t) => _shot(t, const RegisterScreen(asDriver: true), 'l2-inscription', 1000, extra: _overrides(),
          then: (t) async {
        await _type(t, 'Prénom', 'Ali');
        await _type(t, 'Nom', 'Sawadogo');
        await _type(t, 'Téléphone', '70 12 34 56');
        await _type(t, 'Mot de passe', 'telima2026');
        await _tap(t, find.text('Ville'));
        await _tap(t, find.text('Ouagadougou').last);
        FocusManager.instance.primaryFocus?.unfocus();
      }));

  testWidgets('l3 dossier', (t) => _shot(t, const DriverApplicationScreen(), 'l3-dossier', 1500, extra: _overrides(user: _driverUser),
          then: (t) async {
        await _type(t, 'Numéro CNIB / CNI', 'B12345678');
        await _type(t, 'Marque', 'Yamaha');
        await _type(t, 'Modèle', 'Crypton');
        await _type(t, 'Couleur', 'Rouge');
        await _type(t, 'Immatriculation', '11 KK 2345');
        await _type(t, 'Numéro du permis', 'BF-2019-004512');
        FocusManager.instance.primaryFocus?.unfocus();
        await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      }));

  testWidgets('l4 a completer', (t) => _shot(t, const DriverShell(), 'l4-a-completer', 844, extra: _overrides(user: _driverUser)));
  testWidgets('l5 verification', (t) =>
      _shot(t, const DriverShell(), 'l5-verification', 844, extra: _overrides(user: _driverUser, driver: _profile('pending'))));
  testWidgets('l6 hors ligne', (t) =>
      _shot(t, const DriverShell(), 'l6-hors-ligne', 844, extra: _overrides(user: _driverUser, driver: _profile('approved'))));
  testWidgets('l7 en ligne', (t) => _shot(t, const DriverShell(), 'l7-en-ligne', 1300,
      extra: _overrides(user: _driverUser, driver: _profile('approved', online: true), requests: true)));
  testWidgets('l8 revenus', (t) => _shot(t, const DriverShell(), 'l8-revenus', 844,
      extra: _overrides(user: _driverUser, driver: _profile('approved', online: true)), then: (t) async {
        await _tap(t, find.byIcon(Icons.bar_chart_outlined));
      }));

  // ───────── Commander une livraison ─────────
  testWidgets('c1 accueil', (t) => _shot(t, const ClientHomeScreen(), 'c1-accueil', 844, extra: _overrides()));

  testWidgets('c2 recuperation', (t) => _shot(t, const NewDeliveryScreen(), 'c2-recuperation', 1000, extra: _overrides(), mapWaitMs: 300,
          then: (t) async {
        await _tap(t, find.text('Ma boutique'));
        await _tap(t, find.text('Appelez-moi en arrivant'));
        FocusManager.instance.primaryFocus?.unfocus();
      }));

  Future<void> toStep(WidgetTester t, int step) async {
    await _tap(t, find.text('Ma boutique'));
    await _tap(t, find.text('Continuer'));
    if (step >= 1) {
      await _tap(t, find.text('Chez Moussa'));
      await _tap(t, find.text('Portail bleu'));
    }
    if (step >= 2) {
      await _tap(t, find.text('Continuer'));
      await _tap(t, find.text('Petit colis'));
      await _type(t, 'Description (ex. 2 paires de chaussures)', '2 paires de chaussures');
      await _tap(t, find.text('Fragile'));
    }
    if (step >= 3) {
      await _tap(t, find.text('Continuer'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1500)));
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
  }

  testWidgets('c3 destination', (t) =>
      _shot(t, const NewDeliveryScreen(), 'c3-destination', 1000, extra: _overrides(), mapWaitMs: 300, then: (t) => toStep(t, 1)));
  testWidgets('c4 colis', (t) => _shot(t, const NewDeliveryScreen(), 'c4-colis', 1100, extra: _overrides(), then: (t) => toStep(t, 2)));
  testWidgets('c5 confirmation', (t) =>
      _shot(t, const NewDeliveryScreen(), 'c5-confirmation', 1500, extra: _overrides(), then: (t) => toStep(t, 3)));
  testWidgets('c6 suivi', (t) =>
      _shot(t, const DeliveryTrackingScreen(deliveryId: 'd1'), 'c6-suivi', 1500, extra: _overrides(), mapWaitMs: 300));
}
