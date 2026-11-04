import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

void main() {
  Future<TextEditingController> focusedField(
    WidgetTester tester,
    String value,
    int offset,
  ) async {
    final controller = TextEditingController(text: value);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: RtlTextField(controller: controller)),
        ),
      ),
    );
    await tester.tap(find.byType(RtlTextField));
    await tester.pump();
    controller.selection = TextSelection.collapsed(offset: offset);
    await tester.pump();
    return controller;
  }

  for (final (name, value, offset, key, expected)
      in <(String, String, int, LogicalKeyboardKey, int)>[
        ('עברית: ימינה', 'שלום עולם', 3, LogicalKeyboardKey.arrowRight, 2),
        ('עברית: שמאלה', 'שלום עולם', 3, LogicalKeyboardKey.arrowLeft, 4),
        (
          'אנגלית: ימינה',
          'שלום hello עולם',
          7,
          LogicalKeyboardKey.arrowRight,
          8,
        ),
        ('תג: ימינה', 'בראשית <big>ברא', 10, LogicalKeyboardKey.arrowRight, 11),
        (
          'תחילת תג: ימינה',
          'בראשית <big>ברא',
          8,
          LogicalKeyboardKey.arrowRight,
          9,
        ),
        ('מספר: ימינה', 'פרק 12 פסוק', 5, LogicalKeyboardKey.arrowRight, 6),
        ('מספר: שמאלה', 'פרק 12 פסוק', 5, LogicalKeyboardKey.arrowLeft, 4),
        (
          'תחילת מספר: ימינה',
          'פרק 12 פסוק',
          4,
          LogicalKeyboardKey.arrowRight,
          5,
        ),
        ('מספר בתחילת השדה', '123 אב', 1, LogicalKeyboardKey.arrowRight, 2),
        (
          'מספר עם פסיק',
          'פרק 12,345 פסוק',
          7,
          LogicalKeyboardKey.arrowRight,
          8,
        ),
        (
          'שעה: אחרי הנקודתיים',
          'פרק 12:34 פסוק',
          7,
          LogicalKeyboardKey.arrowRight,
          8,
        ),
        (
          'קירילית: ימינה',
          'שלום мир עולם',
          6,
          LogicalKeyboardKey.arrowRight,
          7,
        ),
      ]) {
    testWidgets(name, (tester) async {
      final controller = await focusedField(tester, value, offset);
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(controller.selection.extentOffset, expected);
    });
  }

  testWidgets('Shift+ימינה בתוך מספר מרחיב בחירה לכיוון הנראה', (tester) async {
    final controller = await focusedField(tester, 'פרק 12 פסוק', 5);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(
      controller.selection,
      const TextSelection(baseOffset: 5, extentOffset: 6),
    );
  });

  testWidgets('Shift+שמאלה בתוך מספר מרחיב בחירה לכיוון הנראה', (tester) async {
    final controller = await focusedField(tester, 'פרק 12 פסוק', 5);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(
      controller.selection,
      const TextSelection(baseOffset: 5, extentOffset: 4),
    );
  });

  testWidgets('ניווט מילה בתוך מספר פונה לכיוון הנראה', (tester) async {
    final controller = await focusedField(tester, 'פרק 12 פסוק', 5);
    final modifier = usesAltForWordNavigation()
        ? LogicalKeyboardKey.altLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    expect(controller.selection.extentOffset, greaterThan(5));
  });

  testWidgets('ניווט בתוך רצף ספרות ארוך', (tester) async {
    final controller = await focusedField(
      tester,
      'אב ${'1' * 20000} גד',
      10000,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(controller.selection.extentOffset, 10001);
  });

  group('לחיצות חוזרות במעבר בין עברית ללטינית (issue #3445)', () {
    Future<EditableTextState> fieldAtStart(
      WidgetTester tester,
      String value, {
      required bool multiline,
    }) async {
      final controller = TextEditingController(text: value);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: RtlTextField(
                controller: controller,
                maxLines: multiline ? null : 1,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(RtlTextField));
      await tester.pump();
      controller.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      return tester.state<EditableTextState>(find.byType(EditableText));
    }

    // המקום החזותי של קצה הבחירה. עם Shift משתמשים ב-affinity השמור, כי
    // `selection.extent` של בחירה פתוחה נצמד תמיד לטקסט הנבחר.
    Offset caretSpot(EditableTextState editable) {
      final selection = editable.textEditingValue.selection;
      final rect = editable.renderEditable.getLocalRectForCaret(
        TextPosition(
          offset: selection.extentOffset,
          affinity: selection.affinity,
        ),
      );
      return Offset(rect.left.roundToDouble(), rect.top.roundToDouble());
    }

    /// לוחץ על [key] עד שהסמן נעצר ומחזיר את מספר הצעדים. כל לחיצה חייבת
    /// להזיז את הסמן לכיוון החץ (באותה שורה) ולמקום שלא היה בו קודם.
    Future<int> walk(
      WidgetTester tester,
      EditableTextState editable,
      LogicalKeyboardKey key,
      List<LogicalKeyboardKey> modifiers,
    ) async {
      final toLeft = key == LogicalKeyboardKey.arrowLeft;
      final visited = [caretSpot(editable)];
      final limit = 2 * editable.textEditingValue.text.length + 2;
      for (var press = 1; press <= limit; press++) {
        for (final modifier in modifiers) {
          await tester.sendKeyDownEvent(modifier);
        }
        await tester.sendKeyEvent(key);
        for (final modifier in modifiers.reversed) {
          await tester.sendKeyUpEvent(modifier);
        }
        await tester.pump();
        final spot = caretSpot(editable);
        final last = visited.last;
        if (spot == last) return press - 1;
        expect(
          visited,
          isNot(contains(spot)),
          reason: 'לחיצה $press החזירה את הסמן למקום שכבר עבר בו',
        );
        if (spot.dy == last.dy) {
          expect(
            toLeft ? spot.dx < last.dx : spot.dx > last.dx,
            isTrue,
            reason: 'לחיצה $press הזיזה את הסמן הפוך לכיוון החץ',
          );
        }
        visited.add(spot);
      }
      fail('הסמן לא נעצר אחרי $limit לחיצות');
    }

    for (final (name, value, multiline) in <(String, String, bool)>[
      ('תג לטיני בטקסט עברי', 'אב <b>גד</b>', false),
      ('מילה באנגלית בטקסט עברי', 'אב hello גד', false),
      ('שדה רב-שורתי', 'אב hello גד\nשלום <b>עולם</b>', true),
      ('שורה ריקה ושורה שמתחילה בלטינית', 'אבג\n\nhello דה', true),
    ]) {
      testWidgets(
        '$name: חצים, Shift ומילה עוברים את הטקסט בשני הכיוונים בלי להיתקע',
        (tester) async {
          final editable = await fieldAtStart(
            tester,
            value,
            multiline: multiline,
          );
          final length = editable.textEditingValue.text.length;
          final graphemes = editable.textEditingValue.text.characters.length;
          final word = usesAltForWordNavigation()
              ? LogicalKeyboardKey.altLeft
              : LogicalKeyboardKey.controlLeft;

          for (final modifiers in [
            <LogicalKeyboardKey>[],
            [LogicalKeyboardKey.shiftLeft],
            [word],
          ]) {
            final leftMoves = await walk(
              tester,
              editable,
              LogicalKeyboardKey.arrowLeft,
              modifiers,
            );
            final selection = editable.textEditingValue.selection;
            final shift = modifiers.contains(LogicalKeyboardKey.shiftLeft);
            expect(selection.extentOffset, length, reason: '$modifiers');
            expect(selection.baseOffset, shift ? 0 : length);

            final rightMoves = await walk(
              tester,
              editable,
              LogicalKeyboardKey.arrowRight,
              modifiers,
            );
            expect(
              editable.textEditingValue.selection,
              const TextSelection.collapsed(offset: 0),
              reason: '$modifiers',
            );
            // חץ בלי מקש נוסף נעצר בכל מיקום חזותי, בלי לדלג על קטע.
            if (modifiers.isEmpty) {
              expect([leftMoves, rightMoves], [graphemes, graphemes]);
            }
          }
        },
        variant: TargetPlatformVariant({
          TargetPlatform.windows,
          TargetPlatform.macOS,
        }),
      );
    }
  });
}
