import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../data/models/gas.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/common.dart';
import 'gas_widgets.dart';

/// Fiche d'un point de vente de gaz ou d'une station-service.
class PlaceDetailScreen extends ConsumerWidget {
  const PlaceDetailScreen({super.key, required this.placeId, this.initial});
  final String placeId;
  final Place? initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(placeProvider(placeId));
    // Les produits viennent toujours du serveur (prix et disponibilités à jour).
    final place = async.value ?? initial;
    return Scaffold(
      appBar: AppBar(title: Text(place?.name ?? 'Point de vente')),
      body: place == null
          ? AsyncBody<Place?>(value: async, builder: (_) => const Center(child: Text('Point introuvable')), onRetry: () => ref.invalidate(placeProvider(placeId)))
          : _Body(place: place),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.place});
  final Place place;

  Future<void> _report(BuildContext context, WidgetRef ref, String target, {Availability? value, String? productId, String? note}) async {
    if (!ref.read(authControllerProvider).isSignedIn) {
      showError(context, Exception('Connectez-vous pour faire un signalement'));
      return;
    }
    try {
      final r = await ref.read(gasRepositoryProvider).report(place.id, target, value: value, productId: productId, note: note);
      ref.invalidate(placeProvider(place.id));
      if (context.mounted) {
        showSuccess(context, r['applied'] == true ? 'Merci ! L’information est mise à jour.' : 'Merci ! Elle sera prise en compte dès qu’une autre personne la confirme.');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _availabilitySheet(BuildContext context, WidgetRef ref, String title, String target, {String? productId}) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Votre signalement aide les autres. Il est vérifié avec ceux des autres personnes.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 14),
            for (final a in const [Availability.available, Availability.low, Availability.out])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: a.color, side: BorderSide(color: a.color)),
                  icon: Icon(a.icon),
                  label: Text(a.label),
                  onPressed: () {
                    Navigator.pop(context);
                    _report(context, ref, target, value: a, productId: productId);
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoritePlaceIdsProvider).value ?? const <String>{};
    final isFav = favs.contains(place.id);
    final canOrder = !place.isStation && place.products.any((p) => p.availability.orderable);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      Constrained(
        maxWidth: 720,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            PlaceIcon(isStation: place.isStation, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(place.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                if (place.subtitle.isNotEmpty) Text(place.subtitle, style: const TextStyle(color: AppColors.textMuted)),
              ]),
            ),
            IconButton(
              tooltip: 'Favori',
              icon: Icon(isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: AppColors.danger),
              onPressed: () async {
                if (!ref.read(authControllerProvider).isSignedIn) {
                  showError(context, Exception('Connectez-vous pour ajouter aux favoris'));
                  return;
                }
                await ref.read(gasRepositoryProvider).toggleFavorite(place.id);
                ref.invalidate(favoritePlaceIdsProvider);
              },
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            RatingBadge(avg: place.ratingAvg, count: place.ratingCount, size: 15),
            if (place.promoTitle != null) SmallTag('Promotion : ${place.promoTitle}', AppColors.danger, icon: Icons.local_offer_rounded),
            if (place.isOsm) const SmallTag('Données OpenStreetMap', AppColors.textMuted),
          ]),
          const SizedBox(height: 12),
          if (place.address != null && place.address!.isNotEmpty) _Info(Icons.place_rounded, place.address!),
          if (place.hours != null && place.hours!.isNotEmpty) _Info(Icons.schedule_rounded, place.hours!),
          if (place.phone != null && place.phone!.isNotEmpty) _Info(Icons.phone_rounded, displayPhone(place.phone)),
          if (place.distanceKm != null) _Info(Icons.near_me_rounded, '${km(place.distanceKm)} de vous'),
          if (place.services.isNotEmpty) _Info(Icons.add_business_rounded, place.services.join(' · ')),
          if (place.delivers) _Info(Icons.delivery_dining_rounded, 'Livre à domicile jusqu’à ${place.deliveryRadiusKm.toStringAsFixed(0)} km'),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _BigAction(icon: Icons.directions_rounded, label: 'ITINÉRAIRE', color: AppColors.info, onTap: () => openNavigation(place.position))),
            const SizedBox(width: 10),
            Expanded(
              child: _BigAction(
                icon: Icons.call_rounded,
                label: 'APPELER',
                color: AppColors.primary,
                onTap: place.phone == null || place.phone!.isEmpty ? null : () => callPhone(place.phone!),
              ),
            ),
          ]),
          const SectionTitle('Sur place'),
          if (place.hasQueue)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: Align(alignment: Alignment.centerLeft, child: QueueChip(place: place, full: true)))
          else
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('Pas d’information récente sur la file d’attente.', style: TextStyle(color: AppColors.textMuted)),
            ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54), foregroundColor: AppColors.primaryDark, side: const BorderSide(color: AppColors.primary, width: 1.5)),
            icon: const Icon(Icons.where_to_vote_rounded),
            label: const Text('JE SUIS SUR PLACE', style: TextStyle(fontWeight: FontWeight.w800)),
            onPressed: () => showOnSiteSheet(context, ref, place),
          ),
          const SectionTitle('Disponibilités'),
          if (place.isStation) ...[
            if (place.fuels.isEmpty) const Text('Aucune information pour le moment. Soyez le premier à signaler !', style: TextStyle(color: AppColors.textMuted)),
            for (final f in place.fuels)
              _Row(
                title: f.label,
                price: f.price == null ? null : fcfa(f.price),
                chip: AvailabilityChip(f.availability, at: f.confirmedAt, showAge: true),
                onReport: () => _availabilitySheet(context, ref, '${f.label} : où en est-on ?', f.fuel),
              ),
            for (final fuel in const ['essence', 'gasoil'])
              if (!place.fuels.any((f) => f.fuel == fuel))
                _Row(
                  title: fuel == 'essence' ? 'Essence' : 'Gasoil',
                  chip: const AvailabilityChip(Availability.unknown),
                  onReport: () => _availabilitySheet(context, ref, '${fuel == 'essence' ? 'Essence' : 'Gasoil'} : où en est-on ?', fuel),
                ),
          ] else ...[
            if (place.products.isEmpty) const Text('Aucune bouteille renseignée pour le moment.', style: TextStyle(color: AppColors.textMuted)),
            for (final p in place.products)
              _Row(
                title: '${p.brand} · ${p.sizeLabel}',
                price: p.onPromo ? '${fcfa(p.finalPrice)}  (avant ${fcfa(p.price)} · ${p.promoTitle ?? 'promotion'})' : fcfa(p.price),
                chip: AvailabilityChip(p.availability, at: p.confirmedAt, showAge: true),
                onReport: () => _availabilitySheet(context, ref, '${p.brand} ${p.sizeLabel} : où en est-on ?', 'gas', productId: p.id),
              ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 8, children: [
              ActionChip(avatar: const Icon(Icons.store_mall_directory_outlined, size: 18), label: const Text('Point fermé'), onPressed: () => _report(context, ref, 'closed')),
              ActionChip(
                avatar: const Icon(Icons.price_change_outlined, size: 18),
                label: const Text('Prix incorrect'),
                onPressed: () async {
                  final c = TextEditingController();
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Prix incorrect'),
                      content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Quel est le bon prix ?'), maxLength: 120),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Envoyer')),
                      ],
                    ),
                  );
                  if (ok == true && context.mounted) _report(context, ref, 'price', note: c.text);
                },
              ),
            ]),
          ),
          _Reviews(place: place),
          if (!place.isStation) ...[
            const SizedBox(height: 18),
            BigActionButton(
              label: 'COMMANDER',
              icon: Icons.shopping_bag_rounded,
              onPressed: canOrder ? () => context.push('/client/gas/order/${place.id}', extra: place) : null,
            ),
            if (!canOrder)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Aucune bouteille disponible pour le moment.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
              ),
          ],
        ]),
      ),
    ]);
  }
}

class _Info extends StatelessWidget {
  const _Info(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.3))),
        ]),
      );
}

class _BigAction extends StatelessWidget {
  const _BigAction({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: color, minimumSize: const Size.fromHeight(56)),
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.chip, required this.onReport, this.price});
  final String title;
  final String? price;
  final Widget chip;
  final VoidCallback onReport;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (price != null) Text(price!, style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              chip,
            ]),
          ),
          TextButton(onPressed: onReport, child: const Text('Signaler')),
        ]),
      );
}

/// Avis des clients + formulaire « Donner mon avis ».
class _Reviews extends ConsumerWidget {
  const _Reviews({required this.place});
  final Place place;

  Future<void> _write(BuildContext context, WidgetRef ref, PlaceReview? mine) async {
    if (!ref.read(authControllerProvider).isSignedIn) {
      showError(context, Exception('Connectez-vous pour donner votre avis'));
      return;
    }
    var rating = mine?.rating ?? 5;
    final c = TextEditingController(text: mine?.comment ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: const Text('Votre avis'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setS(() => rating = i),
                  icon: Icon(i <= rating ? Icons.star_rounded : Icons.star_border_rounded, color: AppColors.accent, size: 34),
                ),
            ]),
            TextField(controller: c, maxLength: 500, maxLines: 3, decoration: const InputDecoration(labelText: 'Commentaire (facultatif)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publier')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(gasRepositoryProvider).reviewPlace(place.id, rating, c.text);
      ref.invalidate(placeReviewsProvider(place.id));
      ref.invalidate(placeProvider(place.id));
      if (context.mounted) showSuccess(context, 'Merci pour votre avis !');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(placeReviewsProvider(place.id)).value ?? const <PlaceReview>[];
    final mine = reviews.where((r) => r.mine).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Avis des clients'),
      Row(children: [
        RatingBadge(avg: place.ratingAvg, count: place.ratingCount, size: 16),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () => _write(context, ref, mine),
          icon: const Icon(Icons.rate_review_outlined, size: 18),
          label: Text(mine == null ? 'Donner mon avis' : 'Modifier mon avis'),
        ),
      ]),
      const SizedBox(height: 8),
      for (final r in reviews.take(10))
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              for (var i = 1; i <= 5; i++) Icon(i <= r.rating ? Icons.star_rounded : Icons.star_border_rounded, size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(child: Text(r.mine ? 'Vous' : r.author, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (r.verified) const SmallTag('Achat vérifié', AppColors.primaryDark, icon: Icons.verified_rounded),
            ]),
            if (r.comment != null && r.comment!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.comment!)),
          ]),
        ),
      if (reviews.isEmpty) const Text('Soyez le premier à donner votre avis.', style: TextStyle(color: AppColors.textMuted)),
    ]);
  }
}

/// Feuille « Je suis sur place » : file d'attente + disponibilités, envoyées avec la position.
Future<void> showOnSiteSheet(BuildContext context, WidgetRef ref, Place place) async {
  if (!ref.read(authControllerProvider).isSignedIn) {
    showError(context, Exception('Connectez-vous pour signaler sur place'));
    return;
  }
  String? queue;
  var people = -1; // -1 = non renseigné
  final fuels = <String, String>{};
  final targets = place.isStation ? const ['essence', 'gasoil'] : const ['gas'];
  String targetLabel(String t) => t == 'essence' ? 'Essence' : t == 'gasoil' ? 'Gasoil' : 'Gaz';
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => StatefulBuilder(
      builder: (context, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Je suis sur place', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Votre position est vérifiée (moins de 300 m). L’information est publiée tout de suite, avec l’heure.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 14),
            const Text('File d’attente', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final q in const ['none', 'short', 'medium', 'long'])
                ChoiceChip(label: Text(QueueChip.label(q)), selected: queue == q, onSelected: (_) => setS(() => queue = queue == q ? null : q)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: Text('Personnes devant vous (environ)', style: TextStyle(fontWeight: FontWeight.w700))),
              IconButton.filledTonal(onPressed: people <= 0 ? null : () => setS(() => people = people - 5 < 0 ? 0 : people - 5), icon: const Icon(Icons.remove_rounded)),
              SizedBox(width: 56, child: Text(people < 0 ? '—' : '$people', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              IconButton.filledTonal(onPressed: () => setS(() => people = people < 0 ? 5 : people + 5), icon: const Icon(Icons.add_rounded)),
            ]),
            const SizedBox(height: 12),
            for (final t in targets) ...[
              Text(targetLabel(t), style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final a in const [Availability.available, Availability.low, Availability.out])
                  ChoiceChip(
                    label: Text(a == Availability.low ? 'Stock incertain' : a.label),
                    selected: fuels[t] == a.name,
                    onSelected: (_) => setS(() => fuels[t] == a.name ? fuels.remove(t) : fuels[t] = a.name),
                  ),
              ]),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            BigActionButton(label: 'Publier', icon: Icons.send_rounded, onPressed: () => Navigator.pop(context, true)),
          ]),
        ),
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  if (queue == null && people < 0 && fuels.isEmpty) {
    showError(context, Exception('Indiquez au moins la file ou une disponibilité'));
    return;
  }
  try {
    final pos = await ref.read(locationServiceProvider).current();
    final r = await ref.read(gasRepositoryProvider).reportOnSite(place.id,
        lat: pos.latitude, lng: pos.longitude, queue: queue, people: people < 0 ? null : people, fuels: fuels);
    ref.invalidate(placeProvider(place.id));
    ref.invalidate(nearbyPlacesProvider);
    if (context.mounted) {
      final w = r['wait_min'];
      showSuccess(context, 'Merci ! Vous aidez toute la communauté.${w is num && w > 0 ? ' Attente estimée : ~$w min.' : ''}');
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}
