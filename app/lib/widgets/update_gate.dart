import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ota_update/ota_update.dart';

import '../config/theme.dart';
import '../core/services/update_service.dart';
import '../providers/core_providers.dart';
import 'icon3d.dart';

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService(ref.watch(supabaseProvider)));

enum _Phase { idle, downloading, installing, failed }

/// Vérifie les mises à jour à l'ouverture (et au retour dans l'application) :
/// si l'administrateur a publié une version plus récente, elle se télécharge
/// automatiquement et Android propose aussitôt de l'installer.
/// Version obligatoire : l'application reste bloquée tant qu'elle n'est pas installée.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> with WidgetsBindingObserver {
  AppRelease? _release;
  _Phase _phase = _Phase.idle;
  int _percent = 0;
  String? _error;
  bool _dismissed = false;
  bool _checking = false;
  StreamSubscription<OtaEvent>? _sub;

  @override
  void initState() {
    super.initState();
    if (!UpdateService.supported) return;
    WidgetsBinding.instance.addObserver(this);
    // laisse l'application démarrer avant de vérifier
    Future.delayed(const Duration(seconds: 2), _check);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _phase != _Phase.downloading) _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final r = await ref.read(updateServiceProvider).checkForUpdate();
      if (!mounted) return;
      if (r == null) {
        if (_release != null) setState(() => _release = null);
        return;
      }
      final isNew = _release?.versionCode != r.versionCode;
      setState(() {
        _release = r;
        if (isNew) _dismissed = false;
      });
      // téléchargement automatique, sans action de l'utilisateur
      if (_phase == _Phase.idle || _phase == _Phase.failed || isNew) await _start();
    } catch (_) {
      // pas de réseau : nouvel essai au prochain retour dans l'application
    } finally {
      _checking = false;
    }
  }

  Future<void> _start() async {
    final r = _release;
    if (r == null) return;
    final url = await ref.read(updateServiceProvider).downloadUrlFor(r);
    if (url == null || !mounted) return;
    await _sub?.cancel();
    setState(() {
      _phase = _Phase.downloading;
      _percent = 0;
      _error = null;
    });
    _sub = ref.read(updateServiceProvider).install(url, r.versionName).listen(
      (e) {
        if (!mounted) return;
        setState(() {
          switch (e.status) {
            case OtaStatus.DOWNLOADING:
              _phase = _Phase.downloading;
              _percent = int.tryParse(e.value ?? '') ?? _percent;
            case OtaStatus.INSTALLING:
            case OtaStatus.INSTALLATION_DONE:
              _phase = _Phase.installing;
              _percent = 100;
            case OtaStatus.ALREADY_RUNNING_ERROR:
              _phase = _Phase.downloading;
            default:
              _phase = _Phase.failed;
              _error = e.value;
          }
        });
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _phase = _Phase.failed;
            _error = '$e';
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _release;
    final show = r != null && (r.mandatory || !_dismissed);
    return Stack(children: [
      widget.child,
      if (show && r.mandatory) Positioned.fill(child: _Blocking(release: r, card: _card(r))),
      if (show && !r.mandatory)
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(top: false, child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: _card(r)))),
        ),
    ]);
  }

  Widget _card(AppRelease r) {
    final (title, text) = switch (_phase) {
      _Phase.downloading => ('Mise à jour ${r.versionName}', 'Téléchargement en cours… $_percent %'),
      _Phase.installing => ('Mise à jour prête', 'Touchez « Mettre à jour » sur la fenêtre d’Android pour terminer.'),
      _Phase.failed => ('Mise à jour interrompue', _error == null ? 'Vérifiez votre connexion puis réessayez.' : 'Erreur : $_error'),
      _Phase.idle => ('Nouvelle version ${r.versionName}', r.notes ?? 'Une nouvelle version de Telima est disponible.'),
    };
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: const Color(0x552B6B48),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon3D(Ico3D.rocket, size: 38, shadow: false),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(text, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              ]),
            ),
            if (_phase == _Phase.failed || _phase == _Phase.installing)
              TextButton(onPressed: _start, child: Text(_phase == _Phase.failed ? 'Réessayer' : 'Relancer')),
            if (!r.mandatory && _phase != _Phase.downloading)
              // (pas d'infobulle : ce bandeau est au-dessus du navigateur de pages, hors de l'Overlay)
              IconButton(
                onPressed: () => setState(() => _dismissed = true),
                icon: const Icon(Icons.close_rounded, size: 20, semanticLabel: 'Plus tard'),
              ),
          ]),
          if (_phase == _Phase.downloading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: _percent == 0 ? null : _percent / 100, minHeight: 6),
            ),
          ],
          if (r.notes != null && _phase != _Phase.idle) ...[
            const SizedBox(height: 8),
            Text(r.notes!, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ],
        ]),
      ),
    );
  }
}

/// Écran bloquant pour une version obligatoire.
class _Blocking extends StatelessWidget {
  const _Blocking({required this.release, required this.card});
  final AppRelease release;
  final Widget card;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface.withValues(alpha: 0.97),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon3D(Ico3D.rocket, size: 96, float: true),
                  const SizedBox(height: 16),
                  Text('Telima ${release.versionName}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  const Text('Cette mise à jour est nécessaire pour continuer à utiliser l’application.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 20),
                  card,
                ]),
              ),
            ),
          ),
        ),
      );
}
