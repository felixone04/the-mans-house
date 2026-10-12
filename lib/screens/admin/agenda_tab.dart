import 'package:flutter/material.dart';

import '../../data/slots.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../booking_screen.dart';

/// Agenda giornaliera a calendario: una colonna per dipendente,
/// appuntamenti posizionati in base all'orario.
class AgendaTab extends StatefulWidget {
  const AgendaTab({super.key});

  @override
  State<AgendaTab> createState() => _AgendaTabState();
}

class _AgendaTabState extends State<AgendaTab> {
  DateTime _day = dayOnly(DateTime.now());
  List<Appointment> _items = [];
  Map<String, List<TimeOff>> _timeOff = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  DateTime get _nextDay => DateTime(_day.year, _day.month, _day.day + 1);

  Future<void> _load() async {
    setState(() => _loading = true);
    final state = AppScope.read(context);
    try {
      final results = await Future.wait([
        state.backend.appointmentsBetween(_day, _nextDay),
        for (final b in state.barbers) state.backend.fetchTimeOff(b.id),
      ]);
      _items = results.first as List<Appointment>;
      _timeOff = {
        for (var i = 0; i < state.barbers.length; i++)
          state.barbers[i].id: (results[i + 1] as List<TimeOff>)
              .where((t) => t.start.isBefore(_nextDay) && t.end.isAfter(_day))
              .toList(),
      };
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shift(int days) {
    _day = DateTime(_day.year, _day.month, _day.day + days);
    _load();
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) {
      _day = dayOnly(d);
      _load();
    }
  }

  /// Fascia oraria da mostrare: orari dei barbieri + eventuali appuntamenti fuori orario.
  (int, int) _range(List<Barber> barbers) {
    var start = 24 * 60, end = 0;
    for (final b in barbers) {
      for (final h in b.hoursFor(_day.weekday)) {
        if (h.start < start) start = h.start;
        if (h.end > end) end = h.end;
      }
    }
    for (final a in _items) {
      final s = a.start.hour * 60 + a.start.minute;
      final e = s + a.end.difference(a.start).inMinutes;
      if (s < start) start = s;
      if (e > end) end = e;
    }
    if (end <= start) return (9 * 60, 20 * 60);
    return ((start ~/ 60) * 60, ((end + 59) ~/ 60) * 60);
  }

  Future<void> _newAppointment({Barber? barber, DateTime? time}) async {
    final created = await Navigator.of(context).push<bool>(
      fadeRoute(BookingScreen(adminMode: true, initialDay: time ?? _day, initialBarber: barber, initialTime: time)),
    );
    if (created == true) _load();
  }

  Future<void> _setStatus(Appointment a, AppointmentStatus s) async {
    if (s == AppointmentStatus.cancelled) {
      final ok = await confirmDialog(
        context,
        title: 'Annullare l\'appuntamento?',
        message: '${a.customerName} · ${fmtTime(a.start)} · ${a.serviceName}',
        confirm: 'Annulla appuntamento',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    try {
      await AppScope.read(context).backend.setAppointmentStatus(a.id, s);
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _whatsApp(Appointment a) {
    final shop = AppScope.read(context).settings.name;
    final text =
        'Ciao ${a.customerName.split(' ').first}, ti ricordiamo l\'appuntamento da $shop '
        '${fmtDayLong(a.start).toLowerCase()} alle ${fmtTime(a.start)}'
        '${a.barberName.isEmpty ? '' : ' con ${a.barberName}'} (${a.serviceName}). A presto!';
    openWhatsApp(context, a.customerPhone, text);
  }

  void _openAppointment(Appointment a) {
    showModalBottomSheet<void>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 520),
      // su schermi bassi (es. 360x640) il contenuto superava l'altezza massima
      // predefinita del foglio (9/16 dello schermo): ora si adatta e scorre
      isScrollControlled: true,
      builder: (c) {
        void act(VoidCallback fn) {
          Navigator.pop(c);
          fn();
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          a.customerName.isEmpty ? 'Cliente' : a.customerName,
                          style: slab(size: 20, weight: FontWeight.w600, spacing: 0.4),
                        ),
                      ),
                      StatusBadge(a.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${fmtTime(a.start)} – ${fmtTime(a.end)} · ${a.serviceName} · ${fmtPrice(a.price)}',
                    style: const TextStyle(color: AppColors.silver),
                  ),
                  Text('con ${a.barberName}', style: const TextStyle(color: AppColors.silver)),
                  if (a.customerPhone.isNotEmpty) Text(a.customerPhone, style: const TextStyle(color: AppColors.muted)),
                  if (a.notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '“${a.notes}”',
                      style: const TextStyle(color: AppColors.silver, fontStyle: FontStyle.italic),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (a.customerPhone.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => act(() => _whatsApp(a)),
                            icon: const Icon(Icons.chat_outlined, size: 18),
                            label: const Text('Promemoria'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => act(() => callPhone(context, a.customerPhone)),
                            icon: const Icon(Icons.call_outlined, size: 18),
                            label: const Text('Chiama'),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  if (a.status == AppointmentStatus.confirmed) ...[
                    ListTile(
                      leading: const Icon(Icons.done_all),
                      title: const Text('Segna come completato'),
                      onTap: () => act(() => _setStatus(a, AppointmentStatus.completed)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_off_outlined),
                      title: const Text('Non presentato'),
                      onTap: () => act(() => _setStatus(a, AppointmentStatus.noShow)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.close, color: AppColors.danger),
                      title: const Text('Annulla appuntamento', style: TextStyle(color: AppColors.danger)),
                      onTap: () => act(() => _setStatus(a, AppointmentStatus.cancelled)),
                    ),
                  ] else if (a.status != AppointmentStatus.cancelled)
                    ListTile(
                      leading: const Icon(Icons.undo),
                      title: const Text('Ripristina come confermato'),
                      onTap: () => act(() => _setStatus(a, AppointmentStatus.confirmed)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final barbers = state.barbers;
    final active = _items.where(
      (a) => a.status == AppointmentStatus.confirmed || a.status == AppointmentStatus.completed,
    );
    final revenue = active.fold<double>(0, (s, a) => s + a.price);
    final isToday = _day == dayOnly(DateTime.now());

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          ResponsiveCenter(
            maxWidth: 1200,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _pickDay,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          Text(
                            fmtDayLong(_day),
                            textAlign: TextAlign.center,
                            style: slab(size: 17, weight: FontWeight.w600, spacing: 0.5),
                          ),
                          Text(
                            '${isToday ? 'Oggi · ' : ''}${active.length} appuntamenti · ${fmtPrice(revenue)}',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
                const SizedBox(width: 4),
                IconButton.filled(
                  tooltip: 'Nuovo appuntamento',
                  onPressed: () => _newAppointment(),
                  style: IconButton.styleFrom(backgroundColor: AppColors.white, foregroundColor: AppColors.black),
                  icon: const Icon(Icons.add),
                ),
                if (!isToday)
                  TextButton(
                    onPressed: () {
                      _day = dayOnly(DateTime.now());
                      _load();
                    },
                    child: const Text('Oggi'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : barbers.isEmpty
                ? const EmptyState(icon: Icons.badge_outlined, text: 'Aggiungi i barbieri dalla sezione Barbieri')
                : LayoutBuilder(
                    builder: (context, c) {
                      final range = _range(barbers);
                      final usable = c.maxHeight - _DayCalendar.headerH - 1 - 2 * _DayCalendar.topPad;
                      return _DayCalendar(
                        ppm: usable / (range.$2 - range.$1),
                        day: _day,
                        barbers: barbers,
                        appointments: _items.where((a) => a.status != AppointmentStatus.cancelled).toList(),
                        timeOff: _timeOff,
                        range: range,
                        onTapAppointment: _openAppointment,
                        onTapEmpty: (b, t) => _newAppointment(barber: b, time: t),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Griglia oraria: colonne = dipendenti, righe = orari.
class _DayCalendar extends StatelessWidget {
  const _DayCalendar({
    required this.day,
    required this.barbers,
    required this.appointments,
    required this.timeOff,
    required this.range,
    required this.ppm,
    required this.onTapAppointment,
    required this.onTapEmpty,
  });

  static const headerH = 46.0;
  static const gutter = 52.0;
  static const topPad = 10.0;
  static const minColumn = 96.0;
  static const minBlock = 16.0;

  final DateTime day;
  final List<Barber> barbers;
  final List<Appointment> appointments;
  final Map<String, List<TimeOff>> timeOff;
  final (int, int) range;

  /// Pixel per minuto: calcolato per far stare tutta la giornata senza scorrere.
  final double ppm;
  final ValueChanged<Appointment> onTapAppointment;
  final void Function(Barber, DateTime) onTapEmpty;

  double _y(int minute) => topPad + (minute - range.$1) * ppm;
  int _minuteOf(DateTime d) => d.hour * 60 + d.minute;

  @override
  Widget build(BuildContext context) {
    final height = _y(range.$2) + topPad;
    return LayoutBuilder(
      builder: (context, c) {
        final colW = ((c.maxWidth - gutter - 12) / barbers.length).clamp(minColumn, 420.0);
        final totalW = gutter + colW * barbers.length + 12;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalW < c.maxWidth ? c.maxWidth : totalW,
            child: Column(
              children: [
                // Intestazione con i dipendenti
                SizedBox(
                  height: headerH,
                  child: Row(
                    children: [
                      const SizedBox(width: gutter),
                      for (final b in barbers)
                        SizedBox(
                          width: colW,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // colonne strette: solo il nome, cosi' si legge per intero
                                if (colW >= 130) ...[BarberAvatar(barber: b, size: 30), const SizedBox(width: 8)],
                                Flexible(
                                  child: Text(
                                    b.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: SizedBox(
                    height: height,
                    child: Stack(
                      children: [
                        // Linee delle ore e delle mezz'ore
                        for (var m = range.$1; m <= range.$2; m += 30)
                          Positioned(
                            top: _y(m),
                            left: m % 60 == 0 ? gutter - 6 : gutter,
                            right: 0,
                            child: Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: m % 60 == 0 ? 0.10 : 0.04),
                            ),
                          ),
                        for (var m = range.$1; m < range.$2; m += 60)
                          Positioned(
                            top: _y(m) - 8,
                            left: 0,
                            width: gutter - 10,
                            child: Text(
                              formatTime(m),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        for (var i = 0; i < barbers.length; i++)
                          Positioned(
                            top: 0,
                            bottom: 0,
                            left: gutter + i * colW,
                            width: colW,
                            child: _column(context, barbers[i]),
                          ),
                        if (dayOnly(DateTime.now()) == day) _nowLine(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _nowLine() {
    final m = _minuteOf(DateTime.now());
    // deve restare Positioned: un figlio non posizionato ridimensionerebbe lo Stack a zero
    if (m < range.$1 || m > range.$2) return const Positioned(top: 0, left: 0, child: SizedBox.shrink());
    return Positioned(
      top: _y(m) - 4,
      left: gutter - 4,
      right: 0,
      child: IgnorePointer(
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
            ),
            Expanded(child: Container(height: 1.5, color: AppColors.danger)),
          ],
        ),
      ),
    );
  }

  /// Altezza del blocco: almeno [minBlock] per leggere l'orario, ma senza
  /// coprire l'appuntamento successivo (servizi brevi a schermo piccolo).
  double _blockHeight(List<Appointment> mine, int i) {
    final a = mine[i];
    final top = _y(_minuteOf(a.start)) + 1;
    var h = a.end.difference(a.start).inMinutes * ppm - 2;
    if (h < minBlock) h = minBlock;
    if (i + 1 < mine.length) {
      final room = _y(_minuteOf(mine[i + 1].start)) - top - 1;
      if (room >= 8 && h > room) h = room;
    }
    return h;
  }

  Widget _column(BuildContext context, Barber b) {
    final mine = appointments.where((a) => a.barberId == b.id).toList()..sort((x, y) => x.start.compareTo(y.start));
    final off = timeOff[b.id] ?? [];

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (d) {
        final minute = range.$1 + ((d.localPosition.dy - topPad) / ppm).floor();
        final rounded = (minute ~/ 15) * 15;
        final works = b.hoursFor(day.weekday).any((h) => rounded >= h.start && rounded < h.end);
        if (!works) return;
        onTapEmpty(b, DateTime(day.year, day.month, day.day, 0, rounded));
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
          // fuori orario: sfondo scuro
          color: Colors.black.withValues(alpha: 0.35),
        ),
        child: Stack(
          children: [
            // Fasce di lavoro
            for (final h in b.hoursFor(day.weekday))
              Positioned(
                top: _y(h.start),
                height: (h.end - h.start) * ppm,
                left: 0,
                right: 0,
                child: Container(color: Colors.white.withValues(alpha: 0.035)),
              ),
            // Ferie / permessi
            for (final t in off)
              () {
                final s = t.start.isBefore(day) ? range.$1 : _minuteOf(t.start).clamp(range.$1, range.$2);
                final e = !t.end.isBefore(DateTime(day.year, day.month, day.day + 1))
                    ? range.$2
                    : _minuteOf(t.end).clamp(range.$1, range.$2);
                return Positioned(
                  top: _y(s),
                  height: (e - s) * ppm,
                  left: 3,
                  right: 3,
                  child: Container(
                    alignment: Alignment.topCenter,
                    padding: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      t.reason.isEmpty ? 'Assente' : t.reason,
                      style: const TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                );
              }(),
            // Appuntamenti
            for (var i = 0; i < mine.length; i++)
              Positioned(
                top: _y(_minuteOf(mine[i].start)) + 1,
                height: _blockHeight(mine, i),
                left: 3,
                right: 3,
                child: _AppointmentBlock(appointment: mine[i], onTap: () => onTapAppointment(mine[i])),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentBlock extends StatelessWidget {
  const _AppointmentBlock({required this.appointment, required this.onTap});
  final Appointment appointment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final (bg, fg, sub) = switch (a.status) {
      AppointmentStatus.confirmed => (AppColors.white, AppColors.black, const Color(0xFF555555)),
      AppointmentStatus.completed => (AppColors.steel, AppColors.white, AppColors.silver),
      AppointmentStatus.noShow => (AppColors.warning.withValues(alpha: 0.25), AppColors.white, AppColors.silver),
      AppointmentStatus.cancelled => (AppColors.graphite, AppColors.muted, AppColors.muted),
    };

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, c) {
            final roomy = c.maxHeight >= 44;
            // blocchi bassi (servizi brevi, schermi piccoli): una sola riga
            // centrata, con il testo ridotto all'altezza disponibile
            final size = roomy ? 12.0 : (c.maxHeight - 3).clamp(8.0, 12.0);
            final line = Row(
              children: [
                Text(
                  fmtTime(a.start),
                  style: TextStyle(color: fg, fontSize: size - 0.5, height: 1.1, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    a.customerName.isEmpty ? 'Cliente' : a.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontSize: size, height: 1.1, fontWeight: FontWeight.w700),
                  ),
                ),
                if (a.status == AppointmentStatus.completed) Icon(Icons.check, size: size + 1, color: fg),
              ],
            );
            if (!roomy) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Align(alignment: Alignment.centerLeft, child: line),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  line,
                  if (roomy)
                    Text(
                      a.serviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: sub, fontSize: 11.5),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
