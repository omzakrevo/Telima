import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:telima/widgets/map_widgets.dart';

void main() {
  test('départ = arrivée : pas de cadrage « boîte » (zoom infini)', () {
    const p = LatLng(12.37, -1.52);
    final o = fitOptions([p, p]);
    expect(o.initialCameraFit, isNull);
    expect(o.initialCenter.latitude, closeTo(12.37, 1e-9));
  });

  test('points invalides ou (0,0) ignorés', () {
    expect(fitOptions([const LatLng(0, 0), const LatLng(0, 0)]).initialCameraFit, isNull);
    expect(fitOptions(const []).initialCameraFit, isNull);
  });

  test('deux points éloignés : cadrage plafonné', () {
    final o = fitOptions([const LatLng(12.37, -1.52), const LatLng(12.40, -1.48)]);
    expect(o.initialCameraFit, isNotNull);
  });
}
