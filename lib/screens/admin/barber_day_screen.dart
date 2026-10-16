import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/backend.dart';
import '../../data/slots.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'agenda_actions.dart';
import 'products_tab.dart';
import 'waitlist_screen.dart';
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
      // in lista d'attesa oggi per questo barbiere (o per il primo disponibile)
      try {
        _waiting = (await backend.fetchWaitlist(_day, next))
            .where((w) => w.fits(b.id) && w.start.isAfter(DateTime.now()))
            .length;
      } catch (_) {
        _waiting = 0;
      }
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

  /// Persone in lista d'attesa per questa giornata.
  int _waiting = 0;

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
    if (!mounted) return;
    // anche senza salvare, i prodotti aggiunti cambiano il conto: si ricarica
    if (r == null) return _load(silent: true);
    final (payment, paid, settleDebts) = r;
    if (settleDebts) {
      // salda anche le visite precedenti rimaste da pagare
      final backend = AppScope.read(context).backend;
      try {
        for (final d in debts) {
          await backend.updateVisit(d.id, arrivedAt: d.arrivedAt, payment: PaymentStatus.paid, amountPaid: d.total);
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
    final expected = kept.fold<double>(0, (s, a) => s + a.total);

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

    // voci divise in Mattina e Pomeriggio, con il segno dell'ora attuale
    final children = <Widget>[];
    var nowPlaced = !isToday;
    String? section;
    void addSection(int minute) {
      final s = minute < 13 * 60 ? 'Mattina' : 'Pomeriggio';
      if (s == section) return;
      section = s;
      children.add(_SectionLabel(s));
    }

    for (final e in entries) {
      if (!nowPlaced && e.$1 > nowMin) {
        addSection(nowMin);
        children.add(_NowMarker(key: _nowKey, time: now));
        nowPlaced = true;
      }
      addSection(e.$1);
      children.add(e.$3);
    }
    if (!nowPlaced && entries.isNotEmpty) children.add(_NowMarker(key: _nowKey, time: now));
    if (_waiting > 0) {
      children.insert(
        0,
        _WaitlistBanner(
          count: _waiting,
          onTap: () async {
            await Navigator.of(context).push(fadeRoute(WaitlistScreen(day: _day)));
            _load(silent: true);
          },
        ),
      );
    }

    final doneCount = kept.where((a) => a.status == AppointmentStatus.completed).length;

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: AgendaLight.paper,
        colorScheme: Theme.of(context).colorScheme.copyWith(primary: AgendaLight.ink, onPrimary: Colors.white),
        snackBarTheme: Theme.of(context).snackBarTheme,
      ),
      child: Scaffold(
        backgroundColor: AgendaLight.paper,
        floatingActionButton: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton(
              heroTag: 'new',
              tooltip: 'Nuovo appuntamento',
              elevation: 2,
              backgroundColor: Colors.white,
              foregroundColor: AgendaLight.ink,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                onPressed: () async {
                  if (await showWalkInSheet(context, barber: b)) _load(silent: true);
                },
                icon: const Icon(Icons.login),
                label: const Text('Entrato ora', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
          ],
        ),
        body: Column(
          children: [
            // intestazione nel colore del barbiere: nome, completati e incassi, giorno
            Container(
              color: tone.bg,
              child: SafeArea(
                bottom: false,
                child: ResponsiveCenter(
                  maxWidth: 640,
                  alignment: Alignment.topLeft,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Material(
                            color: Colors.white.withValues(alpha: 0.6),
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: 'Indietro',
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: Icon(Icons.chevron_left, color: tone.ink),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  b.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: tone.ink, fontSize: 24, height: 1.1, fontWeight: FontWeight.w900),
                                ),
                                Text(
                                  '$doneCount di ${kept.length} completati · '
                                  'incassati ${fmtPrice(collected)} su ${fmtPrice(expected)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: tone.mid, fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Giorno precedente',
                              onPressed: () => _shift(-1),
                              icon: Icon(Icons.chevron_left, color: tone.ink),
                            ),
                            Expanded(
                              child: Text(
                                isToday ? 'Oggi · ${fmtDayLong(_day).toLowerCase()}' : fmtDayLong(_day),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: tone.ink, fontSize: 15, fontWeight: FontWeight.w800),
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
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AgendaLight.ink))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(0, 6, 0, 96),
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
                                              (ShopCalendar.forDay(_day)?.closed ?? false)
                                                  ? 'Negozio chiuso'
                                                        '${ShopCalendar.forDay(_day)!.note.isEmpty ? '' : ' · ${ShopCalendar.forDay(_day)!.note}'}'
                                                  : b.hoursOn(_day).isEmpty
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
          ],
        ),
      ),
    );
  }
}

/// Avviso in cima alla giornata: quante persone sono in lista d'attesa.
class _WaitlistBanner extends StatelessWidget {
  const _WaitlistBanner({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Material(
      color: const Color(0xFFFFF1DB),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE0A030)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              const Icon(Icons.hourglass_bottom, color: Color(0xFF8A4B00)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 1 ? '1 persona in lista d\'attesa' : '$count persone in lista d\'attesa',
                  style: const TextStyle(color: Color(0xFF4A2800), fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              const Text(
                'Vedi',
                style: TextStyle(color: Color(0xFF8A4B00), fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF8A4B00)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// "MATTINA" / "POMERIGGIO" sopra le schede.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 0, 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(color: AgendaLight.muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.6),
    ),
  );
}

const _okGreen = Color(0xFF22A06B);
const _nowBlue = Color(0xFF2F6FD6);
const _lateRed = Color(0xFFD33A3A);

/// Scheda di un appuntamento: orario grande, stato a destra, cliente,
/// servizio e prezzo; sotto Completato e il pagamento.
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
    final waiting = a.status == AppointmentStatus.confirmed;
    final started = !a.start.isAfter(now);
    final ended = !a.end.isAfter(now);
    final inProgress = waiting && started && !ended;
    final paid = a.payment == PaymentStatus.paid;
    final mins = a.end.difference(a.start).inMinutes;
    final debt = debts.fold<double>(0, (s, d) => s + d.outstanding);
    final dueToday = (a.total - a.collected).clamp(0, double.infinity) + debt;

    final (String status, Color statusColor) = noShow
        ? ('Non venuto', AgendaLight.muted)
        : done
        ? (paid ? ('Fatto', _okGreen) : ('Da pagare', AgendaLight.warn))
        : ended
        ? ('Da chiudere', _lateRed)
        : started
        ? ('Adesso', _nowBlue)
        : ('In arrivo', AgendaLight.sub);
    final ink = noShow ? AgendaLight.muted : AgendaLight.ink;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: noShow ? const Color(0xFFEDEDED) : AgendaLight.card,
          borderRadius: BorderRadius.circular(18),
          border: inProgress
              ? Border.all(color: _nowBlue, width: 1.8)
              : waiting && ended
              ? Border.all(color: _lateRed.withValues(alpha: 0.5), width: 1.5)
              : Border.all(color: Colors.transparent, width: 1.8),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        fmtTime(a.start),
                        style: TextStyle(color: ink, fontSize: 26, height: 1, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '– ${fmtTime(a.end)} · $mins min',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AgendaLight.sub, fontSize: 13.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                      // il cliente ha risposto «Ci sono» alla conferma presenza
                      if (waiting && a.attendanceConfirmedAt != null)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDDF1E3),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, size: 12, color: Color(0xFF145C35)),
                              SizedBox(width: 3),
                              Text(
                                'CI SARÀ',
                                style: TextStyle(
                                  color: Color(0xFF145C35),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // accettato dalla lista d'attesa anche se l'orario era pieno
                      if (a.extra)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1DB),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'EXTRA',
                            style: TextStyle(
                              color: Color(0xFF8A4B00),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        status,
                        style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    a.customerName.isEmpty ? 'Cliente' : a.customerName,
                    style: TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${a.serviceName}${a.productsTotal > 0 ? ' + prodotti ${fmtPrice(a.productsTotal)}' : ''}',
                          style: const TextStyle(color: AgendaLight.sub, fontSize: 14),
                        ),
                      ),
                      Text(
                        fmtPrice(a.total),
                        style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  if (a.notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '“${a.notes}”',
                      style: const TextStyle(color: AgendaLight.sub, fontSize: 13.5, fontStyle: FontStyle.italic),
                    ),
                  ],
                  // l'avviso serve al momento di incassare: non sulle visite gia' pagate
                  if (debt > 0 && !noShow && !paid) ...[
                    const SizedBox(height: 10),
                    _DebtBanner(debts: debts, debt: debt, dueToday: dueToday.toDouble()),
                  ],
                  if (!noShow) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: AgendaLight.line),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // l'arrivo si segna dal dettaglio (tocco sulla scheda)
                        Expanded(
                          child: _ActionButton(
                            icon: done ? Icons.check : Icons.content_cut,
                            label: done ? 'Completato' : 'Completato?',
                            style: done ? _ActionStyle.on : _ActionStyle.off,
                            onTap: onDone,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ActionButton(
                            icon: paid ? Icons.check : Icons.euro,
                            label: _paymentLabel(a),
                            style: paid
                                ? _ActionStyle.on
                                : a.payment == PaymentStatus.later || a.payment == PaymentStatus.deposit
                                ? _ActionStyle.warn
                                : _ActionStyle.off,
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
      ),
    );
  }

  static String _paymentLabel(Appointment a) => switch (a.payment) {
    PaymentStatus.unpaid => 'Pagato?',
    PaymentStatus.paid => 'Pagato',
    PaymentStatus.later => 'Paga dopo',
    PaymentStatus.deposit => 'Resta ${fmtPrice(a.total - a.collected)}',
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

enum _ActionStyle { on, warn, off }

/// Pulsante sotto la scheda: verde pieno quando fatto, arancio chiaro se
/// resta da pagare, neutro se ancora da segnare.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.style, required this.onTap});
  final IconData icon;
  final String label;
  final _ActionStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color border) = switch (style) {
      _ActionStyle.on => (_okGreen, Colors.white, _okGreen),
      _ActionStyle.warn => (const Color(0xFFFFEFD6), AgendaLight.warn, const Color(0xFFFFEFD6)),
      _ActionStyle.off => (const Color(0xFFF4F3EF), AgendaLight.ink, AgendaLight.line),
    };
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 50,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 19, color: fg),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, style: TextStyle(color: fg, fontSize: 15.5, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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

  /// Prodotti venduti insieme a questa visita (si sommano al conto).
  List<ProductSale> _sales = [];
  late double _productsTotal = widget.appointment.productsTotal;

  double get _total => widget.appointment.price + _productsTotal;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    try {
      final sales = await AppScope.read(context).backend.appointmentSales(widget.appointment.id);
      if (!mounted) return;
      setState(() {
        _sales = sales;
        _productsTotal = sales.fold<double>(0, (s, x) => s + x.total);
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _addProduct() async {
    final sold = await showSellSheet(context, appointmentId: widget.appointment.id);
    if (sold && mounted) await _loadSales();
  }

  Future<void> _removeSale(ProductSale s) async {
    try {
      // il prodotto torna in magazzino e esce dal conto
      await AppScope.read(context).backend.cancelSale(s.id);
      if (mounted) await _loadSales();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final price = _total;
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
              'Pagamento · ${fmtPrice(_total)}',
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
                    'Totale oggi: ${fmtPrice(_total - a.collected + _debt)}',
                    style: const TextStyle(color: Color(0xFF6B3A00), fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            // prodotti comprati insieme al taglio: dal magazzino al conto
            for (final s in _sales)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4EC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AgendaLight.ok.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_bag_outlined, color: AgendaLight.ok, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${s.qty > 1 ? '${s.qty} × ' : ''}${s.productName}',
                        style: const TextStyle(color: AgendaLight.ink, fontSize: 14.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      fmtPrice(s.total),
                      style: const TextStyle(color: AgendaLight.ink, fontSize: 14.5, fontWeight: FontWeight.w800),
                    ),
                    IconButton(
                      tooltip: 'Togli (torna in magazzino)',
                      onPressed: () => _removeSale(s),
                      icon: const Icon(Icons.close, color: AgendaLight.sub, size: 20),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _addProduct,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AgendaLight.line),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.add_shopping_cart, color: AgendaLight.ink),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Aggiunta prodotto',
                                style: TextStyle(color: AgendaLight.ink, fontSize: 15.5, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                _sales.isEmpty
                                    ? 'Scegli dal magazzino: si aggiunge al conto'
                                    : 'Servizio ${fmtPrice(a.price)} + prodotti ${fmtPrice(_productsTotal)}',
                                style: const TextStyle(color: AgendaLight.sub, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: AgendaLight.sub),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _option(PaymentStatus.paid, Icons.check_circle_outline, 'Pagato', 'Ha pagato tutto: ${fmtPrice(_total)}'),
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
                      return v == null || v <= 0 || v >= _total ? null : 'Resta da pagare ${fmtPrice(_total - v)}';
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
