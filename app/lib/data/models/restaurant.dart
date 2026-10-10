import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../config/env.dart';
import '../../config/theme.dart';
import '../../core/services/storage_service.dart';
import 'json.dart';

/// Adresse publique d'une photo du compartiment « restaurants » (lisible sans compte).
String? restaurantPhotoUrl(String? path) {
  if (path == null || path.isEmpty) return null;
  return '${Env.supabaseUrl}/storage/v1/object/public/${StorageService.bucket('restaurants')}/$path';
}

/// Site public de Telima (même domaine que la page de téléchargement).
const kSiteUrl = 'https://telimatchi.com';

/// Lien à partager avec les clients. L'application Web utilise les adresses avec « # »
/// (aucune configuration du serveur d'hébergement n'est nécessaire).
String restaurantShareLink(String slug) => '$kSiteUrl/#/r/$slug';

class Restaurant {
  Restaurant(Json j)
      : id = '${j['id']}',
        slug = '${j['slug']}',
        name = '${j['name']}',
        description = asStr(j['description']),
        cuisine = asStr(j['cuisine']),
        phone = asStr(j['phone']),
        neighborhood = asStr(j['neighborhood']),
        address = asStr(j['address']),
        position = LatLng(asDouble(j['lat']) ?? 0, asDouble(j['lng']) ?? 0),
        logoPath = asStr(j['logo_path']),
        coverPath = asStr(j['cover_path']),
        hours = asStr(j['opening_hours']),
        acceptingOrders = asBool(j['accepting_orders'], true),
        acceptsPickup = asBool(j['accepts_pickup'], true),
        delivers = asBool(j['delivers'], true),
        deliveryRadiusKm = asDouble(j['delivery_radius_km']) ?? 0,
        minOrder = asInt(j['min_order']),
        prepMinutes = asInt(j['prep_minutes'], 20),
        status = asStr(j['status']) ?? 'approved',
        ownerId = asStr(j['owner_id']),
        distanceKm = asDouble(j['distance_km']),
        categories = [for (final c in (j['categories'] as List? ?? const [])) MenuCategory(Map<String, dynamic>.from(c as Map))],
        items = [for (final i in (j['items'] as List? ?? const [])) MenuItem(Map<String, dynamic>.from(i as Map))];

  final String id;
  final String slug;
  final String name;
  final String? description;
  final String? cuisine;
  final String? phone;
  final String? neighborhood;
  final String? address;
  final LatLng position;
  final String? logoPath;
  final String? coverPath;
  final String? hours;
  final bool acceptingOrders;
  final bool acceptsPickup;
  final bool delivers;
  final double deliveryRadiusKm;
  final int minOrder;
  final int prepMinutes;
  final String status;
  final String? ownerId;
  final double? distanceKm;
  final List<MenuCategory> categories;
  final List<MenuItem> items;

  String get subtitle => [if ((cuisine ?? '').isNotEmpty) cuisine!, if ((neighborhood ?? '').isNotEmpty) neighborhood!].join(' · ');
  String? get logoUrl => restaurantPhotoUrl(logoPath);
  String? get coverUrl => restaurantPhotoUrl(coverPath);
  bool get suspended => status != 'approved';

  /// Plats regroupés par catégorie, dans l'ordre du menu. Les plats sans catégorie viennent en premier (« Menu »).
  List<({String? id, String name, List<MenuItem> items})> get sections {
    final out = <({String? id, String name, List<MenuItem> items})>[];
    final loose = [for (final i in items) if (i.categoryId == null || !categories.any((c) => c.id == i.categoryId)) i];
    if (loose.isNotEmpty) out.add((id: null, name: categories.isEmpty ? 'Menu' : 'Autres plats', items: loose));
    for (final c in categories) {
      final list = [for (final i in items) if (i.categoryId == c.id) i];
      if (list.isNotEmpty) out.add((id: c.id, name: c.name, items: list));
    }
    return out;
  }
}

class MenuCategory {
  MenuCategory(Json j)
      : id = '${j['id']}',
        name = '${j['name']}',
        sortOrder = asInt(j['sort_order']);
  final String id;
  final String name;
  final int sortOrder;
}

class MenuItem {
  MenuItem(Json j)
      : id = '${j['id']}',
        categoryId = asStr(j['category_id']),
        name = '${j['name']}',
        description = asStr(j['description']),
        price = asInt(j['price']),
        photoPath = asStr(j['photo_path']),
        isAvailable = asBool(j['is_available'], true);
  final String id;
  final String? categoryId;
  final String name;
  final String? description;
  final int price;
  final String? photoPath;
  final bool isAvailable;

  String? get photoUrl => restaurantPhotoUrl(photoPath);
}

class RestaurantOrderItem {
  RestaurantOrderItem(Json j)
      : name = '${j['name']}',
        qty = asInt(j['qty'], 1),
        unitPrice = asInt(j['unit_price']),
        note = asStr(j['note']);
  final String name;
  final int qty;
  final int unitPrice;
  final String? note;

  String get text => '$qty × $name';
}

class RestaurantOrder {
  RestaurantOrder(Json j)
      : id = '${j['id']}',
        code = '${j['code']}',
        restaurantId = '${j['restaurant_id']}',
        customerId = asStr(j['customer_id']),
        restaurantName = asStr((j['restaurants'] as Map?)?['name']),
        restaurantPhone = asStr((j['restaurants'] as Map?)?['phone']),
        restaurantSlug = asStr((j['restaurants'] as Map?)?['slug']),
        restaurantPosition = (j['restaurants'] as Map?) == null
            ? null
            : LatLng(asDouble((j['restaurants'] as Map)['lat']) ?? 0, asDouble((j['restaurants'] as Map)['lng']) ?? 0),
        mode = '${j['mode']}',
        status = '${j['status']}',
        customerName = '${j['customer_name']}',
        customerPhone = '${j['customer_phone']}',
        note = asStr(j['note']),
        dropoffAddress = asStr(j['dropoff_address']),
        itemsTotal = asInt(j['items_total']),
        deliveryFee = asInt(j['delivery_fee']),
        total = asInt(j['total']),
        paymentStatus = '${j['payment_status']}',
        deliveryId = asStr(j['delivery_id']),
        rejectReason = asStr(j['reject_reason']),
        createdAt = asDate(j['created_at']),
        items = [for (final i in (j['restaurant_order_items'] as List? ?? const [])) RestaurantOrderItem(Map<String, dynamic>.from(i as Map))];

  final String id;
  final String code;
  final String restaurantId;
  final String? customerId;
  final String? restaurantName;
  final String? restaurantPhone;
  final String? restaurantSlug;
  final LatLng? restaurantPosition;
  final String mode;
  final String status;
  final String customerName;
  final String customerPhone;
  final String? note;
  final String? dropoffAddress;
  final int itemsTotal;
  final int deliveryFee;
  final int total;
  final String paymentStatus;
  final String? deliveryId;
  final String? rejectReason;
  final DateTime? createdAt;
  final List<RestaurantOrderItem> items;

  bool get isDelivery => mode == 'delivery';
  bool get isOpen => !const {'delivered', 'rejected', 'cancelled'}.contains(status);

  String get statusLabel => switch (status) {
        'sent' => 'Commande envoyée',
        'accepted' => 'Commande acceptée',
        'preparing' => 'En préparation',
        'ready' => isDelivery ? 'Livreur recherché' : 'Prête à retirer',
        'out_for_delivery' => 'Livreur en route',
        'delivered' => isDelivery ? 'Livrée' : 'Retirée',
        'rejected' => 'Refusée',
        'cancelled' => 'Annulée',
        _ => status,
      };

  Color get statusColor => switch (status) {
        'delivered' => AppColors.primary,
        'rejected' || 'cancelled' => AppColors.danger,
        'sent' => AppColors.info,
        _ => AppColors.accent,
      };

  /// Étapes affichées dans le suivi (le retrait n'a pas l'étape livreur).
  List<(String, String)> get steps => [
        ('sent', 'Commande envoyée'),
        ('accepted', 'Commande acceptée'),
        ('preparing', 'En préparation'),
        ('ready', isDelivery ? 'Prête, livreur recherché' : 'Prête à retirer'),
        if (isDelivery) ('out_for_delivery', 'Livreur en route'),
        ('delivered', isDelivery ? 'Livrée' : 'Retirée'),
      ];
}
