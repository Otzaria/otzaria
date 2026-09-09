import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope;

import '../../support/search_engine_test_init.dart';

Future<void> main() async {
  // sanitizeQuery/splitQueryWords מאצילים למנוע ה-Rust; הטסטים שלהם דורשים
  // את הספרייה הנייטיבית ומדולגים כשאין build זמין.
  final engineReady = await tryInitSearchEngine();

  group('TextRendererService - סימוני הערות שוליים', () {
    const settings = RenderSettings();

    test(
      'סימון מספרי נפלט כספרות-עיליות ולא כ-sup (מניעת WidgetSpan שמתהפך ב-RTL)',
      () {
        const line =
            'יתגבר כארי<sup class="footnote-marker">1</sup> לעמוד עד'
            '<sup class="footnote-marker">2</sup> שיהא';

        final out = TextRendererService.processText(line, settings);

        // אסור שיישאר <sup>: HtmlWidget מממש אותו כ-WidgetSpan, ומנוע Flutter
        // משבץ placeholders בפסקת RTL בסדר ויזואלי הפוך — המספרים מתחלפים.
        expect(out, isNot(contains('<sup')));
        expect(out, contains('¹'));
        expect(out, contains('²'));
      },
    );

    test('סדר המספרים הלוגי נשמר בפלט', () {
      const line =
          'אחד<sup class="footnote-marker">1</sup> שתיים'
          '<sup class="footnote-marker">2</sup> שלוש'
          '<sup class="footnote-marker">3</sup>';

      final out = TextRendererService.processText(line, settings);

      final digits = RegExp(
        '[¹²³]',
      ).allMatches(out).map((m) => m.group(0)).toList();
      expect(digits, ['¹', '²', '³']);
    });

    test('סימון דו-ספרתי מומר במלואו', () {
      const line = 'מילה<sup class="footnote-marker">14</sup> עוד';

      final out = TextRendererService.processText(line, settings);

      expect(out, contains('¹⁴'));
    });

    test('תוכן הסימון עטוף בסימני בידוד דו-כיווניים (LRI/PDI)', () {
      const line = 'מילה<sup class="footnote-marker">7</sup> עוד';

      final out = TextRendererService.processText(line, settings);

      expect(out, contains('\u2066⁷\u2069'));
    });

    test('סימון אות עברית נפלט כ-span מעוצב (אין ספרות-עיליות לעברית)', () {
      const line = 'מילה<sup class="footnote-marker">א</sup> עוד';

      final out = TextRendererService.processText(line, settings);

      expect(out, isNot(contains('<sup')));
      expect(out, contains('<span class="footnote-marker-number">'));
    });

    test('sup מספרי חשוף (בלי class) מומר אף הוא לספרות-עיליות', () {
      // חלק מספרי ההערות-inline מקודדים מרקרים כ-<sup>1</sup> ללא class,
      // והם חשופים לאותו באג היפוך — מקבלים את אותו טיפול.
      const line = 'שורה<sup>1</sup> המשך<sup>2</sup> סוף';

      final out = TextRendererService.processText(line, settings);

      expect(out, isNot(contains('<sup')));
      expect(out, contains('¹'));
      expect(out, contains('²'));
    });

    // sup חשוף היה נשאר `<sup>` ונרנדר ב-WidgetSpan של fwfh — מה שהפך את סדר
    // הסימונים בפסקת RTL. כיום הוא נפלט כ-span טקסט טהור במחלקת raised-sup,
    // עם אותן מטריקות (5/6, בלי נטייה), וההרמה נעשית בציור.
    test('sup עברי חשוף (בלי class) נפלט כ-raised-sup — superscript תוכני', () {
      const line = 'טקסט עם <sup>מעריך</sup> רגיל';

      final out = TextRendererService.processText(line, settings);

      expect(out, isNot(contains('<sup')));
      expect(out, contains('class="raised-sup"'));
      expect(out, isNot(contains('footnote-marker-number')));
    });

    test('sup מורכב נשאר sup ושומר את ה-markup הפנימי', () {
      const line = 'טקסט<sup><a href="x">קישור מורכב!</a></sup> המשך';

      final out = TextRendererService.processText(line, settings);

      expect(out, contains('<sup>'));
      expect(out, isNot(contains('class="raised-sup"')));
      expect(out, contains('<a href="x">'));
    });

    test('sup מעוצב שומר attributes', () {
      const line =
          'טקסט<sup class="custom" style="color:red" title="note">א</sup>';

      final out = TextRendererService.processText(line, settings);

      expect(out, contains('<sup class="custom"'));
      expect(out, contains('style="color:red"'));
      expect(out, contains('title="note"'));
      expect(out, isNot(contains('class="raised-sup"')));
    });

    test('sup ריק מוסר לחלוטין', () {
      const line = 'טקסט<sup class="footnote-marker"></sup> המשך';

      final out = TextRendererService.processText(line, settings);

      expect(out, isNot(contains('<sup')));
      expect(out, isNot(contains('footnote-marker-number')));
    });
  });

  group('TextRendererService - טקסט תחתי (issue #842)', () {
    const settings = RenderSettings();

    test('sub מספרי מומר לספרות-תחתיות יוניקוד (טקסט טהור, נכלל בבחירה)', () {
      const line = 'מים H<sub>2</sub>O וגם A<sub>14</sub> סוף';

      final out = TextRendererService.processText(line, settings);

      expect(out, isNot(contains('<sub')));
      expect(out, contains('₂'));
      expect(out, contains('₁₄'));
    });

    test('sub עברי נפלט כ-span מוקטן — לא WidgetSpan ששובר שורה ובחירה', () {
      const line = 'מילה<sub>הערה</sub> המשך';

      final out = TextRendererService.processText(line, settings);

      expect(out, isNot(contains('<sub')));
      expect(out, contains('<span class="subscript-text">'));
      expect(out, contains('הערה'));
    });

    test('תוכן ה-sub עטוף בסימני בידוד דו-כיווניים', () {
      const line = 'מילה<sub>3</sub> עוד';

      final out = TextRendererService.processText(line, settings);

      expect(out, contains('\u2066₃\u2069'));
    });

    test('sub ריק מוסר לחלוטין', () {
      const line = 'טקסט<sub> </sub> המשך';

      final out = TextRendererService.processText(line, settings);

      expect(out, isNot(contains('<sub')));
      expect(out, isNot(contains('subscript-text')));
    });

    test('sub עם attributes מטופל אף הוא', () {
      const line = 'טקסט<sub class="x">ב</sub> המשך';

      final out = TextRendererService.processText(line, settings);

      expect(out, isNot(contains('<sub')));
      expect(out, contains('<span class="subscript-text">'));
    });
  });

  group('TextRendererService - מטמון render', () {
    setUp(TextRendererService.clearRenderCacheForTesting);

    test(
      'קריאה חוזרת עם אותו טקסט והגדרות מחזירה את אותו instance מהמטמון',
      () {
        const settings = RenderSettings(removeNikud: true);
        const text = 'בְּרֵאשִׁית בָּרָא אֱלֹהִים';

        final first = TextRendererService.processText(text, settings);
        final second = TextRendererService.processText(text, settings);

        expect(identical(first, second), isTrue);
      },
    );

    test('שינוי בשדות עיצוב בלבד (גופן/יישור) לא מפספס את המטמון', () {
      const text = 'בראשית ברא אלהים';

      final first = TextRendererService.processText(
        text,
        const RenderSettings(fontSize: 18),
      );
      final second = TextRendererService.processText(
        text,
        const RenderSettings(fontSize: 24, justifyText: false),
      );

      expect(identical(first, second), isTrue);
    });

    test('שינוי בהגדרות שמשפיעות על הפלט מחזיר תוצאה שונה', () {
      const text = 'בְּרֵאשִׁית בָּרָא';

      final withNikud = TextRendererService.render(
        text,
        const RenderSettings(),
      );
      final withoutNikud = TextRendererService.render(
        text,
        const RenderSettings(removeNikud: true),
      );

      expect(withNikud, isNot(equals(withoutNikud)));
      expect(withoutNikud, isNot(contains('ְ')));
    });

    test(
      'התוצאה מהמטמון זהה לתוצאת חישוב מלא',
      () {
        const settings = RenderSettings(searchText: 'ארץ');
        const text = 'את השמים ואת הארץ';

        final cached = TextRendererService.render(text, settings);
        TextRendererService.clearRenderCacheForTesting();
        final fresh = TextRendererService.render(text, settings);

        expect(cached, equals(fresh));
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );
  });

  group(
    'TextRendererService - מדיניות התאמת החיפוש',
    () {
      const text = 'תדע אחת שתים שלוש ארבע חמש זרעך';

      test('ברירת המחדל אינה מדגישה מילים רחוקות', () {
        const settings = RenderSettings(
          searchText: 'תדע זרעך',
          searchDistance: 2,
        );
        expect(
          TextRendererService.processText(text, settings),
          isNot(contains('<span style="color: red">')),
        );
      });

      test('טווח "באותה פסקה" מדגיש כל מילת שאילתה בשורת תוצאה', () {
        // המדיניות והדגל מגיעים מ-state הספר אל RenderSettings; בלעדיהם
        // החלונית הציגה תוצאה שגוף הספר לא הדגיש בכלל.
        const settings = RenderSettings(
          searchText: 'תדע זרעך',
          searchDistance: 2,
          matchPolicy: SearchMatchPolicy(
            proximityScope: SearchScope.sameParagraph,
          ),
          isSearchResultLine: true,
        );
        final out = TextRendererService.processText(text, settings);
        expect(out, contains('<span style="color: red">תדע</span>'));
        expect(out, contains('<span style="color: red">זרעך</span>'));
      });

      test('שורה שאינה תוצאה אינה מודגשת גם במדיניות מפוזרת', () {
        const settings = RenderSettings(
          searchText: 'תדע זרעך',
          searchDistance: 2,
          matchPolicy: SearchMatchPolicy(
            proximityScope: SearchScope.sameParagraph,
          ),
        );
        expect(
          TextRendererService.processText(text, settings),
          isNot(contains('<span style="color: red">')),
        );
      });

      test('המדיניות והדגל משתתפים במפתח המטמון של הרינדור', () {
        const text = 'תדע אחת שתים שלוש זרעך';
        const standard = RenderSettings(searchText: 'תדע זרעך');
        const sameParagraph = RenderSettings(
          searchText: 'תדע זרעך',
          matchPolicy: SearchMatchPolicy(
            proximityScope: SearchScope.sameParagraph,
          ),
          isSearchResultLine: true,
        );

        final standardOut = TextRendererService.render(text, standard);
        final policyOut = TextRendererService.render(text, sameParagraph);

        expect(policyOut, isNot(equals(standardOut)));
      });
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );

  // issue #1236 — ¹²³ יושבות בבלוק Latin-1 שיש בכל גופן, ⁰⁴–⁹ בבלוק
  // Superscripts שחסר ברוב גופני המערכת: Flutter נופל לגופן אחר עבורן, ומרקרי
  // 4 ומעלה נראו שונה מ-1–3. הספרות חייבות להישאר ספרות רגילות של גופן הספר,
  // מוקטנות ומורמות בציור כמו מרקר-אות.
  group('TextRendererService - מרקר מספרי בגופן הספר (issue #1236)', () {
    const settings = RenderSettings();
    final superscriptGlyphs = RegExp('[⁰¹²³⁴⁵⁶⁷⁸⁹]');

    test('מרקר הערה מספרי נפלט כ-span עם ספרות רגילות', () {
      const line = 'מילה<sup class="footnote-marker">14</sup> עוד';

      final out = TextRendererService.processText(line, settings);

      expect(out, isNot(contains('<sup')));
      expect(out, isNot(matches(superscriptGlyphs)));
      expect(out, contains('<span class="footnote-marker-number">'));
      expect(out, contains('14'));
    });

    test('sup מספרי חשוף נפלט כ-raised-sup עם ספרות רגילות', () {
      const line = 'שורה<sup>7</sup> המשך';

      final out = TextRendererService.processText(line, settings);

      expect(out, isNot(contains('<sup')));
      expect(out, isNot(matches(superscriptGlyphs)));
      expect(out, contains('class="raised-sup"'));
    });
  });
}
