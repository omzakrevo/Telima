import 'enums.dart';
import 'json.dart';
import 'user.dart';

class Vehicle {
  Vehicle(this.raw);
  final Json raw;

  String get id => raw['id'] as String;
  VehicleType get type => VehicleType.parse(raw['type'] as String?);
  String? get brand => raw['brand'] as String?;
  String? get model => raw['model'] as String?;
  String? get color => raw['color'] as String?;
  String? get plateNumber => raw['plate_number'] as String?;
  String? get photoPath => raw['photo_path'] as String?;
  bool get isActive => asBool(raw['is_active'], true);

  String get label => [type.label, brand, model, color].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
}

class DriverProfile {
  DriverProfile(this.raw);
  final Json raw;

  String get userId => raw['user_id'] as String;
  DriverStatus get status => DriverStatus.parse(raw['status'] as String?);
  bool get isOnline => asBool(raw['is_online']);
  String? get cityId => raw['city_id'] as String?;
  String? get idDocumentNumber => raw['id_document_number'] as String?;
  String? get idDocumentPath => raw['id_document_path'] as String?;
  String? get licenseNumber => raw['license_number'] as String?;
  String? get licensePath => raw['license_path'] as String?;
  double get ratingAvg => asDouble(raw['rating_avg']) ?? 0;
  int get ratingCount => asInt(raw['rating_count']);
  int get totalDeliveries => asInt(raw['total_deliveries']);
  double? get lat => asDouble(raw['current_lat']);
  double? get lng => asDouble(raw['current_lng']);
  DateTime? get lastLocationAt => asDate(raw['last_location_at']);
  String? get statusNote => raw['status_note'] as String?;
  DateTime? get createdAt => asDate(raw['created_at']);

  /// Services proposés : parcel (colis), errand (courses à faire), ride (transport de personnes).
  List<String> get services => (raw['services'] as List?)?.map((e) => '$e').toList() ?? const ['parcel', 'errand'];

  /// Présent lorsque la requête embarque users(*) et vehicles(*).
  AppUser? get user => raw['users'] is Map ? AppUser.fromJson(Map<String, dynamic>.from(raw['users'] as Map)) : null;
  List<Vehicle> get vehicles => (raw['vehicles'] as List? ?? [])
      .map((v) => Vehicle(Map<String, dynamic>.from(v as Map)))
      .toList();
  Vehicle? get activeVehicle {
    for (final v in vehicles) {
      if (v.isActive) return v;
    }
    return null;
  }

  bool get hasApplied => (idDocumentNumber ?? '').isNotEmpty;
}

class DriverEarnings {
  DriverEarnings(this.raw);
  final Json raw;

  int get today => asInt(raw['today']);
  int get week => asInt(raw['week']);
  int get month => asInt(raw['month']);
  int get countToday => asInt(raw['count_today']);
  int get countWeek => asInt(raw['count_week']);
  int get countMonth => asInt(raw['count_month']);
  int get countTotal => asInt(raw['count_total']);
  int get commissionMonth => asInt(raw['commission_month']);
  int get commissionTotal => asInt(raw['commission_total']);
  int get earningTotal => asInt(raw['earning_total']);
  int get balance => asInt(raw['balance']);
  int get pendingWithdrawals => asInt(raw['pending_withdrawals']);
}

class Rating {
  Rating(this.raw);
  final Json raw;
  int get stars => asInt(raw['stars']);
  String? get comment => raw['comment'] as String?;
  DateTime? get createdAt => asDate(raw['created_at']);
  String? get deliveryId => raw['delivery_id'] as String?;
}
