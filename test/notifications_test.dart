import 'package:flutter_test/flutter_test.dart';
import 'package:the_mans_house/models.dart';
import 'package:the_mans_house/notifications.dart';

void main() {
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

  test('ogni tipo ha testi e un segnaposto valido', () {
    expect(notifTypes.map((t) => t.kind).toSet().length, NotifKind.values.length);
    for (final t in notifTypes) {
      for (final m in RegExp(r'\{(\w+)\}').allMatches('${t.title} ${t.body}')) {
        expect(t.placeholders, contains(m.group(1)), reason: '${t.label}: {${m.group(1)}}');
      }
    }
  });
}
