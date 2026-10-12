import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telima/data/models/shop.dart';
import 'package:telima/providers/shop_providers.dart';

Map<String, dynamic> _shopJson() => {
      'id': 's1',
      'slug': 'mode-d-awa',
      'name': 'Mode d’Awa',
      'shop_type': 'Vêtements femme',
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
        {'id': 'c1', 'name': 'Robes'},
        {'id': 'c2', 'name': 'Accessoires'},
      ],
      'items': [
        {
          'id': 'p1',
          'category_id': 'c1',
          'name': 'Robe wax',
          'price': 15000,
          'is_available': true,
          'sizes': ['S', 'M', 'L'],
          'colors': ['Rouge', 'Bleu'],
          'stock': 5,
        },
        {'id': 'p2', 'category_id': 'c2', 'name': 'Foulard', 'price': 2500, 'is_available': true},
        {'id': 'p3', 'category_id': null, 'name': 'Sac brodé', 'price': 9000, 'is_available': true, 'stock': 0},
        {'id': 'p4', 'category_id': 'c2', 'name': 'Collier', 'price': 3000, 'is_available': true, 'stock': 2},
      ],
    };

void main() {
  test('le lien partagé pointe vers la page publique de la boutique', () {
    expect(shopShareLink('mode-d-awa'), 'https://telimatchi.com/b/mode-d-awa');
  });

  test('une boutique est lue depuis la réponse du serveur', () {
    final s = Shop(_shopJson());
    expect(s.name, 'Mode d’Awa');
    expect(s.subtitle, 'Vêtements femme · Secteur 15');
    expect(s.minOrder, 1000);
    expect(s.prepMinutes, 25);
    expect(s.suspended, isFalse);
    expect(s.items.length, 4);
  });

  test('un article lit ses tailles, ses couleurs et son stock', () {
    final robe = Shop(_shopJson()).items.first;
    expect(robe.sizes, ['S', 'M', 'L']);
    expect(robe.colors, ['Rouge', 'Bleu']);
    expect(robe.stock, 5);
    expect(robe.needsChoice, isTrue);
    expect(robe.inStock, isTrue);
    expect(robe.lowStock, isFalse);
  });

  test('stock : épuisé à zéro, « plus que… » quand il en reste peu, non suivi sans quantité', () {
    final items = Shop(_shopJson()).items;
    final foulard = items[1], sac = items[2], collier = items[3];
    expect(foulard.stock, isNull);
    expect(foulard.inStock, isTrue);
    expect(foulard.needsChoice, isFalse);
    expect(sac.inStock, isFalse);
    expect(collier.inStock, isTrue);
    expect(collier.lowStock, isTrue);
  });

  test('un article marqué indisponible n’est pas vendable même avec du stock', () {
    final j = _shopJson();
    (j['items'] as List)[0]['is_available'] = false;
    expect(Shop(j).items.first.inStock, isFalse);
  });

  test('le catalogue est regroupé par catégorie, les articles sans catégorie en premier', () {
    final sections = Shop(_shopJson()).sections;
    expect(sections.map((s) => s.name), ['Autres articles', 'Robes', 'Accessoires']);
    expect(sections.first.items.single.name, 'Sac brodé');
  });

  test('un catalogue sans catégorie s’appelle simplement « Catalogue »', () {
    final j = _shopJson()..['categories'] = [];
    expect(Shop(j).sections.first.name, 'Catalogue');
  });

  group('panier', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test('ajouter, retirer et totaliser', () {
      final s = Shop(_shopJson());
      final cart = c.read(cartProvider.notifier);
      cart.add('s1', 'p2');
      cart.add('s1', 'p2');
      cart.add('s1', 'p1', size: 'M', color: 'Rouge');
      expect(c.read(cartProvider).count, 3);
      expect(c.read(cartProvider).total(s), 2500 * 2 + 15000);
      cart.removeOneOf('p2');
      expect(c.read(cartProvider).quantityOf('p2'), 1);
      cart.removeOneOf('p2');
      cart.remove(CartState.keyOf('p1', 'M', 'Rouge'));
      expect(c.read(cartProvider).isEmpty, isTrue);
      expect(c.read(cartProvider).shopId, isNull);
    });

    test('une même robe en deux tailles fait deux lignes', () {
      final cart = c.read(cartProvider.notifier);
      cart.add('s1', 'p1', size: 'M', color: 'Rouge');
      cart.add('s1', 'p1', size: 'M', color: 'Rouge');
      cart.add('s1', 'p1', size: 'L', color: 'Rouge');
      final s = c.read(cartProvider);
      expect(s.lines.length, 2);
      expect(s.quantityOf('p1'), 3);
      expect(s.lineQty(CartState.keyOf('p1', 'M', 'Rouge')), 2);
      expect(s.lineQty(CartState.keyOf('p1', 'L', 'Rouge')), 1);
    });

    test('les lignes envoyées au serveur portent la taille et la couleur', () {
      final cart = c.read(cartProvider.notifier);
      cart.add('s1', 'p1', size: 'S', color: 'Bleu');
      cart.add('s1', 'p2');
      final items = c.read(cartProvider).toOrderItems();
      expect(items.length, 2);
      expect(items.first, {'item_id': 'p1', 'qty': 1, 'size': 'S', 'color': 'Bleu'});
      expect(items.last, {'item_id': 'p2', 'qty': 1});
    });

    test('le panier ne mélange jamais deux boutiques', () {
      final cart = c.read(cartProvider.notifier);
      cart.add('s1', 'p2');
      cart.add('s2', 'x1');
      final s = c.read(cartProvider);
      expect(s.shopId, 's2');
      expect(s.lines.values.map((l) => l.itemId), ['x1']);
    });

    test('la quantité est limitée par le stock, toutes variantes confondues', () {
      final cart = c.read(cartProvider.notifier);
      for (var i = 0; i < 4; i++) {
        cart.add('s1', 'p4', maxQty: 2);
      }
      expect(c.read(cartProvider).quantityOf('p4'), 2);
      cart.add('s1', 'p1', size: 'S', color: 'Rouge', maxQty: 3);
      cart.add('s1', 'p1', size: 'M', color: 'Rouge', maxQty: 3);
      cart.add('s1', 'p1', size: 'L', color: 'Rouge', maxQty: 3);
      cart.add('s1', 'p1', size: 'L', color: 'Bleu', maxQty: 3);
      expect(c.read(cartProvider).quantityOf('p1'), 3);
    });

    test('quantité limitée à 50 par article', () {
      final cart = c.read(cartProvider.notifier);
      for (var i = 0; i < 60; i++) {
        cart.add('s1', 'p2');
      }
      expect(c.read(cartProvider).quantityOf('p2'), 50);
    });
  });

  test('une commande lue du serveur propose les bonnes étapes', () {
    ShopOrder order(String mode, String status) => ShopOrder({
          'id': 'o1',
          'code': 'BOU-0001',
          'shop_id': 's1',
          'mode': mode,
          'status': status,
          'customer_name': 'Ali',
          'customer_phone': '+22670000000',
          'items_total': 30000,
          'delivery_fee': mode == 'delivery' ? 500 : 0,
          'total': mode == 'delivery' ? 30500 : 30000,
          'payment_status': 'unpaid',
          'shops': {'name': 'Mode d’Awa', 'slug': 'mode-d-awa', 'lat': 11.17, 'lng': -4.29},
          'shop_order_items': [
            {'name': 'Robe wax', 'qty': 2, 'unit_price': 15000, 'size': 'M', 'color': 'Rouge'},
            {'name': 'Foulard', 'qty': 1, 'unit_price': 2500},
          ],
        });
    expect(order('pickup', 'ready').steps.map((s) => s.$1), ['sent', 'accepted', 'preparing', 'ready', 'delivered']);
    expect(order('delivery', 'ready').steps.map((s) => s.$1),
        ['sent', 'accepted', 'preparing', 'ready', 'out_for_delivery', 'delivered']);
    expect(order('pickup', 'ready').statusLabel, 'Prête à retirer');
    expect(order('delivery', 'delivered').statusLabel, 'Livrée');
    expect(order('delivery', 'sent').isOpen, isTrue);
    expect(order('delivery', 'rejected').isOpen, isFalse);
    expect(order('pickup', 'sent').shopName, 'Mode d’Awa');
  });

  test('une ligne de commande affiche la taille et la couleur choisies', () {
    final o = ShopOrder({
      'id': 'o2',
      'code': 'BOU-0002',
      'shop_id': 's1',
      'mode': 'pickup',
      'status': 'sent',
      'customer_name': 'Ali',
      'customer_phone': '+22670000000',
      'items_total': 32500,
      'total': 32500,
      'payment_status': 'unpaid',
      'shop_order_items': [
        {'name': 'Robe wax', 'qty': 2, 'unit_price': 15000, 'size': 'M', 'color': 'Rouge'},
        {'name': 'Foulard', 'qty': 1, 'unit_price': 2500},
      ],
    });
    expect(o.items.first.text, '2 × Robe wax (Taille M · Rouge)');
    expect(o.items.first.variant, 'Taille M · Rouge');
    expect(o.items.last.text, '1 × Foulard');
  });

  test('un article lit ses photos, sa vidéo et sa note', () {
    final j = _shopJson();
    final first = (j['items'] as List)[0] as Map;
    first['photo_path'] = 'u/1.jpg';
    first['photos'] = ['u/2.jpg', 'u/1.jpg', 'u/3.jpg'];
    first['video_path'] = 'u/v.mp4';
    first['rating_avg'] = 4.5;
    first['rating_count'] = 2;
    j['rating_avg'] = 3.5;
    j['rating_count'] = 4;
    final shop = Shop(j);
    final robe = shop.items.first;
    expect(robe.galleryPaths, ['u/1.jpg', 'u/2.jpg', 'u/3.jpg']);
    expect(robe.videoUrl, contains('/telima-boutiques/u/v.mp4'));
    expect(robe.ratingAvg, 4.5);
    expect(robe.ratingCount, 2);
    expect(shop.ratingAvg, 3.5);
    expect(shop.ratingCount, 4);
    expect(shop.items[1].galleryPaths, isEmpty);
    expect(shop.items[1].ratingCount, 0);
  });

  test('un avis est lu depuis la réponse du serveur', () {
    final r = ShopReview({'id': 'r1', 'rating': 5, 'comment': 'Superbe', 'author': 'Awa', 'created_at': '2026-10-12T10:00:00Z', 'mine': true});
    expect(r.rating, 5);
    expect(r.author, 'Awa');
    expect(r.mine, isTrue);
    expect(r.createdAt, isNotNull);
  });
}
