import 'dart:convert';
import 'dart:typed_data';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<void> exportTextFile(String filename, String content, {String mimeType = 'text/csv'}) async {
  final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(content)];
  final blob = web.Blob([Uint8List.fromList(bytes).toJS].toJS, web.BlobPropertyBag(type: '$mimeType;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
