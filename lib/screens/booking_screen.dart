import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/phone_notifier.dart';
import '../data/slots.dart';
import '../models.dart';
import '../notifications.dart';
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
  final _dayScroll = ScrollController(); // striscia dei giorni nel passo data/ora

  List<BusyInterval>? _busy;
  Map<DateTime, Map<DateTime, Barber>> _availability = {};

  /// Tutti gli orari del giorno (anche occupati), per mostrarli barrati.
  Map<DateTime, List<DateTime>> _allSlots = {};

  /// Persone in lista d'attesa per orario (senza nomi).
  List<WaitlistCount> _waitCounts = const [];

  /// La lista d'attesa e' per i clienti che prenotano un nuovo appuntamento.
  bool get _canWait => !widget.adminMode && !_moving;
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
        busyMin: a.busyMin,
      );
      _step = 1;
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    _dayScroll.dispose();
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
      // quanti sono in lista d'attesa per gli orari occupati (solo numeri)
      try {
        _waitCounts = await _state.backend.waitlistCounts(days.first, days.last.add(const Duration(days: 1)));
      } catch (_) {
        _waitCounts = const [];
      }
      final moving = widget.reschedule;
      if (moving != null) {
        // l'appuntamento da spostare non occupa il suo stesso orario
        _busy = _busy!
            .where(
              (b) => b.timeOff || b.barberId != moving.barberId || b.start != moving.start || b.end != moving.busyEnd,
            )
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
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToDay());
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  void _computeAvailability() {
    final step = _state.settings.slotStepMin;
    final dur = _service!.durationMin;
    // servizi con posa: il barbiere serve solo per il tempo iniziale
    final busyMin = _service!.busyDuration;
    _availability = {
      for (final d in _days)
        d: _anyBarber
            ? availableSlotsAnyBarber(
                barbers: _state.barbers,
                durationMin: dur,
                busyMin: busyMin,
                day: d,
                busy: _busy!,
                stepMin: step,
              )
            : {
                for (final s in availableSlots(
                  barber: _barber!,
                  durationMin: dur,
                  busyMin: busyMin,
                  day: d,
                  busy: _busy!,
                  stepMin: step,
                ))
                  s: _barber!,
              },
    };
    _allSlots = {
      for (final d in _days)
        d: candidateSlots(
          barbers: _anyBarber ? _state.barbers : [_barber!],
          durationMin: dur,
          day: d,
          stepMin: step,
        ),
    };
  }

  /// Orario occupato: si puo' entrare in lista d'attesa. Il cliente vede solo
  /// quante persone ci sono gia', mai chi.
  Future<void> _waitlistSheet(DateTime slot) async {
    final s = _service!;
    final barberId = _anyBarber ? null : _barber?.id;
    final already = waitingFor(_waitCounts, slot, barberId);
    final join = await showModalBottomSheet<bool>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Orario occupato', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                '${capitalize(fmtDayLong(slot))} · ${fmtTime(slot)} · ${s.name}'
                '${_anyBarber ? '' : ' · con ${_barber!.name}'}',
                style: const TextStyle(color: AppColors.silver, fontSize: 13.5),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1DB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0A030)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hourglass_bottom, color: Color(0xFF8A4B00)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        already == 0
                            ? 'Nessuno in lista d\'attesa: saresti il primo'
                            : already == 1
                            ? '1 persona già in lista d\'attesa: saresti il 2°'
                            : '$already persone già in lista d\'attesa: saresti il ${already + 1}°',
                        style: const TextStyle(color: Color(0xFF4A2800), fontSize: 14.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Se l\'orario si libera, il posto viene assegnato in automatico al primo in lista '
                'e lo trovi tra i tuoi appuntamenti.',
                style: TextStyle(color: AppColors.silver, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(c, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.quiet,
                    foregroundColor: AppColors.quietText,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Mettimi in lista d\'attesa', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Scegli un altro orario')),
            ],
          ),
        ),
      ),
    );
    if (join != true || !mounted) return;
    // anche senza account, come per la prenotazione
    final ok = await openBookingAuth(context);
    if (!ok || !mounted) return;
    try {
      final entry = await _state.backend.joinWaitlist(serviceId: s.id, barberId: barberId, start: slot);
      final mine = await _state.backend.myWaitlist();
      final pos = mine.where((w) => w.id == entry.id).firstOrNull?.position;
      if (!mounted) return;
      showMessage(
        context,
        'Sei in lista d\'attesa${pos == null ? '' : ': sei il $pos°'}. Se si libera, il posto è tuo.',
      );
      await _loadSlots();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  static const _dayW = 58.0, _dayGap = 8.0;

  /// Porta in vista il giorno scelto nella striscia dei giorni.
  void _scrollToDay() {
    if (!_dayScroll.hasClients || _day == null) return;
    final i = _days.indexOf(_day!);
    if (i < 0) return;
    final target = (i * (_dayW + _dayGap) - 24).clamp(0.0, _dayScroll.position.maxScrollExtent);
    _dayScroll.jumpTo(target);
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
      _state.ownChanges.add(widget.reschedule!.id);
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
        // sul telefono resta anche la notifica «Prenotazione confermata»
        final c = NotifSettings.fromJson(_state.settings.notifications).build(
          NotifKind.bookingConfirmed,
          notifValues(appt, _state.settings, clientName: _state.profile?.fullName ?? ''),
        );
        if (c != null) PhoneNotifier.instance.showNow(notifId(appt.id, NotifKind.bookingConfirmed), c);
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
        // in alto il nome del passo e "3 di 4", sotto la barra di avanzamento
        title: _moving && _step == 3 ? 'Sposta appuntamento' : _steps[_step],
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${_step + 1} di ${_steps.length}',
                style: const TextStyle(color: AppColors.silver, fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
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

  /// Riepilogo del servizio scelto, con "Cambia".
  Widget _summaryCard() {
    final s = _service!;
    final assigned = _slot == null ? null : _availability[_day]?[_slot];
    final who = _anyBarber ? (assigned?.name ?? 'Primo disponibile') : (_barber?.name ?? '');
    return Material(
      color: Colors.white.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.white.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        child: Row(
          children: [
            ServiceIcon(s.name, size: 42, square: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  Text(
                    '${fmtDuration(s.durationMin)} · ${fmtPrice(s.price)} · $who',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.silver, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            TextButton(
              // spostando, il servizio resta quello: si cambia il barbiere
              onPressed: () => setState(() => _step = _moving || widget.initialBarber != null ? 1 : 0),
              child: const Text('Cambia', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTime() {
    if (_loadingSlots || _busy == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final free = _availability[_day] ?? {};
    final all = _allSlots[_day] ?? const <DateTime>[];
    final groups = <String, List<(DateTime, bool)>>{
      'Mattina': [for (final s in all) if (s.hour < 13) (s, free.containsKey(s))],
      'Pomeriggio': [for (final s in all) if (s.hour >= 13) (s, free.containsKey(s))],
    }..removeWhere((_, v) => v.isEmpty);
    final days = _days;

    return ResponsiveCenter(
      maxWidth: 640,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _summaryCard(),
          const SizedBox(height: 14),
          Text(
            _day == null ? '' : capitalize(DateFormat('MMMM yyyy', 'it_IT').format(_day!)),
            style: const TextStyle(color: AppColors.white, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.4),
          ),
          const SizedBox(height: 8),
          // striscia dei giorni: pallino verde = libero, arancio = pochi posti,
          // grigio e barrato = chiuso o pieno
          SizedBox(
            height: 76,
            child: ListView.separated(
              controller: _dayScroll,
              scrollDirection: Axis.horizontal,
              itemCount: days.length,
              separatorBuilder: (_, _) => const SizedBox(width: _dayGap),
              itemBuilder: (context, i) {
                final d = days[i];
                final n = _availability[d]?.length ?? 0;
                return SizedBox(
                  width: _dayW,
                  child: _DayChip(
                    day: d,
                    selected: d == _day,
                    level: n == 0
                        ? _DayLevel.closed
                        : n <= 3
                        ? _DayLevel.few
                        : _DayLevel.free,
                    onTap: () => setState(() {
                      _day = d;
                      _slot = null;
                    }),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: free.isEmpty
                ? EmptyState(
                    icon: Icons.event_busy,
                    text: all.isEmpty
                        ? 'In questa data siamo chiusi.\nScegli un altro giorno.'
                        : 'Questo giorno è al completo.\nScegli un altro giorno.',
                  )
                : _SlotGrid(
                    groups: groups,
                    selected: _slot,
                    onSelect: (s) => setState(() => _slot = s),
                    waiting: {
                      for (final (s, isFree) in groups.values.expand((g) => g))
                        if (!isFree) s: waitingFor(_waitCounts, s, _anyBarber ? null : _barber?.id),
                    },
                    onWaitlist: _canWait ? _waitlistSheet : null,
                  ),
          ),
          _Legend(waitlist: _canWait && free.length < all.length),
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

  /// Pulsante nero in fondo: "Continua · Ven 16, 10:30" o la conferma.
  Widget _buildBottomBar() {
    final slot = _slot;
    final when = slot == null ? '' : '${capitalize(DateFormat('EEE d', 'it_IT').format(slot))}, ${fmtTime(slot)}';
    final String label;
    final VoidCallback? onTap;
    if (_step == 2) {
      label = slot == null ? 'Scegli un orario' : 'Continua · $when';
      onTap = slot == null ? null : () => _goTo(3);
    } else {
      label = _moving
          ? 'Sposta · $when'
          : widget.adminMode
          ? 'Inserisci appuntamento'
          : 'Conferma prenotazione';
      onTap = _booking ? null : _confirm;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: ResponsiveCenter(
        maxWidth: 640,
        child: SizedBox(
          height: 56,
          child: FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.quiet,
              foregroundColor: AppColors.quietText,
              disabledBackgroundColor: AppColors.quiet.withValues(alpha: 0.35),
              disabledForegroundColor: AppColors.quietText.withValues(alpha: 0.8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: exo(fontSize: 15.5, fontWeight: FontWeight.w800, letterSpacing: 0.3),
            ),
            child: _booking
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.quietText),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (onTap != null) ...[const SizedBox(width: 8), const Icon(Icons.chevron_right, size: 22)],
                    ],
                  ),
          ),
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

  /// Barra di avanzamento a segmenti (i passi gia' fatti si possono toccare).
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2, bottom: 14),
    child: Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: steps[i],
              child: InkWell(
                onTap: () => onTap(i),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= current ? AppColors.white : AppColors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

enum _DayLevel { free, few, closed }

const _freeGreen = Color(0xFF1F9D55);
const _fewOrange = Color(0xFFE08A1E);

/// Giorno della striscia: giorno della settimana, numero e pallino di disponibilita'.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.day, required this.selected, required this.level, required this.onTap});
  final DateTime day;
  final bool selected;
  final _DayLevel level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final closed = level == _DayLevel.closed;
    final fg = selected ? AppColors.quietText : (closed ? AppColors.muted.withValues(alpha: 0.55) : AppColors.white);
    final dot = switch (level) {
      _DayLevel.free => _freeGreen,
      _DayLevel.few => _fewOrange,
      _DayLevel.closed => AppColors.muted.withValues(alpha: 0.4),
    };
    return InkWell(
      onTap: closed ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? AppColors.quiet : Colors.white.withValues(alpha: closed ? 0.22 : 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.white.withValues(alpha: selected ? 1 : 0.12)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat('EEE', 'it_IT').format(day).replaceAll('.', '').toUpperCase(),
              style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8),
            ),
            const SizedBox(height: 1),
            Text(
              '${day.day}',
              style: TextStyle(
                color: fg,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                decoration: closed ? TextDecoration.lineThrough : null,
                decorationColor: fg,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dot,
                border: selected ? Border.all(color: AppColors.quietText, width: 1) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Orario: libero (bordo verde), occupato (grigio e barrato) o scelto (nero).
/// Un orario occupato si puo' toccare per mettersi in lista d'attesa
/// ([onWaitlist]); il numerino indica quanti sono gia' in lista.
class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.free = true,
    this.waiting = 0,
    this.onWaitlist,
  });
  final String label;
  final bool selected;
  final bool free;
  final VoidCallback onTap;
  final int waiting;
  final VoidCallback? onWaitlist;

  @override
  Widget build(BuildContext context) {
    final Color bg, border, fg;
    if (selected) {
      (bg, border, fg) = (AppColors.quiet, AppColors.quiet, AppColors.quietText);
    } else if (free) {
      (bg, border, fg) = (Colors.white.withValues(alpha: 0.7), _freeGreen, AppColors.white);
    } else {
      (bg, border, fg) = (
        AppColors.white.withValues(alpha: 0.07),
        AppColors.white.withValues(alpha: 0.08),
        AppColors.muted.withValues(alpha: 0.6),
      );
    }
    return InkWell(
      onTap: free ? onTap : onWaitlist,
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border, width: free && !selected ? 1.4 : 1),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  decoration: free ? null : TextDecoration.lineThrough,
                  decorationColor: fg,
                ),
              ),
            ),
          ),
          // quanti sono in lista d'attesa per questo orario (solo il numero)
          if (!free && waiting > 0)
            Positioned(
              top: -6,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: _fewOrange, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hourglass_bottom, size: 10, color: Colors.white),
                    Text(
                      '$waiting',
                      style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Legenda sotto gli orari.
class _Legend extends StatelessWidget {
  const _Legend({this.waitlist = false});

  /// Mostra il suggerimento per la lista d'attesa.
  final bool waitlist;

  Widget _item(Widget mark, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      mark,
      const SizedBox(width: 5),
      Text(text, style: const TextStyle(color: AppColors.silver, fontSize: 12, fontWeight: FontWeight.w600)),
    ],
  );

  Widget _box(Color bg, Color border) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: border, width: 1.4),
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Wrap(
      spacing: 14,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        _item(_box(Colors.white.withValues(alpha: 0.7), _freeGreen), 'Libero'),
        _item(_box(AppColors.white.withValues(alpha: 0.07), AppColors.white.withValues(alpha: 0.12)), 'Occupato'),
        _item(_box(AppColors.quiet, AppColors.quiet), 'Scelto'),
        _item(
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: _fewOrange),
          ),
          'Pochi posti',
        ),
        if (waitlist)
          const Text(
            'Orario occupato? Toccalo per la lista d\'attesa',
            style: TextStyle(color: AppColors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
      ],
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

/// Griglia degli orari che si adatta allo spazio disponibile: piu' colonne
/// e righe piu' basse quando gli orari sono tanti, cosi' la pagina non scorre.
/// Se gli orari sono troppi per restare leggibili (es. intervallo di 5 minuti)
/// si sceglie prima l'ora e poi i minuti.
class _SlotGrid extends StatefulWidget {
  const _SlotGrid({
    required this.groups,
    required this.selected,
    required this.onSelect,
    this.waiting = const {},
    this.onWaitlist,
  });

  /// Orari per fascia: (orario, libero?).
  final Map<String, List<(DateTime, bool)>> groups;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  /// Persone in lista d'attesa per gli orari occupati.
  final Map<DateTime, int> waiting;

  /// Tocco su un orario occupato: lista d'attesa (null = non disponibile).
  final ValueChanged<DateTime>? onWaitlist;

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
  ({int cols, double rowH, double w, double scale}) _layout(
    Map<String, List<(DateTime, bool)>> groups,
    BoxConstraints c,
  ) {
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

  /// "MATTINA   4 liberi"
  Widget _label(String text, [int? free]) => SizedBox(
    height: _labelH,
    child: Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Text(
              text.toUpperCase(),
              style: const TextStyle(color: AppColors.white, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.4),
            ),
            if (free != null) ...[
              const SizedBox(width: 8),
              Text(
                free == 1 ? '1 libero' : '$free liberi',
                style: const TextStyle(color: AppColors.silver, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _grid(Map<String, List<(DateTime, bool)>> groups, BoxConstraints c) {
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
              _label(g.key, g.value.where((e) => e.$2).length),
              Wrap(
                spacing: _gap,
                runSpacing: _gap,
                children: [
                  for (final (s, free) in g.value)
                    SizedBox(
                      width: l.w,
                      height: l.rowH,
                      child: _SlotChip(
                        label: fmtTime(s),
                        free: free,
                        selected: s == widget.selected,
                        onTap: () => widget.onSelect(s),
                        waiting: widget.waiting[s] ?? 0,
                        onWaitlist: widget.onWaitlist == null ? null : () => widget.onWaitlist!(s),
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
      // (solo le ore con almeno un orario libero)
      final byHour = <int, List<(DateTime, bool)>>{};
      for (final e in widget.groups.values.expand((g) => g)) {
        byHour.putIfAbsent(e.$1.hour, () => []).add(e);
      }
      byHour.removeWhere((_, v) => !v.any((e) => e.$2));
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
