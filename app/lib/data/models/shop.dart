import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../config/env.dart';
import '../../config/theme.dart';
import '../../core/services/storage_service.dart';
import 'json.dart';
import 'restaurant.dart' show kSiteUrl;

/// Adresse publique d'une photo du compartiment « boutiques » (lisible sans compte).
String? shopPhotoUrl(String? path) {
  if (path == null || path.isEmpty) return null;
  return '${Env.supabaseUrl}/storage/v1/object/public/${StorageService.bucket('boutiques')}/$path';
}

/// Lien à partager avec les clients. Adresse sans « # » : elle ouvre l'application Android (liens profonds)
/// et le site web. Le serveur d'hébergement doit renvoyer index.html pour /b/* (voir scripts/deploy_lws.py --htaccess).
String shopShareLink(String slug) => '$kSiteUrl/b/$slug';

class Shop {
  Shop(Json j)
      : id = '${j['id']}',
        slug = '${j['slug']}',
        name = '${j['name']}',
        description = asStr(j['description']),
        shopType = asStr(j['shop_type']),
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
        ratingAvg = asDouble(j['rating_avg']) ?? 0,
        ratingCount = asInt(j['rating_count']),
        categories = [for (final c in (j['categories'] as List? ?? const [])) ShopCategory(Map<String, dynamic>.from(c as Map))],
        items = [for (final i in (j['items'] as List? ?? const [])) ShopProduct(Map<String, dynamic>.from(i as Map))];

  final String id;
  final String slug;
  final String name;
  final String? description;
  final String? shopType;
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
  final double ratingAvg;
  final int ratingCount;
  final List<ShopCategory> categories;
  final List<ShopProduct> items;

  String get subtitle => [if ((shopType ?? '').isNotEmpty) shopType!, if ((neighborhood ?? '').isNotEmpty) neighborhood!].join(' · ');
  String? get logoUrl => shopPhotoUrl(logoPath);
  String? get coverUrl => shopPhotoUrl(coverPath);
  bool get suspended => status != 'approved';

  /// Articles regroupés par catégorie, dans l'ordre du catalogue. Les articles sans catégorie viennent en premier (« Catalogue »).
  List<({String? id, String name, List<ShopProduct> items})> get sections {
    final out = <({String? id, String name, List<ShopProduct> items})>[];
    final loose = [for (final i in items) if (i.categoryId == null || !categories.any((c) => c.id == i.categoryId)) i];
    if (loose.isNotEmpty) out.add((id: null, name: categories.isEmpty ? 'Catalogue' : 'Autres articles', items: loose));
    for (final c in categories) {
      final list = [for (final i in items) if (i.categoryId == c.id) i];
      if (list.isNotEmpty) out.add((id: c.id, name: c.name, items: list));
    }
    return out;
  }
}

class ShopCategory {
  ShopCategory(Json j)
      : id = '${j['id']}',
        name = '${j['name']}',
        sortOrder = asInt(j['sort_order']);
  final String id;
  final String name;
  final int sortOrder;
}

class ShopProduct {
  ShopProduct(Json j)
      : id = '${j['id']}',
        categoryId = asStr(j['category_id']),
        name = '${j['name']}',
        description = asStr(j['description']),
        price = asInt(j['price']),
        photoPath = asStr(j['photo_path']),
        isAvailable = asBool(j['is_available'], true),
        sizes = [for (final x in (j['sizes'] as List? ?? const [])) '$x'],
        colors = [for (final x in (j['colors'] as List? ?? const [])) '$x'],
        stock = j['stock'] == null ? null : asInt(j['stock']),
        extraPhotos = [for (final x in (j['photos'] as List? ?? const [])) '$x'],
        videoPath = asStr(j['video_path']),
        ratingAvg = asDouble(j['rating_avg']) ?? 0,
        ratingCount = asInt(j['rating_count']);
  final String id;
  final String? categoryId;
  final String name;
  final String? description;
  final int price;
  final String? photoPath;
  final bool isAvailable;

  /// Tailles et couleurs proposées (vide = pas de choix). [stock] null = quantité non suivie.
  final List<String> sizes;
  final List<String> colors;
  final int? stock;

  /// Photos supplémentaires (la photo principale est [photoPath]), vidéo de présentation et note moyenne.
  final List<String> extraPhotos;
  final String? videoPath;
  final double ratingAvg;
  final int ratingCount;

  String? get photoUrl => shopPhotoUrl(photoPath);
  String? get videoUrl => shopPhotoUrl(videoPath);

  /// Toutes les photos de l'article, la principale en premier.
  List<String> get galleryPaths => [
        if (photoPath != null && photoPath!.isNotEmpty) photoPath!,
        for (final p in extraPhotos) if (p != photoPath) p,
      ];

  /// Vendable : marqué disponible et pas en rupture de stock.
  bool get inStock => isAvailable && (stock == null || stock! > 0);
  bool get lowStock => stock != null && stock! > 0 && stock! <= 3;
  bool get needsChoice => sizes.isNotEmpty || colors.isNotEmpty;
}

class ShopOrderItem {
  ShopOrderItem(Json j)
      : name = '${j['name']}',
        qty = asInt(j['qty'], 1),
        unitPrice = asInt(j['unit_price']),
        size = asStr(j['size']),
        color = asStr(j['color']),
        note = asStr(j['note']);
  final String name;
  final int qty;
  final int unitPrice;
  final String? size;
  final String? color;
  final String? note;

  /// « Taille M · Rouge » (vide si l'article n'a ni taille ni couleur).
  String get variant => [if ((size ?? '').isNotEmpty) 'Taille $size', if ((color ?? '').isNotEmpty) color!].join(' · ');

  String get text => variant.isEmpty ? '$qty × $name' : '$qty × $name ($variant)';
}

class ShopOrder {
  ShopOrder(Json j)
      : id = '${j['id']}',
        code = '${j['code']}',
        shopId = '${j['shop_id']}',
        customerId = asStr(j['customer_id']),
        shopName = asStr((j['shops'] as Map?)?['name']),
        shopPhone = asStr((j['shops'] as Map?)?['phone']),
        shopSlug = asStr((j['shops'] as Map?)?['slug']),
        shopPosition = (j['shops'] as Map?) == null
            ? null
            : LatLng(asDouble((j['shops'] as Map)['lat']) ?? 0, asDouble((j['shops'] as Map)['lng']) ?? 0),
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
        items = [for (final i in (j['shop_order_items'] as List? ?? const [])) ShopOrderItem(Map<String, dynamic>.from(i as Map))];

  final String id;
  final String code;
  final String shopId;
  final String? customerId;
  final String? shopName;
  final String? shopPhone;
  final String? shopSlug;
  final LatLng? shopPosition;
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
  final List<ShopOrderItem> items;

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

/// Avis d'un client sur une boutique ou un article.
class ShopReview {
  ShopReview(Json j)
      : id = '${j['id']}',
        rating = asInt(j['rating']),
        comment = asStr(j['comment']),
        author = asStr(j['author']) ?? 'Client',
        createdAt = DateTime.tryParse('${j['created_at']}')?.toLocal(),
        mine = asBool(j['mine'], false);
  final String id;
  final int rating;
  final String? comment;
  final String author;
  final DateTime? createdAt;
  final bool mine;
}
