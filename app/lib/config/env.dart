/// Configuration injectée à la compilation :
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=xxx
/// ou  flutter run --dart-define-from-file=env.json
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Serveur de calcul d'itinéraire (OSRM). Le serveur public de démonstration convient aux tests ;
  /// en production, héberger son propre OSRM ou utiliser un fournisseur.
  static const osrmUrl = String.fromEnvironment('OSRM_URL', defaultValue: 'https://router.project-osrm.org');

  /// Tuiles OpenStreetMap.
  static const tileUrl = String.fromEnvironment('TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');

  /// Domaine technique utilisé pour convertir le téléphone en identifiant Supabase Auth.
  static const authEmailDomain = 'telima.app';

  /// Schéma PostgreSQL de Telima (permet de partager un projet Supabase avec d'autres applications).
  static const dbSchema = String.fromEnvironment('DB_SCHEMA', defaultValue: 'telima');

  /// Préfixe des compartiments de stockage (telima-avatars, telima-proofs…).
  static const bucketPrefix = String.fromEnvironment('BUCKET_PREFIX', defaultValue: 'telima-');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
