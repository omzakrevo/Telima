import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/formatters.dart';
import '../models/config_models.dart';
import '../models/delivery.dart';
import '../models/driver.dart';
import '../models/enums.dart';
import '../models/user.dart';
import '../models/wallet.dart';

class DeliveryFilter {
  DeliveryFilter({this.from, this.to, this.statusGroup = 'all', this.driverId, this.customerQuery, this.code});
  DateTime? from;
  DateTime? to;

  /// all | pending | active | completed | cancelled
  String statusGroup;
  String? driverId;
  String? customerQuery;
  String? code;
}

/// Opérations du tableau de bord. Les droits sont vérifiés côté serveur (RLS + fonctions).
class AdminRepository {
  AdminRepository(this._client);
  final SupabaseClient _client;

  static const deliverySelect = '*, driver:drivers!deliveries_driver_id_fkey(users!drivers_user_id_fkey(full_name, phone))';

  Future<Map<String, dynamic>> dashboard(DateTime from, DateTime to) async {
    final res = await _client.rpc('admin_dashboard_stats', params: {
      'p_from': from.toUtc().toIso8601String(),
      'p_to': to.toUtc().toIso8601String(),
    });
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> dailyStats(int days) async {
    final res = await _client.rpc('admin_daily_stats', params: {'p_days': days});
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Delivery>> deliveries(DeliveryFilter f, {int limit = 200}) async {
    var q = _client.from('deliveries').select(deliverySelect);
    if (f.from != null) q = q.gte('created_at', f.from!.toUtc().toIso8601String());
    if (f.to != null) q = q.lt('created_at', f.to!.toUtc().toIso8601String());
    switch (f.statusGroup) {
      case 'pending':
        q = q.inFilter('status', ['created', 'searching']);
      case 'active':
        q = q.inFilter('status', ['assigned', 'to_pickup', 'at_pickup', 'picked_up', 'in_transit', 'at_dropoff', 'handed_over']);
      case 'completed':
        q = q.eq('status', 'completed');
      case 'cancelled':
        q = q.eq('status', 'cancelled');
    }
    if (f.driverId != null) q = q.eq('driver_id', f.driverId!);
    if ((f.code ?? '').isNotEmpty) q = q.ilike('code', '%${f.code!.trim()}%');
    final cq = (f.customerQuery ?? '').trim();
    if (cq.isNotEmpty) {
      final digits = cq.replaceAll(RegExp(r'[^0-9]'), '');
      q = digits.length >= 4
          ? q.ilike('customer_phone', '%$digits%')
          : q.ilike('customer_name', '%$cq%');
    }
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return rows.map(Delivery.new).toList();
  }

  Future<Delivery?> delivery(String id) async {
    final row = await _client.from('deliveries').select(deliverySelect).eq('id', id).maybeSingle();
    return row == null ? null : Delivery(row);
  }

  Future<List<Map<String, dynamic>>> assignableDrivers(String deliveryId) async {
    final res = await _client.rpc('admin_list_assignable_drivers', params: {'p_delivery_id': deliveryId});
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> assign(String deliveryId, String driverId) =>
      _client.rpc('admin_assign_delivery', params: {'p_delivery_id': deliveryId, 'p_driver_id': driverId});

  Future<void> cancel(String deliveryId, String reason) =>
      _client.rpc('cancel_delivery', params: {'p_delivery_id': deliveryId, 'p_reason': reason});

  Future<void> forceComplete(String deliveryId, String receiverName) =>
      _client.rpc('complete_delivery', params: {'p_delivery_id': deliveryId, 'p_receiver_name': receiverName});

  Future<Delivery> createPhoneOrder(Map<String, dynamic> data) async {
    final res = await _client.rpc('admin_create_delivery', params: {'p': data});
    return Delivery(Map<String, dynamic>.from(res as Map));
  }

  // ---- Livreurs ----
  static const driverSelect = '*, users!drivers_user_id_fkey(*), vehicles(*)';

  Future<List<DriverProfile>> drivers({DriverStatus? status, bool onlineOnly = false}) async {
    var q = _client.from('drivers').select(driverSelect);
    if (status != null) q = q.eq('status', status.name);
    if (onlineOnly) q = q.eq('is_online', true);
    final rows = await q.order('created_at', ascending: false);
    return rows.map(DriverProfile.new).toList();
  }

  Future<DriverProfile?> driver(String id) async {
    final row = await _client.from('drivers').select(driverSelect).eq('user_id', id).maybeSingle();
    return row == null ? null : DriverProfile(row);
  }

  Future<void> setDriverStatus(String id, DriverStatus status, {String? note}) =>
      _client.rpc('admin_set_driver_status', params: {'p_driver_id': id, 'p_status': status.name, 'p_note': note});

  Future<List<Delivery>> driverCourses(String driverId) async {
    final rows = await _client.from('deliveries').select().eq('driver_id', driverId).order('created_at', ascending: false).limit(200);
    return rows.map(Delivery.new).toList();
  }

  Future<List<Rating>> driverRatings(String driverId) async {
    final rows = await _client.from('ratings').select().eq('driver_id', driverId).order('created_at', ascending: false);
    return rows.map(Rating.new).toList();
  }

  Future<Wallet?> walletOf(String userId) async {
    final row = await _client.from('wallets').select().eq('user_id', userId).maybeSingle();
    return row == null ? null : Wallet.fromJson(row);
  }

  Future<List<WalletTransaction>> walletTransactions(String walletId) async {
    final rows = await _client.from('wallet_transactions').select().eq('wallet_id', walletId).order('created_at', ascending: false).limit(200);
    return rows.map(WalletTransaction.new).toList();
  }

  Future<void> adjustWallet(String userId, int amount, String description) =>
      _client.rpc('admin_wallet_adjust', params: {'p_user_id': userId, 'p_amount': amount, 'p_description': description});

  Future<void> updateVehicle(String id, Map<String, dynamic> data) => _client.from('vehicles').update(data).eq('id', id);

  /// Création d'un compte par l'administrateur (fonction Edge admin-create-user).
  Future<void> createUser({
    required String phone,
    required String fullName,
    required String password,
    required UserRole role,
    String? cityId,
    Map<String, dynamic>? driver,
  }) async {
    await _client.functions.invoke('admin-create-user', body: {
      'phone': normalizePhone(phone),
      'full_name': fullName,
      'password': password,
      'role': role.name,
      'city_id': cityId,
      'driver': driver,
    });
  }

  // ---- Utilisateurs ----
  Future<List<AppUser>> users({UserRole? role, String? query}) async {
    var q = _client.from('users').select();
    if (role != null) q = q.eq('role', role.name);
    final s = (query ?? '').trim();
    if (s.isNotEmpty) {
      final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
      q = digits.length >= 4 ? q.ilike('phone', '%$digits%') : q.ilike('full_name', '%$s%');
    }
    final rows = await q.order('created_at', ascending: false).limit(300);
    return rows.map(AppUser.fromJson).toList();
  }

  Future<void> setUserActive(String id, bool active) =>
      _client.rpc('admin_set_user_active', params: {'p_user_id': id, 'p_active': active});

  Future<void> setUserRole(String id, UserRole role) =>
      _client.rpc('admin_set_user_role', params: {'p_user_id': id, 'p_role': role.name});

  // ---- Paiements & retraits ----
  Future<List<Withdrawal>> withdrawals({WithdrawalStatus? status}) async {
    var q = _client.from('withdrawals').select('*, users!withdrawals_user_id_fkey(full_name, phone)');
    if (status != null) q = q.eq('status', status.name);
    final rows = await q.order('created_at', ascending: false).limit(200);
    return rows.map(Withdrawal.new).toList();
  }

  Future<void> processWithdrawal(String id, bool approve, {String? ref, String? note}) => _client.rpc(
      'admin_process_withdrawal',
      params: {'p_withdrawal_id': id, 'p_approve': approve, 'p_provider_ref': ref, 'p_note': note});

  Future<List<Payment>> payments({PaymentStatus? status}) async {
    var q = _client.from('payments').select();
    if (status != null) q = q.eq('status', status.name);
    final rows = await q.order('created_at', ascending: false).limit(200);
    return rows.map(Payment.new).toList();
  }

  /// Paiements Mobile Money déclarés par les clients, en attente de vérification.
  Future<List<Map<String, dynamic>>> paymentsToVerify() async {
    final rows = await _client
        .from('payments')
        .select('*, users:payer_id(full_name, phone), deliveries:delivery_id(code)')
        .eq('status', 'pending')
        .not('metadata->declared_at', 'is', null)
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> mobileMoneySms({int limit = 50}) async =>
      List<Map<String, dynamic>>.from(await _client.from('mm_sms').select().order('received_at', ascending: false).limit(limit));

  Future<Map<String, dynamic>> pendingCounts() async =>
      Map<String, dynamic>.from(await _client.rpc('admin_pending_counts') as Map);

  Future<void> rejectPayment(String id, String reason) =>
      _client.rpc('admin_reject_payment', params: {'p_payment_id': id, 'p_reason': reason});

  Future<String> enableSmsRelay(String label) async =>
      (await _client.rpc('admin_enable_sms_relay', params: {'p_label': label})) as String;

  Future<void> disableSmsRelay(String token) => _client.rpc('admin_disable_sms_relay', params: {'p_token': token});

  Future<void> confirmPayment(String id, String ref) =>
      _client.rpc('admin_confirm_payment', params: {'p_payment_id': id, 'p_provider_ref': ref});

  // ---- Support, récupération, journal ----
  Future<List<SupportRequest>> supportRequests({bool openOnly = true}) async {
    var q = _client.from('support_requests').select('*, users(full_name, phone)');
    if (openOnly) q = q.neq('status', 'closed');
    final rows = await q.order('created_at', ascending: false).limit(200);
    return rows.map(SupportRequest.new).toList();
  }

  Future<void> updateSupport(String id, {required String status, String? reply}) =>
      _client.from('support_requests').update({'status': status, 'admin_reply': reply}).eq('id', id);

  Future<List<Map<String, dynamic>>> passwordResets() async {
    final rows = await _client
        .from('password_reset_requests')
        .select('id, phone, code_plain, created_at, expires_at, used_at, users(full_name)')
        .isFilter('used_at', null)
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false);
    return rows;
  }

  Future<List<Map<String, dynamic>>> adminLogs({int limit = 200}) async {
    final rows = await _client.from('admin_logs').select('*, users(full_name)').order('created_at', ascending: false).limit(limit);
    return rows;
  }
}
