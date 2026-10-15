import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Prodotti in vendita nel negozio: blocchi con foto, nome, formato e
/// prezzo, filtro per categoria. Toccando un prodotto si apre la sua scheda
/// al centro dello schermo. La giacenza non si vede.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Product> _items = [];
  bool _loading = true;
  String? _category; // null = tutti

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final list = await AppScope.read(context).backend.fetchProducts();
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = {for (final p in _items) if (p.category.isNotEmpty) p.category}.toList()..sort();
    final shown = _category == null ? _items : _items.where((p) => p.category == _category).toList();

    return AppScaffold(
      title: 'Prodotti',
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
            ? const EmptyState(icon: Icons.inventory_2_outlined, text: 'Presto qui i prodotti del negozio')
            : ListView(
                padding: const EdgeInsets.only(top: 4, bottom: 24),
                children: [
                  ResponsiveCenter(
                    maxWidth: 900,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (categories.length > 1) ...[
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _CategoryChip(
                                  label: 'Tutti',
                                  selected: _category == null,
                                  onTap: () => setState(() => _category = null),
                                ),
                                for (final c in categories)
                                  _CategoryChip(
                                    label: c,
                                    selected: _category == c,
                                    onTap: () => setState(() => _category = c),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        LayoutBuilder(
                          builder: (context, c) {
                            // 2 colonne su telefono, di piu' su tablet e computer
                            final cols = (c.maxWidth / 200).floor().clamp(2, 5);
                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: shown.length,
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.72,
                              ),
                              itemBuilder: (context, i) =>
                                  _ProductTile(product: shown[i], onTap: () => showProductDialog(context, shown[i])),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Material(
      color: selected ? AppColors.white : Colors.white.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.white.withValues(alpha: selected ? 1 : 0.15)),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w800, color: selected ? AppColors.black : AppColors.white),
          ),
        ),
      ),
    ),
  );
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return Material(
      color: Colors.white.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.white.withValues(alpha: 0.12)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SizedBox(width: double.infinity, child: ProductPhoto(url: p.photos.firstOrNull))),
              const SizedBox(height: 8),
              Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              Text(
                [if (p.format.isNotEmpty) p.format, if (p.category.isNotEmpty) p.category].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(fmtPrice(p.price), style: slab(size: 17, weight: FontWeight.w700, spacing: 0)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scheda del prodotto al centro dello schermo: foto dei risultati scorrevoli,
/// prezzo e informazioni utili.
Future<void> showProductDialog(BuildContext context, Product p) => showDialog<void>(
  context: context,
  builder: (c) => Dialog(
    backgroundColor: AppColors.black,
    insetPadding: const EdgeInsets.all(20),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: _ProductDetail(product: p)),
  ),
);

class _ProductDetail extends StatefulWidget {
  const _ProductDetail({required this.product});
  final Product product;

  @override
  State<_ProductDetail> createState() => _ProductDetailState();
}

class _ProductDetailState extends State<_ProductDetail> {
  int _page = 0;

  Widget _level(String label, int value) => Row(
    children: [
      SizedBox(width: 92, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
      for (var i = 1; i <= 5; i++)
        Container(
          width: 22,
          height: 8,
          margin: const EdgeInsets.only(right: 4),
          decoration: BoxDecoration(
            color: i <= value ? AppColors.white : AppColors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final photos = p.photos;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 4 / 3,
                child: photos.isEmpty
                    ? const ProductPhoto(url: null, radius: 12)
                    : PageView.builder(
                        itemCount: photos.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (_, i) => ProductPhoto(url: photos[i], radius: 12),
                      ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton.filled(
                  tooltip: 'Chiudi',
                  style: IconButton.styleFrom(backgroundColor: AppColors.white, foregroundColor: AppColors.black),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ),
              if (photos.length > 1)
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < photos.length; i++)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _page ? Colors.white : Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(p.name, style: slab(size: 21, weight: FontWeight.w700, spacing: 0))),
              const SizedBox(width: 10),
              Text(fmtPrice(p.price), style: slab(size: 22, weight: FontWeight.w700, spacing: 0)),
            ],
          ),
          Text(
            [
              if (p.brand.isNotEmpty) p.brand,
              if (p.format.isNotEmpty) p.format,
              if (p.hairType.isNotEmpty) p.hairType,
            ].join(' · '),
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          if (p.hold > 0 || p.shine > 0) ...[
            const SizedBox(height: 12),
            if (p.hold > 0) _level('Fissaggio', p.hold),
            if (p.hold > 0 && p.shine > 0) const SizedBox(height: 6),
            if (p.shine > 0) _level('Lucentezza', p.shine),
          ],
          if (p.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(p.description, style: const TextStyle(height: 1.4)),
          ],
          if (p.howToUse.isNotEmpty) ...[
            const SectionTitle('Come si usa'),
            Text(p.howToUse, style: const TextStyle(color: AppColors.silver, height: 1.4)),
          ],
          const SizedBox(height: 10),
          const Text(
            'Disponibile in negozio: chiedi al tuo barbiere.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
