import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'icon3d.dart';

class NavItem {
  const NavItem(this.icon, this.label, {this.selectedIcon});
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
}

/// Barre de navigation flottante sombre : l'onglet actif s'étire en pastille
/// (pastille verte + libellé), les autres restent des icônes.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({super.key, required this.items, required this.index, required this.onChanged});
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              padding: const EdgeInsets.all(6),
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [BoxShadow(color: AppColors.ink.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10))],
              ),
              child: Row(children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    flex: i == index ? 2 : 1,
                    child: _NavButton(item: items[i], selected: i == index, onTap: () => onChanged(i)),
                  ),
              ]),
            ),
          ),
        ),
      );
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: Tooltip(
          message: item.label,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.10) : Colors.transparent,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(selected ? (item.selectedIcon ?? item.icon) : item.icon,
                      color: selected ? Colors.white : Colors.white70, size: 21),
                ),
                if (selected)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, right: 10),
                      child: Text(item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
}

/// Bord inférieur en vague (en-têtes d'accueil, de profil).
class WaveClipper extends CustomClipper<Path> {
  const WaveClipper({this.depth = 26});
  final double depth;

  @override
  Path getClip(Size size) {
    final h = size.height, w = size.width;
    return Path()
      ..lineTo(0, h - depth)
      ..quadraticBezierTo(w * 0.25, h, w * 0.5, h - depth * 0.6)
      ..quadraticBezierTo(w * 0.78, h - depth * 1.6, w, h - depth * 0.7)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(WaveClipper old) => old.depth != depth;
}

/// Ligne de menu teintée avec chevron (profil, paramètres).
class MenuRow extends StatelessWidget {
  const MenuRow({super.key, required this.icon, required this.label, required this.onTap, this.color, this.trailing, this.image});
  final IconData icon;
  final String? image;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.white,
          elevation: 2,
          shadowColor: const Color(0x222B6B48),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(children: [
                image != null
                    ? Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(11)),
                        alignment: Alignment.center,
                        child: Icon3D(image!, size: 24, shadow: false),
                      )
                    : Icon(icon, size: 20, color: color ?? AppColors.primaryDark),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color ?? AppColors.ink))),
                trailing ?? Icon(Icons.chevron_right_rounded, color: color ?? AppColors.textMuted),
              ]),
            ),
          ),
        ),
      );
}
