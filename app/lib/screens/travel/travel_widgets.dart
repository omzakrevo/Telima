import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/theme.dart';
import '../../core/services/file_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/travel.dart';
import '../../widgets/common.dart';
import '../../widgets/qr_link_sheet.dart';
import '../restaurant/restaurant_widgets.dart' show InfoTag, PhotoBox;

/// Jour d'un départ : « mer. 15 oct. ».
String travelDay(DateTime d) => DateFormat('EEE d MMM', 'fr_FR').format(d.toLocal());

/// Durée lisible : 330 → « 5 h 30 ».
String travelDuration(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

/// Carte d'un départ : trajet, heure, compagnie, classe, prix, places.
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.trip, this.onTap, this.showCompany = true, this.trailing});
  final TravelTrip trip;
  final VoidCallback? onTap;
  final bool showCompany;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final seatsColor = t.full ? AppColors.danger : (t.seatsAvailable <= 5 ? AppColors.accent : AppColors.primary);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // En-tête : la compagnie (recherche), ou le jour du départ (page d'une compagnie, espace compagnie)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              if (showCompany) ...[
                PhotoBox(url: travelPhotoUrl(t.companyLogo), size: 30, radius: 8, icon: Icons.directions_bus_rounded),
                const SizedBox(width: 8),
                Expanded(child: Text(t.companyName ?? '', style: const TextStyle(fontWeight: FontWeight.w800))),
              ] else ...[
                const Icon(Icons.event_rounded, size: 18, color: AppColors.primaryDark),
                const SizedBox(width: 6),
                Expanded(child: Text(travelDay(t.departureAt), style: const TextStyle(fontWeight: FontWeight.w800))),
              ],
              if ((t.busClass ?? '').isNotEmpty) InfoTag(t.busClass!, color: AppColors.info),
            ]),
          ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(formatTime(t.departureAt), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                Text(t.fromCity, style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(children: [
                const Icon(Icons.arrow_forward_rounded, color: AppColors.textMuted),
                if (t.durationMinutes != null)
                  Text(travelDuration(t.durationMinutes!), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(t.arrivalAt == null ? '—' : formatTime(t.arrivalAt), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                Text(t.toCity, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: showCompany
                  ? Text(travelDay(t.departureAt),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600))
                  : const SizedBox(),
            ),
            if (t.cancelled)
              const InfoTag('Annulé', color: AppColors.danger)
            else
              InfoTag(t.full ? 'Complet' : '${t.seatsAvailable} place${t.seatsAvailable > 1 ? 's' : ''}', color: seatsColor),
            const SizedBox(width: 10),
            Text(fcfa(t.price), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.primaryDark)),
            ?trailing,
          ]),
        ]),
      ),
    );
  }
}

/// Étiquette colorée du statut d'une réservation.
class BookingStatusTag extends StatelessWidget {
  const BookingStatusTag(this.booking, {super.key});
  final TravelBooking booking;
  @override
  Widget build(BuildContext context) => InfoTag(booking.statusLabel, color: booking.statusColor);
}

/// E-ticket : QR code à présenter à l'embarquement, avec le code et les voyageurs. Téléchargeable en image.
class ETicketCard extends StatefulWidget {
  const ETicketCard({super.key, required this.booking});
  final TravelBooking booking;

  @override
  State<ETicketCard> createState() => _ETicketCardState();
}

class _ETicketCardState extends State<ETicketCard> {
  bool _busy = false;

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final b = widget.booking;
      final png = await renderQrPng(b.qrData);
      await exportBytesFile('e-ticket-${b.code}.png', png);
      if (mounted) showSuccess(context, 'E-ticket enregistré');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final t = b.trip;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.confirmation_number_rounded, color: AppColors.primaryDark),
          const SizedBox(width: 8),
          const Expanded(child: Text('E-TICKET', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5))),
          Text(b.code, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
        ]),
        const SizedBox(height: 10),
        if (b.status == 'boarded')
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Text('Ticket utilisé · embarqué ${b.boardedAt == null ? '' : 'le ${formatDateTime(b.boardedAt)}'}',
                style: const TextStyle(color: AppColors.info, fontWeight: FontWeight.w700)),
          ),
        QrImageView(
          data: b.qrData,
          size: 220,
          backgroundColor: Colors.white,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          semanticsLabel: 'QR code du ticket ${b.code}',
        ),
        const SizedBox(height: 6),
        const Text('À présenter à l’embarquement', style: TextStyle(color: AppColors.textMuted)),
        const Divider(height: 22),
        if (t != null) ...[
          _Line('Trajet', t.route),
          _Line('Départ', formatDateTime(t.departureAt)),
          if ((t.departureStation ?? '').isNotEmpty) _Line('Gare', t.departureStation!),
          if ((t.busClass ?? '').isNotEmpty) _Line('Classe', t.busClass!),
        ],
        if (b.companyName != null) _Line('Compagnie', b.companyName!),
        _Line('Voyageurs', b.passengerNames.isEmpty ? '${b.passengers}' : '${b.passengers} · ${b.passengerNames.join(', ')}'),
        if ((b.seatNumbers ?? '').isNotEmpty) _Line('Places', b.seatNumbers!),
        if ((b.ticketNumber ?? '').isNotEmpty) _Line('N° de ticket', b.ticketNumber!),
        _Line('Paiement', b.paymentHint),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _download,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded),
            label: const Text('Télécharger le QR code du ticket'),
          ),
        ),
      ]),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 104, child: Text(label, style: const TextStyle(color: AppColors.textMuted))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Lien de la compagnie : copier, partager, QR code
// ---------------------------------------------------------------------------

Future<void> shareCompanyLink(BuildContext context, TransportCompany c) async {
  final text = 'Réservez vos tickets ${c.name} sur Telima : ${companyShareLink(c.slug)}';
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: c.name));
  } catch (_) {
    if (!context.mounted) return;
    await copyCompanyLink(context, c);
  }
}

Future<void> copyCompanyLink(BuildContext context, TransportCompany c) async {
  await Clipboard.setData(ClipboardData(text: companyShareLink(c.slug)));
  if (context.mounted) showSuccess(context, 'Lien copié');
}

Future<void> showCompanyQr(BuildContext context, TransportCompany c) =>
    showQrLinkSheet(context, title: c.name, link: companyShareLink(c.slug), slug: c.slug);

class CompanyLinkCard extends StatelessWidget {
  const CompanyLinkCard({super.key, required this.company});
  final TransportCompany company;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.link_rounded, color: AppColors.primaryDark),
            SizedBox(width: 8),
            Text('Le lien de votre compagnie', style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 6),
          SelectableText(companyShareLink(company.slug), style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Partagez-le ou affichez le QR code au guichet : vos voyageurs voient les départs et réservent directement.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.3)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => copyCompanyLink(context, company),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copier'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => shareCompanyLink(context, company),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Partager'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showCompanyQr(context, company),
              icon: const Icon(Icons.qr_code_2_rounded, size: 20),
              label: const Text('QR code à télécharger'),
            ),
          ),
        ]),
      );
}
