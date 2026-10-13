import 'package:flutter/material.dart';

import '../../data/slots.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Pannello per bloccare un orario dall'agenda (pausa, imprevisto...):
/// crea un'assenza breve del barbiere, cosi' l'orario non e' prenotabile.
/// Ritorna true se il blocco e' stato salvato.
Future<bool> showBlockTimeSheet(
  BuildContext context, {
  required DateTime day,
  required List<Barber> barbers,
  required List<Appointment> appointments,
  Barber? barber,
  int? startMin,
  int? endMin,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (c) => _BlockTimeSheet(
      day: day,
      barbers: barbers,
      appointments: appointments,
      barber: barber,
      startMin: startMin,
      endMin: endMin,
    ),
  );
  return r ?? false;
}

class _BlockTimeSheet extends StatefulWidget {
  const _BlockTimeSheet({
    required this.day,
    required this.barbers,
    required this.appointments,
    this.barber,
    this.startMin,
    this.endMin,
  });
  final DateTime day;
  final List<Barber> barbers;
  final List<Appointment> appointments;
  final Barber? barber;
  final int? startMin;
  final int? endMin;

  @override
  State<_BlockTimeSheet> createState() => _BlockTimeSheetState();
}

class _BlockTimeSheetState extends State<_BlockTimeSheet> {
  static const _reasons = ['Pausa', 'Imprevisto', 'Personale'];

  late Barber? _barber = widget.barber ?? (widget.barbers.length == 1 ? widget.barbers.first : null);
  late int _start = widget.startMin ?? _defaultStart();
  late int _end = widget.endMin ?? (_start + 30).clamp(0, 24 * 60);
  bool _allDay = false;
  String _reason = 'Pausa';
  final _custom = TextEditingController();
  bool _saving = false;

  int _defaultStart() {
    final now = DateTime.now();
    final m = dayOnly(now) == widget.day ? now.hour * 60 + now.minute : 9 * 60;
    return ((m + 14) ~/ 15) * 15; // prossimo quarto d'ora
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final m = start ? _start : _end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (m ~/ 60).clamp(0, 23), minute: m % 60),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return;
    setState(() {
      final v = t.hour * 60 + t.minute;
      if (start) {
        final len = _end - _start;
        _start = v;
        _end = (v + (len > 0 ? len : 30)).clamp(0, 24 * 60);
      } else {
        _end = v;
      }
    });
  }

  DateTime get _from => _allDay ? widget.day : DateTime(widget.day.year, widget.day.month, widget.day.day, 0, _start);
  DateTime get _to => _allDay
      ? DateTime(widget.day.year, widget.day.month, widget.day.day + 1)
      : DateTime(widget.day.year, widget.day.month, widget.day.day, 0, _end);

  /// Appuntamenti confermati che cadono nel blocco: restano validi, ma vanno gestiti.
  int get _clashes => _barber == null
      ? 0
      : widget.appointments
            .where((a) =>
                a.barberId == _barber!.id &&
                a.status == AppointmentStatus.confirmed &&
                a.start.isBefore(_to) &&
                a.end.isAfter(_from))
            .length;

  Future<void> _save() async {
    if (_barber == null) return showMessage(context, 'Scegli il barbiere', error: true);
    if (!_allDay && _end <= _start) return showMessage(context, 'L\'ora di fine deve essere dopo l\'inizio', error: true);
    setState(() => _saving = true);
    try {
      final reason = _reason == 'Altro' ? _custom.text.trim() : _reason;
      await AppScope.read(context).backend.addTimeOff(
        TimeOff(barberId: _barber!.id, start: _from, end: _to, reason: reason),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _timeButton(String label, int minutes, bool start) => Expanded(
    child: OutlinedButton(
      onPressed: _allDay ? null : () => _pick(start),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          Text(formatTime(minutes), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Blocca un orario', style: slab(size: 20, weight: FontWeight.w600, spacing: 0.4)),
            const SizedBox(height: 4),
            Text(
              '${fmtDayLong(widget.day)} · l\'orario non sarà prenotabile',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SectionTitle('Barbiere'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in widget.barbers)
                  ChoiceChip(
                    selected: _barber?.id == b.id,
                    onSelected: (_) => setState(() => _barber = b),
                    showCheckmark: false,
                    avatar: CircleAvatar(radius: 5, backgroundColor: barberColor(widget.barbers, b.id)),
                    label: Text(
                      b.name,
                      style: TextStyle(color: _barber?.id == b.id ? AppColors.black : AppColors.white),
                    ),
                  ),
              ],
            ),
            const SectionTitle('Orario'),
            Row(
              children: [
                _timeButton('Dalle', _start, true),
                const SizedBox(width: 10),
                _timeButton('Alle', _end, false),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _allDay,
              onChanged: (v) => setState(() => _allDay = v),
              title: const Text('Tutto il giorno'),
            ),
            const SectionTitle('Motivo'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in [..._reasons, 'Altro'])
                  ChoiceChip(
                    selected: _reason == r,
                    onSelected: (_) => setState(() => _reason = r),
                    showCheckmark: false,
                    label: Text(r, style: TextStyle(color: _reason == r ? AppColors.black : AppColors.white)),
                  ),
              ],
            ),
            if (_reason == 'Altro') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _custom,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Motivo', counterText: ''),
              ),
            ],
            if (_clashes > 0) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _clashes == 1
                          ? 'C\'è 1 appuntamento in questo orario: resta valido, spostalo o annullalo dall\'agenda.'
                          : 'Ci sono $_clashes appuntamenti in questo orario: restano validi, spostali o annullali dall\'agenda.',
                      style: const TextStyle(color: AppColors.warning, fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            PrimaryButton(label: 'Blocca orario', icon: Icons.block, loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
