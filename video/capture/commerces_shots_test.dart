// Captures « vraies » de l'application pour les vidéos BoutiqueTutoVertical et RestaurantTutoVertical (usage ponctuel, hors de app/test).
// Utilisation : copier ce fichier dans app/test/, puis
//   flutter test test/commerces_shots_test.dart --update-goldens --dart-define=SHOTS_DIR=/chemin/absolu
// et supprimer la copie. Les tuiles de carte ne se chargent pas dans flutter test : la caméra de chaque carte est notée
// (lignes CARTE) et video/capture/poser_tuiles.py pose ensuite les vraies tuiles OpenStreetMap sous la carte.
// Données fictives (boutique « Mode d'Awa », restaurant « Chez Tantie Awa ») ; articles et plats sans photo.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' show FlutterMap, MapCamera, MarkerLayer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:telima/config/theme.dart';
import 'package:telima/core/services/geocoding_service.dart';
import 'package:telima/core/services/location_service.dart';
import 'package:telima/data/models/delivery.dart';
import 'package:telima/data/models/enums.dart';
import 'package:telima/data/models/restaurant.dart';
import 'package:telima/data/models/shop.dart';
import 'package:telima/data/models/travel.dart';
import 'package:telima/data/models/user.dart';
import 'package:telima/data/models/wallet.dart';
import 'package:telima/providers/auth_providers.dart';
import 'package:telima/providers/core_providers.dart';
import 'package:telima/providers/data_providers.dart';
import 'package:telima/providers/restaurant_providers.dart';
import 'package:telima/providers/shop_providers.dart';
import 'package:telima/providers/travel_providers.dart';
import 'package:telima/screens/client/client_home_screen.dart';
import 'package:telima/screens/client/location_picker_screen.dart' show geocodingProvider;
import 'package:telima/screens/restaurant/restaurant_form_screen.dart';
import 'package:telima/screens/restaurant/restaurant_owner_screens.dart';
import 'package:telima/screens/restaurant/restaurant_public_screen.dart';
import 'package:telima/screens/shop/shop_form_screen.dart';
import 'package:telima/screens/shop/shop_owner_screens.dart';
import 'package:telima/screens/shop/shop_public_screen.dart';

const _shots = String.fromEnvironment('SHOTS_DIR');

final _fakeClient = SupabaseClient('https://exemple.supabase.co', 'cle-publique-factice');
late SharedPreferences _prefs;

final _user = AppUser(id: 'u1', phone: '+22670000000', fullName: 'Awa Ouédraogo', role: UserRole.client, isActive: true);
const _gounghin = LatLng(12.3712, -1.5490);

class _FakeLocation extends LocationService {
  @override
  Future<LatLng> current() async => _gounghin;
}

class _FakeGeocoding implements GeocodingService {
  @override
  Future<String?> reverse(LatLng point) async => 'Marché de Gounghin, Ouagadougou';
  @override
  Future<List<PlaceResult>> search(String query, {LatLng? near}) async => const [];
}

Map<String, dynamic> _shopJson({bool empty = false}) => {
      'id': 's1',
      'slug': 'mode-d-awa',
      'owner_id': 'u1',
      'name': 'Mode d’Awa',
      'shop_type': 'Vêtements femme',
      'description': 'Robes en pagne wax, ensembles et accessoires. Coupe sur mesure.',
      'phone': '+22670000000',
      'neighborhood': 'Gounghin',
      'address': 'Marché de Gounghin',
      'opening_hours': '8h – 20h, du lundi au samedi',
      'lat': _gounghin.latitude,
      'lng': _gounghin.longitude,
      'status': 'approved',
      'accepting_orders': true,
      'accepts_pickup': true,
      'delivers': true,
      'delivery_radius_km': 5,
      'min_order': 0,
      'prep_minutes': 20,
      'rating_avg': 4.8,
      'rating_count': 24,
      'categories': empty
          ? []
          : [
              {'id': 'c1', 'name': 'Robes', 'sort_order': 0},
              {'id': 'c2', 'name': 'Chaussures', 'sort_order': 1},
              {'id': 'c3', 'name': 'Accessoires', 'sort_order': 2},
            ],
      'items': empty
          ? []
          : [
              {'id': 'p1', 'category_id': 'c1', 'name': 'Robe en pagne wax', 'price': 15000, 'is_available': true, 'sizes': ['S', 'M', 'L', 'XL'], 'colors': ['Rouge', 'Bleu'], 'stock': 5},
              {'id': 'p2', 'category_id': 'c1', 'name': 'Ensemble pagne', 'price': 18000, 'is_available': true, 'sizes': ['M', 'L'], 'stock': 3},
              {'id': 'p3', 'category_id': 'c2', 'name': 'Sandales en cuir', 'price': 7500, 'is_available': true, 'sizes': ['38', '39', '40', '41'], 'stock': 8},
              {'id': 'p4', 'category_id': 'c3', 'name': 'Sac brodé', 'price': 9000, 'is_available': true, 'stock': 2},
              {'id': 'p5', 'category_id': 'c3', 'name': 'Foulard', 'price': 2500, 'is_available': true},
            ],
    };

Map<String, dynamic> _restaurantJson({bool empty = false}) => {
      'id': 'r1',
      'slug': 'chez-tantie-awa',
      'owner_id': 'u1',
      'name': 'Chez Tantie Awa',
      'cuisine': 'Poulet braisé, Riz gras, Tô',
      'description': 'Cuisine burkinabè faite maison, tous les jours.',
      'phone': '+22670000000',
      'neighborhood': 'Gounghin',
      'address': 'Marché de Gounghin',
      'opening_hours': '11h – 23h, tous les jours',
      'lat': _gounghin.latitude,
      'lng': _gounghin.longitude,
      'status': 'approved',
      'accepting_orders': true,
      'accepts_pickup': true,
      'delivers': true,
      'delivery_radius_km': 5,
      'min_order': 1000,
      'prep_minutes': 25,
      'categories': empty
          ? []
          : [
              {'id': 'c1', 'name': 'Plats', 'sort_order': 0},
              {'id': 'c2', 'name': 'Boissons', 'sort_order': 1},
            ],
      'items': empty
          ? []
          : [
              {'id': 'i1', 'category_id': 'c1', 'name': 'Poulet braisé', 'description': 'Demi-poulet, attiéké ou alloco', 'price': 3500, 'is_available': true},
              {'id': 'i2', 'category_id': 'c1', 'name': 'Riz gras', 'price': 1000, 'is_available': true},
              {'id': 'i3', 'category_id': 'c1', 'name': 'Tô sauce gombo', 'price': 750, 'is_available': true},
              {'id': 'i4', 'category_id': 'c1', 'name': 'Attiéké poisson', 'price': 2000, 'is_available': true},
              {'id': 'i5', 'category_id': 'c2', 'name': 'Bissap', 'price': 500, 'is_available': true},
              {'id': 'i6', 'category_id': 'c2', 'name': 'Jus de gingembre', 'price': 500, 'is_available': true},
            ],
    };

final _now = DateTime.now();

ShopOrder _shopOrder(String code, String status, int minutes, {String mode = 'delivery'}) => ShopOrder({
      'id': 'o-$code',
      'code': code,
      'shop_id': 's1',
      'mode': mode,
      'status': status,
      'customer_name': 'Mariam Kaboré',
      'customer_phone': '+22676451289',
      'dropoff_address': 'Ouaga 2000, rue 15.18',
      'note': mode == 'delivery' ? 'Taille M s’il vous plaît' : null,
      'items_total': 17500,
      'delivery_fee': mode == 'delivery' ? 1000 : 0,
      'total': mode == 'delivery' ? 18500 : 17500,
      'payment_status': 'unpaid',
      'created_at': _now.subtract(Duration(minutes: minutes)).toIso8601String(),
      'shops': {'name': 'Mode d’Awa', 'slug': 'mode-d-awa', 'lat': _gounghin.latitude, 'lng': _gounghin.longitude},
      'shop_order_items': [
        {'name': 'Robe en pagne wax', 'qty': 1, 'unit_price': 15000, 'size': 'M', 'color': 'Rouge'},
        {'name': 'Foulard', 'qty': 1, 'unit_price': 2500},
      ],
    });

RestaurantOrder _restaurantOrder(String code, String status, int minutes, {String mode = 'delivery'}) => RestaurantOrder({
      'id': 'o-$code',
      'code': code,
      'restaurant_id': 'r1',
      'mode': mode,
      'status': status,
      'customer_name': 'Ali Sawadogo',
      'customer_phone': '+22670123456',
      'dropoff_address': 'Zogona, près de l’université',
      'note': mode == 'delivery' ? 'Bien pimenté' : null,
      'items_total': 8000,
      'delivery_fee': mode == 'delivery' ? 1000 : 0,
      'total': mode == 'delivery' ? 9000 : 8000,
      'payment_status': 'unpaid',
      'created_at': _now.subtract(Duration(minutes: minutes)).toIso8601String(),
      'restaurants': {'name': 'Chez Tantie Awa', 'slug': 'chez-tantie-awa', 'lat': _gounghin.latitude, 'lng': _gounghin.longitude},
      'restaurant_order_items': [
        {'name': 'Poulet braisé', 'qty': 2, 'unit_price': 3500},
        {'name': 'Bissap', 'qty': 2, 'unit_price': 500},
      ],
    });

List _overrides({bool emptyShop = false, bool emptyRestaurant = false, bool noShops = false}) => [
      sharedPrefsProvider.overrideWithValue(_prefs),
      supabaseProvider.overrideWithValue(_fakeClient),
      currentUserProvider.overrideWithValue(_user),
      locationServiceProvider.overrideWithValue(_FakeLocation()),
      geocodingProvider.overrideWithValue(_FakeGeocoding()),
      myActiveDeliveriesProvider.overrideWith((ref) => Stream.value(<Delivery>[])),
      myDeliveriesProvider.overrideWith((ref) async => <Delivery>[]),
      myWalletProvider.overrideWith((ref) async => Wallet(id: 'w1', balance: 12500)),
      myBusinessesProvider.overrideWith((ref) async => []),
      notificationsProvider.overrideWith((ref) => Stream.value([])),
      nearbyRestaurantsProvider.overrideWith((ref, _) async => <Restaurant>[]),
      nearbyShopsProvider.overrideWith((ref, _) async => <Shop>[]),
      travelCompaniesProvider.overrideWith((ref) async => <TransportCompany>[]),
      savedAddressesProvider.overrideWith((ref, _) async => []),
      // Boutique
      myShopsProvider.overrideWith((ref) async => noShops ? <Shop>[] : [Shop(_shopJson())]),
      myShopProvider.overrideWith((ref, _) async => Shop(_shopJson(empty: emptyShop))),
      shopBySlugProvider.overrideWith((ref, _) async => Shop(_shopJson())),
      shopReviewsProvider.overrideWith((ref, _) async => <ShopReview>[]),
      shopOrdersProvider.overrideWith((ref, _) async => [_shopOrder('BOU-2026-000041', 'sent', 3), _shopOrder('BOU-2026-000038', 'preparing', 26, mode: 'pickup')]),
      shopDashboardProvider.overrideWith((ref, _) async => {'orders_today': 6, 'sales_today': 74500, 'pending': 1}),
      // Restaurant
      myRestaurantsProvider.overrideWith((ref) async => noShops ? <Restaurant>[] : [Restaurant(_restaurantJson())]),
      myRestaurantProvider.overrideWith((ref, _) async => Restaurant(_restaurantJson(empty: emptyRestaurant))),
      restaurantBySlugProvider.overrideWith((ref, _) async => Restaurant(_restaurantJson())),
      restaurantOrdersProvider.overrideWith((ref, _) async => [
            _restaurantOrder('RES-2026-000112', 'sent', 2),
            _restaurantOrder('RES-2026-000109', 'preparing', 18, mode: 'pickup'),
          ]),
      restaurantDashboardProvider.overrideWith((ref, _) async => {'orders_today': 14, 'sales_today': 52500, 'pending': 1}),
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
    {List? extra, Future<void> Function(WidgetTester)? then}) async {
  tester.view.physicalSize = Size(430, height) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [...(extra ?? _overrides())],
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
  tester.takeException();
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

Future<void> _top(WidgetTester t) async {
  FocusManager.instance.primaryFocus?.unfocus();
  for (final s in find.byType(Scrollable).evaluate()) {
    final st = (s as StatefulElement).state as ScrollableState;
    if (st.position.pixels > 0) st.position.jumpTo(0);
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    Intl.defaultLocale = 'fr_FR';
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  // ───────── Accueil → Plus (commun) ─────────
  testWidgets('x1 plus', (t) => _shot(t, const ClientHomeScreen(), 'x1-plus', 932, then: (t) async {
        await _tap(t, find.text('Plus'));
        await t.pump(const Duration(seconds: 1));
      }));

  // ───────── Boutique ─────────
  testWidgets('b2 vide', (t) => _shot(t, const ShopOwnerHomeScreen(), 'b2-vide', 932, extra: _overrides(noShops: true)));

  testWidgets('b3 formulaire', (t) => _shot(t, const ShopFormScreen(), 'b3-formulaire', 2000, then: (t) async {
        await _type(t, 'Nom de la boutique', 'Mode d’Awa');
        await _type(t, 'Type de boutique', 'Vêtements femme');
        await _type(t, 'Présentation (facultatif)', 'Robes en pagne wax, ensembles et accessoires.');
        await _type(t, 'Quartier', 'Gounghin');
        await _type(t, 'Horaires', '8h – 20h, du lundi au samedi');
        await _tap(t, find.text('Ma position'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await _top(t);
      }));

  testWidgets('b4 article', (t) => _shot(t, const ShopManageScreen(shopId: 's1'), 'b4-article', 1500, extra: _overrides(emptyShop: true),
          then: (t) async {
        await _tap(t, find.text('Catalogue'));
        await _tap(t, find.text('Ajouter un article'));
        await t.pump(const Duration(seconds: 1));
        await _type(t, 'Nom de l’article', 'Robe en pagne wax');
        await _type(t, 'Prix (FCFA)', '15000');
        await _type(t, 'Tailles proposées (facultatif)', 'S, M, L, XL');
        await _type(t, 'Couleurs proposées (facultatif)', 'Rouge, Bleu');
        await _type(t, 'Quantité en stock (facultatif)', '5');
        await _top(t);
      }));

  testWidgets('b5 catalogue', (t) => _shot(t, const ShopManageScreen(shopId: 's1'), 'b5-catalogue', 1100, then: (t) async {
        await _tap(t, find.text('Catalogue'));
        await t.pump(const Duration(seconds: 1));
      }));

  testWidgets('b6 lien', (t) => _shot(t, const ShopManageScreen(shopId: 's1'), 'b6-lien', 1100, then: (t) async {
        await _tap(t, find.text('Mon lien'));
        await t.pump(const Duration(seconds: 1));
      }));

  testWidgets('b7 commandes', (t) => _shot(t, const ShopManageScreen(shopId: 's1'), 'b7-commandes', 1300));

  testWidgets('b8 page client', (t) => _shot(t, const ShopPublicScreen(slug: 'mode-d-awa'), 'b8-page-client', 1300));

  // ───────── Restaurant ─────────
  testWidgets('r2 vide', (t) => _shot(t, const RestaurantOwnerHomeScreen(), 'r2-vide', 932, extra: _overrides(noShops: true)));

  testWidgets('r3 formulaire', (t) => _shot(t, const RestaurantFormScreen(), 'r3-formulaire', 2000, then: (t) async {
        await _type(t, 'Nom du restaurant', 'Chez Tantie Awa');
        await _type(t, 'Spécialités', 'Poulet braisé, Riz gras, Tô');
        await _type(t, 'Présentation (facultatif)', 'Cuisine burkinabè faite maison, tous les jours.');
        await _type(t, 'Quartier', 'Gounghin');
        await _type(t, 'Horaires', '11h – 23h, tous les jours');
        await _tap(t, find.text('Ma position'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await _top(t);
      }));

  testWidgets('r4 categorie', (t) => _shot(t, const RestaurantManageScreen(restaurantId: 'r1'), 'r4-categorie', 1100,
          extra: _overrides(emptyRestaurant: true), then: (t) async {
        await _tap(t, find.text('Menu'));
        await _tap(t, find.text('Ajouter une catégorie'));
        await t.pump(const Duration(seconds: 1));
        await t.enterText(find.byType(TextField).last, 'Plats');
        await t.pump(const Duration(milliseconds: 300));
      }));

  testWidgets('r5 plat', (t) => _shot(t, const RestaurantManageScreen(restaurantId: 'r1'), 'r5-plat', 1300, then: (t) async {
        await _tap(t, find.text('Menu'));
        await _tap(t, find.text('Ajouter un plat'));
        await t.pump(const Duration(seconds: 1));
        await _type(t, 'Nom du plat', 'Poulet braisé');
        await _type(t, 'Prix (FCFA)', '3500');
        await _type(t, 'Description (facultatif)', 'Demi-poulet, attiéké ou alloco');
        await _top(t);
      }));

  testWidgets('r6 menu', (t) => _shot(t, const RestaurantManageScreen(restaurantId: 'r1'), 'r6-menu', 1100, then: (t) async {
        await _tap(t, find.text('Menu'));
        await t.pump(const Duration(seconds: 1));
      }));

  testWidgets('r7 lien', (t) => _shot(t, const RestaurantManageScreen(restaurantId: 'r1'), 'r7-lien', 1100, then: (t) async {
        await _tap(t, find.text('Mon lien'));
        await t.pump(const Duration(seconds: 1));
      }));

  testWidgets('r8 commandes', (t) => _shot(t, const RestaurantManageScreen(restaurantId: 'r1'), 'r8-commandes', 1300));

  testWidgets('r9 page client', (t) => _shot(t, const RestaurantPublicScreen(slug: 'chez-tantie-awa'), 'r9-page-client', 1300));
}
