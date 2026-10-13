import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/slots.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../booking_screen.dart';
import 'block_time_sheet.dart';
import 'customer_screen.dart';

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

class _AgendaTabState extends State<AgendaTab> {
  late DateTime _day = dayOnly(widget.initialDay ?? DateTime.now());
  DateTime? _loadedWeek;
  List<Appointment> _week = []; // appuntamenti della settimana mostrata
  Map<String, List<TimeOff>> _timeOff = {};
  bool _loading = true;
  bool? _grid; // null: deciso in base alla larghezza dello schermo
  String? _filter; // griglia: id del barbiere mostrato, null = tutti
  int _lane = 0; // corsie: barbiere mostrato
  int _scrollToken = 0; // cambia quando l'elenco deve tornare all'ora attuale

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

  // --- Azioni ---

  Future<void> _newAppointment({Barber? barber, DateTime? time}) async {
    final created = await Navigator.of(context).push<bool>(
      fadeRoute(BookingScreen(adminMode: true, initialDay: time ?? _day, initialBarber: barber, initialTime: time)),
    );
    if (created == true) _load(silent: true);
  }

  Future<void> _move(Appointment a) async {
    final moved = await Navigator.of(context).push<bool>(fadeRoute(BookingScreen(adminMode: true, reschedule: a)));
    if (moved == true) _load(silent: true);
  }

  Future<void> _block({Barber? barber, int? start, int? end}) async {
    final state = AppScope.read(context);
    final ok = await showBlockTimeSheet(
      context,
      day: _day,
      barbers: state.barbers,
      appointments: _dayItems,
      barber: barber,
      startMin: start,
      endMin: end,
    );
    if (ok && mounted) {
      showMessage(context, 'Orario bloccato');
      _load(silent: true);
    }
  }

  Future<void> _removeBlock(TimeOff t, Barber b) async {
    final ok = await confirmDialog(
      context,
      title: 'Rimuovere il blocco?',
      message:
          '${b.name} · ${t.reason.isEmpty ? 'Assente' : t.reason}\n'
          '${_offLabel(t)}\nL\'orario tornerà prenotabile.',
      confirm: 'Rimuovi',
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).backend.deleteTimeOff(t.id);
      await _load(silent: true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  String _offLabel(TimeOff t) {
    final allDay = !t.start.isAfter(_day) && !t.end.isBefore(_nextDay);
    if (allDay) return 'Tutto il giorno';
    final s = t.start.isBefore(_day) ? '00:00' : fmtTime(t.start);
    final e = t.end.isAfter(_nextDay) ? '24:00' : fmtTime(t.end);
    return '$s – $e';
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
      await _load(silent: true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Azione rapida (scorrimento): cambia stato con possibilita' di annullare.
  Future<void> _quick(Appointment a, AppointmentStatus s) async {
    final backend = AppScope.read(context).backend;
    final previous = a.status;
    try {
      await backend.setAppointmentStatus(a.id, s);
      await _load(silent: true);
      if (!mounted) return;
      showMessage(
        context,
        '${a.customerName.isEmpty ? 'Cliente' : a.customerName}: ${statusLabel(s).toLowerCase()}',
        actionLabel: 'Annulla',
        onAction: () async {
          try {
            await backend.setAppointmentStatus(a.id, previous);
            if (mounted) await _load(silent: true);
          } catch (e) {
            if (mounted) showError(context, e);
          }
        },
      );
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

  void _openCustomer(Appointment a) {
    final c = CustomerSummary(
      id: a.userId ?? '${CustomerSummary.walkInPrefix}${a.customerName}',
      email: '',
      fullName: a.customerName,
      phone: a.customerPhone,
      bookings: 0,
    );
    Navigator.of(context).push(fadeRoute(CustomerScreen(customer: c))).then((_) => _load(silent: true));
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
                  if (a.customerName.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.person_search_outlined),
                      title: const Text('Scheda cliente'),
                      onTap: () => act(() => _openCustomer(a)),
                    ),
                  if (a.status == AppointmentStatus.confirmed) ...[
                    ListTile(
                      leading: const Icon(Icons.edit_calendar_outlined),
                      title: const Text('Sposta appuntamento'),
                      onTap: () => act(() => _move(a)),
                    ),
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
    _grid ??= MediaQuery.sizeOf(context).width >= 700;
    if (_filter != null && !barbers.any((b) => b.id == _filter)) _filter = null;
    if (_lane >= barbers.length) _lane = 0;
    // corsie: si vede un barbiere alla volta; griglia: filtro facoltativo
    final laneBarber = barbers.isEmpty ? null : barbers[_lane];
    final filter = _grid! ? _filter : laneBarber?.id;
    final shown = _filter == null ? barbers : barbers.where((b) => b.id == _filter).toList();
    final shownIds = shown.map((b) => b.id).toSet();
    final active = _dayItems.where((a) => a.status != AppointmentStatus.cancelled).toList();
    final dayAppts = active.where((a) => shownIds.contains(a.barberId)).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          ResponsiveCenter(
            maxWidth: 1200,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _AgendaHeader(
              day: _day,
              weekStart: _weekStart,
              week: _week,
              barbers: barbers,
              filter: filter,
              grid: _grid!,
              onDay: _setDay,
              onPickDay: _pickDay,
              onFilter: (id) => setState(() => _filter = id),
              onToggleView: () => setState(() {
                _grid = !_grid!;
                _scrollToken++;
              }),
              onNew: () => _newAppointment(),
              onBlock: () => _block(barber: _grid! ? (shown.length == 1 ? shown.first : null) : laneBarber),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : barbers.isEmpty
                ? const EmptyState(icon: Icons.badge_outlined, text: 'Aggiungi i barbieri dalla sezione Barbieri')
                : _grid!
                ? LayoutBuilder(
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
                        onTapAppointment: _openAppointment,
                        onTapEmpty: (b, t) => _newAppointment(barber: b, time: t),
                        onLongPressEmpty: (b, m) => _block(barber: b, start: m, end: m + 30),
                        onTapTimeOff: _removeBlock,
                      );
                    },
                  )
                : _LaneView(
                    key: ValueKey('lanes$_scrollToken'),
                    day: _day,
                    barbers: barbers,
                    index: _lane,
                    onIndex: (i) => setState(() => _lane = i),
                    appointments: active,
                    timeOff: _dayOff,
                    onTapAppointment: _openAppointment,
                    onDone: (a) => _quick(a, AppointmentStatus.completed),
                    onTapEmpty: (b, t) => _newAppointment(barber: b, time: t),
                    onLongPressEmpty: (b, s, e) => _block(barber: b, start: s, end: e),
                    onTapTimeOff: _removeBlock,
                  ),
          ),
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
    required this.onDay,
    required this.onPickDay,
    required this.onFilter,
    required this.onToggleView,
    required this.onNew,
    required this.onBlock,
  });

  final DateTime day;
  final DateTime weekStart;
  final List<Appointment> week;
  final List<Barber> barbers;
  final String? filter;
  final bool grid;
  final ValueChanged<DateTime> onDay;
  final VoidCallback onPickDay;
  final ValueChanged<String?> onFilter;
  final VoidCallback onToggleView;
  final VoidCallback onNew;
  final VoidCallback onBlock;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              visualDensity: compact,
              tooltip: 'Settimana precedente',
              onPressed: () => onDay(DateTime(day.year, day.month, day.day - 7)),
              icon: const Icon(Icons.chevron_left),
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
                          style: slab(size: 16, weight: FontWeight.w600, spacing: 0.5),
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
              icon: const Icon(Icons.chevron_right),
            ),
            if (day != today)
              TextButton(
                style: TextButton.styleFrom(visualDensity: compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () => onDay(today),
                child: const Text('Oggi'),
              ),
            IconButton(
              visualDensity: compact,
              tooltip: grid ? 'Vista corsie' : 'Vista griglia',
              onPressed: onToggleView,
              icon: Icon(grid ? Icons.view_day_outlined : Icons.view_week_outlined, size: 21),
            ),
            PopupMenuButton<int>(
              tooltip: 'Aggiungi',
              position: PopupMenuPosition.under,
              color: AppColors.graphite,
              onSelected: (v) => v == 0 ? onNew() : onBlock(),
              itemBuilder: (_) => const [
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
                decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle),
                child: const Icon(Icons.add, color: AppColors.black),
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
                  count: week.where((a) => dayOnly(a.start) == days[i] && _counts(a)).length,
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
  });
  final DateTime day;
  final bool selected;
  final bool today;
  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.black : (open ? AppColors.white : AppColors.muted);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.white : Colors.white.withValues(alpha: open ? 0.05 : 0.015),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.white
                : today
                ? AppColors.silver.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.08),
          ),
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
                      style: TextStyle(
                        color: selected ? const Color(0xFF555555) : AppColors.silver,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
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
// Vista corsie (telefono): un barbiere alla volta, si cambia scorrendo
// ---------------------------------------------------------------------------

/// Spazi liberi di un barbiere nel giorno (minuti dalla mezzanotte), almeno
/// [minGap] minuti. Oggi si parte dall'ora attuale; i giorni passati non ne hanno.
List<(int, int)> _freeRanges(
  DateTime day,
  Barber b,
  List<Appointment> appointments,
  List<TimeOff> off, {
  int minGap = 15,
}) {
  final now = DateTime.now();
  final today = dayOnly(now);
  if (day.isBefore(today)) return [];
  final from = day == today ? ((_minuteOf(now) + 4) ~/ 5) * 5 : 0;
  final busy = <(int, int)>[
    for (final a in appointments.where((a) => a.barberId == b.id))
      (_minuteOf(a.start), _minuteOf(a.start) + a.end.difference(a.start).inMinutes),
    for (final t in off) _offRange(day, t),
  ]..sort((x, y) => x.$1.compareTo(y.$1));
  final result = <(int, int)>[];
  void add(int s, int e) {
    if (s < from) s = from;
    if (e - s >= minGap) result.add((s, e));
  }

  for (final h in b.hoursFor(day.weekday)) {
    var cur = h.start;
    for (final (s, e) in busy) {
      if (e <= cur) continue;
      if (s >= h.end) break;
      if (s > cur) add(cur, s);
      cur = e;
    }
    if (cur < h.end) add(cur, h.end);
  }
  return result;
}

/// Parte di un'assenza che cade nel giorno, in minuti.
(int, int) _offRange(DateTime day, TimeOff t) {
  final next = DateTime(day.year, day.month, day.day + 1);
  return (t.start.isAfter(day) ? _minuteOf(t.start) : 0, t.end.isBefore(next) ? _minuteOf(t.end) : 24 * 60);
}

class _LaneView extends StatefulWidget {
  const _LaneView({
    super.key,
    required this.day,
    required this.barbers,
    required this.index,
    required this.onIndex,
    required this.appointments,
    required this.timeOff,
    required this.onTapAppointment,
    required this.onDone,
    required this.onTapEmpty,
    required this.onLongPressEmpty,
    required this.onTapTimeOff,
  });

  final DateTime day;
  final List<Barber> barbers;
  final int index;
  final ValueChanged<int> onIndex;
  final List<Appointment> appointments; // del giorno, tutti i barbieri (senza annullati)
  final Map<String, List<TimeOff>> timeOff;
  final ValueChanged<Appointment> onTapAppointment;
  final ValueChanged<Appointment> onDone;
  final void Function(Barber, DateTime) onTapEmpty;
  final void Function(Barber, int, int) onLongPressEmpty;
  final void Function(TimeOff, Barber) onTapTimeOff;

  @override
  State<_LaneView> createState() => _LaneViewState();
}

class _LaneViewState extends State<_LaneView> {
  late final _pages = PageController(initialPage: widget.index);

  @override
  void didUpdateWidget(covariant _LaneView old) {
    super.didUpdateWidget(old);
    if (_pages.hasClients && (_pages.page?.round() ?? widget.index) != widget.index) {
      _pages.jumpToPage(widget.index);
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return Column(
      children: [
        if (w.barbers.length > 1)
          ResponsiveCenter(
            maxWidth: 720,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _LaneTabs(
              barbers: w.barbers,
              day: w.day,
              index: w.index,
              appointments: w.appointments,
              onTap: (i) =>
                  _pages.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic),
            ),
          ),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: w.barbers.length,
            onPageChanged: w.onIndex,
            itemBuilder: (context, i) {
              final b = w.barbers[i];
              return _Lane(
                day: w.day,
                barber: b,
                color: barberColor(w.barbers, b.id),
                appointments: w.appointments.where((a) => a.barberId == b.id).toList()
                  ..sort((x, y) => x.start.compareTo(y.start)),
                timeOff: w.timeOff[b.id] ?? const [],
                onTapAppointment: w.onTapAppointment,
                onDone: w.onDone,
                onTapEmpty: (t) => w.onTapEmpty(b, t),
                onLongPressEmpty: (s, e) => w.onLongPressEmpty(b, s, e),
                onTapTimeOff: (t) => w.onTapTimeOff(t, b),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Schede dei barbieri sopra le corsie: nome, numero di appuntamenti, colore.
class _LaneTabs extends StatelessWidget {
  const _LaneTabs({
    required this.barbers,
    required this.day,
    required this.index,
    required this.appointments,
    required this.onTap,
  });
  final List<Barber> barbers;
  final DateTime day;
  final int index;
  final List<Appointment> appointments;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    Widget tab(int i) {
      final b = barbers[i];
      final selected = i == index;
      final color = barberColor(barbers, b.id);
      final count = appointments.where((a) => a.barberId == b.id).length;
      final resting = b.hoursFor(day.weekday).isEmpty;
      return InkWell(
        onTap: () => onTap(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: selected ? color : AppColors.quietBorder, width: selected ? 3 : 1),
            ),
          ),
          child: Column(
            children: [
              Text(
                b.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.white : AppColors.muted,
                ),
              ),
              Text(
                resting && count == 0 ? 'riposo' : '$count ${count == 1 ? 'appuntamento' : 'appuntamenti'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: selected ? AppColors.silver : AppColors.muted),
              ),
            ],
          ),
        ),
      );
    }

    if (barbers.length <= 4) {
      return Row(children: [for (var i = 0; i < barbers.length; i++) Expanded(child: tab(i))]);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [for (var i = 0; i < barbers.length; i++) SizedBox(width: 104, child: tab(i))]),
    );
  }
}

/// Corsia di un barbiere: orari in verticale, blocchi proporzionati alla durata.
class _Lane extends StatefulWidget {
  const _Lane({
    required this.day,
    required this.barber,
    required this.color,
    required this.appointments,
    required this.timeOff,
    required this.onTapAppointment,
    required this.onDone,
    required this.onTapEmpty,
    required this.onLongPressEmpty,
    required this.onTapTimeOff,
  });

  /// Pixel per minuto: mezz'ora = 54 px, leggibile anche per i servizi brevi.
  static const ppm = 1.8;
  static const gutter = 50.0;
  static const topPad = 12.0;
  static const minBlock = 30.0;

  final DateTime day;
  final Barber barber;
  final Color color;
  final List<Appointment> appointments;
  final List<TimeOff> timeOff;
  final ValueChanged<Appointment> onTapAppointment;
  final ValueChanged<Appointment> onDone;
  final ValueChanged<DateTime> onTapEmpty;
  final void Function(int, int) onLongPressEmpty;
  final ValueChanged<TimeOff> onTapTimeOff;

  @override
  State<_Lane> createState() => _LaneState();
}

class _LaneState extends State<_Lane> {
  final _scroll = ScrollController();

  (int, int) get _range {
    var start = 24 * 60, end = 0;
    for (final h in widget.barber.hoursFor(widget.day.weekday)) {
      if (h.start < start) start = h.start;
      if (h.end > end) end = h.end;
    }
    for (final a in widget.appointments) {
      final s = _minuteOf(a.start);
      final e = s + a.end.difference(a.start).inMinutes;
      if (s < start) start = s;
      if (e > end) end = e;
    }
    if (end <= start) return (9 * 60, 20 * 60);
    return ((start ~/ 60) * 60, ((end + 59) ~/ 60) * 60);
  }

  /// Altezza delle pause tra due fasce di lavoro (es. pranzo), compresse
  /// per non riempire lo schermo di vuoto.
  static const _breakH = 34.0;

  /// Tratti della giornata: (inizio, fine, compresso).
  List<(int, int, bool)> _segments = const [];

  List<(int, int, bool)> _computeSegments((int, int) range) {
    final hours = widget.barber.hoursFor(widget.day.weekday);
    final segs = <(int, int, bool)>[];
    var cur = range.$1;
    for (var i = 0; i + 1 < hours.length; i++) {
      final s = hours[i].end, e = hours[i + 1].start;
      bool overlaps(int a, int b) => a < e && b > s;
      final busy =
          widget.appointments.any(
            (a) => overlaps(_minuteOf(a.start), _minuteOf(a.start) + a.end.difference(a.start).inMinutes),
          ) ||
          widget.timeOff.any((t) {
            final (a, b) = _offRange(widget.day, t);
            return overlaps(a, b) && !(a <= range.$1 && b >= range.$2);
          });
      if (e - s >= 60 && !busy) {
        segs
          ..add((cur, s, false))
          ..add((s, e, true));
        cur = e;
      }
    }
    segs.add((cur, range.$2, false));
    return segs;
  }

  double _y(int minute) {
    var y = _Lane.topPad;
    for (final (s, e, compressed) in _segments) {
      final len = compressed ? _breakH : (e - s) * _Lane.ppm;
      if (minute >= e) {
        y += len;
      } else {
        if (minute > s) y += len * (minute - s) / (e - s);
        break;
      }
    }
    return y;
  }

  int _minuteAt(double dy) {
    var y = _Lane.topPad;
    for (final (s, e, compressed) in _segments) {
      final len = compressed ? _breakH : (e - s) * _Lane.ppm;
      if (dy < y + len) return s + ((dy - y) / len * (e - s)).floor();
      y += len;
    }
    return _segments.isEmpty ? 0 : _segments.last.$2;
  }

  bool _inBreak(int m) => _segments.any((g) => g.$3 && m > g.$1 && m < g.$2);

  @override
  void initState() {
    super.initState();
    // oggi parte dall'ora attuale, gli altri giorni dal primo appuntamento
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final now = DateTime.now();
      final int target;
      if (dayOnly(now) == widget.day) {
        target = _minuteOf(now) - 45;
      } else if (widget.appointments.isNotEmpty) {
        target = _minuteOf(widget.appointments.first.start) - 15;
      } else {
        return;
      }
      _scroll.jumpTo((_y(target) - _Lane.topPad).clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Altezza del blocco: proporzionale, ma almeno [minBlock] e senza coprire il successivo.
  double _blockHeight(int i) {
    final list = widget.appointments;
    final a = list[i];
    final top = _y(_minuteOf(a.start)) + 1;
    var h = a.end.difference(a.start).inMinutes * _Lane.ppm - 3;
    if (h < _Lane.minBlock) h = _Lane.minBlock;
    if (i + 1 < list.length) {
      final room = _y(_minuteOf(list[i + 1].start)) - top - 2;
      if (room >= 18 && h > room) h = room;
    }
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final b = w.barber;
    final hours = b.hoursFor(w.day.weekday);
    if (hours.isEmpty && w.appointments.isEmpty && w.timeOff.isEmpty) {
      return EmptyState(icon: Icons.weekend_outlined, text: '${b.name} oggi è di riposo');
    }
    final range = _range;
    _segments = _computeSegments(range);
    final height = _y(range.$2) + _Lane.topPad;
    final isToday = dayOnly(DateTime.now()) == w.day;
    const gutter = _Lane.gutter;
    int minuteAt(double dy) => _minuteAt(dy);
    bool works(int m) => hours.any((h) => m >= h.start && m < h.end);

    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 24),
      child: ResponsiveCenter(
        maxWidth: 720,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              // tocco su un orario libero: prenota; tenendo premuto: blocca
              Positioned.fill(
                left: gutter,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (d) {
                    final m = (minuteAt(d.localPosition.dy) ~/ 15) * 15;
                    if (works(m)) w.onTapEmpty(DateTime(w.day.year, w.day.month, w.day.day, 0, m));
                  },
                  onLongPressStart: (d) {
                    final m = (minuteAt(d.localPosition.dy) ~/ 15) * 15;
                    if (works(m)) w.onLongPressEmpty(m, m + 30);
                  },
                ),
              ),
              // fasce di lavoro
              for (final h in hours)
                Positioned(
                  top: _y(h.start),
                  height: _y(h.end) - _y(h.start),
                  left: gutter,
                  right: 0,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.025),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              // pause compresse (es. pranzo)
              for (final (s, e, compressed) in _segments)
                if (compressed)
                  Positioned(
                    top: _y(s) + 3,
                    height: _breakH - 6,
                    left: gutter,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'pausa ${formatTime(s)} – ${formatTime(e)}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12, letterSpacing: 0.5),
                        ),
                      ),
                    ),
                  ),
              // linee e orari
              for (var m = range.$1; m <= range.$2; m += 30)
                if (!_inBreak(m))
                  Positioned(
                    top: _y(m),
                    left: m % 60 == 0 ? gutter - 6 : gutter,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(height: 1, color: Colors.white.withValues(alpha: m % 60 == 0 ? 0.09 : 0.035)),
                    ),
                  ),
              for (var m = range.$1; m < range.$2; m += 30)
                if (!_inBreak(m))
                  Positioned(
                    top: _y(m) - 8,
                    left: 0,
                    width: gutter - 12,
                    child: Text(
                      formatTime(m),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: m % 60 == 0 ? AppColors.silver : AppColors.muted.withValues(alpha: 0.6),
                        fontSize: m % 60 == 0 ? 12.5 : 10.5,
                        fontWeight: m % 60 == 0 ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
              // spazi liberi
              for (final (s, e) in _freeRanges(w.day, b, w.appointments, w.timeOff))
                Positioned(
                  top: _y(s) + 2,
                  height: _y(e) - _y(s) - 4,
                  left: gutter + 4,
                  right: 4,
                  child: _FreeBlock(
                    minutes: e - s,
                    onTap: () => w.onTapEmpty(DateTime(w.day.year, w.day.month, w.day.day, 0, s)),
                    onLongPress: () => w.onLongPressEmpty(s, e - s > 60 ? s + 30 : e),
                  ),
                ),
              // ferie, pause, blocchi
              for (final t in w.timeOff)
                () {
                  final (s0, e0) = _offRange(w.day, t);
                  final s = s0.clamp(range.$1, range.$2);
                  final e = e0.clamp(range.$1, range.$2);
                  return Positioned(
                    top: _y(s) + 1,
                    height: (_y(e) - _y(s) - 2).clamp(24.0, double.infinity),
                    left: gutter + 4,
                    right: 4,
                    child: _OffBlock(timeOff: t, from: s0, to: e0, onTap: () => w.onTapTimeOff(t)),
                  );
                }(),
              // appuntamenti
              for (var i = 0; i < w.appointments.length; i++)
                Positioned(
                  top: _y(_minuteOf(w.appointments[i].start)) + 1,
                  height: _blockHeight(i),
                  left: gutter + 4,
                  right: 4,
                  child: _LaneCard(
                    appointment: w.appointments[i],
                    color: w.color,
                    onTap: () => w.onTapAppointment(w.appointments[i]),
                    onDone: () => w.onDone(w.appointments[i]),
                  ),
                ),
              // ora attuale
              if (isToday && _minuteOf(DateTime.now()) >= range.$1 && _minuteOf(DateTime.now()) <= range.$2)
                Positioned(
                  top: _y(_minuteOf(DateTime.now())) - 9,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Row(
                      children: [
                        Container(
                          width: gutter - 8,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(4)),
                          child: Text(
                            fmtTime(DateTime.now()),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                        Expanded(child: Container(height: 1.5, color: AppColors.danger)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FreeBlock extends StatelessWidget {
  const _FreeBlock({required this.minutes, required this.onTap, required this.onLongPress});
  final int minutes;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.quietBorder),
        ),
        child: LayoutBuilder(
          builder: (context, c) => c.maxHeight < 20
              ? const SizedBox.shrink()
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add, size: 15, color: AppColors.muted),
                    const SizedBox(width: 6),
                    Text(
                      'libero ${fmtDuration(minutes)}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}

class _OffBlock extends StatelessWidget {
  const _OffBlock({required this.timeOff, required this.from, required this.to, required this.onTap});
  final TimeOff timeOff;
  final int from;
  final int to;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final allDay = from == 0 && to == 24 * 60;
    return Material(
      color: AppColors.warning.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          alignment: Alignment.topLeft,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.block, size: 15, color: AppColors.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    timeOff.reason.isEmpty ? 'Assente' : timeOff.reason,
                    allDay ? 'tutto il giorno' : '${formatTime(from)} – ${formatTime(to)}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.warning, fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Appuntamento nella corsia. Con il tasto ✓ si chiude quello in corso o passato.
class _LaneCard extends StatelessWidget {
  const _LaneCard({required this.appointment, required this.color, required this.onTap, required this.onDone});
  final Appointment appointment;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final now = DateTime.now();
    final confirmed = a.status == AppointmentStatus.confirmed;
    final running = confirmed && !a.start.isAfter(now) && a.end.isAfter(now);
    final toClose = confirmed && !a.end.isAfter(now);
    final done = a.status == AppointmentStatus.completed;
    final noShow = a.status == AppointmentStatus.noShow;
    final name = a.customerName.isEmpty ? 'Cliente' : a.customerName;
    final mins = a.end.difference(a.start).inMinutes;
    final nameColor = done ? AppColors.silver : AppColors.white;

    return Material(
      color: noShow
          ? AppColors.warning.withValues(alpha: 0.10)
          : done
          ? const Color(0xFF1A1A1A)
          : const Color(0xFF262626),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: running ? Border.all(color: AppColors.white.withValues(alpha: 0.55)) : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: done || noShow ? color.withValues(alpha: 0.4) : color),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final tall = c.maxHeight >= 64;
                    final mid = c.maxHeight >= 42;
                    final status = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (running) const _Tag('IN CORSO', AppColors.white),
                        if (toClose && !running) const _Tag('DA CHIUDERE', AppColors.warning),
                        if (noShow) const _Tag('NON VENUTO', AppColors.warning),
                        if (done) const Icon(Icons.check_circle, size: 17, color: AppColors.success),
                      ],
                    );
                    if (!mid) {
                      // servizi brevi: una riga sola
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        child: Row(
                          children: [
                            Text(
                              fmtTime(a.start),
                              style: TextStyle(color: nameColor, fontSize: 12.5, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '$name · ${a.serviceName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: nameColor, fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                            ),
                            status,
                          ],
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: nameColor, fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                              ),
                              status,
                            ],
                          ),
                          Text(
                            '${fmtTime(a.start)}–${fmtTime(a.end)} · ${a.serviceName}'
                            '${tall ? '' : ' · ${fmtPrice(a.price)}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.silver, fontSize: 12.5),
                          ),
                          if (tall) ...[
                            Text(
                              '$mins min · ${fmtPrice(a.price)}',
                              style: const TextStyle(color: AppColors.muted, fontSize: 12),
                            ),
                            if (a.notes.isNotEmpty)
                              Text(
                                '“${a.notes}”',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              // chiusura rapida: appuntamento iniziato e ancora da segnare
              if (confirmed && !a.start.isAfter(now))
                IconButton(
                  tooltip: 'Segna completato',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDone,
                  icon: const Icon(Icons.check_circle_outline, color: AppColors.success),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(4)),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6),
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
