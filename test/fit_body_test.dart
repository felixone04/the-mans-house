import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_mans_house/widgets/common.dart';

void main() {
  Widget page(TextEditingController ctrl, FocusNode focus) => MaterialApp(
    home: Scaffold(
      body: FitBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 12; i++) const SizedBox(height: 60, child: Text('riga')),
            TextField(controller: ctrl, focusNode: focus),
          ],
        ),
      ),
    ),
  );

  testWidgets('senza tastiera non scorre e riduce il contenuto', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ctrl = TextEditingController();
    final focus = FocusNode();
    await tester.pumpWidget(page(ctrl, focus));
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(FittedBox), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aprendo la tastiera il campo resta attivo (niente perdita di focus)', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ctrl = TextEditingController();
    final focus = FocusNode();
    await tester.pumpWidget(page(ctrl, focus));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    final state = tester.state(find.byType(EditableText));

    // la tastiera si apre: FitBody diventa scorrevole
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(focus.hasFocus, isTrue, reason: 'il campo non deve perdere il focus');
    expect(tester.state(find.byType(EditableText)), same(state), reason: 'lo stato del campo va conservato');

    await tester.enterText(find.byType(TextField), 'ciao');
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(ctrl.text, 'ciao');
    expect(find.byType(SingleChildScrollView), findsNothing);
  });
}
