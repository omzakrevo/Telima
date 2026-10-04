import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> exportTextFile(String filename, String content, {String mimeType = 'text/csv'}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  // BOM UTF-8 pour une ouverture correcte des accents dans Excel
  await file.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(content)]);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mimeType)], subject: filename));
}
