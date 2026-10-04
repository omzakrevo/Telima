import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme.dart';
import '../../core/services/sms_relay.dart';
import '../../core/utils/formatters.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/icon3d.dart';

final _toVerifyProvider = FutureProvider.autoDispose((ref) => ref.watch(adminRepositoryProvider).paymentsToVerify());
final _smsProvider = FutureProvider.autoDispose((ref) => ref.watch(adminRepositoryProvider).mobileMoneySms());
final adminPendingCountsProvider = FutureProvider.autoDispose((ref) => ref.watch(adminRepositoryProvider).pendingCounts());

String _opLabel(String? method) => method == 'moov_money' ? 'Moov Money' : 'Orange Money';

/// Paiements Orange Money / Moov Money déclarés par les clients (« J'ai fait le paiement »),
/// avec les SMS reçus sur le téléphone administrateur pour comparer. L'administrateur valide ou refuse.
class AdminPaymentsScreen extends ConsumerWidget {
  const AdminPaymentsScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(_toVerifyProvider);
    ref.invalidate(_smsProvider);
    ref.invalidate(adminPendingCountsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(_toVerifyProvider);
    final sms = ref.watch(_smsProvider).value ?? const [];
    final smsById = {for (final s in sms) s['id']: s};
    return RefreshIndicator(
      onRefresh: () async => _refresh(ref),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (SmsRelay.supported) _RelayCard(onChanged: () => _refresh(ref)),
        SectionTitle('Paiements à vérifier', trailing: IconButton(onPressed: () => _refresh(ref), icon: const Icon(Icons.refresh))),
        AsyncBody<List<Map<String, dynamic>>>(
          value: payments,
          onRetry: () => ref.invalidate(_toVerifyProvider),
          builder: (list) => list.isEmpty
              ? const EmptyState(icon: Icons.verified_rounded, message: 'Aucun paiement en attente de vérification.')
              : Column(children: [
                  for (final p in list) _PaymentCard(payment: p, sms: smsById[(p['metadata'] as Map?)?['sms_id']], onDone: () => _refresh(ref)),
                ]),
        ),
        const SectionTitle('SMS Mobile Money reçus'),
        if (sms.isEmpty)
          Text(
              SmsRelay.supported
                  ? 'Aucun SMS relayé. Activez le relais ci-dessus sur le téléphone qui reçoit les paiements.'
                  : 'Le relais des SMS s’active depuis l’application Android, sur le téléphone qui reçoit les paiements.',
              style: const TextStyle(color: AppColors.textMuted))
        else
          Card(
            child: Column(children: [
              for (final s in sms.take(30))
                ListTile(
                  dense: true,
                  leading: Icon(
                    s['payment_id'] != null ? Icons.link_rounded : (s['direction'] == 'out' ? Icons.call_made_rounded : Icons.sms_rounded),
                    color: s['payment_id'] != null ? AppColors.primary : AppColors.textMuted,
                  ),
                  title: Text(
                      [if (s['amount'] != null) fcfa((s['amount'] as num).toInt()), if (s['counterpart_phone'] != null) displayPhone(s['counterpart_phone'] as String), if (s['txn_ref'] != null) 'réf. ${s['txn_ref']}']
                          .join(' · ')
                          .ifEmpty('${s['operator'] ?? 'SMS'}'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${formatDateTime(DateTime.tryParse('${s['received_at']}')?.toLocal())}\n${s['body']}',
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                  isThreeLine: true,
                ),
            ]),
          ),
        const SizedBox(height: 24),
      ]),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _PaymentCard extends ConsumerWidget {
  const _PaymentCard({required this.payment, required this.sms, required this.onDone});
  final Map<String, dynamic> payment;
  final Map<String, dynamic>? sms;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = payment;
    final meta = Map<String, dynamic>.from(p['metadata'] as Map? ?? const {});
    final user = p['users'] as Map?;
    final code = (p['deliveries'] as Map?)?['code'];
    final amount = (p['amount'] as num).toInt();
    final matched = sms != null;
    final ref0 = (meta['sms_ref'] ?? meta['txn_ref'])?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: matched ? AppColors.primary : AppColors.line, width: matched ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(fcfa(amount), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
            Pill(_opLabel(p['method'] as String?), color: p['method'] == 'moov_money' ? const Color(0xFF0066B3) : const Color(0xFFFF7900)),
          ]),
          const SizedBox(height: 4),
          Text('${user?['full_name'] ?? 'Client'} · ${meta['kind'] == 'topup' ? 'Rechargement du portefeuille' : 'Commande ${code ?? ''}'}'),
          Text('Envoyé depuis : ${displayPhone(meta['payer_phone'] as String?)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (meta['txn_ref'] != null) Text('Réf. indiquée : ${meta['txn_ref']}'),
          Text('Déclaré ${formatDateTime(DateTime.tryParse('${meta['declared_at']}')?.toLocal())}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (matched ? AppColors.primary : AppColors.accent).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              matched
                  ? '✅ SMS reçu correspondant : ${sms!['body']}'
                  : 'Aucun SMS correspondant pour l’instant. Vérifiez sur le téléphone qui reçoit les paiements.',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () async {
                  final reason = await promptDialog(context, title: 'Refuser ce paiement', label: 'Motif (ex. argent non reçu)');
                  if (reason == null || !context.mounted) return;
                  await runWithLoader(context, () => ref.read(adminRepositoryProvider).rejectPayment(p['id'] as String, reason),
                      success: 'Paiement refusé, le client est prévenu');
                  onDone();
                },
                child: const Text('Refuser'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () async {
                  final ok = await confirmDialog(context,
                      title: 'Valider ${fcfa(amount)} ?',
                      message: 'Confirmez que l’argent est bien arrivé sur votre compte ${_opLabel(p['method'] as String?)}.',
                      confirmLabel: 'Valider');
                  if (!ok || !context.mounted) return;
                  await runWithLoader(
                      context,
                      () => ref.read(adminRepositoryProvider).confirmPayment(p['id'] as String,
                          ref0 ?? 'MANUEL-${DateTime.now().millisecondsSinceEpoch}'),
                      success: 'Paiement validé, le client est prévenu');
                  onDone();
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Argent reçu'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Active le relais des SMS Mobile Money sur ce téléphone (Android).
class _RelayCard extends ConsumerStatefulWidget {
  const _RelayCard({required this.onChanged});
  final VoidCallback onChanged;
  @override
  ConsumerState<_RelayCard> createState() => _RelayCardState();
}

class _RelayCardState extends ConsumerState<_RelayCard> {
  ({bool enabled, bool granted})? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    SmsRelay.flush();
  }

  Future<void> _load() async {
    final s = await SmsRelay.status();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    try {
      if (on) {
        final ok = await confirmDialog(context,
            title: 'Relayer les SMS Mobile Money ?',
            message: 'Ce téléphone transmettra à Telima uniquement les SMS Orange Money / Moov Money reçus (montant, numéro, référence), '
                'même application fermée, pour vous aider à vérifier les paiements. Aucun autre SMS n’est lu ni envoyé.',
            confirmLabel: 'Activer');
        if (!ok) return;
        final token = await ref.read(adminRepositoryProvider).enableSmsRelay('Téléphone de réception des paiements');
        final granted = await SmsRelay.enable(token);
        if (!granted && mounted) showSuccess(context, 'Autorisez « SMS » dans la fenêtre d’Android pour terminer.');
      } else {
        final token = await SmsRelay.disable();
        if (token != null) await ref.read(adminRepositoryProvider).disableSmsRelay(token);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _load();
      if (mounted) setState(() => _busy = false);
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final on = s?.enabled == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon3D(Ico3D.phone, size: 40),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Relais des SMS de paiement', style: TextStyle(fontWeight: FontWeight.w800)),
                Text('À activer sur le téléphone qui reçoit l’argent', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
            ),
            _busy || s == null
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : Switch(value: on, onChanged: _toggle),
          ]),
          if (on && s?.granted == false)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Row(children: [
                const Expanded(child: Text('Autorisation SMS manquante.', style: TextStyle(color: AppColors.danger))),
                TextButton(
                  onPressed: () async {
                    await SmsRelay.requestPermission();
                    await Future<void>.delayed(const Duration(seconds: 1));
                    await _load();
                  },
                  child: const Text('Autoriser'),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Retrait : l'administrateur envoie l'argent au livreur puis indique la référence de la transaction.
Future<String?> withdrawalTransferDialog(BuildContext context, {required int amount, required String phone, required String method}) {
  final refCtrl = TextEditingController();
  final orange = method != 'moov_money';
  final ussd = orange ? '*144#' : '*555#';
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Verser ${fcfa(amount)}'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('1. Envoyez ${fcfa(amount)} par ${orange ? 'Orange Money' : 'Moov Money'} au :'),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text(displayPhone(phone), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
          IconButton(
            tooltip: 'Copier',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => Clipboard.setData(ClipboardData(text: phone.replaceAll('+226', ''))),
          ),
        ]),
        OutlinedButton.icon(
          onPressed: () => launchUrl(Uri(scheme: 'tel', path: ussd)),
          icon: const Icon(Icons.dialpad_rounded),
          label: Text('Ouvrir ${orange ? 'Orange Money' : 'Moov Money'} ($ussd)'),
        ),
        const SizedBox(height: 12),
        const Text('2. Indiquez l’ID de la transaction (SMS de confirmation) :'),
        TextField(controller: refCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'ID de transaction')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, refCtrl.text.trim().isEmpty ? 'MANUEL' : refCtrl.text.trim().toUpperCase()),
          child: const Text('Argent envoyé'),
        ),
      ],
    ),
  );
}
