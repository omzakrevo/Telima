import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/launchers.dart';
import '../../core/utils/validators.dart';
import '../../data/models/json.dart';
import '../../data/models/shop.dart';
import '../../providers/shop_providers.dart';
import '../../widgets/common.dart';
import 'shop_order_screens.dart';
import 'shop_widgets.dart';

/// Espace commerçant : mes boutiques.
class ShopOwnerHomeScreen extends ConsumerWidget {
  const ShopOwnerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myShopsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ma boutique')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/shop/new'),
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('Créer une boutique'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myShopsProvider),
        child: AsyncBody<List<Shop>>(
          value: async,
          onRetry: () => ref.invalidate(myShopsProvider),
          builder: (list) => list.isEmpty
              ? ListView(padding: const EdgeInsets.all(24), children: const [
                  SizedBox(height: 40),
                  Icon(Icons.storefront_rounded, size: 64, color: AppColors.primary),
                  SizedBox(height: 12),
                  Text('Vendez vos articles avec Telima',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  Text(
                    'Créez votre boutique, ajoutez votre catalogue et recevez un lien à partager sur WhatsApp, Facebook ou TikTok. '
                    'Vos clients ouvrent le lien, voient le catalogue et commandent directement. Un livreur Telima peut livrer.',
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
                      onTap: () => context.push('/shop/${r.id}'),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
                        child: Row(children: [
                          ShopPhotoBox(url: r.logoUrl, size: 52, radius: 14),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              Text(r.subtitle.isEmpty ? 'Boutique' : r.subtitle, style: const TextStyle(color: AppColors.textMuted)),
                            ]),
                          ),
                          if (r.suspended)
                            const ShopInfoTag('Suspendu', color: AppColors.danger)
                          else
                            ShopInfoTag(r.acceptingOrders ? 'Ouvert' : 'Fermé', color: r.acceptingOrders ? AppColors.primary : AppColors.textMuted),
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

/// Tableau de bord d'une boutique : commandes, catalogue, lien à partager.
class ShopManageScreen extends ConsumerWidget {
  const ShopManageScreen({super.key, required this.shopId});
  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myShopProvider(shopId));
    final r = async.value;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(r?.name ?? 'Ma boutique'),
          actions: [
            if (r != null)
              IconButton(tooltip: 'Partager mon lien', icon: const Icon(Icons.share_rounded), onPressed: () => shareShopLink(context, r)),
            if (r != null)
              IconButton(tooltip: 'Modifier', icon: const Icon(Icons.edit_rounded), onPressed: () => context.push('/shop/${r.id}/edit')),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'Commandes'),
            Tab(text: 'Catalogue'),
            Tab(text: 'Mon lien'),
          ]),
        ),
        body: AsyncBody<Shop?>(
          value: async,
          onRetry: () => ref.invalidate(myShopProvider(shopId)),
          builder: (rest) {
            if (rest == null) return const EmptyState(icon: Icons.storefront_outlined, message: 'Boutique introuvable.');
            return Constrained(
              maxWidth: 720,
              child: Column(children: [
                if (rest.suspended)
                  Container(
                    width: double.infinity,
                    color: AppColors.danger.withValues(alpha: 0.1),
                    padding: const EdgeInsets.all(12),
                    child: const Text('Votre boutique est suspendue par l’équipe Telima : votre lien n’est plus accessible aux clients.',
                        style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                  ),
                SwitchListTile(
                  secondary: Icon(rest.acceptingOrders ? Icons.lock_open_rounded : Icons.lock_rounded,
                      color: rest.acceptingOrders ? AppColors.primary : AppColors.textMuted),
                  title: Text(rest.acceptingOrders ? 'Ouvert : je reçois des commandes' : 'Fermé : pas de commande'),
                  subtitle: const Text('Les clients voient toujours votre catalogue.'),
                  value: rest.acceptingOrders,
                  onChanged: (v) async {
                    await runWithLoader(context, () => ref.read(shopRepositoryProvider).setAccepting(rest.id, v));
                    ref.invalidate(myShopProvider(shopId));
                  },
                ),
                const Divider(height: 1),
                Expanded(
                  child: TabBarView(children: [
                    _OrdersTab(shopId: shopId),
                    _MenuTab(shop: rest),
                    _LinkTab(shop: rest),
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
  const _OrdersTab({required this.shopId});
  final String shopId;

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
    // Les nouvelles commandes apparaissent sans action du commerçant.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(shopOrdersProvider(widget.shopId));
    ref.invalidate(shopDashboardProvider(widget.shopId));
  }

  Future<void> _act(ShopOrder o, String action, {String? reason}) async {
    await runWithLoader(context, () => ref.read(shopRepositoryProvider).orderAction(o.id, action, reason: reason));
    _refresh();
  }

  Future<void> _reject(ShopOrder o) async {
    final reason = await promptDialog(context, title: 'Refuser la commande ${o.code}', label: 'Motif (ex. article en rupture)', required: false);
    if (reason == null || !mounted) return;
    await _act(o, 'reject', reason: reason.isEmpty ? null : reason);
  }

  List<Widget> _actions(ShopOrder o) {
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
    final id = widget.shopId;
    final async = ref.watch(shopOrdersProvider(id));
    final stats = ref.watch(shopDashboardProvider(id)).value;
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: AsyncBody<List<ShopOrder>>(
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
  final ShopOrder order;
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
          ShopOrderStatusChip(o),
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
              o.isDelivery ? 'Articles ${fcfa(o.itemsTotal)} + livraison ${fcfa(o.deliveryFee)}' : 'À encaisser',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
          Text(fcfa(o.isDelivery ? o.itemsTotal : o.total), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
        ]),
        if (o.isDelivery)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('Le livreur encaisse les articles auprès du client et vous les remet.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
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
// Catalogue
// ---------------------------------------------------------------------------
class _MenuTab extends ConsumerWidget {
  const _MenuTab({required this.shop});
  final Shop shop;

  void _refresh(WidgetRef ref) {
    ref.invalidate(myShopProvider(shop.id));
    ref.invalidate(shopDashboardProvider(shop.id));
  }

  Future<void> _addCategory(BuildContext context, WidgetRef ref) async {
    final name = await promptDialog(context, title: 'Nouvelle catégorie', label: 'Ex. Robes, Chaussures, Accessoires');
    if (name == null || !context.mounted) return;
    await runWithLoader(
      context,
      () => ref.read(shopRepositoryProvider).saveCategory(shopId: shop.id, name: name, sortOrder: shop.categories.length),
    );
    _refresh(ref);
  }

  Future<void> _categoryMenu(BuildContext context, WidgetRef ref, String action, ShopCategory c) async {
    final repo = ref.read(shopRepositoryProvider);
    if (action == 'rename') {
      final name = await promptDialog(context, title: 'Renommer la catégorie', initial: c.name, label: 'Nom');
      if (name == null || !context.mounted) return;
      await runWithLoader(context, () => repo.saveCategory(id: c.id, shopId: shop.id, name: name));
    } else {
      final ok = await confirmDialog(
        context,
        title: 'Supprimer « ${c.name} » ?',
        message: 'Les articles de cette catégorie ne sont pas supprimés : ils passent dans « Autres articles ».',
        confirmLabel: 'Supprimer',
        danger: true,
      );
      if (!ok || !context.mounted) return;
      await runWithLoader(context, () => repo.deleteCategory(c.id));
    }
    _refresh(ref);
  }

  Future<void> _editItem(BuildContext context, WidgetRef ref, {ShopProduct? item}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemEditor(shop: shop, item: item),
    );
    if (saved == true) _refresh(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = shop.sections;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editItem(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter un article'),
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
          if (shop.items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: EmptyState(icon: Icons.checkroom_rounded, message: 'Votre catalogue est vide.\nAjoutez vos premiers articles avec le bouton ci-dessous.'),
            ),
          for (final s in sections) ...[
            SectionTitle(
              s.name,
              trailing: s.id == null
                  ? null
                  : PopupMenuButton<String>(
                      onSelected: (a) => _categoryMenu(context, ref, a, shop.categories.firstWhere((c) => c.id == s.id)),
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
                  leading: ShopPhotoBox(url: item.photoUrl, size: 48, radius: 10),
                  title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text([
                    fcfa(item.price),
                    if (!item.isAvailable) 'masqué' else if (item.stock == 0) 'rupture de stock' else if (item.stock != null) 'stock : ${item.stock}',
                    if (item.sizes.isNotEmpty) item.sizes.join('/'),
                  ].join(' · ')),
                  trailing: Switch(
                    value: item.isAvailable,
                    onChanged: (v) async {
                      await runWithLoader(context, () => ref.read(shopRepositoryProvider).setItemAvailable(item.id, v));
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

/// Ajouter ou modifier un article (feuille qui monte du bas).
class _ItemEditor extends ConsumerStatefulWidget {
  const _ItemEditor({required this.shop, this.item});
  final Shop shop;
  final ShopProduct? item;

  @override
  ConsumerState<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends ConsumerState<_ItemEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _description = TextEditingController(text: widget.item?.description ?? '');
  late final _price = TextEditingController(text: widget.item == null ? '' : '${widget.item!.price}');
  late final _sizes = TextEditingController(text: widget.item?.sizes.join(', ') ?? '');
  late final _colors = TextEditingController(text: widget.item?.colors.join(', ') ?? '');
  late final _stock = TextEditingController(text: widget.item?.stock == null ? '' : '${widget.item!.stock}');
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
    _sizes.dispose();
    _colors.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() => _uploading = true);
    try {
      final path = await ref.read(shopRepositoryProvider).pickAndUploadPhoto(maxWidth: 800);
      if (path != null && mounted) setState(() => _photoPath = path);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// « S, M, L » -> [S, M, L] (sans doublons ni vides, 20 maximum).
  List<String> _list(String text) {
    final out = <String>[];
    for (final x in text.split(RegExp(r'[,;\n]'))) {
      final v = x.trim();
      if (v.isNotEmpty && !out.contains(v)) out.add(v);
    }
    return out.take(20).toList();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(shopRepositoryProvider).saveItem(
            id: widget.item?.id,
            shopId: widget.shop.id,
            categoryId: _categoryId,
            name: _name.text,
            description: _description.text,
            price: int.parse(_price.text.replaceAll(' ', '')),
            photoPath: _photoPath,
            isAvailable: _available,
            sizes: _list(_sizes.text),
            colors: _list(_colors.text),
            stock: _stock.text.trim().isEmpty ? null : int.parse(_stock.text.replaceAll(' ', '')),
            sortOrder: widget.shop.items.length,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: 'Supprimer cet article ?', confirmLabel: 'Supprimer', danger: true);
    if (!ok || !mounted) return;
    try {
      await ref.read(shopRepositoryProvider).deleteItem(widget.item!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.shop.categories;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.item == null ? 'Nouvel article' : 'Modifier l’article', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _uploading ? null : _pickPhoto,
                child: ShopPhotoBox(url: shopPhotoUrl(_photoPath), size: 84, icon: Icons.add_a_photo_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nom de l’article'),
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
              controller: _sizes,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Tailles proposées (facultatif)', hintText: 'S, M, L, XL  ou  38, 40, 42', helperText: 'Séparez par des virgules. Vide = pas de choix de taille.'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _colors,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Couleurs proposées (facultatif)', hintText: 'Rouge, Bleu, Noir', helperText: 'Séparez par des virgules. Vide = pas de choix de couleur.'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _stock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantité en stock (facultatif)', helperText: 'Diminue à chaque commande. Vide = quantité non suivie.'),
              validator: (v) => (v ?? '').trim().isEmpty ? null : Validators.positiveInt(v, min: 0),
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
              TextButton(onPressed: _delete, child: const Text('Supprimer cet article', style: TextStyle(color: AppColors.danger))),
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
  const _LinkTab({required this.shop});
  final Shop shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      ShopShareLinkCard(shop: shop),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: () => context.push('/b/${shop.slug}'),
        icon: const Icon(Icons.visibility_rounded),
        label: const Text('Voir ce que voient mes clients'),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: () => context.push('/shop/${shop.id}/edit'),
        icon: const Icon(Icons.edit_rounded),
        label: const Text('Modifier mes informations'),
      ),
      const SectionTitle('Zone dangereuse'),
      TextButton.icon(
        onPressed: () async {
          final ok = await confirmDialog(
            context,
            title: 'Supprimer « ${shop.name} » ?',
            message: 'Le catalogue et le lien seront supprimés. Cette action est définitive. '
                'Si la boutique a déjà reçu des commandes, fermez-la plutôt (interrupteur « Ouvert / Fermé »).',
            confirmLabel: 'Supprimer',
            danger: true,
          );
          if (!ok || !context.mounted) return;
          final done = await runWithLoader(context, () async {
            await ref.read(shopRepositoryProvider).deleteShop(shop.id);
            return true;
          }, success: 'Boutique supprimée');
          if (done == true) {
            ref.invalidate(myShopsProvider);
            if (context.mounted) context.pop();
          }
        },
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
        label: const Text('Supprimer cette boutique', style: TextStyle(color: AppColors.danger)),
      ),
    ]);
  }
}
