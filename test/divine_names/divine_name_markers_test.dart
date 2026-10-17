import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/divine_names/utils/divine_name_markers.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' show HolyNameStyle;

/// עטיפת מופעי השמות בשורה (קואורדינטות גלויות, אימות שלד) והמרת הסמנים
/// לצורת התצוגה בזמן הרינדור.
void main() {
  // אֱלֹהִים, אֲדֹנָי, יְהוָה — עם ניקוד.
  const elohimNikud = 'אֱלֹהִים';
  const adnutNikud = 'אֲדֹנָי';
  const hvyhNikud = 'יְהוָה';

  String resolve(
    String html, {
    bool substitute = true,
    HolyNameStyle? holyNameStyle,
  }) => resolveDivineNameMarkers(
    html,
    substituteOtherNames: substitute,
    holyNameStyle: holyNameStyle,
  );

  String render(
    String line,
    List<DivineNameSpan> spans, {
    bool substitute = true,
    HolyNameStyle? holyNameStyle,
  }) => resolve(
    wrapDivineNameSpans(line, spans),
    substitute: substitute,
    holyNameStyle: holyNameStyle,
  );

  group('wrapDivineNameSpans', () {
    test('עוטף את הטווח הגלוי, גם אחרי תגים ו-entity', () {
      // "<b>א</b>&amp; " = 3 תווים גלויים לפני השם.
      const line = '<b>א</b>&amp; אלהים שלום';
      final wrapped = wrapDivineNameSpans(line, [
        (start: 3, end: 8, kind: DivineNameKind.elohim),
      ]);
      expect(
        wrapped,
        '<b>א</b>&amp; ${divineNameMarkerOpen(DivineNameKind.elohim)}'
        'אלהים</span> שלום',
      );
    });

    test('שם עם אות שימוש — האות מחוץ לסמן', () {
      final wrapped = wrapDivineNameSpans('לאלהים', [
        (start: 1, end: 6, kind: DivineNameKind.elohim),
      ]);
      expect(
        wrapped,
        'ל${divineNameMarkerOpen(DivineNameKind.elohim)}אלהים</span>',
      );
    });

    test('שלד שאינו תואם את הסוג — המופע מושמט', () {
      const line = 'אלהים שלום';
      expect(
        wrapDivineNameSpans(line, [
          (start: 6, end: 10, kind: DivineNameKind.elohim),
        ]),
        line,
      );
      // סוג לא מוכר אינו נעטף.
      expect(
        wrapDivineNameSpans('יה', [(start: 0, end: 2, kind: 42)]),
        'יה',
      );
    });

    test('מופע שחוצה תג — מושמט', () {
      const line = 'א<b>להים</b>';
      expect(
        wrapDivineNameSpans(line, [
          (start: 0, end: 5, kind: DivineNameKind.elohim),
        ]),
        line,
      );
    });

    test('אופסט מעבר לסוף השורה — מושמט', () {
      expect(
        wrapDivineNameSpans('אל', [
          (start: 0, end: 9, kind: DivineNameKind.el),
        ]),
        'אל',
      );
    });
  });

  group('גבולות מילה', () {
    // [start, end) של "אל"/"אלהים" בתוך [line], לפי ההופעה האחרונה.
    DivineNameSpan spanOf(String line, String name, int kind) {
      final start = line.lastIndexOf(name);
      return (start: start, end: start + name.length, kind: kind);
    }

    String substituted(String line, String name, int kind) =>
        render(line, [spanOf(line, name, kind)]);

    test('"אל" שבתוך "ישראל" — מושמט (אות לפניו שאינה אות שימוש)', () {
      const line = 'שמע ישראל';
      final span = spanOf(line, 'אל', DivineNameKind.el);
      expect(wrapDivineNameSpans(line, [span]), line);
      expect(substituted(line, 'אל', DivineNameKind.el), line);
    });

    test('אות אחרי סוף המופע — מושמט', () {
      const line = 'אלהימו';
      expect(
        wrapDivineNameSpans(line, [
          (start: 0, end: 5, kind: DivineNameKind.elohim),
        ]),
        line,
      );
    });

    test('ניקוד אחרי המופע אינו אות — עובר', () {
      const line = 'אלָ שלום';
      expect(
        render(line, [(start: 0, end: 2, kind: DivineNameKind.el)]),
        'קלָ שלום',
      );
    });

    test('"לאל" ו-"ובאלהים" — אותיות שימוש לפני השם, עוברים', () {
      expect(substituted('לאל', 'אל', DivineNameKind.el), 'לקל');
      expect(
        substituted('ובאלהים', 'אלהים', DivineNameKind.elohim),
        'ובאלקים',
      );
    });

    test('שלוש אותיות שימוש עוברות, ארבע — מושמט', () {
      // הכלל: עד שלוש אותיות שימוש (רמב"ם יסודי התורה ו, ג-ד).
      expect(
        substituted('כשהאלהים', 'אלהים', DivineNameKind.elohim),
        'כשהאלקים',
      );
      const four = 'וכשהאלהים';
      expect(substituted(four, 'אלהים', DivineNameKind.elohim), four);
    });

    test('אות שימוש עם ניקוד — עוברת', () {
      const line = 'לֵאלֹהִים';
      expect(
        substituted(line, 'אלֹהִים', DivineNameKind.elohim),
        'לֵאלֹקִים',
      );
    });

    test('תג בין אות השימוש לשם — מתקבל, כי הטקסט הגלוי תקין', () {
      const line = 'ל<b>אלהים</b>';
      expect(
        render(line, [(start: 1, end: 6, kind: DivineNameKind.elohim)]),
        'ל<b>אלקים</b>',
      );
    });

    test('תג עיצוב אינו גבול מילה; sup ושבירת שורה כן', () {
      const bold = 'ישר<b>אל</b>';
      expect(
        wrapDivineNameSpans(bold, [
          (start: 3, end: 5, kind: DivineNameKind.el),
        ]),
        bold,
      );
      expect(
        render('שמע<br>אל', [(start: 3, end: 5, kind: DivineNameKind.el)]),
        'שמע<br>קל',
      );
    });

    test('גם בזמן הפתרון: סמן מזויף בתוך מילה מוצג ככתבו', () {
      final forged = 'ישר${divineNameMarkerOpen(DivineNameKind.el)}אל</span>';
      expect(resolve(forged), 'ישראל');
    });
  });

  group('resolveDivineNameMarkers', () {
    test('שורה בלי סמנים מוחזרת כמות שהיא', () {
      const line = '<b>בראשית</b> ברא';
      expect(identical(resolve(line), line), isTrue);
    });

    test('כל הסוגים — אות אחת מוחלפת והניקוד נשמר', () {
      expect(
        render(elohimNikud, [
          (start: 0, end: elohimNikud.length, kind: DivineNameKind.elohim),
        ]),
        'אֱלֹקִים',
      );
      expect(
        render('אלהיך', [(start: 0, end: 5, kind: DivineNameKind.elohim)]),
        'אלקיך',
      );
      expect(
        render('אלוהים', [(start: 0, end: 6, kind: DivineNameKind.elohim)]),
        'אלוקים',
      );
      expect(
        render('אלוה', [(start: 0, end: 4, kind: DivineNameKind.eloah)]),
        'אלו-\u2060ה',
      );
      expect(
        render('אלי', [(start: 0, end: 3, kind: DivineNameKind.el)]),
        'קלי',
      );
      expect(
        render('שדי', [(start: 0, end: 3, kind: DivineNameKind.shaddai)]),
        'ש-\u2060די',
      );
      expect(
        render('צבאות', [(start: 0, end: 5, kind: DivineNameKind.tzevaot)]),
        'צבקות',
      );
      expect(
        render('אהיה', [(start: 0, end: 4, kind: DivineNameKind.ehyeh)]),
        'אהי-\u2060ה',
      );
    });

    test('צורות המקף ויה — עם ניקוד, במקום הנכון', () {
      String one(String word, int kind) =>
          render(word, [(start: 0, end: word.length, kind: kind)]);

      // שַׁדַּי → שַׁ-דַּי: אחרי ה-ש וכל הניקוד שלה (שין ופתח).
      expect(
        one('שַׁדַּי', DivineNameKind.shaddai),
        'שַׁ-\u2060דַּי',
      );
      // אֱלוֹהַּ → אֱלוֹ-הַּ; ובכתיב חסר אֱלֹהַּ → אֱלֹ-הַּ.
      expect(
        one('אֱלוֹהַּ', DivineNameKind.eloah),
        'אֱלוֹ-\u2060הַּ',
      );
      expect(
        one('אֱלֹהַּ', DivineNameKind.eloah),
        'אֱלֹ-\u2060הַּ',
      );
      // אֶהְיֶה → אֶהְיֶ-ה: לפני ה-ה הסופית, לא לפני הראשונה.
      expect(
        one('אֶהְיֶה', DivineNameKind.ehyeh),
        'אֶהְיֶ-\u2060ה',
      );
      // יָהּ → קָהּ.
      expect(one('יָהּ', DivineNameKind.yah), 'קָהּ');
    });

    test('יה — גבול מילה: בְּיָהּ עובר, הללויה מושמט', () {
      const withPrefix = 'בּיָהּ';
      expect(
        render(withPrefix, [(start: 2, end: 5, kind: DivineNameKind.yah)]),
        'בּקָהּ',
      );
      const halleluyah = 'הללויה';
      expect(
        wrapDivineNameSpans(halleluyah, [
          (start: 4, end: 6, kind: DivineNameKind.yah),
        ]),
        halleluyah,
      );
    });

    test('צורות המקף בתוך הדגשת חיפוש — המקף נכנס בתוך ההדגשה', () {
      String highlighted(String word, int kind) => resolve(
        '${divineNameMarkerOpen(kind)}'
        '<span style="color: red">$word</span></span>',
      );
      expect(
        highlighted('שדי', DivineNameKind.shaddai),
        '<span style="color: red">ש-\u2060די</span>',
      );
      expect(
        highlighted('אלוה', DivineNameKind.eloah),
        '<span style="color: red">אלו-\u2060ה</span>',
      );
      expect(
        highlighted('אהיה', DivineNameKind.ehyeh),
        '<span style="color: red">אהי-\u2060ה</span>',
      );
    });

    test('אדנות — מקף ASCII אחרי ה-ד והניקוד שלה', () {
      expect(
        render('אדני', [(start: 0, end: 4, kind: DivineNameKind.adnut)]),
        'אד-\u2060ני',
      );
      expect(
        render(adnutNikud, [
          (start: 0, end: adnutNikud.length, kind: DivineNameKind.adnut),
        ]),
        'אֲדֹ-\u2060נָי',
      );
    });

    test('ההגדרה כבויה — הסמן מוסר והטקסט ככתבו', () {
      const line = 'ויאמר אלהים';
      expect(
        render(line, [
          (start: 6, end: 11, kind: DivineNameKind.elohim),
        ], substitute: false),
        line,
      );
    });

    test('הדגשת חיפוש בתוך הסמן — ההחלפה מדלגת על התגים', () {
      final html =
          'ל${divineNameMarkerOpen(DivineNameKind.elohim)}'
          '<span style="color: red">אלהים</span></span> שלום';
      expect(resolve(html), 'ל<span style="color: red">אלקים</span> שלום');

      final adnut =
          '${divineNameMarkerOpen(DivineNameKind.adnut)}'
          '<span style="color: red">$adnutNikud</span></span>';
      expect(
        resolve(adnut),
        '<span style="color: red">אֲדֹ-\u2060נָי</span>',
      );
    });

    test('שם הוי"ה מהטבלה — לפי סגנון שם הוי"ה, לא לפי ההגדרה החדשה', () {
      final spans = [
        (start: 0, end: hvyhNikud.length, kind: DivineNameKind.hvyh),
      ];
      expect(render(hvyhNikud, spans, substitute: false), hvyhNikud);
      expect(
        render(
          hvyhNikud,
          spans,
          substitute: false,
          holyNameStyle: HolyNameStyle.kufKuf,
        ),
        'יְקוָק',
      );
      expect(
        render(
          hvyhNikud,
          spans,
          holyNameStyle: HolyNameStyle.hehApostrophe,
        ),
        "ה'",
      );
      expect(
        render(hvyhNikud, spans, holyNameStyle: HolyNameStyle.doubleYod),
        'יְיָ',
      );
    });

    test('שם הוי"ה כיי — הדגשת חיפוש בתוך הסמן נשמרת', () {
      final html =
          'ל${divineNameMarkerOpen(DivineNameKind.hvyh)}'
          '<span style="color: red">יְהֹ</span>וָה</span>';
      expect(
        resolveDivineNameMarkers(
          html,
          substituteOtherNames: false,
          holyNameStyle: HolyNameStyle.doubleYod,
        ),
        'ל<span style="color: red">יְ</span>יָ',
      );
    });

    test('סמן שתוכנו השתנה ואינו תואם — מוצג ככתבו', () {
      final html = '${divineNameMarkerOpen(DivineNameKind.shaddai)}שלום</span>';
      expect(resolve(html), 'שלום');
    });
  });
}
