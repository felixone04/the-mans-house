import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../models.dart';

/// File CSV per Excel (impostazioni italiane): separatore ";", virgola per i
/// decimali e BOM UTF-8 perche' Excel legga correttamente gli accenti.
class CsvFile {
  CsvFile(this.name, this.rows);
  final String name;
  final List<List<Object?>> rows;

  static String _cell(Object? v) {
    final s = switch (v) {
      null => '',
      double d => d.toStringAsFixed(2).replaceAll('.', ','),
      DateTime d => DateFormat('dd/MM/yyyy').format(d),
      _ => v.toString(),
    };
    return s.contains(RegExp(r'[;"\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  String get text => rows.map((r) => r.map(_cell).join(';')).join('\r\n');

  Uint8List get bytes => Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
}

String _payment(Appointment a) => switch (a.payment) {
  PaymentStatus.paid => 'Pagato',
  PaymentStatus.later => 'Paga dopo',
  PaymentStatus.deposit => 'Acconto',
  PaymentStatus.unpaid => 'Non pagato',
};

/// Appuntamenti di un periodo con incassi, piu' i totali (generale e per barbiere).
CsvFile revenueCsv(String name, List<Appointment> appointments) {
  final list = appointments.where((a) => a.status != AppointmentStatus.cancelled).toList()
    ..sort((x, y) => x.start.compareTo(y.start));
  final time = DateFormat('HH:mm');
  final rows = <List<Object?>>[
    [
      'Data',
      'Ora',
      'Barbiere',
      'Cliente',
      'Telefono',
      'Servizio',
      'Prezzo',
      'Stato',
      'Pagamento',
      'Incassato',
      'Da incassare',
    ],
    for (final a in list)
      [
        a.start,
        time.format(a.start),
        a.barberName,
        a.customerName,
        a.customerPhone,
        a.serviceName,
        a.price,
        statusLabel(a.status),
        _payment(a),
        a.collected,
        a.outstanding,
      ],
  ];

  double sum(Iterable<Appointment> xs, double Function(Appointment) f) => xs.fold(0, (s, a) => s + f(a));
  final done = list.where((a) => a.status == AppointmentStatus.completed);
  rows
    ..add([])
    ..add([
      'Totale',
      '',
      '',
      '',
      '',
      '',
      sum(done, (a) => a.price),
      '',
      '',
      sum(list, (a) => a.collected),
      sum(list, (a) => a.outstanding),
    ]);
  final barbers = {for (final a in list) a.barberName}.toList()..sort();
  for (final b in barbers) {
    final mine = list.where((a) => a.barberName == b);
    rows.add([
      'Totale $b',
      '',
      b,
      '',
      '',
      '',
      sum(mine.where((a) => a.status == AppointmentStatus.completed), (a) => a.price),
      '',
      '',
      sum(mine, (a) => a.collected),
      sum(mine, (a) => a.outstanding),
    ]);
  }
  return CsvFile(name, rows);
}

/// Elenco clienti con visite e importi ancora da incassare.
CsvFile customersCsv(String name, List<CustomerSummary> customers, List<Appointment> appointments) {
  String keyOf(Appointment a) => a.userId ?? '${CustomerSummary.walkInPrefix}${a.customerName}';
  final owed = <String, double>{};
  final noShows = <String, int>{};
  for (final a in appointments.where((a) => a.status != AppointmentStatus.cancelled)) {
    owed[keyOf(a)] = (owed[keyOf(a)] ?? 0) + a.outstanding;
    if (a.status == AppointmentStatus.noShow) noShows[keyOf(a)] = (noShows[keyOf(a)] ?? 0) + 1;
  }
  return CsvFile(name, [
    ['Nome', 'Telefono', 'Email', 'Tipo', 'Prenotazioni', 'Ultima visita', 'Non presentato', 'Da incassare'],
    for (final c in customers)
      [
        c.fullName,
        c.phone,
        c.email,
        c.isWalkIn ? 'Dal banco' : 'Con app',
        c.bookings,
        c.lastVisit,
        noShows[c.id] ?? 0,
        owed[c.id] ?? 0.0,
      ],
  ]);
}
