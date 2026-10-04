import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'motion.dart';

// ---------------------------------------------------------------------------
// Logo Telima : un « t » dont la barre devient une flèche (le mouvement)
// et la jambe un trajet qui se termine par un point orange (l'arrivée).
// Dessiné en vectoriel (net à toutes les tailles) et animable.
// ---------------------------------------------------------------------------
class TelimaLogo extends StatefulWidget {
  const TelimaLogo({super.key, this.size = 40, this.animate = false, this.loop = false, this.inverted = false, this.idle = false});
  final double size;

  /// Après le tracé : la flèche « avance » et le point d'arrivée pulse en continu.
  final bool idle;

  /// Version claire (fond blanc, tracé vert) pour les fonds foncés.
  final bool inverted;

  /// Anime le tracé à l'apparition.
  final bool animate;

  /// Rejoue l'animation en boucle (écran de chargement).
  final bool loop;

  @override
  State<TelimaLogo> createState() => _TelimaLogoState();
}

class _TelimaLogoState extends State<TelimaLogo> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  late final AnimationController _idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void initState() {
    super.initState();
    if (widget.loop) {
      _c.repeat();
    } else if (widget.animate) {
      _c.forward().whenComplete(() {
        if (mounted && widget.idle && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) _idle.repeat();
      });
    } else {
      _c.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c
        ..stop()
        ..value = 1;
      _idle.stop();
    } else if (widget.idle && !widget.animate && !widget.loop && !_idle.isAnimating) {
      _idle.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Telima',
        image: true,
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_c, _idle]),
            builder: (_, _) => CustomPaint(
              painter: _LogoPainter(widget.loop ? _loopProgress(_c.value) : _c.value, inverted: widget.inverted, idle: _idle.value),
            ),
          ),
        ),
      );

  // En boucle : dessin (0 → 1), pause, puis effacement doux.
  double _loopProgress(double v) => v < 0.7 ? Curves.easeInOut.transform(v / 0.7) : 1;
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.t, {this.inverted = false, this.idle = 0});
  final double t;
  final bool inverted;

  /// Phase de l'animation continue (0 → 1).
  final double idle;

  double _seg(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    canvas.scale(s);

    // fond arrondi qui « pousse »
    final bg = Curves.easeOutBack.transform(_seg(0, 0.3));
    canvas.save();
    canvas.translate(50, 50);
    canvas.scale(0.6 + 0.4 * bg);
    canvas.translate(-50, -50);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 100, 100), const Radius.circular(28)),
      Paint()..color = (inverted ? Colors.white : AppColors.primary).withValues(alpha: bg.clamp(0.0, 1.0)),
    );
    canvas.restore();

    final stroke = Paint()
      ..color = inverted ? AppColors.primary : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // jambe → trajet
    final stem = Path()
      ..moveTo(42, 34)
      ..lineTo(42, 60)
      ..quadraticBezierTo(42, 74, 56, 74)
      ..lineTo(62, 74);
    _drawPartial(canvas, stem, stroke, Curves.easeInOut.transform(_seg(0.2, 0.6)));

    // barre → flèche (avance légèrement en continu)
    final nudge = math.sin(idle * 2 * math.pi).clamp(0.0, 1.0) * 3.5;
    canvas.save();
    canvas.translate(nudge, 0);
    final bar = Path()
      ..moveTo(24, 34)
      ..lineTo(66, 34);
    _drawPartial(canvas, bar, stroke, Curves.easeOut.transform(_seg(0.35, 0.65)));
    final head = Path()
      ..moveTo(58, 23)
      ..lineTo(71, 34)
      ..lineTo(58, 45);
    _drawPartial(canvas, head, stroke, Curves.easeOut.transform(_seg(0.55, 0.8)));
    canvas.restore();

    // point d'arrivée qui « rebondit »
    final dot = Curves.elasticOut.transform(_seg(0.7, 1));
    if (dot > 0) {
      final phase = (idle * 2) % 1;
      if (idle > 0) {
        // onde qui s'élargit autour du point (« arrivée »)
        canvas.drawCircle(const Offset(78, 74), 7.5 + 9 * phase,
            Paint()..color = AppColors.accent.withValues(alpha: 0.35 * (1 - phase)));
      }
      final pulse = 1 + 0.12 * math.sin(idle * 4 * math.pi).abs();
      canvas.drawCircle(const Offset(78, 74), 7.5 * dot * pulse, Paint()..color = AppColors.accent);
    }
  }

  void _drawPartial(Canvas canvas, Path path, Paint paint, double p) {
    if (p <= 0) return;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * p), paint);
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.t != t || old.inverted != inverted || old.idle != idle;
}

/// Logo + nom (« telima »), avec badge optionnel (rôle).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 34, this.badge, this.animate = false, this.color});
  final double size;
  final Color? color;
  final String? badge;
  final bool animate;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        TelimaLogo(size: size, animate: animate, idle: animate, inverted: color == Colors.white),
        SizedBox(width: size * 0.28),
        Text('telima', style: TextStyle(fontSize: size * 0.66, fontWeight: FontWeight.w800, letterSpacing: -0.9, height: 1, color: color)),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(20)),
            child: Text(badge!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
          ),
        ],
      ]);
}

/// Tuile pastel cliquable (raccourcis façon « cartes Pinterest »), avec effet d'enfoncement.
class PastelTile extends StatelessWidget {
  const PastelTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.caption,
    this.height = 132,
  });
  final IconData icon;
  final String label;
  final String? caption;
  final Color color;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: height,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: AppColors.ink),
            ),
            const Spacer(),
            Row(children: [
              Expanded(child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2))),
              Transform.rotate(angle: -math.pi / 4, child: const Icon(Icons.arrow_forward_rounded, size: 18)),
            ]),
            if (caption != null)
              Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ]),
        ),
      );
}
