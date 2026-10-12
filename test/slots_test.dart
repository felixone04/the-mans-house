import 'package:flutter_test/flutter_test.dart';
import 'package:the_mans_house/data/slots.dart';
import 'package:the_mans_house/models.dart';

void main() {
  // Martedi' 13 ottobre 2026
  final day = DateTime(2026, 10, 13);
  final before = DateTime(2026, 10, 12, 8);

  Barber barber(String id) => Barber(
    id: id,
    name: id,
    hours: [
      WorkingHours(weekday: 2, start: 9 * 60, end: 13 * 60),
      WorkingHours(weekday: 2, start: 15 * 60, end: 16 * 60),
    ],
  );

  test('genera gli orari dentro le fasce di lavoro', () {
    final s = availableSlots(barber: barber('a'), durationMin: 30, day: day, busy: [], stepMin: 30, now: before);
    expect(s.first, DateTime(2026, 10, 13, 9));
    expect(s.last, DateTime(2026, 10, 13, 15, 30));
    expect(s.length, 8 + 2);
  });

  test('esclude gli orari sovrapposti ad appuntamenti e ferie', () {
    final busy = [
      BusyInterval('a', DateTime(2026, 10, 13, 10), DateTime(2026, 10, 13, 10, 40)),
      BusyInterval('b', DateTime(2026, 10, 13, 9), DateTime(2026, 10, 13, 13)),
    ];
    final s = availableSlots(barber: barber('a'), durationMin: 30, day: day, busy: busy, stepMin: 15, now: before);
    expect(s.contains(DateTime(2026, 10, 13, 9, 30)), isTrue);
    expect(s.contains(DateTime(2026, 10, 13, 9, 45)), isFalse); // finirebbe alle 10:15
    expect(s.contains(DateTime(2026, 10, 13, 10, 30)), isFalse);
    expect(s.contains(DateTime(2026, 10, 13, 10, 45)), isTrue);
  });

  test('il servizio deve finire entro la fascia', () {
    final s = availableSlots(barber: barber('a'), durationMin: 50, day: day, busy: [], stepMin: 15, now: before);
    expect(s.contains(DateTime(2026, 10, 13, 12, 15)), isFalse);
    expect(s.contains(DateTime(2026, 10, 13, 12, 10)), isFalse);
    expect(s.last, DateTime(2026, 10, 13, 15));
  });

  test('nessun orario nel passato o nei giorni di chiusura', () {
    final now = DateTime(2026, 10, 13, 11, 5);
    final s = availableSlots(barber: barber('a'), durationMin: 30, day: day, busy: [], stepMin: 30, now: now);
    expect(s.first, DateTime(2026, 10, 13, 11, 30));
    final sunday = availableSlots(
      barber: barber('a'),
      durationMin: 30,
      day: DateTime(2026, 10, 18),
      busy: [],
      stepMin: 30,
      now: before,
    );
    expect(sunday, isEmpty);
  });

  test('primo disponibile assegna il barbiere libero', () {
    final busy = [BusyInterval('a', DateTime(2026, 10, 13, 9), DateTime(2026, 10, 13, 13))];
    final map = availableSlotsAnyBarber(
      barbers: [barber('a'), barber('b')],
      durationMin: 30,
      day: day,
      busy: busy,
      stepMin: 30,
      now: before,
    );
    expect(map[DateTime(2026, 10, 13, 9)]!.id, 'b');
  });

  test('ferie di uno o piu giorni escludono tutti gli orari', () {
    // ferie salvate come nell'app: da mezzanotte a mezzanotte del giorno dopo
    final busy = [BusyInterval('a', DateTime(2026, 10, 12), DateTime(2026, 10, 14))];
    final s = availableSlots(barber: barber('a'), durationMin: 30, day: day, busy: busy, stepMin: 15, now: before);
    expect(s, isEmpty);
    final next = availableSlots(
      barber: barber('a'),
      durationMin: 30,
      day: DateTime(2026, 10, 20),
      busy: busy,
      stepMin: 15,
      now: before,
    ); // martedi' successivo
    expect(next.first, DateTime(2026, 10, 20, 9));
  });

  test('ferie parziali (permesso di qualche ora)', () {
    final busy = [BusyInterval('a', DateTime(2026, 10, 13, 11), DateTime(2026, 10, 13, 16))];
    final s = availableSlots(barber: barber('a'), durationMin: 30, day: day, busy: busy, stepMin: 30, now: before);
    expect(s, [
      DateTime(2026, 10, 13, 9),
      DateTime(2026, 10, 13, 9, 30),
      DateTime(2026, 10, 13, 10),
      DateTime(2026, 10, 13, 10, 30),
    ]);
  });

  test('appuntamenti adiacenti non si sovrappongono', () {
    final busy = [BusyInterval('a', DateTime(2026, 10, 13, 9, 30), DateTime(2026, 10, 13, 10))];
    final s = availableSlots(barber: barber('a'), durationMin: 30, day: day, busy: busy, stepMin: 30, now: before);
    expect(s.contains(DateTime(2026, 10, 13, 9)), isTrue);
    expect(s.contains(DateTime(2026, 10, 13, 9, 30)), isFalse);
    expect(s.contains(DateTime(2026, 10, 13, 10)), isTrue);
  });

  test('primo disponibile: nessun orario se tutti occupati, barbiere in ferie escluso', () {
    final busy = [
      BusyInterval('a', DateTime(2026, 10, 13), DateTime(2026, 10, 14)), // ferie
      BusyInterval('b', DateTime(2026, 10, 13, 9), DateTime(2026, 10, 13, 9, 30)),
    ];
    final map = availableSlotsAnyBarber(
      barbers: [barber('a'), barber('b')],
      durationMin: 30,
      day: day,
      busy: busy,
      stepMin: 30,
      now: before,
    );
    expect(map.containsKey(DateTime(2026, 10, 13, 9)), isFalse);
    expect(map.values.every((b) => b.id == 'b'), isTrue);
    expect(map.keys.first, DateTime(2026, 10, 13, 9, 30));

    final all = [...busy, BusyInterval('b', DateTime(2026, 10, 13), DateTime(2026, 10, 14))];
    expect(
      availableSlotsAnyBarber(
        barbers: [barber('a'), barber('b')],
        durationMin: 30,
        day: day,
        busy: all,
        stepMin: 30,
        now: before,
      ),
      isEmpty,
    );
  });

  test('primo disponibile: preferisce il barbiere meno impegnato e rispetta il passato', () {
    final busy = [
      BusyInterval('a', DateTime(2026, 10, 13, 15), DateTime(2026, 10, 13, 15, 30)),
      BusyInterval('a', DateTime(2026, 10, 13, 15, 30), DateTime(2026, 10, 13, 16)),
    ];
    final now = DateTime(2026, 10, 13, 10, 10);
    final map = availableSlotsAnyBarber(
      barbers: [barber('a'), barber('b')],
      durationMin: 30,
      day: day,
      busy: busy,
      stepMin: 30,
      now: now,
    );
    expect(map.keys.first, DateTime(2026, 10, 13, 10, 30));
    expect(map[DateTime(2026, 10, 13, 10, 30)]!.id, 'b');
    expect(map[DateTime(2026, 10, 13, 15)]!.id, 'b');
  });

  test('primo disponibile: a parita\' di carico sceglie chi era libero nella mezz\'ora prima', () {
    // entrambi 30 minuti di lavoro: a alle 10:00, b alle 11:30
    final busy = [
      BusyInterval('a', DateTime(2026, 10, 13, 10), DateTime(2026, 10, 13, 10, 30)),
      BusyInterval('b', DateTime(2026, 10, 13, 11, 30), DateTime(2026, 10, 13, 12)),
    ];
    final map = availableSlotsAnyBarber(
      barbers: [barber('a'), barber('b')],
      durationMin: 30,
      day: day,
      busy: busy,
      stepMin: 30,
      now: before,
    );
    expect(map[DateTime(2026, 10, 13, 10, 30)]!.id, 'b'); // a ha appena lavorato
    expect(map[DateTime(2026, 10, 13, 12)]!.id, 'a'); // b ha appena lavorato
    expect(map[DateTime(2026, 10, 13, 9)]!.id, 'a'); // parita' piena: ordine dei barbieri
  });

  test('primo disponibile: il carico conta in minuti, non in numero di appuntamenti', () {
    final busy = [
      BusyInterval('a', DateTime(2026, 10, 13, 9), DateTime(2026, 10, 13, 9, 20)),
      BusyInterval('a', DateTime(2026, 10, 13, 9, 20), DateTime(2026, 10, 13, 9, 40)),
      BusyInterval('b', DateTime(2026, 10, 13, 15), DateTime(2026, 10, 13, 16)),
    ];
    final map = availableSlotsAnyBarber(
      barbers: [barber('a'), barber('b')],
      durationMin: 30,
      day: day,
      busy: busy,
      stepMin: 30,
      now: before,
    );
    expect(map[DateTime(2026, 10, 13, 12)]!.id, 'a'); // 40 min contro 60
  });

  test('primo disponibile: ferie e permessi non contano come lavoro', () {
    // a: permesso 9-11 (nessun appuntamento); b: 60 minuti di appuntamenti
    final busy = [
      BusyInterval('a', DateTime(2026, 10, 13, 9), DateTime(2026, 10, 13, 11), timeOff: true),
      BusyInterval('b', DateTime(2026, 10, 13, 9, 30), DateTime(2026, 10, 13, 10, 30)),
    ];
    final map = availableSlotsAnyBarber(
      barbers: [barber('a'), barber('b')],
      durationMin: 30,
      day: day,
      busy: busy,
      stepMin: 30,
      now: before,
    );
    expect(map[DateTime(2026, 10, 13, 9)]!.id, 'b'); // a e' in permesso
    expect(map[DateTime(2026, 10, 13, 11)]!.id, 'a'); // rientro dal permesso: nessuna penalita'
    expect(map[DateTime(2026, 10, 13, 15)]!.id, 'a'); // 0 minuti di lavoro contro 60
  });

  test('primo disponibile: penalita\' della mezz\'ora precedente contro carico', () {
    // a: 30 min alle 10:00 -> alle 10:30 punteggio 30+30=60; b: 50 min in mattinata
    final busy = [
      BusyInterval('a', DateTime(2026, 10, 13, 10), DateTime(2026, 10, 13, 10, 30)),
      BusyInterval('b', DateTime(2026, 10, 13, 11), DateTime(2026, 10, 13, 11, 50)),
    ];
    final map = availableSlotsAnyBarber(
      barbers: [barber('a'), barber('b')],
      durationMin: 30,
      day: day,
      busy: busy,
      stepMin: 30,
      now: before,
    );
    expect(map[DateTime(2026, 10, 13, 10, 30)]!.id, 'b'); // 50 < 60
    expect(map[DateTime(2026, 10, 13, 12)]!.id, 'a'); // b ha appena finito: 30 < 80
    expect(map[DateTime(2026, 10, 13, 15)]!.id, 'a'); // 30 < 50
  });

  test('primo disponibile: ogni barbiere assegnato e\' davvero libero per tutta la durata', () {
    final busy = [
      BusyInterval('a', DateTime(2026, 10, 13, 9, 40), DateTime(2026, 10, 13, 10)),
      BusyInterval('b', DateTime(2026, 10, 13, 9, 15), DateTime(2026, 10, 13, 9, 30)),
    ];
    final barbers = [barber('a'), barber('b')];
    final map = availableSlotsAnyBarber(
      barbers: barbers,
      durationMin: 45,
      day: day,
      busy: busy,
      stepMin: 5,
      now: before,
    );
    expect(map, isNotEmpty);
    map.forEach((slot, b) {
      final free = availableSlots(barber: b, durationMin: 45, day: day, busy: busy, stepMin: 5, now: before);
      expect(free.contains(slot), isTrue, reason: '$slot assegnato a ${b.id}');
    });
    expect(map.containsKey(DateTime(2026, 10, 13, 9, 15)), isFalse); // a occupato alle 9:40, b alle 9:15
  });

  test('orari del negozio uniscono le fasce dei barbieri', () {
    final b2 = Barber(
      id: 'c',
      name: 'c',
      hours: [WorkingHours(weekday: 2, start: 12 * 60, end: 14 * 60)],
    );
    expect(shopHoursFor([barber('a'), b2], 2), [
      [9 * 60, 14 * 60],
      [15 * 60, 16 * 60],
    ]);
  });
}
