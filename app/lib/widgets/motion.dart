import 'dart:async';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../core/utils/formatters.dart';

/// Les animations sont coupées si l'utilisateur a demandé à réduire les mouvements.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Apparition en fondu + léger glissement vers le haut, avec délai (effet « cascade »).
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.offset = 18,
  });

  /// Délai en cascade : index × 60 ms.
  FadeSlideIn.staggered({Key? key, required Widget child, required int index, double offset = 18})
      : this(key: key, child: child, delay: Duration(milliseconds: 60 * index), offset: offset);

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _curve,
        child: widget.child,
        builder: (_, child) => Opacity(
          opacity: _curve.value,
          child: Transform.translate(offset: Offset(0, widget.offset * (1 - _curve.value)), child: child),
        ),
      );
}

/// Effet « bouton enfoncé » : léger rétrécissement au toucher.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap, this.scale = 0.96});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _hover = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: MouseRegion(
          cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _set(true),
            onTapUp: (_) => _set(false),
            onTapCancel: () => _set(false),
            onTap: widget.onTap,
            child: AnimatedSlide(
              offset: Offset(0, _hover && !_down ? -0.015 : 0),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: AnimatedScale(
                scale: _down ? widget.scale : (_hover ? 1.02 : 1),
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: widget.child,
              ),
            ),
          ),
        ),
      );
}

/// Léger mouvement de flottement continu (illustrations).
class Floating extends StatefulWidget {
  const Floating({super.key, required this.child, this.amplitude = 5, this.period = const Duration(milliseconds: 2600)});
  final Widget child;
  final double amplitude;
  final Duration period;

  @override
  State<Floating> createState() => _FloatingState();
}

class _FloatingState extends State<Floating> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, -widget.amplitude * Curves.easeInOut.transform(_c.value)),
          child: child,
        ),
      );
}

/// Halo qui pulse autour d'un élément (livreur en ligne, suivi en direct).
class PulseRing extends StatefulWidget {
  const PulseRing({super.key, required this.child, this.color = AppColors.primary, this.active = true, this.size = 52});
  final Widget child;
  final Color color;
  final bool active;
  final double size;

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  void _sync() {
    if (widget.active && !reduceMotion(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(PulseRing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.size,
        child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          if (widget.active)
            AnimatedBuilder(
              animation: _c,
              builder: (_, _) => Transform.scale(
                scale: 1 + 0.55 * _c.value,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.35 * (1 - _c.value)),
                  ),
                ),
              ),
            ),
          widget.child,
        ]),
      );
}

/// Montant en FCFA qui « défile » jusqu'à sa valeur.
class CountUpFcfa extends StatelessWidget {
  const CountUpFcfa({super.key, required this.value, this.style});
  final num value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(fcfa(v.round()), style: style),
      );
}

/// Nombre entier qui « défile » jusqu'à sa valeur.
class CountUpText extends StatelessWidget {
  const CountUpText({super.key, required this.value, this.style});
  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text('${v.round()}', style: style),
      );
}

/// Bandeau animé : un car roule sur une route, les pointillés défilent, des nuages dérivent (page Voyages).
class RoadBanner extends StatefulWidget {
  const RoadBanner({super.key, this.height = 64, this.busColor = Colors.white});
  final double height;
  final Color busColor;

  @override
  State<RoadBanner> createState() => _RoadBannerState();
}

class _RoadBannerState extends State<RoadBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 7));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!reduceMotion(context)) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            return AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value;
                final busX = -60 + (w + 120) * t;
                final bounce = (t * 40 % 2 < 1 ? 0.0 : 1.0); // léger tressautement
                return Stack(clipBehavior: Clip.hardEdge, children: [
                  Positioned(
                    left: (w * (1 - t) * 0.9) - 20,
                    top: 4,
                    child: Icon(Icons.cloud_rounded, size: 26, color: Colors.white.withValues(alpha: 0.22)),
                  ),
                  Positioned(
                    left: (w * (1 - ((t + 0.5) % 1)) * 0.9) - 20,
                    top: 16,
                    child: Icon(Icons.cloud_rounded, size: 18, color: Colors.white.withValues(alpha: 0.16)),
                  ),
                  Positioned(left: 0, right: 0, bottom: 0, height: 14, child: CustomPaint(painter: _RoadPainter(t))),
                  Positioned(left: busX, bottom: 8 + bounce, child: Icon(Icons.directions_bus_rounded, size: 46, color: widget.busColor)),
                ]);
              },
            );
          },
        ),
      );
}

class _RoadPainter extends CustomPainter {
  _RoadPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..strokeWidth = 2;
    const period = 26.0;
    final shift = -(t * period * 12) % period;
    for (var x = shift; x < size.width; x += period) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(x + 12, size.height / 2), dash);
    }
  }

  @override
  bool shouldRepaint(_RoadPainter old) => old.t != t;
}
