import 'package:flutter/material.dart';

/// Identité visuelle d'une compagnie : couleur, logo et photos embarqués dans l'application (dossier assets/voyages/{lien}/).
/// Pour une compagnie sans visuel, l'écran affiche un dégradé à sa couleur avec ses initiales.
class CompanyBrand {
  const CompanyBrand({required this.color, this.logo, this.logoBg = Colors.white, this.logoAspect = 2, this.photos = const [], this.tagline});
  final Color color;

  /// Couleur de fond du logo et sa proportion (largeur / hauteur) : le cadre épouse le logo, sans espace vide.
  final Color logoBg;
  final double logoAspect;
  final String? logo;
  final List<String> photos;
  final String? tagline;

  bool get hasPhotos => photos.isNotEmpty;
}

const _brands = <String, CompanyBrand>{
  'rahimo-transport': CompanyBrand(
    logoBg: Color(0xFFE9F8FD),
    logoAspect: 1.96,
    color: Color(0xFFD62828),
    logo: 'assets/voyages/rahimo-transport/logo.jpg',
    photos: ['assets/voyages/rahimo-transport/1.jpg', 'assets/voyages/rahimo-transport/2.jpg'],
    tagline: 'Le plaisir de prendre la route',
  ),
  'elitis-express': CompanyBrand(
    logoBg: Color(0xFF67380C),
    logoAspect: 2.32,
    color: Color(0xFF8A4B14),
    logo: 'assets/voyages/elitis-express/logo.jpg',
    photos: ['assets/voyages/elitis-express/1.jpg'],
    tagline: 'La passion du voyage',
  ),
  'tsr-express': CompanyBrand(
    logoBg: Color(0xFFE1F2FD),
    logoAspect: 2.6,
    color: Color(0xFF1B7A3D),
    logo: 'assets/voyages/tsr-express/logo.jpg',
    photos: ['assets/voyages/tsr-express/1.jpg', 'assets/voyages/tsr-express/2.jpg'],
    tagline: 'Le plaisir de voyager',
  ),
  'rakieta-transport': CompanyBrand(
    logoBg: Color(0xFFF1FBFC),
    logoAspect: 2.19,
    color: Color(0xFF1F4FA8),
    logo: 'assets/voyages/rakieta-transport/logo.jpg',
    photos: ['assets/voyages/rakieta-transport/1.jpg'],
    tagline: 'Modernité · Ponctualité · Confort',
  ),
  'staf': CompanyBrand(
    logoBg: Color(0xFFF6F9F7),
    logoAspect: 3.68,
    color: Color(0xFF1D3B8B),
    logo: 'assets/voyages/staf/logo.jpg',
    photos: ['assets/voyages/staf/1.jpg'],
    tagline: 'Votre confort, notre priorité',
  ),
  'saramaya-transport': CompanyBrand(color: Color(0xFF0F766E), tagline: 'Voyagez en toute confiance'),
};

const _fallbackColors = [Color(0xFF3D8B5F), Color(0xFF3F6FD8), Color(0xFFB45309), Color(0xFF7C3AED), Color(0xFF0E7490)];

/// Identité d'une compagnie à partir de son lien (slug) ; couleur stable pour les compagnies inconnues.
CompanyBrand companyBrand(String? slug) {
  final key = (slug ?? '').trim();
  final known = _brands[key];
  if (known != null) return known;
  final h = key.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
  return CompanyBrand(color: _fallbackColors[h % _fallbackColors.length]);
}

/// « Rahimo Transport » → « RT ».
String companyInitials(String? name) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.take(2).toString().toUpperCase();
  return (parts.first.characters.first + parts[1].characters.first).toUpperCase();
}
