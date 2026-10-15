import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Scheda prodotto: dati per i clienti (foto dei risultati, prezzo,
/// descrizione, fissaggio/lucentezza) e visibilita'. Ritorna true se cambia.
class ProductEditorScreen extends StatefulWidget {
  const ProductEditorScreen({super.key, this.product, this.nextOrder = 0});
  final Product? product;
  final int nextOrder;

  @override
  State<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends State<ProductEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final Product _p =
      widget.product?.copy() ?? Product(name: '', price: 0, sortOrder: widget.nextOrder, category: 'Styling');
  late final _name = TextEditingController(text: _p.name);
  late final _brand = TextEditingController(text: _p.brand);
  late final _category = TextEditingController(text: _p.category);
  late final _format = TextEditingController(text: _p.format);
  late final _price = TextEditingController(
    text: widget.product == null ? '' : _p.price.toStringAsFixed(2).replaceAll('.', ','),
  );
  late final _desc = TextEditingController(text: _p.description);
  late final _howTo = TextEditingController(text: _p.howToUse);
  late final _hair = TextEditingController(text: _p.hairType);
  bool _busy = false;

  static const _categories = ['Styling', 'Barba', 'Cura', 'Accessori'];

  @override
  void dispose() {
    for (final c in [_name, _brand, _category, _format, _price, _desc, _howTo, _hair]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhoto(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1400, imageQuality: 82);
      if (file == null || !mounted) return;
      setState(() => _busy = true);
      final bytes = await file.readAsBytes();
      final name = file.name.toLowerCase();
      final ext = name.contains('.') ? name.split('.').last : 'jpg';
      if (!mounted) return;
      final url = await AppScope.read(context).backend.uploadProductPhoto(bytes, ext);
      setState(() => _p.photos.add(url));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Dalla galleria'),
              onTap: () => Navigator.pop(c, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Scatta una foto'),
              onTap: () => Navigator.pop(c, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _addPhoto(source);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    _p
      ..name = _name.text.trim()
      ..brand = _brand.text.trim()
      ..category = _category.text.trim()
      ..format = _format.text.trim()
      ..price = double.parse(_price.text.trim().replaceAll(',', '.'))
      ..description = _desc.text.trim()
      ..howToUse = _howTo.text.trim()
      ..hairType = _hair.text.trim();
    setState(() => _busy = true);
    try {
      await AppScope.read(context).backend.saveProduct(_p);
      if (!mounted) return;
      showMessage(context, 'Prodotto salvato');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Eliminare il prodotto?',
      message: 'Sparisce anche la sua giacenza. In alternativa puoi solo nasconderlo ai clienti.',
      confirm: 'Elimina',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).backend.deleteProduct(_p.id);
      if (!mounted) return;
      showMessage(context, 'Prodotto eliminato');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Widget _levelPicker(String label, int value, ValueChanged<int> onChanged) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      children: [
        SizedBox(width: 96, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
        for (var i = 1; i <= 5; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              // toccando di nuovo lo stesso livello si azzera (non indicato)
              onTap: () => onChanged(value == i ? 0 : i),
              child: Container(
                width: 32,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i <= value ? AppColors.white : Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.white.withValues(alpha: 0.2)),
                ),
                child: Text(
                  '$i',
                  style: TextStyle(
                    color: i <= value ? AppColors.black : AppColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isNew = widget.product == null;
    return AppScaffold(
      title: isNew ? 'Nuovo prodotto' : 'Modifica prodotto',
      actions: [
        if (!isNew)
          IconButton(
            tooltip: 'Elimina',
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline),
          ),
      ],
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ResponsiveCenter(
                maxWidth: 640,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionTitle('Foto dei risultati'),
                    SizedBox(
                      height: 104,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var i = 0; i < _p.photos.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  SizedBox(width: 104, height: 104, child: ProductPhoto(url: _p.photos[i])),
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: IconButton.filled(
                                      tooltip: 'Togli foto',
                                      visualDensity: VisualDensity.compact,
                                      iconSize: 16,
                                      style: IconButton.styleFrom(
                                        backgroundColor: AppColors.white,
                                        foregroundColor: AppColors.black,
                                      ),
                                      onPressed: () => setState(() => _p.photos.removeAt(i)),
                                      icon: const Icon(Icons.close),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          InkWell(
                            onTap: _busy ? null : _pickSource,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 104,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.white.withValues(alpha: 0.25)),
                              ),
                              child: _busy
                                  ? const Center(child: CircularProgressIndicator())
                                  : const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_a_photo_outlined),
                                        SizedBox(height: 4),
                                        Text('Aggiungi', style: TextStyle(fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SectionTitle('Prodotto'),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Nome (es. Cera opaca)'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Obbligatorio' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _price,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Prezzo', suffixText: '€'),
                            validator: (v) {
                              final n = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                              return n == null || n < 0 ? 'Non valido' : null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _format,
                            decoration: const InputDecoration(labelText: 'Formato (es. 100 ml)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _brand,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Marca (facoltativa)'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _category,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Categoria'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final c in _categories)
                          ChoiceChip(
                            label: Text(c),
                            selected: _category.text.trim() == c,
                            onSelected: (_) => setState(() => _category.text = c),
                          ),
                      ],
                    ),
                    const SectionTitle('Per il cliente'),
                    TextFormField(
                      controller: _desc,
                      minLines: 2,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Descrizione'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _howTo,
                      minLines: 2,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Come si usa'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _hair,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Adatto a (es. capelli corti e medi)'),
                    ),
                    _levelPicker('Fissaggio', _p.hold, (v) => setState(() => _p.hold = v)),
                    _levelPicker('Lucentezza', _p.shine, (v) => setState(() => _p.shine = v)),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: _p.active,
                      onChanged: (v) => setState(() => _p.active = v),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Visibile ai clienti'),
                      subtitle: const Text('La giacenza non la vedono mai'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: const Text('SALVA'),
                    ),
                    if (isNew) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'La giacenza e la soglia di avviso si impostano dal magazzino, toccando il numero.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
