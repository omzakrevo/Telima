import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../core/services/payment/payment_provider.dart';
import '../core/utils/formatters.dart';
import '../data/models/enums.dart';
import '../data/models/wallet.dart';
import '../providers/auth_providers.dart';
import '../providers/core_providers.dart';
import 'common.dart';

/// Déroule le paiement Mobile Money d'un enregistrement `payments` en attente.
/// Renvoie true si le paiement est confirmé.
Future<bool> runMobileMoneyPayment(BuildContext context, WidgetRef ref, Payment payment) async {
  final settings = await ref.read(settingsProvider.future);
  final user = ref.read(currentUserProvider);
  if (!context.mounted) return false;
  if (settings.paymentManual && payment.method.isMobileMoney) {
    final account = settings.mobileMoneyAccount(payment.method.name);
    final declared = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ManualMobileMoneyDialog(
        payment: payment,
        number: account.number,
        holder: account.name,
        initialPhone: user?.phone ?? '',
        declare: (phone, ref0) => ref.read(walletRepositoryProvider).declareManualPayment(payment.id, phone, ref0),
      ),
    );
    if (declared == true && context.mounted) {
      showSuccess(context, 'Merci ! Votre paiement est en cours de vérification. Vous serez averti dès sa validation.');
    }
    return false; // validé plus tard par l'administrateur
  }
  final provider = ref.read(paymentGatewayProvider).providerFor(payment.method);

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _MobileMoneyDialog(
      payment: payment,
      simulation: settings.paymentSimulation,
      initialPhone: user?.phone ?? '',
      run: (phone) => provider.pay(payment, payerPhone: phone),
    ),
  );
  return ok ?? false;
}

class _MobileMoneyDialog extends StatefulWidget {
  const _MobileMoneyDialog({required this.payment, required this.simulation, required this.initialPhone, required this.run});
  final Payment payment;
  final bool simulation;
  final String initialPhone;
  final Future<PaymentResult> Function(String phone) run;

  @override
  State<_MobileMoneyDialog> createState() => _MobileMoneyDialogState();
}

class _MobileMoneyDialogState extends State<_MobileMoneyDialog> {
  late final _phone = TextEditingController(text: displayPhone(widget.initialPhone));
  bool _running = false;
  String? _error;

  Future<void> _pay() async {
    if (!isValidPhone(_phone.text)) {
      setState(() => _error = 'Numéro invalide');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final res = await widget.run(normalizePhone(_phone.text));
      if (!mounted) return;
      if (res.ok) {
        Navigator.pop(context, true);
      } else {
        setState(() => _error = res.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.payment.method;
    final color = m == PaymentMethod.orange_money ? const Color(0xFFFF7900) : const Color(0xFF0066B3);
    return AlertDialog(
      title: Row(children: [Icon(m.icon, color: color), const SizedBox(width: 8), Text(m.label)]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Montant : ${fcfa(widget.payment.amount)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          enabled: !_running,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Numéro Mobile Money'),
        ),
        const SizedBox(height: 12),
        if (_running)
          Row(children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.simulation ? 'Simulation du paiement…' : 'Validez la demande sur votre téléphone…')),
          ]),
        if (widget.simulation && !_running)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: const Text('Mode simulation : aucun argent réel n\'est débité.', style: TextStyle(fontSize: 12)),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
      ]),
      actions: [
        TextButton(onPressed: _running ? null : () => Navigator.pop(context, false), child: const Text('Plus tard')),
        FilledButton(onPressed: _running ? null : _pay, child: const Text('PAYER')),
      ],
    );
  }
}

/// Paiement manuel : le client envoie l'argent au numéro Telima puis appuie sur « J'ai fait le paiement ».
class _ManualMobileMoneyDialog extends StatefulWidget {
  const _ManualMobileMoneyDialog({
    required this.payment,
    required this.number,
    required this.holder,
    required this.initialPhone,
    required this.declare,
  });
  final Payment payment;
  final String number;
  final String holder;
  final String initialPhone;
  final Future<Payment> Function(String phone, String? ref) declare;

  @override
  State<_ManualMobileMoneyDialog> createState() => _ManualMobileMoneyDialogState();
}

class _ManualMobileMoneyDialogState extends State<_ManualMobileMoneyDialog> {
  late final _phone = TextEditingController(text: displayPhone(widget.initialPhone));
  final _ref = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _orange => widget.payment.method == PaymentMethod.orange_money;
  String get _ussd => _orange ? '*144#' : '*555#';

  Future<void> _submit() async {
    if (!isValidPhone(_phone.text)) {
      setState(() => _error = 'Indiquez le numéro qui a envoyé l’argent');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.declare(normalizePhone(_phone.text), _ref.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.payment.method;
    final color = _orange ? const Color(0xFFFF7900) : const Color(0xFF0066B3);
    final missing = widget.number.trim().isEmpty;
    return AlertDialog(
      title: Row(children: [Icon(m.icon, color: color), const SizedBox(width: 8), Expanded(child: Text(m.label))]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (missing)
            const Text('Le numéro de paiement n’est pas encore configuré. Choisissez un autre moyen de paiement ou réessayez plus tard.',
                style: TextStyle(color: AppColors.danger))
          else ...[
            const Text('1. Envoyez exactement', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fcfa(widget.payment.amount), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: Text('au ${displayPhone(widget.number)}${widget.holder.isEmpty ? '' : '\n${widget.holder}'}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: 'Copier le numéro',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.number.replaceAll('+226', '')));
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Numéro copié')));
                    },
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: _ussd)),
              icon: const Icon(Icons.dialpad_rounded),
              label: Text('Ouvrir ${m.label} ($_ussd)'),
            ),
            const SizedBox(height: 14),
            const Text('2. Indiquez votre paiement', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              enabled: !_busy,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Numéro qui a envoyé l’argent'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ref,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'ID de la transaction (facultatif)',
                helperText: 'Dans le SMS de confirmation reçu après l’envoi',
              ),
            ),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Plus tard')),
        if (!missing)
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('J’AI FAIT LE PAIEMENT'),
          ),
      ],
    );
  }
}

/// Sélecteur de moyen de paiement (grandes tuiles).
class PaymentMethodPicker extends ConsumerWidget {
  const PaymentMethodPicker({super.key, required this.value, required this.onChanged, this.allowed, this.walletBalance});
  final PaymentMethod value;
  final ValueChanged<PaymentMethod> onChanged;
  final List<PaymentMethod>? allowed;
  final int? walletBalance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(settingsProvider).value?.paymentMethods ?? PaymentMethod.values;
    final methods = PaymentMethod.values.where((m) => enabled.contains(m) && (allowed?.contains(m) ?? true)).toList();
    return Column(children: [
      for (final m in methods)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: value == m ? AppColors.primary.withValues(alpha: 0.08) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: value == m ? AppColors.primary : const Color(0xFFE5E7EB), width: value == m ? 2 : 1),
            ),
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onTap: () => onChanged(m),
              leading: Icon(m.icon, color: value == m ? AppColors.primary : null),
              title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: switch (m) {
                PaymentMethod.cash => const Text('Payé au livreur à la récupération'),
                PaymentMethod.cash_on_delivery => const Text('Payé par le destinataire à la livraison'),
                PaymentMethod.wallet => Text('Solde : ${fcfa(walletBalance ?? 0)}'),
                _ => const Text('Envoi depuis votre téléphone, vérifié par Telima'),
              },
              trailing: Icon(value == m ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: value == m ? AppColors.primary : null),
            ),
          ),
        ),
    ]);
  }
}
