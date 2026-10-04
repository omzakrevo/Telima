import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../core/utils/formatters.dart';
import '../data/models/delivery.dart';
import '../data/models/enums.dart';
import '../providers/core_providers.dart';
import '../providers/data_providers.dart';
import 'common.dart';
import 'icon3d.dart';

/// Carte d'une livraison dans une liste.
class DeliveryListTile extends StatelessWidget {
  const DeliveryListTile({super.key, required this.delivery, required this.onTap, this.showDriver = false, this.showEarning = false});
  final Delivery delivery;
  final VoidCallback onTap;
  final bool showDriver;
  final bool showEarning;

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Icon3D(d.isRide ? Ico3D.taxi : d.isErrand ? Ico3D.bags : Ico3D.package, size: 30, shadow: false),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.code, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(formatDateTime(d.createdAt), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ]),
              ),
              StatusChip(d.status, label: d.statusLabel()),
            ]),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Column(children: [
                  _Dot(color: AppColors.primary),
                  SizedBox(height: 2),
                  SizedBox(height: 14, child: VerticalDivider(width: 2, thickness: 1.5, color: AppColors.line)),
                  SizedBox(height: 2),
                  _Dot(color: AppColors.ink),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.pickupAddress, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Text(d.dropoffAddress, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              if (showDriver && d.driverName != null) ...[
                const Icon(Icons.delivery_dining_rounded, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(d.driverName!,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12), overflow: TextOverflow.ellipsis),
                ),
              ],
              const Spacer(),
              Text(fcfa(showEarning ? d.driverEarning : d.totalPrice),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.3)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Détails complets (adresses, contacts, colis, prix, paiement, preuve).
class DeliveryDetailsCard extends ConsumerWidget {
  const DeliveryDetailsCard({super.key, required this.delivery, this.showCommission = false, this.showCustomer = false});
  final Delivery delivery;
  final bool showCommission;
  final bool showCustomer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = delivery;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (showCustomer) ...[
            _block('Client', [d.customerName, displayPhone(d.customerPhone)], Icons.person, AppColors.info),
            const Divider(height: 24),
          ],
          _block('Récupération', [d.pickupAddress, '${d.pickupContactName} · ${displayPhone(d.pickupContactPhone)}', ?d.pickupInstructions],
              Icons.store_mall_directory, AppColors.primary),
          const Divider(height: 24),
          _block('Destination', [d.dropoffAddress, '${d.dropoffContactName} · ${displayPhone(d.dropoffContactPhone)}', ?d.dropoffInstructions],
              Icons.flag, AppColors.danger),
          const Divider(height: 24),
          InfoRow(label: 'Colis', value: '${d.packageCategory.label} × ${d.packageQuantity}'),
          if ((d.packageDescription ?? '').isNotEmpty) InfoRow(label: 'Description', value: d.packageDescription!),
          InfoRow(label: 'Taille', value: d.packageSize.label),
          if (d.packageFragile) const InfoRow(label: 'Fragile', value: 'Oui ⚠️'),
          if (d.packageWeightKg != null) InfoRow(label: 'Poids', value: '${d.packageWeightKg} kg'),
          InfoRow(label: 'Véhicule', value: d.vehicleType.label),
          if (d.packagePhotoPath != null) _PrivateImage(bucket: 'package-photos', path: d.packagePhotoPath!, label: 'Photo du colis'),
          const Divider(height: 24),
          InfoRow(label: 'Distance', value: km(d.distanceKm)),
          InfoRow(label: 'Livraison', value: fcfa(d.priceBase + d.priceDistance)),
          if (d.priceExtras > 0) InfoRow(label: 'Options', value: fcfa(d.priceExtras)),
          if (d.priceZone != 0) InfoRow(label: 'Zone', value: fcfa(d.priceZone)),
          InfoRow(label: 'Total', value: fcfa(d.totalPrice), bold: true),
          if (showCommission) ...[
            InfoRow(label: 'Commission plateforme', value: fcfa(d.commissionAmount)),
            InfoRow(label: 'Part livreur', value: fcfa(d.driverEarning)),
          ],
          InfoRow(label: 'Paiement', value: '${d.paymentMethod.label} · ${d.paymentStatus.label}'),
          if (d.proofType != null) ...[
            const Divider(height: 24),
            InfoRow(label: 'Preuve', value: d.proofType!.label),
            if (d.receiverName != null) InfoRow(label: 'Réceptionné par', value: d.receiverName!),
            if (d.proofPhotoPath != null) _PrivateImage(bucket: 'proofs', path: d.proofPhotoPath!, label: 'Photo de remise'),
            if (d.proofSignaturePath != null) _PrivateImage(bucket: 'proofs', path: d.proofSignaturePath!, label: 'Signature'),
          ],
        ]),
      ),
    );
  }

  Widget _block(String title, List<String> lines, IconData icon, Color color) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            Text(lines.first, style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final l in lines.skip(1).where((l) => l.trim().isNotEmpty)) Text(l, style: const TextStyle(fontSize: 13)),
          ]),
        ),
      ]);
}

/// Image d'un compartiment privé, affichée via une URL signée temporaire.
class _PrivateImage extends ConsumerWidget {
  const _PrivateImage({required this.bucket, required this.path, required this.label});
  final String bucket;
  final String path;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<String>(
        future: ref.read(storageServiceProvider).signedUrl(bucket, path),
        builder: (context, snap) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 4),
            if (snap.hasData)
              GestureDetector(
                onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(snap.data!)))),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(snap.data!, height: 140, fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Text('Image indisponible')),
                ),
              )
            else if (snap.hasError)
              const Text('Image indisponible')
            else
              const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          ]),
        ),
      );
}

/// Historique horodaté des étapes.
class StatusTimeline extends ConsumerWidget {
  const StatusTimeline({super.key, required this.deliveryId, required this.current});
  final String deliveryId;
  final DeliveryStatus current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(deliveryHistoryProvider(deliveryId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: history.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(deliveryHistoryProvider(deliveryId))),
          data: (entries) => Column(children: [
            for (var i = 0; i < entries.length; i++)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(children: [
                  Icon(Icons.circle, size: 12, color: entries[i].status.color),
                  if (i < entries.length - 1) Container(width: 2, height: 30, color: const Color(0xFFE5E7EB)),
                ]),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(entries[i].status.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if ((entries[i].note ?? '').isNotEmpty)
                        Text(entries[i].note!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ]),
                  ),
                ),
                Text(formatDateTime(entries[i].createdAt), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
          ]),
        ),
      ),
    );
  }
}
