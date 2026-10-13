import 'package:flutter_test/flutter_test.dart';
import 'package:the_mans_house/data/backend.dart';
import 'package:the_mans_house/data/demo_backend.dart';
import 'package:the_mans_house/data/slots.dart';
import 'package:the_mans_house/models.dart';

/// Regole del backend demo (le stesse applicate dal server Supabase).
void main() {
  late DemoBackend backend;

  setUp(() async {
    backend = DemoBackend();
    await backend.init();
  });

  /// Primo orario libero del barbiere dopo [after] (passo 15 minuti).
  Future<DateTime> freeSlot(Barber b, Service s, DateTime after) async {
    final from = dayOnly(after);
    final busy = await backend.fetchBusy(from, from.add(const Duration(days: 15)));
    for (var i = 0; i < 15; i++) {
      final day = DateTime(from.year, from.month, from.day + i);
      final slots = availableSlots(
        barber: b,
        durationMin: s.durationMin,
        day: day,
        busy: busy,
        stepMin: 15,
      ).where((t) => t.isAfter(after));
      if (slots.isNotEmpty) return slots.first;
    }
    throw StateError('nessun orario libero');
  }

  Future<void> signUp(String email) =>
      backend.signUpWithEmail(email: email, password: 'segreta1', fullName: 'Mario Rossi', phone: '333 1234567');

  test('registrazione: telefono normalizzato, email duplicata e password corta rifiutate', () async {
    await signUp('mario@test.it');
    final p = await backend.fetchProfile();
    expect(p!.phone, '+393331234567');
    expect(p.isComplete, isTrue);
    expect(p.isAdmin, isFalse);
    await backend.signOut();
    expect(backend.isSignedIn, isFalse);
    await expectLater(() => signUp('MARIO@test.it'), throwsA(isA<AppException>()));
    await expectLater(
      () => backend.signUpWithEmail(email: 'x@test.it', password: '123', fullName: 'X', phone: '3331234567'),
      throwsA(isA<AppException>()),
    );
  });

  test('login: password errata rifiutata, admin riconosciuto', () async {
    await expectLater(() => backend.signInWithEmail(DemoBackend.adminEmail, 'sbagliata'), throwsA(isA<AppException>()));
    await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
    expect((await backend.fetchProfile())!.isAdmin, isTrue);
  });

  test('login social: profilo senza telefono da completare', () async {
    await backend.signInWithGoogle();
    final p = await backend.fetchProfile();
    expect(p!.isComplete, isFalse);
    await backend.updateProfile(Profile(id: p.id, email: p.email, fullName: 'Cliente Google', phone: '3339998877'));
    expect((await backend.fetchProfile())!.isComplete, isTrue);
  });

  test('prenotazione: niente doppie prenotazioni ne orari fuori fascia o passati', () async {
    await signUp('luca@test.it');
    final barber = (await backend.fetchBarbers()).first;
    final service = (await backend.fetchServices()).first;
    final start = await freeSlot(barber, service, DateTime.now().add(const Duration(hours: 3)));

    final a = await backend.book(barberId: barber.id, serviceId: service.id, start: start);
    expect(a.customerName, 'Mario Rossi');
    expect(a.end, start.add(Duration(minutes: service.durationMin)));
    expect((await backend.myAppointments()).map((x) => x.id), contains(a.id));

    // stesso orario o sovrapposto: rifiutato
    await expectLater(
      () => backend.book(barberId: barber.id, serviceId: service.id, start: start),
      throwsA(isA<AppException>()),
    );
    await expectLater(
      () => backend.book(barberId: barber.id, serviceId: service.id, start: start.add(const Duration(minutes: 10))),
      throwsA(isA<AppException>()),
    );
    // passato
    await expectLater(
      () => backend.book(
        barberId: barber.id,
        serviceId: service.id,
        start: DateTime.now().subtract(const Duration(hours: 1)),
      ),
      throwsA(isA<AppException>()),
    );
    // fuori orario (alle 3 di notte)
    final night = DateTime(start.year, start.month, start.day, 3);
    await expectLater(
      () => backend.book(barberId: barber.id, serviceId: service.id, start: night),
      throwsA(isA<AppException>()),
    );
  });

  test('prenotazione: orario non multiplo di 5 minuti accettato se libero', () async {
    // con "Intervallo orari" = 7 min gli slot cadono su 9:07, 9:14, ...
    await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
    await backend.saveBarber(
      Barber(
        name: 'Prova',
        hours: [for (var d = 1; d <= 7; d++) WorkingHours(weekday: d, start: 9 * 60, end: 13 * 60)],
      ),
    );
    final barber = (await backend.fetchBarbers()).firstWhere((b) => b.name == 'Prova');
    final service = (await backend.fetchServices()).first;
    final t = DateTime.now().add(const Duration(days: 1));
    final odd = DateTime(t.year, t.month, t.day, 9, 7);
    final a = await backend.book(barberId: barber.id, serviceId: service.id, start: odd);
    expect(a.start, odd);
  });

  test('prenotazione: ferie escluse', () async {
    await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
    final barber = (await backend.fetchBarbers()).first;
    final service = (await backend.fetchServices()).first;
    final start = await freeSlot(barber, service, DateTime.now().add(const Duration(hours: 3)));
    final d = dayOnly(start);
    await backend.addTimeOff(TimeOff(barberId: barber.id, start: d, end: d.add(const Duration(days: 1))));
    await expectLater(
      () => backend.book(barberId: barber.id, serviceId: service.id, start: start),
      throwsA(isA<AppException>()),
    );
  });

  test('prenotazione: data oltre il limite rifiutata al cliente', () async {
    await signUp('lontano@test.it');
    final settings = await backend.fetchSettings();
    final barber = (await backend.fetchBarbers()).first;
    final service = (await backend.fetchServices()).first;
    final far = await freeSlot(barber, service, DateTime.now().add(Duration(days: settings.bookingDaysAhead + 2)));
    await expectLater(
      () => backend.book(barberId: barber.id, serviceId: service.id, start: far),
      throwsA(isA<AppException>()),
    );
  });

  test('admin: prenotazione per un cliente senza account', () async {
    await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
    final barber = (await backend.fetchBarbers()).first;
    final service = (await backend.fetchServices()).first;
    final start = await freeSlot(barber, service, DateTime.now().add(const Duration(hours: 3)));
    final a = await backend.book(
      barberId: barber.id,
      serviceId: service.id,
      start: start,
      customerName: 'Telefonico',
      customerPhone: '',
    );
    expect(a.userId, isNull);
    expect(a.createdByAdmin, isTrue);
    expect(a.customerName, 'Telefonico');
    expect(a.customerPhone, '');
  });

  test('annullamento: solo fino a minCancelHours prima, solo i propri, admin sempre', () async {
    // limite ampio per avere un appuntamento "troppo vicino"
    final settings = await backend.fetchSettings();
    settings.minCancelHours = 72;
    await backend.saveSettings(settings);

    await signUp('anna@test.it');
    final barber = (await backend.fetchBarbers()).first;
    final service = (await backend.fetchServices()).first;
    final soon = await freeSlot(barber, service, DateTime.now().add(const Duration(hours: 1)));
    final a = await backend.book(barberId: barber.id, serviceId: service.id, start: soon);
    await expectLater(() => backend.cancelAppointment(a.id), throwsA(isA<AppException>()));

    // con limite 0 il cliente puo' annullare
    settings.minCancelHours = 0;
    await backend.saveSettings(settings);
    await backend.cancelAppointment(a.id);
    expect((await backend.myAppointments()).firstWhere((x) => x.id == a.id).status, AppointmentStatus.cancelled);
    // gia' annullato
    await expectLater(() => backend.cancelAppointment(a.id), throwsA(isA<AppException>()));

    // un altro cliente non puo' annullare appuntamenti altrui
    final b = await backend.book(barberId: barber.id, serviceId: service.id, start: soon);
    await backend.signOut();
    await signUp('intruso@test.it');
    await expectLater(() => backend.cancelAppointment(b.id), throwsA(isA<AppException>()));
    expect((await backend.myAppointments()).any((x) => x.id == b.id), isFalse);

    // l'admin puo' annullare anche a ridosso
    settings.minCancelHours = 72;
    await backend.signOut();
    await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
    await backend.saveSettings(settings);
    await backend.cancelAppointment(b.id);
  });

  test('eliminazione account: appuntamenti futuri annullati e login impossibile', () async {
    await signUp('via@test.it');
    final barber = (await backend.fetchBarbers()).first;
    final service = (await backend.fetchServices()).first;
    final start = await freeSlot(barber, service, DateTime.now().add(const Duration(hours: 3)));
    await backend.book(barberId: barber.id, serviceId: service.id, start: start);
    await backend.deleteAccount();
    expect(backend.isSignedIn, isFalse);
    await expectLater(() => backend.signInWithEmail('via@test.it', 'segreta1'), throwsA(isA<AppException>()));
    final busy = await backend.fetchBusy(start, start.add(const Duration(minutes: 1)));
    expect(busy.where((x) => x.barberId == barber.id), isEmpty);
  });

  test('primo disponibile: la prenotazione va al barbiere assegnato, ferie escluse', () async {
    await signUp('primo@test.it');
    final barbers = await backend.fetchBarbers();
    final service = (await backend.fetchServices()).first;
    final tomorrow = dayOnly(DateTime.now()).add(const Duration(days: 1));
    // trova un giorno lavorativo con orari liberi nei prossimi 10 giorni
    for (var i = 0; i < 10; i++) {
      final day = DateTime(tomorrow.year, tomorrow.month, tomorrow.day + i);
      var busy = await backend.fetchBusy(day, day.add(const Duration(days: 1)));
      var map = availableSlotsAnyBarber(
        barbers: barbers,
        durationMin: service.durationMin,
        day: day,
        busy: busy,
        stepMin: 15,
      );
      if (map.isEmpty) continue;

      // ferie di un giorno per il barbiere assegnato al primo orario: non deve piu' essere scelto
      final first = map.keys.first;
      final assigned = map[first]!;
      await backend.signOut();
      await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
      await backend.addTimeOff(TimeOff(barberId: assigned.id, start: day, end: day.add(const Duration(days: 1))));
      await backend.signOut();
      await backend.signInWithEmail('primo@test.it', 'segreta1');
      busy = await backend.fetchBusy(day, day.add(const Duration(days: 1)));
      expect(busy.where((b) => b.timeOff && b.barberId == assigned.id), isNotEmpty);
      map = availableSlotsAnyBarber(
        barbers: barbers,
        durationMin: service.durationMin,
        day: day,
        busy: busy,
        stepMin: 15,
      );
      expect(map.values.any((b) => b.id == assigned.id), isFalse);
      if (map.isEmpty) continue;

      final slot = map.keys.first;
      final appt = await backend.book(barberId: map[slot]!.id, serviceId: service.id, start: slot);
      expect(appt.barberId, map[slot]!.id);
      final mine = await backend.myAppointments();
      expect(mine.any((a) => a.id == appt.id && a.barberId == map[slot]!.id), isTrue);
      return;
    }
    fail('nessun giorno con orari liberi');
  });

  test('spostamento: stessa durata, orario libero, regole come l\'annullamento', () async {
    await signUp('sposta@test.it');
    final barber = (await backend.fetchBarbers()).first;
    final service = (await backend.fetchServices()).first;
    final start = await freeSlot(barber, service, DateTime.now().add(const Duration(hours: 4)));
    final a = await backend.book(barberId: barber.id, serviceId: service.id, start: start);

    // spostato sul primo orario libero dopo: stessa durata
    final target = await freeSlot(barber, service, a.end);
    await backend.rescheduleAppointment(a.id, barberId: barber.id, start: target);
    final moved = (await backend.myAppointments()).firstWhere((x) => x.id == a.id);
    expect(moved.start, target);
    expect(moved.end, target.add(Duration(minutes: service.durationMin)));
    // il vecchio orario torna libero
    final busy = await backend.fetchBusy(start, start.add(const Duration(minutes: 1)));
    expect(busy.where((x) => x.barberId == barber.id && !x.timeOff), isEmpty);

    // sullo stesso orario (si sovrappone solo a se stesso) e' consentito
    await backend.rescheduleAppointment(a.id, barberId: barber.id, start: target);

    // orario occupato da un altro appuntamento: rifiutato
    final other = await backend.book(barberId: barber.id, serviceId: service.id, start: start);
    await expectLater(
      () => backend.rescheduleAppointment(a.id, barberId: barber.id, start: other.start),
      throwsA(isA<AppException>()),
    );

    // un altro cliente non puo' spostarlo
    await backend.signOut();
    await signUp('altro@test.it');
    await expectLater(
      () => backend.rescheduleAppointment(a.id, barberId: barber.id, start: target),
      throwsA(isA<AppException>()),
    );
  });

  test('scheda cliente: appuntamenti del cliente dal banco', () async {
    await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
    final customers = await backend.customers();
    final walkIn = customers.firstWhere((c) => c.isWalkIn);
    final list = await backend.customerAppointments(walkIn);
    expect(list, isNotEmpty);
    expect(list.every((a) => a.customerName == walkIn.fullName && a.userId == null), isTrue);
  });

  test('arrivo e pagamento: solo l\'admin, acconto e resto da incassare', () async {
    await signUp('visita@test.it');
    final barber = (await backend.fetchBarbers()).first;
    final service = (await backend.fetchServices()).first;
    final start = await freeSlot(barber, service, DateTime.now().add(const Duration(hours: 4)));
    final a = await backend.book(barberId: barber.id, serviceId: service.id, start: start);
    expect(a.payment, PaymentStatus.unpaid);
    expect(a.outstanding, 0); // non ancora svolto

    // il cliente non puo' segnarsi come pagato
    await expectLater(
      () => backend.updateVisit(a.id, arrivedAt: DateTime.now(), payment: PaymentStatus.paid, amountPaid: a.price),
      throwsA(isA<AppException>()),
    );

    await backend.signOut();
    await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
    final arrived = DateTime.now();
    await backend.updateVisit(a.id, arrivedAt: arrived, payment: PaymentStatus.deposit, amountPaid: 5);
    final day = dayOnly(start);
    var saved = (await backend.appointmentsBetween(day, day.add(const Duration(days: 1)))).firstWhere((x) => x.id == a.id);
    expect(saved.arrivedAt, arrived);
    expect(saved.collected, 5);
    expect(saved.outstanding, service.price - 5);

    await backend.updateVisit(a.id, arrivedAt: arrived, payment: PaymentStatus.paid, amountPaid: service.price);
    saved = (await backend.appointmentsBetween(day, day.add(const Duration(days: 1)))).firstWhere((x) => x.id == a.id);
    expect(saved.outstanding, 0);
  });

  test('amministratori: email aggiunta diventa admin', () async {
    await signUp('socio@test.it');
    await backend.signOut();
    await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
    await backend.addAdminEmail(' Socio@Test.it ');
    expect(await backend.adminEmails(), contains('socio@test.it'));
    await backend.signOut();
    await backend.signInWithEmail('socio@test.it', 'segreta1');
    expect((await backend.fetchProfile())!.isAdmin, isTrue);
  });
}
