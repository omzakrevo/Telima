import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/env.dart';

/// Photos et documents : compression à la prise de vue (connexions lentes)
/// puis envoi dans un compartiment privé sous le dossier de l'utilisateur.
class StorageService {
  StorageService(this._client);

  /// Nom réel du compartiment (ex. « proofs » → « telima-proofs »).
  static String bucket(String name) => '${Env.bucketPrefix}$name';
  final SupabaseClient _client;
  final _picker = ImagePicker();

  /// Image réduite (1280 px max, qualité 70 %) : quelques centaines de Ko au lieu de plusieurs Mo.
  Future<XFile?> pickImage({bool camera = false, double maxWidth = 1280}) => _picker.pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: maxWidth,
        maxHeight: maxWidth,
        imageQuality: 70,
      );

  Future<String> uploadBytes(String bucket, Uint8List bytes, {String ext = 'jpg', String contentType = 'image/jpeg'}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Connexion requise');
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from(StorageService.bucket(bucket)).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return path;
  }

  Future<String> uploadXFile(String bucket, XFile file) async {
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();
    final isPng = name.endsWith('.png');
    final isPdf = name.endsWith('.pdf');
    return uploadBytes(bucket, bytes,
        ext: isPdf ? 'pdf' : (isPng ? 'png' : 'jpg'),
        contentType: isPdf ? 'application/pdf' : (isPng ? 'image/png' : 'image/jpeg'));
  }

  String publicUrl(String bucket, String path) => _client.storage.from(StorageService.bucket(bucket)).getPublicUrl(path);

  Future<String> signedUrl(String bucket, String path, {int seconds = 3600}) =>
      _client.storage.from(StorageService.bucket(bucket)).createSignedUrl(path, seconds);
}
