import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/icon3d.dart';

final _pushStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final r = await ref.watch(supabaseProvider).rpc('admin_push_status');
  return Map<String, dynamic>.from(r as Map);
});

/// Branchement de Firebase Cloud Messaging : notifications reçues même application fermée.
class AdminPushScreen extends ConsumerWidget {
  const AdminPushScreen({super.key});

  Future<Map<String, dynamic>?> _pickJson(BuildContext context) async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['json']);
    if (picked.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(await picked.first.readAsBytes())) as Map);
    } catch (_) {
      if (context.mounted) showError(context, Exception('Ce fichier n’est pas un JSON valide.'));
      return null;
    }
  }

  Future<void> _upload(BuildContext context, WidgetRef ref, {required bool service}) async {
    final data = await _pickJson(context);
    if (data == null || !context.mounted) return;
    await runWithLoader(
      context,
      () async {
        await ref.read(supabaseProvider).rpc('admin_set_firebase', params: {
          'p_client': service ? null : data,
          'p_service': service ? data : null,
        });
        ref.invalidate(_pushStatusProvider);
      },
      success: service ? 'Clé serveur enregistrée' : 'Configuration de l’application enregistrée',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(_pushStatusProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_pushStatusProvider),
      child: ListView(padding: const EdgeInsets.all(20), children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Row(children: [
              Icon3D(Ico3D.bell, size: 56),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Les notifications s’affichent en bannière en haut de l’écran. Application ouverte ou en arrière-plan, '
                  'elles fonctionnent déjà. Pour les recevoir aussi application fermée, branchez Firebase (gratuit) '
                  'avec les deux fichiers ci-dessous.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
            ]),
          ),
        ),
        const SectionTitle('État'),
        AsyncBody<Map<String, dynamic>>(
          value: status,
          onRetry: () => ref.invalidate(_pushStatusProvider),
          builder: (s) => Card(
            child: Column(children: [
              _StatusRow('Configuration de l’application', s['client_configured'] == true,
                  detail: s['project_id'] == null ? null : 'Projet ${s['project_id']}'),
              _StatusRow('Clé serveur (compte de service)', s['server_configured'] == true),
              ListTile(
                leading: const Icon(Icons.smartphone_rounded),
                title: Text('${s['devices']} téléphone(s) enregistré(s)'),
                subtitle: Text('${s['users_with_device']} utilisateur(s)'),
              ),
            ]),
          ),
        ),
        const SectionTitle('Brancher Firebase'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text(
                '1. console.firebase.google.com → Créer un projet.\n'
                '2. Ajouter une application Android, nom du package : app.telima.telima → télécharger google-services.json.\n'
                '3. Paramètres du projet → Comptes de service → Générer une nouvelle clé privée (fichier .json).',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => _upload(context, ref, service: false),
                icon: const Icon(Icons.android_rounded),
                label: const Text('Déposer google-services.json'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _upload(context, ref, service: true),
                icon: const Icon(Icons.key_rounded),
                label: const Text('Déposer la clé du compte de service'),
              ),
              const SizedBox(height: 6),
              const Text('La clé privée reste sur le serveur : elle n’est jamais renvoyée aux téléphones.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () => runWithLoader(
            context,
            () => ref.read(supabaseProvider).rpc('send_test_notification'),
            success: 'Notification d’essai envoyée : fermez l’application pour vérifier.',
          ),
          icon: const Icon(Icons.notifications_active_rounded),
          label: const Text('M’envoyer une notification d’essai'),
        ),
      ]),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow(this.label, this.ok, {this.detail});
  final String label;
  final bool ok;
  final String? detail;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: ok ? AppColors.primary : AppColors.textMuted),
        title: Text(label),
        subtitle: Text(ok ? (detail ?? 'Enregistrée') : 'À déposer'),
      );
}
