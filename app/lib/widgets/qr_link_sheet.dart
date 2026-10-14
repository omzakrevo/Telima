import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../config/theme.dart';
import '../core/services/file_export.dart';
import 'common.dart';

/// Nom de fichier sûr à partir du lien (« chez-awa » → « telima-qr-chez-awa.png »).
String qrFileName(String slug) =>
    'telima-qr-${slug.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '')}.png';

/// Image PNG du QR code (fond blanc, marge blanche, 1024 px), prête à imprimer ou à envoyer.
Future<List<int>> renderQrPng(String link, {double size = 1024}) async {
  const margin = 0.08; // proportion de marge blanche autour du code
  final inner = size * (1 - 2 * margin);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size, size),
    Paint()..color = Colors.white,
  );
  canvas.translate(size * margin, size * margin);
  QrPainter(
    data: link,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Colors.black,
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Colors.black,
    ),
  ).paint(canvas, Size(inner, inner));
  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw Exception('Création du QR code impossible');
  return data.buffer.asUint8List();
}

/// Feuille « QR code » : montre le code du lien d'un commerce, à télécharger ou à partager.
/// Utilisée par le commerçant (pour l'imprimer, l'afficher) et par le client (pour le garder ou l'envoyer).
Future<void> showQrLinkSheet(
  BuildContext context, {
  required String title,
  required String link,
  required String slug,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _QrLinkSheet(title: title, link: link, slug: slug),
  );
}

class _QrLinkSheet extends StatefulWidget {
  const _QrLinkSheet({
    required this.title,
    required this.link,
    required this.slug,
  });
  final String title;
  final String link;
  final String slug;

  @override
  State<_QrLinkSheet> createState() => _QrLinkSheetState();
}

class _QrLinkSheetState extends State<_QrLinkSheet> {
  bool _busy = false;

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final png = await renderQrPng(widget.link);
      await exportBytesFile(qrFileName(widget.slug), png);
      if (mounted) showSuccess(context, 'QR code prêt');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = (MediaQuery.sizeOf(context).width - 96).clamp(180.0, 320.0);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Scannez ce code pour ouvrir la page et commander',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: QrImageView(
                data: widget.link,
                size: size,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
                semanticsLabel: 'QR code de ${widget.title}',
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              widget.link,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _download,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: const Text('Télécharger le QR code'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
