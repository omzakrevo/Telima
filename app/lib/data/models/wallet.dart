import 'enums.dart';
import 'json.dart';

class Wallet {
  Wallet({required this.id, required this.balance});
  final String id;
  final int balance;
  factory Wallet.fromJson(Json j) => Wallet(id: j['id'] as String, balance: asInt(j['balance']));
}

class WalletTransaction {
  WalletTransaction(this.raw);
  final Json raw;
  int get id => asInt(raw['id']);
  WalletTxType get type => WalletTxType.parse(raw['type'] as String?);
  int get amount => asInt(raw['amount']);
  int get balanceAfter => asInt(raw['balance_after']);
  String? get description => raw['description'] as String?;
  String? get deliveryId => raw['delivery_id'] as String?;
  DateTime? get createdAt => asDate(raw['created_at']);
}

class Withdrawal {
  Withdrawal(this.raw);
  final Json raw;
  String get id => raw['id'] as String;
  String get userId => raw['user_id'] as String;
  int get amount => asInt(raw['amount']);
  PaymentMethod get method => PaymentMethod.parse(raw['method'] as String?);
  String get phone => raw['phone'] as String? ?? '';
  WithdrawalStatus get status => WithdrawalStatus.parse(raw['status'] as String?);
  String? get providerRef => raw['provider_ref'] as String?;
  String? get note => raw['note'] as String?;
  DateTime? get createdAt => asDate(raw['created_at']);
  DateTime? get processedAt => asDate(raw['processed_at']);
  String? get userName => (raw['users'] is Map) ? (raw['users'] as Map)['full_name'] as String? : null;
}

class Payment {
  Payment(this.raw);
  final Json raw;
  String get id => raw['id'] as String;
  String? get deliveryId => raw['delivery_id'] as String?;
  int get amount => asInt(raw['amount']);
  PaymentMethod get method => PaymentMethod.parse(raw['method'] as String?);
  PaymentStatus get status => PaymentStatus.parse(raw['status'] as String?);
  String? get provider => raw['provider'] as String?;
  String? get providerRef => raw['provider_ref'] as String?;
  String get kind => (raw['metadata'] is Map ? (raw['metadata'] as Map)['kind'] as String? : null) ?? 'delivery';
  DateTime? get createdAt => asDate(raw['created_at']);
  DateTime? get paidAt => asDate(raw['paid_at']);
  Map get metadata => raw['metadata'] is Map ? raw['metadata'] as Map : const {};
  /// Paiement manuel déclaré par le client (« J'ai fait le paiement »), en attente de l'administrateur.
  bool get isDeclared => metadata['declared_at'] != null;
  String? get payerPhone => metadata['payer_phone'] as String?;
  String? get txnRef => metadata['txn_ref'] as String?;
}
