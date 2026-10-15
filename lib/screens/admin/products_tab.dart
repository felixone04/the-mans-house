import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'product_editor_screen.dart';

/// Magazzino: prodotti in vendita, giacenza (visibile solo qui), soglia di
/// sottoscorta e vendita al banco senza appuntamento.
class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key, this.onStockChanged});

  /// Avvisa l'area riservata quando cambia il numero di prodotti da riordinare.
  final VoidCallback? onStockChanged;

  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  List<Product> _items = [];
  Map<String, ProductStock> _stock = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final backend = AppScope.read(context).backend;
    try {
      final items = await backend.fetchProducts(includeInactive: true);
      final stock = await backend.fetchStock();
      if (!mounted) return;
      setState(() {
        _items = items;
        _stock = stock;
      });
      widget.onStockChanged?.call();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ProductStock _of(Product p) => _stock[p.id] ?? ProductStock(productId: p.id);

  Future<void> _edit([Product? p]) async {
    final changed = await Navigator.of(context).push<bool>(
      fadeRoute(
        ProductEditorScreen(
          product: p,
          nextOrder: _items.isEmpty ? 1 : _items.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1,
        ),
      ),
    );
    if (changed == true) await _load(silent: true);
  }

  Future<void> _adjust(Product p, int delta) async {
    HapticFeedback.selectionClick();
    try {
      await AppScope.read(context).backend.adjustStock(p.id, delta, note: delta > 0 ? 'Carico' : 'Rettifica');
      await _load(silent: true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Carico di piu' pezzi in una volta (arrivo merce) o correzione inventario.
  Future<void> _editStock(Product p) async {
    final st = _of(p);
    final r = await showDialog<(int, int)>(
      context: context,
      builder: (_) => _StockDialog(product: p, stock: st.stock, threshold: st.threshold),
    );
    if (r == null || !mounted) return;
    final (newStock, threshold) = r;
    final backend = AppScope.read(context).backend;
    try {
      if (newStock != st.stock) {
        await backend.adjustStock(p.id, newStock - st.stock, note: newStock > st.stock ? 'Carico' : 'Inventario');
      }
      if (threshold != st.threshold) await backend.setStockThreshold(p.id, threshold);
      await _load(silent: true);
      if (mounted) showMessage(context, 'Magazzino aggiornato');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _sell() async {
    final sold = await showSellSheet(context);
    if (sold && mounted) await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final low = [for (final p in _items) if (p.active && _of(p).low) p];
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        ResponsiveCenter(
          maxWidth: 800,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _items.isEmpty ? null : _sell,
                      icon: const Icon(Icons.point_of_sale_outlined),
                      label: const Text('VENDI'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _edit(),
                      icon: const Icon(Icons.add),
                      label: const Text('NUOVO'),
                    ),
                  ),
                ],
              ),
              if (low.isNotEmpty) ...[
                const SizedBox(height: 12),
                _LowStockBanner(products: low, stockOf: _of),
              ],
              const SizedBox(height: 14),
              if (_loading)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (_items.isEmpty)
                const EmptyState(icon: Icons.inventory_2_outlined, text: 'Nessun prodotto: aggiungi il primo')
              else
                for (final p in _items)
                  _ProductRow(
                    product: p,
                    stock: _of(p),
                    onTap: () => _edit(p),
                    onMinus: _of(p).stock > 0 ? () => _adjust(p, -1) : null,
                    onPlus: () => _adjust(p, 1),
                    onStock: () => _editStock(p),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LowStockBanner extends StatelessWidget {
  const _LowStockBanner({required this.products, required this.stockOf});
  final List<Product> products;
  final ProductStock Function(Product) stockOf;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE8B8),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE0A030)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFF8A4B00), size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                products.length == 1 ? '1 prodotto da riordinare' : '${products.length} prodotti da riordinare',
                style: const TextStyle(color: Color(0xFF4A2800), fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                products
                    .map((p) {
                      final s = stockOf(p).stock;
                      return '${p.name} (${s <= 0 ? 'esaurito' : 'ne restano $s'})';
                    })
                    .join(' · '),
                style: const TextStyle(color: Color(0xFF6B3A00), fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.stock,
    required this.onTap,
    required this.onMinus,
    required this.onPlus,
    required this.onStock,
  });
  final Product product;
  final ProductStock stock;
  final VoidCallback onTap;
  final VoidCallback? onMinus;
  final VoidCallback onPlus;
  final VoidCallback onStock;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final out = stock.stock <= 0;
    final color = out
        ? AppColors.danger
        : stock.low
        ? AppColors.warning
        : AppColors.success;
    return Opacity(
      opacity: p.active ? 1 : 0.55,
      child: GlassCard(
        margin: const EdgeInsets.only(bottom: 10),
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(width: 54, height: 54, child: ProductPhoto(url: p.photos.firstOrNull, radius: 8)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                  ),
                  Text(
                    [
                      fmtPrice(p.price),
                      if (p.format.isNotEmpty) p.format,
                      if (!p.active) 'nascosto ai clienti',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: onStock,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${out ? 'Esaurito' : stock.low ? 'Da riordinare' : 'Disponibile'} · avviso a ${stock.threshold}',
                        style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Togli un pezzo',
              onPressed: onMinus,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 30,
              child: Text(
                '${stock.stock}',
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            IconButton(tooltip: 'Aggiungi un pezzo', onPressed: onPlus, icon: const Icon(Icons.add_circle_outline)),
          ],
        ),
      ),
    );
  }
}

/// Giacenza esatta (inventario o arrivo merce) e soglia di sottoscorta.
class _StockDialog extends StatefulWidget {
  const _StockDialog({required this.product, required this.stock, required this.threshold});
  final Product product;
  final int stock;
  final int threshold;

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  late final _stock = TextEditingController(text: '${widget.stock}');
  late final _arrived = TextEditingController();
  late final _threshold = TextEditingController(text: '${widget.threshold}');

  @override
  void dispose() {
    for (final c in [_stock, _arrived, _threshold]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return AlertDialog(
      title: Text(widget.product.name),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _arrived,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: const InputDecoration(labelText: 'Arrivati ora (si aggiungono)', suffixText: 'pz'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _stock,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: const InputDecoration(labelText: 'Oppure giacenza esatta (inventario)', suffixText: 'pz'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _threshold,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: const InputDecoration(
                  labelText: 'Avvisami quando ne restano',
                  suffixText: 'pz',
                  helperText: 'Sotto questa soglia il prodotto va tra quelli da riordinare',
                  helperMaxLines: 2,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
          onPressed: () {
            final arrived = int.tryParse(_arrived.text) ?? 0;
            final exact = int.tryParse(_stock.text) ?? widget.stock;
            final stock = arrived > 0 ? widget.stock + arrived : exact;
            Navigator.pop(context, (stock, int.tryParse(_threshold.text) ?? widget.threshold));
          },
          child: const Text('Salva'),
        ),
      ],
    );
  }
}

/// Vendita dal magazzino: si sceglie il prodotto e la quantita', la giacenza
/// scende da sola. Con [appointmentId] la vendita si somma al conto del
/// cliente (dal pagamento in agenda). Ritorna true se ha venduto.
Future<bool> showSellSheet(BuildContext context, {String? appointmentId}) async {
  final sold = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AgendaLight.card,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => _SellSheet(appointmentId: appointmentId),
  );
  return sold ?? false;
}

class _SellSheet extends StatefulWidget {
  const _SellSheet({this.appointmentId});
  final String? appointmentId;

  @override
  State<_SellSheet> createState() => _SellSheetState();
}

class _SellSheetState extends State<_SellSheet> {
  List<Product> _items = [];
  Map<String, ProductStock> _stock = {};
  bool _loading = true;
  bool _busy = false;
  Product? _picked;
  int _qty = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final backend = AppScope.read(context).backend;
    try {
      final items = await backend.fetchProducts(includeInactive: true);
      final stock = await backend.fetchStock();
      if (mounted) {
        setState(() {
          _items = items;
          _stock = stock;
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _left(Product p) => _stock[p.id]?.stock ?? 0;

  Future<void> _confirm() async {
    final p = _picked;
    if (p == null) return;
    setState(() => _busy = true);
    try {
      await AppScope.read(context).backend.sellProduct(p.id, _qty, appointmentId: widget.appointmentId);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      final left = _left(p) - _qty;
      showMessage(
        context,
        '${_qty == 1 ? '' : '$_qty × '}${p.name} venduto · ${left <= 0 ? 'esaurito' : 'ne restano $left'}',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _picked;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.appointmentId == null ? 'Vendi un prodotto' : 'Aggiungi prodotto',
                style: const TextStyle(color: AgendaLight.ink, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              Text(
                widget.appointmentId == null
                    ? 'Vendita al banco: si toglie dal magazzino'
                    : 'Si aggiunge al conto e si toglie dal magazzino',
                style: const TextStyle(color: AgendaLight.sub, fontSize: 13.5),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
              else if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Nessun prodotto in magazzino', textAlign: TextAlign.center),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final it in _items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Material(
                            color: it == p ? const Color(0xFFF1EFEA) : Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: it == p ? AgendaLight.ink : AgendaLight.line,
                                width: it == p ? 2 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: _left(it) <= 0
                                  ? null
                                  : () => setState(() {
                                      _picked = it;
                                      _qty = 1;
                                    }),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 42,
                                      height: 42,
                                      child: ProductPhoto(url: it.photos.firstOrNull, radius: 6),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            it.name,
                                            style: const TextStyle(
                                              color: AgendaLight.ink,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            _left(it) <= 0 ? 'Esaurito' : 'In magazzino: ${_left(it)}',
                                            style: TextStyle(
                                              color: _left(it) <= 0 ? AgendaLight.muted : AgendaLight.sub,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      fmtPrice(it.price),
                                      style: const TextStyle(
                                        color: AgendaLight.ink,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (p != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      'Quantità',
                      style: TextStyle(color: AgendaLight.ink, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                      icon: const Icon(Icons.remove_circle_outline, color: AgendaLight.ink),
                    ),
                    Text(
                      '$_qty',
                      style: const TextStyle(color: AgendaLight.ink, fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    IconButton(
                      onPressed: _qty < _left(p) ? () => setState(() => _qty++) : null,
                      icon: const Icon(Icons.add_circle_outline, color: AgendaLight.ink),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AgendaLight.ink, foregroundColor: Colors.white),
                onPressed: p == null || _busy ? null : _confirm,
                child: Text(p == null ? 'SCEGLI UN PRODOTTO' : 'VENDI · ${fmtPrice(p.price * _qty)}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
