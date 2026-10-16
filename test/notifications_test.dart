import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:the_mans_house/models.dart';
import 'package:the_mans_house/notifications.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it_IT'));

  test('segnaposto: si sostituiscono quelli noti, gli altri restano', () {
    expect(fillNotif('{giorno} · {ora} con {barbiere}', {'giorno': 'sab 17', 'ora': '10:30', 'barbiere': 'Antonio'}),
        'sab 17 · 10:30 con Antonio');
    expect(fillNotif('Ciao {sconosciuto}', {}), 'Ciao {sconosciuto}');
  });

  test('preferenze: testi di partenza, testi modificati, notifiche spente', () {
    final n = NotifSettings();
    expect(n.enabled(NotifKind.reminderDay), isTrue);
    expect(n.offset(NotifKind.reminderDay), 24 * 60);
    expect(n.offset(NotifKind.attendanceCheck), 18 * 60);
    expect(n.build(NotifKind.bookingConfirmed, notifSample)!.body, 'sab 17 ott · 10:30 · Taglio con Antonio');

    n.prefs['reminderHour'] = NotifPref(title: 'Ci vediamo alle {ora}', offset: 30);
    n.prefs['news'] = NotifPref(enabled: false);
    expect(n.build(NotifKind.reminderHour, notifSample)!.title, 'Ci vediamo alle 10:30');
    expect(n.offset(NotifKind.reminderHour), 30);
    expect(n.build(NotifKind.news, notifSample), isNull);

    // si salva nelle impostazioni del negozio e si rilegge uguale
    final s = ShopSettings()..notifications = n.toJson();
    final back = NotifSettings.fromJson(ShopSettings.fromJson(s.toJson()).notifications);
    expect(back.title(NotifKind.reminderHour), 'Ci vediamo alle {ora}');
    expect(back.enabled(NotifKind.news), isFalse);
    expect(back.enabled(NotifKind.review), isTrue);
  });

  test('conferma presenza: dal giorno prima all\'ora scelta, finche\' non risponde', () {
    final n = NotifSettings();
    final a = Appointment(
      id: 'a',
      barberId: 'b',
      serviceName: 'Taglio',
      price: 15,
      start: DateTime(2026, 10, 17, 10, 30),
      end: DateTime(2026, 10, 17, 11),
    );
    expect(needsAttendance(a, n, DateTime(2026, 10, 16, 17, 59)), isFalse);
    expect(needsAttendance(a, n, DateTime(2026, 10, 16, 18)), isTrue);
    expect(needsAttendance(a, n, DateTime(2026, 10, 17, 9)), isTrue);
    expect(needsAttendance(a, n, DateTime(2026, 10, 17, 10, 31)), isFalse); // gia' iniziato
    a.attendanceConfirmedAt = DateTime(2026, 10, 16, 19);
    expect(needsAttendance(a, n, DateTime(2026, 10, 16, 20)), isFalse);
    // spenta dall'area riservata
    a.attendanceConfirmedAt = null;
    n.prefs['attendanceCheck'] = NotifPref(enabled: false);
    expect(needsAttendance(a, n, DateTime(2026, 10, 16, 20)), isFalse);
  });

  test('voto: un\'ora dopo la fine, per 7 giorni, una volta sola', () {
    final n = NotifSettings();
    final a = Appointment(
      id: 'a',
      barberId: 'b',
      serviceName: 'Taglio',
      price: 15,
      start: DateTime(2026, 10, 17, 10, 30),
      end: DateTime(2026, 10, 17, 11),
      status: AppointmentStatus.completed,
    );
    expect(needsReview(a, n, DateTime(2026, 10, 17, 11, 30)), isFalse);
    expect(needsReview(a, n, DateTime(2026, 10, 17, 12)), isTrue);
    expect(needsReview(a, n, DateTime(2026, 10, 25)), isFalse);
    a.reviewStars = 5;
    expect(needsReview(a, n, DateTime(2026, 10, 17, 12)), isFalse);
    a
      ..reviewStars = null
      ..status = AppointmentStatus.noShow;
    expect(needsReview(a, n, DateTime(2026, 10, 17, 12)), isFalse);
  });

  Appointment appt(String id, DateTime start, {AppointmentStatus status = AppointmentStatus.confirmed, String notes = ''}) =>
      Appointment(
        id: id,
        barberId: 'b1',
        barberName: 'Antonio',
        serviceName: 'Taglio',
        price: 15,
        start: start,
        end: start.add(const Duration(minutes: 30)),
        status: status,
        notes: notes,
      );

  test('programma: promemoria, conferma presenza e voto ai tempi scelti', () {
    final s = ShopSettings();
    final now = DateTime(2026, 10, 15, 9);
    final a = appt('a', DateTime(2026, 10, 17, 10, 30));
    final plan = planNotifications([a], s, now);
    expect(plan.map((p) => (p.kind, p.at)), [
      (NotifKind.reminderDay, DateTime(2026, 10, 16, 10, 30)),
      (NotifKind.attendanceCheck, DateTime(2026, 10, 16, 18)),
      (NotifKind.reminderHour, DateTime(2026, 10, 17, 9, 30)),
      (NotifKind.review, DateTime(2026, 10, 17, 12)),
    ]);
    expect(plan.first.content.body, '10:30 · Taglio con Antonio. Ti aspettiamo');

    // spente o gia' confermate non si programmano; i testi modificati si usano
    s.notifications = (NotifSettings()
          ..prefs['reminderDay'] = NotifPref(enabled: false)
          ..prefs['reminderHour'] = NotifPref(title: 'Alle {ora} da {barbiere}', offset: 30))
        .toJson();
    a.attendanceConfirmedAt = now;
    final p2 = planNotifications([a], s, now);
    expect(p2.map((p) => p.kind), [NotifKind.reminderHour, NotifKind.review]);
    expect(p2.first.at, DateTime(2026, 10, 17, 10));
    expect(p2.first.content.title, 'Alle 10:30 da Antonio');
    // gli id restano uguali riprogrammando
    expect(p2.first.id, notifId('a', NotifKind.reminderHour));
  });

  test('novità per il cliente: posto dalla lista, spostato, annullato; non le sue modifiche', () {
    final now = DateTime(2026, 10, 15, 9);
    final a = appt('a', DateTime(2026, 10, 17, 10));
    final b = appt('b', DateTime(2026, 10, 18, 10));
    final before = apptSnapshot([a, b]);
    expect(clientEvents(null, [a, b], {}, now), isEmpty); // prima apertura

    final moved = appt('a', DateTime(2026, 10, 17, 11));
    final cancelled = appt('b', DateTime(2026, 10, 18, 10), status: AppointmentStatus.cancelled);
    final fromList = appt('c', DateTime(2026, 10, 19, 10), notes: 'Dalla lista d\'attesa');
    final ev = clientEvents(before, [moved, cancelled, fromList], {}, now);
    expect(ev.map((e) => e.$1), [NotifKind.moved, NotifKind.cancelled, NotifKind.waitlistAssigned]);
    // spostato e annullato da lui stesso: nessun avviso
    expect(clientEvents(before, [moved, cancelled], {'a', 'b'}, now), isEmpty);
  });

  test('novità per il negozio: nuove prenotazioni dei clienti e annullamenti', () {
    final now = DateTime(2026, 10, 15, 9);
    final a = appt('a', DateTime(2026, 10, 17, 10));
    final before = apptSnapshot([a]);
    final mine = appt('m', DateTime(2026, 10, 17, 12))..createdByAdmin = true;
    final client = appt('n', DateTime(2026, 10, 17, 15));
    final gone = appt('a', DateTime(2026, 10, 17, 10), status: AppointmentStatus.cancelled);
    final ev = shopEvents(before, [gone, mine, client], {}, now);
    expect(ev.map((e) => (e.$1, e.$2.id)), [(NotifKind.bookingCancelled, 'a'), (NotifKind.newBooking, 'n')]);
    expect(shopEvents(before, [gone], {'a'}, now), isEmpty); // annullato dal negozio
  });

  test('ogni tipo ha testi e un segnaposto valido', () {
    expect(notifTypes.map((t) => t.kind).toSet().length, NotifKind.values.length);
    for (final t in notifTypes) {
      for (final m in RegExp(r'\{(\w+)\}').allMatches('${t.title} ${t.body}')) {
        expect(t.placeholders, contains(m.group(1)), reason: '${t.label}: {${m.group(1)}}');
      }
    }
  });
}
