import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../core/utils/validators.dart';
import '../../data/models/delivery.dart';
import '../../data/models/driver.dart';
import '../../data/models/enums.dart';
import '../../data/models/wallet.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/delivery_widgets.dart';

final _driversProvider = FutureProvider.autoDispose
    .family<List<DriverProfile>, DriverStatus?>((ref, status) => ref.watch(adminRepositoryProvider).drivers(status: status));

class AdminDriversScreen extends ConsumerStatefulWidget {
  const AdminDriversScreen({super.key});
  @override
  ConsumerState<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends ConsumerState<AdminDriversScreen> {
  DriverStatus? _status = DriverStatus.pending;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_driversProvider(_status));
    final isAdmin = ref.watch(currentUserProvider)?.role == UserRole.admin;
    return Column(children: [
      Material(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final s in [DriverStatus.pending, DriverStatus.approved, DriverStatus.suspended, DriverStatus.rejected, null])
              ChoiceChip(label: Text(s?.label ?? 'Tous'), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
            SizedBox(
              width: 260,
              child: TextField(
                decoration: const InputDecoration(labelText: 'Rechercher (nom, téléphone, plaque)', prefixIcon: Icon(Icons.search), isDense: true),
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              ),
            ),
            if (isAdmin)
              FilledButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(context: context, builder: (_) => const CreateUserDialog(role: UserRole.driver));
                  if (ok == true) ref.invalidate(_driversProvider);
                },
                icon: const Icon(Icons.person_add),
                label: const Text('Créer un livreur'),
              ),
          ]),
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(_driversProvider(_status)),
          child: AsyncBody<List<DriverProfile>>(
            value: async,
            onRetry: () => ref.invalidate(_driversProvider(_status)),
            builder: (all) {
              final list = all.where((d) {
                if (_query.isEmpty) return true;
                final hay = '${d.user?.fullName} ${d.user?.phone} ${d.activeVehicle?.plateNumber}'.toLowerCase();
                return hay.contains(_query);
              }).toList();
              if (list.isEmpty) return ListView(children: const [EmptyState(icon: Icons.delivery_dining, message: 'Aucun livreur')]);
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final d = list[i];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Badge(
                        backgroundColor: d.isOnline ? AppColors.primary : Colors.grey,
                        smallSize: 12,
                        child: UserAvatar(name: d.user?.fullName ?? '?', url: d.user?.avatarUrl),
                      ),
                      title: Text(d.user?.fullName ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        displayPhone(d.user?.phone),
                        d.activeVehicle?.label ?? 'Pas de véhicule',
                        if ((d.activeVehicle?.plateNumber ?? '').isNotEmpty) d.activeVehicle!.plateNumber!,
                        '${d.totalDeliveries} courses',
                      ].join(' · ')),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        RatingDisplay(rating: d.ratingAvg, count: d.ratingCount),
                        const SizedBox(width: 12),
                        Pill(d.status.label, color: _statusColor(d.status)),
                      ]),
                      onTap: () => context.push('/admin/drivers/${d.userId}').then((_) => ref.invalidate(_driversProvider)),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    ]);
  }
}

Color _statusColor(DriverStatus s) => switch (s) {
      DriverStatus.approved => AppColors.primary,
      DriverStatus.pending => AppColors.accent,
      _ => AppColors.danger,
    };

final _driverProvider = FutureProvider.autoDispose.family<DriverProfile?, String>((ref, id) => ref.watch(adminRepositoryProvider).driver(id));
final _driverCoursesProvider =
    FutureProvider.autoDispose.family<List<Delivery>, String>((ref, id) => ref.watch(adminRepositoryProvider).driverCourses(id));
final _driverRatingsProvider =
    FutureProvider.autoDispose.family<List<Rating>, String>((ref, id) => ref.watch(adminRepositoryProvider).driverRatings(id));
final _driverWalletProvider = FutureProvider.autoDispose.family<(Wallet?, List<WalletTransaction>), String>((ref, id) async {
  final repo = ref.watch(adminRepositoryProvider);
  final w = await repo.walletOf(id);
  return (w, w == null ? <WalletTransaction>[] : await repo.walletTransactions(w.id));
});

class AdminDriverDetailScreen extends ConsumerWidget {
  const AdminDriverDetailScreen({super.key, required this.driverId});
  final String driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_driverProvider(driverId));
    return AsyncBody<DriverProfile?>(
      value: async,
      onRetry: () => ref.invalidate(_driverProvider(driverId)),
      builder: (d) {
        if (d == null) return const EmptyState(icon: Icons.person_off, message: 'Livreur introuvable');
        return DefaultTabController(
          length: 4,
          child: Column(children: [
            _DriverHeader(driver: d),
            const Material(
              color: Colors.white,
              child: TabBar(isScrollable: true, tabs: [
                Tab(text: 'Dossier'),
                Tab(text: 'Courses'),
                Tab(text: 'Revenus & portefeuille'),
                Tab(text: 'Évaluations'),
              ]),
            ),
            Expanded(
              child: TabBarView(children: [
                _DocumentsTab(driver: d),
                _CoursesTab(driverId: driverId),
                _RevenueTab(driverId: driverId),
                _RatingsTab(driverId: driverId),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

class _DriverHeader extends ConsumerWidget {
  const _DriverHeader({required this.driver});
  final DriverProfile driver;

  Future<void> _setStatus(BuildContext context, WidgetRef ref, DriverStatus status) async {
    String? note;
    if (status != DriverStatus.approved) {
      note = await promptDialog(context, title: status == DriverStatus.suspended ? 'Motif de suspension' : 'Motif du refus', label: 'Motif');
      if (note == null) return;
    }
    if (!context.mounted) return;
    await runWithLoader(context, () => ref.read(adminRepositoryProvider).setDriverStatus(driver.userId, status, note: note),
        success: 'Statut mis à jour : ${status.label}');
    ref.invalidate(_driverProvider(driver.userId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = driver.user;
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(spacing: 20, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          UserAvatar(name: u?.fullName ?? '?', url: u?.avatarUrl, radius: 34),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(u?.fullName ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            Text(displayPhone(u?.phone)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: [
              Pill(driver.status.label, color: _statusColor(driver.status)),
              Pill(driver.isOnline ? 'En ligne' : 'Hors ligne', color: driver.isOnline ? AppColors.primary : AppColors.textMuted),
              RatingDisplay(rating: driver.ratingAvg, count: driver.ratingCount),
            ]),
            if ((driver.statusNote ?? '').isNotEmpty) Text('Note : ${driver.statusNote}', style: const TextStyle(color: AppColors.textMuted)),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (driver.status != DriverStatus.approved)
              FilledButton.icon(
                onPressed: () => _setStatus(context, ref, DriverStatus.approved),
                icon: const Icon(Icons.check),
                label: Text(driver.status == DriverStatus.pending ? 'Approuver' : 'Réactiver'),
              ),
            if (driver.status == DriverStatus.pending)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () => _setStatus(context, ref, DriverStatus.rejected),
                icon: const Icon(Icons.close),
                label: const Text('Refuser'),
              ),
            if (driver.status == DriverStatus.approved)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                onPressed: () => _setStatus(context, ref, DriverStatus.suspended),
                icon: const Icon(Icons.block),
                label: const Text('Suspendre'),
              ),
            if (u != null) OutlinedButton.icon(onPressed: () => callPhone(u.phone), icon: const Icon(Icons.call), label: const Text('Appeler')),
          ]),
        ]),
      ),
    );
  }
}

class _DocumentsTab extends ConsumerWidget {
  const _DocumentsTab({required this.driver});
  final DriverProfile driver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = driver.activeVehicle;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Wrap(spacing: 16, runSpacing: 16, children: [
        _DocCard(title: 'CNIB / CNI', number: driver.idDocumentNumber, bucket: 'driver-documents', path: driver.idDocumentPath),
        _DocCard(title: 'Permis de conduire', number: driver.licenseNumber, bucket: 'driver-documents', path: driver.licensePath),
        _DocCard(
          title: 'Véhicule',
          number: v == null ? 'Aucun véhicule' : '${v.label}${v.plateNumber != null ? ' · ${v.plateNumber}' : ''}',
          bucket: 'vehicle-photos',
          path: v?.photoPath,
        ),
      ]),
      const SizedBox(height: 16),
      InfoRow(label: 'Inscrit le', value: formatDate(driver.createdAt)),
      InfoRow(label: 'Dernière position', value: driver.lastLocationAt == null ? '—' : relativeTime(driver.lastLocationAt)),
      InfoRow(label: 'Courses terminées', value: '${driver.totalDeliveries}'),
    ]);
  }
}

class _DocCard extends ConsumerWidget {
  const _DocCard({required this.title, required this.number, required this.bucket, required this.path});
  final String title;
  final String? number;
  final String bucket;
  final String? path;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
        width: 300,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(number?.isNotEmpty == true ? number! : 'Non renseigné', style: const TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 10),
              if (path == null)
                const SizedBox(height: 160, child: Center(child: Text('Aucun fichier')))
              else
                FutureBuilder<String>(
                  future: ref.read(storageServiceProvider).signedUrl(bucket, path!, seconds: 600),
                  builder: (context, snap) => snap.hasData
                      ? GestureDetector(
                          onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(snap.data!)))),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(snap.data!, height: 160, width: double.infinity, fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const SizedBox(height: 160, child: Center(child: Text('Document (PDF ou illisible)')))),
                          ),
                        )
                      : const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
                ),
            ]),
          ),
        ),
      );
}

class _CoursesTab extends ConsumerWidget {
  const _CoursesTab({required this.driverId});
  final String driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncBody<List<Delivery>>(
        value: ref.watch(_driverCoursesProvider(driverId)),
        onRetry: () => ref.invalidate(_driverCoursesProvider(driverId)),
        builder: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.inbox_outlined, message: 'Aucune course')
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => DeliveryListTile(delivery: list[i], showEarning: true, onTap: () => context.push('/admin/orders/${list[i].id}')),
              ),
      );
}

class _RevenueTab extends ConsumerWidget {
  const _RevenueTab({required this.driverId});
  final String driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(_driverCoursesProvider(driverId)).value ?? const <Delivery>[];
    final wallet = ref.watch(_driverWalletProvider(driverId));
    final isAdmin = ref.watch(currentUserProvider)?.role == UserRole.admin;
    final done = courses.where((c) => c.status == DeliveryStatus.completed).toList();
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    int sum(Iterable<Delivery> l, int Function(Delivery) f) => l.fold(0, (a, b) => a + f(b));
    final month = done.where((c) => (c.completedAt ?? DateTime(2000)).isAfter(monthStart));

    return ListView(padding: const EdgeInsets.all(20), children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(width: 220, child: StatCard(label: 'Gains ce mois', value: fcfa(sum(month, (c) => c.driverEarning)), icon: Icons.calendar_month)),
        SizedBox(width: 220, child: StatCard(label: 'Gains au total', value: fcfa(sum(done, (c) => c.driverEarning)), icon: Icons.savings)),
        SizedBox(width: 220, child: StatCard(label: 'Commissions générées', value: fcfa(sum(done, (c) => c.commissionAmount)), icon: Icons.percent, color: AppColors.accent)),
        SizedBox(width: 220, child: StatCard(label: 'Courses terminées', value: '${done.length}', icon: Icons.check_circle)),
      ]),
      const SectionTitle('Portefeuille'),
      AsyncBody<(Wallet?, List<WalletTransaction>)>(
        value: wallet,
        onRetry: () => ref.invalidate(_driverWalletProvider(driverId)),
        builder: (data) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(
            child: ListTile(
              title: const Text('Solde'),
              subtitle: const Text('Négatif = commissions dues par le livreur'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(fcfa(data.$1?.balance ?? 0),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: (data.$1?.balance ?? 0) < 0 ? AppColors.danger : AppColors.primary)),
                if (isAdmin) ...[
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () async {
                      final res = await showDialog<(int, String)>(context: context, builder: (_) => const _AdjustDialog());
                      if (res == null || !context.mounted) return;
                      await runWithLoader(context, () => ref.read(adminRepositoryProvider).adjustWallet(driverId, res.$1, res.$2),
                          success: 'Portefeuille ajusté');
                      ref.invalidate(_driverWalletProvider(driverId));
                    },
                    child: const Text('Ajuster'),
                  ),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(children: [
              for (final t in data.$2)
                ListTile(
                  dense: true,
                  title: Text('${t.type.label} · ${t.description ?? ''}'),
                  subtitle: Text(formatDateTime(t.createdAt)),
                  trailing: Text('${t.amount > 0 ? '+' : ''}${fcfa(t.amount)}',
                      style: TextStyle(fontWeight: FontWeight.w800, color: t.amount > 0 ? AppColors.primary : AppColors.danger)),
                ),
              if (data.$2.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Aucune opération')),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog();
  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _credit = true;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ajuster le portefeuille'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: true, label: Text('Créditer')), ButtonSegment(value: false, label: Text('Débiter'))],
            selected: {_credit},
            onSelectionChanged: (s) => setState(() => _credit = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Montant (FCFA)'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: 'Motif (ex. paiement commissions en espèces)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(_amount.text);
              if (n == null || n <= 0 || _reason.text.trim().isEmpty) return;
              Navigator.pop(context, (_credit ? n : -n, _reason.text.trim()));
            },
            child: const Text('Valider'),
          ),
        ],
      );
}

class _RatingsTab extends ConsumerWidget {
  const _RatingsTab({required this.driverId});
  final String driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncBody<List<Rating>>(
        value: ref.watch(_driverRatingsProvider(driverId)),
        onRetry: () => ref.invalidate(_driverRatingsProvider(driverId)),
        builder: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.star_outline, message: 'Aucune évaluation')
            : ListView(padding: const EdgeInsets.all(16), children: [
                for (final r in list)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('${r.stars}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                        const Icon(Icons.star_rounded, color: AppColors.accent),
                      ]),
                      title: Text(r.comment ?? 'Sans commentaire'),
                      subtitle: Text(formatDateTime(r.createdAt)),
                      onTap: r.deliveryId == null ? null : () => context.push('/admin/orders/${r.deliveryId}'),
                    ),
                  ),
              ]),
      );
}

/// Création d'un compte par l'administrateur (client, livreur, opérateur, administrateur).
class CreateUserDialog extends ConsumerStatefulWidget {
  const CreateUserDialog({super.key, this.role = UserRole.client});
  final UserRole role;
  @override
  ConsumerState<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends ConsumerState<CreateUserDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _idNumber = TextEditingController();
  final _license = TextEditingController();
  final _plate = TextEditingController();
  late UserRole _role = widget.role;
  VehicleType _vehicle = VehicleType.moto;
  String? _cityId;
  bool _approve = true;
  bool _saving = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(adminRepositoryProvider).createUser(
            phone: _phone.text,
            fullName: _name.text.trim(),
            password: _password.text,
            role: _role,
            cityId: _cityId,
            driver: _role == UserRole.driver
                ? {
                    'vehicle_type': _vehicle.name,
                    'plate_number': _plate.text.trim(),
                    'id_document_number': _idNumber.text.trim(),
                    'license_number': _license.text.trim(),
                    'approve': _approve,
                  }
                : null,
          );
      if (mounted) {
        showSuccess(context, 'Compte créé. Communiquez le mot de passe à l\'utilisateur.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cities = ref.watch(citiesProvider).value ?? const [];
    return AlertDialog(
      title: const Text('Créer un compte'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<UserRole>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Rôle'),
                items: [for (final r in UserRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              const SizedBox(height: 10),
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nom et prénom'), validator: Validators.name),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Téléphone (identifiant)'),
                validator: Validators.phone,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Mot de passe provisoire'),
                validator: Validators.password,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _cityId,
                decoration: const InputDecoration(labelText: 'Ville'),
                items: [for (final c in cities) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) => setState(() => _cityId = v),
              ),
              if (_role == UserRole.driver) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<VehicleType>(
                  initialValue: _vehicle,
                  decoration: const InputDecoration(labelText: 'Véhicule'),
                  items: [for (final v in VehicleType.values) DropdownMenuItem(value: v, child: Text(v.label))],
                  onChanged: (v) => setState(() => _vehicle = v ?? _vehicle),
                ),
                const SizedBox(height: 10),
                TextFormField(controller: _plate, decoration: const InputDecoration(labelText: 'Immatriculation')),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _idNumber,
                  decoration: const InputDecoration(labelText: 'N° CNIB / CNI'),
                  validator: (v) => Validators.required(v, 'Le numéro'),
                ),
                const SizedBox(height: 10),
                TextFormField(controller: _license, decoration: const InputDecoration(labelText: 'N° permis (si nécessaire)')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _approve,
                  onChanged: (v) => setState(() => _approve = v),
                  title: const Text('Approuver immédiatement'),
                ),
              ],
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Créer')),
      ],
    );
  }
}
