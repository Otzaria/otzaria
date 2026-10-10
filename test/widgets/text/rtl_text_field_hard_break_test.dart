import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// בודק את עוקף באג-הסמן בשדות רב-שורתיים (otzaria issue #1716): \r לעולם
/// לא דולף לקוד קורא, וה-selection של ה-controller נשאר חי גם בלי עריכה.
void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: child,
      ),
    ),
  );

  Future<void> rightClickAt(WidgetTester tester, Offset position) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(position);
    await gesture.down(position);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  void mockClipboard(WidgetTester tester, {String? initialText}) {
    String? clipboardText = initialText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        } else if (call.method == 'Clipboard.getData') {
          return {'text': clipboardText};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  group('הקלדה: \\r לעולם לא דולף החוצה', () {
    testWidgets('Enter טרי: onChanged ו-controller.text נשארים נקיים', (
      tester,
    ) async {
      final controller = TextEditingController();
      final changes = <String>[];
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        host(
          RtlTextField(
            controller: controller,
            maxLines: null,
            onChanged: changes.add,
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'אבג\nדהו');
      await tester.pump();

      expect(controller.text, 'אבג\nדהו');
      expect(controller.text, isNot(contains('\r')));
      expect(changes, isNotEmpty);
      expect(changes.last, 'אבג\nדהו');
      expect(changes.last, isNot(contains('\r')));
    });

    testWidgets(
      'תוכן קיים עם \\n גולמי (למשל ספר שנטען) נטען בלי קריסה ונשאר נקי',
      (
        tester,
      ) async {
        final controller = TextEditingController(text: 'שורה א\nשורה ב');
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          host(RtlTextField(controller: controller, maxLines: null)),
        );
        await tester.pump();

        expect(controller.text, 'שורה א\nשורה ב');

        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.enterText(
          find.byType(TextField),
          'שורה א\nשורה ב\nשורה ג',
        );
        await tester.pump();

        expect(controller.text, 'שורה א\nשורה ב\nשורה ג');
        expect(controller.text, isNot(contains('\r')));
      },
    );

    testWidgets(
      'תוכן קיים עם \\r: הטעינה לא משנה את ה-controller של הקורא, והעריכה הראשונה מנקה',
      (tester) async {
        final controller = TextEditingController(text: 'שורה א\rשורה ב');
        final changes = <String>[];
        var notifications = 0;
        controller.addListener(() => notifications++);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          host(
            RtlTextField(
              controller: controller,
              maxLines: null,
              onChanged: changes.add,
            ),
          ),
        );
        await tester.pump();

        expect(controller.text, 'שורה א\rשורה ב');
        expect(
          notifications,
          0,
          reason: 'מאזיני הקורא לא יופעלו באמצע build',
        );

        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'שורה א\rשורה בג');
        await tester.pump();

        expect(controller.text, 'שורה א\nשורה בג');
        expect(changes.last, 'שורה א\nשורה בג');
      },
    );

    testWidgets('שדה חד-שורתי (ברירת מחדל) אינו מופעל — ללא שינוי התנהגות', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(host(RtlTextField(controller: controller)));
      await tester.tap(find.byType(TextField));
      await tester.pump();

      // TextField עם maxLines:1 כבר מסנן \n בעצמו (ברירת המחדל של Flutter);
      // מוודאים רק שאין קריסה ושאין \r בשום מקרה.
      await tester.enterText(find.byType(TextField), 'אבגדה');
      await tester.pump();
      expect(controller.text, isNot(contains('\r')));
    });

    testWidgets(
      'הדבקה דרך תפריט ההקשר מנקה \\r\\n מהלוח לפני שהוא נכנס ל-controller הנקי',
      (tester) async {
        mockClipboard(tester, initialText: 'שורה חדשה\r\nעוד שורה');
        final controller = TextEditingController(text: 'התחלה');
        final changes = <String>[];
        final focusNode = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          host(
            RtlTextField(
              controller: controller,
              focusNode: focusNode,
              maxLines: null,
              onChanged: changes.add,
            ),
          ),
        );
        focusNode.requestFocus();
        await tester.pump();
        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.pump();

        await rightClickAt(tester, tester.getCenter(find.byType(TextField)));
        await tester.tap(find.text('הדבק'));
        await tester.pumpAndSettle();

        expect(controller.text, 'שורה חדשה\nעוד שורההתחלה');
        expect(controller.text, isNot(contains('\r')));
        expect(changes.last, isNot(contains('\r')));
      },
    );
  });

  group('הבחירה הנקייה חיה תמיד, גם בלי עריכת טקסט', () {
    testWidgets(
      'ניווט מקלדת בלבד (בלי נגיעה חיצונית) מעדכן את controller.selection הנקי מיידית',
      (tester) async {
        // מדמה קוד קורא חיצוני (toolbar עיצוב/הוספת קישור/חיפוש-מהסמן, כמו
        // ב-text_section_editor_dialog.dart) שקורא controller.selection
        // ישירות אחרי שהמשתמש רק הזיז סמן, בלי להקליד.
        const text = 'אבגדה\nוזחטיכלמנ';
        final controller = TextEditingController(text: text);
        final focusNode = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          host(
            RtlTextField(
              controller: controller,
              focusNode: focusNode,
              maxLines: null,
            ),
          ),
        );
        focusNode.requestFocus();
        await tester.pump();
        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.pump();

        // 7 צעדי Shift+שמאל (="קדימה" בעברית) חוצים את שבירת השורה.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        for (var i = 0; i < 7; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();

        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 7),
          reason:
              'controller.selection (הנקי) חייב לשקף את הבחירה החיה מיד, '
              'בלי שהתפריט או כל נגיעה חיצונית אחרת יפעילו סנכרון',
        );
      },
    );

    testWidgets(
      'תפריט ההקשר פועל נכון על בחירה שנוצרה בניווט מקלדת בלבד',
      (tester) async {
        String? clipboardText;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboardText = (call.arguments as Map)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        const text = 'אבגדה\nוזחטיכלמנ';
        final controller = TextEditingController(text: text);
        final focusNode = FocusNode();
        addTearDown(controller.dispose);
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          host(
            RtlTextField(
              controller: controller,
              focusNode: focusNode,
              maxLines: null,
            ),
          ),
        );
        focusNode.requestFocus();
        await tester.pump();
        controller.selection = const TextSelection.collapsed(offset: 0);
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        for (var i = 0; i < 7; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();

        await rightClickAt(tester, tester.getCenter(find.byType(TextField)));
        expect(find.text('גזור'), findsOneWidget);
        expect(find.text('העתק'), findsOneWidget);

        await tester.tap(find.text('גזור'));
        await tester.pumpAndSettle();

        expect(clipboardText, 'אבגדה\nו');
        expect(controller.text, 'זחטיכלמנ');
        expect(controller.text, isNot(contains('\r')));
      },
    );
  });

  group('מוטציה חיצונית ישירה (דפוס undo/חיפוש-והחלפה של עורך טקסט)', () {
    testWidgets(
      'הצבת text ואז selection בנפרד (כמו _undo ב-text_section_editor_dialog) לא קורסת ונשארת מסונכרנת',
      (tester) async {
        final controller = TextEditingController(text: 'שורה א\nשורה ב');
        final changes = <String>[];
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          host(
            RtlTextField(
              controller: controller,
              maxLines: null,
              onChanged: changes.add,
            ),
          ),
        );
        await tester.pump();

        // דפוס זהה ל-_undo()/_redo(): שתי הקצאות נפרדות, לא דרך הקלדה.
        controller.text = 'חדש\nטקסט לגמרי';
        controller.selection = const TextSelection.collapsed(offset: 4);
        await tester.pump();

        expect(controller.text, 'חדש\nטקסט לגמרי');
        expect(controller.selection, const TextSelection.collapsed(offset: 4));

        // המשך הקלדה אחרי המוטציה החיצונית — חייב להמשיך לעבוד בלי \r דולף.
        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.enterText(
          find.byType(TextField),
          'חדש\nטקסט לגמרי שונה',
        );
        await tester.pump();

        expect(controller.text, 'חדש\nטקסט לגמרי שונה');
        expect(controller.text, isNot(contains('\r')));
        expect(changes.last, isNot(contains('\r')));
      },
    );
  });
}
