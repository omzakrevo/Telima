import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/gas.dart';

/// Pastille de disponibilité avec l'âge de l'information.
class AvailabilityChip extends StatelessWidget {
  const AvailabilityChip(this.availability, {super.key, this.at, this.showAge = false, this.label});
  final Availability availability;
  final DateTime? at;
  final bool showAge;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final a = effectiveAvailability(availability, at);
    final old = a != availability || (availability != Availability.unknown && isStale(at));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: a.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(a.icon, size: 14, color: a.color),
        const SizedBox(width: 4),
        Text(
          label ?? (old && availability == Availability.available ? 'À confirmer' : a.label),
          style: TextStyle(color: a.color, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        if (showAge && availability != Availability.unknown) ...[
          const SizedBox(width: 6),
          Text(ageLabel(at), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ]),
    );
  }
}

class PlaceIcon extends StatelessWidget {
  const PlaceIcon({super.key, required this.isStation, this.size = 46});
  final bool isStation;
  final double size;
  @override
  Widget build(BuildContext context) {
    final color = isStation ? AppColors.info : AppColors.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(isStation ? Icons.directions_car : Icons.inventory_2, color: color, size: size * 0.58),
    );
  }
}

/// Ligne « produit : prix : disponibilité ».
String priceText(int price) => fcfa(price);

/// Étoiles + moyenne + nombre d'avis.
class RatingBadge extends StatelessWidget {
  const RatingBadge({super.key, required this.avg, required this.count, this.size = 14});
  final double? avg;
  final int count;
  final double size;
  @override
  Widget build(BuildContext context) {
    if (avg == null || count == 0) {
      return Text('Pas encore d’avis', style: TextStyle(color: AppColors.textMuted, fontSize: size - 1));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.star_rounded, size: size + 2, color: AppColors.accent),
      const SizedBox(width: 2),
      Text(avg!.toStringAsFixed(1).replaceAll('.', ','), style: TextStyle(fontWeight: FontWeight.w800, fontSize: size)),
      Text(' ($count)', style: TextStyle(color: AppColors.textMuted, fontSize: size - 1)),
    ]);
  }
}

class SmallTag extends StatelessWidget {
  const SmallTag(this.text, this.color, {super.key, this.icon});
  final String text;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 3)],
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800))),
        ]),
      );
}

/// File d'attente signalée sur place : « File moyenne · 15 pers. · ~23 min · il y a 5 min ».
class QueueChip extends StatelessWidget {
  const QueueChip({super.key, required this.place, this.full = false});
  final Place place;
  final bool full;

  static String label(String level) => switch (level) {
        'none' => 'Pas de file',
        'short' => 'File courte',
        'medium' => 'File moyenne',
        _ => 'Longue file',
      };
  static Color color(String level) => switch (level) {
        'none' || 'short' => AppColors.primaryDark,
        'medium' => AppColors.accent,
        _ => AppColors.danger,
      };

  @override
  Widget build(BuildContext context) {
    if (!place.hasQueue) return const SizedBox.shrink();
    final l = place.queueLevel!;
    final parts = [
      label(l),
      if (place.queuePeople != null) '${place.queuePeople} pers.',
      if (place.queueWaitMin != null && place.queueWaitMin! > 0) '~${place.queueWaitMin} min',
      if (full) ageLabel(place.queueAt),
    ];
    return SmallTag(parts.join(' · '), color(l), icon: Icons.groups_rounded);
  }
}
