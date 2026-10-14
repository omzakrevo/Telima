import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../config/theme.dart';
import '../../core/utils/errors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../data/models/delivery.dart';
import '../../data/models/travel.dart';
import '../../data/models/travel_brand.dart';
import '../../providers/auth_providers.dart';
import '../../providers/data_providers.dart';
import '../../providers/travel_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../../widgets/payment_flow.dart';
import '../../widgets/point_form.dart';
import '../restaurant/restaurant_widgets.dart' show InfoTag;
import 'travel_widgets.dart';

// ---------------------------------------------------------------------------
// Recherche d'un voyage
// ---------------------------------------------------------------------------

/// Tranches horaires de départ (heure du Burkina).
const _timeBands = <({String label, String range, IconData icon, int from, int to})>[
  (label: 'Matin', range: '5h–12h', icon: Icons.wb_twilight_rounded, from: 5, to: 12),
  (label: 'Après-midi', range: '12h–18h', icon: Icons.wb_sunny_rounded, from: 12, to: 18),
  (label: 'Soir', range: '18h–24h', icon: Icons.nights_stay_rounded, from: 18, to: 24),
  (label: 'Nuit', range: '0h–5h', icon: Icons.bedtime_rounded, from: 0, to: 5),
];

/// Lignes proposées en un geste quand aucun critère n'est choisi (si les deux villes existent).
const _popularRoutes = [
  ('Ouagadougou', 'Bobo-Dioulasso'),
  ('Bobo-Dioulasso', 'Ouagadougou'),
  ('Bobo-Dioulasso', 'Banfora'),
  ('Ouagadougou', 'Ouahigouya'),
];

/// Choisir son voyage : ville de départ, ville d'arrivée, compagnie, heure, jour.
/// Les horaires s'affichent dès le premier choix, sans bouton « Rechercher ».
class TravelSearchScreen extends ConsumerStatefulWidget {
  const TravelSearchScreen({super.key});

  @override
  ConsumerState<TravelSearchScreen> createState() => _TravelSearchScreenState();
}

class _TravelSearchScreenState extends ConsumerState<TravelSearchScreen> {
  String _from = '';
  String _to = '';
  TransportCompany? _company;
  int _band = -1;
  DateTime? _date;
  int _swapTurns = 0;

  TripQuery get _query => (
        from: _from,
        to: _to,
        date: _date,
        companyId: _company?.id,
        hourFrom: _band < 0 ? null : _timeBands[_band].from,
        hourTo: _band < 0 ? null : _timeBands[_band].to,
      );

  bool get _active => _from.isNotEmpty || _to.isNotEmpty || _company != null || _band >= 0 || _date != null;

  void _reset() => setState(() {
        _from = '';
        _to = '';
        _company = null;
        _band = -1;
        _date = null;
      });

  void _swap() => setState(() {
        final f = _from;
        _from = _to;
        _to = f;
        _swapTurns++;
      });

  Future<void> _pickCity({required bool isFrom, required List<String> cities}) async {
    final r = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _CitySheet(
        title: isFrom ? 'Ville de départ' : 'Ville d’arrivée',
        cities: cities,
        current: isFrom ? _from : _to,
      ),
    );
    if (r == null) return;
    setState(() => isFrom ? _from = r : _to = r);
  }

  Future<void> _pickCompany(List<TransportCompany> companies) async {
    final r = await showModalBottomSheet<({TransportCompany? company})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _CompanySheet(companies: companies, current: _company),
    );
    if (r == null) return;
    setState(() => _company = r.company);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
    );
    if (d != null) setState(() => _date = d);
  }

  @override
  Widget build(BuildContext context) {
    final cities = ref.watch(travelCitiesProvider).value ?? const <String>[];
    final companies = ref.watch(travelCompaniesProvider);
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    bool sameDay(DateTime? a, DateTime b) => a != null && a.year == b.year && a.month == b.month && a.day == b.day;

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
        onRefresh: () async {
          ref.invalidate(travelCompaniesProvider);
          ref.invalidate(tripSearchProvider(_query));
        },
        child: Constrained(
          maxWidth: 760,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            const FadeSlideIn(child: _TravelHero()),
            const SizedBox(height: 14),
            // ----- Choix du trajet -----
            FadeSlideIn(
              delay: const Duration(milliseconds: 120),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.line),
                  boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 18, offset: const Offset(0, 6))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Column(children: [
                        _PickTile(
                          icon: Icons.trip_origin_rounded,
                          label: 'Départ',
                          placeholder: 'Choisir la ville de départ',
                          value: _from,
                          onTap: () => _pickCity(isFrom: true, cities: cities),
                          onClear: () => setState(() => _from = ''),
                        ),
                        const SizedBox(height: 8),
                        _PickTile(
                          icon: Icons.place_rounded,
                          iconColor: AppColors.accent,
                          label: 'Arrivée',
                          placeholder: 'Choisir la ville d’arrivée',
                          value: _to,
                          onTap: () => _pickCity(isFrom: false, cities: cities),
                          onClear: () => setState(() => _to = ''),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: 'Inverser',
                      onPressed: _swap,
                      icon: AnimatedRotation(turns: _swapTurns / 2, duration: const Duration(milliseconds: 350), curve: Curves.easeOutBack, child: const Icon(Icons.swap_vert_rounded)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  _PickTile(
                    icon: Icons.directions_bus_rounded,
                    label: 'Compagnie',
                    placeholder: 'Toutes les compagnies',
                    value: _company?.name ?? '',
                    leading: _company == null ? null : CompanyAvatar(slug: _company!.slug, name: _company!.name, logoPath: _company!.logoPath, size: 28, radius: 8),
                    onTap: () => _pickCompany(companies.value ?? const []),
                    onClear: () => setState(() => _company = null),
                  ),
                  const SizedBox(height: 14),
                  const Text('Heure de départ', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final (i, b) in _timeBands.indexed)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: Icon(b.icon, size: 18, color: _band == i ? AppColors.primaryDark : AppColors.textMuted),
                            label: Text('${b.label} · ${b.range}'),
                            selected: _band == i,
                            onSelected: (v) => setState(() => _band = v ? i : -1),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  const Text('Jour', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      ChoiceChip(label: const Text('Tous les jours'), selected: _date == null, onSelected: (_) => setState(() => _date = null)),
                      const SizedBox(width: 8),
                      ChoiceChip(label: const Text('Aujourd’hui'), selected: sameDay(_date, today), onSelected: (_) => setState(() => _date = today)),
                      const SizedBox(width: 8),
                      ChoiceChip(label: const Text('Demain'), selected: sameDay(_date, tomorrow), onSelected: (_) => setState(() => _date = tomorrow)),
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                        label: Text(_date != null && !sameDay(_date, today) && !sameDay(_date, tomorrow) ? formatDate(_date) : 'Autre date'),
                        onPressed: _pickDate,
                      ),
                    ]),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    alignment: Alignment.topCenter,
                    child: _active
                        ? Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(onPressed: _reset, icon: const Icon(Icons.restart_alt_rounded, size: 18), label: const Text('Tout effacer')),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ]),
              ),
            ),
            // ----- Bandeau des compagnies -----
            const SectionTitle('Nos compagnies'),
            SizedBox(
              height: 148,
              child: companies.when(
                loading: () => ListView(scrollDirection: Axis.horizontal, children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      width: 136,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(18)),
                    ),
                ]),
                error: (_, _) => Center(
                  child: TextButton.icon(
                    onPressed: () => ref.invalidate(travelCompaniesProvider),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Recharger les compagnies'),
                  ),
                ),
                data: (list) => list.isEmpty
                    ? const Center(child: Text('Les compagnies arrivent bientôt.', style: TextStyle(color: AppColors.textMuted)))
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => FadeSlideIn(
                          delay: Duration(milliseconds: 80 * (i > 6 ? 6 : i)),
                          offset: 0,
                          child: _CompanyBannerCard(company: list[i], onTap: () => context.push('/v/${list[i].slug}')),
                        ),
                      ),
              ),
            ),
            // ----- Horaires -----
            const SizedBox(height: 6),
            if (!_active)
              _IdleHint(
                cities: cities,
                onRoute: (f, t) => setState(() {
                  _from = f;
                  _to = t;
                }),
              )
            else
              _Results(query: _query, onRetry: () => ref.invalidate(tripSearchProvider(_query))),
          ]),
        ),
      ),
    );
  }
}

/// Bandeau d'accueil : titre et petit car qui roule.
class _TravelHero extends StatelessWidget {
  const _TravelHero();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Où allez-vous ?', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text(
            'Choisissez votre trajet : les horaires s’affichent aussitôt. Retirez votre ticket au guichet.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), height: 1.35),
          ),
          const SizedBox(height: 10),
          const RoadBanner(height: 58),
        ]),
      );
}

/// Case de choix (ville, compagnie) : touche pour ouvrir la liste, croix pour effacer.
class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.icon,
    required this.label,
    required this.placeholder,
    required this.value,
    required this.onTap,
    required this.onClear,
    this.iconColor = AppColors.primaryDark,
    this.leading,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final String placeholder;
  final String value;
  final VoidCallback onTap;
  final VoidCallback onClear;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final has = value.isNotEmpty;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
        decoration: BoxDecoration(
          color: has ? AppColors.mint : AppColors.field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: has ? AppColors.primary.withValues(alpha: 0.5) : Colors.transparent),
        ),
        child: Row(children: [
          leading ?? Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              Text(has ? value : placeholder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: has ? FontWeight.w800 : FontWeight.w500, color: has ? null : AppColors.textMuted)),
            ]),
          ),
          if (has)
            IconButton(visualDensity: VisualDensity.compact, tooltip: 'Effacer', onPressed: onClear, icon: const Icon(Icons.close_rounded, size: 20))
          else
            const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted)),
        ]),
      ),
    );
  }
}

/// Liste des villes avec recherche. Renvoie la ville choisie, ou '' pour « toutes les villes ».
class _CitySheet extends StatefulWidget {
  const _CitySheet({required this.title, required this.cities, required this.current});
  final String title;
  final List<String> cities;
  final String current;

  @override
  State<_CitySheet> createState() => _CitySheetState();
}

class _CitySheetState extends State<_CitySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = [for (final c in widget.cities) if (q.isEmpty || c.toLowerCase().contains(q)) c];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(hintText: 'Rechercher une ville', prefixIcon: Icon(Icons.search_rounded)),
              ),
            ]),
          ),
          Expanded(
            child: ListView(children: [
              ListTile(
                leading: const Icon(Icons.public_rounded),
                title: const Text('Toutes les villes'),
                selected: widget.current.isEmpty,
                onTap: () => Navigator.pop(context, ''),
              ),
              if (list.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Aucune ville trouvée', style: TextStyle(color: AppColors.textMuted)))),
              for (final c in list)
                ListTile(
                  leading: const Icon(Icons.location_city_rounded),
                  title: Text(c, style: const TextStyle(fontWeight: FontWeight.w700)),
                  trailing: c == widget.current ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
                  onTap: () => Navigator.pop(context, c),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Liste des compagnies. Renvoie la compagnie choisie (ou `company: null` pour « toutes »).
class _CompanySheet extends StatelessWidget {
  const _CompanySheet({required this.companies, required this.current});
  final List<TransportCompany> companies;
  final TransportCompany? current;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Choisir une compagnie', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: ListView(children: [
              ListTile(
                leading: const Icon(Icons.apps_rounded),
                title: const Text('Toutes les compagnies'),
                selected: current == null,
                onTap: () => Navigator.pop(context, (company: null)),
              ),
              for (final c in companies)
                ListTile(
                  leading: CompanyAvatar(slug: c.slug, name: c.name, logoPath: c.logoPath, size: 44, radius: 12),
                  title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: c.subtitle.isEmpty ? null : Text(c.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: current?.id == c.id ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
                  onTap: () => Navigator.pop(context, (company: c)),
                ),
            ]),
          ),
        ]),
      );
}

/// Carte du bandeau « Nos compagnies » : logo, nom ; ouvre la page de la compagnie.
class _CompanyBannerCard extends StatelessWidget {
  const _CompanyBannerCard({required this.company, required this.onTap});
  final TransportCompany company;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = companyBrand(company.slug);
    return SizedBox(
      width: 136,
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [brand.color.withValues(alpha: 0.12), Colors.white], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: brand.color.withValues(alpha: 0.3)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CompanyAvatar(slug: company.slug, name: company.name, logoPath: company.logoPath, size: 56, radius: 16),
            const SizedBox(height: 8),
            Text(company.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, height: 1.2)),
            const SizedBox(height: 4),
            Text('Voir les horaires', style: TextStyle(fontSize: 11, color: brand.color, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

/// Avant le premier choix : invitation et lignes fréquentes.
class _IdleHint extends StatelessWidget {
  const _IdleHint({required this.cities, required this.onRoute});
  final List<String> cities;
  final void Function(String from, String to) onRoute;

  @override
  Widget build(BuildContext context) {
    final routes = [for (final r in _popularRoutes) if (cities.contains(r.$1) && cities.contains(r.$2)) r];
    return FadeSlideIn(
      delay: const Duration(milliseconds: 200),
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
            child: const Icon(Icons.search_rounded, size: 36, color: AppColors.primaryDark),
          ),
          const SizedBox(height: 12),
          const Text('Vos horaires s’affichent ici', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Choisissez une ville, une compagnie ou une heure de départ.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, height: 1.35),
          ),
          if (routes.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Lignes fréquentes', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              for (final r in routes)
                ActionChip(
                  avatar: const Icon(Icons.alt_route_rounded, size: 18),
                  label: Text('${r.$1} → ${r.$2}'),
                  onPressed: () => onRoute(r.$1, r.$2),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Départs correspondant aux critères, regroupés par jour.
class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.onRetry});
  final TripQuery query;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tripSearchProvider(query));
    return async.when(
      loading: () => const Padding(padding: EdgeInsets.all(30), child: LoadingView()),
      error: (e, _) => ErrorView(error: e, onRetry: onRetry),
      data: (list) {
        if (list.isEmpty) {
          return const FadeSlideIn(
            child: Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyState(
                icon: Icons.directions_bus_rounded,
                message: 'Aucun départ trouvé avec ces critères. Essayez une autre heure, un autre jour ou une autre compagnie.',
              ),
            ),
          );
        }
        final children = <Widget>[
          FadeSlideIn(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
              child: Text('${list.length}${list.length >= 150 ? '+' : ''} départ${list.length > 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
        ];
        DateTime? lastDay;
        for (final (i, t) in list.indexed) {
          final d = t.departureAt.toLocal();
          final day = DateTime(d.year, d.month, d.day);
          if (lastDay != day) {
            lastDay = day;
            children.add(Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
              child: Row(children: [
                const Icon(Icons.event_rounded, size: 18, color: AppColors.primaryDark),
                const SizedBox(width: 6),
                Text(_longDay(day), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
              ]),
            ));
          }
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FadeSlideIn(
              key: ValueKey(t.id),
              delay: Duration(milliseconds: i < 8 ? 60 * i : 0),
              child: TripCard(trip: t, onTap: t.bookable ? () => context.push('/voyage/${t.id}') : null),
            ),
          ));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      },
    );
  }
}

/// « Auj. · vendredi 17 octobre », « Demain · samedi 18 octobre » ou « lundi 19 octobre ».
String _longDay(DateTime d) {
  final base = DateFormat('EEEE d MMMM', 'fr_FR').format(d);
  final label = dayChipLabel(d);
  return label == 'Auj.' ? 'Aujourd’hui · $base' : (label == 'Demain' ? 'Demain · $base' : base);
}

// ---------------------------------------------------------------------------
// Page d'une compagnie (lien partagé /v/<slug>, ou touche dans le bandeau)
// ---------------------------------------------------------------------------

class CompanyPublicScreen extends ConsumerWidget {
  const CompanyPublicScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(companyBySlugProvider(slug));
    final c = async.value;
    return Scaffold(
      appBar: c == null ? AppBar(title: const Text('Compagnie')) : null,
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
            return _CompanyView(company: c);
          },
        ),
      ),
    );
  }
}

class _CompanyView extends StatefulWidget {
  const _CompanyView({required this.company});
  final TransportCompany company;

  @override
  State<_CompanyView> createState() => _CompanyViewState();
}

class _CompanyViewState extends State<_CompanyView> {
  final _pages = PageController();
  Timer? _auto;
  int _page = 0;

  CompanyBrand get _brand => companyBrand(widget.company.slug);

  @override
  void initState() {
    super.initState();
    if (_brand.photos.length > 1) {
      _auto = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted || !_pages.hasClients) return;
        final next = (_page + 1) % _brand.photos.length;
        _pages.animateToPage(next, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
      });
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _openPhoto(int index) => showDialog<void>(
        context: context,
        builder: (_) => _PhotoViewer(photos: _brand.photos, initial: index),
      );

  @override
  Widget build(BuildContext context) {
    final c = widget.company;
    final brand = _brand;
    final routes = groupRoutes(c.trips);
    final hasPhotos = brand.hasPhotos;
    final hasPosition = c.position.latitude != 0 || c.position.longitude != 0;
    return CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
      SliverAppBar(
        pinned: true,
        expandedHeight: hasPhotos ? 290 : 200,
        backgroundColor: brand.color,
        foregroundColor: Colors.white,
        actions: [
          IconButton(tooltip: 'QR code', icon: const Icon(Icons.qr_code_2_rounded), onPressed: () => showCompanyQr(context, c)),
          IconButton(tooltip: 'Partager', icon: const Icon(Icons.share_rounded), onPressed: () => shareCompanyLink(context, c)),
        ],
        flexibleSpace: FlexibleSpaceBar(
          collapseMode: CollapseMode.parallax,
          titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 14, end: 100),
          title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Colors.white)),
          background: Stack(fit: StackFit.expand, children: [
            if (hasPhotos)
              PageView.builder(
                controller: _pages,
                itemCount: brand.photos.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _openPhoto(i),
                  child: Image.asset(brand.photos[i], fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: brand.color)),
                ),
              )
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [brand.color, Color.lerp(brand.color, Colors.black, 0.35)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: Align(
                  alignment: const Alignment(0.7, 0.2),
                  child: Icon(Icons.directions_bus_rounded, size: 150, color: Colors.white.withValues(alpha: 0.18)),
                ),
              ),
            // Dégradé pour la lisibilité du titre
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.transparent, Color(0xB3000000)], begin: Alignment.center, end: Alignment.bottomCenter),
                ),
              ),
            ),
            if (brand.photos.length > 1)
              Positioned(
                right: 16,
                bottom: 18,
                child: Row(children: [
                  for (var i = 0; i < brand.photos.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.only(left: 5),
                      width: i == _page ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: i == _page ? 1 : 0.55), borderRadius: BorderRadius.circular(4)),
                    ),
                ]),
              ),
          ]),
        ),
      ),
      SliverToBoxAdapter(
        child: Constrained(
          maxWidth: 760,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Logo posé à cheval sur l'image, slogan et étiquettes
              FadeSlideIn(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14, offset: const Offset(0, 6))],
                      ),
                      child: CompanyAvatar(slug: c.slug, name: c.name, logoPath: c.logoPath, size: 76, radius: 20),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
      padding: const EdgeInsets.only(top: 14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if ((brand.tagline ?? '').isNotEmpty)
                          Text('« ${brand.tagline} »', style: TextStyle(fontStyle: FontStyle.italic, color: brand.color, fontWeight: FontWeight.w700)),
                        if (c.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(c.subtitle, style: const TextStyle(color: AppColors.textMuted)),
                        ],
                      ]),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  InfoTag(c.acceptingBookings ? 'Réservations ouvertes' : 'Réservations fermées',
                      color: c.acceptingBookings ? AppColors.primary : AppColors.danger,
                      icon: c.acceptingBookings ? Icons.check_circle_rounded : Icons.cancel_rounded),
                  const InfoTag('Retrait au guichet', color: AppColors.info, icon: Icons.storefront_rounded),
                  if (c.deliversTickets) const InfoTag('Ticket livré', color: AppColors.info, icon: Icons.delivery_dining_rounded),
                ]),
              ),
              if ((c.description ?? '').isNotEmpty)
                FadeSlideIn(
                  delay: const Duration(milliseconds: 100),
                  child: Padding(padding: const EdgeInsets.only(top: 6), child: Text(c.description!, style: const TextStyle(height: 1.45))),
                ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 150),
                child: Row(children: [
                  if ((c.phone ?? '').isNotEmpty)
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => callPhone(c.phone!),
                        icon: const Icon(Icons.call_rounded),
                        label: const Text('Appeler'),
                      ),
                    ),
                  if ((c.phone ?? '').isNotEmpty && hasPosition) const SizedBox(width: 10),
                  if (hasPosition)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => openNavigation(c.position),
                        icon: const Icon(Icons.directions_rounded),
                        label: const Text('La gare'),
                      ),
                    ),
                ]),
              ),
              if (brand.photos.length > 1) ...[
                const SectionTitle('Photos'),
                SizedBox(
                  height: 88,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: brand.photos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => FadeSlideIn(
                      delay: Duration(milliseconds: 70 * i),
                      offset: 0,
                      child: Pressable(
                        onTap: () => _openPhoto(i),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(brand.photos[i], width: 128, height: 88, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 128, height: 88)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SectionTitle('Horaires et tarifs'),
              if (routes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('Aucun départ programmé pour le moment.', style: TextStyle(color: AppColors.textMuted)),
                )
              else ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Text('Touchez une ligne, choisissez le jour puis l’heure.', style: TextStyle(color: AppColors.textMuted)),
                ),
                for (final (i, r) in routes.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FadeSlideIn(
                      delay: Duration(milliseconds: 70 * (i > 8 ? 8 : i)),
                      child: RouteScheduleCard(
                        route: r,
                        color: brand.color,
                        initiallyOpen: i == 0,
                        onBook: (t) => context.push('/voyage/${t.id}'),
                      ),
                    ),
                  ),
              ],
              const SectionTitle('Votre ticket au guichet'),
              FadeSlideIn(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.butter, borderRadius: BorderRadius.circular(16)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.storefront_rounded, color: AppColors.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Réservez ici (frais de réservation Telima : ${fcfa(travelServiceFee)}). Au guichet${(c.stationAddress ?? '').isEmpty ? '' : ' de ${c.stationAddress}'}, '
                        'présentez-vous avec votre nom, votre signature et la ville : on vous remet votre ticket.',
                        style: const TextStyle(height: 1.4),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// Photo en plein écran : glisser pour changer, pincer pour agrandir.
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.photos, required this.initial});
  final List<String> photos;
  final int initial;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final _pages = PageController(initialPage: widget.initial);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(children: [
          PageView.builder(
            controller: _pages,
            itemCount: widget.photos.length,
            itemBuilder: (_, i) => InteractiveViewer(
              maxScale: 4,
              child: Center(child: Image.asset(widget.photos[i], fit: BoxFit.contain)),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 8,
            child: IconButton.filledTonal(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          ),
        ]),
      );
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
  String _feeMethod = 'orange_money';
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
      final repo = ref.read(travelRepositoryProvider);
      final b = await repo.book(
            tripId: t.id,
            feeMethod: _feeMethod,
            passengers: _passengers,
            passengerNames: [for (final c in _names) c.text],
            ticketMode: _mode,
            note: _note.text,
            dropoff: _mode == 'delivery'
                ? {'address': _drop!.address, 'lat': _drop!.lat, 'lng': _drop!.lng, 'note': _drop!.instructions}
                : null,
          );
      ref.invalidate(myTravelBookingsProvider);
      if (mounted) showSuccess(context, 'Réservation envoyée à ${t.companyName ?? 'la compagnie'}');
      // Frais de réservation Telima : paiement Mobile Money tout de suite (reprise possible depuis la réservation)
      if (mounted && b.feePaymentId != null) {
        final payment = await repo.feePayment(b.feePaymentId);
        if (payment != null && mounted) await runMobileMoneyPayment(context, ref, payment);
      }
      if (mounted) context.go('/client/voyages/bookings/${b.id}');
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
            _TotalLine('Frais de réservation Telima', fcfa(travelServiceFee)),
            const Divider(height: 14),
            _TotalLine('TOTAL', fcfa(total + travelServiceFee), bold: true),
            Text(
                _mode == 'delivery'
                    ? 'Ticket et livraison payés en espèces au livreur · frais de réservation payés maintenant en Mobile Money'
                    : 'Ticket payé au guichet avant le départ · frais de réservation payés maintenant en Mobile Money',
                textAlign: TextAlign.center,
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
                icon: Icons.storefront_rounded,
                title: 'Au guichet',
                caption: 'Nom, signature, ville',
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
          const SectionTitle('Frais de réservation Telima'),
          Text('${fcfa(travelServiceFee)} par réservation, payés en Mobile Money. La compagnie confirme votre place dès qu’ils sont reçus.',
              style: const TextStyle(color: AppColors.textMuted, height: 1.35)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('Orange Money'), selected: _feeMethod == 'orange_money', onSelected: (_) => setState(() => _feeMethod = 'orange_money')),
            ChoiceChip(label: const Text('Moov Money'), selected: _feeMethod == 'moov_money', onSelected: (_) => setState(() => _feeMethod = 'moov_money')),
          ]),
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
                      child: Text(
                          b.feeDue
                              ? 'Vos places sont bloquées. Payez les frais de réservation (${fcfa(b.serviceFee)}) en Mobile Money : la compagnie confirmera ensuite votre place.'
                              : 'Vos places sont bloquées. La compagnie va confirmer votre réservation : vous recevrez une notification.',
                          style: const TextStyle(height: 1.35)),
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
                  if (b.serviceFee > 0) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: Text(b.feeLabel, style: TextStyle(fontWeight: FontWeight.w700, color: b.feePaid ? AppColors.primary : null))),
                      Text(fcfa(b.serviceFee), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                    if (b.feeDue && isCustomer)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                          onPressed: () async {
                            final payment = await ref.read(travelRepositoryProvider).retryFee(b.id);
                            if (!context.mounted) return;
                            await runMobileMoneyPayment(context, ref, payment);
                            ref.invalidate(travelBookingProvider(b.id));
                          },
                          icon: const Icon(Icons.phone_android_rounded),
                          label: Text('PAYER LES FRAIS (${fcfa(b.serviceFee)})'),
                        ),
                      ),
                  ],
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
