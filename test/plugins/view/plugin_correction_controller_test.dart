import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_correction_controller.dart';

void main() {
  _nikudTests();
  _nikudFormatTests();
  _highlightTests();
  for (final source in ['<br>אב', 'אב<br>', '<br>אב<br>']) {
    test('המרה סימטרית גם כשהתיקון הסיר את שולי $source', () {
      final controller = PluginCorrectionController(source);
      addTearDown(controller.dispose);
      for (final canonical in [controller.source.plain, 'אם', '', ' אמת ']) {
        expect(
          controller.forService(controller.forEditor(canonical)),
          canonical,
        );
      }
    });
  }

  test('עדכון מקור מסנכרן טקסט ושוליים גם כשהטקסט הגלוי זהה', () {
    final controller = PluginCorrectionController('<b>אב</b>');
    addTearDown(controller.dispose);
    controller.setSource('<p>אב</p>');
    expect(controller.text, 'אב');
    expect(controller.forService(controller.text), ' אב ');
    controller.setSource('<i>גד</i>');
    expect(controller.text, 'גד');
    expect(controller.forService(controller.text), 'גד');
  });

  test('הד חוזר של אותו מקור משמר בחירה ו-IME', () {
    const source = '<b>אב</b>';
    final controller = PluginCorrectionController(source);
    addTearDown(controller.dispose);
    const editing = TextEditingValue(
      text: 'אגב',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    controller.value = editing;
    controller.setSource(source);
    expect(controller.value, editing);
  });

  group('עיצוב בעורך', () {
    test('תגיות נתמכות ממופות לעיצוב התווים, ותגיות בלוק בקצוות מוסתרות', () {
      final controller = PluginCorrectionController(
        '<p>א<b>ב<i>ג</i></b><u>ד</u><big>ה</big><small>ו</small>'
        '<a href="x">ז</a><s>ח</s><span>ט</span></p>',
      );
      addTearDown(controller.dispose);
      expect(controller.text, 'אבגדהוזחט');
      final formats = controller.formats;
      expect(formats[0].bold, isFalse);
      expect(formats[1].bold, isTrue);
      expect(formats[1].italic, isFalse);
      expect(formats[2].bold && formats[2].italic, isTrue);
      expect(formats[3].underline, isTrue);
      expect(formats[4].scale, greaterThan(1));
      expect(formats[5].scale, lessThan(1));
      expect(formats[6].link, isTrue);
      expect(formats[7].strike, isTrue);
      expect(formats[8], formats[0]);
    });

    test(
      'הקלדה בתוך מילה מודגשת יורשת הדגשה, ובסוף ריצה יורשת מהתו שלפניה',
      () {
        final controller = PluginCorrectionController('א <b>בגד</b> ה');
        addTearDown(controller.dispose);
        controller.text = 'א בגXד ה';
        expect(controller.formats[4].bold, isTrue);
        controller.text = 'א בגXדY ה';
        expect(controller.formats[6].bold, isTrue);
        expect(controller.formats[8].bold, isFalse);
      },
    );

    test('החלפת מילה יורשת את עיצוב המילה שהוחלפה, ומחיקה שומרת את השאר', () {
      final controller = PluginCorrectionController('<i>אב</i> גד <b>הו</b>');
      addTearDown(controller.dispose);
      controller.text = 'אב חדש הו';
      expect(controller.formats.sublist(3, 6).every((f) => !f.bold), isTrue);
      controller.text = 'אב הו';
      expect(controller.formats[0].italic, isTrue);
      expect(controller.formats[3].bold, isTrue);
      expect(controller.formats[3].italic, isFalse);
    });

    test('הוספה בתחילת הטקסט יורשת מהתו הראשון', () {
      final controller = PluginCorrectionController('<b>אב</b> גד');
      addTearDown(controller.dispose);
      controller.text = 'Xאב גד';
      expect(controller.formats.first.bold, isTrue);
      expect(controller.formats[3].bold, isFalse);
    });

    test('המיפוי בין עורך לשירות לא משתנה בגלל העיצוב', () {
      const source = '<p><b>אב</b> גד</p>';
      final controller = PluginCorrectionController(source);
      addTearDown(controller.dispose);
      controller.text = 'אם גד';
      expect(controller.forService(controller.text), ' אם גד ');
      expect(controller.formats.length, controller.text.length);
    });

    testWidgets('טווח IME מסומן בקו תחתון בנוסף לעיצוב המקור', (tester) async {
      final controller = PluginCorrectionController('<s>אב</s>גד');
      addTearDown(controller.dispose);
      controller.value = const TextEditingValue(
        text: 'אבגד',
        composing: TextRange(start: 1, end: 3),
      );
      late TextSpan span;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              span = controller.buildTextSpan(
                context: context,
                style: const TextStyle(fontSize: 20),
                withComposing: true,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      final children = span.children!.cast<TextSpan>();
      expect(children.map((c) => c.text), ['א', 'ב', 'ג', 'ד']);
      expect(children[0].style!.decoration, TextDecoration.lineThrough);
      expect(
        children[1].style!.decoration,
        TextDecoration.combine([
          TextDecoration.underline,
          TextDecoration.lineThrough,
        ]),
      );
      expect(children[2].style!.decoration, TextDecoration.underline);
      expect(children[3].style, isNull);
    });

    testWidgets('פסקה ללא עיצוב נבנית כמו בקר רגיל', (tester) async {
      final controller = PluginCorrectionController('<p>אב גד</p>');
      addTearDown(controller.dispose);
      late TextSpan span;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              span = controller.buildTextSpan(
                context: context,
                withComposing: false,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(span.children, isNull);
      expect(span.text, 'אב גד');
    });

    test('ביטול מחיקה או החזרת הטקסט כולו משחזרים את העיצוב', () {
      final controller = PluginCorrectionController('א <b>בגד</b> ה');
      addTearDown(controller.dispose);
      controller.text = 'א  ה';
      controller.text = 'א בגד ה';
      expect(controller.formats[2].bold, isTrue);
      controller.text = '';
      controller.text = 'א בגד ה';
      expect(controller.formats.sublist(2, 5).every((f) => f.bold), isTrue);
      expect(controller.formats[0].bold, isFalse);
    });

    test('מחיקת המופע הראשון משאירה את סגנון המופע השני', () {
      final controller = PluginCorrectionController('<b>אב</b> <i>אב</i>');
      addTearDown(controller.dispose);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );
      controller.value = const TextEditingValue(
        text: 'אב',
        selection: TextSelection.collapsed(offset: 0),
      );
      expect(controller.formats.every((f) => !f.bold && f.italic), isTrue);
    });

    test('עריכות בקצוות מילה אינן מעצבות תו פנימי שלא נערך', () {
      final controller = PluginCorrectionController('<b>א</b>בג');
      addTearDown(controller.dispose);
      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 3,
      );
      controller.value = const TextEditingValue(
        text: 'אבד',
        selection: TextSelection.collapsed(offset: 3),
      );
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 1,
      );
      controller.value = const TextEditingValue(
        text: 'הבד',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(controller.formats.map((f) => f.bold), [true, false, false]);
    });

    for (final backspace in [true, false]) {
      test('מחיקת מילה חוזרת ללא בחירה, backspace=$backspace', () {
        final controller = PluginCorrectionController('<b>אב</b> אב');
        addTearDown(controller.dispose);
        controller.selection = TextSelection.collapsed(
          offset: backspace ? 3 : 0,
        );
        controller.value = const TextEditingValue(
          text: 'אב',
          selection: TextSelection.collapsed(offset: 0),
        );
        expect(controller.formats.every((f) => !f.bold), isTrue);
      });
    }

    test('ערכים בעלי אותו נוסח ובחירה משחזרים כל אחד את עיצובו', () {
      final controller = PluginCorrectionController('<b>אב</b> אב');
      addTearDown(controller.dispose);
      final original = controller.value;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );
      controller.value = const TextEditingValue(
        text: 'אב',
        selection: TextSelection.collapsed(offset: 0),
      );
      final plain = controller.value;
      controller.value = original;
      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 5,
      );
      controller.value = const TextEditingValue(
        text: 'אב',
        selection: TextSelection.collapsed(offset: 0),
      );
      final bold = controller.value;
      expect(controller.formats.every((f) => f.bold), isTrue);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.value = plain;
      expect(controller.formats.every((f) => !f.bold), isTrue);
      expect(notifications, 1);
      controller.value = bold.copyWith(composing: TextRange.empty);
      expect(controller.formats.every((f) => f.bold), isTrue);
      expect(notifications, 2);
      controller.value = plain.copyWith(
        selection: const TextSelection.collapsed(offset: 1),
      );
      expect(controller.formats.every((f) => !f.bold), isTrue);
    });

    test('טקסט שהודבק יורש מהטווח המוחלף גם אם הופיע בעבר בסגנון אחר', () {
      final controller = PluginCorrectionController('<b>אב</b> גד');
      addTearDown(controller.dispose);
      controller.selection = const TextSelection(
        baseOffset: 3,
        extentOffset: 5,
      );
      controller.value = const TextEditingValue(
        text: 'אב אב',
        selection: TextSelection.collapsed(offset: 5),
      );
      expect(controller.formats.map((f) => f.bold), [
        true,
        true,
        false,
        false,
        false,
      ]);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      controller.value = const TextEditingValue(
        text: 'אב גד',
        selection: TextSelection.collapsed(offset: 5),
      );
      expect(controller.formats.map((f) => f.bold), [
        true,
        true,
        false,
        false,
        false,
      ]);
    });

    test('החלפת מקור באותו נוסח אינה משחזרת snapshot מהמקור הקודם', () {
      final controller = PluginCorrectionController('<b>אב</b>');
      addTearDown(controller.dispose);
      final old = controller.value;
      controller.setSource('<i>אב</i>');
      expect(controller.formats.every((f) => !f.bold && f.italic), isTrue);
      controller.value = old;
      expect(controller.formats.every((f) => !f.bold && f.italic), isTrue);
    });

    test('IME מחליף רק את המופע שב-composing ומשמר שכנים', () {
      final controller = PluginCorrectionController('<b>אב</b> אב');
      addTearDown(controller.dispose);
      controller.value = const TextEditingValue(
        text: 'אב אב',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 2),
      );
      controller.value = const TextEditingValue(
        text: 'אבX אב',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      );
      expect(controller.formats.map((f) => f.bold), [
        true,
        true,
        true,
        false,
        false,
        false,
      ]);
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );
      controller.value = const TextEditingValue(
        text: 'אב',
        selection: TextSelection.collapsed(offset: 0),
      );
      expect(controller.formats.every((f) => !f.bold), isTrue);
    });

    test('שחזור טיוטה עם מופע חוזר אינו מנחש שהמופע המודגש שרד', () {
      final controller = PluginCorrectionController('<b>אב</b> אב <i>גד</i>');
      addTearDown(controller.dispose);
      controller.restoreDraftValue(const TextEditingValue(text: 'אב גד'));
      expect(controller.formats.take(2).every((f) => !f.bold), isTrue);
      expect(controller.formats.skip(3).every((f) => f.italic), isTrue);
    });

    test('שחזור טיוטה משמר מופעים חוזרים כשנערכה רק מילה אחרת', () {
      final controller = PluginCorrectionController('<b>אב</b> אב גד');
      addTearDown(controller.dispose);
      controller.restoreDraftValue(const TextEditingValue(text: 'אב אב גה'));
      expect(controller.formats.map((f) => f.bold), [
        true,
        true,
        false,
        false,
        false,
        false,
        false,
        false,
      ]);
    });

    test('שחזור מילה מעורבת אינו מעצב תו פנימי שלא השתנה', () {
      final controller = PluginCorrectionController('<b>א</b>בג');
      addTearDown(controller.dispose);
      controller.restoreDraftValue(const TextEditingValue(text: 'הבד'));
      expect(controller.formats.every((f) => !f.bold), isTrue);
    });

    test('רווח של br בתוך ריצה מעוצבת מקבל את עיצובה', () {
      final controller = PluginCorrectionController('<u>א<br>ב</u>');
      addTearDown(controller.dispose);
      expect(controller.formats.every((f) => f.underline), isTrue);
    });

    test('תגית שנסגרת שלא לפי הסדר סוגרת רק את עצמה', () {
      final controller = PluginCorrectionController('<b>א<i>ב</b>ג</i>ד');
      addTearDown(controller.dispose);
      expect(controller.text, 'אבגד');
      expect(controller.formats[2].italic, isTrue);
      expect(controller.formats[2].bold, isFalse);
      expect(controller.formats[3].italic, isFalse);
    });
  });
}

void _nikudTests() {
  const base = 'שָׁלוֹם עוֹלָם';
  test('ספר ללא ניקוד: העורך מציג בלי ניקוד והמקור נשמר', () {
    final controller = PluginCorrectionController(base, hideNikud: true);
    addTearDown(controller.dispose);
    expect(controller.text, 'שלום עולם');
    expect(controller.forService(controller.text), base);
  });

  test('ספר ללא ניקוד: עריכה משמרת ניקוד של אותיות שלא נגעו בהן', () {
    final controller = PluginCorrectionController(base, hideNikud: true);
    addTearDown(controller.dispose);
    // הוספת תו בסוף "עולם": הניקוד של כל האותיות הקיימות נשאר.
    expect(
      controller.forService('שלום עולמם'),
      'שָׁלוֹם עוֹלָמם',
    );
    // הוספת תו בסוף המילה הראשונה אחרי האות המנוקדת.
    expect(controller.forService('שלומא עולם'), 'שָׁלוֹמא עוֹלָם');
    // מחיקת מילה שלמה.
    expect(controller.forService('שלום '), 'שָׁלוֹם ');
    // מחיקת הכול.
    expect(controller.forService(''), '');
  });

  test('ספר ללא ניקוד: מקף ופסק אינם נמחקים', () {
    final controller = PluginCorrectionController(
      'אָב־גָד ׀ הוּ',
      hideNikud: true,
    );
    addTearDown(controller.dispose);
    expect(controller.text, 'אב־גד ׀ הו');
  });

  test('ספר עם ניקוד: ללא שינוי התנהגות', () {
    final controller = PluginCorrectionController(base);
    addTearDown(controller.dispose);
    expect(controller.text, base);
    expect(controller.forService('x$base'), 'x$base');
  });

  test('forService טהורה ו-forEditor מעדכנת בסיס אחרי עריכה', () {
    final controller = PluginCorrectionController(base, hideNikud: true);
    addTearDown(controller.dispose);
    expect(controller.forService('שלום'), controller.forService('שלום'));
    final edited = controller.forService('שלום ');
    expect(controller.forEditor(edited), 'שלום ');
    expect(controller.forService('שלום ב'), 'שָׁלוֹם ב');
  });

  test('ניקוד שהוקלד בספר מוסתר אינו מוכפל ואינו משבש עריכות הבאות', () {
    final controller = PluginCorrectionController(
      'אָבֶג',
      hideNikud: true,
    );
    addTearDown(controller.dispose);
    // הדבקת קמץ נוסף אחרי האלף.
    expect(controller.forService('אָבג'), 'אָבֶג');
    expect(controller.forService('אבגד'), 'אָבֶגד');
  });

  test('surrogate pairs אינם נחתכים', () {
    final controller = PluginCorrectionController('א😀ב', hideNikud: true);
    addTearDown(controller.dispose);
    expect(controller.forService('א😁ב'), 'א😁ב');
  });
}

void _nikudFormatTests() {
  const source = 'אב <b>שָׁלוֹם</b> גד';

  test('ספר ללא ניקוד: העיצוב מיושר לטקסט שבעורך', () {
    final controller = PluginCorrectionController(source, hideNikud: true);
    addTearDown(controller.dispose);
    expect(controller.text, 'אב שלום גד');
    expect(controller.formats, hasLength(controller.text.length));
    expect(controller.formats.map((f) => f.bold), [
      for (var i = 0; i < controller.text.length; i++) i >= 3 && i <= 6,
    ]);
  });

  test('ספר ללא ניקוד: מחיקה והוספה שומרות על עיצוב מיושר וניקוד במקור', () {
    final controller = PluginCorrectionController(source, hideNikud: true);
    addTearDown(controller.dispose);
    controller.value = const TextEditingValue(
      text: 'אב שלו גד',
      selection: TextSelection.collapsed(offset: 6),
    );
    expect(controller.formats, hasLength(controller.text.length));
    expect(controller.formats[5].bold, isTrue);
    expect(controller.formats[7].bold, isFalse);
    expect(controller.forService(controller.text), 'אב שָׁלוֹ גד');
    controller.value = const TextEditingValue(
      text: 'אב שלוח גד',
      selection: TextSelection.collapsed(offset: 7),
    );
    expect(controller.formats, hasLength(controller.text.length));
    expect(controller.formats[6].bold, isTrue);
    expect(controller.forService(controller.text), 'אב שָׁלוֹח גד');
  });

  test('שינוי hideNikud אחרי היצירה גוזר מחדש את הטקסט והעיצוב', () {
    final controller = PluginCorrectionController(source);
    addTearDown(controller.dispose);
    expect(controller.formats, hasLength('אב שָׁלוֹם גד'.length));
    controller.hideNikud = true;
    expect(controller.text, 'אב שלום גד');
    expect(controller.formats, hasLength(controller.text.length));
    expect(controller.formats[3].bold, isTrue);
    controller.hideNikud = false;
    expect(controller.text, 'אב שָׁלוֹם גד');
    expect(controller.formats, hasLength(controller.text.length));
  });

  test('שחזור טיוטה בספר ללא ניקוד שומר עיצוב מיושר', () {
    final controller = PluginCorrectionController(source, hideNikud: true);
    addTearDown(controller.dispose);
    controller.restoreDraftValue(const TextEditingValue(text: 'אב שלום גדה'));
    expect(controller.formats, hasLength(controller.text.length));
    expect(controller.formats[3].bold, isTrue);
  });
}

void _highlightTests() {
  Future<TextSpan> build(
    WidgetTester tester,
    PluginCorrectionController controller,
  ) async {
    late TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            span = controller.buildTextSpan(
              context: context,
              style: const TextStyle(fontSize: 20),
              withComposing: false,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    return span;
  }

  testWidgets('הדגשת חיפוש נחתכת בגבולות העיצוב ושומרת עליו', (tester) async {
    final controller = PluginCorrectionController('אב <b>גד</b> הו')
      ..highlightText = 'ב ג';
    addTearDown(controller.dispose);
    final span = await build(tester, controller);
    final leaves = span.children!.cast<TextSpan>();
    expect(leaves.map((l) => l.text).join(), 'אב גד הו');
    final marked = leaves.where((l) => l.style?.color != null).toList();
    expect(marked.map((l) => l.text), ['ב ', 'ג']);
    expect(marked[0].style?.fontWeight, isNot(FontWeight.bold));
    expect(marked[1].style?.fontWeight, FontWeight.bold);
  });

  testWidgets('עלי התצוגה הרגילה מחליפים את העיצוב רק כשהטקסט זהה להם', (
    tester,
  ) async {
    const own = TextStyle(fontStyle: FontStyle.italic);
    final controller = PluginCorrectionController('אבג')
      ..readingLeaves = (text) =>
          text == 'אבג' ? [const TextSpan(text: 'אבג', style: own)] : null;
    addTearDown(controller.dispose);
    var span = await build(tester, controller);
    expect(span.children!.single.style, own);
    controller.value = const TextEditingValue(text: 'אבגד');
    span = await build(tester, controller);
    expect(span.children, isNull);
    expect(span.toPlainText(), 'אבגד');
  });

  testWidgets('הדגשת חיפוש מונחת על עלי התצוגה הרגילה', (tester) async {
    const own = TextStyle(fontStyle: FontStyle.italic);
    final controller = PluginCorrectionController('אבג')
      ..highlightText = 'ב'
      ..readingLeaves = (text) => [TextSpan(text: text, style: own)];
    addTearDown(controller.dispose);
    final span = await build(tester, controller);
    final leaves = span.children!.cast<TextSpan>();
    expect(leaves.map((l) => l.text), ['א', 'ב', 'ג']);
    expect(leaves[1].style?.fontStyle, FontStyle.italic);
    expect(leaves[1].style?.color, isNotNull);
    expect(leaves[0].style?.color, isNull);
  });
}
