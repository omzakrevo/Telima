import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../data/models/delivery.dart';
import '../../data/models/restaurant.dart';
import '../../providers/auth_providers.dart';
import '../../providers/restaurant_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/point_form.dart';
import 'restaurant_widgets.dart';

String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

/// Créer son restaurant, ou modifier ses informations ([restaurantId] renseigné).
/// À la création, le lien à partager est généré tout de suite.
class RestaurantFormScreen extends ConsumerStatefulWidget {
  const RestaurantFormScreen({super.key, this.restaurantId});
  final String? restaurantId;

  @override
  ConsumerState<RestaurantFormScreen> createState() => _RestaurantFormScreenState();
}

class _RestaurantFormScreenState extends ConsumerState<RestaurantFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _cuisine = TextEditingController();
  final _description = TextEditingController();
  final _phone = TextEditingController();
  final _neighborhood = TextEditingController();
  final _hours = TextEditingController();
  final _radius = TextEditingController(text: '5');
  final _minOrder = TextEditingController(text: '0');
  final _prep = TextEditingController(text: '20');
  bool _pickup = true;
  bool _delivers = true;
  String? _logoPath;
  String? _coverPath;
  DeliveryPoint? _point = DeliveryPoint(address: '', lat: 0, lng: 0);
  bool _loading = false;
  bool _saving = false;
  bool _uploading = false;

  bool get _editing => widget.restaurantId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      _loading = true;
      _load();
    } else {
      _phone.text = displayPhone(ref.read(currentUserProvider)?.phone);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _cuisine, _description, _phone, _neighborhood, _hours, _radius, _minOrder, _prep]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(restaurantRepositoryProvider).mine(widget.restaurantId!);
      if (r == null) throw Exception('Restaurant introuvable');
      _name.text = r.name;
      _cuisine.text = r.cuisine ?? '';
      _description.text = r.description ?? '';
      _phone.text = displayPhone(r.phone);
      _neighborhood.text = r.neighborhood ?? '';
      _hours.text = r.hours ?? '';
      _radius.text = r.deliveryRadiusKm.toString().replaceAll(RegExp(r'\.0$'), '');
      _minOrder.text = '${r.minOrder}';
      _prep.text = '${r.prepMinutes}';
      _pickup = r.acceptsPickup;
      _delivers = r.delivers;
      _logoPath = r.logoPath;
      _coverPath = r.coverPath;
      _point = DeliveryPoint(address: r.address ?? '', lat: r.position.latitude, lng: r.position.longitude);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        context.pop();
      }
      return;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickPhoto({required bool logo}) async {
    setState(() => _uploading = true);
    try {
      final path = await ref.read(restaurantRepositoryProvider).pickAndUploadPhoto(maxWidth: logo ? 512 : 1280);
      if (path != null && mounted) {
        setState(() {
          if (logo) {
            _logoPath = path;
          } else {
            _coverPath = path;
          }
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_point == null || _point!.lat == 0 || _point!.lng == 0) {
      showError(context, Exception('Placez votre restaurant sur la carte (« Ma position » ou « Sur la carte »)'));
      return;
    }
    if (!_pickup && !_delivers) {
      showError(context, Exception('Choisissez au moins le retrait sur place ou la livraison'));
      return;
    }
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'description': _nullIfEmpty(_description.text),
      'cuisine': _nullIfEmpty(_cuisine.text),
      'phone': normalizePhone(_phone.text),
      'neighborhood': _nullIfEmpty(_neighborhood.text),
      'address': _nullIfEmpty(_point!.address),
      'lat': _point!.lat,
      'lng': _point!.lng,
      'opening_hours': _nullIfEmpty(_hours.text),
      'accepts_pickup': _pickup,
      'delivers': _delivers,
      'delivery_radius_km': double.tryParse(_radius.text.replaceAll(',', '.')) ?? 5,
      'min_order': int.tryParse(_minOrder.text.replaceAll(' ', '')) ?? 0,
      'prep_minutes': int.tryParse(_prep.text.replaceAll(' ', '')) ?? 20,
      'logo_path': _logoPath,
      'cover_path': _coverPath,
    };
    setState(() => _saving = true);
    try {
      final repo = ref.read(restaurantRepositoryProvider);
      if (_editing) {
        await repo.update(widget.restaurantId!, data);
        ref.invalidate(myRestaurantProvider(widget.restaurantId!));
        ref.invalidate(myRestaurantsProvider);
        if (mounted) {
          showSuccess(context, 'Informations enregistrées');
          context.pop();
        }
      } else {
        final r = await repo.create(data);
        ref.invalidate(myRestaurantsProvider);
        if (mounted) {
          showSuccess(context, 'Restaurant créé ! Ajoutez vos plats puis partagez votre lien.');
          context.pushReplacement('/restaurant/${r.id}');
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Modifier mon restaurant' : 'Créer mon restaurant')),
      body: _loading
          ? const LoadingView()
          : Form(
              key: _form,
              child: Constrained(
                maxWidth: 720,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  if (!_editing)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(14)),
                      child: const Row(children: [
                        Icon(Icons.link_rounded, color: AppColors.primaryDark),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('Un lien personnel est créé pour votre restaurant : vos clients l’ouvrent, voient le menu et commandent.',
                              style: TextStyle(height: 1.3)),
                        ),
                      ]),
                    ),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nom du restaurant'),
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Indiquez le nom' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cuisine,
                    decoration: const InputDecoration(labelText: 'Spécialités', hintText: 'Ex. Poulet braisé, Riz sauce, Brochettes'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: 'Présentation (facultatif)'),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Téléphone du restaurant'),
                    validator: Validators.phone,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(controller: _neighborhood, decoration: const InputDecoration(labelText: 'Quartier')),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _hours,
                    decoration: const InputDecoration(labelText: 'Horaires', hintText: 'Ex. 8h – 22h, tous les jours'),
                  ),
                  const SectionTitle('Photos'),
                  Row(children: [
                    Expanded(child: _PhotoPicker(label: 'Logo', path: _logoPath, busy: _uploading, onPick: () => _pickPhoto(logo: true), onClear: () => setState(() => _logoPath = null))),
                    const SizedBox(width: 12),
                    Expanded(child: _PhotoPicker(label: 'Couverture', path: _coverPath, busy: _uploading, onPick: () => _pickPhoto(logo: false), onClear: () => setState(() => _coverPath = null))),
                  ]),
                  const SectionTitle('Service'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Retrait sur place'),
                    subtitle: const Text('Le client vient chercher sa commande'),
                    value: _pickup,
                    onChanged: (v) => setState(() => _pickup = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Livraison à domicile'),
                    subtitle: const Text('Un livreur Telima apporte la commande'),
                    value: _delivers,
                    onChanged: (v) => setState(() => _delivers = v),
                  ),
                  if (_delivers)
                    TextFormField(
                      controller: _radius,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Rayon de livraison (km)'),
                      validator: (v) => Validators.number(v, min: 0.5),
                    ),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minOrder,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Commande minimum (FCFA)'),
                        validator: (v) => Validators.positiveInt(v, min: 0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _prep,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Préparation (min)'),
                        validator: (v) {
                          final n = int.tryParse((v ?? '').trim());
                          return n == null || n < 0 || n > 240 ? 'Entre 0 et 240' : null;
                        },
                      ),
                    ),
                  ]),
                  const SectionTitle('Où se trouve votre restaurant ?'),
                  DeliveryPointForm(
                    point: _point,
                    isPickup: true,
                    showContact: false,
                    contactRequired: false,
                    mapTitle: 'Position de votre restaurant',
                    addressLabel: 'Adresse ou repère',
                    onChanged: (p) => setState(() => _point = p),
                  ),
                  const SizedBox(height: 20),
                  BigActionButton(
                    label: _editing ? 'ENREGISTRER' : 'CRÉER MON RESTAURANT',
                    icon: Icons.check_rounded,
                    loading: _saving,
                    onPressed: _uploading ? null : _save,
                  ),
                ]),
              ),
            ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({required this.label, required this.path, required this.busy, required this.onPick, required this.onClear});
  final String label;
  final String? path;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: busy ? null : onPick,
          child: PhotoBox(url: restaurantPhotoUrl(path), size: double.infinity, height: 100, icon: Icons.add_a_photo_rounded),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (path != null) TextButton(onPressed: onClear, child: const Text('Retirer')),
        ]),
      ]);
}
