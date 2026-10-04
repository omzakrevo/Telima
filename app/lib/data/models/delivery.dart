import 'package:latlong2/latlong.dart';

import 'enums.dart';
import 'json.dart';

/// Point de récupération ou de destination saisi par le client.
class DeliveryPoint {
  DeliveryPoint({
    required this.address,
    required this.lat,
    required this.lng,
    this.contactName = '',
    this.contactPhone = '',
    this.instructions = '',
  });

  String address;
  double lat;
  double lng;
  String contactName;
  String contactPhone;
  String instructions;

  LatLng get latLng => LatLng(lat, lng);

  Json toJson() => {
        'address': address,
        'lat': lat,
        'lng': lng,
        'contact_name': contactName,
        'contact_phone': contactPhone,
        'instructions': instructions,
      };

  DeliveryPoint copy() => DeliveryPoint(
      address: address,
      lat: lat,
      lng: lng,
      contactName: contactName,
      contactPhone: contactPhone,
      instructions: instructions);
}

class PackageInfo {
  PackageInfo({
    this.category = PackageCategory.petit_colis,
    this.description = '',
    this.photoPath,
    this.quantity = 1,
    this.fragile = false,
    this.size = PackageSize.petit,
    this.weightKg,
  });

  PackageCategory category;
  String description;
  String? photoPath;
  int quantity;
  bool fragile;
  PackageSize size;
  double? weightKg;

  Json toJson() => {
        'category': category.name,
        'description': description,
        'photo_path': photoPath,
        'quantity': quantity,
        'fragile': fragile,
        'size': size.name,
        'weight_kg': weightKg,
      };
}

/// Devis calculé par le serveur (public.quote_delivery).
class Quote {
  Quote(this.raw);
  final Json raw;

  double get distanceKm => asDouble(raw['distance_km']) ?? 0;
  VehicleType get vehicleType => VehicleType.parse(raw['vehicle_type'] as String?);
  VehicleType get suggestedVehicle => VehicleType.parse(raw['suggested_vehicle'] as String?);
  int get priceBase => asInt(raw['price_base']);
  int get priceDistance => asInt(raw['price_distance']);
  int get priceExtras => asInt(raw['price_extras']);
  int get priceZone => asInt(raw['price_zone']);
  int get total => asInt(raw['total_price']);
  String? get zoneName => raw['zone_name'] as String?;
}

class Delivery {
  Delivery(this.raw);
  final Json raw;

  factory Delivery.fromJson(Json j) => Delivery(j);

  String get id => raw['id'] as String;
  String get code => raw['code'] as String? ?? '';
  DeliveryStatus get status => DeliveryStatus.parse(raw['status'] as String?);
  String? get customerId => raw['customer_id'] as String?;
  String get customerName => raw['customer_name'] as String? ?? '';
  String get customerPhone => raw['customer_phone'] as String? ?? '';
  String? get businessId => raw['business_id'] as String?;
  String get createdVia => raw['created_via'] as String? ?? 'app';
  String? get driverId => raw['driver_id'] as String?;
  VehicleType get vehicleType => VehicleType.parse(raw['vehicle_type'] as String?);
  String? get cityId => raw['city_id'] as String?;
  String? get batchId => raw['batch_id'] as String?;
  int get stopOrder => asInt(raw['stop_order'], 1);

  String get pickupAddress => raw['pickup_address'] as String? ?? '';
  LatLng get pickup => LatLng(asDouble(raw['pickup_lat']) ?? 0, asDouble(raw['pickup_lng']) ?? 0);
  String get pickupContactName => raw['pickup_contact_name'] as String? ?? '';
  String get pickupContactPhone => raw['pickup_contact_phone'] as String? ?? '';
  String? get pickupInstructions => raw['pickup_instructions'] as String?;

  String get dropoffAddress => raw['dropoff_address'] as String? ?? '';
  LatLng get dropoff => LatLng(asDouble(raw['dropoff_lat']) ?? 0, asDouble(raw['dropoff_lng']) ?? 0);
  String get dropoffContactName => raw['dropoff_contact_name'] as String? ?? '';
  String get dropoffContactPhone => raw['dropoff_contact_phone'] as String? ?? '';
  String? get dropoffInstructions => raw['dropoff_instructions'] as String?;

  PackageCategory get packageCategory => PackageCategory.parse(raw['package_category'] as String?);
  String? get packageDescription => raw['package_description'] as String?;
  String? get packagePhotoPath => raw['package_photo_path'] as String?;
  int get packageQuantity => asInt(raw['package_quantity'], 1);
  bool get packageFragile => asBool(raw['package_fragile']);
  PackageSize get packageSize => PackageSize.parse(raw['package_size'] as String?);
  double? get packageWeightKg => asDouble(raw['package_weight_kg']);

  double get distanceKm => asDouble(raw['distance_km']) ?? 0;
  int get priceBase => asInt(raw['price_base']);
  int get priceDistance => asInt(raw['price_distance']);
  int get priceExtras => asInt(raw['price_extras']);
  int get priceZone => asInt(raw['price_zone']);
  int get totalPrice => asInt(raw['total_price']);
  int get commissionAmount => asInt(raw['commission_amount']);
  int get driverEarning => asInt(raw['driver_earning']);

  PaymentMethod get paymentMethod => PaymentMethod.parse(raw['payment_method'] as String?);
  PaymentStatus get paymentStatus => PaymentStatus.parse(raw['payment_status'] as String?);

  ProofType? get proofType => ProofType.tryParse(raw['proof_type'] as String?);
  String? get proofPhotoPath => raw['proof_photo_path'] as String?;
  String? get proofSignaturePath => raw['proof_signature_path'] as String?;
  String? get receiverName => raw['receiver_name'] as String?;

  int? get etaMinutes => raw['eta_minutes'] == null ? null : asInt(raw['eta_minutes']);
  String? get cancelReason => raw['cancel_reason'] as String?;
  DateTime? get createdAt => asDate(raw['created_at']);
  DateTime? get assignedAt => asDate(raw['assigned_at']);
  DateTime? get pickedUpAt => asDate(raw['picked_up_at']);
  DateTime? get completedAt => asDate(raw['completed_at']);
  DateTime? get cancelledAt => asDate(raw['cancelled_at']);

  /// Champs embarqués éventuels (vue administrateur).
  Json? get driverUser => (raw['driver'] is Map) ? (raw['driver'] as Map)['users'] as Json? : null;
  String? get driverName => driverUser?['full_name'] as String?;

  bool get isBatch => batchId != null;

  // ---- Type de commande : colis, course à faire (achats) ou transport de personnes ----
  String get kind => raw['kind'] as String? ?? 'parcel';
  bool get isErrand => kind == 'errand';
  bool get isRide => kind == 'ride';
  String? get errandItems => raw['errand_items'] as String?;
  String? get errandCategory => raw['errand_category'] as String?;
  int? get errandBudget => raw['errand_budget'] == null ? null : asInt(raw['errand_budget']);
  int? get purchaseAmount => raw['purchase_amount'] == null ? null : asInt(raw['purchase_amount']);
  String? get purchaseShop => raw['purchase_shop'] as String?;
  String? get purchaseReceiptPath => raw['purchase_receipt_path'] as String?;
  String? get purchaseSettlement => raw['purchase_settlement'] as String?;
  bool get purchaseSettled => raw['purchase_settled_at'] != null;
  int get ridePassengers => asInt(raw['ride_passengers'], 1);

  /// Libellé d'étape adapté au type de commande.
  String statusLabel() => kindStatusLabel(kind, status);
}

/// Libellés d'étapes : un trajet transporte un passager, une course à faire commence par des achats.
String kindStatusLabel(String kind, DeliveryStatus s) => switch ((kind, s)) {
      ('ride', DeliveryStatus.to_pickup) => 'Chauffeur en route',
      ('ride', DeliveryStatus.at_pickup) => 'Chauffeur arrivé',
      ('ride', DeliveryStatus.picked_up) => 'Passager à bord',
      ('ride', DeliveryStatus.in_transit) => 'Trajet en cours',
      ('ride', DeliveryStatus.at_dropoff) => 'Arrivé à destination',
      ('ride', DeliveryStatus.completed) => 'Trajet terminé',
      ('errand', DeliveryStatus.to_pickup) => 'Livreur en route vers le commerce',
      ('errand', DeliveryStatus.at_pickup) => 'Achats en cours',
      ('errand', DeliveryStatus.picked_up) => 'Achats effectués',
      ('errand', DeliveryStatus.in_transit) => 'En route vers vous',
      _ => s.label,
    };

/// Bouton d'étape du livreur / chauffeur selon le type de commande.
String driverActionLabelFor(String kind, DeliveryStatus s) => switch ((kind, s)) {
      ('ride', DeliveryStatus.assigned) => 'Je pars chercher le passager',
      ('ride', DeliveryStatus.to_pickup) => 'Je suis au point de départ',
      ('ride', DeliveryStatus.at_pickup) => 'Passager à bord',
      ('ride', DeliveryStatus.picked_up) => 'Démarrer le trajet',
      ('ride', DeliveryStatus.in_transit) => 'Arrivé à destination',
      ('ride', DeliveryStatus.at_dropoff) => 'Terminer le trajet',
      ('errand', DeliveryStatus.assigned) => 'Je pars faire les achats',
      ('errand', DeliveryStatus.to_pickup) => 'Je suis au commerce',
      ('errand', DeliveryStatus.at_pickup) => 'Achats terminés',
      ('errand', DeliveryStatus.picked_up) => 'Je pars livrer',
      ('errand', DeliveryStatus.in_transit) => 'Arrivé chez le client',
      ('errand', DeliveryStatus.at_dropoff) => 'Remettre les achats',
      _ => s.driverActionLabel,
    };

/// Catégories d'une course à faire.
const errandCategories = <(String, String)>[
  ('repas', 'Repas'),
  ('pharmacie', 'Pharmacie'),
  ('marche', 'Marché'),
  ('boutique', 'Boutique'),
  ('autre', 'Autre'),
];
String errandCategoryLabel(String? c) => errandCategories.firstWhere((e) => e.$1 == c, orElse: () => ('autre', 'Autre')).$2;

class StatusHistoryEntry {
  StatusHistoryEntry(this.status, this.createdAt, this.note);
  final DeliveryStatus status;
  final DateTime? createdAt;
  final String? note;

  factory StatusHistoryEntry.fromJson(Json j) =>
      StatusHistoryEntry(DeliveryStatus.parse(j['status'] as String?), asDate(j['created_at']), j['note'] as String?);
}

/// Livreur tel qu'affiché au client (public.get_delivery_driver).
class AssignedDriver {
  AssignedDriver(this.raw);
  final Json raw;

  String get firstName => raw['first_name'] as String? ?? '';
  String get fullName => raw['full_name'] as String? ?? '';
  String get phone => raw['phone'] as String? ?? '';
  String? get avatarUrl => raw['avatar_url'] as String?;
  double get rating => asDouble(raw['rating_avg']) ?? 0;
  int get ratingCount => asInt(raw['rating_count']);
  VehicleType get vehicleType => VehicleType.parse(raw['vehicle_type'] as String?);
  String get vehicleLabel => (raw['vehicle_label'] as String? ?? '').trim();
  String? get plateNumber => raw['plate_number'] as String?;
  LatLng? get position {
    final lat = asDouble(raw['lat']);
    final lng = asDouble(raw['lng']);
    return (lat == null || lng == null) ? null : LatLng(lat, lng);
  }

  int? get etaMinutes => raw['eta_minutes'] == null ? null : asInt(raw['eta_minutes']);
}

/// Demande disponible côté livreur (public.get_available_requests).
class AvailableRequest {
  AvailableRequest(this.raw);
  final Json raw;

  String get id => raw['id'] as String;
  String get code => raw['code'] as String? ?? '';
  VehicleType get vehicleType => VehicleType.parse(raw['vehicle_type'] as String?);
  String get pickupAddress => raw['pickup_address'] as String? ?? '';
  String get dropoffAddress => raw['dropoff_address'] as String? ?? '';
  LatLng get pickup => LatLng(asDouble(raw['pickup_lat']) ?? 0, asDouble(raw['pickup_lng']) ?? 0);
  LatLng get dropoff => LatLng(asDouble(raw['dropoff_lat']) ?? 0, asDouble(raw['dropoff_lng']) ?? 0);
  PackageCategory get category => PackageCategory.parse(raw['package_category'] as String?);
  PackageSize get size => PackageSize.parse(raw['package_size'] as String?);
  bool get fragile => asBool(raw['package_fragile']);
  int get quantity => asInt(raw['package_quantity'], 1);
  double get distanceKm => asDouble(raw['distance_km']) ?? 0;
  int get totalPrice => asInt(raw['total_price']);
  int get earning => asInt(raw['driver_earning']);
  PaymentMethod get paymentMethod => PaymentMethod.parse(raw['payment_method'] as String?);
  double get distanceToPickupKm => asDouble(raw['distance_to_pickup_km']) ?? 0;
  int get stopsCount => asInt(raw['stops_count'], 1);
  int get batchEarning => asInt(raw['batch_total_earning']);
  String get kind => raw['kind'] as String? ?? 'parcel';
  String? get errandItems => raw['errand_items'] as String?;
  String? get errandCategory => raw['errand_category'] as String?;
  int? get errandBudget => raw['errand_budget'] == null ? null : asInt(raw['errand_budget']);
  int get ridePassengers => asInt(raw['ride_passengers'], 1);
}

class ChatMessage {
  ChatMessage({required this.id, required this.senderId, required this.body, this.createdAt, this.readAt});
  final int id;
  final String senderId;
  final String body;
  final DateTime? createdAt;
  final DateTime? readAt;

  factory ChatMessage.fromJson(Json j) => ChatMessage(
        id: asInt(j['id']),
        senderId: j['sender_id'] as String,
        body: j['body'] as String? ?? '',
        createdAt: asDate(j['created_at']),
        readAt: asDate(j['read_at']),
      );
}
