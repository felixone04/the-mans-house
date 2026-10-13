import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/slots.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Chiusure (ferie, festivita') e orari speciali di tutto il negozio.
class ShopDaysScreen extends StatefulWidget {
  const ShopDaysScreen({super.key});

  @override
  State<ShopDaysScreen> createState() => _ShopDaysScreenState();
}

/// Giorni consecutivi con la stessa chiusura, mostrati come un'unica voce.
class _Group {
  _Group(this.days);
  final List<ShopDay> days;
  ShopDay get first => days.first;
  DateTime get from => days.first.day;
  DateTime get to => days.last.day;
}

class _ShopDaysScreenState extends State<ShopDaysScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      await AppScope.read(context).refreshShopDays();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  List<_Group> _groups(List<ShopDay> all) {
    final today = dayOnly(DateTime.now());
    final upcoming = all.where((d) => !d.day.isBefore(today)).toList()..sort((a, b) => a.day.compareTo(b.day));
    final groups = <_Group>[];
    for (final d in upcoming) {
      final last = groups.isEmpty ? null : groups.last;
      final consecutive = last != null && last.to.add(const Duration(days: 1)) == d.day;
      if (consecutive && d.closed && last.first.closed && last.first.note == d.note) {
        last.days.add(d);
      } else {
        groups.add(_Group([d]));
      }
    }
    return groups;
  }

  String _range(_Group g) {
    final f = DateFormat('EEE d MMM', 'it_IT');
    return g.days.length == 1 ? capitalize(f.format(g.from)) : '${capitalize(f.format(g.from))} – ${f.format(g.to)}';
  }

  Future<void> _save(List<ShopDay> days) async {
    setState(() => _busy = true);
    final state = AppScope.read(context);
    try {
      await state.backend.saveShopDays(days);
      await state.refreshShopDays();
      // gli appuntamenti gia' presi in quei giorni restano: lo segnaliamo
      final from = days.first.day;
      final to = days.last.day.add(const Duration(days: 1));
      final appts = await state.backend.appointmentsBetween(from, to);
      final clashes = appts.where((a) {
        if (a.status != AppointmentStatus.confirmed) return false;
        final b = state.barbers.where((x) => x.id == a.barberId).firstOrNull;
        if (b == null) return false;
        final s = minuteOfDay(a.start), e = s + a.end.difference(a.start).inMinutes;
        return !b.hoursOn(a.start).any((h) => s >= h.start && e <= h.end);
      }).length;
      if (!mounted) return;
      showMessage(
        context,
        clashes == 0
            ? 'Salvato'
            : 'Salvato. Attenzione: $clashes ${clashes == 1 ? 'appuntamento resta' : 'appuntamenti restano'} '
                  'fuori orario in quei giorni, spostali o annullali dall\'agenda.',
        error: clashes > 0,
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addClosure() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: dayOnly(now),
      lastDate: DateTime(now.year + 2),
      helpText: 'Giorni di chiusura',
    );
    if (range == null || !mounted) return;
    final reason = await _askNote('Motivo della chiusura', const ['Ferie', 'Festività', 'Chiusura straordinaria']);
    if (reason == null) return;
    final days = [
      for (var d = dayOnly(range.start); !d.isAfter(range.end); d = DateTime(d.year, d.month, d.day + 1))
        ShopDay(day: d, note: reason),
    ];
    await _save(days);
  }

  Future<void> _addSpecialHours() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      firstDate: dayOnly(now),
      lastDate: DateTime(now.year + 2),
      helpText: 'Giorno con orario speciale',
    );
    if (day == null || !mounted) return;
    final result = await showModalBottomSheet<ShopDay>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => _SpecialHoursSheet(day: day),
    );
    if (result != null) await _save([result]);
  }

  Future<String?> _askNote(String title, List<String> suggestions) {
    final ctrl = TextEditingController(text: suggestions.first);
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in suggestions)
                    ChoiceChip(
                      label: Text(s, style: TextStyle(color: ctrl.text == s ? AppColors.black : AppColors.white)),
                      selected: ctrl.text == s,
                      showCheckmark: false,
                      onSelected: (_) => setLocal(() => ctrl.text = s),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLength: 60,
                onChanged: (_) => setLocal(() {}),
                decoration: const InputDecoration(labelText: 'Motivo (si vede nell\'app)', counterText: ''),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Salva')),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(_Group g) async {
    final ok = await confirmDialog(
      context,
      title: 'Eliminare?',
      message: '${_range(g)} · ${g.first.closed ? 'Chiuso' : 'Orario speciale'}\nTornano gli orari abituali.',
      confirm: 'Elimina',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final state = AppScope.read(context);
    try {
      for (final d in g.days) {
        await state.backend.deleteShopDay(d.day);
      }
      await state.refreshShopDays();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final groups = _groups(state.shopDays);
    String barberNames(ShopDay d) => d.barberIds.isEmpty
        ? 'tutti i barbieri'
        : state.barbers.where((b) => d.barberIds.contains(b.id)).map((b) => b.name).join(', ');

    return AppScaffold(
      title: 'Chiusure e orari',
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                children: [
                  ResponsiveCenter(
                    maxWidth: 640,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Valgono per tutto il negozio: nei giorni chiusi non si può prenotare, '
                          'negli orari speciali si prenota solo in quella fascia.',
                          style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 14),
                        if (groups.isEmpty)
                          const EmptyState(icon: Icons.event_available, text: 'Nessuna chiusura in programma'),
                        for (final g in groups)
                          GlassCard(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                            child: Row(
                              children: [
                                Icon(
                                  g.first.closed ? Icons.door_front_door_outlined : Icons.schedule,
                                  color: g.first.closed ? AppColors.warning : AppColors.success,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _range(g),
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                      ),
                                      Text(
                                        g.first.closed
                                            ? 'Chiuso${g.first.note.isEmpty ? '' : ' · ${g.first.note}'}'
                                            : '${formatTime(g.first.open!)} – ${formatTime(g.first.close!)} · '
                                                  '${barberNames(g.first)}${g.first.note.isEmpty ? '' : ' · ${g.first.note}'}',
                                        style: TextStyle(
                                          color: g.first.closed ? AppColors.warning : AppColors.silver,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Elimina',
                                  onPressed: _busy ? null : () => _delete(g),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ResponsiveCenter(
              maxWidth: 640,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12, top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _addSpecialHours,
                        icon: const Icon(Icons.schedule, size: 18),
                        label: const Text('Orario speciale'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _addClosure,
                        icon: const Icon(Icons.door_front_door_outlined, size: 18),
                        label: const Text('Chiusura'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

int minuteOfDay(DateTime d) => d.hour * 60 + d.minute;

/// Orario speciale di un giorno: fascia oraria, barbieri al lavoro e nota.
class _SpecialHoursSheet extends StatefulWidget {
  const _SpecialHoursSheet({required this.day});
  final DateTime day;

  @override
  State<_SpecialHoursSheet> createState() => _SpecialHoursSheetState();
}

class _SpecialHoursSheetState extends State<_SpecialHoursSheet> {
  int _open = 9 * 60;
  int _close = 13 * 60;
  final _selected = <String>{}; // vuoto = tutti
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(bool open) async {
    final m = open ? _open : _close;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return;
    setState(() => open ? _open = t.hour * 60 + t.minute : _close = t.hour * 60 + t.minute);
  }

  @override
  Widget build(BuildContext context) {
    final barbers = AppScope.of(context).barbers;
    Widget time(String label, int m, bool open) => Expanded(
      child: OutlinedButton(
        onPressed: () => _pick(open),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            Text(formatTime(m), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Orario speciale', style: slab(size: 20, weight: FontWeight.w600, spacing: 0.4)),
            Text(fmtDayLong(widget.day), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SectionTitle('Orario'),
            Row(children: [time('Apre', _open, true), const SizedBox(width: 10), time('Chiude', _close, false)]),
            const SectionTitle('Chi lavora'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  selected: _selected.isEmpty,
                  showCheckmark: false,
                  label: Text('Tutti', style: TextStyle(color: _selected.isEmpty ? AppColors.black : AppColors.white)),
                  onSelected: (_) => setState(_selected.clear),
                ),
                for (final b in barbers)
                  FilterChip(
                    selected: _selected.contains(b.id),
                    showCheckmark: false,
                    avatar: CircleAvatar(radius: 5, backgroundColor: barberColor(barbers, b.id)),
                    label: Text(
                      b.name,
                      style: TextStyle(color: _selected.contains(b.id) ? AppColors.black : AppColors.white),
                    ),
                    onSelected: (v) => setState(() => v ? _selected.add(b.id) : _selected.remove(b.id)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Nota (facoltativa)', hintText: 'Es. apertura natalizia'),
            ),
            const SizedBox(height: 8),
            PrimaryButton(
              label: 'Salva',
              onPressed: () {
                if (_close <= _open) {
                  showMessage(context, 'L\'orario di chiusura deve essere dopo l\'apertura', error: true);
                  return;
                }
                Navigator.pop(
                  context,
                  ShopDay(
                    day: widget.day,
                    open: _open,
                    close: _close,
                    note: _note.text.trim(),
                    barberIds: _selected.toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
