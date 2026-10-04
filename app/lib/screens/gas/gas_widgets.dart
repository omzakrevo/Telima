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
      child: Icon(isStation ? Icons.local_gas_station_rounded : Icons.local_fire_department_rounded, color: color, size: size * 0.58),
    );
  }
}

/// Ligne « produit : prix : disponibilité ».
String priceText(int price) => fcfa(price);
