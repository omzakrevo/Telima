import 'package:flutter/material.dart';

import 'icon3d.dart';

/// Photo d'un service (assets/photos/nom.jpg). Si le fichier n'existe pas, l'illustration 3D de repli s'affiche.
class ServicePhoto extends StatelessWidget {
  const ServicePhoto(this.name, {super.key, required this.fallback, this.size = 96, this.radius = 20});
  final String name;
  final String fallback;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/photos/$name.jpg',
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * dpr).round().clamp(64, 800),
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => Center(child: Icon3D(fallback, size: size * 0.9, float: true)),
        ),
      ),
    );
  }
}
