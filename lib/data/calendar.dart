import '../models.dart';

/// Appuntamento da aggiungere al calendario del telefono o del computer.
class CalendarEvent {
  CalendarEvent({required this.title, required this.start, required this.end, this.location = '', this.details = ''});
  final String title;
  final DateTime start;
  final DateTime end;
  final String location;
  final String details;

  factory CalendarEvent.fromAppointment(Appointment a, {required String shopName, required String address}) =>
      CalendarEvent(
        title: '${a.serviceName} · $shopName',
        start: a.start,
        end: a.end,
        location: address,
        details: a.barberName.isEmpty ? 'Prenotato con l\'app' : 'Con ${a.barberName} · prenotato con l\'app',
      );

  static String _utc(DateTime d) {
    final u = d.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  static String _escape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll(';', r'\;').replaceAll(',', r'\,').replaceAll('\n', r'\n');

  /// Link "aggiungi evento" di Google Calendar.
  Uri get googleUrl => Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': '${_utc(start)}/${_utc(end)}',
    'location': location,
    'details': details,
  });

  /// File .ics (Calendario Apple, Outlook e gli altri), con promemoria un'ora prima.
  String toIcs({DateTime? now}) => [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//The Man\'s House//Prenotazioni//IT',
    'BEGIN:VEVENT',
    'UID:${_utc(start)}-${title.hashCode.abs()}@themanshouse',
    'DTSTAMP:${_utc(now ?? DateTime.now())}',
    'DTSTART:${_utc(start)}',
    'DTEND:${_utc(end)}',
    'SUMMARY:${_escape(title)}',
    if (location.isNotEmpty) 'LOCATION:${_escape(location)}',
    if (details.isNotEmpty) 'DESCRIPTION:${_escape(details)}',
    'BEGIN:VALARM',
    'TRIGGER:-PT1H',
    'ACTION:DISPLAY',
    'DESCRIPTION:${_escape(title)}',
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}
