import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/simple_inline_html.dart';

void main() {
  const style = TextStyle(fontSize: 20);

  test('קלט גדול מוחזר במלואו בלי להישמר או לפנות שורות חמות', () {
    const hot = '<b>שורה חמה לפני קלט גדול</b>';
    final cached = SimpleInlineHtml.tryParse(hot, style);
    final html = 'א' * (3 * 1024 * 1024);
    final first = SimpleInlineHtml.tryParse(html, style)!;
    final second = SimpleInlineHtml.tryParse(html, style)!;
    expect(first.toPlainText(), html);
    expect(second.toPlainText(), html);
    expect(identical(first, second), isFalse);
    expect(identical(SimpleInlineHtml.tryParse(hot, style), cached), isTrue);
  });

  test('קלט ריק מחזיר span ריק בלי להישמר לכל סגנון', () {
    for (var i = 0; i < 5000; i++) {
      final base = TextStyle(fontSize: 10 + i / 5000);
      final first = SimpleInlineHtml.tryParse('', base)!;
      final second = SimpleInlineHtml.tryParse('', base)!;
      expect(first.toPlainText(), isEmpty);
      expect(second.toPlainText(), isEmpty);
      expect(identical(first, second), isFalse);
    }
  });

  test('גם שורות קצרות בסגנונות שונים מוגבלות במספר הרשומות', () {
    const html = 'שורה קצרה בעלת סגנונות שונים';
    final first = SimpleInlineHtml.tryParse(html, style);
    TextSpan? last;
    for (var i = 0; i < 4096; i++) {
      last = SimpleInlineHtml.tryParse(
        html,
        TextStyle(fontSize: 10 + i / 4096),
      );
    }
    expect(identical(SimpleInlineHtml.tryParse(html, style), first), isFalse);
    expect(
      identical(
        SimpleInlineHtml.tryParse(
          html,
          const TextStyle(fontSize: 10 + 4095 / 4096),
        ),
        last,
      ),
      isTrue,
    );
  });

  test('עץ צפוף מוחזר עם כל העיצוב בלי להישמר במטמון', () {
    const hot = 'שורה חמה לפני עץ צפוף';
    final cached = SimpleInlineHtml.tryParse(hot, style);
    final html = '<b>א</b>' * 17000;
    final first = SimpleInlineHtml.tryParse(html, style)!;
    final second = SimpleInlineHtml.tryParse(html, style)!;
    expect(first.toPlainText(), 'א' * 17000);
    expect(second.toPlainText(), first.toPlainText());
    expect(first.children, hasLength(17000));
    for (final child in first.children!.cast<TextSpan>()) {
      expect(child.style?.fontWeight, FontWeight.bold);
    }
    expect(identical(first, second), isFalse);
    expect(identical(SimpleInlineHtml.tryParse(hot, style), cached), isTrue);
  });

  test('מספר הצמתים המצטבר מפנה עצים ישנים ושומר רשומה שנקראה שוב', () {
    final cold = SimpleInlineHtml.tryParse('<i>עץ ישן</i>', style);
    const hot = '<b>עץ חם בזמן לחץ צמתים</b>';
    final cached = SimpleInlineHtml.tryParse(hot, style);
    final dense = '<b>א</b>' * 500;
    for (var i = 0; i < 40; i++) {
      SimpleInlineHtml.tryParse('$i$dense', style);
      SimpleInlineHtml.tryParse(hot, style);
    }
    expect(identical(SimpleInlineHtml.tryParse(hot, style), cached), isTrue);
    expect(
      identical(SimpleInlineHtml.tryParse('<i>עץ ישן</i>', style), cold),
      isFalse,
    );
  });

  test('לחץ תווים מפנה את הישן ושומר שורה חמה גם לאחר קריאות null', () {
    const hot = '<b>חם בזמן לחץ תווים</b>';
    const fallback = '<a href="x">קישור</a>';
    final cold = SimpleInlineHtml.tryParse('ישן לפני לחץ תווים', style);
    final cached = SimpleInlineHtml.tryParse(hot, style);
    for (var i = 0; i < 30; i++) {
      SimpleInlineHtml.tryParse('$i${'א' * 80000}', style);
      expect(SimpleInlineHtml.tryParse(fallback, style), isNull);
      SimpleInlineHtml.tryParse(hot, style);
    }
    expect(identical(SimpleInlineHtml.tryParse(hot, style), cached), isTrue);
    expect(
      identical(SimpleInlineHtml.tryParse('ישן לפני לחץ תווים', style), cold),
      isFalse,
    );
    expect(SimpleInlineHtml.tryParse(fallback, style), isNull);
  });

  test('רשומות null כפופות לאותה תקרת רשומות ולא משנות fallback', () {
    const html = 'ישן לפני לחץ רשומות null';
    final old = SimpleInlineHtml.tryParse(html, style);
    for (var i = 0; i < 4096; i++) {
      expect(
        SimpleInlineHtml.tryParse('<a href="$i">קישור</a>', style),
        isNull,
      );
    }
    expect(identical(SimpleInlineHtml.tryParse(html, style), old), isFalse);
    expect(
      SimpleInlineHtml.tryParse('<a href="4095">קישור</a>', style),
      isNull,
    );
  });
  test('מפתח המטמון כולל את כל הסגנון גם כשהפרסור עצמו יורש חלק ממנו', () {
    const html = '<b>מפתח סגנון מלא</b> <small>הערה</small>';
    const base = TextStyle(fontSize: 20, fontFamily: 'FrankRuhlCLM');
    final first = SimpleInlineHtml.tryParse(html, base);
    final variants = [
      base.copyWith(fontSize: 24),
      base.copyWith(fontFamily: 'Rubik'),
      base.copyWith(fontWeight: FontWeight.w600),
      base.copyWith(fontVariations: const [FontVariation('wght', 900)]),
      base.copyWith(color: const Color(0xFF123456)),
      base.copyWith(locale: const Locale('en')),
      base.copyWith(height: 1.8, letterSpacing: 2),
      base.copyWith(fontFamilyFallback: const ['NotoRashiHebrew']),
    ];
    for (final variant in variants) {
      final span = SimpleInlineHtml.tryParse(html, variant)!;
      expect(identical(first, span), isFalse);
      expect(
        identical(SimpleInlineHtml.tryParse(html, variant.copyWith()), span),
        isTrue,
      );
      expect(span.toPlainText(), 'מפתח סגנון מלא הערה');
      final small = span.children!.last as TextSpan;
      expect(small.style?.fontSize, closeTo(variant.fontSize! * 5 / 6, 1e-9));
    }
  });

  test('שורות ספרים אמיתיות שומרות על הטקסט גם אחרי פינוי ופרסור חוזר', () {
    // דגימות קריאה בלבד מבראשית ומשולחן ערוך; אין תלות במסד נתונים בבדיקה.
    const rows = <(String, String)>[
      (
        "(ה) וַיִּקְרָ֨א אֱלֹהִ֤ים&thinsp;<small>׀</small>&thinsp;לָאוֹר֙ י֔וֹם וְלַחֹ֖שֶׁךְ קָ֣רָא לָ֑יְלָה וַֽיְהִי־עֶ֥רֶב וַֽיְהִי־בֹ֖קֶר י֥וֹם אֶחָֽד׃&nbsp;<span class=\"mam-spi-pe\">{פ}</span><br>",
        "(ה) וַיִּקְרָ֨א אֱלֹהִ֤ים\u2009׀\u2009לָאוֹר֙ י֔וֹם וְלַחֹ֖שֶׁךְ קָ֣רָא לָ֑יְלָה וַֽיְהִי־עֶ֥רֶב וַֽיְהִי־בֹ֖קֶר י֥וֹם אֶחָֽד׃\u00A0{פ}",
      ),
      (
        "(ב) <i data-commentator=\"Be'er HaGolah\" data-label=\"ב\" data-order=\"2\"></i>אל יאמר הנני בחדרי חדרים <i data-commentator=\"Magen Avraham\" data-order=\"2\"></i>מי רואני כי הקב\"ה מלא כל הארץ כבודו:",
        "(ב) אל יאמר הנני בחדרי חדרים מי רואני כי הקב\"ה מלא כל הארץ כבודו:",
      ),
      (
        "(כט) וַיֹּ֣אמֶר אֱלֹהִ֗ים הִנֵּה֩ נָתַ֨תִּי לָכֶ֜ם אֶת־כׇּל־עֵ֣שֶׂב&thinsp;<b>׀</b> זֹרֵ֣עַ זֶ֗רַע אֲשֶׁר֙ עַל־פְּנֵ֣י כׇל־הָאָ֔רֶץ וְאֶת־כׇּל־הָעֵ֛ץ אֲשֶׁר־בּ֥וֹ פְרִי־עֵ֖ץ זֹרֵ֣עַ זָ֑רַע לָכֶ֥ם יִֽהְיֶ֖ה לְאׇכְלָֽה׃",
        "(כט) וַיֹּ֣אמֶר אֱלֹהִ֗ים הִנֵּה֩ נָתַ֨תִּי לָכֶ֜ם אֶת־כׇּל־עֵ֣שֶׂב\u2009׀ זֹרֵ֣עַ זֶ֗רַע אֲשֶׁר֙ עַל־פְּנֵ֣י כׇל־הָאָ֔רֶץ וְאֶת־כׇּל־הָעֵ֛ץ אֲשֶׁר־בּ֥וֹ פְרִי־עֵ֖ץ זֹרֵ֣עַ זָ֑רַע לָכֶ֥ם יִֽהְיֶ֖ה לְאׇכְלָֽה׃",
      ),
    ];
    for (final (html, text) in rows) {
      final first = SimpleInlineHtml.tryParse(html, style)!;
      expect(first.toPlainText(), text);
      for (var i = 0; i < 4096; i++) {
        SimpleInlineHtml.tryParse('לחץ בין דגימות $i', style);
      }
      final again = SimpleInlineHtml.tryParse(html, style)!;
      expect(identical(first, again), isFalse);
      expect(again, first);
    }
  });
  test('קריאה חוזרת של תוצאת null מקדמת גם אותה בסדר LRU', () {
    const fallback = '<a href="negative-lru">קישור לבדיקת LRU</a>';
    const sentinel = 'ישן אחרי רשומה שלילית לבדיקת LRU';
    expect(SimpleInlineHtml.tryParse(fallback, style), isNull);
    final old = SimpleInlineHtml.tryParse(sentinel, style);
    for (var i = 0; i < 4094; i++) {
      SimpleInlineHtml.tryParse('רשומת מילוי לבדיקת LRU $i', style);
    }
    expect(SimpleInlineHtml.tryParse(fallback, style), isNull);
    SimpleInlineHtml.tryParse('חדש לאחר קריאת רשומה שלילית', style);
    expect(identical(SimpleInlineHtml.tryParse(sentinel, style), old), isFalse);
    expect(SimpleInlineHtml.tryParse(fallback, style), isNull);
  });
}
