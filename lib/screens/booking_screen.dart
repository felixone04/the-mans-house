import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/slots.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'admin/customer_picker.dart';
import 'auth_screen.dart';
import 'booking_success_screen.dart';

/// Prenotazione in 4 passi: servizio, barbiere, data e ora, conferma.
/// In [adminMode] il titolare inserisce un appuntamento per un cliente
/// (es. prenotazione telefonica).
/// Con [reschedule] si sposta un appuntamento esistente: il servizio resta
/// lo stesso e si sceglie solo barbiere, data e ora. Ritorna true se spostato.
class BookingScreen extends StatefulWidget {
  const BookingScreen({
    super.key,
    this.adminMode = false,
    this.initialDay,
    this.initialBarber,
    this.initialTime,
    this.reschedule,
    this.initialCustomerName,
    this.initialCustomerPhone,
  });
  final bool adminMode;
  final DateTime? initialDay;

  /// Se impostato, il passo "barbiere" viene saltato.
  final Barber? initialBarber;
  final DateTime? initialTime;
  final Appointment? reschedule;

  /// Cliente gia' noto (dalla scheda cliente).
  final String? initialCustomerName;
  final String? initialCustomerPhone;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  static const _steps = ['Servizio', 'Barbiere', 'Data e ora', 'Conferma'];

  int _step = 0;
  Service? _service;
  Barber? _barber;
  bool _anyBarber = false;
  DateTime? _day;
  DateTime? _slot;
  int _week = 0; // settimana mostrata nel passo data/ora

  List<BusyInterval>? _busy;
  Map<DateTime, Map<DateTime, Barber>> _availability = {};
  bool _loadingSlots = false;
  bool _booking = false;

  final _notes = TextEditingController();

  /// Admin: cliente scelto (esistente, nuovo o senza dati); dalla scheda
  /// cliente arriva gia' impostato.
  late BookingCustomer? _customer = (widget.initialCustomerName ?? '').isEmpty
      ? null
      : BookingCustomer(name: widget.initialCustomerName!, phone: widget.initialCustomerPhone ?? '');

  AppState get _state => AppScope.read(context);

  bool get _moving => widget.reschedule != null;

  @override
  void initState() {
    super.initState();
    final a = widget.reschedule;
    if (a != null) {
      // servizio fisso: durata e prezzo dell'appuntamento originale
      _service = Service(
        id: a.serviceId ?? '',
        name: a.serviceName,
        durationMin: a.end.difference(a.start).inMinutes,
        price: a.price,
      );
      _step = 1;
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  List<DateTime> get _days {
    final today = dayOnly(DateTime.now());
    final n = widget.adminMode ? 90 : _state.settings.bookingDaysAhead;
    return [for (var i = 0; i <= n; i++) DateTime(today.year, today.month, today.day + i)];
  }

  Future<void> _loadSlots() async {
    setState(() => _loadingSlots = true);
    try {
      final days = _days;
      _busy = await _state.backend.fetchBusy(days.first, days.last.add(const Duration(days: 1)));
      final moving = widget.reschedule;
      if (moving != null) {
        // l'appuntamento da spostare non occupa il suo stesso orario
        _busy = _busy!
            .where((b) => b.timeOff || b.barberId != moving.barberId || b.start != moving.start || b.end != moving.end)
            .toList();
      }
      _computeAvailability();
      final initialDay = widget.initialDay ?? moving?.start;
      final preferred = initialDay == null ? null : dayOnly(initialDay);
      if (_day == null || (_availability[_day]?.isEmpty ?? true)) {
        _day = (preferred != null && (_availability[preferred]?.isNotEmpty ?? false))
            ? preferred
            : days.firstWhere((d) => _availability[d]?.isNotEmpty ?? false, orElse: () => days.first);
      }
      // Dall'agenda: orario toccato nel calendario, se libero
      // (il tocco e' arrotondato al quarto d'ora: si prende l'orario libero piu'
      // vicino, anche se l'intervallo tra gli orari e' diverso da 15 minuti)
      final t = widget.initialTime;
      final daySlots = t == null ? const <DateTime>[] : (_availability[dayOnly(t)]?.keys ?? const <DateTime>[]);
      final tolerance = _state.settings.slotStepMin < 15 ? 15 : _state.settings.slotStepMin;
      DateTime? nearest;
      for (final s in daySlots) {
        final diff = s.difference(t!).inMinutes.abs();
        if (diff < tolerance && (nearest == null || diff < nearest.difference(t).inMinutes.abs())) nearest = s;
      }
      if (_slot == null && nearest != null) {
        _day = dayOnly(nearest);
        _slot = nearest;
      }
      if (_day != null) _showWeekOf(_day!);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  void _computeAvailability() {
    final step = _state.settings.slotStepMin;
    final dur = _service!.durationMin;
    _availability = {
      for (final d in _days)
        d: _anyBarber
            ? availableSlotsAnyBarber(barbers: _state.barbers, durationMin: dur, day: d, busy: _busy!, stepMin: step)
            : {
                for (final s in availableSlots(barber: _barber!, durationMin: dur, day: d, busy: _busy!, stepMin: step))
                  s: _barber!,
              },
    };
  }

  void _goTo(int step) {
    setState(() => _step = step);
    if (step == 2) _loadSlots();
  }

  void _back() {
    if (_step == 0 || (_moving && _step == 1)) {
      Navigator.of(context).pop();
    } else {
      setState(() => _step--);
    }
  }

  Future<void> _move() async {
    final barber = _availability[_day]?[_slot];
    if (barber == null) return;
    setState(() => _booking = true);
    try {
      await _state.backend.rescheduleAppointment(widget.reschedule!.id, barberId: barber.id, start: _slot!);
      if (!widget.adminMode) await _state.refreshAppointments();
      if (!mounted) return;
      showMessage(context, 'Appuntamento spostato a ${fmtDayShort(_slot!)} alle ${fmtTime(_slot!)}');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showError(context, e);
      if (e.toString().contains('disponibile')) {
        _slot = null;
        _goTo(2);
      }
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  Future<void> _confirm() async {
    if (_moving) return _move();
    if (widget.adminMode) {
      if (_customer == null) {
        final c = await pickCustomer(context);
        if (c == null || !mounted) return;
        setState(() => _customer = c);
      }
    } else {
      // chi non ha l'account puo' prenotare come ospite
      final ok = await openBookingAuth(context);
      if (!ok || !mounted) return;
    }
    final customer = _customer;
    final barber = _availability[_day]?[_slot];
    if (barber == null) return;

    setState(() => _booking = true);
    try {
      final appt = await _state.backend.book(
        barberId: barber.id,
        serviceId: _service!.id,
        start: _slot!,
        notes: _notes.text.trim(),
        // admin: cliente con account (userId) oppure dal banco (nome e contatti)
        customerUserId: widget.adminMode ? customer?.userId : null,
        customerName: widget.adminMode && customer?.userId == null ? customer?.name : null,
        customerPhone: widget.adminMode && customer?.userId == null ? customer?.phone : null,
        customerEmail: widget.adminMode && customer?.userId == null ? customer?.email : null,
      );
      appt.barberName = barber.name;
      if (!mounted) return;
      if (widget.adminMode) {
        showMessage(context, 'Appuntamento inserito');
        Navigator.of(context).pop(true);
      } else {
        await _state.refreshAppointments();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(fadeRoute(BookingSuccessScreen(appointment: appt)));
      }
    } catch (e) {
      if (!mounted) return;
      showError(context, e);
      if (e.toString().contains('disponibile')) {
        _slot = null;
        _goTo(2);
      }
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return PopScope(
      canPop: _step == 0 || (_moving && _step == 1),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AppScaffold(
        title: _moving ? 'Sposta appuntamento' : (widget.adminMode ? 'Nuovo appuntamento' : 'Prenota'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        body: SafeArea(
          child: Column(
            children: [
              ResponsiveCenter(
                maxWidth: 640,
                child: _StepIndicator(
                  steps: _steps,
                  current: _step,
                  onTap: (i) {
                    // spostando, il servizio non si cambia
                    if (i < _step && !(_moving && i == 0)) setState(() => _step = i);
                  },
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: switch (_step) {
                      0 => _buildServices(state),
                      1 => _buildBarbers(state),
                      2 => _buildDateTime(),
                      _ => _buildConfirm(state),
                    },
                  ),
                ),
              ),
              if (_step >= 2) _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  // --- Passo 1: servizio ---

  Widget _buildServices(AppState state) {
    if (state.services.isEmpty) {
      return const EmptyState(icon: Icons.content_cut, text: 'Nessun servizio disponibile');
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ResponsiveCenter(
          maxWidth: 640,
          child: Column(
            children: [
              const ShopHeading('Il listino', subtitle: 'Scegli il servizio'),
              for (final s in state.services)
                _PriceListRow(
                  service: s,
                  selected: _service?.id == s.id,
                  onTap: () {
                    _service = s;
                    _slot = null;
                    if (widget.initialBarber != null) {
                      _barber = widget.initialBarber;
                      _anyBarber = false;
                      _goTo(2);
                    } else {
                      _goTo(1);
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Passo 2: barbiere ---

  String _workDays(Barber b) {
    const short = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
    final days = [
      for (var d = 1; d <= 7; d++)
        if (b.hoursFor(d).isNotEmpty) short[d - 1],
    ];
    return days.isEmpty ? 'Nessun orario' : days.join(' · ');
  }

  Widget _buildBarbers(AppState state) {
    return FitBody(
      maxWidth: 640,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ShopHeading('I nostri barbieri', subtitle: 'Con chi vuoi prenotare?'),
          GlassCard(
            margin: const EdgeInsets.only(bottom: 10),
            selected: _anyBarber,
            onTap: () {
              _anyBarber = true;
              _barber = null;
              _slot = null;
              _goTo(2);
            },
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white.withValues(alpha: 0.25)),
                  ),
                  child: const Icon(Icons.groups_outlined),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Primo disponibile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      SizedBox(height: 2),
                      Text(
                        'Scegli l\'orario, il barbiere te lo assegniamo noi',
                        style: TextStyle(color: AppColors.silver, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.muted),
              ],
            ),
          ),
          for (final b in state.barbers)
            GlassCard(
              margin: const EdgeInsets.only(bottom: 10),
              selected: !_anyBarber && _barber?.id == b.id,
              onTap: () {
                _anyBarber = false;
                _barber = b;
                _slot = null;
                _goTo(2);
              },
              child: Row(
                children: [
                  BarberAvatar(barber: b, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(b.name, style: slab(size: 17, weight: FontWeight.w600, spacing: 0.4)),
                        Text(b.title, style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(_workDays(b), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.muted),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // --- Passo 3: data e ora ---

  DateTime get _thisMonday {
    final today = dayOnly(DateTime.now());
    return DateTime(today.year, today.month, today.day - (today.weekday - 1));
  }

  /// Lunedi' della settimana mostrata (settimane navigabili con le frecce).
  DateTime get _weekStart => DateTime(_thisMonday.year, _thisMonday.month, _thisMonday.day + 7 * _week);

  int get _maxWeek => _days.last.difference(_thisMonday).inDays ~/ 7;

  void _showWeekOf(DateTime d) => _week = dayOnly(d).difference(_thisMonday).inDays ~/ 7;

  Widget _buildDateTime() {
    if (_loadingSlots || _busy == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final slots = _availability[_day] ?? {};
    final groups = <String, List<DateTime>>{
      'Mattina': slots.keys.where((s) => s.hour < 13).toList(),
      'Pomeriggio': slots.keys.where((s) => s.hour >= 13 && s.hour < 17).toList(),
      'Sera': slots.keys.where((s) => s.hour >= 17).toList(),
    }..removeWhere((_, v) => v.isEmpty);
    final start = _weekStart;
    final week = [for (var i = 0; i < 7; i++) DateTime(start.year, start.month, start.day + i)];
    final assigned = _slot == null ? null : slots[_slot];

    return ResponsiveCenter(
      maxWidth: 640,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Settimana con frecce: niente scorrimento orizzontale
          Row(
            children: [
              IconButton(
                onPressed: _week > 0 ? () => setState(() => _week--) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  capitalize(DateFormat('MMMM yyyy', 'it_IT').format(week[3])),
                  textAlign: TextAlign.center,
                  style: slab(size: 15, weight: FontWeight.w600, spacing: 1),
                ),
              ),
              IconButton(
                onPressed: _week < _maxWeek ? () => setState(() => _week++) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            children: [
              for (var i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _DayChip(
                    day: week[i],
                    selected: week[i] == _day,
                    enabled: _availability[week[i]]?.isNotEmpty ?? false,
                    onTap: () => setState(() {
                      _day = week[i];
                      _slot = null;
                    }),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          // altezza fissa e suggerimento sempre visibile: scegliendo l'orario
          // compare il badge senza spostare la griglia sotto il dito
          SizedBox(
            height: 34,
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _day == null ? '' : fmtDayLong(_day!),
                      style: slab(size: 16, weight: FontWeight.w600, spacing: 0.5),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_anyBarber && assigned != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: _AssignedBadge(barber: assigned),
                  ),
              ],
            ),
          ),
          if (_anyBarber)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                'Barbiere assegnato in automatico in base all\'orario',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: slots.isEmpty
                ? const EmptyState(
                    icon: Icons.event_busy,
                    text: 'Nessun orario libero in questa data.\nProva un altro giorno.',
                  )
                : _SlotGrid(groups: groups, selected: _slot, onSelect: (s) => setState(() => _slot = s)),
          ),
        ],
      ),
    );
  }

  // --- Passo 4: conferma ---

  Widget _buildConfirm(AppState state) {
    final barber = _availability[_day]?[_slot];
    final s = _service!;
    Widget row(IconData icon, String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.muted),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppColors.silver)),
          const SizedBox(width: 16),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: value),
          ),
        ],
      ),
    );
    Text bold(String t) => Text(
      t,
      textAlign: TextAlign.right,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
    );

    return FitBody(
      maxWidth: 640,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_moving)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 18, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Prima: ${fmtDayShort(widget.reschedule!.start)} alle ${fmtTime(widget.reschedule!.start)}'
                      '${widget.reschedule!.barberName.isEmpty ? '' : ' con ${widget.reschedule!.barberName}'}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Column(
              children: [
                if (_moving && widget.reschedule!.customerName.isNotEmpty && widget.adminMode) ...[
                  row(Icons.person, 'Cliente', bold(widget.reschedule!.customerName)),
                  const Divider(),
                ],
                row(Icons.content_cut, 'Servizio', bold(s.name)),
                const Divider(),
                row(
                  Icons.person_outline,
                  _anyBarber ? 'Assegnato a' : 'Barbiere',
                  barber == null
                      ? bold('-')
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BarberAvatar(barber: barber, size: 26),
                            const SizedBox(width: 8),
                            bold(barber.name),
                          ],
                        ),
                ),
                const Divider(),
                row(Icons.calendar_today_outlined, 'Data', bold(_day == null ? '-' : fmtDayLong(_day!))),
                const Divider(),
                row(
                  Icons.schedule,
                  'Ora',
                  bold(
                    _slot == null
                        ? '-'
                        : '${fmtTime(_slot!)} – ${fmtTime(_slot!.add(Duration(minutes: s.durationMin)))}',
                  ),
                ),
                const Divider(),
                row(Icons.euro, 'Prezzo', bold(fmtPrice(s.price))),
              ],
            ),
          ),
          if (_anyBarber && barber != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${barber.name} è stato scelto in automatico tra i barbieri liberi a quest\'ora.',
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            ),
          if (widget.adminMode && !_moving) ...[
            const SectionTitle('Cliente'),
            GlassCard(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              onTap: () async {
                final c = await pickCustomer(context);
                if (c != null && mounted) setState(() => _customer = c);
              },
              child: Row(
                children: [
                  Icon(
                    _customer == null
                        ? Icons.person_search_outlined
                        : _customer!.anonymous
                        ? Icons.bolt
                        : Icons.person,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _customer?.name ?? 'Scegli il cliente',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                        Text(
                          _customer == null ? 'Esistente, nuovo o senza dati' : _customer!.detail,
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _customer == null ? 'Scegli' : 'Cambia',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (!_moving) ...[
            TextField(
              controller: _notes,
              maxLines: 2,
              minLines: 1,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Note (facoltative)',
                hintText: 'Es. sfumatura alta, barba corta...',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.notifications_active_outlined, size: 18, color: AppColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _moving
                      ? 'I promemoria WhatsApp verranno inviati in base al nuovo orario.'
                      : widget.adminMode
                      ? 'Se è indicato il cellulare, il cliente riceverà un promemoria su WhatsApp '
                            '24 ore e 1 ora prima.'
                      : 'Riceverai un promemoria su WhatsApp 24 ore e 1 ora prima. '
                            'Puoi annullare dall\'app fino a ${state.settings.minCancelHours} ore prima.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final canContinue = _slot != null;
    final barber = _slot == null ? null : _availability[_day]?[_slot];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.6),
        border: Border(top: BorderSide(color: AppColors.white.withValues(alpha: 0.18))),
      ),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      child: ResponsiveCenter(
        maxWidth: 640,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _service?.name ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _slot == null ? 'Scegli un orario' : '${fmtDayShort(_slot!)} · ${fmtTime(_slot!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.silver, fontSize: 13),
                  ),
                  // riga a parte (sempre presente, cosi' la griglia non si sposta):
                  // sui telefoni stretti "assegnato a ..." veniva troncato
                  Text(
                    barber == null
                        ? (_anyBarber ? 'barbiere: primo disponibile' : 'con ${_barber?.name ?? ''}')
                        : '${_anyBarber ? 'assegnato a ' : 'con '}${barber.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _anyBarber ? AppColors.white : AppColors.silver,
                      fontSize: 13,
                      fontWeight: _anyBarber ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 170,
              child: _step == 2
                  ? FilledButton(onPressed: canContinue ? () => _goTo(3) : null, child: const Text('CONTINUA'))
                  : FilledButton(
                      onPressed: _booking ? null : _confirm,
                      child: _booking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.black),
                            )
                          : Text(_moving ? 'SPOSTA' : 'CONFERMA'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.steps, required this.current, required this.onTap});
  final List<String> steps;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 12),
    child: Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 3,
                    decoration: BoxDecoration(
                      color: i <= current ? AppColors.white : AppColors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    steps[i].toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                      color: i == current ? AppColors.white : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day, required this.selected, required this.enabled, required this.onTap});
  final DateTime day;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.black : (enabled ? AppColors.white : AppColors.muted.withValues(alpha: 0.5));
    final parts = fmtDayShort(day).split(' '); // Lun 12 Ott
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.white : Colors.white.withValues(alpha: enabled ? 0.55 : 0.18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.white.withValues(alpha: selected ? 1 : 0.10)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              parts[0].replaceAll('.', '').toUpperCase(),
              style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1),
            ),
            const SizedBox(height: 2),
            Text(
              parts[1],
              style: slab(size: 19, color: fg, weight: FontWeight.w700, spacing: 0),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? AppColors.white : Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.white.withValues(alpha: selected ? 1 : 0.10)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? AppColors.black : AppColors.white,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),
  );
}

/// Riga del listino: icona, nome ····· prezzo, durata e descrizione.
class _PriceListRow extends StatelessWidget {
  const _PriceListRow({required this.service, required this.selected, required this.onTap});
  final Service service;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = service;
    // un blocco incorniciato per servizio: icona in un quadrato, nome e durata, prezzo a destra
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? Colors.white.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? AppColors.white : AppColors.white.withValues(alpha: 0.16),
            width: selected ? 1.4 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ServiceIcon(s.name, size: 56, selected: selected, square: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: slab(size: 16, weight: FontWeight.w600, spacing: 0.3)),
                      const SizedBox(height: 3),
                      Text(
                        fmtDuration(s.durationMin),
                        style: const TextStyle(color: AppColors.silver, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      if (s.description.isNotEmpty)
                        Text(
                          s.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(fmtPrice(s.price), style: slab(size: 19, weight: FontWeight.w700, spacing: 0.2)),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barbiere assegnato in automatico ("primo disponibile").
class _AssignedBadge extends StatelessWidget {
  const _AssignedBadge({required this.barber});
  final Barber barber;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
    decoration: BoxDecoration(
      color: AppColors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.white.withValues(alpha: 0.4)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BarberAvatar(barber: barber, size: 24),
        const SizedBox(width: 8),
        Flexible(
          child: Text.rich(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Assegnato a ',
                  style: TextStyle(color: AppColors.silver, fontSize: 12.5),
                ),
                TextSpan(
                  text: barber.name,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// Griglia degli orari che si adatta allo spazio disponibile: piu' colonne
/// e righe piu' basse quando gli orari sono tanti, cosi' la pagina non scorre.
/// Se gli orari sono troppi per restare leggibili (es. intervallo di 5 minuti)
/// si sceglie prima l'ora e poi i minuti.
class _SlotGrid extends StatefulWidget {
  const _SlotGrid({required this.groups, required this.selected, required this.onSelect});
  final Map<String, List<DateTime>> groups;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  @override
  State<_SlotGrid> createState() => _SlotGridState();
}

class _SlotGridState extends State<_SlotGrid> {
  static const _gap = 8.0;
  static const _labelH = 28.0;

  /// Sotto questa riduzione gli orari diventano poco leggibili.
  static const _minScale = 0.85;

  int? _hour; // ora scelta nella vista "per ora"

  /// Colonne e altezza delle righe; [scale] e' la riduzione che servirebbe.
  ({int cols, double rowH, double w, double scale}) _layout(Map<String, List<DateTime>> groups, BoxConstraints c) {
    // colonne larghe almeno 54 px per leggere bene l'orario
    final maxCols = ((c.maxWidth + _gap) / (54 + _gap)).floor().clamp(3, 8);
    int rowsFor(int cols) => groups.values.fold<int>(0, (n, g) => n + (g.length + cols - 1) ~/ cols);
    // altezza delle righe che riempie lo spazio (le spaziature sono tra le righe di ogni gruppo)
    double fill(int cols) {
      final rows = rowsFor(cols);
      return (c.maxHeight - groups.length * _labelH - (rows - groups.length) * _gap) / rows;
    }

    var cols = 4.clamp(3, maxCols);
    while (cols < maxCols && fill(cols) < 38) {
      cols++;
    }
    final rowH = fill(cols).clamp(30.0, 46.0);
    final rows = rowsFor(cols);
    final height = groups.length * _labelH + rows * rowH + (rows - groups.length) * _gap;
    return (
      cols: cols,
      rowH: rowH,
      w: (c.maxWidth - (cols - 1) * _gap) / cols,
      scale: height <= c.maxHeight ? 1.0 : c.maxHeight / height,
    );
  }

  Widget _label(String text) => SizedBox(
    height: _labelH,
    child: Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.6),
        ),
      ),
    ),
  );

  Widget _grid(Map<String, List<DateTime>> groups, BoxConstraints c) {
    final l = _layout(groups, c);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: c.maxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final g in groups.entries) ...[
              _label(g.key),
              Wrap(
                spacing: _gap,
                runSpacing: _gap,
                children: [
                  for (final s in g.value)
                    SizedBox(
                      width: l.w,
                      height: l.rowH,
                      child: _SlotChip(
                        label: fmtTime(s),
                        selected: s == widget.selected,
                        onTap: () => widget.onSelect(s),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (_layout(widget.groups, c).scale >= _minScale) return _grid(widget.groups, c);

      // Troppi orari: prima l'ora, poi i minuti di quell'ora
      final byHour = <int, List<DateTime>>{};
      for (final s in widget.groups.values.expand((g) => g)) {
        byHour.putIfAbsent(s.hour, () => []).add(s);
      }
      final sel = widget.selected;
      final hour = byHour.containsKey(_hour)
          ? _hour!
          : (sel != null && byHour.containsKey(sel.hour) ? sel.hour : byHour.keys.first);
      final hourCols = byHour.length.clamp(1, ((c.maxWidth + _gap) / (44 + _gap)).floor().clamp(4, 12));
      final hourW = (c.maxWidth - (hourCols - 1) * _gap) / hourCols;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Ora'),
          Wrap(
            spacing: _gap,
            runSpacing: _gap,
            children: [
              for (final h in byHour.keys)
                SizedBox(
                  width: hourW,
                  height: 38,
                  child: _SlotChip(label: '$h', selected: h == hour, onTap: () => setState(() => _hour = h)),
                ),
            ],
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c2) {
                return _grid({'Orari dalle ${hour.toString().padLeft(2, '0')}:00': byHour[hour]!}, c2);
              },
            ),
          ),
        ],
      );
    },
  );
}
