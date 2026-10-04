import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/brand.dart';
import '../../widgets/icon3d.dart';
import '../../widgets/motion.dart';
import '../../widgets/nav.dart';

class _Slide {
  const _Slide(this.title, this.text, this.image, this.badges);
  final String title;
  final String text;
  final String image;
  final List<(String, String)> badges;
}

const _slides = [
  _Slide(
    'Rapide, sûr et\ntoujours à l’heure',
    'Un livreur proche récupère votre colis en quelques minutes et le dépose à destination.',
    Ico3D.scooter,
    [(Ico3D.stopwatch, '12 min'), (Ico3D.package, 'Colis pris')],
  ),
  _Slide(
    'Le prix affiché\navant de confirmer',
    'Pas de surprise : payez en espèces, à la livraison, par Orange Money ou Moov Money.',
    Ico3D.moneyBag,
    [(Ico3D.card, '1 500 FCFA'), (Ico3D.phone, 'Mobile Money')],
  ),
  _Slide(
    'Suivi en direct,\nremise sécurisée',
    'Suivez votre livreur sur la carte. Le colis n’est remis qu’avec votre code de livraison.',
    Ico3D.map,
    [(Ico3D.pin, 'En route'), (Ico3D.locked, 'Code 4 chiffres')],
  ),
];

/// Accueil en trois écrans (glisser ou « Continuer »), puis inscription / connexion.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});
  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _pages = PageController();
  int _page = 0;

  bool get _last => _page == _slides.length - 1;

  void _go(int i) => _pages.animateToPage(i, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(children: [
            // En-tête vert pâle à bord ondulé : logo + illustration qui glisse
            Expanded(
              flex: h < 700 ? 5 : 6,
              child: ClipPath(
                clipper: const WaveClipper(),
                child: Container(
                  color: AppColors.backdrop,
                  child: SafeArea(
                    bottom: false,
                    child: Column(children: [
                      const SizedBox(height: 18),
                      const BrandMark(size: 34, animate: true),
                      Expanded(
                        child: PageView.builder(
                          controller: _pages,
                          itemCount: _slides.length,
                          onPageChanged: (i) => setState(() => _page = i),
                          itemBuilder: (_, i) => _Illustration(slide: _slides[i]),
                        ),
                      ),
                      const SizedBox(height: 30),
                    ]),
                  ),
                ),
              ),
            ),
            // Indicateur de page
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 18),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < _slides.length; i++)
                  GestureDetector(
                    onTap: () => _go(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 26 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? AppColors.primary : AppColors.line,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
              ]),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a), child: child),
                    ),
                    child: Column(key: ValueKey(_page), children: [
                      Text(_slides[_page].title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.25, letterSpacing: -0.4)),
                      const SizedBox(height: 10),
                      Text(_slides[_page].text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.5)),
                    ]),
                  ),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _last ? _finalActions(context) : _nextActions(),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _nextActions() => Container(
        key: const ValueKey('next'),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Expanded(
            child: ElevatedButton(onPressed: () => _go(_page + 1), child: const Text('Continuer')),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: () => _go(_slides.length - 1),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Passer'),
              style: TextButton.styleFrom(foregroundColor: AppColors.ink, minimumSize: const Size(0, 52)),
            ),
          ),
        ]),
      );

  Widget _finalActions(BuildContext context) => Column(
        key: const ValueKey('final'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton(onPressed: () => context.push('/register'), child: const Text('Créer un compte')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => context.push('/login'), child: const Text('J’ai déjà un compte')),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(
              onPressed: () {
                ref.read(authControllerProvider.notifier).continueAsGuest();
                context.go('/visitor');
              },
              child: const Text('Voir les tarifs'),
            ),
            const Text('·', style: TextStyle(color: AppColors.textMuted)),
            TextButton(onPressed: () => context.push('/register?driver=1'), child: const Text('Devenir livreur')),
          ]),
        ],
      );
}

/// Illustration d'une page : grand médaillon + étiquettes flottantes.
class _Illustration extends StatelessWidget {
  const _Illustration({required this.slide});
  final _Slide slide;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final d = (c.maxHeight * 0.72).clamp(120.0, 230.0);
        return Center(
          child: SizedBox(
            width: d + 120,
            height: d + 30,
            child: Stack(alignment: Alignment.center, children: [
              // halo
              Container(
                width: d,
                height: d,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.55)),
              ),
              Floating(
                amplitude: 6,
                child: Container(
                  width: d * 0.72,
                  height: d * 0.72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.18), blurRadius: 30, offset: const Offset(0, 14))],
                  ),
                  alignment: Alignment.center,
                  child: Icon3D(slide.image, size: d * 0.5),
                ),
              ),
              Positioned(
                left: 0,
                top: d * 0.18,
                child: FadeSlideIn(delay: const Duration(milliseconds: 250), child: _Badge(image: slide.badges[0].$1, label: slide.badges[0].$2)),
              ),
              Positioned(
                right: 0,
                bottom: d * 0.12,
                child: FadeSlideIn(
                  delay: const Duration(milliseconds: 400),
                  child: _Badge(image: slide.badges[1].$1, label: slide.badges[1].$2, accent: true),
                ),
              ),
            ]),
          ),
        );
      });
}

class _Badge extends StatelessWidget {
  const _Badge({required this.image, required this.label, this.accent = false});
  final String image;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) => Floating(
        amplitude: 4,
        period: const Duration(milliseconds: 3200),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 7, 12, 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: accent ? AppColors.peach : AppColors.mint,
              child: Icon3D(image, size: 22, shadow: false),
            ),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}
