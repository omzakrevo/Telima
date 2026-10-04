import 'package:flutter/material.dart';
import '../../core/services/analytics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/utils/validators.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.asDriver = false});
  final bool asDriver;
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String? _cityId;
  XFile? _photo;
  late bool _asDriver = widget.asDriver;
  bool _loading = false;
  bool _obscure = true;

  Future<void> _pickPhoto() async {
    final f = await ref.read(storageServiceProvider).pickImage(maxWidth: 512);
    if (f != null) setState(() => _photo = f);
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_cityId == null) {
      showError(context, Exception('Choisissez votre ville'));
      return;
    }
    setState(() => _loading = true);
    try {
      final fullName = '${_first.text.trim()} ${_last.text.trim()}';
      await ref.read(authRepositoryProvider).signUp(
            phone: _phone.text,
            password: _password.text,
            fullName: fullName,
            cityId: _cityId,
            asDriver: _asDriver,
          );
      trackEvent('sign_up', {'method': _asDriver ? 'livreur' : 'client'});
      if (_photo != null) {
        try {
          final storage = ref.read(storageServiceProvider);
          final path = await storage.uploadXFile('avatars', _photo!);
          final profile = await ref
              .read(profileRepositoryProvider)
              .updateProfile(fullName: fullName, cityId: _cityId, avatarUrl: storage.publicUrl('avatars', path));
          ref.read(authControllerProvider.notifier).setProfile(profile);
        } catch (_) {
          // la photo est facultative : on n'empêche pas l'inscription
        }
      }
      await ref.read(authControllerProvider.notifier).refreshProfile();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cities = ref.watch(citiesProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, title: Text(_asDriver ? 'Devenir livreur' : 'Créer un compte')),
      body: Constrained(
        maxWidth: 520,
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Center(
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Stack(children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: const Color(0xFFE5E7EB),
                    child: _photo == null
                        ? const Icon(Icons.person, size: 44, color: Colors.white)
                        : ClipOval(
                            child: FutureBuilder(
                              future: _photo!.readAsBytes(),
                              builder: (_, s) =>
                                  s.hasData ? Image.memory(s.data!, width: 88, height: 88, fit: BoxFit.cover) : const SizedBox(),
                            ),
                          ),
                  ),
                  const Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(radius: 14, child: Icon(Icons.camera_alt, size: 16)),
                  ),
                ]),
              ),
            ),
            const Center(child: Padding(padding: EdgeInsets.only(top: 6), child: Text('Photo (facultative)'))),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _first,
                  decoration: const InputDecoration(labelText: 'Prénom'),
                  textCapitalization: TextCapitalization.words,
                  validator: Validators.name,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _last,
                  decoration: const InputDecoration(labelText: 'Nom'),
                  textCapitalization: TextCapitalization.words,
                  validator: Validators.name,
                ),
              ),
            ]),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
              decoration: const InputDecoration(
                labelText: 'Téléphone',
                prefixIcon: Icon(Icons.phone),
                hintText: '70 12 34 56',
                helperText: 'Votre numéro sert d\'identifiant de connexion',
              ),
              validator: Validators.phone,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: Validators.password,
            ),
            const SizedBox(height: 14),
            cities.when(
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _cityId,
                decoration: const InputDecoration(labelText: 'Ville', prefixIcon: Icon(Icons.location_city)),
                items: [for (final c in list) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) => setState(() => _cityId = v),
                validator: (v) => v == null ? 'Choisissez votre ville' : null,
              ),
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(citiesProvider)),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _asDriver,
              onChanged: (v) => setState(() => _asDriver = v),
              title: const Text('Je veux être livreur'),
              subtitle: const Text('Vous compléterez votre dossier (CNIB, véhicule) après l\'inscription.'),
            ),
            const SizedBox(height: 12),
            BigActionButton(label: 'Créer mon compte', onPressed: _submit, loading: _loading),
            const SizedBox(height: 12),
            TextButton(onPressed: () => context.pushReplacement('/login'), child: const Text('J\'ai déjà un compte')),
          ]),
        ),
      ),
    );
  }
}
