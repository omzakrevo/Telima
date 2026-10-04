import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/enums.dart';
import '../../data/models/wallet.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import 'admin_payments_screen.dart';

final _withdrawalsProvider = FutureProvider.autoDispose
    .family<List<Withdrawal>, WithdrawalStatus?>((ref, s) => ref.watch(adminRepositoryProvider).withdrawals(status: s));
final _paymentsProvider =
    FutureProvider.autoDispose.family<List<Payment>, PaymentStatus?>((ref, s) => ref.watch(adminRepositoryProvider).payments(status: s));

/// Paiements et retraits (versements Orange Money / Moov Money aux livreurs).
class AdminFinanceScreen extends ConsumerStatefulWidget {
  const AdminFinanceScreen({super.key});
  @override
  ConsumerState<AdminFinanceScreen> createState() => _AdminFinanceScreenState();
}

class _AdminFinanceScreenState extends ConsumerState<AdminFinanceScreen> {
  WithdrawalStatus? _wStatus = WithdrawalStatus.pending;
  PaymentStatus? _pStatus;

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(currentUserProvider)?.role == UserRole.admin;
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        const Material(color: Colors.white, child: TabBar(tabs: [Tab(text: 'Retraits livreurs'), Tab(text: 'Paiements')])),
        Expanded(
          child: TabBarView(children: [
            Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 8, children: [
                  for (final s in [WithdrawalStatus.pending, WithdrawalStatus.paid, WithdrawalStatus.rejected, null])
                    ChoiceChip(label: Text(s?.label ?? 'Tous'), selected: _wStatus == s, onSelected: (_) => setState(() => _wStatus = s)),
                ]),
              ),
              Expanded(
                child: AsyncBody<List<Withdrawal>>(
                  value: ref.watch(_withdrawalsProvider(_wStatus)),
                  onRetry: () => ref.invalidate(_withdrawalsProvider(_wStatus)),
                  builder: (list) => list.isEmpty
                      ? const EmptyState(icon: Icons.call_made, message: 'Aucun retrait')
                      : ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                          for (final w in list)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(w.method.icon, color: AppColors.primary),
                                title: Text('${fcfa(w.amount)} · ${w.userName ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text([
                                  '${w.method.label} → ${displayPhone(w.phone)}',
                                  'Demandé le ${formatDateTime(w.createdAt)}',
                                  if (w.providerRef != null) 'Réf. ${w.providerRef}',
                                  if (w.note != null) w.note!,
                                ].join('\n')),
                                isThreeLine: true,
                                trailing: w.status == WithdrawalStatus.pending && isAdmin
                                    ? Wrap(spacing: 6, children: [
                                        IconButton(
                                          tooltip: 'Refuser',
                                          icon: const Icon(Icons.close, color: AppColors.danger),
                                          onPressed: () => _process(w, false),
                                        ),
                                        FilledButton(onPressed: () => _process(w, true), child: const Text('Payé')),
                                      ])
                                    : Pill(w.status.label,
                                        color: w.status == WithdrawalStatus.paid
                                            ? AppColors.primary
                                            : (w.status == WithdrawalStatus.rejected ? AppColors.danger : AppColors.accent)),
                                onTap: () => context.push('/admin/drivers/${w.userId}'),
                              ),
                            ),
                        ]),
                ),
              ),
            ]),
            Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 8, children: [
                  for (final s in [null, PaymentStatus.pending, PaymentStatus.paid, PaymentStatus.failed, PaymentStatus.refunded])
                    ChoiceChip(label: Text(s?.label ?? 'Tous'), selected: _pStatus == s, onSelected: (_) => setState(() => _pStatus = s)),
                ]),
              ),
              Expanded(
                child: AsyncBody<List<Payment>>(
                  value: ref.watch(_paymentsProvider(_pStatus)),
                  onRetry: () => ref.invalidate(_paymentsProvider(_pStatus)),
                  builder: (list) => list.isEmpty
                      ? const EmptyState(icon: Icons.payments_outlined, message: 'Aucun paiement')
                      : ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                          for (final p in list)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: Icon(p.method.icon),
                                title: Text('${fcfa(p.amount)} · ${p.method.label}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text('${p.kind == 'topup' ? 'Rechargement portefeuille' : 'Livraison'} · ${formatDateTime(p.createdAt)}'
                                    '${p.providerRef != null ? '\nRéf. ${p.providerRef}' : ''}'),
                                trailing: p.status == PaymentStatus.pending && p.method.isMobileMoney && isAdmin
                                    ? OutlinedButton(onPressed: () => _confirmPayment(p), child: const Text('Confirmer'))
                                    : Pill(p.status.label, color: p.status == PaymentStatus.paid ? AppColors.primary : AppColors.textMuted),
                                onTap: p.deliveryId == null ? null : () => context.push('/admin/orders/${p.deliveryId}'),
                              ),
                            ),
                        ]),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Future<void> _process(Withdrawal w, bool approve) async {
    final text = approve && w.method.isMobileMoney
        ? await withdrawalTransferDialog(context, amount: w.amount, phone: w.phone, method: w.method.name)
        : await promptDialog(
            context,
            title: approve ? 'Confirmer le versement de ${fcfa(w.amount)}' : 'Refuser le retrait',
            label: approve ? 'Référence de la transaction ${w.method.label}' : 'Motif du refus',
          );
    if (text == null || !mounted) return;
    await runWithLoader(
      context,
      () => ref.read(adminRepositoryProvider).processWithdrawal(w.id, approve, ref: approve ? text : null, note: approve ? null : text),
      success: approve ? 'Retrait marqué comme payé' : 'Retrait refusé, montant recrédité',
    );
    ref.invalidate(_withdrawalsProvider);
  }

  Future<void> _confirmPayment(Payment p) async {
    final ref0 = await promptDialog(context, title: 'Confirmer manuellement le paiement', label: 'Référence opérateur');
    if (ref0 == null || !mounted) return;
    await runWithLoader(context, () => ref.read(adminRepositoryProvider).confirmPayment(p.id, ref0), success: 'Paiement confirmé');
    ref.invalidate(_paymentsProvider);
  }
}
