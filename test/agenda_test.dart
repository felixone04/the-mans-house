import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:the_mans_house/data/demo_backend.dart';
import 'package:the_mans_house/data/slots.dart';
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

  PageController lanes(WidgetTester tester) => tester.widget<PageView>(find.byType(PageView)).controller!;

  testWidgets('corsie: un barbiere alla volta, si cambia scorrendo o con le schede', (tester) async {
    final (state, _) = await pumpAgenda(tester);
    expect(tester.takeException(), isNull);
    expect(lanes(tester).page, 0);
    // la prima corsia mostra solo gli appuntamenti del primo barbiere
    expect(find.textContaining('libero'), findsWidgets);

    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await settle(tester);
    expect(lanes(tester).page, 1);

    await tester.tap(find.text(state.barbers[2].name));
    await settle(tester);
    expect(lanes(tester).page, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toccando un appuntamento si apre il dettaglio con "Sposta"', (tester) async {
    await pumpAgenda(tester);
    final card = find.textContaining(RegExp(r'^\d\d:\d\d–\d\d:\d\d')).first;
    await tester.ensureVisible(card);
    await tester.tap(card);
    await settle(tester);
    expect(find.text('Sposta appuntamento'), findsOneWidget);
    expect(find.text('Segna come completato'), findsOneWidget);
  });

  testWidgets('vista griglia su telefono: nessun errore di impaginazione', (tester) async {
    await pumpAgenda(tester);
    await tester.tap(find.byTooltip('Vista griglia'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Vista corsie'), findsOneWidget);
    // filtro su un barbiere: resta una sola colonna
    await tester.tap(find.text('Antonio').first);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tenendo premuto uno spazio libero si blocca l\'orario', (tester) async {
    await pumpAgenda(tester);
    final gap = find.textContaining('libero').first;
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
