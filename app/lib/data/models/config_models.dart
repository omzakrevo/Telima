import 'package:latlong2/latlong.dart';

import 'enums.dart';
import 'json.dart';

class City {
  City(this.raw);
  final Json raw;
  String get id => raw['id'] as String;
  String get name => raw['name'] as String? ?? '';
  LatLng get center => LatLng(asDouble(raw['center_lat']) ?? 0, asDouble(raw['center_lng']) ?? 0);
  double get radiusKm => asDouble(raw['radius_km']) ?? 0;
  bool get isActive => asBool(raw['is_active'], true);
}

class DeliveryZone {
  DeliveryZone(this.raw);
  final Json raw;
  String get id => raw['id'] as String;
  String get cityId => raw['city_id'] as String;
  String get name => raw['name'] as String? ?? '';
  LatLng get center => LatLng(asDouble(raw['center_lat']) ?? 0, asDouble(raw['center_lng']) ?? 0);
  double get radiusKm => asDouble(raw['radius_km']) ?? 0;
  int get extraFee => asInt(raw['extra_fee']);
  double get multiplier => asDouble(raw['multiplier']) ?? 1;
  bool get isActive => asBool(raw['is_active'], true);
}

class PricingRule {
  PricingRule(this.raw);
  final Json raw;
  String get id => raw['id'] as String;
  String? get cityId => raw['city_id'] as String?;
  VehicleType get vehicleType => VehicleType.parse(raw['vehicle_type'] as String?);
  int get basePrice => asInt(raw['base_price']);
  double get includedKm => asDouble(raw['included_km']) ?? 0;
  int get pricePerKm => asInt(raw['price_per_km']);
  int get minPrice => asInt(raw['min_price']);
  int get fragileFee => asInt(raw['fragile_fee']);
  int get sizeFeeMoyen => asInt(raw['size_fee_moyen']);
  int get sizeFeeGrand => asInt(raw['size_fee_grand']);
  int get sizeFeeTresGrand => asInt(raw['size_fee_tres_grand']);
  int get extraStopFee => asInt(raw['extra_stop_fee']);
  bool get isActive => asBool(raw['is_active'], true);
}

/// Paramètres de la plateforme (table app_settings).
class AppSettings {
  AppSettings(this.values);
  final Map<String, dynamic> values;

  /// Identifiants Google Analytics / AdSense saisis par l'administrateur.
  ({String gaId, String adsenseId, String adSlot, bool adsEnabled}) get google {
    final g = values['google'];
    final m = g is Map ? g : const {};
    return (
      gaId: '${m['ga_id'] ?? ''}',
      adsenseId: '${m['adsense_id'] ?? ''}',
      adSlot: '${m['ad_slot'] ?? ''}',
      adsEnabled: m['ads_enabled'] == true && '${m['adsense_id'] ?? ''}'.isNotEmpty,
    );
  }

  T? get<T>(String key) => values[key] is T ? values[key] as T : null;

  Map get commission => (values['commission'] as Map?) ?? {'type': 'percent', 'value': 15};
  String get commissionLabel {
    final c = commission;
    return c['type'] == 'fixed' ? '${c['value']} FCFA / course' : '${c['value']} %';
  }

  List<PaymentMethod> get paymentMethods {
    final list = (values['payment_methods'] as List?)?.cast<String>() ??
        ['cash', 'cash_on_delivery', 'orange_money', 'moov_money', 'wallet'];
    return list.map(PaymentMethod.parse).toList();
  }

  bool get paymentSimulation => (values['payment_mode'] ?? 'simulation') == 'simulation';
  /// Paiement manuel : le client envoie l'argent sur le numéro Telima puis l'administrateur valide.
  bool get paymentManual => values['payment_mode'] == 'manual';
  String get paymentMode => '${values['payment_mode'] ?? 'simulation'}';

  /// Numéro et nom du compte Mobile Money qui reçoit les paiements (mode manuel).
  ({String number, String name}) mobileMoneyAccount(String method) {
    final all = values['mobile_money_accounts'];
    final m = all is Map ? all[method] : null;
    return (number: m is Map ? '${m['number'] ?? ''}' : '', name: m is Map ? '${m['name'] ?? ''}' : '');
  }

  int get errandServiceFee => (values['errand_service_fee'] as num?)?.toInt() ?? 500;
  num get ridePriceMultiplier => (values['ride_price_multiplier'] as num?) ?? 1;
  bool get smsSimulation => (values['sms_mode'] ?? 'simulation') == 'simulation';
  String get proofMode => (values['proof_mode'] as String?) ?? 'otp';
  double get avgSpeedKmh => asDouble(values['avg_speed_kmh']) ?? 25;
  int get locationIntervalSeconds => asInt(values['location_min_interval_s'], 10);
  int get withdrawalMin => asInt(values['withdrawal_min'], 1000);
  int get driverMaxDebt => asInt(values['driver_max_debt'], 10000);
  Map get support => (values['support'] as Map?) ?? const {};
  String get supportPhone => support['phone']?.toString() ?? '';
  String get supportWhatsapp => support['whatsapp']?.toString() ?? '';
  String get supportEmail => support['email']?.toString() ?? '';
  String get supportHours => support['hours']?.toString() ?? '';
}

class AppNotification {
  AppNotification(this.raw);
  final Json raw;
  int get id => asInt(raw['id']);
  String get type => raw['type'] as String? ?? 'info';
  String get title => raw['title'] as String? ?? '';
  String get body => raw['body'] as String? ?? '';
  Map get data => (raw['data'] as Map?) ?? const {};
  String? get deliveryId => data['delivery_id']?.toString();
  DateTime? get readAt => asDate(raw['read_at']);
  DateTime? get createdAt => asDate(raw['created_at']);
  bool get isRead => readAt != null;
}

class BusinessAccount {
  BusinessAccount(this.raw);
  final Json raw;
  String get id => raw['id'] as String;
  String get name => raw['name'] as String? ?? '';
  BusinessType get type => BusinessType.parse(raw['type'] as String?);
  String get ownerId => raw['owner_id'] as String;
  String? get phone => raw['phone'] as String?;
  String? get address => raw['address'] as String?;
  double? get lat => asDouble(raw['lat']);
  double? get lng => asDouble(raw['lng']);
  String? get cityId => raw['city_id'] as String?;
  bool get isActive => asBool(raw['is_active'], true);
}

class BusinessMember {
  BusinessMember(this.raw);
  final Json raw;
  String get userId => raw['user_id'] as String;
  MemberRole get role => MemberRole.parse(raw['role'] as String?);
  String get name => (raw['users'] is Map) ? ((raw['users'] as Map)['full_name'] as String? ?? '') : '';
  String get phone => (raw['users'] is Map) ? ((raw['users'] as Map)['phone'] as String? ?? '') : '';
}

class SavedAddress {
  SavedAddress(this.raw);
  final Json raw;
  String get id => raw['id'] as String;
  String get label => raw['label'] as String? ?? '';
  String? get contactName => raw['contact_name'] as String?;
  String? get contactPhone => raw['contact_phone'] as String?;
  String get address => raw['address'] as String? ?? '';
  double get lat => asDouble(raw['lat']) ?? 0;
  double get lng => asDouble(raw['lng']) ?? 0;
  String? get instructions => raw['instructions'] as String?;
  String? get businessId => raw['business_id'] as String?;
}

class SupportRequest {
  SupportRequest(this.raw);
  final Json raw;
  String get id => raw['id'] as String;
  String? get userId => raw['user_id'] as String?;
  String? get phone => raw['phone'] as String?;
  String get subject => raw['subject'] as String? ?? '';
  String get message => raw['message'] as String? ?? '';
  String get status => raw['status'] as String? ?? 'open';
  String? get adminReply => raw['admin_reply'] as String?;
  DateTime? get createdAt => asDate(raw['created_at']);
  String? get userName => (raw['users'] is Map) ? (raw['users'] as Map)['full_name'] as String? : null;
  String? get userPhone => (raw['users'] is Map) ? (raw['users'] as Map)['phone'] as String? : null;

  String get statusLabel => switch (status) { 'open' => 'Ouvert', 'in_progress' => 'En cours', _ => 'Clos' };
}
