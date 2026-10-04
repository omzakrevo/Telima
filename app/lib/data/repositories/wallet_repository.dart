import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/formatters.dart';
import '../models/enums.dart';
import '../models/wallet.dart';

class WalletRepository {
  WalletRepository(this._client);
  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  Future<Wallet?> myWallet() async {
    final row = await _client.from('wallets').select().eq('user_id', _uid!).maybeSingle();
    return row == null ? null : Wallet.fromJson(row);
  }

  Future<List<WalletTransaction>> transactions(String walletId, {int limit = 100}) async {
    final rows = await _client
        .from('wallet_transactions')
        .select()
        .eq('wallet_id', walletId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(WalletTransaction.new).toList();
  }

  Future<List<Withdrawal>> myWithdrawals() async {
    final rows = await _client.from('withdrawals').select().eq('user_id', _uid!).order('created_at', ascending: false);
    return rows.map(Withdrawal.new).toList();
  }

  Future<Withdrawal> requestWithdrawal(int amount, PaymentMethod method, String phone) async {
    final res = await _client.rpc('request_withdrawal', params: {
      'p_amount': amount,
      'p_method': method.name,
      'p_phone': normalizePhone(phone),
    });
    return Withdrawal(Map<String, dynamic>.from(res as Map));
  }

  /// Paiement manuel : « J'ai fait le paiement » (l'administrateur le vérifiera).
  Future<Payment> declareManualPayment(String paymentId, String payerPhone, String? txnRef) async {
    final res = await _client.rpc('declare_manual_payment', params: {
      'p_payment_id': paymentId,
      'p_payer_phone': normalizePhone(payerPhone),
      'p_txn_ref': (txnRef ?? '').trim().isEmpty ? null : txnRef!.trim(),
    });
    return Payment(Map<String, dynamic>.from(res as Map));
  }

  Future<Payment> requestTopup(int amount, PaymentMethod method) async {
    final res = await _client.rpc('request_wallet_topup', params: {'p_amount': amount, 'p_method': method.name});
    return Payment(Map<String, dynamic>.from(res as Map));
  }
}
