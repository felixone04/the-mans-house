import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:the_mans_house/data/demo_backend.dart';
import 'package:the_mans_house/data/slots.dart';
import 'package:the_mans_house/models.dart';
import 'package:the_mans_house/screens/admin/agenda_tab.dart';
import 'package:the_mans_house/state/app_state.dart';
import 'package:the_mans_house/theme.dart';

/// Agenda da telefono: elenco, azioni rapide con lo scorrimento e blocco orari.
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

  Future<(AppState, DemoBackend)> pumpAgenda(WidgetTester tester) async {
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
          home: Scaffold(body: AgendaTab(initialDay: nextTuesday())),
        ),
      ),
    );
    await settle(tester);
    return (state, backend);
  }

  testWidgets('scorrendo a destra l\'appuntamento diventa completato', (tester) async {
    final (_, backend) = await pumpAgenda(tester);
    expect(find.textContaining('Libero fino alle'), findsWidgets);
    // solo le righe degli appuntamenti (anche il messaggio in basso e' un Dismissible)
    final swipeable = find.byWidgetPredicate(
      (w) => w is Dismissible && w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('swipe-'),
    );
    final before = swipeable.evaluate().length;
    expect(before, greaterThan(0));

    await tester.drag(swipeable.first, const Offset(300, 0));
    await settle(tester);

    expect(find.textContaining(': completato'), findsOneWidget); // messaggio con "Annulla"
    expect(find.text('Annulla'), findsOneWidget);
    expect(swipeable.evaluate().length, before - 1);
    final day = nextTuesday();
    final items = await tester.runAsync(() => backend.appointmentsBetween(day, day.add(const Duration(days: 1))));
    expect(items!.where((a) => a.status == AppointmentStatus.completed), isNotEmpty);
  });

  testWidgets('vista griglia su telefono: nessun errore di impaginazione', (tester) async {
    await pumpAgenda(tester);
    await tester.tap(find.byTooltip('Vista griglia'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Vista elenco'), findsOneWidget);
    // filtro su un barbiere: resta una sola colonna
    await tester.tap(find.text('Antonio').first);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tenendo premuto uno spazio libero si blocca l\'orario', (tester) async {
    await pumpAgenda(tester);
    final gap = find.textContaining('Libero fino alle').first;
    await tester.ensureVisible(gap);
    await tester.longPress(gap);
    await settle(tester);
    expect(find.text('Blocca un orario'), findsOneWidget);

    await tester.tap(find.text('BLOCCA ORARIO'));
    await settle(tester);
    expect(find.text('Orario bloccato'), findsOneWidget);
    expect(find.textContaining('Pausa'), findsWidgets);
  });
}

/// Fa avanzare il tempo finto (il backend demo risponde dopo 250 ms).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}
