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

  for (final h in barber.hoursOn(d)) {
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

/// Tutti gli orari di inizio possibili nella giornata (liberi e occupati),
/// dopo [now]: servono per mostrare anche gli orari gia' presi.
List<DateTime> candidateSlots({
  required Iterable<Barber> barbers,
  required int durationMin,
  required DateTime day,
  required int stepMin,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final d = dayOnly(day);
  final result = <DateTime>{};
  for (final b in barbers) {
    for (final h in b.hoursOn(d)) {
      for (var m = h.start; m + durationMin <= h.end; m += stepMin) {
        final start = DateTime(d.year, d.month, d.day, 0, m);
        if (start.isAfter(current)) result.add(start);
      }
    }
  }
  return result.toList()..sort();
}

/// Minuti di lavoro (solo appuntamenti: ferie e permessi non contano) di un
/// barbiere in un intervallo.
int busyMinutes(String barberId, List<BusyInterval> busy, DateTime from, DateTime to) {
  var total = 0;
  for (final b in busy) {
    if (b.timeOff || b.barberId != barberId || !b.start.isBefore(to) || !b.end.isAfter(from)) continue;
    final s = b.start.isBefore(from) ? from : b.start;
    final e = b.end.isAfter(to) ? to : b.end;
    total += e.difference(s).inMinutes;
  }
  return total;
}

/// Penalita' (in minuti) per chi ha lavorato nella mezz'ora precedente:
/// a parita' di carico si preferisce chi e' appena stato libero.
const previousHalfHourPenalty = 30;

/// Orari liberi per "qualsiasi barbiere": per ogni orario sceglie, tra i
/// barbieri liberi, chi ha meno lavoro quel giorno, penalizzando chi era
/// impegnato nella mezz'ora prima. A parita' vale l'ordine dei barbieri.
Map<DateTime, Barber> availableSlotsAnyBarber({
  required List<Barber> barbers,
  required int durationMin,
  required DateTime day,
  required List<BusyInterval> busy,
  required int stepMin,
  DateTime? now, // per i test: altrimenti l'ora corrente
}) {
  final d = dayOnly(day);
  final nextDay = DateTime(d.year, d.month, d.day + 1);
  final dayLoad = {for (final b in barbers) b.id: busyMinutes(b.id, busy, d, nextDay)};

  final candidates = <DateTime, List<Barber>>{};
  for (final b in barbers) {
    for (final s in availableSlots(
      barber: b,
      durationMin: durationMin,
      day: d,
      busy: busy,
      stepMin: stepMin,
      now: now,
    )) {
      candidates.putIfAbsent(s, () => []).add(b);
    }
  }

  int score(Barber b, DateTime slot) {
    final before = busyMinutes(b.id, busy, slot.subtract(const Duration(minutes: 30)), slot);
    return dayLoad[b.id]! + (before > 0 ? previousHalfHourPenalty : 0);
  }

  final keys = candidates.keys.toList()..sort();
  return {for (final k in keys) k: candidates[k]!.reduce((best, b) => score(b, k) < score(best, k) ? b : best)};
}

/// Orari del negozio in un giorno (unione delle fasce di tutti i barbieri).
List<List<int>> shopHoursFor(List<Barber> barbers, int weekday) =>
    _merge(barbers.expand((b) => b.hoursFor(weekday)));

/// Come [shopHoursFor] ma per una data precisa: conta chiusure e orari speciali.
List<List<int>> shopHoursOn(List<Barber> barbers, DateTime day) => _merge(barbers.expand((b) => b.hoursOn(day)));

/// Stato del negozio per la home: (aperto adesso?, testo breve).
(bool, String) shopStatus(List<Barber> barbers, DateTime now) {
  final today = dayOnly(now);
  final m = now.hour * 60 + now.minute;
  for (final r in shopHoursOn(barbers, today)) {
    if (m >= r[0] && m < r[1]) return (true, 'Aperto · chiude alle ${formatTime(r[1])}');
    if (m < r[0]) return (false, 'Chiuso · apre alle ${formatTime(r[0])}');
  }
  for (var i = 1; i <= 14; i++) {
    final d = DateTime(today.year, today.month, today.day + i);
    final hours = shopHoursOn(barbers, d);
    if (hours.isEmpty) continue;
    const names = ['lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato', 'domenica'];
    final when = i == 1 ? 'domani' : names[d.weekday - 1];
    return (false, 'Chiuso · apre $when alle ${formatTime(hours.first[0])}');
  }
  return (false, 'Chiuso');
}

List<List<int>> _merge(Iterable<WorkingHours> hours) {
  final ranges = hours.map((h) => [h.start, h.end]).toList()..sort((a, b) => a[0].compareTo(b[0]));
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
