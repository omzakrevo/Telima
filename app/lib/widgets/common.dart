import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../core/utils/errors.dart';
import '../core/utils/formatters.dart';
import '../data/models/enums.dart';
import '../providers/core_providers.dart';
import 'icon3d.dart';

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------
void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: AppColors.danger,
      content: Text(friendlyError(error)),
    ),
  );
}

void showSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Color(0xFF6EE7A8), size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirmer',
  bool danger = false,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Demande un texte (motif d'annulation, référence de paiement…).
Future<String?> promptDialog(
  BuildContext context, {
  required String title,
  String? label,
  String? initial,
  bool required = true,
  TextInputType? keyboard,
  int maxLines = 1,
}) {
  final ctrl = TextEditingController(text: initial);
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: ctrl,
          autofocus: true,
          keyboardType: keyboard,
          maxLines: maxLines,
          decoration: InputDecoration(labelText: label),
          validator: (v) => required && (v == null || v.trim().isEmpty)
              ? 'Obligatoire'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(ctx, ctrl.text.trim());
            }
          },
          child: const Text('Valider'),
        ),
      ],
    ),
  );
}

/// Exécute une action asynchrone avec indicateur bloquant et message d'erreur.
Future<T?> runWithLoader<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? success,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
    ),
  );
  try {
    final r = await action();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      if (success != null) showSuccess(context, success);
    }
    return r;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      showError(context, e);
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// États (chargement, vide, erreur)
// ---------------------------------------------------------------------------
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: CircularProgressIndicator(),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.action,
    this.image,
  });
  final IconData icon;
  final String? image;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          (image ?? _imageFor(icon)) != null
              ? Icon3D((image ?? _imageFor(icon))!, size: 72, float: true)
              : Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(color: AppColors.field, shape: BoxShape.circle),
                  child: Icon(icon, size: 30, color: AppColors.textMuted),
                ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 15),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

/// Illustration 3D associée aux icônes des états vides.
String? _imageFor(IconData icon) {
  final m = <int, String>{
    Icons.inbox_outlined.codePoint: Ico3D.package,
    Icons.inventory_2_outlined.codePoint: Ico3D.package,
    Icons.history.codePoint: Ico3D.receipt,
    Icons.receipt_long_outlined.codePoint: Ico3D.receipt,
    Icons.notifications_none.codePoint: Ico3D.bell,
    Icons.chat_bubble_outline.codePoint: Ico3D.chat,
    Icons.payments_outlined.codePoint: Ico3D.moneyBag,
    Icons.call_made.codePoint: Ico3D.moneyBag,
    Icons.delivery_dining.codePoint: Ico3D.scooter,
    Icons.map_outlined.codePoint: Ico3D.map,
    Icons.people_outline.codePoint: Ico3D.people,
    Icons.contacts_outlined.codePoint: Ico3D.people,
    Icons.star_outline.codePoint: Ico3D.star,
    Icons.support_agent.codePoint: Ico3D.headphone,
    Icons.search_off.codePoint: Ico3D.clipboard,
    Icons.history_edu.codePoint: Ico3D.clipboard,
    Icons.lock_reset.codePoint: Ico3D.key,
  };
  return m[icon.codePoint];
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 48,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 12),
          Text(friendlyError(error), textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ],
      ),
    ),
  );
}

class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => value.when(
    data: builder,
    loading: () => const LoadingView(),
    error: (e, _) => ErrorView(error: e, onRetry: onRetry),
    skipLoadingOnRefresh: true,
  );
}

/// Bandeau affiché quand la connexion est coupée ou quand des opérations attendent le réseau.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider).value ?? true;
    final pending = ref.watch(pendingOpsProvider).value ?? 0;
    if (online && pending == 0) return const SizedBox.shrink();
    return Material(
      color: online ? AppColors.info : const Color(0xFF374151),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                online ? Icons.sync : Icons.cloud_off,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  online
                      ? 'Synchronisation de $pending opération(s)…'
                      : 'Hors connexion — dernières données affichées${pending > 0 ? ' · $pending en attente' : ''}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Éléments d'interface
// ---------------------------------------------------------------------------
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.bold = false,
  });
  final String label;
  final String value;
  final IconData? icon;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
        ],
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 17 : 14,
            ),
          ),
        ),
      ],
    ),
  );
}

class BigActionButton extends StatelessWidget {
  const BigActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final bool loading;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 56,
    child: ElevatedButton(
      style: color == null
          ? null
          : ElevatedButton.styleFrom(backgroundColor: color),
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon), const SizedBox(width: 10)],
                Flexible(child: Text(label, textAlign: TextAlign.center)),
              ],
            ),
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.label});
  final DeliveryStatus status;
  /// Libellé adapté (trajet, course à faire) ; par défaut celui de l'étape.
  final String? label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: status.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label ?? status.label,
      style: TextStyle(
        color: status.color,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = AppColors.textMuted});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.url, this.radius = 24});
  final String name;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: AppColors.mint,
    foregroundImage: (url != null && url!.isNotEmpty)
        ? NetworkImage(url!)
        : null,
    child: Text(
      initials(name),
      style: TextStyle(
        color: AppColors.primaryDark,
        fontWeight: FontWeight.w700,
        fontSize: radius * 0.66,
      ),
    ),
  );
}

class RatingDisplay extends StatelessWidget {
  const RatingDisplay({
    super.key,
    required this.rating,
    this.count,
    this.size = 16,
  });
  final double rating;
  final int? count;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.star_rounded, color: AppColors.accent, size: size + 2),
      const SizedBox(width: 2),
      Text(
        rating == 0
            ? 'Nouveau'
            : rating.toStringAsFixed(1).replaceAll('.', ','),
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: size - 2),
      ),
      if (count != null && count! > 0)
        Text(
          ' ($count)',
          style: TextStyle(color: AppColors.textMuted, fontSize: size - 3),
        ),
    ],
  );
}

class StarInput extends StatelessWidget {
  const StarInput({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 1; i <= 5; i++)
        IconButton(
          iconSize: 44,
          onPressed: () => onChanged(i),
          icon: Icon(
            i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
            color: AppColors.accent,
          ),
          tooltip: '$i étoile${i > 1 ? 's' : ''}',
        ),
    ],
  );
}

/// Détail du prix : « Distance : 6,2 km / Livraison : 1 500 FCFA / Total : 1 500 FCFA »
class PriceSummary extends StatelessWidget {
  const PriceSummary({
    super.key,
    required this.distanceKm,
    required this.total,
    this.base,
    this.distancePrice,
    this.extras,
    this.zone,
    this.zoneName,
  });
  final double distanceKm;
  final int total;
  final int? base;
  final int? distancePrice;
  final int? extras;
  final int? zone;
  final String? zoneName;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          InfoRow(label: 'Distance', value: km(distanceKm), icon: Icons.route),
          InfoRow(
            label: 'Livraison',
            value: fcfa((base ?? 0) + (distancePrice ?? 0)),
            icon: Icons.delivery_dining,
          ),
          if ((extras ?? 0) > 0)
            InfoRow(
              label: 'Options (taille, fragile)',
              value: fcfa(extras),
              icon: Icons.add_box_outlined,
            ),
          if ((zone ?? 0) != 0)
            InfoRow(
              label: 'Zone${zoneName != null ? ' ($zoneName)' : ''}',
              value: fcfa(zone),
              icon: Icons.map_outlined,
            ),
          const Divider(height: 20),
          InfoRow(label: 'Total', value: fcfa(total), bold: true),
        ],
      ),
    ),
  );
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.image,
    this.color = AppColors.primary,
    this.onTap,
  });
  final String label;
  final String value;
  final IconData? icon;

  /// Illustration 3D (remplace l'icône).
  final String? image;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image != null)
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Icon3D(image!, size: 32, shadow: false),
              )
            else if (icon != null)
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
            const SizedBox(height: 14),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              maxLines: 2,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Sélecteur en grandes tuiles (catégorie, véhicule, paiement…).
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });
  final String label;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.mint : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.ink : AppColors.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 28,
              color: selected ? AppColors.ink : AppColors.textMuted,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.ink,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Contenu centré à largeur limitée (lisible sur tablette et Web).
class Constrained extends StatelessWidget {
  const Constrained({super.key, required this.child, this.maxWidth = 640});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    // heightFactor 1 : ne s'étire pas en hauteur (important dans une bottomNavigationBar)
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
