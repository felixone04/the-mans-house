import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Gestione dei servizi (taglio, barba, ...): nome, durata, prezzo.
class ServicesTab extends StatefulWidget {
  const ServicesTab({super.key});

  @override
  State<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<ServicesTab> {
  List<Service> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _items = await AppScope.read(context).backend.fetchServices(includeInactive: true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Service? s]) async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _ServiceDialog(
        service: s,
        nextOrder: _items.isEmpty ? 1 : _items.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1,
      ),
    );
    if (result == null || !mounted) return;
    final state = AppScope.read(context);
    try {
      if (result.delete) {
        await state.backend.deleteService(s!.id);
      } else {
        await state.backend.saveService(result.service!);
      }
      await state.refreshCatalog();
      await _load();
      if (mounted) showMessage(context, result.delete ? 'Servizio eliminato' : 'Servizio salvato');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        ResponsiveCenter(
          maxWidth: 800,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('NUOVO SERVIZIO')),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_items.isEmpty)
              const EmptyState(icon: Icons.content_cut, text: 'Nessun servizio')
            else
              for (final s in _items)
                Opacity(
                  opacity: s.active ? 1 : 0.5,
                  child: GlassCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    onTap: () => _edit(s),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                          Text(
                            '${fmtDuration(s.durationMin)}${s.active ? '' : ' · non visibile ai clienti'}',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                          ),
                        ]),
                      ),
                      Text(fmtPrice(s.price), style: slab(size: 17, weight: FontWeight.w600, spacing: 0.3)),
                      const SizedBox(width: 8),
                      const Icon(Icons.edit_outlined, size: 18, color: AppColors.muted),
                    ]),
                  ),
                ),
          ]),
        ),
      ],
    );
  }
}

class _EditResult {
  final Service? service;
  final bool delete;
  _EditResult({this.service, this.delete = false});
}

class _ServiceDialog extends StatefulWidget {
  const _ServiceDialog({this.service, required this.nextOrder});
  final Service? service;
  final int nextOrder;

  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.service?.name ?? '');
  late final _desc = TextEditingController(text: widget.service?.description ?? '');
  late final _duration = TextEditingController(text: '${widget.service?.durationMin ?? 30}');
  late final _price = TextEditingController(
      text: widget.service == null ? '' : widget.service!.price.toStringAsFixed(2).replaceAll('.', ','));
  late bool _active = widget.service?.active ?? true;

  @override
  void dispose() {
    for (final c in [_name, _desc, _duration, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      _EditResult(
        service: Service(
          id: widget.service?.id ?? '',
          name: _name.text.trim(),
          description: _desc.text.trim(),
          durationMin: int.parse(_duration.text),
          price: double.parse(_price.text.replaceAll(',', '.')),
          active: _active,
          sortOrder: widget.service?.sortOrder ?? widget.nextOrder,
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'Eliminare il servizio?',
        message: 'Gli appuntamenti già presi resteranno in agenda. In alternativa puoi solo nasconderlo.',
        confirm: 'Elimina',
        destructive: true);
    if (ok && mounted) Navigator.pop(context, _EditResult(delete: true));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.service == null ? 'Nuovo servizio' : 'Modifica servizio'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Nome (es. Taglio + Shampoo)'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Obbligatorio' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _desc,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Descrizione (facoltativa)'),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _duration,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Durata', suffixText: 'min'),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return n == null || n < 5 || n > 480 ? '5–480' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Prezzo', suffixText: '€'),
                      validator: (v) =>
                          double.tryParse((v ?? '').replaceAll(',', '.')) == null ? 'Non valido' : null,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Prenotabile dai clienti'),
                ),
              ]),
            ),
          ),
        ),
        actions: [
          if (widget.service != null)
            TextButton(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('Elimina'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            child: const Text('Salva'),
          ),
        ],
      );
}
