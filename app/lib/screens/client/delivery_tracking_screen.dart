import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../data/models/delivery.dart';
import '../../data/models/enums.dart';
import '../../data/models/wallet.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/delivery_widgets.dart';
import '../../widgets/icon3d.dart';
import '../../widgets/live_tracking.dart';
import '../../widgets/payment_flow.dart';

final _assignedDriverProvider = FutureProvider.autoDispose
    .family<AssignedDriver?, String>((ref, id) => ref.watch(deliveryRepositoryProvider).driverInfo(id));

/// Suivi d'une livraison par le client (ou un membre du compte professionnel).
class DeliveryTrackingScreen extends ConsumerWidget {
  const DeliveryTrackingScreen({super.key, required this.deliveryId});
  final String deliveryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(deliveryStreamProvider(deliveryId));
    return Scaffold(
      appBar: AppBar(title: Text(async.value?.code ?? 'Suivi')),
      body: AsyncBody<Delivery?>(
        value: async,
        onRetry: () => ref.invalidate(deliveryStreamProvider(deliveryId)),
        builder: (d) => d == null
            ? const EmptyState(icon: Icons.search_off, message: 'Livraison introuvable')
            : _TrackingBody(delivery: d),
      ),
    );
  }
}

class _TrackingBody extends ConsumerStatefulWidget {
  const _TrackingBody({required this.delivery});
  final Delivery delivery;
  @override
  ConsumerState<_TrackingBody> createState() => _TrackingBodyState();
}

class _TrackingBodyState extends ConsumerState<_TrackingBody> {
  DeliveryStatus? _lastStatus;

  Delivery get d => widget.delivery;

  @override
  Widget build(BuildContext context) {
    // Rafraîchit les infos du livreur à chaque changement d'étape
    if (_lastStatus != d.status) {
      if (_lastStatus != null) {
        ref.invalidate(_assignedDriverProvider(d.id));
        ref.invalidate(deliveryHistoryProvider(d.id));
      }
      _lastStatus = d.status;
    }
    final driverPos = d.status.hasDriver && !d.status.isFinished ? ref.watch(driverPositionProvider(d.id)) : null;
    final driver = d.status.hasDriver ? ref.watch(_assignedDriverProvider(d.id)).value : null;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(deliveryStreamProvider(d.id));
        ref.invalidate(_assignedDriverProvider(d.id));
      },
      child: Constrained(
        maxWidth: 720,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _StatusHeader(delivery: d),
          const SizedBox(height: 12),
          if (d.status == DeliveryStatus.created && d.paymentMethod.isMobileMoney) _PaymentPending(delivery: d),
          LiveTrackingMap(delivery: d, driverPosition: driverPos ?? driver?.position, height: 280),
          const SizedBox(height: 12),
          if (d.status == DeliveryStatus.searching) const _SearchingCard(),
          if (driver != null) _DriverCard(delivery: d, driver: driver),
          if (d.isErrand) _ErrandCard(delivery: d),
          if (d.status.isActive && d.status != DeliveryStatus.created) _OtpCard(delivery: d),
          if (d.status == DeliveryStatus.completed) _RateCard(delivery: d),
          if (d.isBatch) _BatchStops(batchId: d.batchId!, currentId: d.id),
          const SectionTitle('Détails'),
          DeliveryDetailsCard(delivery: d),
          const SectionTitle('Étapes'),
          StatusTimeline(deliveryId: d.id, current: d.status),
          const SizedBox(height: 16),
          if (d.status.isActive && d.status.canCustomerCancel)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () => _cancel(context),
              icon: const Icon(Icons.cancel_outlined),
              label: Text(d.isRide ? 'Annuler le trajet' : d.isErrand ? 'Annuler la course' : 'Annuler la livraison'),
            ),
          if (d.status.isActive && !d.status.canCustomerCancel)
            TextButton.icon(
              onPressed: () => context.push('/support?delivery=${d.id}'),
              icon: const Icon(Icons.support_agent),
              label: const Text('Un problème ? Contacter le support'),
            ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Future<void> _cancel(BuildContext context) async {
    final reason = await promptDialog(context, title: 'Annuler la livraison', label: 'Motif (ex. erreur d\'adresse)');
    if (reason == null || !context.mounted) return;
    await runWithLoader(context, () => ref.read(deliveryRepositoryProvider).cancel(d.id, reason), success: 'Livraison annulée');
    ref.invalidate(myActiveDeliveriesProvider);
    ref.invalidate(myWalletProvider);
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.delivery});
  final Delivery delivery;

  @override
  Widget build(BuildContext context) {
    final s = delivery.status;
    final ride = delivery.isRide, errand = delivery.isErrand;
    final who = ride ? 'chauffeur' : 'livreur';
    final text = switch (s) {
      DeliveryStatus.created => delivery.paymentMethod.isMobileMoney ? 'En attente du paiement' : 'Nouvelle demande',
      DeliveryStatus.searching => 'Recherche d\'un $who disponible…',
      DeliveryStatus.assigned when ride || errand => 'Un $who a accepté votre demande',
      DeliveryStatus.to_pickup when ride => 'Votre chauffeur arrive',
      DeliveryStatus.at_pickup when ride => 'Votre chauffeur est là',
      DeliveryStatus.picked_up when ride => 'Vous êtes à bord',
      DeliveryStatus.in_transit when ride => 'Trajet en cours',
      DeliveryStatus.completed when ride => 'Trajet terminé',
      DeliveryStatus.cancelled when ride => 'Trajet annulé',
      DeliveryStatus.to_pickup when errand => 'Le livreur part faire vos achats',
      DeliveryStatus.at_pickup when errand => 'Achats en cours',
      DeliveryStatus.picked_up when errand => 'Achats effectués',
      DeliveryStatus.in_transit when errand => 'Vos achats sont en route',
      DeliveryStatus.completed when errand => 'Course terminée',
      DeliveryStatus.cancelled when errand => 'Course annulée',
      DeliveryStatus.assigned => 'Un livreur a accepté votre commande',
      DeliveryStatus.to_pickup => 'Votre livreur arrive',
      DeliveryStatus.at_pickup => 'Votre livreur est arrivé',
      DeliveryStatus.picked_up => 'Votre colis a été récupéré',
      DeliveryStatus.in_transit => 'Votre colis est en route',
      DeliveryStatus.at_dropoff => 'Le livreur est à destination',
      DeliveryStatus.handed_over => 'Colis remis',
      DeliveryStatus.completed => 'Livraison terminée',
      DeliveryStatus.cancelled => 'Livraison annulée',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(
          s == DeliveryStatus.completed
              ? Icons.check_circle
              : s == DeliveryStatus.cancelled
                  ? Icons.cancel
                  : delivery.isRide
                      ? Icons.local_taxi_rounded
                      : delivery.isErrand
                          ? Icons.shopping_bag_rounded
                          : Icons.delivery_dining,
          color: Colors.white,
          size: 36,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            Text('Étape ${s.step}/11 · ${fcfa(delivery.totalPrice)}', style: const TextStyle(color: Colors.white70)),
            if (s == DeliveryStatus.cancelled && delivery.cancelReason != null)
              Text('Motif : ${delivery.cancelReason}', style: const TextStyle(color: Colors.white)),
          ]),
        ),
      ]),
    );
  }
}

class _SearchingCard extends StatelessWidget {
  const _SearchingCard();
  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(children: [
            SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            SizedBox(width: 14),
            Expanded(
              child: Text('Nous prévenons les livreurs disponibles autour du point de récupération. '
                  'Vous serez notifié dès qu\'un livreur accepte.'),
            ),
          ]),
        ),
      );
}

final _pendingPaymentProvider = FutureProvider.autoDispose.family<Payment?, String>(
    (ref, key) => ref.watch(deliveryRepositoryProvider).pendingPayment(key.split('|').first));

class _PaymentPending extends ConsumerWidget {
  const _PaymentPending({required this.delivery});
  final Delivery delivery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(_pendingPaymentProvider('${delivery.id}|${delivery.paymentStatus.name}')).value;
    if (pending != null && pending.isDeclared) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          color: const Color(0xFFFFF7E6),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Paiement en cours de vérification', style: TextStyle(fontWeight: FontWeight.w800)),
                  Text('${fcfa(pending.amount)} envoyés depuis le ${displayPhone(pending.payerPhone)}. '
                      'La recherche démarre dès la validation (quelques minutes).',
                      style: const TextStyle(fontSize: 13)),
                ]),
              ),
            ]),
          ),
        ),
      );
    }
    return _payCard(context, ref);
  }

  Widget _payCard(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Paiement ${delivery.paymentMethod.label} en attente',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('La recherche du livreur démarre dès que le paiement est confirmé.'),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  final repo = ref.read(deliveryRepositoryProvider);
                  final p = await repo.pendingPayment(delivery.id);
                  if (p == null || !context.mounted) return;
                  await runMobileMoneyPayment(context, ref, p);
                  ref.invalidate(_pendingPaymentProvider('${delivery.id}|${delivery.paymentStatus.name}'));
                },
                icon: const Icon(Icons.payment),
                label: Text('PAYER ${fcfa(delivery.totalPrice)}'),
              ),
              TextButton(
                onPressed: () async {
                  final m = await showModalBottomSheet<PaymentMethod>(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        for (final m in [PaymentMethod.cash, PaymentMethod.cash_on_delivery, PaymentMethod.wallet,
                          PaymentMethod.orange_money, PaymentMethod.moov_money].where((m) => m != delivery.paymentMethod))
                          ListTile(leading: Icon(m.icon), title: Text(m.label), onTap: () => Navigator.pop(ctx, m)),
                      ]),
                    ),
                  );
                  if (m == null || !context.mounted) return;
                  await runWithLoader(context, () => ref.read(deliveryRepositoryProvider).changePaymentMethod(delivery.id, m),
                      success: 'Moyen de paiement modifié');
                },
                child: const Text('Changer de moyen de paiement'),
              ),
            ]),
          ),
        ),
      );
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({required this.delivery, required this.driver});
  final Delivery delivery;
  final AssignedDriver driver;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            Row(children: [
              UserAvatar(name: driver.fullName, url: driver.avatarUrl, radius: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(driver.firstName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  RatingDisplay(rating: driver.rating, count: driver.ratingCount),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(driver.vehicleType.icon, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        [driver.vehicleType.label, if (driver.vehicleLabel.isNotEmpty) driver.vehicleLabel].join(' · '),
                        style: const TextStyle(color: AppColors.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  if ((driver.plateNumber ?? '').isNotEmpty) Pill(driver.plateNumber!, color: const Color(0xFF111827)),
                ]),
              ),
              if (delivery.status.headingToPickup && delivery.etaMinutes != null)
                Column(children: [
                  Text('${delivery.etaMinutes}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.info)),
                  const Text('min', style: TextStyle(color: AppColors.textMuted)),
                ]),
            ]),
            if (delivery.status.isActive) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => callPhone(driver.phone),
                    icon: const Icon(Icons.call),
                    label: const Text('Appeler'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/chat/${delivery.id}'),
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Message'),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      );
}

class _OtpCard extends ConsumerWidget {
  const _OtpCard({required this.delivery});
  final Delivery delivery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final otp = ref.watch(deliveryOtpProvider(delivery.id)).value;
    if (otp == null) return const SizedBox.shrink();
    final msg = 'Telima : votre colis ${delivery.code} arrive. Donnez le code $otp au livreur à la réception.';
    final selfOnly = delivery.isRide || delivery.isErrand; // le client lui-même donne le code
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: const Color(0xFFFFF7E6),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const Text('Code de livraison', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(otp.split('').join(' '), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 6)),
            const SizedBox(height: 6),
            Text(
                delivery.isRide
                    ? 'Donnez ce code au chauffeur à l’arrivée pour terminer le trajet.'
                    : delivery.isErrand
                        ? 'Donnez ce code au livreur quand il vous remet vos achats.'
                        : 'À communiquer à ${delivery.dropoffContactName}. Le livreur le saisit à la remise du colis.',
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 10),
            if (!selfOnly) Wrap(spacing: 8, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => sendSms(delivery.dropoffContactPhone, msg),
                icon: const Icon(Icons.sms_outlined),
                label: const Text('Par SMS'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => openWhatsApp(delivery.dropoffContactPhone, msg),
                icon: const Icon(Icons.chat),
                label: const Text('WhatsApp'),
              ),
              IconButton(
                tooltip: 'Copier',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: otp));
                  showSuccess(context, 'Code copié');
                },
                icon: const Icon(Icons.copy),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _RateCard extends ConsumerStatefulWidget {
  const _RateCard({required this.delivery});
  final Delivery delivery;
  @override
  ConsumerState<_RateCard> createState() => _RateCardState();
}

class _RateCardState extends ConsumerState<_RateCard> {
  int _stars = 0;
  final _comment = TextEditingController();
  bool _sending = false;
  bool? _alreadyRated;

  @override
  void initState() {
    super.initState();
    ref.read(deliveryRepositoryProvider).myRating(widget.delivery.id).then((r) {
      if (!mounted) return;
      setState(() {
        _alreadyRated = r != null;
        if (r != null) _stars = (r['stars'] as num).toInt();
      });
    }).catchError((_) {});
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await ref.read(deliveryRepositoryProvider).rate(widget.delivery.id, _stars, _comment.text);
      if (mounted) {
        setState(() => _alreadyRated = true);
        showSuccess(context, 'Merci pour votre avis !');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_alreadyRated == null || widget.delivery.driverId == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _alreadyRated!
              ? Column(children: [
                  const Text('Votre évaluation', style: TextStyle(fontWeight: FontWeight.w700)),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 1; i <= 5; i++)
                      Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, color: AppColors.accent, size: 30),
                  ]),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Comment s\'est passée votre livraison ?',
                      textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  StarInput(value: _stars, onChanged: (v) => setState(() => _stars = v)),
                  TextField(
                    controller: _comment,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Commentaire (facultatif)'),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _stars == 0 || _sending ? null : _send, child: const Text('Envoyer mon avis')),
                ]),
        ),
      ),
    );
  }
}

class _BatchStops extends ConsumerWidget {
  const _BatchStops({required this.batchId, required this.currentId});
  final String batchId;
  final String currentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stops = ref.watch(batchProvider(batchId)).value ?? const [];
    if (stops.length < 2) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Tournée multi-destinations'),
      Card(
        child: Column(children: [
          for (final s in stops)
            ListTile(
              selected: s.id == currentId,
              leading: CircleAvatar(radius: 14, child: Text('${s.stopOrder}', style: const TextStyle(fontSize: 12))),
              title: Text(s.dropoffAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${s.dropoffContactName} · ${s.code}'),
              trailing: StatusChip(s.status),
              onTap: s.id == currentId ? null : () => context.pushReplacement('/client/delivery/${s.id}'),
            ),
        ]),
      ),
    ]);
  }
}

/// Course à faire : liste d'achats, budget, montant payé par le livreur et remboursement.
class _ErrandCard extends ConsumerWidget {
  const _ErrandCard({required this.delivery});
  final Delivery delivery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = delivery;
    final amount = d.purchaseAmount;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon3D(Ico3D.bags, size: 34),
              const SizedBox(width: 10),
              Expanded(child: Text('Vos achats · ${errandCategoryLabel(d.errandCategory)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            ]),
            const SizedBox(height: 8),
            Text(d.errandItems ?? '', style: const TextStyle(height: 1.4)),
            if (d.errandBudget != null) ...[
              const SizedBox(height: 6),
              Text('Budget maximum : ${fcfa(d.errandBudget!)}', style: const TextStyle(color: AppColors.textMuted)),
            ],
            const Divider(height: 22),
            if (amount == null)
              const Text('Le livreur indiquera ici le montant payé, avec la photo du ticket.',
                  style: TextStyle(color: AppColors.textMuted))
            else ...[
              Row(children: [
                Expanded(child: Text('Achats${d.purchaseShop == null ? '' : ' · ${d.purchaseShop}'}')),
                Text(fcfa(amount), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
              if (d.errandBudget != null && amount > d.errandBudget!)
                const Text('Budget dépassé : le livreur vous a sans doute appelé.', style: TextStyle(color: AppColors.accent, fontSize: 12.5)),
              if (d.purchaseReceiptPath != null)
                TextButton.icon(
                  onPressed: () async {
                    final url = await ref.read(storageServiceProvider).signedUrl('proofs', d.purchaseReceiptPath!, seconds: 600);
                    if (!context.mounted) return;
                    showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(url))));
                  },
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('Voir le ticket'),
                ),
              const SizedBox(height: 6),
              if (d.purchaseSettled)
                Text(d.purchaseSettlement == 'wallet' ? '✅ Remboursé par votre portefeuille' : '✅ Remboursé en espèces',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))
              else ...[
                Text('À rembourser au livreur à la livraison : ${fcfa(amount)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await confirmDialog(context,
                        title: 'Payer ${fcfa(amount)} avec le portefeuille ?',
                        message: 'Le montant des achats est versé au livreur. Vous n’aurez rien à lui donner en espèces.',
                        confirmLabel: 'Payer');
                    if (!ok || !context.mounted) return;
                    await runWithLoader(context, () => ref.read(deliveryRepositoryProvider).settlePurchaseWithWallet(d.id),
                        success: 'Achats remboursés au livreur');
                    ref.invalidate(myWalletProvider);
                  },
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Payer avec mon portefeuille'),
                ),
              ],
            ],
          ]),
        ),
      ),
    );
  }
}
