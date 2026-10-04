import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../data/models/delivery.dart';
import '../../data/models/enums.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../providers/driver_tracking.dart';
import '../../widgets/common.dart';
import '../../widgets/delivery_widgets.dart';
import '../../widgets/live_tracking.dart';

/// Écran de course du livreur : carte, étape suivante, contacts, preuve de livraison.
class DriverCourseScreen extends ConsumerWidget {
  const DriverCourseScreen({super.key, required this.deliveryId});
  final String deliveryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(deliveryStreamProvider(deliveryId));
    return Scaffold(
      appBar: AppBar(title: Text(async.value?.code ?? 'Course')),
      body: AsyncBody<Delivery?>(
        value: async,
        onRetry: () => ref.invalidate(deliveryStreamProvider(deliveryId)),
        builder: (d) => d == null ? const EmptyState(icon: Icons.search_off, message: 'Course introuvable') : _CourseBody(delivery: d),
      ),
    );
  }
}

class _CourseBody extends ConsumerStatefulWidget {
  const _CourseBody({required this.delivery});
  final Delivery delivery;
  @override
  ConsumerState<_CourseBody> createState() => _CourseBodyState();
}

class _CourseBodyState extends ConsumerState<_CourseBody> {
  bool _busy = false;

  /// État affiché de manière optimiste quand l'étape a été mise en file hors connexion.
  DeliveryStatus? _optimistic;

  Delivery get d => widget.delivery;
  DeliveryStatus get status => _optimistic != null && _optimistic!.step > d.status.step ? _optimistic! : d.status;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(driverTrackingProvider.notifier).start());
  }

  /// Course à faire : montant payé chez le commerçant + photo du ticket.
  Future<bool> _enterPurchase() async {
    final res = await showDialog<bool>(context: context, builder: (_) => _PurchaseDialog(delivery: d));
    if (res == true) ref.invalidate(deliveryStreamProvider(d.id));
    return res == true;
  }

  Future<void> _advance() async {
    final next = status.nextForDriver;
    if (d.isErrand && next == DeliveryStatus.picked_up && d.purchaseAmount == null) {
      if (!await _enterPurchase()) return;
    }
    if (next == null) {
      if (status == DeliveryStatus.at_dropoff) _openProof();
      return;
    }
    setState(() => _busy = true);
    try {
      final pos = ref.read(driverTrackingProvider).lastPosition;
      final queued = await ref.read(driverRepositoryProvider).advance(d.id, next, lat: pos?.latitude, lng: pos?.longitude);
      setState(() => _optimistic = next);
      if (queued && mounted) showSuccess(context, 'Hors connexion : l\'étape sera envoyée automatiquement.');
      ref.invalidate(deliveryStreamProvider(d.id));
      ref.invalidate(deliveryHistoryProvider(d.id));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openProof() async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ProofOfDeliveryScreen(delivery: d)));
    if (done == true && mounted) {
      ref.invalidate(activeCoursesProvider);
      ref.invalidate(driverEarningsProvider);
      final remaining = d.isBatch
          ? (await ref.read(deliveryRepositoryProvider).batch(d.batchId!)).where((x) => x.status.isActive && x.id != d.id).toList()
          : const <Delivery>[];
      if (!mounted) return;
      if (remaining.isNotEmpty) {
        context.pushReplacement('/driver/course/${remaining.first.id}');
      } else {
        context.go('/driver');
      }
    }
  }

  Future<void> _release() async {
    final reason = await promptDialog(context, title: 'Abandonner la course', label: 'Motif (panne, client injoignable…)');
    if (reason == null || !mounted) return;
    try {
      await ref.read(driverRepositoryProvider).release(d.id, reason);
      ref.invalidate(activeCoursesProvider);
      if (mounted) {
        showSuccess(context, 'Course libérée');
        context.go('/driver');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracking = ref.watch(driverTrackingProvider);
    final s = status;
    final atPickupPhase = s.headingToPickup;
    final contactName = atPickupPhase ? d.pickupContactName : d.dropoffContactName;
    final contactPhone = atPickupPhase ? d.pickupContactPhone : d.dropoffContactPhone;
    final instructions = atPickupPhase ? d.pickupInstructions : d.dropoffInstructions;
    final target = atPickupPhase ? d.pickup : d.dropoff;
    final phaseLabel = d.isRide
        ? (atPickupPhase ? 'Prise en charge du passager' : 'Destination')
        : d.isErrand
            ? (atPickupPhase ? 'Achats à faire (commerce de votre choix)' : 'Livraison chez le client')
            : (atPickupPhase ? 'Récupération' : 'Livraison');
    final collect = switch (d.paymentMethod) {
      PaymentMethod.cash when atPickupPhase => 'À encaisser au départ : ${fcfa(d.totalPrice)}',
      PaymentMethod.cash_on_delivery when !atPickupPhase => 'À encaisser à la livraison : ${fcfa(d.totalPrice)}',
      _ => null,
    };

    if (s.isFinished) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Icon(s == DeliveryStatus.completed ? Icons.check_circle : Icons.cancel, color: s.color, size: 64),
              const SizedBox(height: 8),
              Text(s == DeliveryStatus.completed
                      ? (d.isRide ? 'Trajet terminé.' : d.isErrand ? 'Course terminée avec succès.' : 'Livraison terminée avec succès.')
                      : 'Course annulée',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              if (s == DeliveryStatus.completed) Text('Gain : ${fcfa(d.driverEarning)}', style: const TextStyle(fontSize: 16)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        DeliveryDetailsCard(delivery: d, showCommission: true),
      ]);
    }

    return Column(children: [
      Expanded(
        child: Constrained(
          maxWidth: 720,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            LiveTrackingMap(delivery: d, driverPosition: tracking.lastPosition, height: 260),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    StatusChip(s, label: kindStatusLabel(d.kind, s)),
                    if (d.isBatch) ...[const SizedBox(width: 8), Pill('Arrêt ${d.stopOrder}', color: AppColors.info)],
                    const Spacer(),
                    Text(fcfa(d.driverEarning), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary, fontSize: 18)),
                  ]),
                  const SizedBox(height: 12),
                  Text(phaseLabel, style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
                  if (d.isErrand && atPickupPhase)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
                      child: Text('🛍️ ${d.errandItems ?? ''}${d.errandBudget != null ? '\n\nBudget max : ${fcfa(d.errandBudget!)}' : ''}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.35)),
                    )
                  else
                    Text(atPickupPhase ? d.pickupAddress : d.dropoffAddress, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  if (d.isErrand && atPickupPhase)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Livrer ensuite à : ${d.dropoffAddress}', style: const TextStyle(color: AppColors.textMuted)),
                    ),
                  if (d.isRide && d.ridePassengers > 1)
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text('${d.ridePassengers} passagers')),
                  if ((instructions ?? '').isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        const Icon(Icons.info_outline, color: AppColors.accent),
                        const SizedBox(width: 8),
                        Expanded(child: Text(instructions!, style: const TextStyle(fontWeight: FontWeight.w600))),
                      ]),
                    ),
                  const SizedBox(height: 10),
                  Text('$contactName · ${displayPhone(contactPhone)}'),
                  if (collect != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('💰 $collect', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                  if (d.packageFragile)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('⚠️ Colis FRAGILE', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.danger)),
                    ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(onPressed: () => callPhone(contactPhone), icon: const Icon(Icons.call), label: const Text('Appeler')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(onPressed: () => openNavigation(target), icon: const Icon(Icons.navigation), label: const Text('Itinéraire')),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    if (d.customerId != null)
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => context.push('/chat/${d.id}'),
                          icon: const Icon(Icons.chat_outlined),
                          label: const Text('Message au client'),
                        ),
                      ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => callPhone(d.customerPhone),
                        icon: const Icon(Icons.person),
                        label: const Text('Appeler le client'),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
            if (d.isErrand) _PurchaseCard(delivery: d, onEdit: _enterPurchase, atDropoff: !atPickupPhase),
            if (d.isBatch) _BatchList(batchId: d.batchId!, currentId: d.id),
            const SectionTitle('Détails'),
            DeliveryDetailsCard(delivery: d, showCommission: true),
            if (s.canDriverRelease)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: _release,
                icon: const Icon(Icons.undo),
                label: const Text('Abandonner la course'),
              ),
            const SizedBox(height: 16),
          ]),
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Constrained(
            maxWidth: 720,
            child: BigActionButton(
              label: driverActionLabelFor(d.kind, s),
              icon: s == DeliveryStatus.at_dropoff ? Icons.verified : Icons.arrow_forward,
              color: s == DeliveryStatus.at_dropoff ? AppColors.accent : null,
              loading: _busy,
              onPressed: _advance,
            ),
          ),
        ),
      ),
    ]);
  }
}

class _BatchList extends ConsumerWidget {
  const _BatchList({required this.batchId, required this.currentId});
  final String batchId;
  final String currentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stops = ref.watch(batchProvider(batchId)).value ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Tournée'),
      Card(
        child: Column(children: [
          for (final s in stops)
            ListTile(
              selected: s.id == currentId,
              leading: CircleAvatar(radius: 14, child: Text('${s.stopOrder}', style: const TextStyle(fontSize: 12))),
              title: Text(s.dropoffContactName),
              subtitle: Text(s.dropoffAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: StatusChip(s.status),
              onTap: s.id == currentId || !s.status.isActive ? null : () => context.pushReplacement('/driver/course/${s.id}'),
            ),
        ]),
      ),
    ]);
  }
}

/// Preuve de livraison : code OTP du destinataire, photo, signature, nom du réceptionnaire.
class ProofOfDeliveryScreen extends ConsumerStatefulWidget {
  const ProofOfDeliveryScreen({super.key, required this.delivery});
  final Delivery delivery;
  @override
  ConsumerState<ProofOfDeliveryScreen> createState() => _ProofOfDeliveryScreenState();
}

class _ProofOfDeliveryScreenState extends ConsumerState<ProofOfDeliveryScreen> {
  final _otp = TextEditingController();
  final _name = TextEditingController();
  final _signature = SignatureController(penStrokeWidth: 3, penColor: Colors.black, exportBackgroundColor: Colors.white);
  XFile? _photo;
  bool _withSignature = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _signature.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final settings = await ref.read(settingsProvider.future);
    final otpRequired = settings.proofMode == 'otp';
    if (otpRequired && _otp.text.length != 4) {
      setState(() => _error = 'Saisissez le code à 4 chiffres donné par ${widget.delivery.isRide ? 'le passager' : widget.delivery.isErrand ? 'le client' : 'le destinataire'}');
      return;
    }
    if (!otpRequired && _otp.text.isEmpty && _photo == null && _name.text.trim().isEmpty && _signature.isEmpty) {
      setState(() => _error = 'Ajoutez au moins une preuve (code, photo, signature ou nom)');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final storage = ref.read(storageServiceProvider);
      String? photoPath;
      String? signaturePath;
      if (_photo != null) photoPath = await storage.uploadXFile('proofs', _photo!);
      if (_withSignature && _signature.isNotEmpty) {
        final png = await _signature.toPngBytes();
        if (png != null) signaturePath = await storage.uploadBytes('proofs', png, ext: 'png', contentType: 'image/png');
      }
      final pos = ref.read(driverTrackingProvider).lastPosition;
      final res = await ref.read(driverRepositoryProvider).complete(
            widget.delivery.id,
            otp: _otp.text.isEmpty ? null : _otp.text,
            receiverName: _name.text.trim().isEmpty ? null : _name.text.trim(),
            photoPath: photoPath,
            signaturePath: signaturePath,
            lat: pos?.latitude,
            lng: pos?.longitude,
          );
      if (!mounted) return;
      if (res == null) {
        setState(() => _error = 'Code incorrect. Vérifiez auprès ${widget.delivery.isRide ? 'du passager' : 'du destinataire'}.');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: AppColors.primary, size: 56),
          title: Text(widget.delivery.isRide ? 'Trajet terminé.' : 'Livraison terminée avec succès.'),
          content: Text(widget.delivery.paymentMethod == PaymentMethod.cash_on_delivery
              ? 'Pensez à encaisser ${fcfa(widget.delivery.totalPrice)}.\nVotre gain : ${fcfa(widget.delivery.driverEarning)}'
              : 'Votre gain : ${fcfa(widget.delivery.driverEarning)}'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final otpRequired = (ref.watch(settingsProvider).value?.proofMode ?? 'otp') == 'otp';
    return Scaffold(
      appBar: AppBar(title: Text(widget.delivery.isRide ? 'Fin du trajet' : widget.delivery.isErrand ? 'Remise des achats' : 'Remise du colis')),
      body: Constrained(
        maxWidth: 560,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Demandez le code de livraison à ${widget.delivery.dropoffContactName}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(
            controller: _otp,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            autofocus: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 16),
            decoration: InputDecoration(labelText: otpRequired ? 'Code à 4 chiffres' : 'Code (facultatif)', counterText: ''),
          ),
          const SectionTitle('Preuves complémentaires'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nom de la personne qui réceptionne', prefixIcon: Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final f = await ref.read(storageServiceProvider).pickImage(camera: true);
              if (f != null) setState(() => _photo = f);
            },
            icon: Icon(_photo == null ? Icons.photo_camera_outlined : Icons.check_circle, color: _photo == null ? null : AppColors.primary),
            label: Text(_photo == null ? 'Photo de remise' : 'Photo ajoutée (reprendre)'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _withSignature,
            onChanged: (v) => setState(() => _withSignature = v),
            title: const Text('Signature du destinataire'),
          ),
          if (_withSignature) ...[
            Container(
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD1D5DB)), borderRadius: BorderRadius.circular(12)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Signature(controller: _signature, height: 180, backgroundColor: Colors.white),
              ),
            ),
            TextButton(onPressed: _signature.clear, child: const Text('Effacer la signature')),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 20),
          BigActionButton(label: 'Valider la livraison', icon: Icons.verified, color: AppColors.accent, loading: _submitting, onPressed: _submit),
        ]),
      ),
    );
  }
}

/// Course à faire : montant des achats, ticket et remboursement par le client.
class _PurchaseCard extends ConsumerWidget {
  const _PurchaseCard({required this.delivery, required this.onEdit, required this.atDropoff});
  final Delivery delivery;
  final Future<bool> Function() onEdit;
  final bool atDropoff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = delivery;
    final amount = d.purchaseAmount;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: const Color(0xFFFFF7E6),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Achats', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            if (amount == null)
              const Text('Après l’achat, saisissez le montant payé et photographiez le ticket : le client est prévenu aussitôt.')
            else
              Text('${fcfa(amount)}${d.purchaseShop == null ? '' : ' · ${d.purchaseShop}'}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            if (d.purchaseSettled)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(d.purchaseSettlement == 'wallet' ? '✅ Remboursé sur votre portefeuille' : '✅ Remboursé en espèces',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
              )
            else ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => onEdit(),
                icon: Icon(amount == null ? Icons.add_shopping_cart_rounded : Icons.edit_rounded),
                label: Text(amount == null ? 'Saisir le montant des achats' : 'Modifier le montant'),
              ),
              if (amount != null && atDropoff) ...[
                const SizedBox(height: 8),
                Text('💰 À récupérer auprès du client : ${fcfa(amount)} (ou payé depuis son portefeuille)',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                FilledButton.icon(
                  onPressed: () => runWithLoader(context, () => ref.read(driverRepositoryProvider).settlePurchaseCash(d.id),
                      success: 'Remboursement enregistré'),
                  icon: const Icon(Icons.payments_rounded),
                  label: const Text('Le client m’a remboursé en espèces'),
                ),
              ],
            ],
          ]),
        ),
      ),
    );
  }
}

class _PurchaseDialog extends ConsumerStatefulWidget {
  const _PurchaseDialog({required this.delivery});
  final Delivery delivery;
  @override
  ConsumerState<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends ConsumerState<_PurchaseDialog> {
  late final _amount = TextEditingController(text: widget.delivery.purchaseAmount?.toString() ?? '');
  late final _shop = TextEditingController(text: widget.delivery.purchaseShop ?? '');
  XFile? _receipt;
  bool _busy = false;

  Future<void> _save() async {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), ''));
    if (amount == null || amount <= 0) {
      showError(context, Exception('Indiquez le montant payé'));
      return;
    }
    final budget = widget.delivery.errandBudget;
    if (budget != null && amount > budget) {
      final ok = await confirmDialog(context,
          title: 'Budget dépassé',
          message: 'Le client a fixé ${fcfa(budget)} maximum. L’avez-vous appelé pour accord ?',
          confirmLabel: 'Oui, il est d’accord');
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      String? path;
      if (_receipt != null) path = await ref.read(storageServiceProvider).uploadXFile('proofs', _receipt!);
      await ref.read(driverRepositoryProvider).setPurchase(widget.delivery.id, amount,
          shop: _shop.text.trim().isEmpty ? null : _shop.text.trim(), receiptPath: path);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Montant des achats'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Montant payé', suffixText: 'FCFA'),
            ),
            const SizedBox(height: 10),
            TextField(controller: _shop, decoration: const InputDecoration(labelText: 'Commerce (facultatif)', hintText: 'Ex. Pharmacie du Progrès')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final f = await ref.read(storageServiceProvider).pickImage(camera: true);
                      if (f != null) setState(() => _receipt = f);
                    },
              icon: Icon(_receipt == null ? Icons.photo_camera_rounded : Icons.check_circle_rounded,
                  color: _receipt == null ? null : AppColors.primary),
              label: Text(_receipt == null ? 'Photo du ticket' : 'Ticket ajouté'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Enregistrer'),
          ),
        ],
      );
}
