import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../data/models/delivery.dart';
import '../../data/models/travel.dart';
import '../../providers/auth_providers.dart';
import '../../providers/data_providers.dart';
import '../../providers/travel_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/point_form.dart';
import '../restaurant/restaurant_widgets.dart' show InfoTag, PhotoBox;
import 'travel_widgets.dart';

// ---------------------------------------------------------------------------
// Recherche d'un voyage
// ---------------------------------------------------------------------------

/// Rechercher un départ : ville de départ, d'arrivée, jour.
class TravelSearchScreen extends ConsumerStatefulWidget {
  const TravelSearchScreen({super.key});

  @override
  ConsumerState<TravelSearchScreen> createState() => _TravelSearchScreenState();
}

class _TravelSearchScreenState extends ConsumerState<TravelSearchScreen> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  DateTime? _date;
  TripQuery _query = (from: '', to: '', date: null);

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _search() => setState(() => _query = (from: _from.text.trim(), to: _to.text.trim(), date: _date));

  void _swap() {
    final f = _from.text;
    _from.text = _to.text;
    _to.text = f;
    _search();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
    );
    if (d != null) {
      _date = d;
      _search();
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(tripSearchProvider(_query));
    final cities = ref.watch(travelCitiesProvider).value ?? const <String>[];
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    bool sameDay(DateTime? a, DateTime b) => a != null && a.year == b.year && a.month == b.month && a.day == b.day;

    Widget cityField(TextEditingController c, String label, IconData icon) =>
        _CityField(controller: c, label: label, icon: icon, cities: cities, onDone: _search);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voyages'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/client/voyages/bookings'),
            icon: const Icon(Icons.confirmation_number_rounded),
            label: const Text('Mes tickets'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(tripSearchProvider(_query)),
        child: Constrained(
          maxWidth: 760,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Column(children: [
                      cityField(_from, 'Départ', Icons.trip_origin_rounded),
                      const SizedBox(height: 10),
                      cityField(_to, 'Arrivée', Icons.place_rounded),
                    ]),
                  ),
                  IconButton(tooltip: 'Inverser', onPressed: _swap, icon: const Icon(Icons.swap_vert_rounded)),
                ]),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    ChoiceChip(label: const Text('Toutes les dates'), selected: _date == null, onSelected: (_) { _date = null; _search(); }),
                    const SizedBox(width: 8),
                    ChoiceChip(label: const Text('Aujourd’hui'), selected: sameDay(_date, today), onSelected: (_) { _date = today; _search(); }),
                    const SizedBox(width: 8),
                    ChoiceChip(label: const Text('Demain'), selected: sameDay(_date, tomorrow), onSelected: (_) { _date = tomorrow; _search(); }),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: Text(_date != null && !sameDay(_date, today) && !sameDay(_date, tomorrow) ? formatDate(_date) : 'Autre date'),
                      onPressed: _pickDate,
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(onPressed: _search, icon: const Icon(Icons.search_rounded), label: const Text('Rechercher')),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            results.when(
              loading: () => const Padding(padding: EdgeInsets.all(30), child: LoadingView()),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(tripSearchProvider(_query))),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.only(top: 30),
                      child: EmptyState(
                        icon: Icons.directions_bus_rounded,
                        message: 'Aucun départ trouvé. Essayez une autre date ou une autre ville.',
                      ),
                    )
                  : Column(children: [
                      for (final t in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TripCard(trip: t, onTap: t.bookable ? () => context.push('/voyage/${t.id}') : null),
                        ),
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Champ de ville avec suggestions (villes des départs programmés).
class _CityField extends StatefulWidget {
  const _CityField({required this.controller, required this.label, required this.icon, required this.cities, required this.onDone});
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final List<String> cities;
  final VoidCallback onDone;

  @override
  State<_CityField> createState() => _CityFieldState();
}

class _CityFieldState extends State<_CityField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
        textEditingController: widget.controller,
        focusNode: _focus,
        optionsBuilder: (v) {
          final q = v.text.trim().toLowerCase();
          return q.isEmpty ? widget.cities : widget.cities.where((x) => x.toLowerCase().contains(q));
        },
        onSelected: (_) => widget.onDone(),
        fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
          controller: ctrl,
          focusNode: focus,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => widget.onDone(),
          decoration: InputDecoration(labelText: widget.label, prefixIcon: Icon(widget.icon)),
        ),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [for (final o in options) ListTile(dense: true, title: Text(o), onTap: () => onSelected(o))],
              ),
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Page publique d'une compagnie (lien partagé /v/<slug>)
// ---------------------------------------------------------------------------

class CompanyPublicScreen extends ConsumerWidget {
  const CompanyPublicScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(companyBySlugProvider(slug));
    final c = async.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(c?.name ?? 'Compagnie'),
        actions: [
          if (c != null) ...[
            IconButton(tooltip: 'QR code', icon: const Icon(Icons.qr_code_2_rounded), onPressed: () => showCompanyQr(context, c)),
            IconButton(tooltip: 'Partager', icon: const Icon(Icons.share_rounded), onPressed: () => shareCompanyLink(context, c)),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(companyBySlugProvider(slug)),
        child: AsyncBody<TransportCompany?>(
          value: async,
          onRetry: () => ref.invalidate(companyBySlugProvider(slug)),
          builder: (c) {
            if (c == null) {
              return ListView(children: const [
                SizedBox(height: 80),
                EmptyState(icon: Icons.directions_bus_outlined, message: 'Ce lien n’est plus valable.'),
              ]);
            }
            return Constrained(
              maxWidth: 760,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  PhotoBox(url: c.logoUrl, size: 64, radius: 16, icon: Icons.directions_bus_rounded),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      if (c.subtitle.isNotEmpty) Text(c.subtitle, style: const TextStyle(color: AppColors.textMuted)),
                    ]),
                  ),
                ]),
                if ((c.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(c.description!, style: const TextStyle(height: 1.4)),
                ],
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  InfoTag(c.acceptingBookings ? 'Réservations ouvertes' : 'Réservations fermées',
                      color: c.acceptingBookings ? AppColors.primary : AppColors.danger),
                  const InfoTag('E-ticket', icon: Icons.qr_code_rounded),
                  if (c.deliversTickets) const InfoTag('Ticket livré', color: AppColors.info, icon: Icons.delivery_dining_rounded),
                ]),
                if ((c.phone ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => callPhone(c.phone!),
                      icon: const Icon(Icons.call_rounded),
                      label: Text(displayPhone(c.phone)),
                    ),
                  ),
                ],
                const SectionTitle('Prochains départs'),
                if (c.trips.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('Aucun départ programmé pour le moment.', style: TextStyle(color: AppColors.textMuted)),
                  ),
                for (final t in c.trips)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TripCard(
                      trip: t,
                      showCompany: false,
                      onTap: t.bookable ? () => context.push('/voyage/${t.id}') : null,
                    ),
                  ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Réservation (compte requis)
// ---------------------------------------------------------------------------

class TravelBookScreen extends ConsumerStatefulWidget {
  const TravelBookScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<TravelBookScreen> createState() => _TravelBookScreenState();
}

class _TravelBookScreenState extends ConsumerState<TravelBookScreen> {
  final _note = TextEditingController();
  final List<TextEditingController> _names = [TextEditingController()];
  int _passengers = 1;
  String _mode = 'eticket';
  DeliveryPoint? _drop;
  int? _fee;
  double? _km;
  Object? _feeError;
  bool _feeLoading = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final u = ref.read(currentUserProvider);
    _names.first.text = u?.fullName ?? '';
    _drop = DeliveryPoint(address: '', lat: 0, lng: 0, contactName: u?.fullName ?? '', contactPhone: displayPhone(u?.phone));
  }

  @override
  void dispose() {
    _note.dispose();
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  void _setPassengers(int n) {
    setState(() {
      _passengers = n;
      while (_names.length < n) {
        _names.add(TextEditingController());
      }
      while (_names.length > n) {
        _names.removeLast().dispose();
      }
    });
  }

  bool get _dropValid => _drop != null && _drop!.address.trim().isNotEmpty && _drop!.lat != 0 && _drop!.lng != 0;

  Future<void> _computeFee(TravelTrip t) async {
    if (!_dropValid) return;
    setState(() {
      _feeLoading = true;
      _feeError = null;
      _fee = null;
    });
    try {
      final res = await ref.read(travelRepositoryProvider).ticketDeliveryFee(t.id, _drop!.lat, _drop!.lng);
      if (mounted) {
        setState(() {
          _fee = res.fee;
          _km = res.km;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _feeError = e);
    } finally {
      if (mounted) setState(() => _feeLoading = false);
    }
  }

  Future<void> _submit(TravelTrip t) async {
    if (_mode == 'delivery' && (!_dropValid || _fee == null)) {
      showError(context, _feeError ?? Exception('Indiquez l’adresse où livrer le ticket'));
      return;
    }
    setState(() => _submitting = true);
    try {
      final b = await ref.read(travelRepositoryProvider).book(
            tripId: t.id,
            passengers: _passengers,
            passengerNames: [for (final c in _names) c.text],
            ticketMode: _mode,
            note: _note.text,
            dropoff: _mode == 'delivery'
                ? {'address': _drop!.address, 'lat': _drop!.lat, 'lng': _drop!.lng, 'note': _drop!.instructions}
                : null,
          );
      ref.invalidate(myTravelBookingsProvider);
      if (mounted) {
        showSuccess(context, 'Réservation envoyée à ${t.companyName ?? 'la compagnie'}');
        context.go('/client/voyages/bookings/${b.id}');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(travelTripProvider(widget.tripId));
    final t = async.value;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Réserver')),
        body: async.isLoading
            ? const LoadingView()
            : async.hasError
                ? ErrorView(error: async.error!, onRetry: () => ref.invalidate(travelTripProvider(widget.tripId)))
                : const EmptyState(icon: Icons.directions_bus_outlined, message: 'Ce départ n’est plus disponible.'),
      );
    }
    if (_mode == 'delivery' && !t.canDeliverTicket) _mode = 'eticket';
    final maxSeats = t.seatsAvailable.clamp(0, 10);
    final tickets = t.price * _passengers;
    final fee = _mode == 'delivery' ? (_fee ?? 0) : 0;
    final total = tickets + fee;
    final addresses = ref.watch(savedAddressesProvider(null)).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: Text('Réserver · ${t.route}')),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _TotalLine('$_passengers billet${_passengers > 1 ? 's' : ''} × ${fcfa(t.price)}', fcfa(tickets)),
            if (_mode == 'delivery')
              _TotalLine('Livraison du ticket${_km == null ? '' : ' (${km(_km)})'}',
                  _feeLoading ? '…' : (_fee == null ? 'à calculer' : fcfa(_fee))),
            const Divider(height: 14),
            _TotalLine('TOTAL', fcfa(total), bold: true),
            Text(_mode == 'delivery' ? 'Payé en espèces au livreur, à la remise du ticket' : 'Payé au guichet de la gare, avant le départ',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 8),
            BigActionButton(
              label: 'ENVOYER LA RÉSERVATION',
              icon: Icons.check_rounded,
              loading: _submitting,
              onPressed: t.bookable && maxSeats > 0 ? () => _submit(t) : null,
            ),
          ]),
        ),
      ),
      body: Constrained(
        maxWidth: 720,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TripCard(trip: t),
          if ((t.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(t.notes!, style: const TextStyle(color: AppColors.textMuted)),
          ],
          if (!t.bookable)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Text(t.full ? 'Ce départ est complet.' : 'Ce départ ne peut plus être réservé.',
                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
            ),
          const SectionTitle('Voyageurs'),
          Row(children: [
            const Expanded(child: Text('Nombre de places', style: TextStyle(fontWeight: FontWeight.w700))),
            IconButton.filledTonal(
              onPressed: _passengers > 1 ? () => _setPassengers(_passengers - 1) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(width: 36, child: Text('$_passengers', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            IconButton.filled(
              onPressed: _passengers < maxSeats ? () => _setPassengers(_passengers + 1) : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ]),
          const SizedBox(height: 6),
          for (final (i, c) in _names.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: c,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: 'Nom du voyageur ${i + 1} (facultatif)'),
              ),
            ),
          const SectionTitle('Votre ticket'),
          Row(children: [
            Expanded(
              child: _ModeCard(
                icon: Icons.qr_code_2_rounded,
                title: 'E-ticket',
                caption: 'QR code · payé à la gare',
                selected: _mode == 'eticket',
                onTap: () => setState(() => _mode = 'eticket'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ModeCard(
                icon: Icons.delivery_dining_rounded,
                title: 'Livré chez moi',
                caption: !t.deliversTickets
                    ? 'Non proposé'
                    : t.canDeliverTicket
                        ? 'Payé au livreur'
                        : 'Départ trop proche',
                selected: _mode == 'delivery',
                onTap: t.canDeliverTicket
                    ? () {
                        setState(() => _mode = 'delivery');
                        _computeFee(t);
                      }
                    : null,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            _mode == 'eticket'
                ? 'Après confirmation par la compagnie, votre e-ticket (QR code) s’affiche ici. Présentez-le au guichet et payez avant le départ.'
                : 'Après confirmation, un livreur Telima récupère votre ticket papier à la gare et vous l’apporte. Vous gardez aussi l’e-ticket.',
            style: const TextStyle(color: AppColors.textMuted, height: 1.35),
          ),
          if (_mode == 'delivery') ...[
            const SectionTitle('Où livrer le ticket ?'),
            DeliveryPointForm(
              point: _drop,
              isPickup: false,
              savedAddresses: addresses,
              showContact: false,
              addressLabel: 'Quartier, repère',
              contactRequired: false,
              mapTitle: 'Adresse de livraison du ticket',
              onChanged: (p) {
                final moved = _drop == null || p.lat != _drop!.lat || p.lng != _drop!.lng;
                setState(() => _drop = p);
                if (moved) _computeFee(t);
              },
            ),
            if (_feeError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(friendlyError(_feeError!), style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ),
          ],
          const SectionTitle('Un message pour la compagnie ? (facultatif)'),
          TextField(
            controller: _note,
            maxLines: 2,
            maxLength: 300,
            decoration: const InputDecoration(hintText: 'Ex. bagage volumineux, place près de la fenêtre…'),
          ),
        ]),
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: bold ? 18 : 14, color: bold ? AppColors.primaryDark : null)),
        ]),
      );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.icon, required this.title, required this.caption, required this.selected, required this.onTap});
  final IconData icon;
  final String title;
  final String caption;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? AppColors.mint : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? AppColors.primary : AppColors.line, width: selected ? 2 : 1),
            ),
            child: Column(children: [
              Icon(icon, size: 30, color: AppColors.primaryDark),
              const SizedBox(height: 6),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(caption, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ]),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Mes réservations
// ---------------------------------------------------------------------------

class MyTravelBookingsScreen extends ConsumerWidget {
  const MyTravelBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myTravelBookingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mes tickets de voyage')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myTravelBookingsProvider),
        child: AsyncBody<List<TravelBooking>>(
          value: async,
          onRetry: () => ref.invalidate(myTravelBookingsProvider),
          builder: (list) => list.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 80),
                  const EmptyState(icon: Icons.confirmation_number_outlined, message: 'Aucune réservation pour le moment.'),
                  Center(
                    child: TextButton(onPressed: () => context.go('/client/voyages'), child: const Text('Rechercher un voyage')),
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final b = list[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => context.push('/client/voyages/bookings/${b.id}'),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(b.trip?.route ?? b.code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                            BookingStatusTag(b),
                          ]),
                          const SizedBox(height: 4),
                          Text('${b.companyName ?? ''} · ${formatDateTime(b.trip?.departureAt)}', style: const TextStyle(color: AppColors.textMuted)),
                          const SizedBox(height: 2),
                          Text('${b.code} · ${b.passengers} place${b.passengers > 1 ? 's' : ''} · ${fcfa(b.total)}',
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// Détail d'une réservation : étapes, e-ticket, suivi du livreur (se met à jour toutes les 15 secondes).
class TravelBookingDetailScreen extends ConsumerStatefulWidget {
  const TravelBookingDetailScreen({super.key, required this.bookingId});
  final String bookingId;

  @override
  ConsumerState<TravelBookingDetailScreen> createState() => _TravelBookingDetailScreenState();
}

class _TravelBookingDetailScreenState extends ConsumerState<TravelBookingDetailScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) ref.invalidate(travelBookingProvider(widget.bookingId));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.bookingId;
    final async = ref.watch(travelBookingProvider(id));
    final me = ref.watch(currentUserProvider)?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Ma réservation')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(travelBookingProvider(id)),
        child: AsyncBody<TravelBooking>(
          value: async,
          onRetry: () => ref.invalidate(travelBookingProvider(id)),
          builder: (b) {
            final idx = b.steps.indexWhere((s) => s.$1 == b.status);
            final isCustomer = b.customerId == null || b.customerId == me;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Constrained(
                maxWidth: 720,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(b.trip?.route ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text('${b.companyName ?? ''} · ${formatDateTime(b.trip?.departureAt)}', style: const TextStyle(color: AppColors.textMuted)),
                  Text('${b.code} · réservée ${relativeTime(b.createdAt)}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(height: 14),
                  if (b.failed)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
                      child: Text('${b.statusLabel}${b.rejectReason == null ? '' : ' : ${b.rejectReason}'}',
                          style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                    )
                  else
                    for (final (i, s) in b.steps.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          Icon(i <= idx ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                              color: i <= idx ? AppColors.primary : AppColors.line, size: 26),
                          const SizedBox(width: 12),
                          Text(s.$2, style: TextStyle(fontWeight: i == idx ? FontWeight.w800 : FontWeight.w500, color: i > idx ? AppColors.textMuted : null)),
                        ]),
                      ),
                  if (b.status == 'pending')
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
                      child: const Text('Vos places sont bloquées. La compagnie va confirmer votre réservation : vous recevrez une notification.',
                          style: TextStyle(height: 1.35)),
                    ),
                  if ((b.companyMessage ?? '').isNotEmpty) ...[
                    const SectionTitle('Message de la compagnie'),
                    Text(b.companyMessage!),
                  ],
                  if (b.hasETicket) ...[
                    const SizedBox(height: 16),
                    ETicketCard(booking: b),
                  ],
                  const SectionTitle('Détail'),
                  Row(children: [
                    Expanded(child: Text('${b.passengers} billet${b.passengers > 1 ? 's' : ''} × ${fcfa(b.unitPrice)}')),
                    Text(fcfa(b.ticketsTotal)),
                  ]),
                  if (b.isDelivery) Row(children: [const Expanded(child: Text('Livraison du ticket')), Text(fcfa(b.deliveryFee))]),
                  const Divider(),
                  Row(children: [
                    const Expanded(child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w800))),
                    Text(fcfa(b.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.primaryDark)),
                  ]),
                  Text(b.paymentHint, style: const TextStyle(color: AppColors.textMuted)),
                  if (b.isDelivery && b.dropoffAddress != null) ...[
                    const SectionTitle('Ticket livré à'),
                    Text(b.dropoffAddress!),
                  ],
                  const SizedBox(height: 16),
                  if (b.deliveryId != null && b.isOpen && isCustomer)
                    BigActionButton(
                      label: 'SUIVRE MON LIVREUR',
                      icon: Icons.delivery_dining_rounded,
                      onPressed: () => context.push('/client/delivery/${b.deliveryId}'),
                    ),
                  if (b.trip?.stationPosition != null && b.isOpen) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () => openNavigation(b.trip!.stationPosition!),
                      icon: const Icon(Icons.directions_rounded),
                      label: const Text('ITINÉRAIRE VERS LA GARE'),
                    ),
                  ],
                  if ((b.companyPhone ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () => callPhone(b.companyPhone!),
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('APPELER LA COMPAGNIE'),
                    ),
                  ],
                  if (b.customerCanCancel && isCustomer) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () async {
                        final ok = await confirmDialog(context,
                            title: 'Annuler la réservation ?', message: 'Vos places seront libérées.', confirmLabel: 'Annuler la réservation', danger: true);
                        if (!ok || !context.mounted) return;
                        await runWithLoader(context, () => ref.read(travelRepositoryProvider).cancelBooking(b.id), success: 'Réservation annulée');
                        ref.invalidate(travelBookingProvider(id));
                        ref.invalidate(myTravelBookingsProvider);
                      },
                      child: const Text('Annuler la réservation', style: TextStyle(color: AppColors.danger)),
                    ),
                  ],
                  if (b.companySlug != null)
                    TextButton(onPressed: () => context.push('/v/${b.companySlug}'), child: const Text('Voir les autres départs de la compagnie')),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
