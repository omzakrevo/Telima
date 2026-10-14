import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../core/utils/validators.dart';
import '../../data/models/delivery.dart';
import '../../data/models/travel.dart';
import '../../providers/auth_providers.dart';
import '../../providers/travel_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/point_form.dart';
import '../restaurant/restaurant_widgets.dart' show InfoTag, PhotoBox;
import 'travel_widgets.dart';

String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

// ---------------------------------------------------------------------------
// Mes compagnies
// ---------------------------------------------------------------------------

class CompanyOwnerHomeScreen extends ConsumerWidget {
  const CompanyOwnerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myCompaniesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ma compagnie de transport')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/transport/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Inscrire ma compagnie'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myCompaniesProvider),
        child: AsyncBody<List<TransportCompany>>(
          value: async,
          onRetry: () => ref.invalidate(myCompaniesProvider),
          builder: (list) => list.isEmpty
              ? ListView(padding: const EdgeInsets.all(24), children: const [
                  SizedBox(height: 40),
                  Icon(Icons.directions_bus_rounded, size: 64, color: AppColors.primary),
                  SizedBox(height: 12),
                  Text('Vendez vos tickets avec Telima',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  Text(
                    'Inscrivez votre compagnie, publiez vos départs (trajet, heure, prix, places) et partagez votre lien. '
                    'Les voyageurs réservent, vous confirmez, ils reçoivent un e-ticket. Un livreur Telima peut aussi leur apporter le ticket papier.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, height: 1.4),
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => CompanyTile(company: list[i], onTap: () => context.push('/transport/${list[i].id}')),
                ),
        ),
      ),
    );
  }
}

class CompanyTile extends StatelessWidget {
  const CompanyTile({super.key, required this.company, this.onTap, this.trailing});
  final TransportCompany company;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = company;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
        child: Row(children: [
          PhotoBox(url: c.logoUrl, size: 52, radius: 14, icon: Icons.directions_bus_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(c.subtitle.isEmpty ? 'Compagnie de transport' : c.subtitle, style: const TextStyle(color: AppColors.textMuted)),
            ]),
          ),
          if (c.pendingApproval)
            const InfoTag('À valider', color: AppColors.accent)
          else if (c.suspended)
            const InfoTag('Suspendue', color: AppColors.danger)
          else
            InfoTag(c.acceptingBookings ? 'Ouverte' : 'Fermée', color: c.acceptingBookings ? AppColors.primary : AppColors.textMuted),
          trailing ?? const Icon(Icons.chevron_right_rounded),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inscrire / modifier une compagnie
// ---------------------------------------------------------------------------

/// [companyId] renseigné : modification. [asAdmin] : compagnie saisie par l'équipe Telima (sans propriétaire).
class CompanyFormScreen extends ConsumerStatefulWidget {
  const CompanyFormScreen({super.key, this.companyId, this.asAdmin = false});
  final String? companyId;
  final bool asAdmin;

  @override
  ConsumerState<CompanyFormScreen> createState() => _CompanyFormScreenState();
}

class _CompanyFormScreenState extends ConsumerState<CompanyFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _radius = TextEditingController(text: '20');
  bool _delivers = true;
  String? _logoPath;
  DeliveryPoint? _point = DeliveryPoint(address: '', lat: 0, lng: 0);
  bool _loading = false;
  bool _saving = false;
  bool _uploading = false;

  bool get _editing => widget.companyId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      _loading = true;
      _load();
    } else if (!widget.asAdmin) {
      _phone.text = displayPhone(ref.read(currentUserProvider)?.phone);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _phone, _city, _radius]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await ref.read(travelRepositoryProvider).company(widget.companyId!);
      if (c == null) throw Exception('Compagnie introuvable');
      _name.text = c.name;
      _description.text = c.description ?? '';
      _phone.text = displayPhone(c.phone);
      _city.text = c.city ?? '';
      _radius.text = c.deliveryRadiusKm.toString().replaceAll(RegExp(r'\.0$'), '');
      _delivers = c.deliversTickets;
      _logoPath = c.logoPath;
      _point = DeliveryPoint(address: c.stationAddress ?? '', lat: c.position.latitude, lng: c.position.longitude);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        context.pop();
      }
      return;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickLogo() async {
    setState(() => _uploading = true);
    try {
      final path = await ref.read(travelRepositoryProvider).pickAndUploadLogo();
      if (path != null && mounted) setState(() => _logoPath = path);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_point == null || _point!.lat == 0 || _point!.lng == 0) {
      showError(context, Exception('Placez la gare sur la carte (« Ma position » ou « Sur la carte »)'));
      return;
    }
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'description': _nullIfEmpty(_description.text),
      'phone': _phone.text.trim().isEmpty ? null : normalizePhone(_phone.text),
      'city': _nullIfEmpty(_city.text),
      'station_address': _nullIfEmpty(_point!.address),
      'lat': _point!.lat,
      'lng': _point!.lng,
      'logo_path': _logoPath,
      'delivers_tickets': _delivers,
      'ticket_delivery_radius_km': double.tryParse(_radius.text.replaceAll(',', '.')) ?? 20,
    };
    setState(() => _saving = true);
    try {
      final repo = ref.read(travelRepositoryProvider);
      if (_editing) {
        await repo.updateCompany(widget.companyId!, data);
        ref.invalidate(companyProvider(widget.companyId!));
        ref.invalidate(myCompaniesProvider);
        ref.invalidate(adminCompaniesProvider);
        if (mounted) {
          showSuccess(context, 'Informations enregistrées');
          context.pop();
        }
      } else {
        final c = await repo.createCompany(data, asAdmin: widget.asAdmin);
        ref.invalidate(myCompaniesProvider);
        ref.invalidate(adminCompaniesProvider);
        if (mounted) {
          showSuccess(context, widget.asAdmin
              ? 'Compagnie enregistrée ! Ajoutez ses départs puis partagez son lien.'
              : 'Compagnie enregistrée ! Elle sera visible dès sa validation par l’équipe Telima ; préparez vos départs en attendant.');
          context.pushReplacement('/transport/${c.id}');
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Modifier la compagnie' : (widget.asAdmin ? 'Saisir une compagnie' : 'Inscrire ma compagnie'))),
      body: _loading
          ? const LoadingView()
          : Form(
              key: _form,
              child: Constrained(
                maxWidth: 720,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  if (widget.asAdmin && !_editing)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.sky, borderRadius: BorderRadius.circular(14)),
                      child: const Text(
                          'Compagnie gérée par l’équipe Telima : vous publiez ses départs et confirmez les réservations à sa place '
                          '(après accord par téléphone). Vous pourrez la confier plus tard au compte de la compagnie.',
                          style: TextStyle(height: 1.3)),
                    ),
                  Row(children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _uploading ? null : _pickLogo,
                      child: PhotoBox(url: travelPhotoUrl(_logoPath), size: 76, radius: 16, icon: Icons.add_a_photo_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Nom de la compagnie'),
                        validator: (v) => (v ?? '').trim().length < 2 ? 'Indiquez le nom' : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: 'Présentation (facultatif)', hintText: 'Ex. Lignes Ouaga – Bobo – Banfora, cars climatisés'),
                  ),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Téléphone du guichet'),
                    validator: (v) => (v ?? '').trim().isEmpty ? null : Validators.phone(v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(controller: _city, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Ville de la gare principale')),
                  const SectionTitle('Livraison des tickets'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Proposer la livraison du ticket'),
                    subtitle: const Text('Un livreur Telima récupère le ticket papier au guichet et l’apporte au voyageur'),
                    value: _delivers,
                    onChanged: (v) => setState(() => _delivers = v),
                  ),
                  if (_delivers)
                    TextFormField(
                      controller: _radius,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Distance maximale de livraison depuis la gare (km)'),
                      validator: (v) => Validators.number(v, min: 1),
                    ),
                  const SectionTitle('Où se trouve la gare ?'),
                  DeliveryPointForm(
                    point: _point,
                    isPickup: true,
                    showContact: false,
                    contactRequired: false,
                    mapTitle: 'Position de la gare',
                    addressLabel: 'Adresse ou repère de la gare',
                    onChanged: (p) => setState(() => _point = p),
                  ),
                  const SizedBox(height: 20),
                  BigActionButton(
                    label: _editing ? 'ENREGISTRER' : 'ENREGISTRER LA COMPAGNIE',
                    icon: Icons.check_rounded,
                    loading: _saving,
                    onPressed: _uploading ? null : _save,
                  ),
                ]),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gestion d'une compagnie
// ---------------------------------------------------------------------------

class CompanyManageScreen extends ConsumerWidget {
  const CompanyManageScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(companyProvider(companyId));
    final c = async.value;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(c?.name ?? 'Ma compagnie'),
          actions: [
            if (c != null)
              IconButton(tooltip: 'Modifier', icon: const Icon(Icons.edit_rounded), onPressed: () => context.push('/transport/${c.id}/edit')),
          ],
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Réservations'),
            Tab(text: 'Départs'),
            Tab(text: 'Contrôle'),
            Tab(text: 'Mon lien'),
          ]),
        ),
        body: AsyncBody<TransportCompany?>(
          value: async,
          onRetry: () => ref.invalidate(companyProvider(companyId)),
          builder: (company) {
            if (company == null) return const EmptyState(icon: Icons.directions_bus_outlined, message: 'Compagnie introuvable.');
            return Constrained(
              maxWidth: 760,
              child: Column(children: [
                if (company.pendingApproval)
                  Container(
                    width: double.infinity,
                    color: AppColors.accent.withValues(alpha: 0.12),
                    padding: const EdgeInsets.all(12),
                    child: const Text('Inscription en attente de validation par l’équipe Telima : votre lien et vos départs seront visibles dès qu’elle sera validée.',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                if (company.suspended)
                  Container(
                    width: double.infinity,
                    color: AppColors.danger.withValues(alpha: 0.1),
                    padding: const EdgeInsets.all(12),
                    child: const Text('Compagnie suspendue par l’équipe Telima : son lien et ses départs ne sont plus visibles.',
                        style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                  ),
                if (company.managedByTelima)
                  Container(
                    width: double.infinity,
                    color: AppColors.sky,
                    padding: const EdgeInsets.all(10),
                    child: const Text('Compagnie gérée par l’équipe Telima.', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                SwitchListTile(
                  secondary: Icon(company.acceptingBookings ? Icons.lock_open_rounded : Icons.lock_rounded,
                      color: company.acceptingBookings ? AppColors.primary : AppColors.textMuted),
                  title: Text(company.acceptingBookings ? 'Réservations ouvertes' : 'Réservations fermées'),
                  subtitle: const Text('Les voyageurs voient toujours vos départs.'),
                  value: company.acceptingBookings,
                  onChanged: (v) async {
                    await runWithLoader(context, () => ref.read(travelRepositoryProvider).setAcceptingBookings(company.id, v));
                    ref.invalidate(companyProvider(companyId));
                  },
                ),
                const Divider(height: 1),
                Expanded(
                  child: TabBarView(children: [
                    _BookingsTab(companyId: companyId),
                    _TripsTab(company: company),
                    _ControlTab(companyId: companyId),
                    ListView(padding: const EdgeInsets.all(16), children: [CompanyLinkCard(company: company)]),
                  ]),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

// ----- Réservations -----

class _BookingsTab extends ConsumerStatefulWidget {
  const _BookingsTab({required this.companyId});
  final String companyId;

  @override
  ConsumerState<_BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends ConsumerState<_BookingsTab> with AutomaticKeepAliveClientMixin {
  Timer? _timer;
  String _filter = 'pending';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Les nouvelles réservations apparaissent sans action de la compagnie.
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(companyBookingsProvider(widget.companyId));
    ref.invalidate(companyDashboardProvider(widget.companyId));
    ref.invalidate(companyTripsProvider(widget.companyId));
  }

  Future<void> _confirm(TravelBooking b) async {
    final data = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _ConfirmDialog(booking: b));
    if (data == null || !mounted) return;
    await runWithLoader(context, () => ref.read(travelRepositoryProvider).bookingAction(b.id, 'confirm', data),
        success: b.isDelivery ? 'Confirmée : un livreur va chercher le ticket au guichet' : 'Confirmée : le voyageur a son e-ticket');
    _refresh();
  }

  Future<void> _reject(TravelBooking b) async {
    final reason = await promptDialog(context, title: 'Refuser la réservation ${b.code} ?', label: 'Motif (ex. car complet)', required: false);
    if (reason == null || !mounted) return;
    await runWithLoader(context, () => ref.read(travelRepositoryProvider).bookingAction(b.id, 'reject', {'reason': reason}),
        success: 'Réservation refusée, places libérées');
    _refresh();
  }

  Future<void> _act(TravelBooking b, String action, String success) async {
    await runWithLoader(context, () => ref.read(travelRepositoryProvider).bookingAction(b.id, action), success: success);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final async = ref.watch(companyBookingsProvider(widget.companyId));
    final dash = ref.watch(companyDashboardProvider(widget.companyId)).value;
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: AsyncBody<List<TravelBooking>>(
        value: async,
        onRetry: _refresh,
        builder: (all) {
          final list = switch (_filter) {
            'pending' => all.where((b) => b.status == 'pending').toList(),
            'confirmed' => all.where((b) => const {'confirmed', 'out_for_delivery', 'delivered'}.contains(b.status)).toList(),
            _ => all,
          };
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (dash != null)
              Row(children: [
                Expanded(child: _Stat('À confirmer', '${dash['pending'] ?? 0}', AppColors.accent)),
                const SizedBox(width: 8),
                Expanded(child: _Stat('Aujourd’hui', '${dash['today'] ?? 0}', AppColors.info)),
                const SizedBox(width: 8),
                Expanded(child: _Stat('Places · 7 j', '${dash['seats_sold_week'] ?? 0}', AppColors.primary)),
              ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('À confirmer'), selected: _filter == 'pending', onSelected: (_) => setState(() => _filter = 'pending')),
              ChoiceChip(label: const Text('Confirmées'), selected: _filter == 'confirmed', onSelected: (_) => setState(() => _filter = 'confirmed')),
              ChoiceChip(label: const Text('Toutes'), selected: _filter == 'all', onSelected: (_) => setState(() => _filter = 'all')),
            ]),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 30),
                child: EmptyState(icon: Icons.confirmation_number_outlined, message: 'Aucune réservation ici.'),
              ),
            for (final b in list)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(b.code, style: const TextStyle(fontWeight: FontWeight.w800))),
                    BookingStatusTag(b),
                  ]),
                  const SizedBox(height: 4),
                  Text('${b.trip?.route ?? ''} · ${formatDateTime(b.trip?.departureAt)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${b.passengers} place${b.passengers > 1 ? 's' : ''} · ${fcfa(b.ticketsTotal)}'
                      '${b.isDelivery ? ' · ticket à livrer' : ' · e-ticket'}${b.paid ? ' · payé' : ''}',
                      style: const TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(child: Text(b.customerName, style: const TextStyle(fontWeight: FontWeight.w700))),
                    TextButton.icon(onPressed: () => callPhone(b.customerPhone), icon: const Icon(Icons.call_rounded, size: 18), label: Text(displayPhone(b.customerPhone))),
                  ]),
                  if (b.passengerNames.isNotEmpty) Text('Voyageurs : ${b.passengerNames.join(', ')}'),
                  if ((b.seatNumbers ?? '').isNotEmpty) Text('Places : ${b.seatNumbers}'),
                  if ((b.note ?? '').isNotEmpty) Text('« ${b.note} »', style: const TextStyle(fontStyle: FontStyle.italic)),
                  if (b.isDelivery && b.dropoffAddress != null) Text('Livraison : ${b.dropoffAddress}', style: const TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (b.status == 'pending') ...[
                      FilledButton.icon(onPressed: () => _confirm(b), icon: const Icon(Icons.check_rounded), label: const Text('Confirmer')),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                        onPressed: () => _reject(b),
                        child: const Text('Refuser'),
                      ),
                    ],
                    if (const {'confirmed', 'out_for_delivery', 'delivered'}.contains(b.status))
                      FilledButton.icon(
                        onPressed: () => _act(b, 'board', 'Voyageur embarqué'),
                        icon: const Icon(Icons.directions_bus_rounded),
                        label: const Text('Embarqué'),
                      ),
                    if (b.status == 'confirmed' && !b.paid && !b.isDelivery)
                      OutlinedButton(onPressed: () => _act(b, 'paid', 'Paiement enregistré'), child: const Text('Payé au guichet')),
                    if (b.status == 'confirmed' && b.deliveryId == null)
                      TextButton(onPressed: () => _reject(b), child: const Text('Annuler', style: TextStyle(color: AppColors.danger))),
                  ]),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ]),
      );
}

/// Confirmation d'une réservation : numéros de place, numéro de ticket, message (tout est facultatif).
class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({required this.booking});
  final TravelBooking booking;
  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  final _seats = TextEditingController();
  final _ticket = TextEditingController();
  final _message = TextEditingController();

  @override
  void dispose() {
    _seats.dispose();
    _ticket.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    return AlertDialog(
      title: Text('Confirmer ${b.code}'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${b.passengers} place${b.passengers > 1 ? 's' : ''} · ${b.customerName}'),
          if (b.isDelivery)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Préparez le ticket papier : un livreur Telima viendra le chercher au guichet et encaissera le prix pour vous.',
                  style: TextStyle(color: AppColors.info, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 10),
          TextField(controller: _seats, decoration: const InputDecoration(labelText: 'Numéros de place (facultatif)', hintText: 'Ex. 12, 13')),
          const SizedBox(height: 8),
          TextField(controller: _ticket, decoration: const InputDecoration(labelText: 'N° du ticket (facultatif)')),
          const SizedBox(height: 8),
          TextField(
            controller: _message,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Message au voyageur (facultatif)', hintText: 'Ex. Soyez à la gare 30 min avant'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Retour')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {'seat_numbers': _seats.text, 'ticket_number': _ticket.text, 'message': _message.text}),
          child: const Text('Confirmer'),
        ),
      ],
    );
  }
}

// ----- Départs -----

class _TripsTab extends ConsumerWidget {
  const _TripsTab({required this.company});
  final TransportCompany company;

  Future<void> _edit(BuildContext context, WidgetRef ref, {TravelTrip? trip, bool duplicate = false}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TripFormSheet(companyId: company.id, trip: trip, duplicate: duplicate),
    );
    if (saved == true) ref.invalidate(companyTripsProvider(company.id));
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, TravelTrip t) async {
    final reason = await promptDialog(context,
        title: 'Annuler le départ ${t.route} du ${formatDateTime(t.departureAt)} ?',
        label: 'Motif communiqué aux voyageurs',
        required: false);
    if (reason == null || !context.mounted) return;
    await runWithLoader(context, () => ref.read(travelRepositoryProvider).cancelTrip(t.id, reason: reason),
        success: 'Départ annulé, voyageurs prévenus');
    ref.invalidate(companyTripsProvider(company.id));
    ref.invalidate(companyBookingsProvider(company.id));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, TravelTrip t) async {
    final ok = await confirmDialog(context, title: 'Supprimer ce départ ?', confirmLabel: 'Supprimer', danger: true);
    if (!ok || !context.mounted) return;
    await runWithLoader(context, () => ref.read(travelRepositoryProvider).deleteTrip(t.id), success: 'Départ supprimé');
    ref.invalidate(companyTripsProvider(company.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(companyTripsProvider(company.id));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(companyTripsProvider(company.id)),
      child: AsyncBody<List<TravelTrip>>(
        value: async,
        onRetry: () => ref.invalidate(companyTripsProvider(company.id)),
        builder: (list) {
          final upcoming = list.where((t) => !t.departed).toList();
          final past = list.where((t) => t.departed).toList().reversed.toList();
          Widget card(TravelTrip t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TripCard(
                    trip: t,
                    showCompany: false,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => switch (v) {
                        'edit' => _edit(context, ref, trip: t),
                        'copy' => _edit(context, ref, trip: t, duplicate: true),
                        'cancel' => _cancel(context, ref, t),
                        _ => _delete(context, ref, t),
                      },
                      itemBuilder: (_) => [
                        if (!t.cancelled && !t.departed) const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                        const PopupMenuItem(value: 'copy', child: Text('Dupliquer (autre date)')),
                        if (!t.cancelled && !t.departed) const PopupMenuItem(value: 'cancel', child: Text('Annuler le départ')),
                        if (t.seatsSold == 0) const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6, top: 4),
                    child: Text('${t.seatsSold} / ${t.seatsTotal} places réservées${t.cancelled && t.cancelReason != null ? ' · ${t.cancelReason}' : ''}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ),
                ]),
              );
          return ListView(padding: const EdgeInsets.all(16), children: [
            BigActionButton(label: 'AJOUTER UN DÉPART', icon: Icons.add_rounded, onPressed: () => _edit(context, ref)),
            const SizedBox(height: 12),
            if (upcoming.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('Aucun départ à venir. Ajoutez vos horaires : les voyageurs pourront réserver aussitôt.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
              ),
            for (final t in upcoming) card(t),
            if (past.isNotEmpty) ...[
              const SectionTitle('Départs passés (30 derniers jours)'),
              for (final t in past) Opacity(opacity: 0.7, child: card(t)),
            ],
          ]);
        },
      ),
    );
  }
}

/// Ajouter, modifier ou dupliquer un départ.
class TripFormSheet extends ConsumerStatefulWidget {
  const TripFormSheet({super.key, required this.companyId, this.trip, this.duplicate = false});
  final String companyId;
  final TravelTrip? trip;
  final bool duplicate;

  @override
  ConsumerState<TripFormSheet> createState() => _TripFormSheetState();
}

class _TripFormSheetState extends ConsumerState<TripFormSheet> {
  final _form = GlobalKey<FormState>();
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _price = TextEditingController();
  final _seats = TextEditingController(text: '50');
  final _duration = TextEditingController();
  final _class = TextEditingController();
  final _station = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _date;
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  bool _saving = false;

  bool get _editing => widget.trip != null && !widget.duplicate;

  @override
  void initState() {
    super.initState();
    final t = widget.trip;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _date = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
    if (t != null) {
      _from.text = t.fromCity;
      _to.text = t.toCity;
      _price.text = '${t.price}';
      _seats.text = '${t.seatsTotal}';
      _duration.text = t.durationMinutes == null ? '' : (t.durationMinutes! / 60).toStringAsFixed(t.durationMinutes! % 60 == 0 ? 0 : 1);
      _class.text = t.busClass ?? '';
      _station.text = t.departureStation ?? '';
      _notes.text = t.notes ?? '';
      final d = t.departureAt.toLocal();
      _time = TimeOfDay(hour: d.hour, minute: d.minute);
      if (_editing) _date = DateTime(d.year, d.month, d.day);
    }
  }

  @override
  void dispose() {
    for (final c in [_from, _to, _price, _seats, _duration, _class, _station, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final dep = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    if (dep.isBefore(DateTime.now())) {
      showError(context, Exception('L’heure de départ est déjà passée'));
      return;
    }
    final hours = double.tryParse(_duration.text.replaceAll(',', '.').trim());
    setState(() => _saving = true);
    try {
      await ref.read(travelRepositoryProvider).saveTrip(
            id: _editing ? widget.trip!.id : null,
            companyId: widget.companyId,
            fromCity: _from.text,
            toCity: _to.text,
            departureAt: dep,
            durationMinutes: hours == null ? null : (hours * 60).round(),
            busClass: _class.text,
            price: int.parse(_price.text.replaceAll(' ', '')),
            seatsTotal: int.parse(_seats.text.trim()),
            departureStation: _station.text,
            notes: _notes.text,
          );
      if (mounted) {
        showSuccess(context, _editing ? 'Départ modifié' : 'Départ publié');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: Form(
        key: _form,
        child: ListView(shrinkWrap: true, children: [
          Text(_editing ? 'Modifier le départ' : 'Nouveau départ', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _from,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Départ', hintText: 'Ouagadougou'),
                validator: (v) => (v ?? '').trim().length < 2 ? 'Ville ?' : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _to,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Arrivée', hintText: 'Bobo-Dioulasso'),
                validator: (v) {
                  if ((v ?? '').trim().length < 2) return 'Ville ?';
                  if (v!.trim().toLowerCase() == _from.text.trim().toLowerCase()) return 'Même ville';
                  return null;
                },
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date.isBefore(now) ? now : _date,
                    firstDate: DateTime(now.year, now.month, now.day),
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (d != null) setState(() => _date = d);
                },
                icon: const Icon(Icons.calendar_month_rounded),
                label: Text(formatDate(_date)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final t = await showTimePicker(context: context, initialTime: _time);
                  if (t != null) setState(() => _time = t);
                },
                icon: const Icon(Icons.schedule_rounded),
                label: Text('${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Prix (FCFA)'),
                validator: (v) => Validators.positiveInt(v, min: 0),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _seats,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Places'),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  return n == null || n < 1 || n > 200 ? 'Entre 1 et 200' : null;
                },
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _duration,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Durée (h)', hintText: '5,5'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(controller: _class, decoration: const InputDecoration(labelText: 'Classe', hintText: 'VIP, Climatisé')),
            ),
          ]),
          const SizedBox(height: 10),
          TextFormField(
            controller: _station,
            decoration: const InputDecoration(labelText: 'Gare de départ', helperText: 'Si différente de la gare principale (facultatif)'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _notes,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Informations', hintText: 'Ex. bagages : 1 valise incluse'),
          ),
          BigActionButton(
            label: _editing ? 'ENREGISTRER' : 'PUBLIER LE DÉPART',
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: _save,
          ),
        ]),
      ),
    );
  }
}

// ----- Contrôle à l'embarquement -----

class _ControlTab extends ConsumerStatefulWidget {
  const _ControlTab({required this.companyId});
  final String companyId;

  @override
  ConsumerState<_ControlTab> createState() => _ControlTabState();
}

class _ControlTabState extends ConsumerState<_ControlTab> {
  final _code = TextEditingController();
  TicketCheck? _result;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_code.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(travelRepositoryProvider).checkTicket(widget.companyId, _code.text);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _board() async {
    final id = _result?.bookingId;
    if (id == null) return;
    await runWithLoader(context, () => ref.read(travelRepositoryProvider).bookingAction(id, 'board'), success: 'Voyageur embarqué');
    ref.invalidate(companyBookingsProvider(widget.companyId));
    if (mounted) {
      _code.clear();
      setState(() => _result = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Contrôle des tickets', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      const Text(
          'Saisissez le code du ticket (ex. VOY-2026-000012, ou seulement 12), ou collez le contenu du QR code lu par votre téléphone.',
          style: TextStyle(color: AppColors.textMuted, height: 1.35)),
      const SizedBox(height: 12),
      TextField(
        controller: _code,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _check(),
        decoration: InputDecoration(
          labelText: 'Code du ticket',
          prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
          suffixIcon: IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => setState(() {
                _code.clear();
                _result = null;
              })),
        ),
      ),
      const SizedBox(height: 10),
      BigActionButton(label: 'VÉRIFIER', icon: Icons.verified_rounded, loading: _busy, onPressed: _check),
      if (r != null) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (r.valid ? AppColors.primary : AppColors.danger).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: r.valid ? AppColors.primary : AppColors.danger, width: 2),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(r.valid ? Icons.check_circle_rounded : Icons.cancel_rounded, color: r.valid ? AppColors.primary : AppColors.danger, size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(r.message,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: r.valid ? AppColors.primaryDark : AppColors.danger)),
              ),
            ]),
            if (r.code != null) ...[
              const SizedBox(height: 10),
              Text('${r.code} · ${r.trip ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${r.customerName ?? ''} · ${r.passengers} place${r.passengers > 1 ? 's' : ''}'),
              if (r.passengerNames.isNotEmpty) Text('Voyageurs : ${r.passengerNames.join(', ')}'),
              if ((r.seatNumbers ?? '').isNotEmpty) Text('Places : ${r.seatNumbers}'),
              Text(r.paid ? 'Payé' : 'À encaisser : ${fcfa(r.ticketsTotal)}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: r.paid ? AppColors.primaryDark : AppColors.accent)),
            ],
            if (r.valid) ...[
              const SizedBox(height: 12),
              BigActionButton(label: r.paid ? 'EMBARQUER' : 'ENCAISSÉ · EMBARQUER', icon: Icons.directions_bus_rounded, onPressed: _board),
            ],
          ]),
        ),
      ],
    ]);
  }
}
