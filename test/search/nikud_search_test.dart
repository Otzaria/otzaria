import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

import '../support/search_engine_test_init.dart';

Future<void> main() async {
  // sanitizeQuery ו-countMatches מאצילים למנוע ה-Rust; הטסטים שלהם דורשים
  // את הספרייה הנייטיבית ומדולגים כשאין build זמין.
  final engineReady = await tryInitSearchEngine();

  group('Nikud Detection and Removal Tests', () {
    test('hasNikud should detect nikud in text', () {
      // טקסט עם ניקוד
      expect(hasNikud('שָׁלוֹם'), true);
      expect(hasNikud('בְּרֵאשִׁית'), true);
      expect(hasNikud('הַלְלוּיָהּ'), true);

      // טקסט ללא ניקוד
      expect(hasNikud('שלום'), false);
      expect(hasNikud('בראשית'), false);
      expect(hasNikud('הללויה'), false);

      // טקסט ריק
      expect(hasNikud(''), false);

      // טקסט עם טעמים בלבד (טעמים הם גם חלק מ-vowelsAndCantillation)
      expect(hasNikud('שָׁל֥וֹם'), true);
    });

    test('removeVolwels should remove nikud and cantillation from text', () {
      // הסרת ניקוד בסיסי
      expect(removeVolwels('שָׁלוֹם'), 'שלום');
      expect(removeVolwels('בְּרֵאשִׁית'), 'בראשית');
      expect(removeVolwels('הַלְלוּיָהּ'), 'הללויה');

      // טקסט ללא ניקוד - צריך להישאר זהה
      expect(removeVolwels('שלום'), 'שלום');
      expect(removeVolwels('בראשית'), 'בראשית');

      // טקסט ריק
      expect(removeVolwels(''), '');

      // הסרת ניקוד וטעמים
      expect(removeVolwels('שָׁל֥וֹם'), 'שלום');

      // החלפת תווים מיוחדים
      expect(removeVolwels('שָׁלוֹם־עוֹלָם'), 'שלום עולם');
      expect(removeVolwels('שָׁלוֹם׀עוֹלָם'), 'שלום עולם');
      expect(removeVolwels('שָׁלוֹם|עוֹלָם'), 'שלום עולם');
    });

    test('removeVolwels should handle mixed content', () {
      // טקסט מעורב - עברית ואנגלית
      expect(removeVolwels('שָׁלוֹם Hello'), 'שלום Hello');

      // טקסט עם מספרים
      expect(removeVolwels('פֶּרֶק 123'), 'פרק 123');

      // טקסט עם סימני פיסוק
      expect(removeVolwels('שָׁלוֹם, עוֹלָם!'), 'שלום, עולם!');
    });

    test(
      'sanitizeQuery should remove commas and convert Hebrew quotes',
      () {
        expect(SearchQueryBuilder.sanitizeQuery("שלום, עולם'"), "שלום עולם'");
        expect(
          SearchQueryBuilder.sanitizeQuery('שלום, עולם׳״'),
          'שלום עולם\'"',
        );
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'countMatches should ignore commas and exclamation in query',
      () {
        expect(countMatches('שלום עולם שלום', 'שלום,!'), 2);
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test('Complex nikud patterns', () {
      // דגש חזק
      expect(hasNikud('שַׁבָּת'), true);
      expect(removeVolwels('שַׁבָּת'), 'שבת');

      // שווא
      expect(hasNikud('בְּרֵאשִׁית'), true);
      expect(removeVolwels('בְּרֵאשִׁית'), 'בראשית');

      // חולם חסר
      expect(hasNikud('תּוֹרָה'), true);
      expect(removeVolwels('תּוֹרָה'), 'תורה');

      // קמץ וסגול
      expect(hasNikud('אָדָם'), true);
      expect(removeVolwels('אָדָם'), 'אדם');
    });

    test('Edge cases', () {
      // רק ניקוד (לא צריך לקרות, אבל בואו נבדוק)
      expect(hasNikud('ָ'), true);
      expect(removeVolwels('ָ'), '');

      // תווים מיוחדים - מקף עברי (־) הוא בטווח הניקוד
      expect(hasNikud('־'), true);
      expect(hasNikud('׀'), true);
      expect(hasNikud('|'), false);

      // רווחים מרובים
      expect(removeVolwels('שָׁלוֹם    עוֹלָם'), 'שלום    עולם');
    });

    test('Real-world examples from Tanach', () {
      // בראשית א:א
      const verse1 =
          'בְּרֵאשִׁית בָּרָא אֱלֹהִים אֵת הַשָּׁמַיִם וְאֵת הָאָרֶץ';
      expect(hasNikud(verse1), true);
      expect(removeVolwels(verse1), 'בראשית ברא אלהים את השמים ואת הארץ');

      // תהלים כ"ג:א
      const verse2 = 'מִזְמוֹר לְדָוִד יְהוָה רֹעִי לֹא אֶחְסָר';
      expect(hasNikud(verse2), true);
      expect(removeVolwels(verse2), 'מזמור לדוד יהוה רעי לא אחסר');

      // שמע ישראל
      const shema = 'שְׁמַע יִשְׂרָאֵל יְהוָה אֱלֹהֵינוּ יְהוָה אֶחָד';
      expect(hasNikud(shema), true);
      expect(removeVolwels(shema), 'שמע ישראל יהוה אלהינו יהוה אחד');
    });

    test('replaceHolyNames should handle nikud before the holy name', () {
      expect(replaceHolyNames('לַֽיהֹוָֽה'), 'לַֽיקֹוָֽק');
      expect(replaceHolyNames('לִפְנֵי יְהֹוָֽה'), 'לִפְנֵי יְקֹוָֽק');
      expect(replaceHolyNames('לַיקֹוָק'), 'לַיקֹוָק');
    });

    test('replaceHolyNames should not replace inside larger words', () {
      expect(replaceHolyNames('ויגביהוהו'), 'ויגביהוהו');
    });

    test('Performance test - large text', () {
      // יצירת טקסט גדול עם ניקוד
      final largeText = 'שָׁלוֹם עוֹלָם ' * 1000;

      // בדיקה שהפונקציות עובדות על טקסט גדול
      expect(hasNikud(largeText), true);

      final stopwatch = Stopwatch()..start();
      final result = removeVolwels(largeText);
      stopwatch.stop();

      expect(result, 'שלום עולם ' * 1000);

      // וידוא שהפעולה מהירה (פחות מ-100ms)
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('Unicode ranges - nikud and teamim', () {
      // ניקוד: U+05B0-U+05C7
      expect(hasNikud('\u05B0'), true); // שווא
      expect(hasNikud('\u05B1'), true); // חטף סגול
      expect(hasNikud('\u05BB'), true); // קובוץ
      expect(hasNikud('\u05C7'), true); // קמץ קטן

      // טעמים: U+0591-U+05AF
      expect(hasNikud('\u0591'), true); // אתנחתא
      expect(hasNikud('\u05A3'), true); // מונח
      expect(hasNikud('\u05AF'), true); // מסורה

      // תווים שאינם ניקוד או טעמים
      expect(hasNikud('א'), false); // אלף רגילה
      expect(hasNikud('ת'), false); // תו רגילה
    });
  });
}
