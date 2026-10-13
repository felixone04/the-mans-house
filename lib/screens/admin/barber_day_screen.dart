import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/backend.dart';
import '../../data/slots.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'agenda_actions.dart';
import 'walk_in_sheet.dart';

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
      _debts = await _loadDebts(backend);
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

  /// Pagamenti lasciati in sospeso nelle visite precedenti, per appuntamento.
  Map<String, List<Appointment>> _debts = {};

  Future<Map<String, List<Appointment>>> _loadDebts(Backend backend) async {
    String keyOf(Appointment a) => a.userId ?? '${CustomerSummary.walkInPrefix}${a.customerName}';
    final customers = {
      for (final a in _items.where((a) => a.userId != null || a.customerName.isNotEmpty))
        keyOf(a): CustomerSummary(id: keyOf(a), email: '', fullName: a.customerName, phone: '', bookings: 0),
    };
    final histories = await Future.wait(customers.values.map(backend.customerAppointments));
    final byCustomer = {for (final (i, k) in customers.keys.indexed) k: histories[i]};
    return {
      for (final a in _items)
        a.id: (byCustomer[keyOf(a)] ?? const <Appointment>[])
            .where(
              (x) =>
                  x.id != a.id &&
                  x.start.isBefore(a.start) &&
                  x.status != AppointmentStatus.cancelled &&
                  x.outstanding > 0,
            )
            .toList(),
    };
  }

  void _shift(int days) {
    _day = DateTime(_day.year, _day.month, _day.day + days);
    _load();
  }

  // --- Completato e pagamento ---

  Future<void> _savePayment(Appointment a, PaymentStatus payment, double paid) async {
    HapticFeedback.selectionClick();
    try {
      await AppScope.read(context).backend
          .updateVisit(a.id, arrivedAt: a.arrivedAt, payment: payment, amountPaid: paid);
      await _load(silent: true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

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
    final debts = _debts[a.id] ?? const <Appointment>[];
    final r = await showModalBottomSheet<(PaymentStatus, double, bool)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AgendaLight.card,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => _PaymentSheet(appointment: a, debts: debts),
    );
    if (r == null || !mounted) return;
    final (payment, paid, settleDebts) = r;
    if (settleDebts) {
      // salda anche le visite precedenti rimaste da pagare
      final backend = AppScope.read(context).backend;
      try {
        for (final d in debts) {
          await backend.updateVisit(d.id, arrivedAt: d.arrivedAt, payment: PaymentStatus.paid, amountPaid: d.price);
        }
      } catch (e) {
        if (mounted) showError(context, e);
        return;
      }
    }
    await _savePayment(a, payment, paid);
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
            debts: _debts[a.id] ?? const [],
            onTap: () => openAppointment(a),
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
        floatingActionButton: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton(
              heroTag: 'new',
              tooltip: 'Nuovo appuntamento',
              elevation: 2,
              backgroundColor: Colors.white,
              foregroundColor: AgendaLight.ink,
              onPressed: () => newAppointment(barber: b),
              child: const Icon(Icons.add),
            ),
            const SizedBox(width: 10),
            // cliente senza appuntamento: primo orario libero da adesso
            if (isToday)
              FloatingActionButton.extended(
                heroTag: 'walkin',
                elevation: 2,
                backgroundColor: AgendaLight.ink,
                foregroundColor: Colors.white,
                onPressed: () async {
                  if (await showWalkInSheet(context, barber: b)) _load(silent: true);
                },
                icon: const Icon(Icons.login),
                label: const Text('Entrato ora'),
              ),
          ],
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
                      alignment: Alignment.topLeft, // come i riquadri dei barbieri
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

/// Rosso: da completare (cliente non ancora arrivato). Bianco: completato.
/// Grigio: non presentato.
const BarberTone _waitingTone = (
  bg: Color(0xFFFCE4E4),
  mid: Color(0xFFA32D2D),
  accent: Color(0xFFD33A3A),
  ink: Color(0xFF501313),
);
const BarberTone _doneTone = (bg: AgendaLight.card, mid: AgendaLight.sub, accent: AgendaLight.ok, ink: AgendaLight.ink);
const BarberTone _noShowTone = (
  bg: Color(0xFFEDEDED),
  mid: AgendaLight.muted,
  accent: AgendaLight.muted,
  ink: AgendaLight.muted,
);

/// Scheda grande di un appuntamento.
class _VisitCard extends StatelessWidget {
  const _VisitCard({
    required this.appointment,
    required this.debts,
    required this.onTap,
    required this.onDone,
    required this.onPayment,
  });
  final Appointment appointment;

  /// Visite precedenti dello stesso cliente rimaste da pagare.
  final List<Appointment> debts;
  final VoidCallback onTap;
  final VoidCallback onDone;
  final VoidCallback onPayment;

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final now = DateTime.now();
    final done = a.status == AppointmentStatus.completed;
    final noShow = a.status == AppointmentStatus.noShow;
    // completato = arrivato: finche' non e' completato la scheda resta rossa
    final waiting = a.status == AppointmentStatus.confirmed;
    final started = !a.start.isAfter(now);
    final ended = !a.end.isAfter(now);
    final t = noShow
        ? _noShowTone
        : done
        ? _doneTone
        : _waitingTone;
    final mins = a.end.difference(a.start).inMinutes;
    final debt = debts.fold<double>(0, (s, d) => s + d.outstanding);
    final dueToday = (a.price - a.collected).clamp(0, double.infinity) + debt;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: t.bg,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: done
                  ? Border.all(color: AgendaLight.line, width: 1.5)
                  : waiting
                  ? Border.all(color: _waitingTone.accent.withValues(alpha: 0.45), width: 1.5)
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
                      style: TextStyle(color: t.ink, fontSize: 30, height: 1, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          'fino alle ${fmtTime(a.end)} · $mins min',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: t.mid, fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    if (waiting)
                      _Pill(
                        ended
                            ? 'DA CHIUDERE'
                            : started
                            ? 'IN CORSO'
                            : 'DA ARRIVARE',
                        fg: Colors.white,
                        bg: _waitingTone.accent,
                      ),
                    if (done) const _Pill('COMPLETATO', fg: Colors.white, bg: AgendaLight.ok),
                    if (noShow) const _Pill('NON VENUTO', fg: Colors.white, bg: AgendaLight.muted),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  a.customerName.isEmpty ? 'Cliente' : a.customerName,
                  style: TextStyle(color: t.ink, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${a.serviceName} · ${fmtPrice(a.price)}',
                  style: TextStyle(color: t.mid, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                if (a.notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '“${a.notes}”',
                    style: TextStyle(color: t.mid, fontSize: 13.5, fontStyle: FontStyle.italic),
                  ),
                ],
                // l'avviso serve al momento di incassare: non sulle visite gia' pagate
                if (debt > 0 && !noShow && a.payment != PaymentStatus.paid) ...[
                  const SizedBox(height: 10),
                  _DebtBanner(debts: debts, debt: debt, dueToday: dueToday.toDouble()),
                ],
                if (!noShow) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // l'arrivo si segna dal dettaglio (tocco sulla scheda)
                      Expanded(
                        child: _StepButton(
                          icon: Icons.content_cut,
                          label: done ? 'Completato' : 'Completato?',
                          on: done,
                          tone: t,
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
                          tone: t,
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

/// Avviso: il cliente deve ancora pagare visite precedenti.
class _DebtBanner extends StatelessWidget {
  const _DebtBanner({required this.debts, required this.debt, required this.dueToday});
  final List<Appointment> debts;
  final double debt;
  final double dueToday;

  @override
  Widget build(BuildContext context) {
    final last = debts.map((d) => d.start).reduce((x, y) => x.isAfter(y) ? x : y);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8B8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0A030)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFF8A4B00), size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deve ancora ${fmtPrice(debt)} '
                  '${debts.length == 1 ? 'dalla visita del ${fmtDayShort(last)}' : 'da ${debts.length} visite precedenti'}',
                  style: const TextStyle(color: Color(0xFF6B3A00), fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                Text(
                  'Totale da pagare oggi: ${fmtPrice(dueToday)}',
                  style: const TextStyle(color: Color(0xFF4A2800), fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
  const _PaymentSheet({required this.appointment, this.debts = const []});
  final Appointment appointment;

  /// Visite precedenti ancora da pagare (arretrato).
  final List<Appointment> debts;

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
    Navigator.pop(context, (_choice, paid, _choice == PaymentStatus.paid && _settleDebts && _debt > 0));
  }

  double get _debt => widget.debts.fold<double>(0, (s, d) => s + d.outstanding);

  /// Con l'arretrato: salda anche le visite precedenti.
  bool _settleDebts = true;

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
            if (_debt > 0 && _choice == PaymentStatus.paid) ...[
              const SizedBox(height: 12),
              Material(
                color: const Color(0xFFFFE8B8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFFE0A030)),
                ),
                clipBehavior: Clip.antiAlias,
                child: CheckboxListTile(
                  contentPadding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
                  value: _settleDebts,
                  activeColor: const Color(0xFF8A4B00),
                  checkColor: Colors.white,
                  onChanged: (v) => setState(() => _settleDebts = v ?? false),
                  title: Text(
                    'Salda anche l\'arretrato: ${fmtPrice(_debt)}',
                    style: const TextStyle(color: Color(0xFF4A2800), fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    'Totale oggi: ${fmtPrice(a.price - a.collected + _debt)}',
                    style: const TextStyle(color: Color(0xFF6B3A00), fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
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
