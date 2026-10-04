import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/enums.dart';
import '../../data/models/wallet.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/payment_flow.dart';

/// Portefeuille : solde, rechargements, retraits (livreurs) et historique des opérations.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key, this.isDriver = false, this.embedded = false});
  final bool isDriver;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(myWalletProvider);
    final txs = ref.watch(myWalletTransactionsProvider);
    final withdrawals = isDriver ? ref.watch(myWithdrawalsProvider).value ?? const <Withdrawal>[] : const <Withdrawal>[];

    void refresh() {
      ref.invalidate(myWalletProvider);
      ref.invalidate(myWalletTransactionsProvider);
      ref.invalidate(myWithdrawalsProvider);
      if (isDriver) ref.invalidate(driverEarningsProvider);
    }

    final body = RefreshIndicator(
      onRefresh: () async => refresh(),
      child: Constrained(
        maxWidth: 720,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          AsyncBody<Wallet?>(
            value: wallet,
            onRetry: refresh,
            builder: (w) {
              final balance = w?.balance ?? 0;
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: balance < 0 ? [AppColors.danger, const Color(0xFF9B2C2C)] : [AppColors.primary, AppColors.primaryDark]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Solde disponible', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(fcfa(balance), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                  if (balance < 0)
                    const Text('Commissions dues à la plateforme : rechargez votre portefeuille.', style: TextStyle(color: Colors.white)),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary, minimumSize: const Size.fromHeight(48)),
                        onPressed: () => _topup(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Recharger'),
                      ),
                    ),
                    if (isDriver) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, minimumSize: const Size.fromHeight(48)),
                          onPressed: balance <= 0 ? null : () => _withdraw(context, ref, balance),
                          icon: const Icon(Icons.call_made),
                          label: const Text('Retirer'),
                        ),
                      ),
                    ],
                  ]),
                ]),
              );
            },
          ),
          if (isDriver) ...[
            const SizedBox(height: 12),
            txs.maybeWhen(
              data: (list) {
                int sum(WalletTxType t) => list.where((x) => x.type == t).fold(0, (a, b) => a + b.amount);
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2,
                  children: [
                    StatCard(label: 'Gains crédités', value: fcfa(sum(WalletTxType.earning)), icon: Icons.trending_up),
                    StatCard(label: 'Commissions', value: fcfa(-sum(WalletTxType.commission)), icon: Icons.percent, color: AppColors.accent),
                    StatCard(label: 'Retraits', value: fcfa(-sum(WalletTxType.withdrawal) - sum(WalletTxType.withdrawal_refund)), icon: Icons.call_made, color: AppColors.info),
                    StatCard(label: 'Rechargements', value: fcfa(sum(WalletTxType.topup)), icon: Icons.add_card, color: const Color(0xFF7C3AED)),
                  ],
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
          ],
          if (withdrawals.isNotEmpty) ...[
            const SectionTitle('Mes retraits'),
            Card(
              child: Column(children: [
                for (final w in withdrawals.take(10))
                  ListTile(
                    leading: Icon(w.method.icon),
                    title: Text(fcfa(w.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${w.method.label} · ${displayPhone(w.phone)} · ${formatDate(w.createdAt)}'),
                    trailing: Pill(w.status.label,
                        color: switch (w.status) {
                          WithdrawalStatus.paid => AppColors.primary,
                          WithdrawalStatus.rejected => AppColors.danger,
                          _ => AppColors.accent,
                        }),
                  ),
              ]),
            ),
          ],
          const SectionTitle('Historique des opérations'),
          AsyncBody<List<WalletTransaction>>(
            value: txs,
            onRetry: refresh,
            builder: (list) => list.isEmpty
                ? const EmptyState(icon: Icons.receipt_long_outlined, message: 'Aucune opération pour le moment')
                : Card(
                    child: Column(children: [
                      for (final t in list)
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: (t.amount > 0 ? AppColors.primary : AppColors.danger).withValues(alpha: 0.1),
                            child: Icon(t.amount > 0 ? Icons.south_west : Icons.north_east,
                                color: t.amount > 0 ? AppColors.primary : AppColors.danger, size: 18),
                          ),
                          title: Text(t.type.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${t.description ?? ''}\n${formatDateTime(t.createdAt)}'),
                          isThreeLine: true,
                          trailing: Text('${t.amount > 0 ? '+' : ''}${fcfa(t.amount)}',
                              style: TextStyle(fontWeight: FontWeight.w800, color: t.amount > 0 ? AppColors.primary : AppColors.danger)),
                        ),
                    ]),
                  ),
          ),
        ]),
      ),
    );

    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Portefeuille')), body: body);
  }

  Future<void> _topup(BuildContext context, WidgetRef ref) async {
    final res = await showDialog<(int, PaymentMethod)>(context: context, builder: (_) => const _AmountDialog(title: 'Recharger', withdraw: false));
    if (res == null || !context.mounted) return;
    final payment = await runWithLoader(context, () => ref.read(walletRepositoryProvider).requestTopup(res.$1, res.$2));
    if (payment == null || !context.mounted) return;
    final ok = await runMobileMoneyPayment(context, ref, payment);
    if (ok && context.mounted) showSuccess(context, 'Portefeuille rechargé de ${fcfa(res.$1)}');
    ref.invalidate(myWalletProvider);
    ref.invalidate(myWalletTransactionsProvider);
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref, int balance) async {
    final res = await showDialog<(int, PaymentMethod, String)>(
        context: context, builder: (_) => _AmountDialog(title: 'Demander un retrait', withdraw: true, max: balance));
    if (res == null || !context.mounted) return;
    await runWithLoader(context, () => ref.read(walletRepositoryProvider).requestWithdrawal(res.$1, res.$2, res.$3),
        success: 'Demande de retrait envoyée. Elle sera traitée par l\'administration.');
    ref.invalidate(myWalletProvider);
    ref.invalidate(myWalletTransactionsProvider);
    ref.invalidate(myWithdrawalsProvider);
  }
}

class _AmountDialog extends ConsumerStatefulWidget {
  const _AmountDialog({required this.title, required this.withdraw, this.max});
  final String title;
  final bool withdraw;
  final int? max;

  @override
  ConsumerState<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends ConsumerState<_AmountDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late final _phone = TextEditingController(text: displayPhone(ref.read(currentUserProvider)?.phone));
  PaymentMethod _method = PaymentMethod.orange_money;

  @override
  Widget build(BuildContext context) {
    final min = widget.withdraw ? (ref.watch(settingsProvider).value?.withdrawalMin ?? 1000) : 100;
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: _amount,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Montant (FCFA)',
              helperText: widget.max != null ? 'Maximum : ${fcfa(widget.max)} · minimum ${fcfa(min)}' : 'Minimum : ${fcfa(min)}',
            ),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null || n < min) return 'Minimum ${fcfa(min)}';
              if (widget.max != null && n > widget.max!) return 'Solde insuffisant';
              return null;
            },
          ),
          const SizedBox(height: 12),
          SegmentedButton<PaymentMethod>(
            segments: const [
              ButtonSegment(value: PaymentMethod.orange_money, label: Text('Orange Money')),
              ButtonSegment(value: PaymentMethod.moov_money, label: Text('Moov Money')),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          if (widget.withdraw) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Numéro qui reçoit l\'argent'),
              validator: (v) => isValidPhone(v ?? '') ? null : 'Numéro invalide',
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final amount = int.parse(_amount.text);
            Navigator.pop(context, widget.withdraw ? (amount, _method, _phone.text) : (amount, _method));
          },
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
