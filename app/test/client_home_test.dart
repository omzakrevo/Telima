// Accueil client et recherche générale avec des données fictives : aucun débordement, mobile et grand écran.
// Captures : flutter test test/client_home_test.dart --update-goldens --dart-define=SHOTS_DIR=/chemin
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:telima/config/theme.dart';
import 'package:telima/data/models/delivery.dart';
import 'package:telima/data/models/enums.dart';
import 'package:telima/data/models/restaurant.dart';
import 'package:telima/data/models/shop.dart';
import 'package:telima/data/models/travel.dart';
import 'package:telima/data/models/user.dart';
import 'package:telima/data/models/wallet.dart';
import 'package:telima/providers/auth_providers.dart';
import 'package:telima/providers/data_providers.dart';
import 'package:telima/providers/restaurant_providers.dart';
import 'package:telima/providers/shop_providers.dart';
import 'package:telima/providers/travel_providers.dart';
import 'package:telima/screens/client/client_home_screen.dart';
import 'package:telima/screens/client/global_search_screen.dart';

const _shots = String.fromEnvironment('SHOTS_DIR');

final _user = AppUser(id: 'u1', phone: '+22670000000', fullName: 'Awa Ouédraogo', role: UserRole.client, isActive: true);

final _delivery = Delivery({
  'id': 'd1',
  'code': 'LIV-2026-000012',
  'status': 'in_transit',
  'pickup_address': 'Marché de Gounghin',
  'dropoff_address': 'Ouaga 2000',
  'package_description': 'Chaussures',
  'driver_name': 'Ali Sawadogo',
});

final _company = TransportCompany({
  'id': 'c1',
  'slug': 'kadiogo',
  'name': 'Voyages du Kadiogo',
  'city': 'Ouagadougou',
  'lat': 12.36,
  'lng': -1.52,
  'status': 'approved',
  'trips': [],
});

List _overrides({bool withDelivery = true}) => [
      currentUserProvider.overrideWithValue(_user),
      myActiveDeliveriesProvider.overrideWith((ref) => Stream.value(withDelivery ? [_delivery] : <Delivery>[])),
      myDeliveriesProvider.overrideWith((ref) async => [_delivery]),
      myWalletProvider.overrideWith((ref) async => Wallet(id: 'w1', balance: 12500)),
      myBusinessesProvider.overrideWith((ref) async => []),
      notificationsProvider.overrideWith((ref) => Stream.value([])),
      nearbyRestaurantsProvider.overrideWith((ref, _) async => <Restaurant>[]),
      nearbyShopsProvider.overrideWith((ref, _) async => <Shop>[]),
      travelCompaniesProvider.overrideWith((ref) async => [_company]),
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

Future<void> _pump(WidgetTester tester, Widget screen, String name, {Size size = const Size(390, 844), bool withDelivery = true}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [..._overrides(withDelivery: withDelivery)],
    child: MaterialApp(theme: AppTheme.light(), debugShowCheckedModeBanner: false, home: screen),
  ));
  await tester.runAsync(() async {
    final ctx = tester.element(find.byType(MaterialApp));
    for (final f in Directory('assets/3d').listSync().whereType<File>().where((f) => f.path.endsWith('.webp'))) {
      await precacheImage(AssetImage(f.path.replaceAll('\\', '/')), ctx);
    }
  });
  for (var k = 0; k < 14; k++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
  for (var k = 0; k < 5; k++) {
    await tester.pump(const Duration(milliseconds: 100));
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

  testWidgets('accueil client', (t) => _pump(t, const ClientHomeScreen(), 'h1-accueil'));
  testWidgets('accueil client : sans livraison', (t) => _pump(t, const ClientHomeScreen(), 'h2-accueil-vide', withDelivery: false));
  testWidgets('accueil client : petit écran', (t) => _pump(t, const ClientHomeScreen(), 'h3-accueil-petit', size: const Size(320, 640)));
  testWidgets('accueil client : grand écran', (t) => _pump(t, const ClientHomeScreen(), 'h4-accueil-large', size: const Size(1280, 800)));
  testWidgets('recherche : suggestions', (t) => _pump(t, const GlobalSearchScreen(), 's1-recherche'));
  testWidgets('recherche : résultats', (t) => _pump(t, const GlobalSearchScreen(initialQuery: 'kad'), 's2-resultats'));
  testWidgets('recherche : code de commande', (t) => _pump(t, const GlobalSearchScreen(initialQuery: '000012'), 's3-code'));
}
