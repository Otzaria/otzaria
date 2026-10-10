import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/rtl_hard_break_workaround.dart';

/// בודק את פונקציות הליבה של עוקף באג-הסמן (otzaria issue #1716,
/// flutter/flutter#178945): הרחבת \n בודד ל-\r\n וצמצום בחזרה, כולל מיפוי
/// offsets עקבי בשני הכיוונים.
void main() {
  String expandHardBreaks(String text) =>
      expandValue(TextEditingValue(text: text)).text;

  group('expandValue — טקסט', () {
    test('טקסט בלי שבירת שורה נשאר ללא שינוי', () {
      expect(expandHardBreaks('אבגדה'), 'אבגדה');
      expect(expandHardBreaks(''), '');
    });

    test('מרחיב \\n בודד ל-\\r\\n', () {
      expect(expandHardBreaks('אבג\nדהו'), 'אבג\r\nדהו');
    });

    test('\\n בתחילת הטקסט', () {
      expect(expandHardBreaks('\nאבג'), '\r\nאבג');
    });

    test('כמה שורות', () {
      expect(expandHardBreaks('א\nב\nג'), 'א\r\nב\r\nג');
    });

    test('אידמפוטנטי: \\r\\n קיים נשאר כפי שהוא', () {
      final once = expandHardBreaks('אבג\nדהו');
      expect(expandHardBreaks(once), once);
    });

    test('מעורב: \\r\\n קיים לצד \\n בודד חדש', () {
      expect(expandHardBreaks('א\r\nב\nג'), 'א\r\nב\r\nג');
    });
  });

  group('collapseHardBreaks', () {
    test('טקסט בלי \\r נשאר ללא שינוי', () {
      expect(collapseHardBreaks('אבגדה'), 'אבגדה');
    });

    test('הופך \\r\\n בחזרה ל-\\n', () {
      expect(collapseHardBreaks('אבג\r\nדהו'), 'אבג\nדהו');
    });

    test('הופך גם \\r בודד (סגנון Mac קלאסי) ל-\\n, לא מוחק אותו', () {
      expect(collapseHardBreaks('אב\rג'), 'אב\nג');
    });

    test('roundtrip: collapse(expand(x)) == x עבור טקסט נקי', () {
      const samples = ['', 'אבג', 'אבג\nדהו', '\nאבג', 'א\nב\nג\n'];
      for (final s in samples) {
        expect(collapseHardBreaks(expandHardBreaks(s)), s, reason: 'עבור "$s"');
      }
    });
  });

  group('snapOffsetOutOfCrlf', () {
    const expanded = 'אבג\r\nדהו'; // 0=א 1=ב 2=ג 3=\r 4=\n 5=ד 6=ה 7=ו

    test('offset באמצע ה-CRLF מתיישר לפני השבר', () {
      expect(snapOffsetOutOfCrlf(expanded, 4), 3);
    });

    test('offset שאינו באמצע CRLF נשאר ללא שינוי', () {
      expect(snapOffsetOutOfCrlf(expanded, 3), 3);
      expect(snapOffsetOutOfCrlf(expanded, 5), 5);
    });

    test('offset שלילי (sentinel) נשאר ללא שינוי', () {
      expect(snapOffsetOutOfCrlf(expanded, -1), -1);
    });
  });

  group('expandValue / collapseValue', () {
    test('מרחיב טקסט+בחירה יחד ובעקביות', () {
      const value = TextEditingValue(
        text: 'אבג\nדהו',
        selection: TextSelection.collapsed(offset: 4),
      );
      final expanded = expandValue(value);
      expect(expanded.text, 'אבג\r\nדהו');
      expect(expanded.selection, const TextSelection.collapsed(offset: 5));
    });

    test('offset ממש לפני ה-\\n (סוף "אבג") אינו זז בהרחבה', () {
      const value = TextEditingValue(
        text: 'אבג\nדהו',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(
        expandValue(value).selection,
        const TextSelection.collapsed(offset: 3),
      );
    });

    test('offset באמצע ה-CRLF מתיישר לפני השבר בצמצום', () {
      const value = TextEditingValue(
        text: 'אבג\r\nדהו',
        selection: TextSelection.collapsed(offset: 4),
      );
      expect(
        collapseValue(value).selection,
        const TextSelection.collapsed(offset: 3),
      );
    });

    test('ממפה גם composing, בנפרד מהבחירה', () {
      const value = TextEditingValue(
        text: 'אבג\nדהו',
        selection: TextSelection.collapsed(offset: 0),
        composing: TextRange(start: 4, end: 6),
      );
      final expanded = expandValue(value);
      expect(expanded.composing, const TextRange(start: 5, end: 7));
      expect(
        collapseValue(expanded).composing,
        const TextRange(start: 4, end: 6),
      );
    });

    test('בחירה/composing לא-תקינים (sentinel) נשארים ללא שינוי', () {
      const value = TextEditingValue(text: 'אבג\nדהו');
      final expanded = expandValue(value);
      expect(expanded.selection, const TextSelection.collapsed(offset: -1));
      expect(expanded.composing, TextRange.empty);
    });

    test('roundtrip: collapseValue(expandValue(x)) == x, לכל offset בטקסט', () {
      const clean = 'שורה א\nשורה ב';
      for (var o = 0; o <= clean.length; o++) {
        final value = TextEditingValue(
          text: clean,
          selection: TextSelection.collapsed(offset: o),
        );
        final roundTripped = collapseValue(expandValue(value));
        expect(roundTripped.text, clean, reason: 'offset $o');
        expect(roundTripped.selection.extentOffset, o, reason: 'offset $o');
      }
    });

    test('בלי \\n/\\r בטקסט — מחזיר את אותו ערך (ללא allocation מיותר)', () {
      const value = TextEditingValue(text: 'אבגדה');
      expect(identical(expandValue(value), value), isTrue);
      expect(identical(collapseValue(value), value), isTrue);
    });

    test('טקסט שכל שבירותיו כבר \\r\\n — הקלדה רגילה לא בונה ערך חדש', () {
      const value = TextEditingValue(
        text: 'שורה א\r\nשורה ב',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(identical(expandValue(value), value), isTrue);
    });
  });

  group('HardBreakInputFormatter', () {
    const formatter = HardBreakInputFormatter();

    test('בזמן composing של IME לא נוגע בערך', () {
      const value = TextEditingValue(
        text: 'אבג\nדה',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 4, end: 6),
      );
      expect(formatter.formatEditUpdate(TextEditingValue.empty, value), value);
    });

    TextEditingValue format(String text, int selectionOffset) =>
        formatter.formatEditUpdate(
          TextEditingValue.empty,
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: selectionOffset),
          ),
        );

    test('בלי \\n — מחזיר את אותו ערך (ללא שינוי)', () {
      const value = TextEditingValue(
        text: 'אבג',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(formatter.formatEditUpdate(TextEditingValue.empty, value), value);
    });

    test('Enter טרי: מרחיב מיד ומזיז את הסמן אחרי ה-CRLF', () {
      final result = format('אבג\n', 4);
      expect(result.text, 'אבג\r\n');
      expect(result.selection, const TextSelection.collapsed(offset: 5));
    });

    test('Enter נוסף בסוף טקסט שכבר מורחב מרחיב רק את החדש', () {
      final result = format('אבג\r\nדהו\n', 9);
      expect(result.text, 'אבג\r\nדהו\r\n');
      expect(result.selection, const TextSelection.collapsed(offset: 10));
    });
  });

  group('CleanSpaceFormatterAdapter', () {
    test('מגביל אורך לפי הטקסט הנקי, לא לפי האורך המורחב עם ה-\\r', () {
      final adapter = CleanSpaceFormatterAdapter([
        LengthLimitingTextInputFormatter(5),
      ]);
      // "אבג\nד" במרחב הגולמי הוא "אבג\r\nד" (6 תווים) אבל נקי הוא 5 — מתחת
      // למגבלה, ולכן לא אמור להיחתך.
      const raw = TextEditingValue(
        text: 'אבג\r\nד',
        selection: TextSelection.collapsed(offset: 6),
      );
      final result = adapter.formatEditUpdate(TextEditingValue.empty, raw);
      expect(collapseHardBreaks(result.text), 'אבג\nד');
    });

    test('טקסט נקי שחורג מהמגבלה נחתך, ואז מורחב מחדש אם יש שבירת שורה', () {
      final adapter = CleanSpaceFormatterAdapter([
        LengthLimitingTextInputFormatter(3),
      ]);
      const raw = TextEditingValue(
        text: 'אב\r\nגדה', // נקי: "אב\nגדה" (6 תווים) — חורג מ-3
        selection: TextSelection.collapsed(offset: 7),
      );
      final result = adapter.formatEditUpdate(TextEditingValue.empty, raw);
      expect(collapseHardBreaks(result.text).length, 3);
    });
  });
  group('cached newline mapping', () {
    test('selection-only edits reuse text in both directions', () {
      for (final length in [50000, 200000]) {
        final clean = '${'א\n' * (length ~/ 2)}😀';
        final expand = HardBreakValueMapper(expand: true);
        final collapse = HardBreakValueMapper(expand: false);
        final initial = TextEditingValue(text: clean);
        final raw = expand.map(initial);
        final normalized = collapse.map(raw);
        for (final offset in [0, 1, 2, length, clean.length]) {
          final moved = initial.copyWith(
            selection: TextSelection(
              baseOffset: clean.length,
              extentOffset: offset,
              affinity: TextAffinity.upstream,
              isDirectional: true,
            ),
          );
          final expanded = expand.map(moved);
          final collapsed = collapse.map(expanded);
          expect(identical(expanded.text, raw.text), isTrue);
          expect(identical(collapsed.text, normalized.text), isTrue);
          expect(collapsed, moved);
        }
        final changed = expand.map(const TextEditingValue(text: 'חדש\nטקסט'));
        expect(changed.text, 'חדש\r\nטקסט');
        expect(collapse.map(changed).text, 'חדש\nטקסט');
      }
    });
    test('UTF-16 offsets and reversed ranges survive every boundary', () {
      const text = 'א😀\n\nב🕎\n';
      for (var offset = 0; offset <= text.length; offset++) {
        final value = TextEditingValue(
          text: text,
          selection: TextSelection(
            baseOffset: text.length,
            extentOffset: offset,
            affinity: TextAffinity.upstream,
            isDirectional: true,
          ),
          composing: TextRange.collapsed(offset),
        );
        expect(collapseValue(expandValue(value)), value);
      }
    });
    test('identity adapter preserves composition with existing CRLF', () {
      final formatter = CleanSpaceFormatterAdapter([
        TextInputFormatter.withFunction((oldValue, newValue) => newValue),
      ]);
      const value = TextEditingValue(
        text: 'אב\r\nדה',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 4, end: 6),
      );
      expect(formatter.formatEditUpdate(TextEditingValue.empty, value), value);
    });
  });
}
