
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../core/services/update_service.dart';
import '../../core/utils/formatters.dart';
import '../../widgets/common.dart';
import '../../widgets/get_app_card.dart';
import '../../widgets/icon3d.dart';
import '../../widgets/update_gate.dart';

final _releasesProvider = FutureProvider.autoDispose<List<AppRelease>>((ref) => ref.watch(updateServiceProvider).all());

/// Mises à jour de l'application Android : l'administrateur dépose le(s) fichier(s) APK,
/// et chaque téléphone télécharge et installe la nouvelle version à son ouverture.
class AdminReleasesScreen extends ConsumerWidget {
  const AdminReleasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final releases = ref.watch(_releasesProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_releasesProvider),
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              const Icon3D(Ico3D.rocket, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Mises à jour automatiques', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text(
                    'Publiez ici chaque nouvelle version Android. À l’ouverture de l’application, les téléphones la '
                    'téléchargent seuls ; Android demande ensuite une seule confirmation pour l’installer. '
                    'Une version « obligatoire » bloque l’application tant qu’elle n’est pas installée.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final latest = releases.value?.isNotEmpty == true ? releases.value!.first.versionCode : 1;
                      final ok = await showDialog<bool>(context: context, builder: (_) => _PublishDialog(nextCode: latest + 1));
                      if (ok == true) ref.invalidate(_releasesProvider);
                    },
                    icon: const Icon(Icons.upload_rounded),
                    label: const Text('Publier une nouvelle version'),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            leading: const Icon3D(Ico3D.phone, size: 44),
            title: const Text('Lien public de téléchargement', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('$kDownloadPage\nÀ partager sur WhatsApp, TikTok et Facebook : la page propose toujours la dernière version publiée ici, '
                'et l’installation de la version web.'),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: 'Copier le lien',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: kDownloadPage));
                if (context.mounted) showSuccess(context, 'Lien copié');
              },
            ),
          ),
        ),
        const SectionTitle('Versions publiées'),
        AsyncBody<List<AppRelease>>(
          value: releases,
          onRetry: () => ref.invalidate(_releasesProvider),
          builder: (list) => list.isEmpty
              ? const EmptyState(icon: Icons.history_edu, message: 'Aucune version publiée pour le moment.')
              : Column(children: [
                  for (final (i, r) in list.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ReleaseCard(release: r, isLatest: i == 0 && r.isPublished),
                    ),
                ]),
        ),
      ]),
    );
  }
}

class _ReleaseCard extends ConsumerWidget {
  const _ReleaseCard({required this.release, required this.isLatest});
  final AppRelease release;
  final bool isLatest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = release;
    final files = [
      if (r.arm64Path != null) 'Récent (arm64)',
      if (r.arm32Path != null) 'Ancien (arm32)',
      if (r.universalPath != null) 'Universel',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Version ${r.versionName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Pill('n° ${r.versionCode}'),
            const SizedBox(width: 6),
            if (isLatest) const Pill('Distribuée', color: AppColors.primary),
            if (!r.isPublished) const Pill('Retirée', color: AppColors.danger),
            if (r.mandatory) ...[const SizedBox(width: 6), const Pill('Obligatoire', color: AppColors.accent)],
          ]),
          const SizedBox(height: 6),
          Text('${formatDateTime(r.createdAt)} · ${files.join(' · ')}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          if (r.notes != null) ...[const SizedBox(height: 8), Text(r.notes!)],
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            TextButton.icon(
              onPressed: () => runWithLoader(
                context,
                () async {
                  await ref.read(updateServiceProvider).setMandatory(r.id, !r.mandatory);
                  ref.invalidate(_releasesProvider);
                },
                success: r.mandatory ? 'La mise à jour redevient facultative' : 'La mise à jour est désormais obligatoire',
              ),
              icon: Icon(r.mandatory ? Icons.lock_open_rounded : Icons.lock_rounded, size: 18),
              label: Text(r.mandatory ? 'Rendre facultative' : 'Rendre obligatoire'),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: r.isPublished ? AppColors.danger : AppColors.primary),
              onPressed: () async {
                if (r.isPublished &&
                    !await confirmDialog(context,
                        title: 'Retirer la version ${r.versionName} ?',
                        message: 'Les téléphones qui ne l’ont pas encore installée ne la recevront plus.',
                        confirmLabel: 'Retirer',
                        danger: true)) {
                  return;
                }
                if (!context.mounted) return;
                await runWithLoader(context, () async {
                  await ref.read(updateServiceProvider).setPublished(r.id, !r.isPublished);
                  ref.invalidate(_releasesProvider);
                });
              },
              icon: Icon(r.isPublished ? Icons.unpublished_outlined : Icons.publish_rounded, size: 18),
              label: Text(r.isPublished ? 'Retirer' : 'Remettre en ligne'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _PublishDialog extends ConsumerStatefulWidget {
  const _PublishDialog({required this.nextCode});
  final int nextCode;
  @override
  ConsumerState<_PublishDialog> createState() => _PublishDialogState();
}

class _PublishDialogState extends ConsumerState<_PublishDialog> {
  final _form = GlobalKey<FormState>();
  late final _code = TextEditingController(text: '${widget.nextCode}');
  final _name = TextEditingController();
  final _notes = TextEditingController();
  bool _mandatory = false;
  final Map<String, PlatformFile> _files = {};
  bool _busy = false;
  String? _step;

  static const _variants = {
    'arm64': 'Téléphones récents (app-arm64-v8a-release.apk)',
    'arm32': 'Téléphones anciens (app-armeabi-v7a-release.apk)',
    'universal': 'Universel (app-release.apk, 50 Mo max.)',
  };

  Future<void> _pick(String variant) async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['apk']);
    if (picked.isEmpty) return;
    final f = picked.first;
    final size = await f.length() ?? 0;
    if (size > 50 * 1024 * 1024) {
      if (mounted) showError(context, Exception('Fichier trop lourd (${(size / 1048576).toStringAsFixed(1)} Mo, 50 Mo maximum). Utilisez les APK par type de téléphone.'));
      return;
    }
    setState(() => _files[variant] = f);
  }

  Future<void> _publish() async {
    if (!_form.currentState!.validate()) return;
    if (_files.isEmpty) {
      showError(context, Exception('Ajoutez au moins un fichier APK.'));
      return;
    }
    final code = int.parse(_code.text.trim());
    final svc = ref.read(updateServiceProvider);
    setState(() => _busy = true);
    try {
      final paths = <String, String>{};
      for (final e in _files.entries) {
        setState(() => _step = 'Envoi du fichier ${_variants[e.key]!.split(' (').first.toLowerCase()}…');
        final Uint8List bytes = await e.value.readAsBytes();
        paths[e.key] = await svc.uploadApk(code, e.key, bytes);
      }
      setState(() => _step = 'Publication…');
      await svc.publish(
        versionName: _name.text.trim(),
        versionCode: code,
        notes: _notes.text,
        mandatory: _mandatory,
        arm64Path: paths['arm64'],
        arm32Path: paths['arm32'],
        universalPath: paths['universal'],
      );
      if (mounted) {
        Navigator.pop(context, true);
        showSuccess(context, 'Version ${_name.text.trim()} publiée : les téléphones la recevront à l’ouverture.');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Publier une nouvelle version'),
        content: SizedBox(
          width: 480,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Version', hintText: '1.2.0'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Obligatoire' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 130,
                    child: TextFormField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Numéro (build)'),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        return n == null || n < 1 || n > 999 ? '1 à 999' : null;
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                const Text('Numéro = valeur après le « + » dans pubspec.yaml moins 2000 (ex. 1.4.0+2005 → 4), plus grand que la version précédente.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Nouveautés (affichées aux utilisateurs)'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _mandatory,
                  onChanged: (v) => setState(() => _mandatory = v),
                  title: const Text('Mise à jour obligatoire'),
                  subtitle: const Text('Bloque l’application tant que la version n’est pas installée'),
                ),
                const SizedBox(height: 4),
                for (final e in _variants.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pick(e.key),
                      icon: Icon(_files.containsKey(e.key) ? Icons.check_circle_rounded : Icons.attach_file_rounded,
                          color: _files.containsKey(e.key) ? AppColors.primary : null),
                      label: Text(_files.containsKey(e.key) ? _files[e.key]!.name : e.value,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                if (_busy && _step != null) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 6),
                  Text(_step!, style: const TextStyle(fontSize: 12.5)),
                ],
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: _busy ? null : _publish, child: const Text('Publier')),
        ],
      );
}
