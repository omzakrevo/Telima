import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/enums.dart';
import '../../../data/models/wallet.dart';

class PaymentResult {
  PaymentResult.success([this.message]) : ok = true;
  PaymentResult.failure(this.message) : ok = false;
  final bool ok;
  final String? message;
}

/// Contrat commun à tous les moyens de paiement.
/// Ajouter un fournisseur = créer une classe qui implémente [PaymentProvider]
/// et l'enregistrer dans [PaymentGateway].
abstract class PaymentProvider {
  PaymentMethod get method;

  /// Vrai si l'utilisateur doit valider le paiement sur son téléphone (USSD / application).
  bool get requiresUserConfirmation;

  /// Lance le paiement d'un enregistrement `payments` en attente.
  Future<PaymentResult> pay(Payment payment, {required String payerPhone});
}

/// Espèces / paiement à la livraison : encaissé par le livreur à la remise du colis.
class CashPaymentProvider implements PaymentProvider {
  CashPaymentProvider(this.method);
  @override
  final PaymentMethod method;
  @override
  bool get requiresUserConfirmation => false;
  @override
  Future<PaymentResult> pay(Payment payment, {required String payerPhone}) async =>
      PaymentResult.success('À régler en espèces au livreur.');
}

/// Portefeuille interne : débité côté serveur à la création de la commande.
class WalletPaymentProvider implements PaymentProvider {
  @override
  PaymentMethod get method => PaymentMethod.wallet;
  @override
  bool get requiresUserConfirmation => false;
  @override
  Future<PaymentResult> pay(Payment payment, {required String payerPhone}) async =>
      PaymentResult.success('Payé avec votre portefeuille.');
}

/// Mode simulation : aucun argent réel, le serveur confirme le paiement
/// (autorisé uniquement si app_settings.payment_mode = "simulation").
class SimulatedMobileMoneyProvider implements PaymentProvider {
  SimulatedMobileMoneyProvider(this.method, this._client);
  @override
  final PaymentMethod method;
  final SupabaseClient _client;
  @override
  bool get requiresUserConfirmation => true;

  @override
  Future<PaymentResult> pay(Payment payment, {required String payerPhone}) async {
    await Future<void>.delayed(const Duration(seconds: 2)); // délai réaliste d'une validation USSD
    await _client.rpc('confirm_simulated_payment', params: {'p_payment_id': payment.id});
    return PaymentResult.success('Paiement ${method.label} simulé confirmé.');
  }
}

/// Mode réel : la fonction Edge `mobile-money-init` déclenche la demande de paiement chez
/// l'opérateur (Orange Money / Moov Money). La confirmation arrive par webhook
/// (fonction serveur public._confirm_payment) ; l'application attend le statut « payé ».
class LiveMobileMoneyProvider implements PaymentProvider {
  LiveMobileMoneyProvider(this.method, this._client);
  @override
  final PaymentMethod method;
  final SupabaseClient _client;
  @override
  bool get requiresUserConfirmation => true;

  @override
  Future<PaymentResult> pay(Payment payment, {required String payerPhone}) async {
    try {
      await _client.functions.invoke('mobile-money-init', body: {
        'payment_id': payment.id,
        'provider': method.name,
        'phone': payerPhone,
      });
    } on FunctionException catch (e) {
      return PaymentResult.failure(
          e.status == 404 ? '${method.label} n\'est pas encore activé. Choisissez un autre moyen de paiement.' : 'Paiement refusé.');
    }
    // Attente de la confirmation (2 minutes max)
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 4));
      final row = await _client.from('payments').select('status').eq('id', payment.id).maybeSingle();
      final status = row?['status'];
      if (status == 'paid') return PaymentResult.success('Paiement confirmé.');
      if (status == 'failed') return PaymentResult.failure('Paiement refusé par l\'opérateur.');
    }
    return PaymentResult.failure('Délai dépassé. Si vous avez validé, le paiement sera confirmé automatiquement.');
  }
}

class PaymentGateway {
  PaymentGateway(this._client, {required this.simulation});
  final SupabaseClient _client;
  final bool simulation;

  PaymentProvider providerFor(PaymentMethod method) => switch (method) {
        PaymentMethod.cash || PaymentMethod.cash_on_delivery => CashPaymentProvider(method),
        PaymentMethod.wallet => WalletPaymentProvider(),
        PaymentMethod.orange_money || PaymentMethod.moov_money =>
          simulation ? SimulatedMobileMoneyProvider(method, _client) : LiveMobileMoneyProvider(method, _client),
      };
}
