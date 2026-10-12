import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/shop.dart';
import '../../providers/auth_providers.dart';
import '../../providers/shop_providers.dart';
import '../../widgets/common.dart';
import 'shop_widgets.dart';

/// Ajoute un article au panier (demande la taille et la couleur si l'article en propose).
Future<void> addShopItemToCart(BuildContext context, WidgetRef ref, Shop shop, ShopProduct item) async {
  String? size;
  String? color;
  if (item.needsChoice) {
    final v = await pickShopVariant(context, item);
    if (v == null) return;
    size = v.size;
    color = v.color;
  }
  ref.read(cartProvider.notifier).add(shop.id, item.id, size: size, color: color, maxQty: item.stock);
}

/// Ouvre la fiche d'un article : grandes photos, vidéo, détails, avis.
Future<void> openShopProduct(BuildContext context, Shop shop, ShopProduct item) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShopProductScreen(shop: shop, item: item)));

class ShopProductScreen extends ConsumerStatefulWidget {
  const ShopProductScreen({super.key, required this.shop, required this.item});
  final Shop shop;
  final ShopProduct item;

  @override
  ConsumerState<ShopProductScreen> createState() => _ShopProductScreenState();
}

class _ShopProductScreenState extends ConsumerState<ShopProductScreen> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shop = widget.shop;
    final item = widget.item;
    final cart = ref.watch(cartProvider);
    final qty = cart.shopId == shop.id ? cart.quantityOf(item.id) : 0;
    final orderable = shop.acceptingOrders && item.inStock;
    final photos = [for (final p in item.galleryPaths) shopPhotoUrl(p)!];
    final video = item.videoUrl;
    final slides = photos.length + (video != null ? 1 : 0);

    return Scaffold(
      appBar: AppBar(title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
          child: Constrained(
            maxWidth: 720,
            child: Row(children: [
              Expanded(child: Text(fcfa(item.price), style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800, fontSize: 22))),
              if (!item.inStock)
                const ShopInfoTag('Épuisé', color: AppColors.danger)
              else if (orderable)
                ShopQtyStepper(
                  qty: qty,
                  onAdd: () => addShopItemToCart(context, ref, shop, item),
                  onRemove: () => ref.read(cartProvider.notifier).removeOneOf(item.id),
                )
              else
                const ShopInfoTag('Boutique fermée', color: AppColors.danger),
            ]),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Constrained(
          maxWidth: 720,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (slides == 0)
              const ShopPhotoBox(url: null, size: double.infinity, height: 260, radius: 0, icon: Icons.image_outlined)
            else ...[
              SizedBox(
                height: 340,
                child: PageView.builder(
                  controller: _page,
                  itemCount: slides,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) {
                    if (i >= photos.length) return _VideoSlide(url: video!);
                    return GestureDetector(
                      onTap: () => openShopPhotoViewer(context, photos, i),
                      child: Container(
                        color: AppColors.peach,
                        child: Image.network(photos[i], fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, size: 48)),
                      ),
                    );
                  },
                ),
              ),
              if (slides > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SizedBox(
                    height: 56,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: slides,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => _page.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                        child: Container(
                          width: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: i == _index ? AppColors.primary : AppColors.line, width: i == _index ? 2.5 : 1),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: i >= photos.length
                                ? Container(color: Colors.black87, child: const Icon(Icons.play_arrow_rounded, color: Colors.white))
                                : ShopPhotoBox(url: photos[i], size: 56, radius: 0),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Touchez la photo pour l’agrandir', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Row(children: [
                  RatingDisplay(rating: item.ratingAvg, count: item.ratingCount),
                  const SizedBox(width: 10),
                  if (item.lowStock) ShopInfoTag('Plus que ${item.stock}', color: AppColors.accent),
                ]),
                if (item.sizes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('Tailles', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: [for (final x in item.sizes) ShopInfoTag(x)]),
                ],
                if (item.colors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Couleurs', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: [for (final x in item.colors) ShopInfoTag(x)]),
                ],
                if ((item.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(item.description!, style: const TextStyle(height: 1.4)),
                ],
                const SizedBox(height: 8),
                const Divider(height: 28),
                ShopReviewsSection(shop: shop, productId: item.id, title: 'Avis sur cet article'),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Vignette vidéo : la lecture s'ouvre dans le lecteur du téléphone ou du navigateur.
class _VideoSlide extends StatelessWidget {
  const _VideoSlide({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Container(
          color: Colors.black87,
          alignment: Alignment.center,
          child: const Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 76),
            SizedBox(height: 8),
            Text('Voir la vidéo de l’article', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

/// Visionneuse plein écran : glisser pour changer de photo, pincer pour zoomer.
Future<void> openShopPhotoViewer(BuildContext context, List<String> urls, int start) => Navigator.of(context).push(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => _PhotoViewer(urls: urls, start: start)),
    );

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.urls, required this.start});
  final List<String> urls;
  final int start;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final _controller = PageController(initialPage: widget.start);
  late int _index = widget.start;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('${_index + 1} / ${widget.urls.length}'),
        ),
        body: PageView.builder(
          controller: _controller,
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(child: Image.network(widget.urls[i], fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 56))),
          ),
        ),
      );
}

/// Avis et note d'une boutique ([productId] null) ou d'un article.
class ShopReviewsSection extends ConsumerWidget {
  const ShopReviewsSection({super.key, required this.shop, this.productId, required this.title});
  final Shop shop;
  final String? productId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (shop.id, productId);
    final async = ref.watch(shopReviewsProvider(key));
    final signedIn = ref.watch(authControllerProvider).isSignedIn;
    final reviews = async.value ?? const <ShopReview>[];
    final mine = reviews.where((r) => r.mine).firstOrNull;
    final avg = reviews.isEmpty ? 0.0 : reviews.fold<int>(0, (a, r) => a + r.rating) / reviews.length;

    Future<void> rate() async {
      if (!signedIn) {
        ref.read(pendingRouteProvider.notifier).set('/b/${shop.slug}');
        context.push('/login');
        return;
      }
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _RateSheet(shop: shop, productId: productId, existing: mine, title: title),
      );
      if (ok == true) {
        ref.invalidate(shopReviewsProvider(key));
        ref.invalidate(shopBySlugProvider(shop.slug));
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        if (reviews.isNotEmpty) RatingDisplay(rating: avg, count: reviews.length),
      ]),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: rate,
        icon: Icon(mine == null ? Icons.star_outline_rounded : Icons.edit_rounded),
        label: Text(mine == null ? 'Donner mon avis' : 'Modifier mon avis'),
      ),
      const SizedBox(height: 10),
      if (async.isLoading && reviews.isEmpty)
        const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
      else if (reviews.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Aucun avis pour le moment. Soyez le premier !', style: TextStyle(color: AppColors.textMuted)))
      else
        for (final r in reviews.take(20)) _ReviewTile(review: r),
    ]);
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});
  final ShopReview review;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(review.mine ? '${review.author} (vous)' : review.author, style: const TextStyle(fontWeight: FontWeight.w700))),
            for (var i = 1; i <= 5; i++)
              Icon(i <= review.rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 17, color: AppColors.accent),
          ]),
          if ((review.comment ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(review.comment!, style: const TextStyle(height: 1.3))),
          if (review.createdAt != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(formatDate(review.createdAt!), style: const TextStyle(color: AppColors.textMuted, fontSize: 12))),
        ]),
      );
}

class _RateSheet extends ConsumerStatefulWidget {
  const _RateSheet({required this.shop, required this.productId, required this.existing, required this.title});
  final Shop shop;
  final String? productId;
  final ShopReview? existing;
  final String title;

  @override
  ConsumerState<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends ConsumerState<_RateSheet> {
  late int _rating = widget.existing?.rating ?? 0;
  late final _comment = TextEditingController(text: widget.existing?.comment ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await ref.read(shopRepositoryProvider).rate(widget.shop.id, productId: widget.productId, rating: _rating, comment: _comment.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await ref.read(shopRepositoryProvider).deleteMyReview(widget.shop.id, productId: widget.productId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.productId == null ? 'Noter ${widget.shop.name}' : 'Noter cet article', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            StarInput(value: _rating, onChanged: (v) => setState(() => _rating = v)),
            TextField(
              controller: _comment,
              maxLines: 3,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Votre commentaire (facultatif)'),
            ),
            const SizedBox(height: 8),
            BigActionButton(label: 'ENVOYER MON AVIS', icon: Icons.check_rounded, loading: _busy, onPressed: _rating == 0 ? null : _send),
            if (widget.existing != null)
              TextButton(onPressed: _busy ? null : _delete, child: const Text('Supprimer mon avis', style: TextStyle(color: AppColors.danger))),
          ]),
        ),
      );
}
