import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/dialogs/error_report_sender_email_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// העלאת השדה לבדיקה בתוך MaterialApp + Overlay, עם MediaQuery עם רוחב סביר
  /// כדי שה-OverlayEntry של ההצעות יוצב נכון.
  Future<void> pumpField(
    WidgetTester tester, {
    String initialText = '',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(600, 800)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: EmailFieldWithAutocomplete(
                  initialValue: initialText,
                  subtitle: 'תיאור',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// גישה ל-controller הפנימי של ה-widget דרך ה-TextField שבתוכו.
  TextEditingController getController(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!;

  group('commonEmailDomains', () {
    test('מכיל את הסיומות העיקריות הצפויות', () {
      expect(commonEmailDomains, contains('gmail.com'));
      expect(commonEmailDomains, contains('walla.co.il'));
      expect(commonEmailDomains, contains('9900.co.il'));
      expect(commonEmailDomains, contains('outlook.com'));
    });
  });

  group('EmailFieldWithAutocomplete — הצגת הצעות', () {
    testWidgets('הקלדת @ מציגה את כל הסיומות הנפוצות', (tester) async {
      await pumpField(tester);

      await tester.enterText(find.byType(TextField), 'someone@');
      await tester.pumpAndSettle();

      // לפחות שלוש הצעות מוכרות צריכות להופיע
      expect(find.text('@gmail.com'), findsOneWidget);
      expect(find.text('@walla.co.il'), findsOneWidget);
      expect(find.text('@outlook.com'), findsOneWidget);
    });

    testWidgets('בלי @ — אין הצעות', (tester) async {
      await pumpField(tester);

      await tester.enterText(find.byType(TextField), 'someone');
      await tester.pumpAndSettle();

      expect(find.text('@gmail.com'), findsNothing);
      expect(find.text('@outlook.com'), findsNothing);
    });

    testWidgets('הקלדת @gm — מסננת רק לסיומות שמתחילות ב-gm', (tester) async {
      await pumpField(tester);

      await tester.enterText(find.byType(TextField), 'a@gm');
      await tester.pumpAndSettle();

      expect(find.text('@gmail.com'), findsOneWidget);
      expect(find.text('@walla.co.il'), findsNothing);
      expect(find.text('@outlook.com'), findsNothing);
    });

    testWidgets('כשהסיומת כבר מלאה במלואה — לא מציגים אותה כהצעה', (
      tester,
    ) async {
      await pumpField(tester);

      await tester.enterText(find.byType(TextField), 'a@gmail.com');
      await tester.pumpAndSettle();

      // הסיומת המלאה לא צריכה להופיע כהצעה (אין מה להשלים)
      expect(find.text('@gmail.com'), findsNothing);
    });

    testWidgets('סיומת לא מוכרת — אין הצעות', (tester) async {
      await pumpField(tester);

      await tester.enterText(find.byType(TextField), 'a@example.xyz');
      await tester.pumpAndSettle();

      expect(find.text('@gmail.com'), findsNothing);
      expect(find.text('@outlook.com'), findsNothing);
    });

    testWidgets('הקלדת רישיות — סינון לא רגיש לרישיות', (tester) async {
      await pumpField(tester);

      await tester.enterText(find.byType(TextField), 'a@GM');
      await tester.pumpAndSettle();

      expect(find.text('@gmail.com'), findsOneWidget);
    });
  });

  group('EmailFieldWithAutocomplete — בחירת הצעה', () {
    testWidgets('לחיצה על הצעה משלימה את הסיומת', (tester) async {
      await pumpField(tester);
      final controller = getController(tester);

      await tester.enterText(find.byType(TextField), 'someone@gm');
      await tester.pumpAndSettle();

      await tester.tap(find.text('@gmail.com'));
      await tester.pumpAndSettle();

      expect(controller.text, equals('someone@gmail.com'));
      expect(
        controller.selection.baseOffset,
        equals('someone@gmail.com'.length),
        reason: 'הסמן צריך להיות בסוף הטקסט אחרי השלמה',
      );
    });

    testWidgets('לאחר בחירת הצעה האוברליי נסגר', (tester) async {
      await pumpField(tester);

      await tester.enterText(find.byType(TextField), 'a@out');
      await tester.pumpAndSettle();
      expect(find.text('@outlook.com'), findsOneWidget);

      await tester.tap(find.text('@outlook.com'));
      await tester.pumpAndSettle();

      expect(find.text('@gmail.com'), findsNothing);
      expect(find.text('@outlook.com'), findsNothing);
    });

    testWidgets('בחירת הצעה כשהסמן באמצע דומיין מחליפה את כל הדומיין', (
      tester,
    ) async {
      // רגרסיה: לפני התיקון הטקסט "name@gma|il.com" היה הופך
      // ל-"name@gmail.comil.com" כי ה-after נלקח מהסמן ולא מסוף הדומיין.
      await pumpField(tester);
      final controller = getController(tester);

      controller.value = const TextEditingValue(
        text: 'name@gmail.com',
        selection: TextSelection.collapsed(offset: 8), // אחרי "name@gma"
      );
      await tester.pumpAndSettle();

      // לכאורה "gma" הוא הקלט — צריך להופיע gmail.com כהצעה
      expect(find.text('@gmail.com'), findsOneWidget);

      await tester.tap(find.text('@gmail.com'));
      await tester.pumpAndSettle();

      expect(
        controller.text,
        equals('name@gmail.com'),
        reason: 'יש להחליף את כל הדומיין, לא לשרשר חלק נוסף',
      );
      expect(
        controller.selection.baseOffset,
        equals('name@gmail.com'.length),
      );
    });

    testWidgets('בחירת הצעה שומרת טקסט אחרי הדומיין כשיש מפריד', (
      tester,
    ) async {
      await pumpField(tester);
      final controller = getController(tester);

      controller.value = const TextEditingValue(
        text: 'a@gm, b@example.com',
        selection: TextSelection.collapsed(offset: 4), // אחרי "a@gm"
      );
      await tester.pumpAndSettle();

      expect(find.text('@gmail.com'), findsOneWidget);
      await tester.tap(find.text('@gmail.com'));
      await tester.pumpAndSettle();

      expect(
        controller.text,
        equals('a@gmail.com, b@example.com'),
        reason: 'מפריד פסיק מסמן את סוף הדומיין הראשון, השני נשאר נגיש',
      );
    });
  });

  group('showErrorReportSenderEmailDialog — ולידציה', () {
    Future<String?> openDialog(
      WidgetTester tester, {
      required String typedValue,
    }) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(600, 800)),
            child: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    result = await showErrorReportSenderEmailDialog(
                      context: context,
                      validator: (email) => email.contains('@')
                          ? null
                          : 'יש להזין כתובת דוא"ל תקינה.',
                    );
                  },
                  child: const Text('פתח'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), typedValue);
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('ערך לא תקין משאיר את הדיאלוג פתוח ומציג שגיאה', (
      tester,
    ) async {
      await openDialog(tester, typedValue: 'invalid');

      await tester.tap(find.widgetWithText(FilledButton, 'שמור'));
      await tester.pumpAndSettle();

      expect(find.text('יש להזין כתובת דוא"ל תקינה.'), findsOneWidget);
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason: 'הדיאלוג צריך להישאר פתוח כדי שהקלט לא יאבד',
      );
    });

    testWidgets('תיקון הערך אחרי שגיאה מנקה אותה ומאפשר שמירה', (tester) async {
      await openDialog(tester, typedValue: 'invalid');

      await tester.tap(find.widgetWithText(FilledButton, 'שמור'));
      await tester.pumpAndSettle();
      expect(find.text('יש להזין כתובת דוא"ל תקינה.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'name@example.com');
      await tester.pumpAndSettle();
      expect(find.text('יש להזין כתובת דוא"ל תקינה.'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'שמור'));
      await tester.pumpAndSettle();
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'ערך תקין סוגר את הדיאלוג',
      );
    });
  });

  group('EmailFieldWithAutocomplete — Ctrl+V (הדבקה)', () {
    setUp(() {
      // נדמה את הקלסבורד עם טקסט מוכן להדבקה
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.getData') {
                return <String, dynamic>{'text': 'pasted@gmail.com'};
              }
              if (call.method == 'Clipboard.setData') {
                return null;
              }
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
    });

    testWidgets('Ctrl+V מדביק טקסט לתוך השדה', (tester) async {
      await pumpField(tester);
      final controller = getController(tester);

      // מבטיחים שהפוקוס בשדה
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // מפעילים את שורטקאט ההדבקה הסטנדרטי של פלטר
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(controller.text, equals('pasted@gmail.com'));
    });
  });
}
