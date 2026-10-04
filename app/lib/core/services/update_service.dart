import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/env.dart';

/// Version de l'application publiée par l'administrateur (table telima.app_releases).
class AppRelease {
  AppRelease(this.raw);
  final Map<String, dynamic> raw;

  String get id => raw['id'] as String;
  String get versionName => raw['version_name'] as String;
  int get versionCode => (raw['version_code'] as num).toInt();
  String? get notes => raw['notes'] as String?;
  bool get mandatory => raw['mandatory'] == true;
  bool get isPublished => raw['is_published'] == true;
  String? get arm64Path => raw['apk_arm64_path'] as String?;
  String? get arm32Path => raw['apk_arm32_path'] as String?;
  String? get universalPath => raw['apk_universal_path'] as String?;
  DateTime get createdAt => DateTime.parse(raw['created_at'] as String).toLocal();
}

/// Mises à jour de l'application Android sans passer par un magasin d'applications :
/// à l'ouverture, l'application compare son numéro de version à la dernière version publiée,
/// télécharge seule le bon fichier pour le téléphone puis lance l'installation.
class UpdateService {
  UpdateService(this._client);
  final SupabaseClient _client;

  static const bucket = '${Env.bucketPrefix}releases';

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Numéro de version de l'application installée (le numéro après le « + » du pubspec).
  /// Avec des APK par architecture, Android ajoute 1000 × architecture : on le retire.
  Future<int> currentBuild() async {
    final info = await PackageInfo.fromPlatform();
    return (int.tryParse(info.buildNumber) ?? 0) % 1000;
  }

  Future<String> currentVersionLabel() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version} (${(int.tryParse(info.buildNumber) ?? 0) % 1000})';
  }

  Future<AppRelease?> latest() async {
    final row = await _client
        .from('app_releases')
        .select()
        .eq('platform', 'android')
        .eq('is_published', true)
        .order('version_code', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : AppRelease(row);
  }

  /// Dernière version publiée si elle est plus récente que celle installée.
  Future<AppRelease?> checkForUpdate() async {
    if (!supported) return null;
    final release = await latest();
    if (release == null) return null;
    return release.versionCode > await currentBuild() ? release : null;
  }

  /// Fichier adapté au processeur du téléphone (le plus léger possible).
  Future<String?> downloadUrlFor(AppRelease r) async {
    String? path;
    try {
      final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
      if (abis.contains('arm64-v8a')) path = r.arm64Path;
      if (path == null && abis.contains('armeabi-v7a')) path = r.arm32Path;
    } catch (_) {
      // information indisponible : on prend le fichier universel
    }
    path ??= r.universalPath ?? r.arm64Path ?? r.arm32Path;
    if (path == null) return null;
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  /// Télécharge et lance l'installation (progression en pourcentage dans les évènements).
  Stream<OtaEvent> install(String url, String versionName) =>
      OtaUpdate().execute(url, destinationFilename: 'telima-$versionName.apk');

  // ---------------------------------------------------------------------------
  // Administration
  // ---------------------------------------------------------------------------
  Future<List<AppRelease>> all() async {
    final rows = await _client.from('app_releases').select().eq('platform', 'android').order('version_code', ascending: false);
    return [for (final r in rows) AppRelease(r)];
  }

  Future<String> uploadApk(int versionCode, String variant, Uint8List bytes) async {
    final path = 'android/$versionCode/telima-$variant.apk';
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'application/vnd.android.package-archive', upsert: true),
        );
    return path;
  }

  Future<void> publish({
    required String versionName,
    required int versionCode,
    String? notes,
    required bool mandatory,
    String? arm64Path,
    String? arm32Path,
    String? universalPath,
  }) async {
    await _client.from('app_releases').insert({
      'platform': 'android',
      'version_name': versionName,
      'version_code': versionCode,
      'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
      'mandatory': mandatory,
      'apk_arm64_path': arm64Path,
      'apk_arm32_path': arm32Path,
      'apk_universal_path': universalPath,
      'created_by': _client.auth.currentUser?.id,
    });
  }

  Future<void> setPublished(String id, bool published) =>
      _client.from('app_releases').update({'is_published': published}).eq('id', id);

  Future<void> setMandatory(String id, bool mandatory) =>
      _client.from('app_releases').update({'mandatory': mandatory}).eq('id', id);
}
