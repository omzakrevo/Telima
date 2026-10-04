import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import '../core/services/pwa.dart';
import '../core/services/update_service.dart';
import '../providers/core_providers.dart';
import 'common.dart';
import 'icon3d.dart';
import 'update_gate.dart';

/// Adresse publique de la page de téléchargement (à partager sur les réseaux).
const kDownloadPage = 'https://telimatchi.com/telecharger';

/// Dernière version Android publiée par l'administrateur, avec le lien de son fichier APK.
final latestApkProvider = FutureProvider<({String version, String url})?>((ref) async {
  final svc = ref.watch(updateServiceProvider);
  final r = await svc.latest();
  if (r == null) return null;
  // Sur le web on ne connaît pas le processeur du téléphone : le fichier universel d'abord,
  // sinon celui des téléphones récents (la grande majorité).
  final path = r.universalPath ?? r.arm64Path ?? r.arm32Path;
  if (path == null) return null;
  final url = ref.watch(supabaseProvider).storage.from(UpdateService.bucket).getPublicUrl(path);
  return (version: r.versionName, url: url);
});

/// Carte « Obtenir l'application », visible uniquement sur la version web non installée :
/// télécharger l'application Android, ou installer la version web sur l'écran d'accueil.
class GetAppCard extends ConsumerStatefulWidget {
  const GetAppCard({super.key, this.compact = false});
  final bool compact;

  @override
  ConsumerState<GetAppCard> createState() => _GetAppCardState();
}

class _GetAppCardState extends ConsumerState<GetAppCard> {
  bool _installed = false;

  Future<void> _download() async {
    final apk = await ref.read(latestApkProvider.future).catchError((_) => null);
    if (apk == null) {
      if (mounted) showError(context, Exception('L’application Android n’est pas encore disponible au téléchargement.'));
      return;
    }
    await launchUrl(Uri.parse(apk.url), mode: LaunchMode.externalApplication);
  }

  Future<void> _install() async {
    if (pwaCanPrompt()) {
      final r = await pwaPrompt();
      if (r == 'accepted' && mounted) {
        setState(() => _installed = true);
        showSuccess(context, 'Telima est ajoutée à votre écran d’accueil.');
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (_) => _InstallHelp(platform: pwaPlatform()));
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || _installed || pwaIsStandalone()) return const SizedBox.shrink();
    final platform = pwaPlatform();
    final apk = ref.watch(latestApkProvider).value;
    final showApk = platform != 'ios';
    return Card(
      color: AppColors.mint,
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(widget.compact ? 14 : 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon3D(Ico3D.phone, size: widget.compact ? 40 : 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Telima sur votre téléphone', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  showApk
                      ? 'Installez l’application Android, ou ajoutez cette version web à votre écran d’accueil.'
                      : 'Ajoutez Telima à votre écran d’accueil pour l’ouvrir comme une application.',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.35),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            if (showApk)
              ElevatedButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.android_rounded),
                label: Text(apk == null ? 'Application Android' : 'Application Android · v${apk.version}'),
              ),
            OutlinedButton.icon(
              onPressed: _install,
              icon: const Icon(Icons.add_to_home_screen_rounded),
              label: const Text('Installer sur ce téléphone'),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Explications quand le navigateur ne propose pas l'installation automatique.
class _InstallHelp extends StatelessWidget {
  const _InstallHelp({required this.platform});
  final String platform;

  @override
  Widget build(BuildContext context) {
    final steps = switch (platform) {
      'ios' => const [
          'Ouvrez telimatchi.com dans Safari.',
          'Touchez le bouton Partager (carré avec une flèche vers le haut).',
          'Choisissez « Sur l’écran d’accueil », puis « Ajouter ».',
        ],
      'android' => const [
          'Ouvrez telimatchi.com dans Google Chrome.',
          'Touchez le menu ⋮ en haut à droite.',
          'Choisissez « Installer l’application » ou « Ajouter à l’écran d’accueil ».',
        ],
      _ => const [
          'Dans Chrome ou Edge, cliquez sur l’icône d’installation à droite de la barre d’adresse.',
          'Ou ouvrez le menu ⋮ puis « Installer Telima ».',
        ],
    };
    return AlertDialog(
      title: const Text('Installer Telima'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, s) in steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 12, backgroundColor: AppColors.primary, child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))),
              const SizedBox(width: 10),
              Expanded(child: Text(s, style: const TextStyle(height: 1.4))),
            ]),
          ),
        const SizedBox(height: 4),
        const Text('Telima s’ouvrira ensuite en plein écran, comme une application.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Compris'))],
    );
  }
}

/// Ouvre la carte « Obtenir l'application » dans une feuille en bas de l'écran.
Future<void> showGetAppSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [GetAppCard()]),
        ),
      ),
    );

/// Petit bouton « Obtenir l'appli » (version web seulement, masqué une fois installée).
class GetAppChip extends StatelessWidget {
  const GetAppChip({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || pwaIsStandalone()) return const SizedBox.shrink();
    return ActionChip(
      avatar: const Icon(Icons.download_rounded, size: 18, color: AppColors.primary),
      label: const Text('Obtenir l’appli', style: TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.line),
      onPressed: () => showGetAppSheet(context),
    );
  }
}
