import 'package:flutter_test/flutter_test.dart';
import 'package:telima/widgets/qr_link_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('le nom du fichier QR est sûr', () {
    expect(qrFileName('chez-awa'), 'telima-qr-chez-awa.png');
    expect(qrFileName('../a b/é'), 'telima-qr-ab.png');
  });

  test('le QR code est une image PNG', () async {
    final png = await renderQrPng('https://telimatchi.com/b/boutique-awa', size: 256);
    expect(png.take(8).toList(), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    expect(png.length, greaterThan(500));
  });
}
