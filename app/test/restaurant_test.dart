import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telima/data/models/restaurant.dart';
import 'package:telima/providers/restaurant_providers.dart';

Map<String, dynamic> _restaurantJson() => {
      'id': 'r1',
      'slug': 'chez-awa',
      'name': 'Chez Awa',
      'cuisine': 'Poulet braisé',
      'neighborhood': 'Secteur 15',
      'lat': 11.17,
      'lng': -4.29,
      'accepting_orders': true,
      'accepts_pickup': true,
      'delivers': true,
      'delivery_radius_km': 5,
      'min_order': 1000,
      'prep_minutes': 25,
      'categories': [
        {'id': 'c1', 'name': 'Plats'},
        {'id': 'c2', 'name': 'Boissons'},
      ],
      'items': [
        {'id': 'i1', 'category_id': 'c1', 'name': 'Poulet braisé', 'price': 3500, 'is_available': true},
        {'id': 'i2', 'category_id': 'c2', 'name': 'Bissap', 'price': 500, 'is_available': true},
        {'id': 'i3', 'category_id': null, 'name': 'Plat du jour', 'price': 1500, 'is_available': false},
      ],
    };

void main() {
  test('le lien partagé pointe vers la page publique du restaurant', () {
    expect(restaurantShareLink('chez-awa'), 'https://telimatchi.com/r/chez-awa');
  });

  test('un restaurant est lu depuis la réponse du serveur', () {
    final r = Restaurant(_restaurantJson());
    expect(r.name, 'Chez Awa');
    expect(r.subtitle, 'Poulet braisé · Secteur 15');
    expect(r.minOrder, 1000);
    expect(r.prepMinutes, 25);
    expect(r.suspended, isFalse);
    expect(r.items.length, 3);
  });

  test('le menu est regroupé par catégorie, les plats sans catégorie en premier', () {
    final sections = Restaurant(_restaurantJson()).sections;
    expect(sections.map((s) => s.name), ['Autres plats', 'Plats', 'Boissons']);
    expect(sections.first.items.single.name, 'Plat du jour');
    expect(sections.first.items.single.isAvailable, isFalse);
  });

  test('un menu sans catégorie s’appelle simplement « Menu »', () {
    final j = _restaurantJson()..['categories'] = [];
    expect(Restaurant(j).sections.first.name, 'Menu');
  });

  group('panier', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('ajouter, retirer et totaliser', () {
      final r = Restaurant(_restaurantJson());
      final cart = c.read(cartProvider.notifier);
      cart.add('r1', 'i1');
      cart.add('r1', 'i1');
      cart.add('r1', 'i2');
      expect(c.read(cartProvider).count, 3);
      expect(c.read(cartProvider).total(r), 3500 * 2 + 500);
      cart.remove('i1');
      expect(c.read(cartProvider).quantityOf('i1'), 1);
      cart.remove('i1');
      cart.remove('i2');
      expect(c.read(cartProvider).isEmpty, isTrue);
      expect(c.read(cartProvider).restaurantId, isNull);
    });

    test('le panier ne mélange jamais deux restaurants', () {
      final cart = c.read(cartProvider.notifier);
      cart.add('r1', 'i1');
      cart.add('r2', 'x1');
      final s = c.read(cartProvider);
      expect(s.restaurantId, 'r2');
      expect(s.qty.keys, ['x1']);
    });

    test('quantité limitée à 50 par plat', () {
      final cart = c.read(cartProvider.notifier);
      for (var i = 0; i < 60; i++) {
        cart.add('r1', 'i1');
      }
      expect(c.read(cartProvider).quantityOf('i1'), 50);
    });
  });

  test('une commande lue du serveur propose les bonnes étapes', () {
    RestaurantOrder order(String mode, String status) => RestaurantOrder({
          'id': 'o1',
          'code': 'RES-0001',
          'restaurant_id': 'r1',
          'mode': mode,
          'status': status,
          'customer_name': 'Ali',
          'customer_phone': '+22670000000',
          'items_total': 4000,
          'delivery_fee': mode == 'delivery' ? 500 : 0,
          'total': mode == 'delivery' ? 4500 : 4000,
          'payment_status': 'unpaid',
          'restaurants': {'name': 'Chez Awa', 'slug': 'chez-awa', 'lat': 11.17, 'lng': -4.29},
          'restaurant_order_items': [
            {'name': 'Poulet braisé', 'qty': 2, 'unit_price': 2000},
          ],
        });
    expect(order('pickup', 'ready').steps.map((s) => s.$1), ['sent', 'accepted', 'preparing', 'ready', 'delivered']);
    expect(order('delivery', 'ready').steps.map((s) => s.$1),
        ['sent', 'accepted', 'preparing', 'ready', 'out_for_delivery', 'delivered']);
    expect(order('pickup', 'ready').statusLabel, 'Prête à retirer');
    expect(order('delivery', 'delivered').statusLabel, 'Livrée');
    expect(order('delivery', 'sent').isOpen, isTrue);
    expect(order('delivery', 'rejected').isOpen, isFalse);
    expect(order('pickup', 'sent').items.single.text, '2 × Poulet braisé');
    expect(order('pickup', 'sent').restaurantName, 'Chez Awa');
  });
}
