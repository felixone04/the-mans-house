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
    // senza informativa accettata il profilo resta da completare
    await backend.updateProfile(Profile(id: p.id, email: p.email, fullName: 'Cliente Google', phone: '3339998877'));
    expect((await backend.fetchProfile())!.isComplete, isFalse);
    await backend.updateProfile(
      Profile(
        id: p.id,
        email: p.email,
        fullName: 'Cliente Google',
        phone: '3339998877',
        privacyAcceptedAt: DateTime.now(),
      ),
    );
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
    var saved = (await backend.appointmentsBetween(
      day,
      day.add(const Duration(days: 1)),
    )).firstWhere((x) => x.id == a.id);
    expect(saved.arrivedAt, arrived);
    expect(saved.collected, 5);
    expect(saved.outstanding, service.price - 5);

    await backend.updateVisit(a.id, arrivedAt: arrived, payment: PaymentStatus.paid, amountPaid: service.price);
    saved = (await backend.appointmentsBetween(day, day.add(const Duration(days: 1)))).firstWhere((x) => x.id == a.id);
    expect(saved.outstanding, 0);
  });

  test('magazzino: giacenza solo admin, vendita col taglio o al banco, annullo', () async {
    // il cliente vede i prodotti ma non la giacenza
    await signUp('prodotti@test.it');
    final products = await backend.fetchProducts();
    expect(products, isNotEmpty);
    await expectLater(() => backend.fetchStock(), throwsA(isA<AppException>()));

    final barber = (await backend.fetchBarbers()).first;
    final service = (await backend.fetchServices()).first;
    final start = await freeSlot(barber, service, DateTime.now().add(const Duration(hours: 4)));
    final a = await backend.book(barberId: barber.id, serviceId: service.id, start: start);

    await backend.signOut();
    await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
    final p = products.first;
    await backend.adjustStock(p.id, 5 - (await backend.fetchStock())[p.id]!.stock);
    await backend.setStockThreshold(p.id, 2);

    // insieme al taglio: scende la giacenza e sale il conto
    await backend.sellProduct(p.id, 2, appointmentId: a.id);
    expect((await backend.fetchStock())[p.id]!.stock, 3);
    final day = dayOnly(start);
    Future<Appointment> saved() async =>
        (await backend.appointmentsBetween(day, day.add(const Duration(days: 1)))).firstWhere((x) => x.id == a.id);
    expect((await saved()).total, service.price + p.price * 2);
    final sales = await backend.appointmentSales(a.id);
    expect(sales.single.qty, 2);

    // al banco, senza appuntamento: sotto la soglia scatta l'avviso
    await backend.sellProduct(p.id, 1);
    expect((await backend.fetchStock())[p.id]!.low, isTrue);
    // non si vende piu' di quanto c'e'
    await expectLater(() => backend.sellProduct(p.id, 3), throwsA(isA<AppException>()));
    await expectLater(() => backend.adjustStock(p.id, -10), throwsA(isA<AppException>()));

    // annullo: torna in magazzino ed esce dal conto
    await backend.cancelSale(sales.single.id);
    expect((await backend.fetchStock())[p.id]!.stock, 4);
    expect((await saved()).total, service.price);
  });

  test('conferma presenza e voto: solo il cliente, voto dopo l\'appuntamento e una volta', () async {
    await signUp('voto@test.it');
    final barber = (await backend.fetchBarbers()).first;
    final service = (await backend.fetchServices()).first;
    final start = await freeSlot(barber, service, DateTime.now().add(const Duration(hours: 4)));
    final a = await backend.book(barberId: barber.id, serviceId: service.id, start: start);

    await backend.confirmAttendance(a.id);
    expect((await backend.myAppointments()).firstWhere((x) => x.id == a.id).attendanceConfirmedAt, isNotNull);
    // prima dell'appuntamento non si vota
    await expectLater(() => backend.submitReview(a.id, 5), throwsA(isA<AppException>()));

    // dopo il taglio (data spostata nel passato per la prova)
    final mine = (await backend.myAppointments()).firstWhere((x) => x.id == a.id)
      ..start = DateTime.now().subtract(const Duration(hours: 3))
      ..end = DateTime.now().subtract(const Duration(hours: 2))
      ..status = AppointmentStatus.completed;
    await backend.submitReview(mine.id, 2, comment: 'Attesa lunga');
    await expectLater(() => backend.submitReview(mine.id, 5), throwsA(isA<AppException>()));
    await expectLater(() => backend.fetchReviews(), throwsA(isA<AppException>())); // solo admin

    await backend.signOut();
    await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
    final reviews = await backend.fetchReviews();
    expect(reviews.first.reviewStars, 2);
    expect(reviews.first.reviewComment, 'Attesa lunga');
  });

  test('colore con posa: durante la posa il barbiere prende altri clienti', () async {
    await signUp('colore@test.it');
    final barber = (await backend.fetchBarbers()).first;
    final services = await backend.fetchServices();
    final colore = services.firstWhere((s) => s.hasPosa);
    final taglio = services.firstWhere((s) => s.name == 'Taglio');
    final start = await freeSlot(barber, colore, DateTime.now().add(const Duration(days: 1)));
    final c = await backend.book(barberId: barber.id, serviceId: colore.id, start: start);
    // il cliente vede il tempo totale
    expect(c.end.difference(c.start).inMinutes, colore.durationMin);
    // subito dopo il tempo iniziale lo stesso barbiere e' libero per un taglio
    final after = start.add(Duration(minutes: colore.busyMin!));
    final busy = await backend.fetchBusy(dayOnly(start), dayOnly(start).add(const Duration(days: 1)));
    final free = availableSlots(barber: barber, durationMin: taglio.durationMin, day: start, busy: busy, stepMin: 5);
    if (free.contains(after)) {
      final t = await backend.book(barberId: barber.id, serviceId: taglio.id, start: after);
      expect(t.barberId, barber.id);
    }
    // nel tempo iniziale invece no
    await expectLater(
      () => backend.book(barberId: barber.id, serviceId: taglio.id, start: start.add(const Duration(minutes: 10))),
      throwsA(isA<AppException>()),
    );
  });

  test('lista d\'attesa: solo numeri al cliente, posto assegnato al primo, extra accettato dall\'admin', () async {
    final barber = (await backend.fetchBarbers()).first;
    final service = (await backend.fetchServices()).first;
    final start = await freeSlot(barber, service, DateTime.now().add(const Duration(days: 1)));

    // Anna prende l'orario
    await signUp('anna@test.it');
    final taken = await backend.book(barberId: barber.id, serviceId: service.id, start: start);
    await backend.signOut();

    // Bruno e Carlo si mettono in lista per lo stesso barbiere e orario
    await signUp('bruno@test.it');
    await backend.joinWaitlist(serviceId: service.id, barberId: barber.id, start: start);
    await expectLater(
      () => backend.joinWaitlist(serviceId: service.id, barberId: barber.id, start: start),
      throwsA(isA<AppException>()), // gia' in lista
    );
    await backend.signOut();
    await signUp('carlo@test.it');
    await backend.joinWaitlist(serviceId: service.id, barberId: barber.id, start: start);
    expect((await backend.myWaitlist()).single.position, 2);
    // il cliente vede solo quanti sono, non chi
    final counts = await backend.waitlistCounts(dayOnly(start), dayOnly(start).add(const Duration(days: 1)));
    expect(waitingFor(counts, start, barber.id), 2);
    // nessuna lista per un orario libero: si prenota e basta
    final free = await freeSlot(barber, service, start.add(const Duration(hours: 1)));
    await expectLater(
      () => backend.joinWaitlist(serviceId: service.id, barberId: barber.id, start: free),
      throwsA(isA<AppException>()),
    );
    // i nomi in lista li vede solo l'admin
    await expectLater(() => backend.fetchWaitlist(dayOnly(start), start.add(const Duration(days: 1))),
        throwsA(isA<AppException>()));
    await backend.signOut();

    // Anna annulla: il posto va da solo a Bruno, il primo in lista
    await backend.signInWithEmail('anna@test.it', 'segreta1');
    await backend.cancelAppointment(taken.id);
    await backend.signOut();
    await backend.signInWithEmail('bruno@test.it', 'segreta1');
    expect((await backend.myAppointments()).where((a) => a.isUpcoming).single.start, start);
    expect((await backend.myWaitlist()).single.status, WaitlistStatus.assigned);
    await backend.signOut();

    // Carlo ora e' il primo; l'admin lo accetta comunque, come extra
    await backend.signInWithEmail('carlo@test.it', 'segreta1');
    expect((await backend.myWaitlist()).single.position, 1);
    await backend.signOut();
    await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
    Future<List<WaitlistEntry>> atStart() async =>
        (await backend.fetchWaitlist(dayOnly(start), dayOnly(start).add(const Duration(days: 1))))
            .where((w) => w.start == start)
            .toList();
    final waiting = await atStart();
    expect(waiting.single.customerName, 'Mario Rossi');
    final extra = await backend.acceptWaitlist(waiting.single.id);
    expect(extra.extra, isTrue);
    expect(extra.barberId, barber.id);
    expect(extra.start, start);
    expect(await atStart(), isEmpty);
  });

  test('chiusura del negozio: niente prenotazioni quel giorno, orario speciale solo in fascia', () async {
    await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
    final barber = (await backend.fetchBarbers()).first;
    final service = (await backend.fetchServices()).first;
    final slot = await freeSlot(barber, service, DateTime.now().add(const Duration(days: 1)));
    final day = dayOnly(slot);

    await backend.saveShopDays([ShopDay(day: day, note: 'Ferie')]);
    await expectLater(
      () => backend.book(barberId: barber.id, serviceId: service.id, start: slot, customerName: 'X'),
      throwsA(isA<AppException>()),
    );
    expect((await backend.fetchShopDays()).single.note, 'Ferie');

    // orario speciale 7-8 (prima dell'apertura abituale, quindi libero) solo per
    // questo barbiere: dentro si', fuori no
    await backend.saveShopDays([
      ShopDay(day: day, open: 420, close: 480, barberIds: [barber.id]),
    ]);
    final inside = DateTime(day.year, day.month, day.day, 7);
    final outside = DateTime(day.year, day.month, day.day, 15, 30);
    final ok = await backend.book(barberId: barber.id, serviceId: service.id, start: inside, customerName: 'Y');
    expect(ok.start, inside);
    await expectLater(
      () => backend.book(barberId: barber.id, serviceId: service.id, start: outside, customerName: 'Z'),
      throwsA(isA<AppException>()),
    );

    await backend.deleteShopDay(day);
    expect(await backend.fetchShopDays(), isEmpty);
    ShopCalendar.set(const []);
  });

  test('consensi: registrazione con offerte, cliente dal banco segnato in negozio', () async {
    await backend.signUpWithEmail(
      email: 'offerte@test.it',
      password: 'segreta1',
      fullName: 'Paolo Offerte',
      phone: '3331112222',
      marketingOptIn: true,
    );
    final p = (await backend.fetchProfile())!;
    expect(p.privacyAcceptedAt, isNotNull);
    expect(p.marketingOptIn, isTrue);

    await backend.signOut();
    await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
    var customers = await backend.customers();
    expect(customers.firstWhere((c) => c.email == 'offerte@test.it').marketingOptIn, isTrue);
    final walkIn = customers.firstWhere((c) => c.isWalkIn && !c.marketingOptIn);
    await backend.setWalkInConsent(walkIn.fullName, marketing: true);
    customers = await backend.customers();
    expect(customers.firstWhere((c) => c.id == walkIn.id).marketingOptIn, isTrue);
  });

  test('ospite: prenota senza account, poi crea l\'account e tiene gli appuntamenti', () async {
    await backend.signInAsGuest(fullName: 'Gino Ospite', phone: '333 4445566', email: 'gino@test.it');
    expect(backend.isGuest, isTrue);
    final p = (await backend.fetchProfile())!;
    expect(p.isComplete, isTrue); // nome, telefono e privacy: puo' prenotare subito
    final barber = (await backend.fetchBarbers()).first;
    final service = (await backend.fetchServices()).first;
    final start = await freeSlot(barber, service, DateTime.now().add(const Duration(hours: 3)));
    final a = await backend.book(barberId: barber.id, serviceId: service.id, start: start);
    expect(a.customerName, 'Gino Ospite');
    expect(a.customerEmail, 'gino@test.it');

    expect(await backend.upgradeGuest(email: 'gino@test.it', password: 'segreta1'), isTrue);
    expect(backend.isGuest, isFalse);
    expect((await backend.myAppointments()).any((x) => x.id == a.id), isTrue);
    // ora entra con email e password
    await backend.signOut();
    await backend.signInWithEmail('gino@test.it', 'segreta1');
    expect((await backend.myAppointments()).any((x) => x.id == a.id), isTrue);
  });

  test('admin: prenota per un cliente con account, per un nuovo cliente e senza dati', () async {
    await signUp('cliente.app@test.it');
    final client = (await backend.fetchProfile())!;
    await backend.signOut();
    await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
    final barber = (await backend.fetchBarbers()).first;
    final service = (await backend.fetchServices()).first;

    // cliente con account: l'appuntamento compare nella sua app
    final s1 = await freeSlot(barber, service, DateTime.now().add(const Duration(hours: 3)));
    final forUser = await backend.book(
      barberId: barber.id,
      serviceId: service.id,
      start: s1,
      customerUserId: client.id,
    );
    expect(forUser.userId, client.id);
    expect(forUser.customerName, 'Mario Rossi');

    // nuovo cliente dal banco con email
    final s2 = await freeSlot(barber, service, forUser.end);
    final walkIn = await backend.book(
      barberId: barber.id,
      serviceId: service.id,
      start: s2,
      customerName: 'Nuovo Cliente',
      customerPhone: '3337778899',
      customerEmail: 'nuovo@test.it',
    );
    expect((walkIn.userId, walkIn.customerPhone, walkIn.customerEmail), (null, '+393337778899', 'nuovo@test.it'));

    // senza dati
    final s3 = await freeSlot(barber, service, walkIn.end);
    final quick = await backend.book(barberId: barber.id, serviceId: service.id, start: s3, customerName: 'Cliente');
    expect((quick.userId, quick.customerName, quick.customerPhone), (null, 'Cliente', ''));

    await backend.signOut();
    await backend.signInWithEmail('cliente.app@test.it', 'segreta1');
    expect((await backend.myAppointments()).any((x) => x.id == forUser.id), isTrue);
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
