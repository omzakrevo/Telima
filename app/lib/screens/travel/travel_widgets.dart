import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/theme.dart';
import '../../core/services/file_export.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/travel.dart';
import '../../data/models/travel_brand.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../../widgets/qr_link_sheet.dart';
import '../restaurant/restaurant_widgets.dart' show InfoTag;

/// Jour d'un départ : « mer. 15 oct. ».
String travelDay(DateTime d) => DateFormat('EEE d MMM', 'fr_FR').format(d.toLocal());

/// Durée lisible : 330 → « 5 h 30 ».
String travelDuration(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

/// « Auj. », « Demain » ou « ven. 17 oct. ».
String dayChipLabel(DateTime d) {
  final now = DateTime.now(), l = d.toLocal();
  bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  if (same(l, now)) return 'Auj.';
  if (same(l, now.add(const Duration(days: 1)))) return 'Demain';
  return travelDay(l);
}

/// Prix compact : « 7 500 F ».
String shortFcfa(int price) => fcfa(price).replaceAll('FCFA', 'F');

/// Texte secondaire des écrans Voyages : plus foncé que le gris habituel pour rester lisible.
const travelMuted = Color(0xFF4E5A54);

/// Monogramme d'une compagnie (petites tailles) : initiales blanches sur un dégradé à sa couleur, ou logo envoyé par la compagnie.
class CompanyAvatar extends StatelessWidget {
  const CompanyAvatar({super.key, required this.slug, required this.name, this.logoPath, this.size = 48, this.radius = 14});
  final String? slug;
  final String? name;
  final String? logoPath;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final brand = companyBrand(slug);
    final initials = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [brand.color, Color.lerp(brand.color, Colors.black, 0.28)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Text(companyInitials(name), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
    );
    final url = travelPhotoUrl(logoPath);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null ? initials : Image.network(url, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => initials),
      ),
    );
  }
}

/// Logo d'une compagnie dans un cadre qui épouse sa forme et son fond : pas d'espace vide autour.
/// Sans logo embarqué : monogramme.
class CompanyLogoPlate extends StatelessWidget {
  const CompanyLogoPlate({super.key, required this.slug, required this.name, this.logoPath, this.height = 56, this.maxWidth = 160, this.radius = 14});
  final String? slug;
  final String? name;
  final String? logoPath;
  final double height;
  final double maxWidth;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final brand = companyBrand(slug);
    if (brand.logo == null) return CompanyAvatar(slug: slug, name: name, logoPath: logoPath, size: height, radius: radius);
    final width = (height * brand.logoAspect).clamp(height, maxWidth);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: brand.logoBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: brand.color.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [BoxShadow(color: brand.color.withValues(alpha: 0.22), blurRadius: 12, offset: const Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1.5),
        child: Image.asset(
          brand.logo!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => CompanyAvatar(slug: slug, name: name, size: height, radius: radius),
        ),
      ),
    );
  }
}

/// Puce de choix (heure, jour, ligne) : pleine et en dégradé quand elle est choisie, blanche et bordée sinon.
class TravelChip extends StatelessWidget {
  const TravelChip({super.key, required this.label, required this.selected, required this.onTap, this.color = AppColors.primary, this.icon});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.ink;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected ? LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.22)!], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
          color: selected ? null : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? Colors.transparent : color.withValues(alpha: 0.35)),
          boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (selected) ...[
            const Icon(Icons.check_rounded, size: 17, color: Colors.white),
            const SizedBox(width: 5),
          ] else if (icon != null) ...[
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
          ],
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
        ]),
      ),
    );
  }
}

/// Départ — trajet — arrivée : points reliés par une ligne pointillée, car au milieu, durée dessous.
class _TripTimeline extends StatelessWidget {
  const _TripTimeline({required this.trip, required this.color});
  final TravelTrip trip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = trip;
    Widget dot(Color c, {bool ring = false}) => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: ring ? Colors.white : c, shape: BoxShape.circle, border: Border.all(color: c, width: 3)),
        );
    Widget dashes() => Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final n = (box.maxWidth / 8).floor().clamp(1, 40);
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [for (var i = 0; i < n; i++) Container(width: 4, height: 2, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)))],
              );
            },
          ),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        flex: 3,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(formatTime(t.departureAt), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1)),
          const SizedBox(height: 2),
          Text(t.fromCity, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
      Expanded(
        flex: 3,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(children: [
            Row(children: [
              dot(color),
              dashes(),
              Icon(Icons.directions_bus_rounded, size: 20, color: color),
              dashes(),
              dot(AppColors.accent, ring: true),
            ]),
            if (t.durationMinutes != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(travelDuration(t.durationMinutes!), style: const TextStyle(fontSize: 12, color: travelMuted, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ),
      Expanded(
        flex: 3,
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(t.arrivalAt == null ? '—' : formatTime(t.arrivalAt),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1)),
          const SizedBox(height: 2),
          Text(t.toCity, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      ),
    ]);
  }
}

/// Carte d'un départ : compagnie, trajet, heures, classe, prix, places.
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.trip, this.onTap, this.showCompany = true, this.trailing});
  final TravelTrip trip;
  final VoidCallback? onTap;
  final bool showCompany;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final brand = companyBrand(t.companySlug);
    final seatsColor = t.full ? AppColors.danger : (t.seatsAvailable <= 5 ? AppColors.accent : AppColors.primary);
    return Opacity(
      opacity: onTap == null && !t.bookable ? 0.7 : 1,
      child: Pressable(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.line),
            boxShadow: [BoxShadow(color: brand.color.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 5))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // En-tête teinté : la compagnie (recherche) ou le jour du départ
              Container(
                color: brand.color.withValues(alpha: 0.07),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(children: [
                  if (showCompany) ...[
                    CompanyAvatar(slug: t.companySlug, name: t.companyName, logoPath: t.companyLogo, size: 32, radius: 9),
                    const SizedBox(width: 10),
                    Expanded(child: Text(t.companyName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                  ] else ...[
                    Icon(Icons.event_rounded, size: 18, color: brand.color),
                    const SizedBox(width: 6),
                    Expanded(child: Text(travelDay(t.departureAt), style: const TextStyle(fontWeight: FontWeight.w800))),
                  ],
                  if ((t.busClass ?? '').isNotEmpty) InfoTag(t.busClass!, color: AppColors.info),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _TripTimeline(trip: t, color: brand.color),
                  const SizedBox(height: 12),
                  Row(children: [
                    if (showCompany) ...[
                      const Icon(Icons.event_rounded, size: 15, color: travelMuted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(travelDay(t.departureAt),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: travelMuted, fontWeight: FontWeight.w600)),
                      ),
                    ] else
                      const Spacer(),
                    if (t.cancelled)
                      const InfoTag('Annulé', color: AppColors.danger)
                    else
                      InfoTag(t.full ? 'Complet' : '${t.seatsAvailable} place${t.seatsAvailable > 1 ? 's' : ''}', color: seatsColor, icon: Icons.event_seat_rounded),
                    const SizedBox(width: 10),
                    Text(fcfa(t.price), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: brand.color)),
                    ?trailing,
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Une ligne (ville → ville) d'une compagnie avec tous ses départs.
class TravelRoute {
  TravelRoute(this.from, this.to, this.trips);
  final String from;
  final String to;
  final List<TravelTrip> trips;

  int get minPrice => trips.map((t) => t.price).reduce((a, b) => a < b ? a : b);
  int get maxPrice => trips.map((t) => t.price).reduce((a, b) => a > b ? a : b);
  int? get duration => trips.map((t) => t.durationMinutes).whereType<int>().firstOrNull;
  TravelTrip? get next => trips.where((t) => t.bookable).firstOrNull;
}

/// Regroupe des départs par ligne ; les lignes sont classées par leur prochain départ.
List<TravelRoute> groupRoutes(Iterable<TravelTrip> trips) {
  final map = <String, List<TravelTrip>>{};
  for (final t in trips) {
    (map['${t.fromCity}→${t.toCity}'] ??= []).add(t);
  }
  final routes = [
    for (final e in map.entries)
      TravelRoute(e.value.first.fromCity, e.value.first.toCity, [...e.value]..sort((a, b) => a.departureAt.compareTo(b.departureAt))),
  ];
  routes.sort((a, b) => a.trips.first.departureAt.compareTo(b.trips.first.departureAt));
  return routes;
}

/// Carte d'une ligne : prix, durée, prochains horaires ; une fois ouverte, choix du jour puis de l'heure.
class RouteScheduleCard extends StatefulWidget {
  const RouteScheduleCard({super.key, required this.route, required this.color, required this.onBook, this.initiallyOpen = false});
  final TravelRoute route;
  final Color color;
  final bool initiallyOpen;
  final void Function(TravelTrip trip) onBook;

  @override
  State<RouteScheduleCard> createState() => _RouteScheduleCardState();
}

class _RouteScheduleCardState extends State<RouteScheduleCard> {
  late bool _open = widget.initiallyOpen;
  int _day = 0;

  List<DateTime> get _days {
    final out = <DateTime>[];
    for (final t in widget.route.trips) {
      final d = t.departureAt.toLocal();
      final day = DateTime(d.year, d.month, d.day);
      if (!out.contains(day)) out.add(day);
    }
    return out;
  }

  List<TravelTrip> _tripsOf(DateTime day) => [
        for (final t in widget.route.trips)
          if (DateUtils.isSameDay(t.departureAt.toLocal(), day)) t
      ];

  @override
  Widget build(BuildContext context) {
    final r = widget.route;
    final days = _days;
    final day = days[_day.clamp(0, days.length - 1)];
    final dayTrips = _tripsOf(days.first);
    final preview = dayTrips.take(4).map((t) => formatTime(t.departureAt)).join('  ·  ');
    final price = r.minPrice == r.maxPrice ? shortFcfa(r.minPrice) : 'dès ${shortFcfa(r.minPrice)}';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _open ? widget.color.withValues(alpha: 0.5) : AppColors.line, width: _open ? 1.5 : 1),
        boxShadow: [BoxShadow(color: widget.color.withValues(alpha: _open ? 0.12 : 0.05), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(Icons.alt_route_rounded, color: widget.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: r.from),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Icon(Icons.arrow_forward_rounded, size: 16, color: widget.color)),
                      ),
                      TextSpan(text: r.to),
                    ]),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [if (r.duration != null) travelDuration(r.duration!), if (!_open && preview.isNotEmpty) preview].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: travelMuted, fontSize: 13),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Text(price, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: widget.color)),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                child: const Icon(Icons.keyboard_arrow_down_rounded, color: travelMuted),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final (i, d) in days.indexed)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: TravelChip(
                              label: dayChipLabel(d),
                              selected: d == day,
                              color: widget.color,
                              onTap: () => setState(() => _day = i),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Wrap(
                        key: ValueKey(day),
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (i, t) in _tripsOf(day).indexed)
                            FadeSlideIn(
                              key: ValueKey('${t.id}-${day.day}'),
                              delay: Duration(milliseconds: 40 * (i > 10 ? 10 : i)),
                              offset: 10,
                              child: _TimeChip(trip: t, color: widget.color, onTap: t.bookable ? () => widget.onBook(t) : null),
                            ),
                        ],
                      ),
                    ),
                  ]),
                ),
        ),
      ]),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.trip, required this.color, required this.onTap});
  final TravelTrip trip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final enabled = onTap != null;
    final sub = t.full ? 'Complet' : [shortFcfa(t.price), if ((t.busClass ?? '').isNotEmpty) t.busClass!].join(' · ');
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.white, color.withValues(alpha: 0.12)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(formatTime(t.departureAt), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color.lerp(color, Colors.black, 0.25))),
            const SizedBox(height: 1),
            Text(sub, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: travelMuted)),
          ]),
        ),
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
        const Text('Au guichet : votre nom, votre signature et la ville suffisent', textAlign: TextAlign.center, style: TextStyle(color: travelMuted)),
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
          SizedBox(width: 104, child: Text(label, style: const TextStyle(color: travelMuted))),
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
              style: TextStyle(color: travelMuted, fontSize: 13, height: 1.3)),
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
