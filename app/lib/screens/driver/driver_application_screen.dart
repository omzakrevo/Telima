import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/theme.dart';
import '../../core/utils/validators.dart';
import '../../data/models/enums.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/data_providers.dart';
import '../../widgets/common.dart';

/// Dossier livreur : CNIB/CNI, permis si nécessaire, véhicule.
class DriverApplicationScreen extends ConsumerStatefulWidget {
  const DriverApplicationScreen({super.key});
  @override
  ConsumerState<DriverApplicationScreen> createState() => _DriverApplicationScreenState();
}

class _DriverApplicationScreenState extends ConsumerState<DriverApplicationScreen> {
  final _form = GlobalKey<FormState>();
  final _idNumber = TextEditingController();
  final _license = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _color = TextEditingController();
  final _plate = TextEditingController();
  VehicleType _vehicle = VehicleType.moto;
  XFile? _idPhoto, _licensePhoto, _vehiclePhoto;
  bool _saving = false;
  bool _loaded = false;

  bool get _licenseRequired => _vehicle == VehicleType.voiture || _vehicle == VehicleType.utilitaire;

  void _prefill() {
    if (_loaded) return;
    final p = ref.read(myDriverProfileProvider).value;
    if (p == null) return;
    _loaded = true;
    _idNumber.text = p.idDocumentNumber ?? '';
    _license.text = p.licenseNumber ?? '';
    final v = p.activeVehicle;
    if (v != null) {
      _vehicle = v.type;
      _brand.text = v.brand ?? '';
      _model.text = v.model ?? '';
      _color.text = v.color ?? '';
      _plate.text = v.plateNumber ?? '';
    }
  }

  Future<XFile?> _pick() => ref.read(storageServiceProvider).pickImage(camera: false);

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final current = ref.read(myDriverProfileProvider).value;
    if (_idPhoto == null && current?.idDocumentPath == null) {
      showError(context, Exception('Ajoutez une photo de votre CNIB / CNI'));
      return;
    }
    setState(() => _saving = true);
    try {
      final storage = ref.read(storageServiceProvider);
      final idPath = _idPhoto == null ? null : await storage.uploadXFile('driver-documents', _idPhoto!);
      final licensePath = _licensePhoto == null ? null : await storage.uploadXFile('driver-documents', _licensePhoto!);
      final vehiclePath = _vehiclePhoto == null ? null : await storage.uploadXFile('vehicle-photos', _vehiclePhoto!);
      await ref.read(driverRepositoryProvider).submitApplication({
        'id_document_number': _idNumber.text.trim(),
        'id_document_path': idPath,
        'license_number': _license.text.trim(),
        'license_path': licensePath,
        'vehicle_type': _vehicle.name,
        'brand': _brand.text.trim(),
        'model': _model.text.trim(),
        'color': _color.text.trim(),
        'plate_number': _plate.text.trim(),
        'vehicle_photo_path': vehiclePath ?? current?.activeVehicle?.photoPath,
        'city_id': ref.read(currentUserProvider)?.cityId,
      });
      ref.invalidate(myDriverProfileProvider);
      await ref.read(authControllerProvider.notifier).refreshProfile();
      if (mounted) {
        showSuccess(context, 'Dossier envoyé ! Vous serez notifié après vérification.');
        context.go('/driver');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _photoButton(String label, XFile? file, bool alreadyUploaded, ValueChanged<XFile> onPicked) => OutlinedButton.icon(
        onPressed: () async {
          final f = await _pick();
          if (f != null) setState(() => onPicked(f));
        },
        icon: Icon(file != null || alreadyUploaded ? Icons.check_circle : Icons.upload_file,
            color: file != null || alreadyUploaded ? AppColors.primary : null),
        label: Text(file != null ? '$label ✓' : (alreadyUploaded ? '$label (déjà envoyée)' : label)),
      );

  @override
  Widget build(BuildContext context) {
    ref.watch(myDriverProfileProvider);
    _prefill();
    final current = ref.watch(myDriverProfileProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Dossier livreur')),
      body: Constrained(
        maxWidth: 560,
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Pièce d\'identité', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            TextFormField(
              controller: _idNumber,
              decoration: const InputDecoration(labelText: 'Numéro CNIB / CNI', prefixIcon: Icon(Icons.badge_outlined)),
              validator: (v) => Validators.required(v, 'Le numéro'),
            ),
            const SizedBox(height: 8),
            _photoButton('Photo de la CNIB / CNI', _idPhoto, current?.idDocumentPath != null, (f) => _idPhoto = f),
            const SizedBox(height: 24),
            const Text('Véhicule', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              children: [
                for (final v in VehicleType.values)
                  ChoiceTile(label: v.label, icon: v.icon, selected: _vehicle == v, onTap: () => setState(() => _vehicle = v)),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Marque'))),
              const SizedBox(width: 10),
              Expanded(child: TextFormField(controller: _model, decoration: const InputDecoration(labelText: 'Modèle'))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextFormField(controller: _color, decoration: const InputDecoration(labelText: 'Couleur'))),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Immatriculation'),
                  validator: (v) => _vehicle == VehicleType.moto || _vehicle == VehicleType.tricycle || (v ?? '').trim().isNotEmpty
                      ? null
                      : 'Obligatoire',
                ),
              ),
            ]),
            const SizedBox(height: 8),
            _photoButton('Photo du véhicule', _vehiclePhoto, current?.activeVehicle?.photoPath != null, (f) => _vehiclePhoto = f),
            const SizedBox(height: 24),
            Text('Permis de conduire${_licenseRequired ? '' : ' (facultatif pour moto/tricycle)'}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            TextFormField(
              controller: _license,
              decoration: const InputDecoration(labelText: 'Numéro du permis', prefixIcon: Icon(Icons.credit_card)),
              validator: (v) => _licenseRequired ? Validators.required(v, 'Le permis') : null,
            ),
            const SizedBox(height: 8),
            _photoButton('Photo du permis', _licensePhoto, current?.licensePath != null, (f) => _licensePhoto = f),
            const SizedBox(height: 28),
            BigActionButton(label: 'Envoyer mon dossier', icon: Icons.send, onPressed: _submit, loading: _saving),
          ]),
        ),
      ),
    );
  }
}
