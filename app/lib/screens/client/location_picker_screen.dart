import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../config/theme.dart';
import '../../core/services/geocoding_service.dart';
import '../../core/utils/geo.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/map_widgets.dart';

final geocodingProvider = Provider<GeocodingService>((ref) => NominatimGeocodingService());

class PickedLocation {
  PickedLocation(this.point, this.address);
  final LatLng point;
  final String? address;
}

/// Sélection d'un point sur la carte : on déplace la carte sous le repère central.
class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({super.key, this.initial, this.title = 'Choisir sur la carte'});
  final LatLng? initial;
  final String title;

  @override
  ConsumerState<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  late LatLng _center = widget.initial ?? defaultCenter;
  List<PlaceResult> _results = [];
  Timer? _debounce;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) _goToMyPosition(silent: true);
  }

  Future<void> _goToMyPosition({bool silent = false}) async {
    try {
      final p = await ref.read(locationServiceProvider).current();
      if (!mounted) return;
      setState(() => _center = p);
      _map.move(p, 17);
    } catch (e) {
      if (!silent && mounted) showError(context, e);
    }
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () async {
      final r = await ref.read(geocodingProvider).search(q, near: _center);
      if (mounted) setState(() => _results = r);
    });
  }

  Future<void> _confirm() async {
    setState(() => _resolving = true);
    final address = await ref.read(geocodingProvider).reverse(_center);
    if (!mounted) return;
    Navigator.pop(context, PickedLocation(_center, address));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 16,
            onPositionChanged: (camera, hasGesture) => _center = camera.center,
          ),
          children: [osmTileLayer(), osmAttribution()],
        ),
        const IgnorePointer(
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Icon(Icons.location_on, size: 48, color: AppColors.danger),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Column(children: [
            Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(12),
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                decoration: const InputDecoration(
                  hintText: 'Rechercher un lieu, un quartier…',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            if (_results.isNotEmpty)
              Material(
                elevation: 3,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView(shrinkWrap: true, children: [
                    for (final r in _results)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(r.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          setState(() {
                            _center = r.point;
                            _results = [];
                          });
                          _map.move(r.point, 17);
                          FocusScope.of(context).unfocus();
                        },
                      ),
                  ]),
                ),
              ),
          ]),
        ),
        Positioned(
          right: 16,
          bottom: 110,
          child: FloatingActionButton(
            heroTag: 'mypos',
            backgroundColor: Colors.white,
            onPressed: _goToMyPosition,
            tooltip: 'Ma position',
            child: const Icon(Icons.my_location, color: AppColors.primary),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: BigActionButton(label: 'Valider ce point', icon: Icons.check, onPressed: _confirm, loading: _resolving),
        ),
      ]),
    );
  }
}
