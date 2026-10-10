import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/ui_snack.dart';

void main() {
  tearDown(UiSnack.hide);

  Future<void> pumpHost(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()),
  );

  testWidgets('סגירה לפי בעלות אינה מסתירה הודעה חדשה', (tester) async {
    await pumpHost(tester);
    final owner = Object();
    UiSnack.showChecking('ממתין', owner: owner);
    await tester.pump();
    UiSnack.showError('שגיאה חדשה');
    await tester.pump();
    UiSnack.hide(owner: owner);
    await tester.pump();
    expect(find.text('שגיאה חדשה'), findsOneWidget);
    UiSnack.hide();
    await tester.pump();
    expect(find.text('שגיאה חדשה'), findsNothing);
  });

  testWidgets('הבעלים יכול לסגור את ההודעה שלו', (tester) async {
    await pumpHost(tester);
    final owner = Object();
    UiSnack.showChecking('ממתין', owner: owner);
    await tester.pump();
    expect(find.text('ממתין'), findsOneWidget);
    UiSnack.hide(owner: owner);
    await tester.pump();
    expect(find.text('ממתין'), findsNothing);
  });

  testWidgets('הודעה שבוטלה לפני הצגתה אינה מופיעה בפריים הבא', (tester) async {
    await pumpHost(tester);
    final owner = Object();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UiSnack.showChecking('בוטלה', owner: owner);
      UiSnack.hide(owner: owner);
    });
    tester.binding.scheduleFrame();
    await tester.pump();
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump();
    expect(find.text('בוטלה'), findsNothing);
  });

  testWidgets('שתי הודעות שנדחו לפריים הבא מציגות רק את האחרונה', (
    tester,
  ) async {
    await pumpHost(tester);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UiSnack.showChecking('ראשונה', owner: Object());
      UiSnack.showChecking('אחרונה', owner: Object());
    });
    tester.binding.scheduleFrame();
    await tester.pump();
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump();
    expect(find.text('ראשונה'), findsNothing);
    expect(find.text('אחרונה'), findsOneWidget);
    UiSnack.hide();
    await tester.pump();
  });
}
