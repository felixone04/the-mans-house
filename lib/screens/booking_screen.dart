import 'package:flutter/material.dart';

import '../data/slots.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'auth_screen.dart';
import 'booking_success_screen.dart';

/// Prenotazione in 4 passi: servizio, barbiere, data e ora, conferma.
/// In [adminMode] il titolare inserisce un appuntamento per un cliente
/// (es. prenotazione telefonica).
class BookingScreen extends StatefulWidget {
  const BookingScreen({
    super.key,
    this.adminMode = false,
    this.initialDay,
    this.initialBarber,
    this.initialTime,
  });
  final bool adminMode;
  final DateTime? initialDay;

  /// Se impostato, il passo "barbiere" viene saltato.
  final Barber? initialBarber;
  final DateTime? initialTime;

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

  List<BusyInterval>? _busy;
  Map<DateTime, Map<DateTime, Barber>> _availability = {};
  bool _loadingSlots = false;
  bool _booking = false;

  final _notes = TextEditingController();
  final _customerName = TextEditingController();
  final _customerPhone = TextEditingController(text: '+39 ');
  final _adminForm = GlobalKey<FormState>();

  AppState get _state => AppScope.read(context);

  @override
  void dispose() {
    _notes.dispose();
    _customerName.dispose();
    _customerPhone.dispose();
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
      _computeAvailability();
      final preferred = widget.initialDay == null ? null : dayOnly(widget.initialDay!);
      if (_day == null || (_availability[_day]?.isEmpty ?? true)) {
        _day = (preferred != null && (_availability[preferred]?.isNotEmpty ?? false))
            ? preferred
            : days.firstWhere((d) => _availability[d]?.isNotEmpty ?? false, orElse: () => days.first);
      }
      // Dall'agenda: orario toccato nel calendario, se libero
      final t = widget.initialTime;
      if (_slot == null && t != null && (_availability[dayOnly(t)]?.containsKey(t) ?? false)) {
        _day = dayOnly(t);
        _slot = t;
      }
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
            ? availableSlotsAnyBarber(
                barbers: _state.barbers, durationMin: dur, day: d, busy: _busy!, stepMin: step)
            : {
                for (final s in availableSlots(
                    barber: _barber!, durationMin: dur, day: d, busy: _busy!, stepMin: step))
                  s: _barber!
              },
    };
  }

  void _goTo(int step) {
    setState(() => _step = step);
    if (step == 2) _loadSlots();
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() => _step--);
    }
  }

  Future<void> _confirm() async {
    if (widget.adminMode) {
      if (!_adminForm.currentState!.validate()) return;
    } else {
      final ok = await openAuthFlow(context);
      if (!ok || !mounted) return;
    }
    final barber = _availability[_day]?[_slot];
    if (barber == null) return;

    setState(() => _booking = true);
    try {
      final appt = await _state.backend.book(
        barberId: barber.id,
        serviceId: _service!.id,
        start: _slot!,
        notes: _notes.text.trim(),
        customerName: widget.adminMode ? _customerName.text.trim() : null,
        // campo lasciato a "+39 ": nessun numero (prima veniva salvato "+39")
        customerPhone: widget.adminMode
            ? (isValidPhone(_customerPhone.text) ? _customerPhone.text.trim() : '')
            : null,
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
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AppScaffold(
        title: widget.adminMode ? 'Nuovo appuntamento' : 'Prenota',
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        body: SafeArea(
          child: Column(children: [
            ResponsiveCenter(maxWidth: 640, child: _StepIndicator(steps: _steps, current: _step, onTap: (i) {
              if (i < _step) setState(() => _step = i);
            })),
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
          ]),
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
          child: Column(children: [
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
          ]),
        ),
      ],
    );
  }

  // --- Passo 2: barbiere ---

  String _workDays(Barber b) {
    const short = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];
    final days = [for (var d = 1; d <= 7; d++) if (b.hoursFor(d).isNotEmpty) short[d - 1]];
    return days.isEmpty ? 'Nessun orario' : days.join(' · ');
  }

  Widget _buildBarbers(AppState state) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ResponsiveCenter(
          maxWidth: 640,
          child: Column(children: [
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
              child: Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  child: const Icon(Icons.groups_outlined),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Primo disponibile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text('Ti mostriamo tutti gli orari liberi', style: TextStyle(color: AppColors.silver, fontSize: 13)),
                  ]),
                ),
                const Icon(Icons.chevron_right, color: AppColors.muted),
              ]),
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
                child: Row(children: [
                  BarberAvatar(barber: b, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b.name, style: slab(size: 17, weight: FontWeight.w600, spacing: 0.4)),
                      Text(b.title, style: const TextStyle(color: AppColors.silver, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(_workDays(b), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.muted),
                ]),
              ),
          ]),
        ),
      ],
    );
  }

  // --- Passo 3: data e ora ---

  Widget _buildDateTime() {
    if (_loadingSlots || _busy == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final slots = _availability[_day] ?? {};
    final groups = <String, List<DateTime>>{
      'Mattina': slots.keys.where((s) => s.hour < 13).toList(),
      'Pomeriggio': slots.keys.where((s) => s.hour >= 13 && s.hour < 17).toList(),
      'Sera': slots.keys.where((s) => s.hour >= 17).toList(),
    };

    return Column(children: [
      SizedBox(
        height: 92,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _days.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final d = _days[i];
                final available = _availability[d]?.isNotEmpty ?? false;
                final selected = d == _day;
                return _DayChip(
                  day: d,
                  selected: selected,
                  enabled: available,
                  onTap: () => setState(() {
                    _day = d;
                    _slot = null;
                  }),
                );
              },
            ),
          ),
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            ResponsiveCenter(
              maxWidth: 640,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: 8),
                Text(_day == null ? '' : fmtDayLong(_day!), style: slab(size: 17, weight: FontWeight.w600, spacing: 0.5)),
                if (slots.isEmpty)
                  const EmptyState(
                      icon: Icons.event_busy, text: 'Nessun orario libero in questa data.\nProva un altro giorno.'),
                for (final g in groups.entries)
                  if (g.value.isNotEmpty) ...[
                    SectionTitle(g.key),
                    LayoutBuilder(builder: (context, c) {
                      final cols = (c.maxWidth / 84).floor().clamp(3, 8);
                      final w = (c.maxWidth - (cols - 1) * 8) / cols;
                      return Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final s in g.value)
                          SizedBox(
                            width: w,
                            child: _SlotChip(
                              label: fmtTime(s),
                              selected: s == _slot,
                              onTap: () => setState(() => _slot = s),
                            ),
                          ),
                      ]);
                    }),
                  ],
              ]),
            ),
          ],
        ),
      ),
    ]);
  }

  // --- Passo 4: conferma ---

  Widget _buildConfirm(AppState state) {
    final barber = _availability[_day]?[_slot];
    final s = _service!;
    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(icon, size: 20, color: AppColors.muted),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(color: AppColors.silver)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ]),
        );

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ResponsiveCenter(
          maxWidth: 640,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Column(children: [
                row(Icons.content_cut, 'Servizio', s.name),
                const Divider(),
                row(Icons.person_outline, 'Barbiere', barber?.name ?? '-'),
                const Divider(),
                row(Icons.calendar_today_outlined, 'Data', _day == null ? '-' : fmtDayLong(_day!)),
                const Divider(),
                row(Icons.schedule, 'Ora',
                    _slot == null ? '-' : '${fmtTime(_slot!)} – ${fmtTime(_slot!.add(Duration(minutes: s.durationMin)))}'),
                const Divider(),
                row(Icons.euro, 'Prezzo', fmtPrice(s.price)),
              ]),
            ),
            if (widget.adminMode) ...[
              const SectionTitle('Cliente'),
              Form(
                key: _adminForm,
                child: Column(children: [
                  TextFormField(
                    controller: _customerName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nome cliente', prefixIcon: Icon(Icons.person_outline)),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Obbligatorio' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customerPhone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                        labelText: 'Cellulare (per promemoria WhatsApp)', prefixIcon: Icon(Icons.phone_iphone)),
                    validator: (v) {
                      final t = (v ?? '').replaceAll(RegExp(r'[\s+]'), '');
                      if (t.isEmpty || t == '39') return null;
                      return isValidPhone(v!) ? null : 'Numero non valido';
                    },
                  ),
                ]),
              ),
            ],
            const SectionTitle('Note (facoltative)'),
            TextField(
              controller: _notes,
              maxLines: 3,
              minLines: 2,
              maxLength: 300,
              decoration: const InputDecoration(hintText: 'Es. sfumatura alta, barba corta...'),
            ),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.notifications_active_outlined, size: 18, color: AppColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Riceverai un promemoria su WhatsApp 24 ore e 1 ora prima. '
                  'Puoi annullare dall\'app fino a ${state.settings.minCancelHours} ore prima.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
                ),
              ),
            ]),
          ]),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final canContinue = _slot != null;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.6),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      child: ResponsiveCenter(
        maxWidth: 640,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(_service?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                _slot == null
                    ? 'Scegli un orario'
                    : '${fmtDayShort(_slot!)} · ${fmtTime(_slot!)} · ${_availability[_day]?[_slot]?.name ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.silver, fontSize: 13),
              ),
            ]),
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
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.black))
                        : const Text('CONFERMA'),
                  ),
          ),
        ]),
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
        child: Row(children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                onTap: () => onTap(i),
                borderRadius: BorderRadius.circular(6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 3,
                    decoration: BoxDecoration(
                      color: i <= current ? AppColors.white : Colors.white.withValues(alpha: 0.12),
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
                ]),
              ),
            ),
          ],
        ]),
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
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.white : Colors.white.withValues(alpha: enabled ? 0.06 : 0.02),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: selected ? 1 : 0.10)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(parts[0].replaceAll('.', '').toUpperCase(),
              style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(parts[1], style: slab(size: 20, color: fg, weight: FontWeight.w700, spacing: 0)),
          Text(parts.length > 2 ? parts[2].replaceAll('.', '') : '', style: TextStyle(color: fg, fontSize: 11)),
        ]),
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
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.white : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: selected ? 1 : 0.10)),
          ),
          child: Text(label,
              style: TextStyle(
                color: selected ? AppColors.black : AppColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              )),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.white.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border(bottom: BorderSide(color: AppColors.white.withValues(alpha: 0.08))),
        ),
        child: Row(children: [
          ServiceIcon(s.name, selected: selected),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LayoutBuilder(
                builder: (context, c) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  // il nome prende lo spazio che serve, i puntini riempiono il resto
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: c.maxWidth - 84),
                    child: Text(s.name, style: slab(size: 16, weight: FontWeight.w600, spacing: 0.3)),
                  ),
                  const Expanded(child: Padding(padding: EdgeInsets.only(bottom: 5), child: DottedLeader())),
                  Text(fmtPrice(s.price), style: slab(size: 17, weight: FontWeight.w700, spacing: 0.4)),
                ]),
              ),
              const SizedBox(height: 4),
              Text(
                [fmtDuration(s.durationMin), if (s.description.isNotEmpty) s.description].join('  ·  '),
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
