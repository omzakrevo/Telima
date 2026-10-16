import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/validators.dart';
import '../../data/models/enums.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/icon3d.dart';
import '../../widgets/get_app_card.dart';
import '../../core/services/pwa.dart';
import '../../widgets/motion.dart';
import '../../widgets/nav.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final cities = ref.watch(citiesProvider).value ?? const [];
    if (user == null) return const LoadingView();
    final city = cities.where((c) => c.id == user.cityId).firstOrNull;

    final body = Constrained(
      maxWidth: 600,
      child: ListView(padding: EdgeInsets.zero, children: [
        // En-tête vert à bord ondulé avec avatar
        SizedBox(
          height: 230,
          child: Stack(alignment: Alignment.topCenter, children: [
            ClipPath(
              clipper: const WaveClipper(depth: 30),
              child: Container(
                height: 150,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.primary, AppColors.primaryDark],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
              ),
            ),
            Positioned(
              top: 80,
              child: FadeSlideIn(
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: UserAvatar(name: user.fullName, url: user.avatarUrl, radius: 40),
                  ),
                  const SizedBox(height: 8),
                  Text(user.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('${user.role.label} · ${displayPhone(user.phone)}${city != null ? ' · ${city.name}' : ''}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                ]),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(children: [
            for (final (i, row) in [
              MenuRow(icon: Icons.edit_outlined, label: 'Modifier mon profil', image: Ico3D.pencil, onTap: () => context.push('/profile/edit')),
              MenuRow(icon: Icons.lock_outline, label: 'Changer mon mot de passe', image: Ico3D.key, onTap: () => _changePassword(context, ref)),
              if (user.role == UserRole.client)
                MenuRow(icon: Icons.receipt_long_outlined, label: 'Historique des livraisons', image: Ico3D.receipt, onTap: () => context.push('/client/history')),
              if (user.role == UserRole.client)
                MenuRow(icon: Icons.storefront_outlined, label: 'Compte professionnel', image: Ico3D.store, onTap: () => context.push('/business')),
              if (user.role == UserRole.client)
                MenuRow(icon: Icons.delivery_dining_outlined, label: 'Devenir livreur', image: Ico3D.scooter, onTap: () => context.push('/driver/apply')),
              if (user.role == UserRole.client)
                MenuRow(icon: Icons.inventory_2_outlined, label: 'Vendre du gaz / ma station', image: Ico3D.store, onTap: () => context.push('/vendor')),
              MenuRow(icon: Icons.notifications_none, label: 'Notifications', image: Ico3D.bell, onTap: () => context.push('/notifications')),
              MenuRow(icon: Icons.support_agent, label: 'Contacter le support', image: Ico3D.headphone, onTap: () => context.push('/support')),
              if (kIsWeb && !pwaIsStandalone())
                MenuRow(icon: Icons.download, label: 'Obtenir l’application', image: Ico3D.phone, onTap: () => showGetAppSheet(context)),
            ].indexed)
              FadeSlideIn.staggered(index: i, offset: 10, child: row),
            const SizedBox(height: 10),
            MenuRow(
              icon: Icons.logout,
              label: 'Se déconnecter',
              image: Ico3D.door,
              color: AppColors.danger,
              trailing: const SizedBox.shrink(),
              onTap: () async {
                if (await confirmDialog(context, title: 'Se déconnecter ?', confirmLabel: 'Déconnexion')) {
                  await ref.read(authControllerProvider.notifier).signOut();
                }
              },
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
              icon: const Icon(Icons.person_off_outlined, size: 18),
              label: const Text('Désactiver mon compte'),
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: 'Désactiver votre compte ?',
                    message: 'Vous ne pourrez plus vous connecter. Pour le réactiver, contactez le support.',
                    confirmLabel: 'Désactiver',
                    danger: true);
                if (!ok || !context.mounted) return;
                await runWithLoader(context, () => ref.read(authRepositoryProvider).deactivateAccount());
              },
            ),
            const SizedBox(height: 6),
            const Text('Telima · version 1.0.0', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ),
      ]),
    );
    if (embedded) return body;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Mon profil', style: TextStyle(color: Colors.white)),
      ),
      body: body,
    );
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final pwd = await promptDialog(context, title: 'Nouveau mot de passe', label: '6 caractères minimum');
    if (pwd == null || !context.mounted) return;
    if (Validators.password(pwd) != null) {
      showError(context, Exception('Le mot de passe doit contenir au moins 6 caractères'));
      return;
    }
    await runWithLoader(context, () => ref.read(authRepositoryProvider).changePassword(pwd), success: 'Mot de passe modifié');
  }
}

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: ref.read(currentUserProvider)?.fullName);
  late String? _cityId = ref.read(currentUserProvider)?.cityId;
  String? _avatarUrl;
  bool _saving = false;

  Future<void> _pickAvatar() async {
    final storage = ref.read(storageServiceProvider);
    final f = await storage.pickImage(maxWidth: 512);
    if (f == null || !mounted) return;
    final path = await runWithLoader(context, () => storage.uploadXFile('avatars', f));
    if (path != null) setState(() => _avatarUrl = storage.publicUrl('avatars', path));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final p = await ref.read(profileRepositoryProvider).updateProfile(fullName: _name.text, cityId: _cityId, avatarUrl: _avatarUrl);
      ref.read(authControllerProvider.notifier).setProfile(p);
      if (mounted) {
        showSuccess(context, 'Profil mis à jour');
        context.pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final cities = ref.watch(citiesProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier mon profil')),
      body: Constrained(
        maxWidth: 520,
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(children: [
                  UserAvatar(name: user?.fullName ?? '', url: _avatarUrl ?? user?.avatarUrl, radius: 46),
                  const Positioned(right: 0, bottom: 0, child: CircleAvatar(radius: 15, child: Icon(Icons.camera_alt, size: 16))),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom et prénom'),
              textCapitalization: TextCapitalization.words,
              validator: Validators.name,
            ),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: displayPhone(user?.phone),
              enabled: false,
              decoration: const InputDecoration(labelText: 'Téléphone (identifiant)', helperText: 'Pour changer de numéro, contactez le support'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: cities.any((c) => c.id == _cityId) ? _cityId : null,
              decoration: const InputDecoration(labelText: 'Ville'),
              items: [for (final c in cities) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => setState(() => _cityId = v),
            ),
            const SizedBox(height: 24),
            BigActionButton(label: 'Enregistrer', onPressed: _save, loading: _saving),
          ]),
        ),
      ),
    );
  }
}
