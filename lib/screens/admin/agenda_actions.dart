import 'package:flutter/material.dart';

import '../../data/slots.dart';
import '../../models.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../booking_screen.dart';
import 'block_time_sheet.dart';
import 'customer_screen.dart';

int minuteOf(DateTime d) => d.hour * 60 + d.minute;

/// Parte di un'assenza che cade nel giorno, in minuti dalla mezzanotte.
(int, int) offRangeIn(DateTime day, TimeOff t) {
  final next = DateTime(day.year, day.month, day.day + 1);
  return (t.start.isAfter(day) ? minuteOf(t.start) : 0, t.end.isBefore(next) ? minuteOf(t.end) : 24 * 60);
}

/// Spazi liberi di un barbiere nel giorno (minuti dalla mezzanotte), almeno
/// [minGap] minuti. Oggi si parte dall'ora attuale; i giorni passati non ne hanno.
List<(int, int)> freeRanges(
  DateTime day,
  Barber b,
  List<Appointment> appointments,
  List<TimeOff> off, {
  int minGap = 15,
}) {
  final now = DateTime.now();
  final today = dayOnly(now);
  if (day.isBefore(today)) return [];
  final from = day == today ? ((minuteOf(now) + 4) ~/ 5) * 5 : 0;
  final busy = <(int, int)>[
    for (final a in appointments.where((a) => a.barberId == b.id && a.status != AppointmentStatus.cancelled))
      (minuteOf(a.start), minuteOf(a.start) + a.end.difference(a.start).inMinutes),
    for (final t in off) offRangeIn(day, t),
  ]..sort((x, y) => x.$1.compareTo(y.$1));
  final result = <(int, int)>[];
  void add(int s, int e) {
    if (s < from) s = from;
    if (e - s >= minGap) result.add((s, e));
  }

  for (final h in b.hoursOn(day)) {
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

/// Azioni dell'agenda condivise tra la vista generale e la giornata del
/// singolo barbiere: prenotare, spostare, bloccare, cambiare stato...
/// Dopo ogni modifica viene chiamato [reloadAgenda].
mixin AgendaActions<T extends StatefulWidget> on State<T> {
  /// Giorno mostrato.
  DateTime get agendaDay;

  /// Appuntamenti del giorno (per avvisare dei conflitti quando si blocca un orario).
  List<Appointment> get agendaDayAppointments;

  Future<void> reloadAgenda();

  Future<void> newAppointment({Barber? barber, DateTime? time}) async {
    final created = await Navigator.of(context).push<bool>(
      fadeRoute(
        BookingScreen(adminMode: true, initialDay: time ?? agendaDay, initialBarber: barber, initialTime: time),
      ),
    );
    if (created == true) await reloadAgenda();
  }

  Future<void> moveAppointment(Appointment a) async {
    final moved = await Navigator.of(context).push<bool>(fadeRoute(BookingScreen(adminMode: true, reschedule: a)));
    if (moved == true) await reloadAgenda();
  }

  Future<void> blockTime({Barber? barber, int? start, int? end}) async {
    final state = AppScope.read(context);
    final ok = await showBlockTimeSheet(
      context,
      day: agendaDay,
      barbers: state.barbers,
      appointments: agendaDayAppointments,
      barber: barber,
      startMin: start,
      endMin: end,
    );
    if (ok && mounted) {
      showMessage(context, 'Orario bloccato');
      await reloadAgenda();
    }
  }

  Future<void> removeBlock(TimeOff t, Barber b) async {
    final day = agendaDay;
    final (s, e) = offRangeIn(day, t);
    final ok = await confirmDialog(
      context,
      title: 'Rimuovere il blocco?',
      message:
          '${b.name} · ${t.reason.isEmpty ? 'Assente' : t.reason}\n'
          '${s == 0 && e == 24 * 60 ? 'Tutto il giorno' : '${formatTime(s)} – ${formatTime(e)}'}\n'
          'L\'orario tornerà prenotabile.',
      confirm: 'Rimuovi',
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).backend.deleteTimeOff(t.id);
      await reloadAgenda();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> setAppointmentStatus(Appointment a, AppointmentStatus s) async {
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
      await reloadAgenda();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// Cambio di stato rapido (tasto ✓), con possibilita' di annullare.
  Future<void> quickStatus(Appointment a, AppointmentStatus s) async {
    final backend = AppScope.read(context).backend;
    final previous = a.status;
    try {
      await backend.setAppointmentStatus(a.id, s);
      await reloadAgenda();
      if (!mounted) return;
      showMessage(
        context,
        '${a.customerName.isEmpty ? 'Cliente' : a.customerName}: ${statusLabel(s).toLowerCase()}',
        actionLabel: 'Annulla',
        onAction: () async {
          try {
            await backend.setAppointmentStatus(a.id, previous);
            if (mounted) await reloadAgenda();
          } catch (e) {
            if (mounted) showError(context, e);
          }
        },
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void sendReminder(Appointment a) {
    final shop = AppScope.read(context).settings.name;
    final text =
        'Ciao ${a.customerName.split(' ').first}, ti ricordiamo l\'appuntamento da $shop '
        '${fmtDayLong(a.start).toLowerCase()} alle ${fmtTime(a.start)}'
        '${a.barberName.isEmpty ? '' : ' con ${a.barberName}'} (${a.serviceName}). A presto!';
    openWhatsApp(context, a.customerPhone, text);
  }

  void openCustomerOf(Appointment a) {
    final c = CustomerSummary(
      id: a.userId ?? '${CustomerSummary.walkInPrefix}${a.customerName}',
      email: '',
      fullName: a.customerName,
      phone: a.customerPhone,
      bookings: 0,
    );
    Navigator.of(context).push(fadeRoute(CustomerScreen(customer: c))).then((_) => reloadAgenda());
  }

  /// Dettaglio dell'appuntamento con tutte le azioni.
  void openAppointment(Appointment a) {
    showModalBottomSheet<void>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 520),
      // su schermi bassi il contenuto supera l'altezza predefinita del foglio
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
                            onPressed: () => act(() => sendReminder(a)),
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
                      onTap: () => act(() => openCustomerOf(a)),
                    ),
                  if (a.status == AppointmentStatus.confirmed) ...[
                    ListTile(
                      leading: const Icon(Icons.edit_calendar_outlined),
                      title: const Text('Sposta appuntamento'),
                      onTap: () => act(() => moveAppointment(a)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.done_all),
                      title: const Text('Segna come completato'),
                      onTap: () => act(() => setAppointmentStatus(a, AppointmentStatus.completed)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_off_outlined),
                      title: const Text('Non presentato'),
                      onTap: () => act(() => setAppointmentStatus(a, AppointmentStatus.noShow)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.close, color: AppColors.danger),
                      title: const Text('Annulla appuntamento', style: TextStyle(color: AppColors.danger)),
                      onTap: () => act(() => setAppointmentStatus(a, AppointmentStatus.cancelled)),
                    ),
                  ] else if (a.status != AppointmentStatus.cancelled)
                    ListTile(
                      leading: const Icon(Icons.undo),
                      title: const Text('Ripristina come confermato'),
                      onTap: () => act(() => setAppointmentStatus(a, AppointmentStatus.confirmed)),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
