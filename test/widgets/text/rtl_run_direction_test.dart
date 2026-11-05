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
      double? width,
    }) async {
      final controller = TextEditingController(text: value);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: width,
                child: RtlTextField(
                  controller: controller,
                  maxLines: multiline ? null : 1,
                ),
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
        final selection = editable.textEditingValue.selection;
        expect(
          CharacterBoundary(
            editable.textEditingValue.text,
          ).getLeadingTextBoundaryAt(selection.extentOffset),
          selection.extentOffset,
          reason: 'הסמן חייב להישאר בגבול גרפמה, גם בסוף שורה',
        );
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

    for (final (name, value, multiline, width, visualWords)
        in <(String, String, bool, double?, bool)>[
          ('תג לטיני בטקסט עברי', 'אב <b>גד</b>', false, null, true),
          ('מילה באנגלית בטקסט עברי', 'אב hello גד', false, null, true),
          ('שדה רב-שורתי', 'אב hello גד\nשלום <b>עולם</b>', true, null, true),
          (
            'שורה ריקה ושורה שמתחילה בלטינית',
            'אבג\n\nhello דה',
            true,
            null,
            true,
          ),
          (
            'גלישת שורות בעברית',
            'אבגדה וזחטי כלמנס עפקצר שתאבג דהוזח טיכלמ נסעפצ',
            true,
            160,
            true,
          ),
          // פעולת המילה נשמרת כמקודם במקרה הזה ונבדקת בנפרד להלן.
          ('מילה לטינית נגלשת', 'אב ${'abcdefgh' * 5} גד', true, 160, false),
          ('מילה נגלשת עם חילופי כיוון רבים', '${'אa' * 20}א', true, 160, true),
          (
            'מילה מעורבת עם סימנים משולבים',
            'אָב${'a\u0301' * 12}גּד',
            false,
            null,
            true,
          ),
        ]) {
      testWidgets(
        '$name: ${visualWords ? 'חצים, Shift ומילה' : 'חצים ו־Shift'} עוברים את הטקסט בשני הכיוונים בלי להיתקע',
        (tester) async {
          final editable = await fieldAtStart(
            tester,
            value,
            multiline: multiline,
            width: width,
          );
          final length = editable.textEditingValue.text.length;
          final graphemes = editable.textEditingValue.text.characters.length;
          final word = usesAltForWordNavigation()
              ? LogicalKeyboardKey.altLeft
              : LogicalKeyboardKey.controlLeft;

          for (final modifiers in [
            <LogicalKeyboardKey>[],
            [LogicalKeyboardKey.shiftLeft],
            if (visualWords) [word],
            if (visualWords) [word, LogicalKeyboardKey.shiftLeft],
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
            if (modifiers.isEmpty && width == null) {
              expect([leftMoves, rightMoves], [graphemes, graphemes]);
            }
          }
        },
        variant: TargetPlatformVariant({
          TargetPlatform.windows,
          TargetPlatform.macOS,
          TargetPlatform.linux,
        }),
      );
    }
    testWidgets(
      'מילה לטינית נגלשת שומרת את פעולת המילה המובנית, גם עם Shift',
      (tester) async {
        final editable = await fieldAtStart(
          tester,
          'אב ${'abcdefgh' * 5} גד',
          multiline: true,
          width: 160,
        );
        final word = usesAltForWordNavigation()
            ? LogicalKeyboardKey.altLeft
            : LogicalKeyboardKey.controlLeft;
        for (final right in [false, true]) {
          for (final shift in [false, true]) {
            editable.widget.controller.selection =
                const TextSelection.collapsed(offset: 20);
            await tester.pump();
            await tester.sendKeyDownEvent(word);
            if (shift) {
              await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
            }
            await tester.sendKeyEvent(
              right
                  ? LogicalKeyboardKey.arrowRight
                  : LogicalKeyboardKey.arrowLeft,
            );
            if (shift) {
              await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
            }
            await tester.sendKeyUpEvent(word);
            await tester.pump();
            final expected = right ? 43 : 3;
            expect(
              editable.textEditingValue.selection,
              TextSelection(
                baseOffset: shift ? 20 : expected,
                extentOffset: expected,
              ),
            );
          }
        }
      },
      variant: TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }),
    );
    testWidgets(
      'קיצור מילה חוצה את כל המילה הנגלשת, גם עם Shift',
      (tester) async {
        final value = 'אבגדה' * 16;
        final editable = await fieldAtStart(
          tester,
          value,
          multiline: true,
          width: 160,
        );
        final word = usesAltForWordNavigation()
            ? LogicalKeyboardKey.altLeft
            : LogicalKeyboardKey.controlLeft;
        for (final shift in [false, true]) {
          await tester.sendKeyDownEvent(word);
          if (shift) {
            await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pump();
          final selection = editable.textEditingValue.selection;
          expect(selection.extentOffset, value.length);
          expect(selection.baseOffset, shift ? 0 : value.length);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          expect(
            editable.textEditingValue.selection,
            const TextSelection.collapsed(offset: 0),
          );
          if (shift) {
            await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          }
          await tester.sendKeyUpEvent(word);
        }
      },
      variant: TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }),
    );
  });
}
