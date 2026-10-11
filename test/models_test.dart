import 'package:flutter_test/flutter_test.dart';
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

  test('Profile.isComplete richiede nome e telefono', () {
    expect(Profile(id: '1', fullName: 'Mario', phone: '+393331234567').isComplete, isTrue);
    expect(Profile(id: '1', fullName: 'Mario').isComplete, isFalse);
    expect(Profile(id: '1', phone: '+393331234567').isComplete, isFalse);
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
