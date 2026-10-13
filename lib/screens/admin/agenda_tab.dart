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
  String? _filter; // id del barbiere mostrato, null = tutti
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
      _timeOff = {
        for (var i = 0; i < state.barbers.length; i++) state.barbers[i].id: results[i + 1] as List<TimeOff>,
      };
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
    final moved = await Navigator.of(context).push<bool>(
      fadeRoute(BookingScreen(adminMode: true, reschedule: a)),
    );
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
    final shown = _filter == null ? barbers : barbers.where((b) => b.id == _filter).toList();
    final shownIds = shown.map((b) => b.id).toSet();
    final dayAppts = _dayItems
        .where((a) => a.status != AppointmentStatus.cancelled && shownIds.contains(a.barberId))
        .toList();

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
              filter: _filter,
              grid: _grid!,
              onDay: _setDay,
              onPickDay: _pickDay,
              onFilter: (id) => setState(() => _filter = id),
              onToggleView: () => setState(() {
                _grid = !_grid!;
                _scrollToken++;
              }),
              onNew: () => _newAppointment(),
              onBlock: () => _block(barber: shown.length == 1 ? shown.first : null),
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
                : _AgendaList(
                    key: ValueKey('list$_scrollToken'),
                    day: _day,
                    barbers: shown,
                    allBarbers: barbers,
                    appointments: dayAppts,
                    timeOff: _dayOff,
                    showBarber: _filter == null && barbers.length > 1,
                    onTapAppointment: _openAppointment,
                    onQuick: _quick,
                    onTapGap: (g) => _newAppointment(
                      barber: g.barbers.length == 1 ? g.barbers.first : null,
                      time: DateTime(_day.year, _day.month, _day.day, 0, g.start),
                    ),
                    onLongPressGap: (g) => _block(
                      barber: g.barbers.length == 1 ? g.barbers.first : null,
                      start: g.start,
                      end: g.end - g.start > 60 ? g.start + 30 : g.end,
                    ),
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

  bool _counts(Appointment a) =>
      a.status != AppointmentStatus.cancelled && (filter == null || a.barberId == filter);

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
              tooltip: grid ? 'Vista elenco' : 'Vista griglia',
              onPressed: onToggleView,
              icon: Icon(grid ? Icons.view_agenda_outlined : Icons.view_week_outlined, size: 21),
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
                  open: barbers.any((b) => (filter == null || b.id == filter) && b.hoursFor(days[i].weekday).isNotEmpty),
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
        if (barbers.length > 1) ...[
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
            Text('${day.day}', style: slab(size: 17, color: fg, weight: FontWeight.w700, spacing: 0)),
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
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
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
// Vista elenco
// ---------------------------------------------------------------------------

/// Spazio libero (minuti dalla mezzanotte) condiviso da uno o piu' barbieri.
class _Gap {
  _Gap(this.start, this.end, this.barbers);
  final int start;
  final int end;
  final List<Barber> barbers;
}

class _AgendaList extends StatefulWidget {
  const _AgendaList({
    super.key,
    required this.day,
    required this.barbers,
    required this.allBarbers,
    required this.appointments,
    required this.timeOff,
    required this.showBarber,
    required this.onTapAppointment,
    required this.onQuick,
    required this.onTapGap,
    required this.onLongPressGap,
    required this.onTapTimeOff,
  });

  final DateTime day;
  final List<Barber> barbers; // barbieri mostrati (filtro)
  final List<Barber> allBarbers; // per i colori
  final List<Appointment> appointments;
  final Map<String, List<TimeOff>> timeOff;
  final bool showBarber;
  final ValueChanged<Appointment> onTapAppointment;
  final void Function(Appointment, AppointmentStatus) onQuick;
  final ValueChanged<_Gap> onTapGap;
  final ValueChanged<_Gap> onLongPressGap;
  final void Function(TimeOff, Barber) onTapTimeOff;

  @override
  State<_AgendaList> createState() => _AgendaListState();
}

class _AgendaListState extends State<_AgendaList> {
  final _nowKey = GlobalKey();

  /// Spazi liberi minimi da mostrare.
  static const _minGap = 15;

  @override
  void initState() {
    super.initState();
    // all'apertura l'elenco parte dall'ora attuale
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _nowKey.currentContext;
      if (c != null) Scrollable.ensureVisible(c, alignment: 0.25);
    });
  }

  (int, int) _offRange(TimeOff t) {
    final d = widget.day;
    final next = DateTime(d.year, d.month, d.day + 1);
    return (
      t.start.isAfter(d) ? _minuteOf(t.start) : 0,
      t.end.isBefore(next) ? _minuteOf(t.end) : 24 * 60,
    );
  }

  List<_Gap> _gaps() {
    final now = DateTime.now();
    final today = dayOnly(now);
    if (widget.day.isBefore(today)) return [];
    // oggi: solo gli spazi ancora utilizzabili (dal prossimo multiplo di 5 minuti)
    final from = widget.day == today ? ((_minuteOf(now) + 4) ~/ 5) * 5 : 0;
    final byRange = <(int, int), List<Barber>>{};
    void add(int s, int e, Barber b) {
      if (s < from) s = from;
      if (e - s >= _minGap) byRange.putIfAbsent((s, e), () => []).add(b);
    }

    for (final b in widget.barbers) {
      final busy = <(int, int)>[
        for (final a in widget.appointments.where((a) => a.barberId == b.id))
          (_minuteOf(a.start), _minuteOf(a.start) + a.end.difference(a.start).inMinutes),
        for (final t in widget.timeOff[b.id] ?? const <TimeOff>[]) _offRange(t),
      ]..sort((x, y) => x.$1.compareTo(y.$1));
      for (final h in b.hoursFor(widget.day.weekday)) {
        var cur = h.start;
        for (final (s, e) in busy) {
          if (e <= cur) continue;
          if (s >= h.end) break;
          if (s > cur) add(cur, s, b);
          cur = e;
        }
        if (cur < h.end) add(cur, h.end, b);
      }
    }
    return [for (final e in byRange.entries) _Gap(e.key.$1, e.key.$2, e.value)];
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final now = DateTime.now();
    final isToday = w.day == dayOnly(now);
    final nowMin = _minuteOf(now);

    // voci ordinate per orario: (minuto, ordine a parita', widget)
    final entries = <(int, int, Widget)>[
      for (final b in w.barbers)
        for (final t in w.timeOff[b.id] ?? const <TimeOff>[])
          (
            _offRange(t).$1,
            0,
            _TimeOffRow(
              range: _offRange(t),
              reason: t.reason,
              barber: b,
              showBarber: w.showBarber,
              color: barberColor(w.allBarbers, b.id),
              onTap: () => w.onTapTimeOff(t, b),
            ),
          ),
      for (final a in w.appointments)
        (
          _minuteOf(a.start),
          1,
          _AppointmentRow(
            appointment: a,
            color: barberColor(w.allBarbers, a.barberId),
            showBarber: w.showBarber,
            onTap: () => w.onTapAppointment(a),
            onQuick: (s) => w.onQuick(a, s),
          ),
        ),
      for (final g in _gaps())
        (g.start, 2, _GapRow(gap: g, onTap: () => w.onTapGap(g), onLongPress: () => w.onLongPressGap(g))),
    ]..sort((x, y) => x.$1 != y.$1 ? x.$1.compareTo(y.$1) : x.$2.compareTo(y.$2));

    final resting = w.barbers.where((b) => b.hoursFor(w.day.weekday).isEmpty).map((b) => b.name).toList();
    final children = <Widget>[
      if (resting.isNotEmpty && resting.length < w.barbers.length)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Riposo: ${resting.join(', ')}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
    ];
    var nowPlaced = !isToday;
    for (final e in entries) {
      if (!nowPlaced && e.$1 > nowMin) {
        children.add(_NowLine(key: _nowKey, time: now));
        nowPlaced = true;
      }
      children.add(e.$3);
    }
    if (!nowPlaced && entries.isNotEmpty) children.add(_NowLine(key: _nowKey, time: now));

    if (entries.isEmpty) {
      final closed = w.barbers.every((b) => b.hoursFor(w.day.weekday).isEmpty);
      children.add(
        EmptyState(
          icon: closed ? Icons.door_front_door_outlined : Icons.event_available,
          text: closed ? 'Giorno di chiusura' : 'Nessun appuntamento',
        ),
      );
    } else {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: 14),
          child: Text(
            'Scorri un appuntamento verso destra per segnarlo completato, verso sinistra per «non presentato». '
            'Tocca uno spazio libero per prenotare, tienilo premuto per bloccarlo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 4, bottom: 32),
      child: ResponsiveCenter(
        maxWidth: 720,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }
}

/// Colonna dell'orario a sinistra delle voci dell'elenco.
class _TimeColumn extends StatelessWidget {
  const _TimeColumn({required this.time, this.sub, this.strong = true});
  final String time;
  final String? sub;
  final bool strong;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 50,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          time,
          style: TextStyle(
            fontSize: strong ? 15 : 12.5,
            fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            color: strong ? AppColors.white : AppColors.muted,
          ),
        ),
        if (sub != null) Text(sub!, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ],
    ),
  );
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({
    required this.appointment,
    required this.color,
    required this.showBarber,
    required this.onTap,
    required this.onQuick,
  });
  final Appointment appointment;
  final Color color;
  final bool showBarber;
  final VoidCallback onTap;
  final ValueChanged<AppointmentStatus> onQuick;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final now = DateTime.now();
    final running = a.status == AppointmentStatus.confirmed && !a.start.isAfter(now) && a.end.isAfter(now);
    final toClose = a.status == AppointmentStatus.confirmed && !a.end.isAfter(now);
    final done = a.status == AppointmentStatus.completed;
    final noShow = a.status == AppointmentStatus.noShow;
    final mins = a.end.difference(a.start).inMinutes;

    final card = Material(
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
            border: running ? Border.all(color: AppColors.white.withValues(alpha: 0.6)) : null,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: done || noShow ? color.withValues(alpha: 0.4) : color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(11, 9, 10, 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                a.customerName.isEmpty ? 'Cliente' : a.customerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: done ? AppColors.silver : AppColors.white,
                                ),
                              ),
                            ),
                            if (running) const _Tag('IN CORSO', AppColors.white),
                            if (toClose) const _Tag('DA CHIUDERE', AppColors.warning),
                            if (done) const Icon(Icons.check_circle, size: 17, color: AppColors.success),
                            if (noShow) const _Tag('NON PRESENTATO', AppColors.warning),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            a.serviceName,
                            if (showBarber && a.barberName.isNotEmpty) a.barberName,
                            fmtPrice(a.price),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.silver, fontSize: 12.5),
                        ),
                        if (a.notes.isNotEmpty)
                          Text(
                            '“${a.notes}”',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.muted, fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final row = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _TimeColumn(time: fmtTime(a.start), sub: '$mins\''),
          ),
          Expanded(child: card),
        ],
      ),
    );

    if (a.status != AppointmentStatus.confirmed) return row;

    // Azioni rapide: l'elemento torna al suo posto, poi l'elenco si aggiorna
    Widget swipeBg(Color c, IconData icon, String label, Alignment align) => Container(
      margin: const EdgeInsets.only(bottom: 8, left: 50),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      alignment: align,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w700)),
        ],
      ),
    );

    return Dismissible(
      key: ValueKey('swipe-${a.id}'),
      dismissThresholds: const {DismissDirection.startToEnd: 0.3, DismissDirection.endToStart: 0.3},
      background: swipeBg(AppColors.success, Icons.done_all, 'Completato', Alignment.centerLeft),
      secondaryBackground: swipeBg(AppColors.warning, Icons.person_off_outlined, 'Non presentato', Alignment.centerRight),
      confirmDismiss: (dir) async {
        onQuick(dir == DismissDirection.startToEnd ? AppointmentStatus.completed : AppointmentStatus.noShow);
        return false;
      },
      child: row,
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
    child: Text(text, style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
  );
}

class _GapRow extends StatelessWidget {
  const _GapRow({required this.gap, required this.onTap, required this.onLongPress});
  final _Gap gap;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final names = gap.barbers.map((b) => b.name).join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          _TimeColumn(time: formatTime(gap.start), strong: false),
          Expanded(
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.quietBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.add, size: 16, color: AppColors.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Libero fino alle ${formatTime(gap.end)} · ${fmtDuration(gap.end - gap.start)} · $names',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeOffRow extends StatelessWidget {
  const _TimeOffRow({
    required this.range,
    required this.reason,
    required this.barber,
    required this.showBarber,
    required this.color,
    required this.onTap,
  });
  final (int, int) range;
  final String reason;
  final Barber barber;
  final bool showBarber;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final allDay = range.$1 == 0 && range.$2 == 24 * 60;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          _TimeColumn(time: allDay ? 'Giorno' : formatTime(range.$1), strong: false),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.block, size: 16, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [
                          reason.isEmpty ? 'Assente' : reason,
                          allDay ? 'tutto il giorno' : '${formatTime(range.$1)} – ${formatTime(range.$2)}',
                          if (showBarber) barber.name,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.warning, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (showBarber)
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NowLine extends StatelessWidget {
  const _NowLine({super.key, required this.time});
  final DateTime time;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            fmtTime(time),
            style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
        ),
        Expanded(child: Container(height: 1.5, color: AppColors.danger)),
      ],
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
