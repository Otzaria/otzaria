import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

void main() {
  group('highLight', () {
    test('single word - highlights the word', () {
      const text = 'כל יום טוב';
      final result = highLight(text, 'יום');
      expect(result, contains('<span style="color: red">'));
      expect(result, contains('יום'));
    });

    test('multi-word query - highlights only the complete sequence', () {
      // "כל היום" should be highlighted only where both words appear together
      const text = 'היה זה כל היום טוב';
      final result = highLight(text, 'כל היום');
      // המילה "היה" לא אמורה להיות מודגשת
      expect(result, isNot(contains('<span style="color: red">היה')));
      // רק מילות החיפוש עצמן אמורות להיות מודגשות
      expect(
        result,
        contains(
          '<span style="color: red">כל</span> <span style="color: red">היום</span>',
        ),
      );
      // "היה", "זה", "טוב" לא אמורים להיות מודגשים
      expect(result, isNot(contains('<span style="color: red">טוב')));
    });

    test('multi-word query - does not highlight lone words from query', () {
      // אם מחפשים "כל היום", מילה בודדת "כל" לא אמורה להיות מודגשת
      const text = 'כל הספרים היו שם';
      final result = highLight(text, 'כל היום');
      // אין מופע של "כל היום" יחד - לכן לא אמור להיות highlighting כלל
      expect(result, isNot(contains('<span')));
    });

    test('single word - does not highlight inside another word by default', () {
      const text = 'ויאמר משה';
      final result = highLight(text, 'אמר');

      expect(result, isNot(contains('<span')));
    });

    test('single word - can highlight inside another word when enabled', () {
      const text = 'ויאמר משה';
      final result = highLight(
        text,
        'אמר',
        searchOptions: const {
          'אמר_0': {'חלק ממילה': true},
        },
      );

      expect(result, contains('<span style="color: red">אמר</span>'));
    });

    test('multi-word query with spacing - highlights spaced phrase', () {
      const text = 'היה זה כל דבר היום טוב';
      final result = highLight(
        text,
        'כל היום',
        spacingValues: const {'0-1': '1'},
      );

      expect(
        result,
        contains(
          '<span style="color: red">כל</span> דבר <span style="color: red">היום</span>',
        ),
      );
      expect(result, isNot(contains('<span style="color: red">דבר</span>')));
    });

    test('multi-word query with spacing - respects spacing limit', () {
      const text = 'היה זה כל דבר נוסף היום טוב';
      final result = highLight(
        text,
        'כל היום',
        spacingValues: const {'0-1': '1'},
      );

      expect(result, isNot(contains('<span')));
    });

    test('multi-word query with spacing - ignores punctuation between words',
        () {
      const text = 'אמר ליה רבי יוחנן: הוא אפילו תינוקות';
      final result = highLight(
        text,
        'אמר רבי יוחנן הוא',
        spacingValues: const {'0-1': '1'},
      );

      expect(
        result,
        contains(
          '<span style="color: red">אמר</span> ליה <span style="color: red">רבי</span> <span style="color: red">יוחנן</span>: <span style="color: red">הוא</span>',
        ),
      );
      expect(result, isNot(contains('<span style="color: red">ליה</span>')));
    });

    test(
        'multi-word query with one spacing value - applies max spacing to all gaps',
        () {
      const text = 'אמר רבי שמעון בן לקיש';
      final result = highLight(
        text,
        'אמר שמעון לקיש',
        spacingValues: const {'0-1': '1'},
      );

      expect(
        result,
        contains(
          '<span style="color: red">אמר</span> רבי <span style="color: red">שמעון</span> בן <span style="color: red">לקיש</span>',
        ),
      );
      expect(result, isNot(contains('<span style="color: red">רבי</span>')));
      expect(result, isNot(contains('<span style="color: red">בן</span>')));
    });

    test('single word with nikud in text - highlights correctly', () {
      const text = 'הָיָה כָּל הַיּוֹם';
      final result = highLight(text, 'כל');
      expect(result, contains('<span style="color: red">'));
    });

    test('multi-word with nikud and spacing - highlights both words', () {
      const text = 'וְעַתָּה יֵרֶא פַּרְעֹה אִישׁ נָבוֹן וְחָכָם';
      final result = highLight(
        text,
        'פרעה נבון',
        spacingValues: const {'0-1': '1'},
      );

      expect(result, contains('<span style="color: red">פַּרְעֹה</span>'));
      expect(result, contains('<span style="color: red">נָבוֹן</span>'));
    });

    test('multi-word with nikud and searchDistance - highlights both words', () {
      const text = 'וְעַתָּה יֵרֶא פַּרְעֹה אִישׁ נָבוֹן וְחָכָם';
      final result = highLight(
        text,
        'פרעה נבון',
        searchDistance: 1,
      );

      expect(result, contains('<span style="color: red">פַּרְעֹה</span>'));
      expect(result, contains('<span style="color: red">נָבוֹן</span>'));
    });
  });

  group('removePunctuation', () {
    test('keeps dot and colon inside nested parentheses', () {
      const input = 'שלום: עולם! (א:ב. (ג:ד.))';

      final result = removePunctuation(input);

      expect(result, equals('שלום עולם (א:ב. (ג:ד.))'));
    });

    test('keeps allowed punctuation at end of line', () {
      const input = 'משפט עם נקודה.';

      final result = removePunctuation(input);

      expect(result, equals('משפט עם נקודה.'));
    });
  });
}
