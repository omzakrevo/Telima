import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../core/utils/validators.dart';
import '../data/models/config_models.dart';
import '../data/models/delivery.dart';
import '../providers/core_providers.dart';
import '../screens/client/location_picker_screen.dart';
import 'common.dart';
import 'map_widgets.dart';

/// Saisie d'un point (récupération ou destination) : GPS, carte, adresse écrite, contact, indications.
class DeliveryPointForm extends ConsumerStatefulWidget {
  const DeliveryPointForm({
    super.key,
    required this.point,
    required this.onChanged,
    required this.isPickup,
    this.savedAddresses = const [],
    this.contactRequired = true,
    this.showContact = true,
    this.mapTitle,
    this.addressLabel,
  });

  /// Point modifié sur place ; null tant qu'aucune position n'est choisie.
  final DeliveryPoint? point;
  final ValueChanged<DeliveryPoint> onChanged;
  final bool isPickup;
  final List<SavedAddress> savedAddresses;
  final bool contactRequired;
  /// Masque nom / téléphone (trajet : c'est le client lui-même).
  final bool showContact;
  final String? mapTitle;
  final String? addressLabel;

  @override
  ConsumerState<DeliveryPointForm> createState() => _DeliveryPointFormState();
}

class _DeliveryPointFormState extends ConsumerState<DeliveryPointForm> {
  late final _address = TextEditingController(text: widget.point?.address ?? '');
  late final _name = TextEditingController(text: widget.point?.contactName ?? '');
  late final _phone = TextEditingController(text: widget.point?.contactPhone ?? '');
  late final _instructions = TextEditingController(text: widget.point?.instructions ?? '');
  bool _locating = false;

  static const _quickPickup = ['Boutique à côté du marché', 'Appelez-moi en arrivant', 'Demandez au gardien'];
  static const _quickDropoff = ['Maison derrière la station', 'Appelez-moi en arrivant', 'Portail bleu', 'Laisser au voisin'];

  DeliveryPoint _current() =>
      widget.point ?? DeliveryPoint(address: '', lat: 0, lng: 0);

  void _emit({double? lat, double? lng}) {
    final p = _current().copy()
      ..address = _address.text.trim()
      ..contactName = _name.text.trim()
      ..contactPhone = _phone.text.trim()
      ..instructions = _instructions.text.trim();
    if (lat != null) p.lat = lat;
    if (lng != null) p.lng = lng;
    widget.onChanged(p);
  }

  bool get _hasPosition => widget.point != null && widget.point!.lat != 0;

  Future<void> _useGps() async {
    setState(() => _locating = true);
    try {
      final pos = await ref.read(locationServiceProvider).current();
      if (_address.text.trim().isEmpty) {
        final a = await ref.read(geocodingProvider).reverse(pos);
        if (a != null) _address.text = a;
      }
      _emit(lat: pos.latitude, lng: pos.longitude);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickOnMap() async {
    final res = await Navigator.of(context).push<PickedLocation>(MaterialPageRoute(
      builder: (_) => LocationPickerScreen(
        initial: _hasPosition ? widget.point!.latLng : null,
        title: widget.mapTitle ?? (widget.isPickup ? 'Point de récupération' : 'Destination'),
      ),
    ));
    if (res == null) return;
    if (_address.text.trim().isEmpty && res.address != null) _address.text = res.address!;
    _emit(lat: res.point.latitude, lng: res.point.longitude);
  }

  void _applySaved(SavedAddress a) {
    _address.text = a.address;
    _name.text = a.contactName ?? _name.text;
    _phone.text = a.contactPhone ?? _phone.text;
    _instructions.text = a.instructions ?? _instructions.text;
    _emit(lat: a.lat, lng: a.lng);
  }

  void _addQuick(String text) {
    final cur = _instructions.text.trim();
    _instructions.text = cur.isEmpty ? text : '$cur. $text';
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final quick = widget.isPickup ? _quickPickup : _quickDropoff;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.savedAddresses.isNotEmpty) ...[
        const Text('Adresses enregistrées', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final a in widget.savedAddresses)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(avatar: const Icon(Icons.bookmark, size: 18), label: Text(a.label), onPressed: () => _applySaved(a)),
              ),
          ]),
        ),
        const SizedBox(height: 12),
      ],
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _locating ? null : _useGps,
            icon: _locating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
            label: const Text('Ma position'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(onPressed: _pickOnMap, icon: const Icon(Icons.map_outlined), label: const Text('Sur la carte')),
        ),
      ]),
      const SizedBox(height: 10),
      if (_hasPosition)
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 130,
            child: IgnorePointer(
              child: FlutterMap(
                key: ValueKey('${widget.point!.lat},${widget.point!.lng}'),
                options: MapOptions(initialCenter: widget.point!.latLng, initialZoom: 16),
                children: [
                  osmTileLayer(),
                  MarkerLayer(markers: [
                    widget.isPickup ? pickupMarker(widget.point!.latLng) : dropoffMarker(widget.point!.latLng),
                  ]),
                ],
              ),
            ),
          ),
        )
      else
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: const Row(children: [
            Icon(Icons.info_outline, color: AppColors.accent),
            SizedBox(width: 8),
            Expanded(child: Text('Indiquez la position avec « Ma position » ou « Sur la carte ».')),
          ]),
        ),
      const SizedBox(height: 14),
      TextFormField(
        controller: _address,
        decoration: InputDecoration(
          labelText: widget.addressLabel ?? (widget.isPickup ? 'Adresse de récupération' : 'Adresse ou description du lieu'),
          prefixIcon: const Icon(Icons.home_outlined),
        ),
        maxLines: 2,
        minLines: 1,
        validator: (v) => Validators.required(v, 'L\'adresse'),
        onChanged: (_) => _emit(),
      ),
      if (widget.showContact) ...[
      const SizedBox(height: 12),
      TextFormField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: widget.isPickup ? 'Nom du contact' : 'Nom du destinataire',
          prefixIcon: const Icon(Icons.person_outline),
        ),
        validator: widget.contactRequired ? (v) => Validators.required(v, 'Le nom') : null,
        onChanged: (_) => _emit(),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
        decoration: InputDecoration(
          labelText: widget.isPickup ? 'Téléphone du contact' : 'Téléphone du destinataire',
          prefixIcon: const Icon(Icons.phone_outlined),
        ),
        validator: widget.contactRequired ? Validators.phone : Validators.optionalPhone,
        onChanged: (_) => _emit(),
      ),
      ],
      const SizedBox(height: 12),
      TextFormField(
        controller: _instructions,
        decoration: const InputDecoration(labelText: 'Indications (facultatif)', prefixIcon: Icon(Icons.chat_bubble_outline)),
        maxLines: 2,
        minLines: 1,
        onChanged: (_) => _emit(),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final q in quick) ActionChip(label: Text(q, style: const TextStyle(fontSize: 12)), onPressed: () => _addQuick(q)),
      ]),
    ]);
  }
}
