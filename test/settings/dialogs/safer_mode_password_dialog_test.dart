import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/dialogs/safer_mode_password_dialog.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

Widget _openButton(void Function(BuildContext) onOpen) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (ctx) => TextButton(
        onPressed: () => onOpen(ctx),
        child: const Text('פתח'),
      ),
    ),
  ),
);

Future<void> _openSetPasswordDialog(
  WidgetTester tester, {
  required Future<void> Function(String password) onSetPassword,
  Future<void> Function()? onClearPassword,
  bool isSaferModeEnabled = false,
}) async {
  await tester.pumpWidget(
    _openButton(
      (ctx) => showDialog<bool>(
        context: ctx,
        builder: (_) => SaferModeSetPasswordDialog(
          onSetPassword: onSetPassword,
          onClearPassword: onClearPassword,
          isSaferModeEnabled: isSaferModeEnabled,
        ),
      ),
    ),
  );
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
}

void main() {
  group('SaferModeSetPasswordDialog — הסרת סיסמה', () {
    testWidgets('כשלא הועבר onClearPassword — אין כפתור מחיקה כלל', (
      tester,
    ) async {
      await _openSetPasswordDialog(
        tester,
        onSetPassword: (_) async {},
      );

      expect(find.text('מחיקת סיסמה'), findsNothing);
      expect(
        find.text('לא ניתן למחוק את הסיסמה כשמצב סייפר פעיל'),
        findsNothing,
      );
    });

    testWidgets(
      'כשיש onClearPassword ומצב סייפר כבוי — מוצג כפתור "מחיקת סיסמה" פעיל',
      (tester) async {
        await _openSetPasswordDialog(
          tester,
          onSetPassword: (_) async {},
          onClearPassword: () async {},
          isSaferModeEnabled: false,
        );

        expect(find.text('מחיקת סיסמה'), findsOneWidget);
        final button = tester.widget<ActionButton>(
          find.ancestor(
            of: find.text('מחיקת סיסמה'),
            matching: find.byType(ActionButton),
          ),
        );
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets('כשמצב סייפר פעיל — הכפתור מציג הודעה מתאימה ומנוטרל', (
      tester,
    ) async {
      await _openSetPasswordDialog(
        tester,
        onSetPassword: (_) async {},
        onClearPassword: () async {},
        isSaferModeEnabled: true,
      );

      expect(
        find.text('לא ניתן למחוק את הסיסמה כשמצב סייפר פעיל'),
        findsOneWidget,
      );
      expect(find.text('מחיקת סיסמה'), findsNothing);
      final button = tester.widget<ActionButton>(
        find.ancestor(
          of: find.text('לא ניתן למחוק את הסיסמה כשמצב סייפר פעיל'),
          matching: find.byType(ActionButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'לחיצה על "מחיקת סיסמה" ואישור באזהרה — קורא ל-onClearPassword וסוגר את הדיאלוג',
      (tester) async {
        var cleared = false;

        await _openSetPasswordDialog(
          tester,
          onSetPassword: (_) async {},
          onClearPassword: () async {
            cleared = true;
          },
          isSaferModeEnabled: false,
        );

        await tester.tap(find.text('מחיקת סיסמה'));
        await tester.pumpAndSettle();

        // דיאלוג אזהרה נפתח - יש לאשר את ההסרה.
        expect(find.text('הסרת סיסמה'), findsOneWidget);

        await tester.tap(find.text('הסר סיסמה'));
        await tester.pumpAndSettle();

        expect(cleared, isTrue);
        expect(find.text('הסרת סיסמה'), findsNothing);
        expect(find.byType(SaferModeSetPasswordDialog), findsNothing);
      },
    );

    testWidgets('ביטול באזהרה — לא קורא ל-onClearPassword והדיאלוג נשאר פתוח', (
      tester,
    ) async {
      var cleared = false;

      await _openSetPasswordDialog(
        tester,
        onSetPassword: (_) async {},
        onClearPassword: () async {
          cleared = true;
        },
        isSaferModeEnabled: false,
      );

      await tester.tap(find.text('מחיקת סיסמה'));
      await tester.pumpAndSettle();

      // "ביטול" מופיע גם על הדיאלוג הבסיסי וגם על דיאלוג האזהרה - יש לבחור
      // את זה שבחזית (דיאלוג האזהרה, שנפתח אחרון).
      await tester.tap(find.text('ביטול').last);
      await tester.pumpAndSettle();

      expect(cleared, isFalse);
      expect(find.byType(SaferModeSetPasswordDialog), findsOneWidget);
    });
  });
}
