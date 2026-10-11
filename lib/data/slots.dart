import '../models.dart';

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calcola gli orari liberi di un barbiere in un giorno.
List<DateTime> availableSlots({
  required Barber barber,
  required int durationMin,
  required DateTime day,
  required List<BusyInterval> busy,
  required int stepMin,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final d = dayOnly(day);
  final mine = busy.where((b) => b.barberId == barber.id).toList();
  final result = <DateTime>[];

  for (final h in barber.hoursFor(d.weekday)) {
    for (var m = h.start; m + durationMin <= h.end; m += stepMin) {
      final start = DateTime(d.year, d.month, d.day, 0, m);
      final end = start.add(Duration(minutes: durationMin));
      if (!start.isAfter(current)) continue;
      final overlaps = mine.any((b) => b.start.isBefore(end) && b.end.isAfter(start));
      if (!overlaps) result.add(start);
    }
  }
  result.sort();
  return result;
}

/// Orari liberi per "qualsiasi barbiere": a ogni orario associa il barbiere
/// meno impegnato quel giorno.
Map<DateTime, Barber> availableSlotsAnyBarber({
  required List<Barber> barbers,
  required int durationMin,
  required DateTime day,
  required List<BusyInterval> busy,
  required int stepMin,
  DateTime? now, // per i test: altrimenti l'ora corrente
}) {
  final d = dayOnly(day);
  final load = <String, int>{
    for (final b in barbers)
      b.id: busy.where((x) => x.barberId == b.id && dayOnly(x.start) == d).length,
  };
  final ordered = [...barbers]..sort((a, b) => load[a.id]!.compareTo(load[b.id]!));
  final map = <DateTime, Barber>{};
  for (final b in ordered) {
    for (final s in availableSlots(
        barber: b, durationMin: durationMin, day: d, busy: busy, stepMin: stepMin, now: now)) {
      map.putIfAbsent(s, () => b);
    }
  }
  final keys = map.keys.toList()..sort();
  return {for (final k in keys) k: map[k]!};
}

/// Orari del negozio in un giorno (unione delle fasce di tutti i barbieri).
List<List<int>> shopHoursFor(List<Barber> barbers, int weekday) {
  final ranges = barbers
      .expand((b) => b.hoursFor(weekday))
      .map((h) => [h.start, h.end])
      .toList()
    ..sort((a, b) => a[0].compareTo(b[0]));
  final merged = <List<int>>[];
  for (final r in ranges) {
    if (merged.isNotEmpty && r[0] <= merged.last[1]) {
      if (r[1] > merged.last[1]) merged.last[1] = r[1];
    } else {
      merged.add([r[0], r[1]]);
    }
  }
  return merged;
}

