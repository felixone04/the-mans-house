import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/slots.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Modifica barbiere: dati, orari settimanali e ferie/permessi.
class BarberEditorScreen extends StatefulWidget {
  const BarberEditorScreen({super.key, required this.barber});
  final Barber barber;

  @override
  State<BarberEditorScreen> createState() => _BarberEditorScreenState();
}

class _BarberEditorScreenState extends State<BarberEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final Barber _b = widget.barber;
  late final _name = TextEditingController(text: _b.name);
  late final _title = TextEditingController(text: _b.title);
  late final _photo = TextEditingController(text: _b.photoUrl ?? '');
  List<TimeOff> _timeOff = [];
  bool _saving = false;
  bool _changed = false;

  bool get _isNew => _b.id.isEmpty;

  @override
  void initState() {
    super.initState();
    if (!_isNew) WidgetsBinding.instance.addPostFrameCallback((_) => _loadTimeOff());
  }

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _photo.dispose();
    super.dispose();
  }

  Future<void> _loadTimeOff() async {
    try {
      final list = await AppScope.read(context).backend.fetchTimeOff(_b.id);
      if (mounted) setState(() => _timeOff = list);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    for (final h in _b.hours) {
      if (h.end <= h.start) {
        showMessage(
          context,
          '${weekdayNames[h.weekday - 1]}: l\'orario di fine deve essere dopo l\'inizio',
          error: true,
        );
        return;
      }
    }
    _b
      ..name = _name.text.trim()
      ..title = _title.text.trim()
      ..photoUrl = _photo.text.trim().isEmpty ? null : _photo.text.trim();
    setState(() => _saving = true);
    try {
      await AppScope.read(context).backend.saveBarber(_b);
      if (mounted) {
        showMessage(context, 'Barbiere salvato');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Eliminare ${_b.name}?',
      message: 'Se ha appuntamenti in archivio verrà solo disattivato.',
      confirm: 'Elimina',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).backend.deleteBarber(_b.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        showError(context, e);
        Navigator.of(context).pop(true);
      }
    }
  }

  Future<int?> _pickTime(int minutes) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  void _toggleDay(int weekday, bool on) {
    setState(() {
      if (on) {
        _b.hours.addAll([
          WorkingHours(weekday: weekday, start: 9 * 60, end: 13 * 60),
          WorkingHours(weekday: weekday, start: 15 * 60 + 30, end: 20 * 60),
        ]);
      } else {
        _b.hours.removeWhere((h) => h.weekday == weekday);
      }
    });
  }

  void _copyToAll(int weekday) {
    final src = _b.hoursFor(weekday);
    setState(() {
      for (var d = 1; d <= 7; d++) {
        if (d == weekday || _b.hoursFor(d).isEmpty) continue;
        _b.hours.removeWhere((h) => h.weekday == d);
        _b.hours.addAll(src.map((h) => WorkingHours(weekday: d, start: h.start, end: h.end)));
      }
    });
    showMessage(context, 'Orari copiati sugli altri giorni lavorativi');
  }

  Future<void> _addTimeOff() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Seleziona i giorni di assenza',
    );
    if (range == null || !mounted) return;
    final reason = TextEditingController(text: 'Ferie');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Motivo'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Es. Ferie, Permesso'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Aggiungi')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final s = range.start;
    final e = range.end;
    try {
      await AppScope.read(context).backend.addTimeOff(
        TimeOff(
          barberId: _b.id,
          start: DateTime(s.year, s.month, s.day),
          end: DateTime(e.year, e.month, e.day + 1),
          reason: reason.text.trim(),
        ),
      );
      _changed = true;
      await _loadTimeOff();
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  Future<void> _deleteTimeOff(TimeOff t) async {
    try {
      await AppScope.read(context).backend.deleteTimeOff(t.id);
      _changed = true;
      await _loadTimeOff();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: AppScaffold(
        title: _isNew ? 'Nuovo barbiere' : 'Modifica barbiere',
        actions: [
          if (!_isNew) IconButton(tooltip: 'Elimina', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
        body: SafeArea(
          child: Form(
            key: _form,
            child: Column(
              children: [
                Expanded(
                  child: FitBody(
                    maxWidth: 720,
                    alignment: Alignment.topCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _name,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(labelText: 'Nome'),
                                validator: (v) => (v ?? '').trim().isEmpty ? 'Obbligatorio' : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _title,
                                decoration: const InputDecoration(labelText: 'Ruolo'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _photo,
                                keyboardType: TextInputType.url,
                                decoration: const InputDecoration(labelText: 'Link foto (facoltativo)'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(value: _b.active, onChanged: (v) => setState(() => _b.active = v)),
                                const Text('Prenotabile', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                        const SectionTitle('Orari settimanali'),
                        GlassCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              for (var d = 1; d <= 7; d++) ...[if (d > 1) const Divider(height: 1), _dayRow(d)],
                            ],
                          ),
                        ),
                        if (!_isNew) ...[
                          SectionTitle(
                            'Ferie e permessi',
                            trailing: TextButton.icon(
                              onPressed: _addTimeOff,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Aggiungi'),
                            ),
                          ),
                          if (_timeOff.isEmpty)
                            const Text('Nessuna assenza programmata', style: TextStyle(color: AppColors.muted))
                          else
                            // al massimo 2 assenze (etichette brevi); se sono di piu' la prossima e "Tutte"
                            // in un pannello: con tante ferie la pagina si rimpiccioliva troppo
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final t in _timeOff.take(_timeOff.length > _maxOffChips ? 1 : _maxOffChips))
                                  _offChip(t),
                                if (_timeOff.length > _maxOffChips)
                                  ActionChip(
                                    label: Text(
                                      'Tutte (${_timeOff.length})',
                                      style: const TextStyle(fontSize: 12.5, color: AppColors.white),
                                    ),
                                    onPressed: _showAllTimeOff,
                                  ),
                              ],
                            ),
                        ] else
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'Salva il barbiere per poter aggiungere ferie e permessi.',
                              style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                ResponsiveCenter(
                  maxWidth: 720,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    child: PrimaryButton(label: 'Salva', loading: _saving, onPressed: _save),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _maxOffChips = 2;

  /// Periodo breve: "20 ott", "13–14 ott", "30 ott – 2 nov".
  String _offRange(TimeOff t) {
    final s = t.start;
    final e = t.end.subtract(const Duration(minutes: 1));
    final dm = DateFormat('d MMM', 'it_IT');
    if (dayOnly(s) == dayOnly(e)) return dm.format(s);
    if (s.month == e.month && s.year == e.year) return '${s.day}–${dm.format(e)}';
    return '${dm.format(s)} – ${dm.format(e)}';
  }

  Widget _offChip(TimeOff t) => InputChip(
    avatar: const Icon(Icons.beach_access_outlined, size: 16, color: AppColors.silver),
    label: Text(
      '${t.reason.isEmpty ? 'Assenza' : t.reason} · ${_offRange(t)}',
      style: const TextStyle(fontSize: 12.5, color: AppColors.silver),
    ),
    onDeleted: () => _deleteTimeOff(t),
  );

  /// Elenco completo delle assenze in un pannello dal basso.
  void _showAllTimeOff() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (c, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Center(
                child: Text('FERIE E PERMESSI', style: slab(size: 16, weight: FontWeight.w600, spacing: 2)),
              ),
              const SizedBox(height: 12),
              for (final t in _timeOff)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.beach_access_outlined, color: AppColors.silver),
                  title: Text(t.reason.isEmpty ? 'Assenza' : t.reason),
                  subtitle: Text(_offRange(t), style: const TextStyle(color: AppColors.muted)),
                  trailing: IconButton(
                    tooltip: 'Elimina',
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      await _deleteTimeOff(t);
                      setLocal(() {});
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Riga compatta del giorno: tocca per modificare le fasce.
  Widget _dayRow(int weekday) {
    final ranges = _b.hoursFor(weekday);
    final works = ranges.isNotEmpty;
    return InkWell(
      onTap: works ? () => _editDay(weekday) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 6, 2),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              child: Text(
                weekdayNames[weekday - 1],
                style: TextStyle(fontWeight: FontWeight.w700, color: works ? AppColors.white : AppColors.muted),
              ),
            ),
            // una fascia per riga se non c'e' spazio (prima a 360 px gli orari
            // del pomeriggio venivano troncati)
            Expanded(
              child: works
                  ? Wrap(
                      spacing: 12,
                      children: [
                        for (final h in ranges)
                          Text(
                            '${formatTime(h.start)}–${formatTime(h.end)}',
                            style: const TextStyle(color: AppColors.silver, fontSize: 13),
                          ),
                      ],
                    )
                  : const Text('Chiuso', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ),
            if (works) const Icon(Icons.edit_outlined, size: 16, color: AppColors.muted),
            // senza area di tocco extra: righe piu' basse, la pagina sta nello schermo
            Switch(
              value: works,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => _toggleDay(weekday, v),
            ),
          ],
        ),
      ),
    );
  }

  /// Modifica delle fasce di un giorno in un pannello.
  Future<void> _editDay(int weekday) async {
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) {
          final ranges = _b.hoursFor(weekday);
          void update(VoidCallback fn) {
            setState(fn);
            setLocal(() {});
          }

          return AlertDialog(
            title: Text(weekdayNames[weekday - 1]),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final h in ranges)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          _TimeButton(
                            label: formatTime(h.start),
                            onTap: () async {
                              final v = await _pickTime(h.start);
                              if (v != null) update(() => h.start = v);
                            },
                          ),
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('–')),
                          _TimeButton(
                            label: formatTime(h.end),
                            onTap: () async {
                              final v = await _pickTime(h.end);
                              if (v != null) update(() => h.end = v);
                            },
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Rimuovi fascia',
                            onPressed: () => update(() => _b.hours.remove(h)),
                            icon: const Icon(Icons.remove_circle_outline, color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  // Wrap: a 360 px i due pulsanti non stavano su una riga (overflow)
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: () => update(() {
                            final last = ranges.isEmpty ? 9 * 60 : ranges.last.end;
                            _b.hours.add(
                              WorkingHours(weekday: weekday, start: last, end: (last + 120).clamp(0, 24 * 60 - 1)),
                            );
                          }),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Aggiungi fascia'),
                        ),
                        if (ranges.isNotEmpty)
                          TextButton.icon(
                            onPressed: () {
                              _copyToAll(weekday);
                              setLocal(() {});
                            },
                            icon: const Icon(Icons.copy_all_outlined, size: 18),
                            label: const Text('Copia su tutti'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Fatto'))],
          );
        },
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
    ),
  );
}
