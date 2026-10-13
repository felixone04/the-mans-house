import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:the_mans_house/data/demo_backend.dart';
import 'package:the_mans_house/data/export.dart';
import 'package:the_mans_house/data/slots.dart';
import 'package:the_mans_house/models.dart';
import 'package:the_mans_house/screens/admin/customer_screen.dart';
import 'package:the_mans_house/screens/admin/search_screen.dart';
import 'package:the_mans_house/screens/admin/walk_in_sheet.dart';
import 'package:the_mans_house/state/app_state.dart';
import 'package:the_mans_house/theme.dart';

/// Esportazione per Excel, ricerca clienti e cliente entrato senza appuntamento.
void main() {
  setUpAll(() async {
    googleFontsEnabled = false;
    await initializeDateFormatting('it_IT');
    Intl.defaultLocale = 'it_IT';
  });

  Appointment appt(String id, {double price = 15, AppointmentStatus status = AppointmentStatus.completed}) =>
      Appointment(
        id: id,
        barberId: 'b1',
        barberName: 'Antonio',
        serviceName: 'Taglio; corto', // il ";" va racchiuso tra virgolette
        price: price,
        start: DateTime(2026, 10, 13, 10, 30),
        end: DateTime(2026, 10, 13, 11),
        status: status,
        customerName: 'Mario "Mimmo" Rossi',
        customerPhone: '+393331234567',
      );

  group('esportazione CSV', () {
    test('incassi: BOM, separatore ";", decimali con virgola, totali per barbiere', () {
      final paid = appt('1')..payment = PaymentStatus.paid;
      final deposit = appt('2', price: 23)
        ..payment = PaymentStatus.deposit
        ..amountPaid = 5;
      final cancelled = appt('3', status: AppointmentStatus.cancelled);
      final file = revenueCsv('incassi.csv', [paid, deposit, cancelled]);

      expect(file.bytes.take(3), [0xEF, 0xBB, 0xBF]);
      final lines = utf8.decode(file.bytes.skip(3).toList()).split('\r\n');
      expect(lines.first, startsWith('Data;Ora;Barbiere;Cliente'));
      expect(lines, hasLength(1 + 2 + 1 + 2)); // intestazione, 2 righe (annullato escluso), vuota, 2 totali
      expect(lines[1], contains('13/10/2026;10:30;Antonio;"Mario ""Mimmo"" Rossi"'));
      expect(lines[1], contains('"Taglio; corto";15,00;Completato;Pagato;15,00;0,00'));
      expect(lines[2], contains('23,00;Completato;Acconto;5,00;18,00'));
      expect(lines[4], 'Totale;;;;;;38,00;;;20,00;18,00');
      expect(lines[5], startsWith('Totale Antonio;;Antonio'));
    });

    test('clienti: importi da incassare e non presentati per cliente', () {
      final c = CustomerSummary(
        id: '${CustomerSummary.walkInPrefix}Mario "Mimmo" Rossi',
        email: '',
        fullName: 'Mario "Mimmo" Rossi',
        phone: '+393331234567',
        bookings: 3,
        lastVisit: DateTime(2026, 10, 13),
      );
      final later = appt('1')..payment = PaymentStatus.later;
      final noShow = appt('2', status: AppointmentStatus.noShow);
      final lines = customersCsv('c.csv', [c], [later, noShow]).text.split('\r\n');
      expect(lines.first, 'Nome;Telefono;Email;Tipo;Prenotazioni;Ultima visita;Non presentato;Da incassare');
      expect(lines[1], '"Mario ""Mimmo"" Rossi";+393331234567;;Dal banco;3;13/10/2026;1;15,00');
    });
  });

  Future<(AppState, DemoBackend)> pump(WidgetTester tester, Widget Function(AppState) page) async {
    tester.view.physicalSize = const Size(390, 844);
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
          theme: buildTheme(),
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

  testWidgets('ricerca: scrivendo un nome si trova il cliente e si apre la scheda', (tester) async {
    await pump(tester, (_) => const SearchScreen());
    expect(find.text('Scrivi un nome o un numero'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bianc'); // "Luca Bianchi" nei dati demo
    await settle(tester);
    expect(find.text('Luca Bianchi'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await settle(tester);
    expect(find.text('Nessun cliente trovato'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'luca');
    await settle(tester);
    await tester.tap(find.text('Luca Bianchi'));
    await settle(tester);
    expect(find.byType(CustomerScreen), findsOneWidget);
  });

  testWidgets('cliente entrato ora: inserito nel primo orario libero di oggi', (tester) async {
    final (state, backend) = await pump(
      tester,
      (_) => Builder(
        builder: (c) => Center(
          child: FilledButton(onPressed: () => showWalkInSheet(c), child: const Text('apri')),
        ),
      ),
    );
    await tester.tap(find.text('apri'));
    await settle(tester);
    expect(find.text('Scegli il servizio'), findsOneWidget);

    final service = state.services.first;
    await tester.tap(find.textContaining(service.name).first);
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nome (facoltativo)'), 'Gino Passante');
    await settle(tester);

    // oggi il negozio puo' essere chiuso o gia' pieno: in quel caso lo dice
    final today = dayOnly(DateTime.now());
    final busy = await tester.runAsync(() => backend.fetchBusy(today, today.add(const Duration(days: 1))));
    final free = availableSlotsAnyBarber(
      barbers: state.barbers,
      durationMin: service.durationMin,
      day: today,
      busy: busy!,
      stepMin: 5,
    );
    if (free.isEmpty) {
      expect(find.text('Nessun orario libero oggi per questo servizio.'), findsOneWidget);
      return;
    }
    expect(find.text(fmtTime(free.keys.first)), findsOneWidget);
    await tester.ensureVisible(find.text('INSERISCI'));
    await settle(tester);
    await tester.tap(find.text('INSERISCI'));
    await settle(tester);
    final list = await tester.runAsync(() => backend.appointmentsBetween(today, today.add(const Duration(days: 1))));
    final added = list!.where((a) => a.customerName == 'Gino Passante').toList();
    expect(added, hasLength(1));
    expect(added.single.start, free.keys.first);
    expect(added.single.barberId, free.values.first.id);
  });
}

String fmtTime(DateTime d) => DateFormat.Hm('it_IT').format(d);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}
