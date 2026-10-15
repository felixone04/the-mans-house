import 'package:flutter/material.dart';

import '../../data/slots.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Cliente entrato senza appuntamento: si sceglie il servizio e il barbiere
/// (o il primo libero) e viene inserito nel primo orario libero da adesso.
/// Ritorna true se l'appuntamento e' stato inserito.
Future<bool> showWalkInSheet(BuildContext context, {Barber? barber}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => _WalkInSheet(barber: barber),
  );
  return r ?? false;
}

class _WalkInSheet extends StatefulWidget {
  const _WalkInSheet({this.barber});
  final Barber? barber;

  @override
  State<_WalkInSheet> createState() => _WalkInSheetState();
}

class _WalkInSheetState extends State<_WalkInSheet> {
  Service? _service;
  late Barber? _barber = widget.barber; // null = primo libero
  final _name = TextEditingController();
  final _phone = TextEditingController(text: '+39 ');
  List<BusyInterval>? _busy;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBusy());
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadBusy() async {
    final today = dayOnly(DateTime.now());
    try {
      final busy = await AppScope.read(context).backend.fetchBusy(today, today.add(const Duration(days: 1)));
      if (mounted) setState(() => _busy = busy);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Primo orario libero da adesso (passo di 5 minuti) e barbiere assegnato.
  (DateTime, Barber)? get _slot {
    final s = _service;
    final busy = _busy;
    if (s == null || busy == null) return null;
    final state = AppScope.read(context);
    final today = dayOnly(DateTime.now());
    if (_barber != null) {
      final slots = availableSlots(barber: _barber!, durationMin: s.durationMin, day: today, busy: busy, stepMin: 5);
      return slots.isEmpty ? null : (slots.first, _barber!);
    }
    final any = availableSlotsAnyBarber(
      barbers: state.barbers,
      durationMin: s.durationMin,
      day: today,
      busy: busy,
      stepMin: 5,
    );
    return any.isEmpty ? null : (any.keys.first, any.values.first);
  }

  Future<void> _save() async {
    final slot = _slot;
    if (slot == null) return;
    setState(() => _saving = true);
    try {
      final name = _name.text.trim();
      await AppScope.read(context).backend.book(
        barberId: slot.$2.id,
        serviceId: _service!.id,
        start: slot.$1,
        customerName: name.isEmpty ? 'Cliente al banco' : name,
        customerPhone: isValidPhone(_phone.text) ? _phone.text.trim() : '',
      );
      if (!mounted) return;
      showMessage(context, '${name.isEmpty ? 'Cliente' : name} inserito alle ${fmtTime(slot.$1)} con ${slot.$2.name}');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showError(context, e);
      // l'orario potrebbe essere appena stato preso: ricalcola
      await _loadBusy();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Una sola riga scorrevole: il pannello resta corto e "Inserisci" sempre in vista.
  Widget _row(List<Widget> chips) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [for (final c in chips) Padding(padding: const EdgeInsets.only(right: 8), child: c)],
    ),
  );

  Widget _chip(String label, bool selected, VoidCallback onTap, {Color? dot}) => ChoiceChip(
    selected: selected,
    onSelected: (_) => onTap(),
    showCheckmark: false,
    avatar: dot == null ? null : CircleAvatar(radius: 5, backgroundColor: dot),
    label: Text(label, style: TextStyle(color: selected ? AppColors.black : AppColors.white)),
  );

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final slot = _slot;
    final now = DateTime.now();

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cliente entrato ora', style: slab(size: 20, weight: FontWeight.w600, spacing: 0.4)),
            const SizedBox(height: 2),
            const Text(
              'Viene inserito nel primo orario libero da adesso.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SectionTitle('Servizio'),
            _row([
              for (final s in state.services)
                _chip(
                  '${s.name} · ${fmtDuration(s.durationMin)}',
                  _service?.id == s.id,
                  () => setState(() => _service = s),
                ),
            ]),
            const SectionTitle('Barbiere'),
            _row([
              _chip('Primo libero', _barber == null, () => setState(() => _barber = null)),
              for (final b in state.barbers)
                _chip(
                  b.name,
                  _barber?.id == b.id,
                  () => setState(() => _barber = b),
                  dot: barberColor(state.barbers, b.id),
                ),
            ]),
            const SectionTitle('Cliente'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nome (facoltativo)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Cellulare'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // anteprima dell'orario trovato
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.quietBorder),
              ),
              child: _service == null
                  ? const Text('Scegli il servizio', style: TextStyle(color: AppColors.muted))
                  : _busy == null
                  ? const Text('Cerco il primo orario libero…', style: TextStyle(color: AppColors.muted))
                  : slot == null
                  ? const Text(
                      'Nessun orario libero oggi per questo servizio.',
                      style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700),
                    )
                  : Row(
                      children: [
                        Text(fmtTime(slot.$1), style: slab(size: 28, weight: FontWeight.w700, spacing: 0)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'con ${slot.$2.name}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                              Text(
                                slot.$1.difference(now).inMinutes <= 5
                                    ? 'subito'
                                    : 'tra ${fmtDuration(slot.$1.difference(now).inMinutes)}',
                                style: const TextStyle(color: AppColors.silver, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Inserisci',
              icon: Icons.login,
              loading: _saving,
              onPressed: slot == null ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
