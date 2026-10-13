import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/slots.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'agenda_actions.dart';

/// Giornata di un barbiere (telefono, colori chiari): un appuntamento per
/// scheda con orario grande, cliente e servizio. Da qui si segna se il cliente
/// e' arrivato, se il servizio e' completato e come ha pagato.
class BarberDayScreen extends StatefulWidget {
  const BarberDayScreen({super.key, required this.barber, required this.day});
  final Barber barber;
  final DateTime day;

  @override
  State<BarberDayScreen> createState() => _BarberDayScreenState();
}

class _BarberDayScreenState extends State<BarberDayScreen> with AgendaActions {
  late DateTime _day = dayOnly(widget.day);
  List<Appointment> _items = [];
  List<TimeOff> _off = [];
  bool _loading = true;
  final _nowKey = GlobalKey();

  Barber get b => widget.barber;

  @override
  DateTime get agendaDay => _day;

  @override
  List<Appointment> get agendaDayAppointments => _items;

  @override
  Future<void> reloadAgenda() => _load(silent: true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final backend = AppScope.read(context).backend;
    final next = DateTime(_day.year, _day.month, _day.day + 1);
    try {
      final results = await Future.wait([backend.appointmentsBetween(_day, next), backend.fetchTimeOff(b.id)]);
      _items =
          (results[0] as List<Appointment>)
              .where((a) => a.barberId == b.id && a.status != AppointmentStatus.cancelled)
              .toList()
            ..sort((x, y) => x.start.compareTo(y.start));
      _off = (results[1] as List<TimeOff>).where((t) => t.start.isBefore(next) && t.end.isAfter(_day)).toList();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    // oggi: si parte dall'ora attuale
    if (!silent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _nowKey.currentContext;
        if (c != null) Scrollable.ensureVisible(c, alignment: 0.2);
      });
    }
  }

  void _shift(int days) {
    _day = DateTime(_day.year, _day.month, _day.day + days);
    _load();
  }

  // --- Arrivo, completato, pagamento ---

  Future<void> _saveVisit(
    Appointment a, {
    DateTime? arrivedAt,
    bool clearArrived = false,
    PaymentStatus? payment,
    double? paid,
  }) async {
    HapticFeedback.selectionClick();
    try {
      await AppScope.read(context).backend.updateVisit(
        a.id,
        arrivedAt: clearArrived ? null : (arrivedAt ?? a.arrivedAt),
        payment: payment ?? a.payment,
        amountPaid: paid ?? a.amountPaid,
      );
      await _load(silent: true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _toggleArrived(Appointment a) =>
      a.arrivedAt == null ? _saveVisit(a, arrivedAt: DateTime.now()) : _saveVisit(a, clearArrived: true);

  Future<void> _toggleDone(Appointment a) async {
    HapticFeedback.selectionClick();
    final backend = AppScope.read(context).backend;
    try {
      if (a.status == AppointmentStatus.completed) {
        await backend.setAppointmentStatus(a.id, AppointmentStatus.confirmed);
      } else {
        await backend.setAppointmentStatus(a.id, AppointmentStatus.completed);
        // completato: il cliente e' per forza arrivato
        if (a.arrivedAt == null) {
          await backend.updateVisit(a.id, arrivedAt: a.start, payment: a.payment, amountPaid: a.amountPaid);
        }
      }
      await _load(silent: true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _payment(Appointment a) async {
    final r = await showModalBottomSheet<(PaymentStatus, double)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AgendaLight.card,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => _PaymentSheet(appointment: a),
    );
    if (r != null) await _saveVisit(a, payment: r.$1, paid: r.$2);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final tone = barberTone(state.barbers, b.id);
    final now = DateTime.now();
    final isToday = _day == dayOnly(now);
    final nowMin = minuteOf(now);
    final kept = _items.where((a) => a.status != AppointmentStatus.noShow);
    final collected = _items.fold<double>(0, (s, a) => s + a.collected);
    final expected = kept.fold<double>(0, (s, a) => s + a.price);

    // voci in ordine di orario: (minuto, ordine a parita', widget)
    final entries = <(int, int, Widget)>[
      for (final t in _off)
        (offRangeIn(_day, t).$1, 0, _OffCard(timeOff: t, day: _day, onTap: () => removeBlock(t, b))),
      for (final a in _items)
        (
          minuteOf(a.start),
          1,
          _VisitCard(
            appointment: a,
            tone: tone,
            onTap: () => openAppointment(a),
            onArrived: () => _toggleArrived(a),
            onDone: () => _toggleDone(a),
            onPayment: () => _payment(a),
          ),
        ),
      for (final (s, e) in freeRanges(_day, b, _items, _off))
        (
          s,
          2,
          _FreeCard(
            from: s,
            to: e,
            onTap: () => newAppointment(barber: b, time: DateTime(_day.year, _day.month, _day.day, 0, s)),
            onLongPress: () => blockTime(barber: b, start: s, end: e - s > 60 ? s + 30 : e),
          ),
        ),
    ]..sort((x, y) => x.$1 != y.$1 ? x.$1.compareTo(y.$1) : x.$2.compareTo(y.$2));

    final children = <Widget>[];
    var nowPlaced = !isToday;
    for (final e in entries) {
      if (!nowPlaced && e.$1 > nowMin) {
        children.add(_NowMarker(key: _nowKey, time: now));
        nowPlaced = true;
      }
      children.add(e.$3);
    }
    if (!nowPlaced && entries.isNotEmpty) children.add(_NowMarker(key: _nowKey, time: now));

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: AgendaLight.paper,
        colorScheme: Theme.of(context).colorScheme.copyWith(primary: AgendaLight.ink, onPrimary: Colors.white),
        snackBarTheme: Theme.of(context).snackBarTheme,
      ),
      child: Scaffold(
        backgroundColor: AgendaLight.paper,
        appBar: AppBar(
          backgroundColor: tone.bg,
          foregroundColor: tone.ink,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          titleSpacing: 0,
          title: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: tone.accent,
                child: Text(
                  b.initials,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.name,
                      style: TextStyle(color: tone.ink, fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${kept.length} ${kept.length == 1 ? 'appuntamento' : 'appuntamenti'} · '
                      'incassati ${fmtPrice(collected)} su ${fmtPrice(expected)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tone.mid, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(46),
            child: Container(
              color: tone.bg,
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Giorno precedente',
                    onPressed: () => _shift(-1),
                    icon: Icon(Icons.chevron_left, color: tone.ink),
                  ),
                  Expanded(
                    child: Text(
                      '${isToday ? 'Oggi · ' : ''}${fmtDayLong(_day)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: tone.ink, fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Giorno successivo',
                    onPressed: () => _shift(1),
                    icon: Icon(Icons.chevron_right, color: tone.ink),
                  ),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AgendaLight.ink,
          foregroundColor: Colors.white,
          onPressed: () => newAppointment(barber: b),
          icon: const Icon(Icons.add),
          label: const Text('Nuovo'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AgendaLight.ink))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(0, 14, 0, 96),
                  children: [
                    ResponsiveCenter(
                      maxWidth: 640,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: children.isEmpty
                            ? [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 60),
                                  child: Column(
                                    children: [
                                      Icon(Icons.weekend_outlined, size: 44, color: tone.accent),
                                      const SizedBox(height: 12),
                                      Text(
                                        b.hoursFor(_day.weekday).isEmpty
                                            ? '${b.name} oggi è di riposo'
                                            : 'Nessun appuntamento',
                                        style: const TextStyle(color: AgendaLight.sub, fontSize: 15),
                                      ),
                                    ],
                                  ),
                                ),
                              ]
                            : children,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Scheda grande di un appuntamento.
class _VisitCard extends StatelessWidget {
  const _VisitCard({
    required this.appointment,
    required this.tone,
    required this.onTap,
    required this.onArrived,
    required this.onDone,
    required this.onPayment,
  });
  final Appointment appointment;
  final BarberTone tone;
  final VoidCallback onTap;
  final VoidCallback onArrived;
  final VoidCallback onDone;
  final VoidCallback onPayment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final now = DateTime.now();
    final done = a.status == AppointmentStatus.completed;
    final noShow = a.status == AppointmentStatus.noShow;
    final running = a.status == AppointmentStatus.confirmed && !a.start.isAfter(now) && a.end.isAfter(now);
    final mins = a.end.difference(a.start).inMinutes;
    // completati e non presentati restano leggibili ma piu' tenui
    final bg = noShow ? const Color(0xFFEDEDED) : (done ? AgendaLight.card : tone.bg);
    final ink = noShow ? AgendaLight.muted : tone.ink;
    final mid = noShow ? AgendaLight.muted : tone.mid;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: running
                  ? Border.all(color: tone.accent, width: 2.5)
                  : done
                  ? Border.all(color: tone.bg, width: 2)
                  : null,
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      fmtTime(a.start),
                      style: TextStyle(color: ink, fontSize: 30, height: 1, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          'fino alle ${fmtTime(a.end)} · $mins min',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: mid, fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    if (running) _Pill('IN CORSO', fg: Colors.white, bg: tone.accent),
                    if (done) const _Pill('COMPLETATO', fg: Colors.white, bg: AgendaLight.ok),
                    if (noShow) const _Pill('NON VENUTO', fg: Colors.white, bg: AgendaLight.muted),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  a.customerName.isEmpty ? 'Cliente' : a.customerName,
                  style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${a.serviceName} · ${fmtPrice(a.price)}',
                  style: TextStyle(color: mid, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                if (a.notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '“${a.notes}”',
                    style: TextStyle(color: mid, fontSize: 13.5, fontStyle: FontStyle.italic),
                  ),
                ],
                if (!noShow) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StepButton(
                          icon: Icons.how_to_reg_outlined,
                          label: a.arrivedAt == null ? 'Arrivato?' : 'Arrivato ${fmtTime(a.arrivedAt!)}',
                          on: a.arrivedAt != null,
                          tone: tone,
                          onTap: onArrived,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _StepButton(
                          icon: Icons.content_cut,
                          label: done ? 'Completato' : 'Completato?',
                          on: done,
                          tone: tone,
                          onTap: onDone,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _StepButton(
                          icon: Icons.euro,
                          label: _paymentLabel(a),
                          on: a.payment == PaymentStatus.paid,
                          warn: a.payment == PaymentStatus.later || a.payment == PaymentStatus.deposit,
                          tone: tone,
                          onTap: onPayment,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _paymentLabel(Appointment a) => switch (a.payment) {
    PaymentStatus.unpaid => 'Pagato?',
    PaymentStatus.paid => 'Pagato',
    PaymentStatus.later => 'Paga dopo',
    PaymentStatus.deposit => 'Resta ${fmtPrice(a.price - a.collected)}',
  };
}

/// Pulsante di stato (Arrivato / Completato / Pagamento): pieno quando fatto.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.on,
    required this.tone,
    required this.onTap,
    this.warn = false,
  });
  final IconData icon;
  final String label;
  final bool on;
  final bool warn;
  final BarberTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = on ? Colors.white : (warn ? AgendaLight.warn : tone.ink);
    final bg = on ? tone.accent : (warn ? const Color(0xFFFFF1DB) : Colors.white.withValues(alpha: 0.75));
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: on ? tone.accent : (warn ? AgendaLight.warn : tone.accent.withValues(alpha: 0.35)),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(on ? Icons.check : icon, size: 17, color: fg),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.fg, required this.bg});
  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(
      text,
      style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.5),
    ),
  );
}

class _FreeCard extends StatelessWidget {
  const _FreeCard({required this.from, required this.to, required this.onTap, required this.onLongPress});
  final int from;
  final int to;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBDBAB2), width: 1.2),
          ),
          child: Row(
            children: [
              Text(
                formatTime(from),
                style: const TextStyle(color: AgendaLight.sub, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'libero fino alle ${formatTime(to)} · ${fmtDuration(to - from)}',
                  style: const TextStyle(color: AgendaLight.sub, fontSize: 13.5),
                ),
              ),
              const Icon(Icons.add_circle_outline, color: AgendaLight.ok),
            ],
          ),
        ),
      ),
    ),
  );
}

class _OffCard extends StatelessWidget {
  const _OffCard({required this.timeOff, required this.day, required this.onTap});
  final TimeOff timeOff;
  final DateTime day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (s, e) = offRangeIn(day, timeOff);
    final allDay = s == 0 && e == 24 * 60;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFFFF1DB),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  allDay ? 'Tutto il giorno' : formatTime(s),
                  style: const TextStyle(color: AgendaLight.warn, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${timeOff.reason.isEmpty ? 'Assente' : timeOff.reason}'
                    '${allDay ? '' : ' fino alle ${formatTime(e)}'}',
                    style: const TextStyle(color: AgendaLight.warn, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                const Icon(Icons.block, color: AgendaLight.warn, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NowMarker extends StatelessWidget {
  const _NowMarker({super.key, required this.time});
  final DateTime time;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: AgendaLight.now, borderRadius: BorderRadius.circular(6)),
          child: Text(
            'ORA ${fmtTime(time)}',
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(child: Container(height: 2, color: AgendaLight.now)),
      ],
    ),
  );
}

/// Pagamento: pagato, paga dopo, acconto (con importo) o non ancora pagato.
class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.appointment});
  final Appointment appointment;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late PaymentStatus _choice = widget.appointment.payment == PaymentStatus.unpaid
      ? PaymentStatus.paid
      : widget.appointment.payment;
  late final _amount = TextEditingController(
    text: widget.appointment.amountPaid > 0
        ? widget.appointment.amountPaid.toStringAsFixed(2).replaceAll('.', ',')
        : '',
  );
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final price = widget.appointment.price;
    var paid = 0.0;
    switch (_choice) {
      case PaymentStatus.paid:
        paid = price;
      case PaymentStatus.deposit:
        final v = double.tryParse(_amount.text.trim().replaceAll('€', '').replaceAll(',', '.'));
        if (v == null || v <= 0) return setState(() => _error = 'Scrivi l\'importo dell\'acconto');
        if (v >= price) return setState(() => _error = 'L\'acconto deve essere inferiore a ${fmtPrice(price)}');
        paid = v;
      case PaymentStatus.later:
      case PaymentStatus.unpaid:
        paid = 0;
    }
    Navigator.pop(context, (_choice, paid));
  }

  Widget _option(PaymentStatus p, IconData icon, String title, String subtitle) {
    final selected = _choice == p;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFF1EFEA) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _choice = p;
            _error = null;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? AgendaLight.ink : AgendaLight.line, width: selected ? 2 : 1),
            ),
            child: Row(
              children: [
                Icon(icon, color: AgendaLight.ink),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(color: AgendaLight.ink, fontSize: 15.5, fontWeight: FontWeight.w700),
                      ),
                      Text(subtitle, style: const TextStyle(color: AgendaLight.sub, fontSize: 12.5)),
                    ],
                  ),
                ),
                if (selected) const Icon(Icons.check_circle, color: AgendaLight.ink),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pagamento · ${fmtPrice(a.price)}',
              style: const TextStyle(color: AgendaLight.ink, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(
              '${a.customerName} · ${a.serviceName}',
              style: const TextStyle(color: AgendaLight.sub, fontSize: 13.5),
            ),
            const SizedBox(height: 14),
            _option(PaymentStatus.paid, Icons.check_circle_outline, 'Pagato', 'Ha pagato tutto: ${fmtPrice(a.price)}'),
            _option(PaymentStatus.deposit, Icons.savings_outlined, 'Acconto', 'Ha lasciato una parte, il resto dopo'),
            if (_choice == PaymentStatus.deposit)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
                child: TextField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AgendaLight.ink, fontSize: 18, fontWeight: FontWeight.w700),
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF1EFEA),
                    labelText: 'Importo dell\'acconto',
                    labelStyle: const TextStyle(color: AgendaLight.sub),
                    prefixText: '€ ',
                    prefixStyle: const TextStyle(color: AgendaLight.ink, fontSize: 18),
                    errorText: _error,
                    helperText: () {
                      final v = double.tryParse(_amount.text.trim().replaceAll(',', '.'));
                      return v == null || v <= 0 || v >= a.price ? null : 'Resta da pagare ${fmtPrice(a.price - v)}';
                    }(),
                    helperStyle: const TextStyle(color: AgendaLight.ok, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            _option(PaymentStatus.later, Icons.schedule, 'Paga dopo', 'Pagherà tutto in un altro momento'),
            _option(
              PaymentStatus.unpaid,
              Icons.remove_circle_outline,
              'Non ancora pagato',
              'Nessun pagamento registrato',
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AgendaLight.ink, foregroundColor: Colors.white),
              onPressed: _save,
              child: const Text('SALVA'),
            ),
          ],
        ),
      ),
    );
  }
}
