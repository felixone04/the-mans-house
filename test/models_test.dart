import 'package:flutter_test/flutter_test.dart';
import 'package:the_mans_house/data/calendar.dart';
import 'package:the_mans_house/data/slots.dart';
import 'package:the_mans_house/models.dart';

void main() {
  group('normalizePhone', () {
    test('aggiunge il prefisso italiano e toglie spazi e simboli', () {
      expect(normalizePhone('333 123 4567'), '+393331234567');
      expect(normalizePhone('333-123.45(67)'), '+393331234567');
      expect(normalizePhone('0883 123456'), '+390883123456');
    });

    test('mantiene i prefissi internazionali', () {
      expect(normalizePhone('+39 333 1234567'), '+393331234567');
      expect(normalizePhone('0039 333 1234567'), '+393331234567');
      expect(normalizePhone('+44 7700 900123'), '+447700900123');
    });

    test('campo vuoto o solo spazi', () {
      expect(normalizePhone(''), '');
      expect(normalizePhone('   '), '');
    });
  });

  group('isValidPhone', () {
    test('numeri validi', () {
      expect(isValidPhone('3331234567'), isTrue);
      expect(isValidPhone('+39 333 123 4567'), isTrue);
      expect(isValidPhone('0039 333 1234567'), isTrue);
    });

    test('numeri non validi', () {
      expect(isValidPhone(''), isFalse);
      expect(isValidPhone('+39 '), isFalse); // valore iniziale del campo
      expect(isValidPhone('12345'), isFalse);
      expect(isValidPhone('333 abc 4567'), isFalse);
      expect(isValidPhone('+39 3331234567890123'), isFalse); // troppe cifre
    });
  });

  test('parseTime / formatTime', () {
    expect(parseTime('09:30:00'), 9 * 60 + 30);
    expect(parseTime('15:05'), 15 * 60 + 5);
    expect(formatTime(9 * 60 + 5), '09:05');
    expect(formatTime(20 * 60), '20:00');
  });

  test('Barber.hoursFor ordina le fasce del giorno', () {
    final b = Barber(id: 'x', name: 'Mario Rossi', hours: [
      WorkingHours(weekday: 2, start: 15 * 60, end: 19 * 60),
      WorkingHours(weekday: 2, start: 9 * 60, end: 13 * 60),
      WorkingHours(weekday: 3, start: 9 * 60, end: 13 * 60),
    ]);
    expect(b.hoursFor(2).map((h) => h.start), [9 * 60, 15 * 60]);
    expect(b.hoursFor(7), isEmpty);
    expect(b.initials, 'MR');
  });

  test('Profile.isComplete richiede nome, telefono e informativa privacy accettata', () {
    final accepted = DateTime(2026, 10, 13);
    expect(Profile(id: '1', fullName: 'Mario', phone: '+393331234567', privacyAcceptedAt: accepted).isComplete, isTrue);
    expect(Profile(id: '1', fullName: 'Mario', phone: '+393331234567').isComplete, isFalse);
    expect(Profile(id: '1', fullName: 'Mario', privacyAcceptedAt: accepted).isComplete, isFalse);
    expect(Profile(id: '1', phone: '+393331234567', privacyAcceptedAt: accepted).isComplete, isFalse);
  });

  test('ShopDay: chiusura, orario speciale solo per alcuni barbieri, JSON', () {
    final b = Barber(id: 'b1', name: 'Antonio', hours: [WorkingHours(weekday: 2, start: 540, end: 1200)]);
    final tuesday = DateTime(2026, 10, 20); // martedi'
    expect(b.hoursOn(tuesday).single.start, 540);

    ShopCalendar.set([ShopDay(day: tuesday, note: 'Ferie')]);
    expect(b.hoursOn(tuesday), isEmpty);

    final sunday = DateTime(2026, 10, 25);
    ShopCalendar.set([
      ShopDay(day: sunday, open: 540, close: 780, barberIds: ['b1']),
    ]);
    expect(b.hoursOn(sunday).single.end, 780);
    expect(Barber(id: 'b2', name: 'Giuseppe').hoursOn(sunday), isEmpty);

    final json = ShopDay(day: sunday, open: 540, close: 780, note: 'x').toJson();
    expect(json, {'day': '2026-10-25', 'open_time': '09:00', 'close_time': '13:00', 'note': 'x', 'barber_ids': null});
    final back = ShopDay.fromJson({...json, 'open_time': '09:00:00', 'close_time': '13:00:00'});
    expect((back.open, back.close, back.closed), (540, 780, false));
    ShopCalendar.set(const []);
  });

  test('stato del negozio in home: aperto, pausa, chiusura e prossima apertura', () {
    final b = Barber(id: 'b1', name: 'Antonio', hours: [
      WorkingHours(weekday: 2, start: 540, end: 780),
      WorkingHours(weekday: 2, start: 930, end: 1200),
      WorkingHours(weekday: 3, start: 540, end: 780),
    ]);
    DateTime at(int day, int h, int m) => DateTime(2026, 10, day, h, m); // 20 = martedi'
    expect(shopStatus([b], at(20, 10, 0)), (true, 'Aperto · chiude alle 13:00'));
    expect(shopStatus([b], at(20, 14, 0)), (false, 'Chiuso · apre alle 15:30'));
    expect(shopStatus([b], at(20, 21, 0)), (false, 'Chiuso · apre domani alle 09:00'));
    expect(shopStatus([b], at(21, 14, 0)), (false, 'Chiuso · apre martedì alle 09:00'));
    // chiusura straordinaria domani: si salta al giorno dopo utile
    ShopCalendar.set([ShopDay(day: DateTime(2026, 10, 21), note: 'Ferie')]);
    expect(shopStatus([b], at(20, 21, 0)), (false, 'Chiuso · apre martedì alle 09:00'));
    ShopCalendar.set(const []);
  });

  test('calendario: link Google e file .ics con orari in UTC e testo protetto', () {
    final e = CalendarEvent(
      title: 'Taglio, barba; rifinitura',
      start: DateTime.utc(2026, 10, 16, 8, 30),
      end: DateTime.utc(2026, 10, 16, 9, 20),
      location: 'Via Garibaldi 91, Andria',
    );
    expect(e.googleUrl.queryParameters['dates'], '20261016T083000Z/20261016T092000Z');
    final ics = e.toIcs(now: DateTime.utc(2026, 10, 15));
    expect(ics, contains('DTSTART:20261016T083000Z\r\n'));
    expect(ics, contains(r'SUMMARY:Taglio\, barba\; rifinitura'));
    expect(ics, contains(r'LOCATION:Via Garibaldi 91\, Andria'));
    expect(ics, contains('TRIGGER:-PT1H'));
  });

  test('candidateSlots: tutti gli orari della fascia, anche quelli gia\' presi', () {
    final b = Barber(id: 'b1', name: 'Antonio', hours: [WorkingHours(weekday: 2, start: 540, end: 600)]);
    final day = DateTime(2026, 10, 20);
    final all = candidateSlots(barbers: [b], durationMin: 30, day: day, stepMin: 15, now: DateTime(2026, 10, 1));
    expect(all.map((s) => s.hour * 60 + s.minute), [540, 555, 570]);
    // gli orari gia' passati non compaiono
    expect(candidateSlots(barbers: [b], durationMin: 30, day: day, stepMin: 15, now: DateTime(2026, 10, 20, 9, 10)).length, 2);
  });

  test('Appointment.isUpcoming solo se confermato e futuro', () {
    Appointment a(DateTime start, AppointmentStatus s) => Appointment(
        id: '1',
        barberId: 'b',
        serviceName: 'Taglio',
        price: 15,
        start: start,
        end: start.add(const Duration(minutes: 30)),
        status: s);
    final future = DateTime.now().add(const Duration(days: 1));
    final past = DateTime.now().subtract(const Duration(days: 1));
    expect(a(future, AppointmentStatus.confirmed).isUpcoming, isTrue);
    expect(a(future, AppointmentStatus.cancelled).isUpcoming, isFalse);
    expect(a(past, AppointmentStatus.confirmed).isUpcoming, isFalse);
  });
}
