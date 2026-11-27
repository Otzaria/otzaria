import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_correction_controller.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

void main() {
  for (final source in ['<br>אב', 'אב<br>', '<br>אב<br>']) {
    test('המרה סימטרית גם כשהתיקון הסיר את שולי $source', () {
      final controller = PluginCorrectionController(source);
      addTearDown(controller.dispose);
      for (final canonical in [controller.source.plain, 'אם', '', ' אמת ']) {
        controller.restoreCanonical(canonical);
        expect(controller.canonical, canonical);
      }
    });
  }

  test('עדכון מקור מסנכרן טקסט ושוליים גם כשהטקסט הגלוי זהה', () {
    final controller = PluginCorrectionController('<b>אב</b>');
    addTearDown(controller.dispose);
    controller.setSource('<p>אב</p>');
    expect(controller.text, 'אב');
    expect(controller.canonical, ' אב ');
    controller.setSource('<i>גד</i>');
    expect(controller.text, 'גד');
    expect(controller.canonical, 'גד');
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
      expect(controller.canonical, ' אם גד ');
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
      controller.restoreCanonical('אב גד');
      expect(controller.formats.take(2).every((f) => !f.bold), isTrue);
      expect(controller.formats.skip(3).every((f) => f.italic), isTrue);
    });

    test('שחזור טיוטה משמר מופעים חוזרים כשנערכה רק מילה אחרת', () {
      final controller = PluginCorrectionController('<b>אב</b> אב גד');
      addTearDown(controller.dispose);
      controller.restoreCanonical('אב אב גה');
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
      controller.restoreCanonical('הבד');
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

  group('הסתרת ניקוד וטעמים', () {
    const patah = '\u05B7';
    const holam = '\u05B9';
    const samples = [
      'בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֣ת־הַשָּׁמַ֔יִם',
      'אב ׀ גד',
      'אב־׀גד ׀',
    ];

    for (final sample in samples) {
      for (final nikud in [false, true]) {
        for (final teamim in [false, true]) {
          test('מחיקת כל תו בנפרד: "$sample" ניקוד=$nikud טעמים=$teamim', () {
            final shown = utils.removeMarks(
              sample,
              nikud: nikud,
              teamim: teamim,
            );
            for (var i = 0; i < shown.length; i++) {
              final controller = PluginCorrectionController(
                sample,
                removeNikud: nikud,
                removeTeamim: teamim,
              );
              addTearDown(controller.dispose);
              expect(controller.text, shown);
              controller.value = TextEditingValue(
                text: shown.replaceRange(i, i + 1, ''),
                selection: TextSelection.collapsed(offset: i),
              );
              // מה שהעורך מציג אחרי המחיקה הוא מה שהקורא יציג מהמקור שנשמר.
              expect(
                utils.removeMarks(
                  controller.canonical,
                  nikud: nikud,
                  teamim: teamim,
                ),
                controller.text,
                reason: 'מחיקת התו $i',
              );
            }
          });
        }
      }
    }

    test('עריכה בלי סימון בחירה מעגנת את הטווח בסמן החדש', () {
      final controller = PluginCorrectionController(
        'ב$patahב$holam',
        removeNikud: true,
      );
      addTearDown(controller.dispose);
      controller.value = const TextEditingValue(
        text: 'ב',
        selection: TextSelection.collapsed(offset: 0),
      );
      expect(controller.canonical, 'ב$holam');
    });

    test('ערך מההיסטוריה שנוצר לפני החלפת ההסתרה מוצג לפי ההסתרה הנוכחית', () {
      final controller = PluginCorrectionController('ב$patahב$holam');
      addTearDown(controller.dispose);
      final before = controller.value;
      controller.value = before.copyWith(
        text: 'ב$patahג$holam',
        selection: const TextSelection.collapsed(offset: 3),
      );
      controller.setHiding(nikud: true, teamim: false);
      expect(controller.text, 'בג');
      controller.value = before;
      expect(controller.text, 'בב');
      expect(controller.canonical, 'ב$patahב$holam');
      expect(controller.formats.length, 2);
    });

    test('החלפת ההסתרה ממפה את הבחירה ושומרת על העיצוב והטקסט המלא', () {
      final controller = PluginCorrectionController(
        '<b>ב$patah</b>ב$holam',
      );
      addTearDown(controller.dispose);
      controller.selection = const TextSelection.collapsed(offset: 2);
      controller.setHiding(nikud: true, teamim: false);
      expect(controller.text, 'בב');
      expect(controller.selection, const TextSelection.collapsed(offset: 1));
      expect(controller.formats.map((f) => f.bold), [true, false]);
      controller.setHiding(nikud: false, teamim: false);
      expect(controller.text, 'ב$patahב$holam');
      expect(controller.formats.map((f) => f.bold), [true, true, false, false]);
      expect(controller.canonical, 'ב$patahב$holam');
    });

    test('שחזור טיוטה מציג אותה לפי ההסתרה ומשמר את הסימנים שבה', () {
      final controller = PluginCorrectionController(
        'ב$patahב$holamג',
        removeNikud: true,
      );
      addTearDown(controller.dispose);
      controller.restoreCanonical('ב$patahב');
      expect(controller.text, 'בב');
      expect(controller.canonical, 'ב$patahב');
    });
  });

  group('הרכבת מקלדת שנערכת מול מצב ההתחלה', () {
    const patah = '\u05B7';
    const holam = '\u05B9';
    const source = 'ב$patahב$holam';

    TextEditingValue compose(String text, int start, int end, {int? caret}) =>
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: caret ?? end),
          composing: TextRange(start: start, end: end),
        );

    PluginCorrectionController selected(String raw, int start, int end) {
      final controller = PluginCorrectionController(raw, removeNikud: true);
      addTearDown(controller.dispose);
      controller.value = controller.value.copyWith(
        selection: TextSelection(baseOffset: start, extentOffset: end),
      );
      return controller;
    }

    test('ביטול הרכבה על אות נבחרת משחזר את הניקוד המוסתר', () {
      final controller = selected(source, 0, 1);
      controller.value = compose('גב', 0, 1);
      expect(
        controller.canonical,
        'ג'
        'ב$holam',
      );
      controller.value = const TextEditingValue(
        text: 'בב',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(controller.canonical, source);
    });

    test('הרכבה שעוברת בין כמה קלטים ואז מתבטלת משחזרת את המקור', () {
      final controller = selected(source, 0, 1);
      controller.value = compose('גב', 0, 1);
      controller.value = compose('דב', 0, 1);
      expect(
        controller.canonical,
        'ד'
        'ב$holam',
      );
      controller.value = compose('בב', 0, 1);
      expect(controller.canonical, source);
    });

    test('הרכבה שגבולותיה זזים ומתבטלת לא מוחקת סימנים משכנים', () {
      final controller = PluginCorrectionController(source, removeNikud: true);
      addTearDown(controller.dispose);
      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: 2),
      );
      controller.value = compose('בבג', 2, 3);
      controller.value = compose('בגג', 1, 3);
      controller.value = compose('גג', 0, 2);
      controller.value = const TextEditingValue(
        text: 'בב',
        selection: TextSelection.collapsed(offset: 2),
      );
      expect(controller.canonical, source);
    });

    test('סיום הרכבה שהחליפה אות משמר את הסימנים של האות השכנה', () {
      final controller = selected(source, 0, 1);
      controller.value = compose('גב', 0, 1);
      controller.value = controller.value.copyWith(composing: TextRange.empty);
      expect(
        controller.canonical,
        'ג'
        'ב$holam',
      );
      controller.value = compose('גד', 1, 2);
      controller.value = const TextEditingValue(
        text: 'גב',
        selection: TextSelection.collapsed(offset: 2),
      );
      expect(
        controller.canonical,
        'ג'
        'ב$holam',
      );
    });

    test('הרכבה בסמן שמתבטלת משמרת את הסימנים של הטקסט שסביבה', () {
      final controller = PluginCorrectionController(source, removeNikud: true);
      addTearDown(controller.dispose);
      controller.value = controller.value.copyWith(
        selection: const TextSelection.collapsed(offset: 1),
      );
      controller.value = compose('בגב', 1, 2);
      controller.value = const TextEditingValue(
        text: 'בב',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(controller.canonical, source);
    });

    test('הרכבה בפסקה רב-שורתית לא נוגעת בשורה שלפניה', () {
      const multi = 'ב$patahב$holam\nב$patahב$holam';
      final controller = selected(multi, 3, 4);
      controller.value = compose('בב\nגב', 3, 4);
      controller.value = const TextEditingValue(
        text: 'בב\nבב',
        selection: TextSelection.collapsed(offset: 4),
      );
      expect(controller.canonical, multi);
    });

    test('הטיוטה נכתבת מחדש כשההרכבה מתבטלת', () {
      final drafts = <String>[];
      late PluginCorrectionController controller;
      controller = PluginCorrectionController(
        source,
        removeNikud: true,
        onEdit: () => drafts.add(controller.canonical),
      );
      addTearDown(controller.dispose);
      controller.value = controller.value.copyWith(
        selection: const TextSelection(baseOffset: 0, extentOffset: 1),
      );
      controller.value = compose('גב', 0, 1);
      controller.value = const TextEditingValue(
        text: 'בב',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(drafts, [
        'ג'
            'ב$holam',
        source,
      ]);
    });

    test('החלפת הגדרות באמצע הרכבה לא משמידה את הטקסט המלא', () {
      final controller = selected(source, 0, 1);
      controller.value = compose('גב', 0, 1);
      controller.setHiding(nikud: false, teamim: false);
      expect(
        controller.canonical,
        'ג'
        'ב$holam',
      );
      expect(
        controller.text,
        'ג'
        'ב$holam',
      );
      controller.setHiding(nikud: true, teamim: false);
      expect(controller.text, 'גב');
      expect(
        controller.canonical,
        'ג'
        'ב$holam',
      );
    });

    test('ביטול הרכבה נרשם בהיסטוריה פעם אחת, והחזרה אליה שלמה', () {
      final controller = selected(source, 0, 1);
      final first = controller.undoValue.value;
      controller.value = compose('גב', 0, 1);
      controller.value = const TextEditingValue(
        text: 'בב',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(controller.undoValue.value.canonical, source);
      controller.applyUndoValue(first);
      expect(controller.canonical, source);
    });
  });

  group('מקרי קצה של פסק והרכבה', () {
    const patah = '\u05B7';
    const holam = '\u05B9';
    const etnahta = '\u0591';

    TextEditingValue compose(String text, int start, int end) =>
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: end),
          composing: TextRange(start: start, end: end),
        );

    TextEditingValue plain(String text, int caret) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );

    PluginCorrectionController make(
      String raw, {
      bool nikud = false,
      bool teamim = false,
      int? start,
      int? end,
    }) {
      final controller = PluginCorrectionController(
        raw,
        removeNikud: nikud,
        removeTeamim: teamim,
      );
      addTearDown(controller.dispose);
      if (start != null) {
        controller.value = controller.value.copyWith(
          selection: TextSelection(baseOffset: start, extentOffset: end!),
        );
      }
      return controller;
    }

    test('מחיקת האות שלפני רווחים ופסק משאירה את הרווח הגלוי המבוקש', () {
      final controller = make('א  ׀ב', teamim: true, start: 0, end: 1);
      controller.value = plain(' ב', 0);
      expect(controller.canonical, '  ׀ב');
      expect(controller.text, ' ב');
    });

    test('מחיקת הרווח הגלוי לפני פסק מוחקת איתו את הפסק המוסתר שאחריו', () {
      final controller = make('א  ׀ב', teamim: true, start: 1, end: 2);
      controller.value = plain('אב', 1);
      expect(controller.canonical, 'אב');
    });

    for (final full in [
      'א־׀ב',
      '׀א',
      'א ׀ ׀ב',
      'א ׀׀ב',
      '  ׀',
      'א ׀',
      'א$etnahta  ׀ב',
      'ב$patah  ׀ב$holam',
    ]) {
      for (final (nikud, teamim) in [
        (false, true),
        (true, true),
        (true, false),
      ]) {
        test(
          'כל תו גלוי ב-"$full" מתאים לתו המלא שהקורא מציג ($nikud,$teamim)',
          () {
            final controller = make(full, nikud: nikud, teamim: teamim);
            final visible = utils.removeMarks(
              full,
              nikud: nikud,
              teamim: teamim,
            );
            expect(controller.text, visible);
            expect(controller.canonical, full);
            // מחיקת כל תו גלוי בנפרד משאירה בדיוק את שאר הטקסט הגלוי.
            for (var i = 0; i < visible.length; i++) {
              final editor = make(
                full,
                nikud: nikud,
                teamim: teamim,
                start: i,
                end: i + 1,
              );
              editor.value = plain(
                visible.substring(0, i) + visible.substring(i + 1),
                i,
              );
              expect(
                utils.removeMarks(
                  editor.canonical,
                  nikud: nikud,
                  teamim: teamim,
                ),
                visible.substring(0, i) + visible.substring(i + 1),
                reason: 'מחיקת התו הגלוי $i',
              );
            }
          },
        );
      }
    }

    test('ביטול הרכבה כשהטעמים מוסתרים משחזר אותם', () {
      final raw = 'ב$etnahtaב';
      final controller = make(raw, teamim: true, start: 0, end: 1);
      controller.value = compose('גב', 0, 1);
      controller.value = plain('בב', 1);
      expect(controller.canonical, raw);
    });

    test('ביטול הרכבה כשניקוד וטעמים מוסתרים יחד משחזר את שניהם', () {
      final raw = 'ב$patah$etnahtaב$holam';
      final controller = make(raw, nikud: true, teamim: true, start: 0, end: 1);
      controller.value = compose('גב', 0, 1);
      controller.value = plain('בב', 1);
      expect(controller.canonical, raw);
    });

    test('הרכבה מחדש בלי שינוי טקסט ואז החלפה וביטול משחזרת את המקור', () {
      const raw = 'ב$patahב$holam';
      final controller = make(raw, nikud: true);
      controller.value = compose('בב', 0, 1);
      controller.value = compose('גב', 0, 1);
      controller.value = compose('בב', 0, 1);
      controller.value = plain('בב', 1);
      expect(controller.canonical, raw);
    });

    test('החלפת מקור באמצע הרכבה לא נושאת את ההרכבה הישנה', () {
      const raw = 'ב$patahב$holam';
      final controller = make(raw, nikud: true, start: 0, end: 1);
      controller.value = compose('גב', 0, 1);
      controller.setSource('ג$patahג$holam');
      controller.value = plain('גג', 1);
      expect(controller.canonical, 'ג$patahג$holam');
    });

    test('שחזור טיוטה באמצע הרכבה מנקה אותה', () {
      const raw = 'ב$patahב$holam';
      final controller = make(raw, nikud: true, start: 0, end: 1);
      controller.value = compose('גב', 0, 1);
      controller.restoreCanonical(raw);
      controller.value = plain('בב', 1);
      expect(controller.canonical, raw);
    });

    test('החזרה להיסטוריה באמצע הרכבה לא מחזירה סימנים שנמחקו', () {
      const raw = 'ב$patahב$holam';
      final controller = make(raw, nikud: true, start: 0, end: 1);
      final first = controller.undoValue.value;
      controller.value = compose('גב', 0, 1);
      controller.applyUndoValue(first);
      expect(controller.canonical, raw);
      controller.value = plain('בב', 1);
      expect(controller.canonical, raw);
    });

    test('הרכבה שמסתיימת בטקסט חדש ואחריה הרכבה נוספת נמדדת מההתחלה החדשה', () {
      const raw = 'ב$patahב$holam';
      final controller = make(raw, nikud: true, start: 0, end: 1);
      controller.value = compose('גב', 0, 1);
      controller.value = plain('גב', 1);
      controller.value = compose('גדב', 1, 2);
      controller.value = plain('גב', 1);
      expect(
        controller.canonical,
        'ג'
        'ב$holam',
      );
    });
  });
}
