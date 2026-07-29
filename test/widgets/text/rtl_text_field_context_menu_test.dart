import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// בודק את תפריט ההקשר (לחצן ימני) המותאם-אישית של [RtlTextField].
///
/// רגרסיה: הדבקה/גזירה דרך התפריט הציבו `controller.text` ישירות בלי
/// להפעיל את `onChanged` (שמופעל רק מנתיב הקלט הפנימי של EditableText),
/// כך ששדות חיפוש שמריצים חיפוש מתוך onChanged (למשל חיפוש הספרייה)
/// המשיכו להציג תוצאות לפי הטקסט שהיה כתוב *לפני* ההדבקה.
void main() {
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

  Future<TextEditingController> pumpField(
    WidgetTester tester, {
    ValueChanged<String>? onChanged,
    String text = '',
  }) async {
    final controller = TextEditingController(text: text);
    final focusNode = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: RtlTextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
    // ממקד את השדה: לחיצה ימנית בלי פוקוס גוררת selectPosition פנימי
    // ב-Windows/Linux שמכווץ כל בחירה קיימת למיקום הלחיצה (ראו onSecondaryTap
    // ב-text_selection.dart) — לא רלוונטי לתרחיש האמיתי בו כבר יש פוקוס בשדה.
    focusNode.requestFocus();
    await tester.pump();
    return controller;
  }

  testWidgets(
    'הדבקה דרך תפריט ההקשר מעדכנת את הטקסט ומפעילה onChanged',
    (tester) async {
      mockClipboard(tester, initialText: 'ראשית');
      final changes = <String>[];
      final controller = await pumpField(tester, onChanged: changes.add);
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();

      await rightClickAt(tester, tester.getCenter(find.byType(TextField)));
      await tester.tap(find.text('הדבק'));
      await tester.pumpAndSettle();

      expect(controller.text, 'ראשית');
      expect(
        changes,
        contains('ראשית'),
        reason:
            'הדבקה דרך לחצן ימני חייבת להפעיל onChanged כמו הקלדה רגילה, '
            'אחרת שדה חיפוש המבוסס על onChanged (כמו חיפוש הספרייה) ימשיך '
            'להריץ חיפוש לפי הטקסט הישן',
      );
    },
  );

  testWidgets(
    'הדבקה באמצע טקסט קיים משלבת נכון ומעדכנת onChanged עם הטקסט המלא',
    (tester) async {
      mockClipboard(tester, initialText: 'XYZ');
      final changes = <String>[];
      final controller = await pumpField(
        tester,
        text: 'אבגד',
        onChanged: changes.add,
      );
      // סמן אחרי "אב" (offset 2).
      controller.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();

      await rightClickAt(tester, tester.getCenter(find.byType(TextField)));
      await tester.tap(find.text('הדבק'));
      await tester.pumpAndSettle();

      expect(controller.text, 'אבXYZגד');
      expect(changes.last, 'אבXYZגד');
      expect(controller.selection.baseOffset, 5);
    },
  );

  testWidgets(
    'הדבקה על טקסט נבחר מחליפה את הבחירה ומעדכנת onChanged',
    (tester) async {
      mockClipboard(tester, initialText: 'חדש');
      final changes = <String>[];
      final controller = await pumpField(
        tester,
        text: 'אבגדה',
        onChanged: changes.add,
      );
      // בוחר "בגד" (offset 1..4).
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      await tester.pump();

      await rightClickAt(tester, tester.getCenter(find.byType(TextField)));
      await tester.tap(find.text('הדבק'));
      await tester.pumpAndSettle();

      expect(controller.text, 'אחדשה');
      expect(changes.last, 'אחדשה');
    },
  );

  testWidgets(
    'הדבקה משתמשת בבחירה העדכנית כשה-controller משתנה בזמן שהתפריט פתוח',
    (tester) async {
      mockClipboard(tester, initialText: 'X');
      final controller = await pumpField(tester, text: 'טקסט ישן');
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );
      await tester.pump();

      await rightClickAt(tester, tester.getCenter(find.byType(TextField)));
      controller.value = const TextEditingValue(
        text: 'עדכני',
        selection: TextSelection.collapsed(offset: 2),
      );
      await tester.pump();
      await tester.tap(find.text('הדבק'));
      await tester.pumpAndSettle();

      expect(controller.text, 'עדXכני');
      expect(controller.selection.baseOffset, 3);
    },
  );

  testWidgets(
    'גזירה מעתיקה ללוח, מסירה את הטקסט הנבחר ומפעילה onChanged',
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

      final changes = <String>[];
      final controller = await pumpField(
        tester,
        text: 'אבגדה',
        onChanged: changes.add,
      );
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      await tester.pump();

      await rightClickAt(tester, tester.getCenter(find.byType(TextField)));
      await tester.tap(find.text('גזור'));
      await tester.pumpAndSettle();

      expect(clipboardText, 'בגד');
      expect(controller.text, 'אה');
      expect(
        changes,
        contains('אה'),
        reason: 'גזירה משנה את הטקסט ולכן חייבת גם היא להפעיל onChanged',
      );
    },
  );

  testWidgets(
    'העתקה אינה משנה את הטקסט ולכן אינה מפעילה onChanged',
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

      final changes = <String>[];
      final controller = await pumpField(
        tester,
        text: 'אבגדה',
        onChanged: changes.add,
      );
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      await tester.pump();

      await rightClickAt(tester, tester.getCenter(find.byType(TextField)));
      await tester.tap(find.text('העתק'));
      await tester.pumpAndSettle();

      expect(clipboardText, 'בגד');
      expect(controller.text, 'אבגדה');
      expect(changes, isEmpty);
    },
  );

  testWidgets(
    '"בחר הכל" בוחר את כל הטקסט ואינו מפעיל onChanged',
    (tester) async {
      final changes = <String>[];
      final controller = await pumpField(
        tester,
        text: 'אבגדה',
        onChanged: changes.add,
      );
      await tester.pump();

      await rightClickAt(tester, tester.getCenter(find.byType(TextField)));
      await tester.tap(find.text('בחר הכל'));
      await tester.pumpAndSettle();

      expect(controller.selection.baseOffset, 0);
      expect(controller.selection.extentOffset, 5);
      expect(changes, isEmpty);
    },
  );

  testWidgets(
    'התפריט מציג "גזור"/"העתק" רק כשיש בחירה פעילה',
    (tester) async {
      final controller = await pumpField(tester, text: 'אבגדה');
      controller.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();

      await rightClickAt(tester, tester.getCenter(find.byType(TextField)));

      expect(find.text('גזור'), findsNothing);
      expect(find.text('העתק'), findsNothing);
      expect(find.text('הדבק'), findsOneWidget);
      expect(find.text('בחר הכל'), findsOneWidget);
    },
  );

  testWidgets(
    'התפריט אינו מציג "בחר הכל" כששדה החיפוש ריק',
    (tester) async {
      await pumpField(tester, text: '');

      await rightClickAt(tester, tester.getCenter(find.byType(TextField)));

      expect(find.text('בחר הכל'), findsNothing);
      expect(find.text('הדבק'), findsOneWidget);
    },
  );

  testWidgets(
    'לחיצה ימנית ללא פוקוס מכווצת את הבחירה הפנימית של Flutter, '
    'אך גזירה עדיין פועלת על הבחירה שהייתה כשהתפריט נפתח',
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

      final controller = TextEditingController(text: 'אבגדה');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Directionality(
              textDirection: TextDirection.rtl,
              child: RtlTextField(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();
      // בכוונה בלי פוקוס: מדמה מצב בו כבר קיימת בחירה (למשל מגרירת עכבר
      // קודמת) אבל הפוקוס עבר משדה זה הלאה לפני הלחיצה הימנית.
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      await tester.pump();

      await rightClickAt(tester, tester.getCenter(find.byType(TextField)));

      // מוודא שהתרחיש שגילינו אכן קיים ברמת Flutter: לחיצה ימנית בלי פוקוס
      // מפעילה גם את הזיהוי המובנה ל-secondary tap, שמכווץ את הבחירה
      // הקיימת למיקום הלחיצה (ראו onSecondaryTap ב-text_selection.dart).
      expect(
        controller.selection.isCollapsed,
        isTrue,
        reason: 'מוודא שתנאי המרוץ שגרם לבאג עדיין קיים ברמת Flutter עצמו',
      );

      await tester.tap(find.text('גזור'));
      await tester.pumpAndSettle();

      expect(
        clipboardText,
        'בגד',
        reason:
            'גזירה חייבת לפעול על הבחירה שנלכדה בפתיחת התפריט, לא על מה '
            'שהתכווץ לאחר מכן על ידי הטיפול הפנימי של Flutter בלחיצה ימנית',
      );
      expect(controller.text, 'אה');
    },
  );
}
