import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../config/theme.dart';
import 'json.dart';

/// Disponibilité d'un produit ou d'un carburant.
enum Availability {
  available('Disponible', AppColors.primary, Icons.check_circle_rounded),
  low('Stock faible', AppColors.accent, Icons.error_rounded),
  out('Rupture', AppColors.danger, Icons.cancel_rounded),
  unknown('Non renseigné', AppColors.textMuted, Icons.help_rounded);

  const Availability(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;

  static Availability parse(dynamic v) =>
      Availability.values.firstWhere((e) => e.name == '$v', orElse: () => Availability.unknown);

  bool get orderable => this == available || this == low;
}

/// Une information de disponibilité de plus de 6 h est affichée comme ancienne.
const staleAfter = Duration(hours: 6);

bool isStale(DateTime? confirmedAt) => confirmedAt == null || DateTime.now().difference(confirmedAt.toLocal()) > staleAfter;

/// Statut affiché : une info ancienne devient « à confirmer » (orange), jamais verte.
Availability effectiveAvailability(Availability a, DateTime? confirmedAt) {
  if (a == Availability.unknown) return a;
  if (a == Availability.available && isStale(confirmedAt)) return Availability.low;
  return a;
}

String ageLabel(DateTime? at) {
  if (at == null) return 'jamais confirmé';
  final d = DateTime.now().difference(at.toLocal());
  if (d.inMinutes < 2) return 'à l’instant';
  if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
  if (d.inHours < 24) return 'il y a ${d.inHours} h';
  return 'il y a ${d.inDays} j';
}

class GasBrand {
  GasBrand(Json j)
      : id = '${j['id']}',
        name = '${j['name']}';
  final String id;
  final String name;
}

class PlaceProduct {
  PlaceProduct(Json j)
      : id = '${j['id']}',
        brandId = asStr(j['brand_id']),
        brand = asStr(j['brand']) ?? asStr((j['gas_brands'] as Map?)?['name']) ?? 'Gaz',
        sizeKg = asDouble(j['size_kg']) ?? 0,
        price = asInt(j['price']),
        availability = Availability.parse(j['availability']),
        confirmedAt = asDate(j['confirmed_at']),
        trackStock = asBool(j['track_stock']),
        stock = asInt(j['stock_available']),
        promoPrice = j['promo_price'] == null ? null : asInt(j['promo_price']),
        promoTitle = asStr(j['promo_title']);
  final String id;
  final String? brandId;
  final String brand;
  final double sizeKg;
  final int price;
  final Availability availability;
  final DateTime? confirmedAt;
  final bool trackStock;
  final int stock;
  int? promoPrice;
  String? promoTitle;

  /// Prix réellement payé (promotion comprise).
  int get finalPrice => promoPrice != null && promoPrice! < price ? promoPrice! : price;
  bool get onPromo => finalPrice < price;

  String get sizeLabel => '${sizeKg == sizeKg.roundToDouble() ? sizeKg.toInt() : sizeKg.toString().replaceAll('.', ',')} kg';
  Availability get shown => effectiveAvailability(availability, confirmedAt);
}

class PlaceFuel {
  PlaceFuel(Json j)
      : fuel = '${j['fuel']}',
        availability = Availability.parse(j['availability']),
        price = j['price'] == null ? null : asInt(j['price']),
        confirmedAt = asDate(j['confirmed_at']);
  final String fuel; // essence | gasoil
  final Availability availability;
  final int? price;
  final DateTime? confirmedAt;

  String get label => fuel == 'essence' ? 'Essence' : 'Gasoil';
  Availability get shown => effectiveAvailability(availability, confirmedAt);
}

class Place {
  Place(Json j)
      : id = '${j['id']}',
        isStation = j['kind'] == 'fuel_station',
        name = '${j['name']}',
        brandLabel = asStr(j['brand_label']),
        neighborhood = asStr(j['neighborhood']),
        address = asStr(j['address']),
        position = LatLng(asDouble(j['lat']) ?? 0, asDouble(j['lng']) ?? 0),
        phone = asStr(j['phone']),
        hours = asStr(j['opening_hours']),
        services = [for (final s in (j['services'] as List? ?? const [])) '$s'],
        delivers = asBool(j['delivers']),
        deliveryRadiusKm = asDouble(j['delivery_radius_km']) ?? 0,
        lastConfirmedAt = asDate(j['last_confirmed_at']),
        distanceKm = asDouble(j['distance_km']),
        status = asStr(j['status']) ?? 'approved',
        ownerId = asStr(j['owner_id']),
        ratingAvg = asDouble(j['rating_avg']),
        ratingCount = asInt(j['rating_count']),
        boost = asInt(j['boost']),
        promoTitle = asStr(j['promo_title']),
        isOsm = j['source'] == 'osm',
        products = [for (final p in (j['products'] as List? ?? const [])) PlaceProduct(Map<String, dynamic>.from(p as Map))],
        fuels = [for (final f in (j['fuels'] as List? ?? const [])) PlaceFuel(Map<String, dynamic>.from(f as Map))];

  final String id;
  final bool isStation;
  final String name;
  final String? brandLabel;
  final String? neighborhood;
  final String? address;
  final LatLng position;
  final String? phone;
  final String? hours;
  final List<String> services;
  final bool delivers;
  final double deliveryRadiusKm;
  final DateTime? lastConfirmedAt;
  final double? distanceKm;
  final String status;
  final String? ownerId;
  final double? ratingAvg;
  final int ratingCount;
  final int boost;
  String? promoTitle;
  final bool isOsm;
  final List<PlaceProduct> products;
  final List<PlaceFuel> fuels;

  String get subtitle => [if (brandLabel != null && brandLabel!.isNotEmpty) brandLabel!, if (neighborhood != null && neighborhood!.isNotEmpty) neighborhood!].join(' · ');

  /// Meilleur statut pour la carte : vert si du gaz / du carburant est disponible.
  Availability get summary {
    final all = isStation ? fuels.map((f) => f.shown) : products.map((p) => p.shown);
    final list = all.toList();
    if (list.isEmpty) return Availability.unknown;
    if (list.contains(Availability.available)) return Availability.available;
    if (list.contains(Availability.low)) return Availability.low;
    if (list.every((a) => a == Availability.out)) return Availability.out;
    return Availability.unknown;
  }
}

class GasOrderItem {
  GasOrderItem(Json j)
      : originalPrice = j['original_price'] == null ? null : asInt(j['original_price']),
        label = '${j['label']}',
        sizeKg = asDouble(j['size_kg']) ?? 0,
        qty = asInt(j['qty']),
        unitPrice = asInt(j['unit_price']);
  final String label;
  final double sizeKg;
  final int qty;
  final int unitPrice;
  final int? originalPrice;
  String get text => '$qty × $label ${sizeKg == sizeKg.roundToDouble() ? sizeKg.toInt() : sizeKg.toString().replaceAll('.', ',')} kg';
}

class GasOrder {
  GasOrder(Json j)
      : id = '${j['id']}',
        code = '${j['code']}',
        placeId = '${j['place_id']}',
        placeName = asStr((j['places'] as Map?)?['name']),
        placePhone = asStr((j['places'] as Map?)?['phone']),
        placePosition = (j['places'] as Map?) == null
            ? null
            : LatLng(asDouble((j['places'] as Map)['lat']) ?? 0, asDouble((j['places'] as Map)['lng']) ?? 0),
        mode = '${j['mode']}',
        status = '${j['status']}',
        customerName = '${j['customer_name']}',
        customerPhone = '${j['customer_phone']}',
        dropoffAddress = asStr(j['dropoff_address']),
        itemsTotal = asInt(j['items_total']),
        deliveryFee = asInt(j['delivery_fee']),
        total = asInt(j['total']),
        paymentStatus = '${j['payment_status']}',
        deliveryId = asStr(j['delivery_id']),
        rejectReason = asStr(j['reject_reason']),
        createdAt = asDate(j['created_at']),
        items = [for (final i in (j['gas_order_items'] as List? ?? const [])) GasOrderItem(Map<String, dynamic>.from(i as Map))];

  final String id;
  final String code;
  final String placeId;
  final String? placeName;
  final String? placePhone;
  final LatLng? placePosition;
  final String mode;
  final String status;
  final String customerName;
  final String customerPhone;
  final String? dropoffAddress;
  final int itemsTotal;
  final int deliveryFee;
  final int total;
  final String paymentStatus;
  final String? deliveryId;
  final String? rejectReason;
  final DateTime? createdAt;
  final List<GasOrderItem> items;

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

  /// Étapes affichées dans le suivi (le mode de retrait n'a pas l'étape livreur).
  List<(String, String)> get steps => [
        ('sent', 'Commande envoyée'),
        ('accepted', 'Commande acceptée'),
        ('preparing', 'En préparation'),
        if (isDelivery) ('ready', 'Livreur recherché') else ('ready', 'Prête à retirer'),
        if (isDelivery) ('out_for_delivery', 'Livreur en route'),
        ('delivered', isDelivery ? 'Livrée' : 'Retirée'),
      ];
}

/// Promotion d'un point de vente.
class PlacePromo {
  PlacePromo(Json j)
      : id = '${j['id']}',
        placeId = '${j['place_id']}',
        productId = asStr(j['product_id']),
        title = '${j['title']}',
        percent = j['discount_type'] == 'percent',
        value = asInt(j['discount_value']),
        startsAt = asDate(j['starts_at']),
        endsAt = asDate(j['ends_at']),
        isActive = asBool(j['is_active']);
  final String id;
  final String placeId;
  final String? productId;
  final String title;
  final bool percent;
  final int value;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;

  bool get running {
    final now = DateTime.now();
    return isActive && (startsAt == null || !startsAt!.isAfter(now)) && (endsAt == null || endsAt!.isAfter(now));
  }

  String get label => percent ? '-$value %' : '-$value FCFA';
  int priceFor(int price) => (percent ? (price * (100 - value) / 100).round() : price - value).clamp(0, price);
}

class PlaceReview {
  PlaceReview(Json j)
      : id = '${j['id']}',
        rating = asInt(j['rating']),
        comment = asStr(j['comment']),
        verified = asBool(j['verified']),
        author = asStr(j['author']) ?? 'Client',
        mine = asBool(j['mine']),
        createdAt = asDate(j['created_at']);
  final String id;
  final int rating;
  final String? comment;
  final bool verified;
  final String author;
  final bool mine;
  final DateTime? createdAt;
}

class VendorPlan {
  VendorPlan(Json j)
      : code = '${j['code']}',
        name = '${j['name']}',
        priceMonthly = asInt(j['price_monthly']),
        maxProducts = j['max_products'] == null ? null : asInt(j['max_products']),
        maxPromotions = j['max_promotions'] == null ? null : asInt(j['max_promotions']),
        boost = asInt(j['boost']),
        features = [for (final f in (j['features'] as List? ?? const [])) '$f'];
  final String code;
  final String name;
  final int priceMonthly;
  final int? maxProducts;
  final int? maxPromotions;
  final int boost;
  final List<String> features;
}

class VendorSubscription {
  VendorSubscription(Json j)
      : id = '${j['id']}',
        placeId = '${j['place_id']}',
        placeName = asStr((j['places'] as Map?)?['name']),
        planCode = '${j['plan_code']}',
        months = asInt(j['months']),
        amount = asInt(j['amount']),
        status = '${j['status']}',
        paymentRef = asStr(j['payment_ref']),
        endsAt = asDate(j['ends_at']),
        createdAt = asDate(j['created_at']);
  final String id;
  final String placeId;
  final String? placeName;
  final String planCode;
  final int months;
  final int amount;
  final String status;
  final String? paymentRef;
  final DateTime? endsAt;
  final DateTime? createdAt;

  bool get activeNow => status == 'active' && endsAt != null && endsAt!.isAfter(DateTime.now());
}
