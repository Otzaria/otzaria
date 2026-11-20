// כפתורי הצגה והסתרה של סיסמה בדיאלוגי מצב סייפר נושאים
// שם נגיש (tooltip) שמתעדכן לפי המצב.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/dialogs/safer_mode_password_dialog.dart';

Future<void> _open(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => dialog,
            ),
            child: const Text('פתח'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('דיאלוג אימות: כפתור ההצגה נושא שם ומתהפך', (tester) async {
    await _open(tester, SaferModePasswordDialog(onVerify: (_) async => true));

    expect(find.byTooltip('הצג סיסמה'), findsOneWidget);
    expect(find.byTooltip('הסתר סיסמה'), findsNothing);

    await tester.tap(find.byTooltip('הצג סיסמה'));
    await tester.pump();

    expect(find.byTooltip('הסתר סיסמה'), findsOneWidget);
    expect(find.byTooltip('הצג סיסמה'), findsNothing);
  });

  testWidgets('דיאלוג הגדרת סיסמה: שני השדות נושאים שם', (tester) async {
    await _open(
      tester,
      SaferModeSetPasswordDialog(onSetPassword: (_) async {}),
    );

    expect(find.byTooltip('הצג סיסמה'), findsNWidgets(2));
  });
}
