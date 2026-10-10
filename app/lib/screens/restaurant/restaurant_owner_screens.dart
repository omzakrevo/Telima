import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../core/utils/validators.dart';
import '../../data/models/json.dart';
import '../../data/models/restaurant.dart';
import '../../providers/restaurant_providers.dart';
import '../../widgets/common.dart';
import 'restaurant_order_screens.dart';
import 'restaurant_widgets.dart';

/// Espace restaurateur : mes restaurants.
class RestaurantOwnerHomeScreen extends ConsumerWidget {
  const RestaurantOwnerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myRestaurantsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mon restaurant')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/restaurant/new'),
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Créer un restaurant'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myRestaurantsProvider),
        child: AsyncBody<List<Restaurant>>(
          value: async,
          onRetry: () => ref.invalidate(myRestaurantsProvider),
          builder: (list) => list.isEmpty
              ? ListView(padding: const EdgeInsets.all(24), children: const [
                  SizedBox(height: 40),
                  Icon(Icons.restaurant_rounded, size: 64, color: AppColors.primary),
                  SizedBox(height: 12),
                  Text('Vendez vos plats avec Telima',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  Text(
                    'Créez votre restaurant, ajoutez votre menu et recevez un lien à partager sur WhatsApp, Facebook ou TikTok. '
                    'Vos clients ouvrent le lien, voient le menu et commandent directement. Un livreur Telima peut livrer.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, height: 1.4),
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final r = list[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => context.push('/restaurant/${r.id}'),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
                        child: Row(children: [
                          PhotoBox(url: r.logoUrl, size: 52, radius: 14),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              Text(r.subtitle.isEmpty ? 'Restaurant' : r.subtitle, style: const TextStyle(color: AppColors.textMuted)),
                            ]),
                          ),
                          if (r.suspended)
                            const InfoTag('Suspendu', color: AppColors.danger)
                          else
                            InfoTag(r.acceptingOrders ? 'Ouvert' : 'Fermé', color: r.acceptingOrders ? AppColors.primary : AppColors.textMuted),
                          const Icon(Icons.chevron_right_rounded),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// Tableau de bord d'un restaurant : commandes, menu, lien à partager.
class RestaurantManageScreen extends ConsumerWidget {
  const RestaurantManageScreen({super.key, required this.restaurantId});
  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myRestaurantProvider(restaurantId));
    final r = async.value;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(r?.name ?? 'Mon restaurant'),
          actions: [
            if (r != null)
              IconButton(tooltip: 'Partager mon lien', icon: const Icon(Icons.share_rounded), onPressed: () => shareRestaurantLink(context, r)),
            if (r != null)
              IconButton(tooltip: 'Modifier', icon: const Icon(Icons.edit_rounded), onPressed: () => context.push('/restaurant/${r.id}/edit')),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Commandes'),
            Tab(text: 'Menu'),
            Tab(text: 'Mon lien'),
          ]),
        ),
        body: AsyncBody<Restaurant?>(
          value: async,
          onRetry: () => ref.invalidate(myRestaurantProvider(restaurantId)),
          builder: (rest) {
            if (rest == null) return const EmptyState(icon: Icons.storefront_outlined, message: 'Restaurant introuvable.');
            return Constrained(
              maxWidth: 720,
              child: Column(children: [
                if (rest.suspended)
                  Container(
                    width: double.infinity,
                    color: AppColors.danger.withValues(alpha: 0.1),
                    padding: const EdgeInsets.all(12),
                    child: const Text('Votre restaurant est suspendu par l’équipe Telima : votre lien n’est plus accessible aux clients.',
                        style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                  ),
                SwitchListTile(
                  secondary: Icon(rest.acceptingOrders ? Icons.lock_open_rounded : Icons.lock_rounded,
                      color: rest.acceptingOrders ? AppColors.primary : AppColors.textMuted),
                  title: Text(rest.acceptingOrders ? 'Ouvert : je reçois des commandes' : 'Fermé : pas de commande'),
                  subtitle: const Text('Les clients voient toujours votre menu.'),
                  value: rest.acceptingOrders,
                  onChanged: (v) async {
                    await runWithLoader(context, () => ref.read(restaurantRepositoryProvider).setAccepting(rest.id, v));
                    ref.invalidate(myRestaurantProvider(restaurantId));
                  },
                ),
                const Divider(height: 1),
                Expanded(
                  child: TabBarView(children: [
                    _OrdersTab(restaurantId: restaurantId),
                    _MenuTab(restaurant: rest),
                    _LinkTab(restaurant: rest),
                  ]),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Commandes
// ---------------------------------------------------------------------------
class _OrdersTab extends ConsumerStatefulWidget {
  const _OrdersTab({required this.restaurantId});
  final String restaurantId;

  @override
  ConsumerState<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends ConsumerState<_OrdersTab> with AutomaticKeepAliveClientMixin {
  Timer? _timer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Les nouvelles commandes apparaissent sans action du restaurateur.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(restaurantOrdersProvider(widget.restaurantId));
    ref.invalidate(restaurantDashboardProvider(widget.restaurantId));
  }

  Future<void> _act(RestaurantOrder o, String action, {String? reason}) async {
    await runWithLoader(context, () => ref.read(restaurantRepositoryProvider).orderAction(o.id, action, reason: reason));
    _refresh();
  }

  Future<void> _reject(RestaurantOrder o) async {
    final reason = await promptDialog(context, title: 'Refuser la commande ${o.code}', label: 'Motif (ex. plat épuisé)', required: false);
    if (reason == null || !mounted) return;
    await _act(o, 'reject', reason: reason.isEmpty ? null : reason);
  }

  List<Widget> _actions(RestaurantOrder o) {
    switch (o.status) {
      case 'sent':
        return [
          OutlinedButton(onPressed: () => _reject(o), child: const Text('Refuser')),
          FilledButton(onPressed: () => _act(o, 'accept'), child: const Text('Accepter')),
        ];
      case 'accepted':
        return [
          OutlinedButton(onPressed: () => _reject(o), child: const Text('Refuser')),
          FilledButton(onPressed: () => _act(o, 'preparing'), child: const Text('En préparation')),
        ];
      case 'preparing':
        return [
          FilledButton(
            onPressed: () => _act(o, 'ready'),
            child: Text(o.isDelivery ? 'Prête : appeler un livreur' : 'Prête à retirer'),
          ),
        ];
      case 'ready':
        return o.isDelivery ? const [] : [FilledButton(onPressed: () => _act(o, 'handed'), child: const Text('Remise au client'))];
      default:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final id = widget.restaurantId;
    final async = ref.watch(restaurantOrdersProvider(id));
    final stats = ref.watch(restaurantDashboardProvider(id)).value;
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: AsyncBody<List<RestaurantOrder>>(
        value: async,
        onRetry: _refresh,
        builder: (list) {
          final open = [for (final o in list) if (o.isOpen) o];
          final done = [for (final o in list) if (!o.isOpen) o];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
            if (stats != null)
              Row(children: [
                Expanded(child: _Stat('Aujourd’hui', '${asInt(stats['orders_today'])} cmd')),
                const SizedBox(width: 8),
                Expanded(child: _Stat('Ventes', fcfa(asInt(stats['sales_today'])))),
                const SizedBox(width: 8),
                Expanded(child: _Stat('À traiter', '${asInt(stats['pending'])}', highlight: asInt(stats['pending']) > 0)),
              ]),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: EmptyState(icon: Icons.receipt_long_rounded, message: 'Pas encore de commande.\nPartagez votre lien pour recevoir la première !'),
              ),
            if (open.isNotEmpty) const SectionTitle('En cours'),
            for (final o in open) _OrderCard(order: o, actions: _actions(o)),
            if (done.isNotEmpty) const SectionTitle('Terminées'),
            for (final o in done) _OrderCard(order: o, actions: const []),
          ]);
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.highlight = false});
  final String label;
  final String value;
  final bool highlight;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: highlight ? AppColors.peach : AppColors.field, borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ]),
      );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.actions});
  final RestaurantOrder order;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${o.code} · ${relativeTime(o.createdAt)}', style: const TextStyle(fontWeight: FontWeight.w800))),
          OrderStatusChip(o),
        ]),
        const SizedBox(height: 8),
        for (final i in o.items)
          Padding(padding: const EdgeInsets.only(bottom: 2), child: Row(children: [Expanded(child: Text(i.text)), Text(fcfa(i.unitPrice * i.qty))])),
        if ((o.note ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Message : ${o.note}', style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.accent, fontWeight: FontWeight.w600)),
          ),
        const Divider(height: 16),
        Row(children: [
          Icon(o.isDelivery ? Icons.delivery_dining_rounded : Icons.storefront_rounded, size: 18, color: AppColors.primaryDark),
          const SizedBox(width: 6),
          Expanded(child: Text(o.isDelivery ? 'Livraison · ${o.dropoffAddress ?? ''}' : 'Retrait sur place')),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text('${o.customerName} · ${displayPhone(o.customerPhone)}')),
          IconButton(
            tooltip: 'Appeler',
            visualDensity: VisualDensity.compact,
            onPressed: () => callPhone(o.customerPhone),
            icon: const Icon(Icons.call_rounded, color: AppColors.primaryDark),
          ),
        ]),
        Row(children: [
          Expanded(
            child: Text(
              o.isDelivery ? 'Plats ${fcfa(o.itemsTotal)} + livraison ${fcfa(o.deliveryFee)}' : 'À encaisser',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
          Text(fcfa(o.isDelivery ? o.itemsTotal : o.total), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
        ]),
        if (o.isDelivery)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('Le livreur encaisse les plats auprès du client et vous les remet.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: a)],
          ]),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Menu
// ---------------------------------------------------------------------------
class _MenuTab extends ConsumerWidget {
  const _MenuTab({required this.restaurant});
  final Restaurant restaurant;

  void _refresh(WidgetRef ref) {
    ref.invalidate(myRestaurantProvider(restaurant.id));
    ref.invalidate(restaurantDashboardProvider(restaurant.id));
  }

  Future<void> _addCategory(BuildContext context, WidgetRef ref) async {
    final name = await promptDialog(context, title: 'Nouvelle catégorie', label: 'Ex. Plats, Boissons, Desserts');
    if (name == null || !context.mounted) return;
    await runWithLoader(
      context,
      () => ref.read(restaurantRepositoryProvider).saveCategory(restaurantId: restaurant.id, name: name, sortOrder: restaurant.categories.length),
    );
    _refresh(ref);
  }

  Future<void> _categoryMenu(BuildContext context, WidgetRef ref, String action, MenuCategory c) async {
    final repo = ref.read(restaurantRepositoryProvider);
    if (action == 'rename') {
      final name = await promptDialog(context, title: 'Renommer la catégorie', initial: c.name, label: 'Nom');
      if (name == null || !context.mounted) return;
      await runWithLoader(context, () => repo.saveCategory(id: c.id, restaurantId: restaurant.id, name: name));
    } else {
      final ok = await confirmDialog(
        context,
        title: 'Supprimer « ${c.name} » ?',
        message: 'Les plats de cette catégorie ne sont pas supprimés : ils passent dans « Autres plats ».',
        confirmLabel: 'Supprimer',
        danger: true,
      );
      if (!ok || !context.mounted) return;
      await runWithLoader(context, () => repo.deleteCategory(c.id));
    }
    _refresh(ref);
  }

  Future<void> _editItem(BuildContext context, WidgetRef ref, {MenuItem? item}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemEditor(restaurant: restaurant, item: item),
    );
    if (saved == true) _refresh(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = restaurant.sections;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editItem(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter un plat'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(ref),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _addCategory(context, ref),
              icon: const Icon(Icons.create_new_folder_rounded),
              label: const Text('Ajouter une catégorie'),
            ),
          ),
          if (restaurant.items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: EmptyState(icon: Icons.restaurant_menu_rounded, message: 'Votre menu est vide.\nAjoutez vos premiers plats avec le bouton ci-dessous.'),
            ),
          for (final s in sections) ...[
            SectionTitle(
              s.name,
              trailing: s.id == null
                  ? null
                  : PopupMenuButton<String>(
                      onSelected: (a) => _categoryMenu(context, ref, a, restaurant.categories.firstWhere((c) => c.id == s.id)),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Renommer')),
                        PopupMenuItem(value: 'delete', child: Text('Supprimer la catégorie')),
                      ],
                    ),
            ),
            for (final item in s.items)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
                child: ListTile(
                  onTap: () => _editItem(context, ref, item: item),
                  leading: PhotoBox(url: item.photoUrl, size: 48, radius: 10),
                  title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(item.isAvailable ? fcfa(item.price) : '${fcfa(item.price)} · épuisé'),
                  trailing: Switch(
                    value: item.isAvailable,
                    onChanged: (v) async {
                      await runWithLoader(context, () => ref.read(restaurantRepositoryProvider).setItemAvailable(item.id, v));
                      _refresh(ref);
                    },
                  ),
                ),
              ),
          ],
        ]),
      ),
    );
  }
}

/// Ajouter ou modifier un plat (feuille qui monte du bas).
class _ItemEditor extends ConsumerStatefulWidget {
  const _ItemEditor({required this.restaurant, this.item});
  final Restaurant restaurant;
  final MenuItem? item;

  @override
  ConsumerState<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends ConsumerState<_ItemEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _description = TextEditingController(text: widget.item?.description ?? '');
  late final _price = TextEditingController(text: widget.item == null ? '' : '${widget.item!.price}');
  late String? _categoryId = widget.item?.categoryId;
  late String? _photoPath = widget.item?.photoPath;
  late bool _available = widget.item?.isAvailable ?? true;
  bool _saving = false;
  bool _uploading = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() => _uploading = true);
    try {
      final path = await ref.read(restaurantRepositoryProvider).pickAndUploadPhoto(maxWidth: 800);
      if (path != null && mounted) setState(() => _photoPath = path);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(restaurantRepositoryProvider).saveItem(
            id: widget.item?.id,
            restaurantId: widget.restaurant.id,
            categoryId: _categoryId,
            name: _name.text,
            description: _description.text,
            price: int.parse(_price.text.replaceAll(' ', '')),
            photoPath: _photoPath,
            isAvailable: _available,
            sortOrder: widget.restaurant.items.length,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: 'Supprimer ce plat ?', confirmLabel: 'Supprimer', danger: true);
    if (!ok || !mounted) return;
    try {
      await ref.read(restaurantRepositoryProvider).deleteItem(widget.item!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.restaurant.categories;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.item == null ? 'Nouveau plat' : 'Modifier le plat', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _uploading ? null : _pickPhoto,
                child: PhotoBox(url: restaurantPhotoUrl(_photoPath), size: 84, icon: Icons.add_a_photo_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nom du plat'),
                  validator: (v) => Validators.required(v, 'Le nom'),
                ),
              ),
            ]),
            if (_photoPath != null)
              Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => setState(() => _photoPath = null), child: const Text('Retirer la photo'))),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Prix (FCFA)'),
              validator: (v) => Validators.positiveInt(v, min: 0),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 2,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Description (facultatif)'),
            ),
            if (cats.isNotEmpty) ...[
              const SizedBox(height: 4),
              DropdownButtonFormField<String?>(
                initialValue: cats.any((c) => c.id == _categoryId) ? _categoryId : null,
                decoration: const InputDecoration(labelText: 'Catégorie'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Aucune')),
                  for (final c in cats) DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Disponible aujourd’hui'),
              value: _available,
              onChanged: (v) => setState(() => _available = v),
            ),
            const SizedBox(height: 8),
            BigActionButton(label: 'ENREGISTRER', icon: Icons.check_rounded, loading: _saving, onPressed: _uploading ? null : _save),
            if (widget.item != null)
              TextButton(onPressed: _delete, child: const Text('Supprimer ce plat', style: TextStyle(color: AppColors.danger))),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lien à partager
// ---------------------------------------------------------------------------
class _LinkTab extends ConsumerWidget {
  const _LinkTab({required this.restaurant});
  final Restaurant restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      ShareLinkCard(restaurant: restaurant),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: () => context.push('/r/${restaurant.slug}'),
        icon: const Icon(Icons.visibility_rounded),
        label: const Text('Voir ce que voient mes clients'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: () => context.push('/restaurant/${restaurant.id}/edit'),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('Modifier mes informations'),
      ),
      const SectionTitle('Zone dangereuse'),
      TextButton.icon(
        onPressed: () async {
          final ok = await confirmDialog(
            context,
            title: 'Supprimer « ${restaurant.name} » ?',
            message: 'Le menu et le lien seront supprimés. Cette action est définitive. '
                'Si le restaurant a déjà reçu des commandes, fermez-le plutôt (interrupteur « Ouvert / Fermé »).',
            confirmLabel: 'Supprimer',
            danger: true,
          );
          if (!ok || !context.mounted) return;
          final done = await runWithLoader(context, () async {
            await ref.read(restaurantRepositoryProvider).deleteRestaurant(restaurant.id);
            return true;
          }, success: 'Restaurant supprimé');
          if (done == true) {
            ref.invalidate(myRestaurantsProvider);
            if (context.mounted) context.pop();
          }
        },
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
        label: const Text('Supprimer ce restaurant', style: TextStyle(color: AppColors.danger)),
      ),
    ]);
  }
}
