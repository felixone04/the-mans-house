import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:the_mans_house/data/demo_backend.dart';
import 'package:the_mans_house/data/slots.dart';
import 'package:the_mans_house/models.dart';
import 'package:the_mans_house/screens/admin/agenda_tab.dart';
import 'package:the_mans_house/screens/admin/barber_day_screen.dart';
import 'package:the_mans_house/state/app_state.dart';
import 'package:the_mans_house/theme.dart';

/// Agenda da telefono: un riquadro per barbiere e la giornata del barbiere
/// (arrivato, completato, pagamento, blocco orari).
void main() {
  setUpAll(() async {
    googleFontsEnabled = false;
    await initializeDateFormatting('it_IT');
    Intl.defaultLocale = 'it_IT';
  });

  // prossimo martedi': in demo lavorano tutti i barbieri
  DateTime nextTuesday() {
    var d = dayOnly(DateTime.now()).add(const Duration(days: 1));
    while (d.weekday != DateTime.tuesday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  Future<(AppState, DemoBackend)> pumpPage(WidgetTester tester, Widget Function(AppState) page) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = DemoBackend();
    final state = AppState(backend);
    await tester.runAsync(() async {
      await backend.init();
      await backend.signInWithEmail(DemoBackend.adminEmail, DemoBackend.adminPassword);
      await state.load();
    });
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          locale: const Locale('it', 'IT'),
          supportedLocales: const [Locale('it', 'IT')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: page(state)),
        ),
      ),
    );
    await settle(tester);
    return (state, backend);
  }

  Future<(AppState, DemoBackend)> pumpAgenda(WidgetTester tester) =>
      pumpPage(tester, (_) => AgendaTab(initialDay: nextTuesday()));

  Future<(AppState, DemoBackend)> pumpBarberDay(WidgetTester tester) =>
      pumpPage(tester, (s) => BarberDayScreen(barber: s.barbers.first, day: nextTuesday()));

  Future<Appointment> firstOfDay(WidgetTester tester, DemoBackend backend, String barberId) async {
    final day = nextTuesday();
    final list = await tester.runAsync(() => backend.appointmentsBetween(day, day.add(const Duration(days: 1))));
    return list!.where((a) => a.barberId == barberId).first;
  }

  testWidgets('agenda: un riquadro per barbiere, toccandolo si apre la sua giornata', (tester) async {
    final (state, _) = await pumpAgenda(tester);
    expect(tester.takeException(), isNull);
    for (final b in state.barbers) {
      expect(find.text(b.name), findsOneWidget);
    }
    // solo i nomi: nessun dettaglio prima di aprire il barbiere
    expect(find.textContaining('appuntament'), findsNothing);
    expect(find.textContaining('€'), findsNothing);

    await tester.tap(find.text(state.barbers.first.name));
    await settle(tester);
    expect(find.byType(BarberDayScreen), findsOneWidget);
    expect(find.textContaining('incassati'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('giornata del barbiere: arrivato, completato e acconto', (tester) async {
    final (state, backend) = await pumpBarberDay(tester);
    final barber = state.barbers.first;
    // nessuno ancora arrivato: schede rosse "DA ARRIVARE"
    expect(find.text('DA ARRIVARE'), findsWidgets);

    // niente "Arrivato": completato vuol dire arrivato
    expect(find.textContaining('Arrivato'), findsNothing);
    var a = await firstOfDay(tester, backend, barber.id);
    // toccando la scheda si apre il dettaglio con le altre azioni
    await tester.tap(find.text(a.customerName).first);
    await settle(tester);
    expect(find.text('Sposta appuntamento'), findsOneWidget);
    expect(find.textContaining('arrivato'), findsNothing);
    await tester.tapAt(const Offset(10, 10)); // chiude il dettaglio
    await settle(tester);

    await tester.tap(find.text('Completato?').first);
    await settle(tester);
    a = await firstOfDay(tester, backend, barber.id);
    expect(a.status, AppointmentStatus.completed);
    expect(a.arrivedAt, isNotNull); // completato = arrivato
    expect(find.text('COMPLETATO'), findsOneWidget);

    // acconto di 5 euro: resta il resto
    await tester.tap(find.text('Pagato?').first);
    await settle(tester);
    await tester.tap(find.text('Acconto'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '5');
    await tester.tap(find.text('SALVA'));
    await settle(tester);
    a = await firstOfDay(tester, backend, barber.id);
    expect(a.payment, PaymentStatus.deposit);
    expect(a.amountPaid, 5);
    expect(a.outstanding, a.price - 5);
    expect(find.text('Resta ${fmtPriceForTest(a.price - 5)}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cliente che torna con un pagamento in sospeso: avviso, totale e saldo', (tester) async {
    final day = nextTuesday();
    // prepara un arretrato prima di aprire la giornata
    late final Appointment today;
    late final Appointment previous;
    final (state, backend) = await pumpPage(tester, (s) => const SizedBox());
    await tester.runAsync(() async {
      final first = state.barbers.first;
      final all = await backend.appointmentsBetween(
        day.subtract(const Duration(days: 10)),
        day.add(const Duration(days: 1)),
      );
      today = all.firstWhere(
        (a) =>
            a.barberId == first.id &&
            dayOnly(a.start) == day &&
            all.any((p) => p.customerName == a.customerName && p.start.isBefore(day)),
      );
      previous = all.lastWhere((p) => p.customerName == today.customerName && p.start.isBefore(day));
      await backend.setAppointmentStatus(previous.id, AppointmentStatus.completed);
      await backend.updateVisit(previous.id, arrivedAt: previous.start, payment: PaymentStatus.later, amountPaid: 0);
    });
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          locale: const Locale('it', 'IT'),
          supportedLocales: const [Locale('it', 'IT')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: BarberDayScreen(barber: state.barbers.first, day: day),
          ),
        ),
      ),
    );
    await settle(tester);

    final total = previous.price + today.price;
    final banner = find.text('Totale da pagare oggi: ${fmtPriceForTest(total)}');
    expect(banner, findsWidgets);
    expect(find.textContaining('Deve ancora ${fmtPriceForTest(previous.price)}'), findsWidgets);

    // pagando tutto si salda anche l'arretrato
    await tester.ensureVisible(banner.first);
    final card = find.ancestor(of: banner.first, matching: find.byType(Material)).first;
    await tester.tap(find.descendant(of: card, matching: find.text('Pagato?')));
    await settle(tester);
    expect(find.textContaining('Salda anche l\'arretrato'), findsOneWidget);
    await tester.tap(find.text('SALVA'));
    await settle(tester);

    final after = await tester.runAsync(
      () => backend.appointmentsBetween(day.subtract(const Duration(days: 10)), day.add(const Duration(days: 1))),
    );
    expect(after!.firstWhere((a) => a.id == previous.id).outstanding, 0);
    expect(after.firstWhere((a) => a.id == today.id).payment, PaymentStatus.paid);
    expect(find.textContaining('Deve ancora'), findsNothing);
  });

  testWidgets('giornata del barbiere: tenendo premuto uno spazio libero si blocca l\'orario', (tester) async {
    await pumpBarberDay(tester);
    final gap = find.textContaining('libero fino alle').first;
    await tester.ensureVisible(gap);
    await tester.longPress(gap);
    await settle(tester);
    expect(find.text('Blocca un orario'), findsOneWidget);

    await tester.tap(find.text('BLOCCA ORARIO'));
    await settle(tester);
    expect(find.text('Orario bloccato'), findsOneWidget);
    expect(find.textContaining('Pausa'), findsWidgets);
  });

  testWidgets('vista griglia su telefono: nessun errore di impaginazione', (tester) async {
    await pumpAgenda(tester);
    await tester.tap(find.byTooltip('Vista griglia'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Vista barbieri'), findsOneWidget);
    // filtro su un barbiere: resta una sola colonna
    await tester.tap(find.text('Antonio').first);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}

/// Come fmtPrice: "€ 10" per gli importi interi.
String fmtPriceForTest(double v) => '€ ${v.toStringAsFixed(0)}';

/// Fa avanzare il tempo finto (il backend demo risponde dopo 250 ms).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}
