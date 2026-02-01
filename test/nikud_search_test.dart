import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text_manipulation.dart';

// ignore_for_file: dead_code

void main() {
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

    test('removeVolwels should remove nikud from text', () {
      // הסרת ניקוד בסיסי
      expect(removeVolwels('שָׁלוֹם'), 'שלום');
      expect(removeVolwels('בְּרֵאשִׁית'), 'בראשית');
      expect(removeVolwels('הַלְלוּיָהּ'), 'הללויה');

      // טקסט ללא ניקוד - צריך להישאר זהה
      expect(removeVolwels('שלום'), 'שלום');
      expect(removeVolwels('בראשית'), 'בראשית');

      // טקסט ריק
      expect(removeVolwels(''), '');

      // הסרת טעמים וניקוד
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

    test('Search workflow - nikud removal by default', () {
      // סימולציה של תהליך חיפוש
      const userInput = 'שָׁלוֹם עוֹלָם';

      // בדיקה אם יש ניקוד
      final hasNikudInInput = hasNikud(userInput);
      expect(hasNikudInInput, true);

      // הסרת ניקוד כברירת מחדל
      final searchQuery =
          hasNikudInInput ? removeVolwels(userInput) : userInput;
      expect(searchQuery, 'שלום עולם');

      // אם המשתמש לוחץ על "עם ניקוד" - משתמשים בטקסט המקורי
      final searchWithNikud = userInput;
      expect(searchWithNikud, 'שָׁלוֹם עוֹלָם');
    });

    test('Search workflow - no nikud in input', () {
      // סימולציה של תהליך חיפוש ללא ניקוד
      const userInput = 'שלום עולם';

      // בדיקה אם יש ניקוד
      final hasNikudInInput = hasNikud(userInput);
      expect(hasNikudInInput, false);

      // אין צורך להסיר ניקוד
      final searchQuery =
          hasNikudInInput ? removeVolwels(userInput) : userInput;
      expect(searchQuery, 'שלום עולם');
    });

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

  group('Integration Tests - Search Scenarios', () {
    test('Scenario 1: User types text with nikud', () {
      // משתמש מקליד טקסט עם ניקוד
      const userInput = 'תּוֹרָה';

      // המערכת מזהה שיש ניקוד
      expect(hasNikud(userInput), true);

      // ברירת מחדל: חיפוש ללא ניקוד
      var searchWithNikud = false;
      var query = !searchWithNikud && hasNikud(userInput)
          ? removeVolwels(userInput)
          : userInput;
      expect(query, 'תורה');

      // משתמש לוחץ על כפתור "עם ניקוד"
      searchWithNikud = true;
      query = !searchWithNikud && hasNikud(userInput)
          ? removeVolwels(userInput)
          : userInput;
      expect(query, 'תּוֹרָה');
    });

    test('Scenario 2: User types text without nikud', () {
      // משתמש מקליד טקסט ללא ניקוד
      const userInput = 'תורה';

      // המערכת מזהה שאין ניקוד
      expect(hasNikud(userInput), false);

      // הכפתור "עם ניקוד" לא צריך להופיע
      // החיפוש מתבצע כרגיל - אין ניקוד להסיר
      expect(removeVolwels(userInput), 'תורה');
    });

    test('Scenario 3: User pastes text with nikud from external source', () {
      // משתמש מדביק טקסט עם ניקוד מ-Sefaria או מקור אחר
      const pastedText = 'וַיְדַבֵּר אֱלֹהִים אֶל־מֹשֶׁה';

      // המערכת מזהה ניקוד
      expect(hasNikud(pastedText), true);

      // ברירת מחדל: הסרת ניקוד
      final cleanQuery = removeVolwels(pastedText);
      expect(cleanQuery, 'וידבר אלהים אל משה');

      // אם המשתמש רוצה לחפש עם הניקוד המדויק - משתמשים בטקסט המקורי
      expect(pastedText, 'וַיְדַבֵּר אֱלֹהִים אֶל־מֹשֶׁה');
    });

    test('Scenario 4: Mixed content - Hebrew with nikud and English', () {
      // טקסט מעורב
      const mixedInput = 'תּוֹרָה Torah שָׁלוֹם Shalom';

      expect(hasNikud(mixedInput), true);

      // ברירת מחדל: הסרת ניקוד
      final cleaned = removeVolwels(mixedInput);
      expect(cleaned, 'תורה Torah שלום Shalom');
    });

    test('Scenario 5: Toggle nikud button multiple times', () {
      const userInput = 'בְּרֵאשִׁית';
      var searchWithNikud = false;

      // לחיצה ראשונה - הפעלת חיפוש עם ניקוד
      searchWithNikud = !searchWithNikud;
      expect(searchWithNikud, true);
      var query = !searchWithNikud && hasNikud(userInput)
          ? removeVolwels(userInput)
          : userInput;
      expect(query, 'בְּרֵאשִׁית');

      // לחיצה שנייה - חזרה לחיפוש ללא ניקוד
      searchWithNikud = !searchWithNikud;
      expect(searchWithNikud, false);
      query = !searchWithNikud && hasNikud(userInput)
          ? removeVolwels(userInput)
          : userInput;
      expect(query, 'בראשית');

      // לחיצה שלישית - שוב עם ניקוד
      searchWithNikud = !searchWithNikud;
      expect(searchWithNikud, true);
      query = !searchWithNikud && hasNikud(userInput)
          ? removeVolwels(userInput)
          : userInput;
      expect(query, 'בְּרֵאשִׁית');
    });
  });
}
