import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/slots.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'agenda_actions.dart';
import 'barber_day_screen.dart';
import 'walk_in_sheet.dart';

int _minuteOf(DateTime d) => d.hour * 60 + d.minute;

/// Agenda giornaliera. Due viste:
///  - elenco (predefinito su telefono): appuntamenti in ordine di orario,
///    spazi liberi, blocchi e linea dell'ora attuale;
///  - griglia (predefinita su tablet/computer): una colonna per barbiere.
/// In alto la settimana (con il numero di appuntamenti) e il filtro per barbiere.
class AgendaTab extends StatefulWidget {
  const AgendaTab({super.key, this.initialDay});

  /// Giorno mostrato all'apertura (predefinito: oggi).
  final DateTime? initialDay;

  @override
  State<AgendaTab> createState() => _AgendaTabState();
}

class _AgendaTabState extends State<AgendaTab> with AgendaActions {
  late DateTime _day = dayOnly(widget.initialDay ?? DateTime.now());
  DateTime? _loadedWeek;
  List<Appointment> _week = []; // appuntamenti della settimana mostrata
  Map<String, List<TimeOff>> _timeOff = {};
  bool _loading = true;
  bool? _grid; // null: deciso in base alla larghezza dello schermo
  String? _filter; // griglia: id del barbiere mostrato, null = tutti
  int _scrollToken = 0; // cambia quando la griglia deve tornare all'ora attuale

  @override
  DateTime get agendaDay => _day;

  @override
  List<Appointment> get agendaDayAppointments => _dayItems;

  @override
  Future<void> reloadAgenda() => _load(silent: true);

  Future<void> _openBarber(Barber b) async {
    await Navigator.of(context).push(fadeRoute(BarberDayScreen(barber: b, day: _day)));
    if (mounted) _load(silent: true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  DateTime get _weekStart => DateTime(_day.year, _day.month, _day.day - (_day.weekday - 1));
  DateTime get _nextDay => DateTime(_day.year, _day.month, _day.day + 1);

  List<Appointment> get _dayItems => _week.where((a) => dayOnly(a.start) == _day).toList();

  /// Ferie e blocchi del giorno, per barbiere.
  Map<String, List<TimeOff>> get _dayOff => {
    for (final e in _timeOff.entries)
      e.key: e.value.where((t) => t.start.isBefore(_nextDay) && t.end.isAfter(_day)).toList(),
  };

  /// [silent]: aggiorna senza indicatore di caricamento (azioni rapide).
  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final state = AppScope.read(context);
    final from = _weekStart;
    try {
      final results = await Future.wait([
        state.backend.appointmentsBetween(from, DateTime(from.year, from.month, from.day + 7)),
        for (final b in state.barbers) state.backend.fetchTimeOff(b.id),
      ]);
      _week = results.first as List<Appointment>;
      _timeOff = {for (var i = 0; i < state.barbers.length; i++) state.barbers[i].id: results[i + 1] as List<TimeOff>};
      _loadedWeek = from;
      if (!silent) _scrollToken++;
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setDay(DateTime d) {
    _day = dayOnly(d);
    if (_loadedWeek != _weekStart) {
      _load();
    } else {
      setState(() => _scrollToken++);
    }
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) _setDay(d);
  }

  /// Fascia oraria della griglia: orari dei barbieri + eventuali appuntamenti fuori orario.
  (int, int) _range(List<Barber> barbers, List<Appointment> items) {
    var start = 24 * 60, end = 0;
    for (final b in barbers) {
      for (final h in b.hoursFor(_day.weekday)) {
        if (h.start < start) start = h.start;
        if (h.end > end) end = h.end;
      }
    }
    for (final a in items) {
      final s = _minuteOf(a.start);
      final e = s + a.end.difference(a.start).inMinutes;
      if (s < start) start = s;
      if (e > end) end = e;
    }
    if (end <= start) return (9 * 60, 20 * 60);
    return ((start ~/ 60) * 60, ((end + 59) ~/ 60) * 60);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final barbers = state.barbers;
    // stessa agenda su telefono, tablet e computer; la griglia resta a scelta
    _grid ??= false;
    final grid = _grid!;
    if (_filter != null && !barbers.any((b) => b.id == _filter)) _filter = null;
    final shown = _filter == null ? barbers : barbers.where((b) => b.id == _filter).toList();
    final shownIds = shown.map((b) => b.id).toSet();
    final active = _dayItems.where((a) => a.status != AppointmentStatus.cancelled).toList();
    final dayAppts = active.where((a) => shownIds.contains(a.barberId)).toList();

    final header = ResponsiveCenter(
      maxWidth: grid ? 1200 : _BarberPanels.wideMaxWidth,
      // vista barbieri: tutto allineato a sinistra, come i riquadri sotto
      alignment: grid ? Alignment.topCenter : Alignment.topLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: _AgendaHeader(
        day: _day,
        weekStart: _weekStart,
        week: _week,
        barbers: barbers,
        filter: grid ? _filter : null,
        grid: grid,
        light: !grid,
        onDay: _setDay,
        onPickDay: _pickDay,
        onFilter: (id) => setState(() => _filter = id),
        onToggleView: () => setState(() {
          _grid = !grid;
          _scrollToken++;
        }),
        onNew: () => newAppointment(),
        onBlock: () => blockTime(barber: grid && shown.length == 1 ? shown.first : null),
        onWalkIn: () async {
          if (await showWalkInSheet(context, barber: grid && shown.length == 1 ? shown.first : null)) {
            _load(silent: true);
          }
        },
      ),
    );

    final Widget body;
    if (_loading) {
      body = Center(child: CircularProgressIndicator(color: grid ? null : AgendaLight.ink));
    } else if (barbers.isEmpty) {
      body = const EmptyState(icon: Icons.badge_outlined, text: 'Aggiungi i barbieri dalla sezione Barbieri');
    } else if (grid) {
      body = LayoutBuilder(
        builder: (context, c) {
          final range = _range(shown, dayAppts);
          final usable = c.maxHeight - _DayCalendar.headerH - 1 - 2 * _DayCalendar.topPad;
          // almeno 1,3 px al minuto: su telefono la griglia scorre
          // in verticale invece di schiacciare gli appuntamenti
          final fit = usable / (range.$2 - range.$1);
          return _DayCalendar(
            key: ValueKey('grid$_scrollToken'),
            ppm: fit < 1.3 ? 1.3 : fit,
            day: _day,
            barbers: shown,
            allBarbers: barbers,
            appointments: dayAppts,
            timeOff: _dayOff,
            range: range,
            onTapAppointment: openAppointment,
            onTapEmpty: (b, t) => newAppointment(barber: b, time: t),
            onLongPressEmpty: (b, m) => blockTime(barber: b, start: m, end: m + 30),
            onTapTimeOff: removeBlock,
          );
        },
      );
    } else {
      body = _BarberPanels(barbers: barbers, onOpen: _openBarber);
    }

    // telefono: agenda su fondo chiaro, a foglio
    if (!grid) {
      return Container(
        margin: const EdgeInsets.only(top: 4),
        decoration: const BoxDecoration(
          color: AgendaLight.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 6),
            header,
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          header,
          Expanded(child: body),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Intestazione: settimana, riepilogo, filtro barbieri
// ---------------------------------------------------------------------------

class _AgendaHeader extends StatelessWidget {
  const _AgendaHeader({
    required this.day,
    required this.weekStart,
    required this.week,
    required this.barbers,
    required this.filter,
    required this.grid,
    this.light = false,
    required this.onDay,
    required this.onPickDay,
    required this.onFilter,
    required this.onToggleView,
    required this.onNew,
    required this.onBlock,
    required this.onWalkIn,
  });

  final DateTime day;
  final DateTime weekStart;
  final List<Appointment> week;
  final List<Barber> barbers;
  final String? filter;
  final bool grid;

  /// Colori chiari (agenda da telefono).
  final bool light;
  final ValueChanged<DateTime> onDay;
  final VoidCallback onPickDay;
  final ValueChanged<String?> onFilter;
  final VoidCallback onToggleView;
  final VoidCallback onNew;
  final VoidCallback onBlock;
  final VoidCallback onWalkIn;

  bool _counts(Appointment a) => a.status != AppointmentStatus.cancelled && (filter == null || a.barberId == filter);

  @override
  Widget build(BuildContext context) {
    final today = dayOnly(DateTime.now());
    final days = [for (var i = 0; i < 7; i++) DateTime(weekStart.year, weekStart.month, weekStart.day + i)];
    final dayList = week.where((a) => dayOnly(a.start) == day && _counts(a)).toList();
    final active = dayList.where((a) => a.status != AppointmentStatus.noShow);
    final revenue = active.fold<double>(0, (s, a) => s + a.price);
    final now = DateTime.now();
    final next = day == today
        ? (dayList.where((a) => a.status == AppointmentStatus.confirmed && a.start.isAfter(now)).toList()
                ..sort((a, b) => a.start.compareTo(b.start)))
              .firstOrNull
        : null;
    const compact = VisualDensity(horizontal: -2, vertical: -2);
    final ink = light ? AgendaLight.ink : AppColors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              visualDensity: compact,
              tooltip: 'Settimana precedente',
              onPressed: () => onDay(DateTime(day.year, day.month, day.day - 7)),
              icon: Icon(Icons.chevron_left, color: ink),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onPickDay,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          capitalize(DateFormat('MMMM yyyy', 'it_IT').format(day)),
                          style: slab(size: 16, weight: FontWeight.w600, spacing: 0.5, color: ink),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.expand_more, size: 18, color: AppColors.muted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              visualDensity: compact,
              tooltip: 'Settimana successiva',
              onPressed: () => onDay(DateTime(day.year, day.month, day.day + 7)),
              icon: Icon(Icons.chevron_right, color: ink),
            ),
            if (day != today)
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: compact,
                  foregroundColor: light ? AgendaLight.ink : null,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => onDay(today),
                child: const Text('Oggi'),
              ),
            IconButton(
              visualDensity: compact,
              tooltip: grid ? 'Vista barbieri' : 'Vista griglia',
              onPressed: onToggleView,
              icon: Icon(grid ? Icons.view_agenda_outlined : Icons.view_week_outlined, size: 21, color: ink),
            ),
            PopupMenuButton<int>(
              tooltip: 'Aggiungi',
              position: PopupMenuPosition.under,
              color: AppColors.graphite,
              onSelected: (v) => switch (v) {
                0 => onNew(),
                1 => onBlock(),
                _ => onWalkIn(),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 2,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.login),
                    title: Text('Cliente entrato ora'),
                  ),
                ),
                PopupMenuItem(
                  value: 0,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.event_available),
                    title: Text('Nuovo appuntamento'),
                  ),
                ),
                PopupMenuItem(
                  value: 1,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.block),
                    title: Text('Blocca un orario'),
                  ),
                ),
              ],
              child: Container(
                width: 38,
                height: 38,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(color: light ? AgendaLight.ink : AppColors.white, shape: BoxShape.circle),
                child: Icon(Icons.add, color: light ? Colors.white : AppColors.black),
              ),
            ),
          ],
        ),
        // Settimana: tocca un giorno; il numero indica gli appuntamenti
        Row(
          children: [
            for (var i = 0; i < 7; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Expanded(
                child: _WeekDay(
                  day: days[i],
                  selected: days[i] == day,
                  today: days[i] == today,
                  count: light ? 0 : week.where((a) => dayOnly(a.start) == days[i] && _counts(a)).length,
                  light: light,
                  open: barbers.any(
                    (b) => (filter == null || b.id == filter) && b.hoursFor(days[i].weekday).isNotEmpty,
                  ),
                  onTap: () => onDay(days[i]),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // telefono: nessun dettaglio prima di aprire il barbiere
        if (!light)
          Text(
            [
              // il giorno e' gia' evidenziato nella settimana
              '${active.length} ${active.length == 1 ? 'appuntamento' : 'appuntamenti'}',
              fmtPrice(revenue),
              if (next != null) 'prossimo alle ${fmtTime(next.start)}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.silver, fontSize: 12.5),
          ),
        // filtro solo in griglia: nelle corsie si sceglie il barbiere dalle schede
        if (grid && barbers.length > 1) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(label: 'Tutti', selected: filter == null, onTap: () => onFilter(null)),
                for (final b in barbers)
                  _FilterChip(
                    label: b.name,
                    color: barberColor(barbers, b.id),
                    selected: filter == b.id,
                    dimmed: b.hoursFor(day.weekday).isEmpty,
                    onTap: () => onFilter(filter == b.id ? null : b.id),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 6),
      ],
    );
  }
}

class _WeekDay extends StatelessWidget {
  const _WeekDay({
    required this.day,
    required this.selected,
    required this.today,
    required this.count,
    required this.open,
    required this.onTap,
    this.light = false,
  });
  final DateTime day;
  final bool selected;
  final bool today;
  final int count;
  final bool open;
  final VoidCallback onTap;
  final bool light;

  @override
  Widget build(BuildContext context) {
    // scuro: tessera avorio quando scelta; chiaro: tessera nera quando scelta
    final Color fg, bg, border, sub;
    if (light) {
      fg = selected ? Colors.white : (open ? AgendaLight.ink : AgendaLight.muted);
      bg = selected ? AgendaLight.ink : (open ? AgendaLight.card : Colors.transparent);
      border = selected ? AgendaLight.ink : (today ? AgendaLight.now : AgendaLight.line);
      sub = selected ? const Color(0xFFCFCFCF) : AgendaLight.sub;
    } else {
      fg = selected ? AppColors.black : (open ? AppColors.white : AppColors.muted);
      bg = selected ? AppColors.white : Colors.white.withValues(alpha: open ? 0.05 : 0.015);
      border = selected
          ? AppColors.white
          : today
          ? AppColors.silver.withValues(alpha: 0.7)
          : Colors.white.withValues(alpha: 0.08);
      sub = selected ? const Color(0xFF555555) : AppColors.silver;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: today && !selected ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Text(
              DateFormat('EEE', 'it_IT').format(day).replaceAll('.', '').toUpperCase(),
              style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8),
            ),
            Text(
              '${day.day}',
              style: slab(size: 17, color: fg, weight: FontWeight.w700, spacing: 0),
            ),
            SizedBox(
              height: 14,
              child: count == 0
                  ? null
                  : Text(
                      '$count',
                      style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.dimmed = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final bool dimmed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.white : AppColors.quietBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              dimmed ? '$label · riposo' : label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.black : (dimmed ? AppColors.muted : AppColors.white),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Vista barbieri (telefono): lo schermo diviso in un riquadro per barbiere
// ---------------------------------------------------------------------------

class _BarberPanels extends StatelessWidget {
  const _BarberPanels({required this.barbers, required this.onOpen});
  final List<Barber> barbers;
  final ValueChanged<Barber> onOpen;

  static const _gap = 10.0;
  static const _minH = 96.0;
  static const _wideH = 110.0;

  /// Larghezza massima di riquadri e intestazione su schermi larghi.
  static const wideMaxWidth = 640.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final avail = c.maxHeight - 24 - _gap * (barbers.length - 1);
      // telefono: i riquadri si dividono lo schermo; tablet e computer:
      // colonna ordinata a sinistra con riquadri di altezza fissa
      final wide = c.maxWidth >= 700;
      final h = wide ? _wideH : (avail / barbers.length).clamp(_minH, 220.0);
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 6, 0, 18),
        child: ResponsiveCenter(
          maxWidth: wideMaxWidth,
          alignment: Alignment.topLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              for (var i = 0; i < barbers.length; i++) ...[
                if (i > 0) const SizedBox(height: _gap),
                SizedBox(
                  height: h,
                  child: _BarberPanel(
                    barber: barbers[i],
                    tone: barberTone(barbers, barbers[i].id),
                    onTap: () => onOpen(barbers[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Riquadro del barbiere: solo il nome, come una sezione da aprire.
class _BarberPanel extends StatelessWidget {
  const _BarberPanel({required this.barber, required this.tone, required this.onTap});
  final Barber barber;
  final BarberTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: tone.bg,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Expanded(
              child: Text(
                barber.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: tone.ink, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 0.3),
              ),
            ),
            Icon(Icons.chevron_right, color: tone.ink, size: 34),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Vista griglia
// ---------------------------------------------------------------------------

/// Griglia oraria: colonne = barbieri, righe = orari. Scorre in verticale
/// quando la giornata non sta nello schermo.
class _DayCalendar extends StatefulWidget {
  const _DayCalendar({
    super.key,
    required this.day,
    required this.barbers,
    required this.allBarbers,
    required this.appointments,
    required this.timeOff,
    required this.range,
    required this.ppm,
    required this.onTapAppointment,
    required this.onTapEmpty,
    required this.onLongPressEmpty,
    required this.onTapTimeOff,
  });

  static const headerH = 46.0;
  static const gutter = 52.0;
  static const topPad = 10.0;
  static const minColumn = 104.0;
  static const minBlock = 22.0;

  final DateTime day;
  final List<Barber> barbers;
  final List<Barber> allBarbers;
  final List<Appointment> appointments;
  final Map<String, List<TimeOff>> timeOff;
  final (int, int) range;

  /// Pixel per minuto.
  final double ppm;
  final ValueChanged<Appointment> onTapAppointment;
  final void Function(Barber, DateTime) onTapEmpty;
  final void Function(Barber, int) onLongPressEmpty;
  final void Function(TimeOff, Barber) onTapTimeOff;

  @override
  State<_DayCalendar> createState() => _DayCalendarState();
}

class _DayCalendarState extends State<_DayCalendar> {
  final _vertical = ScrollController();

  double get ppm => widget.ppm;
  (int, int) get range => widget.range;
  double _y(int minute) => _DayCalendar.topPad + (minute - range.$1) * ppm;

  @override
  void initState() {
    super.initState();
    // oggi: parte dall'ora attuale
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_vertical.hasClients || dayOnly(DateTime.now()) != widget.day) return;
      final target = _y(_minuteOf(DateTime.now())) - 80;
      _vertical.jumpTo(target.clamp(0.0, _vertical.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _vertical.dispose();
    super.dispose();
  }

  int _minuteAt(double dy) => range.$1 + ((dy - _DayCalendar.topPad) / ppm).floor();

  @override
  Widget build(BuildContext context) {
    const gutter = _DayCalendar.gutter;
    final height = _y(range.$2) + _DayCalendar.topPad;
    final barbers = widget.barbers;
    return LayoutBuilder(
      builder: (context, c) {
        final colW = ((c.maxWidth - gutter - 12) / barbers.length).clamp(_DayCalendar.minColumn, 420.0);
        final totalW = gutter + colW * barbers.length + 12;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalW < c.maxWidth ? c.maxWidth : totalW,
            child: Column(
              children: [
                // Intestazione con i barbieri
                SizedBox(
                  height: _DayCalendar.headerH,
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
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: barberColor(widget.allBarbers, b.id),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 7),
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
                  child: SingleChildScrollView(
                    controller: _vertical,
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
                              child: _column(barbers[i]),
                            ),
                          if (dayOnly(DateTime.now()) == widget.day) _nowLine(),
                        ],
                      ),
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
      left: _DayCalendar.gutter - 4,
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
  /// coprire l'appuntamento successivo.
  double _blockHeight(List<Appointment> mine, int i) {
    final a = mine[i];
    final top = _y(_minuteOf(a.start)) + 1;
    var h = a.end.difference(a.start).inMinutes * ppm - 2;
    if (h < _DayCalendar.minBlock) h = _DayCalendar.minBlock;
    if (i + 1 < mine.length) {
      final room = _y(_minuteOf(mine[i + 1].start)) - top - 1;
      if (room >= 8 && h > room) h = room;
    }
    return h;
  }

  Widget _column(Barber b) {
    final day = widget.day;
    final mine = widget.appointments.where((a) => a.barberId == b.id).toList()
      ..sort((x, y) => x.start.compareTo(y.start));
    final off = widget.timeOff[b.id] ?? [];
    final color = barberColor(widget.allBarbers, b.id);
    bool works(int m) => b.hoursFor(day.weekday).any((h) => m >= h.start && m < h.end);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (d) {
        final rounded = (_minuteAt(d.localPosition.dy) ~/ 15) * 15;
        if (!works(rounded)) return;
        widget.onTapEmpty(b, DateTime(day.year, day.month, day.day, 0, rounded));
      },
      onLongPressStart: (d) {
        final rounded = (_minuteAt(d.localPosition.dy) ~/ 15) * 15;
        if (!works(rounded)) return;
        widget.onLongPressEmpty(b, rounded);
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
            // Ferie / permessi / blocchi: toccando si possono rimuovere
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
                  child: GestureDetector(
                    onTap: () => widget.onTapTimeOff(t, b),
                    child: Container(
                      alignment: Alignment.topCenter,
                      padding: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        t.reason.isEmpty ? 'Assente' : t.reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
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
                child: _AppointmentBlock(
                  appointment: mine[i],
                  color: color,
                  onTap: () => widget.onTapAppointment(mine[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentBlock extends StatelessWidget {
  const _AppointmentBlock({required this.appointment, required this.color, required this.onTap});
  final Appointment appointment;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final (bg, fg, sub) = switch (a.status) {
      AppointmentStatus.confirmed => (const Color(0xFF2A2A2A), AppColors.white, AppColors.silver),
      AppointmentStatus.completed => (const Color(0xFF1A1A1A), AppColors.silver, AppColors.muted),
      AppointmentStatus.noShow => (AppColors.warning.withValues(alpha: 0.16), AppColors.white, AppColors.silver),
      AppointmentStatus.cancelled => (AppColors.graphite, AppColors.muted, AppColors.muted),
    };

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: a.status == AppointmentStatus.confirmed ? color : color.withValues(alpha: 0.4)),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  final roomy = c.maxHeight >= 40;
                  // blocchi bassi (servizi brevi): una sola riga centrata
                  final size = roomy ? 12.5 : (c.maxHeight - 4).clamp(9.0, 12.5);
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
                      if (a.status == AppointmentStatus.completed)
                        Icon(Icons.check, size: size + 1, color: AppColors.success),
                    ],
                  );
                  if (!roomy) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Align(alignment: Alignment.centerLeft, child: line),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        line,
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
          ],
        ),
      ),
    );
  }
}
