import 'dart:async';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'icon3d.dart';
import 'motion.dart';
import 'service_photo.dart';

/// Une diapositive : le besoin, la solution Telima, et où aller.
class ServiceSlide {
  const ServiceSlide({
    required this.tag,
    required this.problem,
    required this.solution,
    required this.cta,
    required this.route,
    required this.photo,
    required this.icon,
  });
  final String tag; // petit titre : « COLIS », « RESTAURANTS »…
  final String problem; // « Vous manquez de temps ? »
  final String solution; // « On récupère et on livre votre colis. »
  final String cta;
  final String route;
  final String photo; // assets/photos/<photo>.jpg (facultatif)
  final String icon; // illustration 3D de repli

  static const all = [
    ServiceSlide(
      tag: 'COLIS',
      problem: 'Pas le temps de vous déplacer ?',
      solution: 'Un livreur récupère votre colis et le remet en main propre, suivi en direct.',
      cta: 'Envoyer un colis',
      route: '/client/new',
      photo: 'colis',
      icon: Ico3D.package,
    ),
    ServiceSlide(
      tag: 'RESTAURANTS',
      problem: 'Un petit creux, mais pas envie de sortir ?',
      solution: 'Commandez vos plats préférés, ils arrivent chauds jusqu’à votre porte.',
      cta: 'Voir les restaurants',
      route: '/client/restaurants',
      photo: 'restaurants',
      icon: Ico3D.food,
    ),
    ServiceSlide(
      tag: 'BOUTIQUES',
      problem: 'Envie de vous faire plaisir ?',
      solution: 'Vêtements, chaussures, accessoires : choisissez en ligne, on vous livre.',
      cta: 'Découvrir les boutiques',
      route: '/client/shops',
      photo: 'boutiques',
      icon: Ico3D.bags,
    ),
    ServiceSlide(
      tag: 'VOYAGES',
      problem: 'Un voyage en car à prévoir ?',
      solution: 'Comparez les compagnies, réservez et payez votre billet sans faire la queue.',
      cta: 'Réserver un billet',
      route: '/client/voyages',
      photo: 'voyages',
      icon: Ico3D.map,
    ),
    ServiceSlide(
      tag: 'GAZ ET CARBURANT',
      problem: 'Bouteille de gaz vide ?',
      solution: 'Trouvez le point de vente le plus proche, ou faites-vous livrer.',
      cta: 'Trouver du gaz',
      route: '/client/gas',
      photo: 'gaz',
      icon: Ico3D.pin,
    ),
    ServiceSlide(
      tag: 'COURSES ET TRAJETS',
      problem: 'Une course à faire, un trajet à effectuer ?',
      solution: 'Un livreur fait vos achats, ou un chauffeur vous emmène où vous voulez.',
      cta: 'Faire une course',
      route: '/client/errand',
      photo: 'course',
      icon: Ico3D.taxi,
    ),
  ];
}

/// Bandeau défilant qui présente les services : situation, solution, bouton. Défile seul, ou au doigt.
class ServiceSlider extends StatefulWidget {
  const ServiceSlider({super.key, required this.onOpen, this.slides = ServiceSlide.all});
  final void Function(String route) onOpen;
  final List<ServiceSlide> slides;

  @override
  State<ServiceSlider> createState() => _ServiceSliderState();
}

class _ServiceSliderState extends State<ServiceSlider> {
  final _page = PageController();
  Timer? _timer;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_page.hasClients) return;
      _page.animateToPage((_i + 1) % widget.slides.length, duration: const Duration(milliseconds: 550), curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(
          height: 184,
          child: Listener(
            onPointerDown: (_) => _timer?.cancel(),
            onPointerUp: (_) => _start(),
            child: PageView.builder(
              controller: _page,
              itemCount: widget.slides.length,
              onPageChanged: (v) => setState(() => _i = v),
              itemBuilder: (_, i) => _SlideCard(slide: widget.slides[i], onTap: () => widget.onOpen(widget.slides[i].route)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var d = 0; d < widget.slides.length; d++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: d == _i ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(color: d == _i ? AppColors.primary : AppColors.line, borderRadius: BorderRadius.circular(3)),
            ),
        ]),
      ]);
}

class _SlideCard extends StatelessWidget {
  const _SlideCard({required this.slide, required this.onTap});
  final ServiceSlide slide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        scale: 0.985,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
          decoration: BoxDecoration(color: AppColors.backdrop, borderRadius: BorderRadius.circular(24)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(slide.tag, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.primaryDark)),
                const SizedBox(height: 6),
                Text(slide.problem, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.3)),
                const SizedBox(height: 4),
                Text(slide.solution, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, height: 1.3, color: AppColors.textMuted)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(slide.cta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
                  ]),
                ),
              ]),
            ),
            const SizedBox(width: 10),
            ServicePhoto(slide.photo, fallback: slide.icon, size: 104),
          ]),
        ),
      );
}
