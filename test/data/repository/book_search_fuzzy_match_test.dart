import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';

/// בדיקות להתאמה הסלחנית של חיפוש ספרים בספרייה.
/// הדרישה המרכזית: הדדיות — אם א' מוצא את ב', גם ב' מוצא את א'.
void main() {
  group('bookSearchWordMatchesFuzzy - הדדיות כתיב מלא/חסר', () {
    const reciprocalPairs = [
      ('מדות', 'מידות'),
      ('קדושין', 'קידושין'),
      ('חדושי', 'חידושי'),
      ('קצור', 'קיצור'),
    ];

    for (final (haser, male) in reciprocalPairs) {
      test('$haser ↔ $male - שני הכיוונים', () {
        expect(
          bookSearchWordMatchesFuzzy(haser, 'משנה $male'),
          isTrue,
          reason: "'$haser' אמור למצוא '$male'",
        );
        expect(
          bookSearchWordMatchesFuzzy(male, 'משנה $haser'),
          isTrue,
          reason: "'$male' אמור למצוא '$haser'",
        );
      });
    }
  });

  group('bookSearchWordMatchesFuzzy - מניעת התאמות שווא', () {
    test('מילים קצרות באותו אורך נשארות מדויקות', () {
      expect(bookSearchWordMatchesFuzzy('מדות', 'ספר מצות'), isFalse);
      expect(bookSearchWordMatchesFuzzy('אבות', 'ספר עדות'), isFalse);
    });

    test('מילה קצרה מ-3 אותיות - רק התאמת substring, בלי fuzzy', () {
      expect(bookSearchWordMatchesFuzzy('שב', 'מסכת שבת'), isTrue);
      expect(bookSearchWordMatchesFuzzy('שג', 'מסכת שבת'), isFalse);
      expect(bookSearchWordMatchesFuzzy('שבת', 'מסכת שבות'), isFalse);
    });

    test('פער של שתי אותיות במילה קצרה אינו מותאם', () {
      expect(bookSearchWordMatchesFuzzy('מדות', 'ספר מהדורות'), isFalse);
    });

    test('התאמת substring מדויקת עדיין עובדת', () {
      expect(bookSearchWordMatchesFuzzy('קידושין', 'מאירי על קידושין'), isTrue);
    });

    test('שיכול אותיות סמוכות נספר כשגיאה אחת', () {
      expect(bookSearchWordMatchesFuzzy('אבועלפיה', 'רבי אבולעפיה'), isTrue);
    });
  });

  group('filterBookSearchEntries - התאמה דרך כינויים', () {
    const entries = [
      BookSearchEntry(
        index: 0,
        title: 'קידושין',
        author: '',
        topics: '',
        acronyms: ['מסכת קידושין', 'גמרא קידושין'],
      ),
      BookSearchEntry(
        index: 1,
        title: 'ספר המדות',
        author: '',
        topics: '',
        acronyms: ['ספר המידות'],
      ),
      BookSearchEntry(
        index: 2,
        title: 'מסילת ישרים',
        author: 'רמח"ל',
        topics: '',
      ),
    ];

    List<int> search(String query) => filterBookSearchEntries(
      entries: entries,
      queryWords: query.split(' '),
      topics: const [],
      sortByRatio: true,
      normalizedQuery: query,
    );

    test('שאילתה שתואמת רק כינוי מוצאת את הספר', () {
      expect(search('מסכת קידושין'), contains(0));
    });

    test('כינוי בכתיב אחר מהכותרת נמצא בשני הכתיבים', () {
      expect(search('ספר המידות'), contains(1));
      expect(search('ספר המדות'), contains(1));
    });

    test('התאמה סלחנית עובדת גם על כינויים', () {
      expect(search('מסכת קדושין'), contains(0));
    });

    test('התאמה מדויקת בכותרת מדורגת לפני התאמה בכינוי', () {
      const withTitleMatch = [
        ...entries,
        BookSearchEntry(
          index: 3,
          title: 'מסכת קידושין מבוארת',
          author: '',
          topics: '',
        ),
      ];
      final results = filterBookSearchEntries(
        entries: withTitleMatch,
        queryWords: 'מסכת קידושין'.split(' '),
        topics: const [],
        sortByRatio: true,
        normalizedQuery: 'מסכת קידושין',
      );
      expect(results.indexOf(3), lessThan(results.indexOf(0)));
    });

    test('ספר בלי כינויים לא מושפע', () {
      expect(search('מסילת ישרים'), equals([2]));
    });

    test('בתוך אותה שכבת רלוונטיות, סדר הדורות קודם ל-ratio', () {
      // שני הספרים מכילים את השאילתה אך אינם התאמה מדויקת (אותה שכבה);
      // הדור צריך להכריע לפני ה-ratio.
      const byEra = [
        // אחרון עם כותרת קצרה (ratio גבוה) - בכל זאת אמור לרדת מתחת לראשון.
        BookSearchEntry(
          index: 0,
          title: 'דיני שכירות',
          author: '',
          topics: '',
          eraOrder: 3,
        ),
        // ראשון עם כותרת ארוכה (ratio נמוך) - אמור לצוף מעל האחרון.
        BookSearchEntry(
          index: 1,
          title: 'משנה תורה, הלכות שכירות',
          author: '',
          topics: '',
          eraOrder: 2,
        ),
      ];
      final results = filterBookSearchEntries(
        entries: byEra,
        queryWords: const ['שכירות'],
        topics: const [],
        sortByRatio: true,
        normalizedQuery: 'שכירות',
      );
      expect(
        results,
        equals([1, 0]),
        reason: 'הראשונים (1) קודמים לאחרונים (0) למרות ratio נמוך יותר',
      );
    });

    test('בתוך אותו דור, ספר אישי תמיד אחרון', () {
      // שני ספרים מאותו דור ואותה שכבה — האישי יורד מתחת לרשמי
      // גם כש-ratio שלו גבוה יותר.
      const userVsOfficial = [
        BookSearchEntry(
          index: 0,
          title: 'שכירות בית',
          author: '',
          topics: '',
          eraOrder: 5,
          isUserBook: true,
        ),
        BookSearchEntry(
          index: 1,
          title: 'הלכות שכירות מפורטות',
          author: '',
          topics: '',
          eraOrder: 5,
        ),
      ];
      final results = filterBookSearchEntries(
        entries: userVsOfficial,
        queryWords: const ['שכירות'],
        topics: const [],
        sortByRatio: true,
        normalizedQuery: 'שכירות',
      );
      expect(
        results,
        equals([1, 0]),
        reason: 'הספר האישי (0) אחרון למרות ratio גבוה יותר',
      );
    });

    test('התאמה מדויקת לכותרת גוברת על סדר הדורות', () {
      // ספר יסוד נטול-דור ('קידושין', other) אך התאמה מדויקת — אמור לצוף מעל
      // פירוש מתוארך (ראשונים) שרק מכיל את השאילתה. זה מונע קבירת המסכת.
      const exactVsEra = [
        BookSearchEntry(
          index: 0,
          title: 'חידושי הר"ן על קידושין',
          author: '',
          topics: '',
          eraOrder: 2,
        ),
        BookSearchEntry(
          index: 1,
          title: 'קידושין',
          author: '',
          topics: '',
          eraOrder: 5,
        ),
      ];
      final results = filterBookSearchEntries(
        entries: exactVsEra,
        queryWords: const ['קידושין'],
        topics: const [],
        sortByRatio: true,
        normalizedQuery: 'קידושין',
      );
      expect(results.first, 1, reason: 'המסכת המדויקת קודמת לפירוש המתוארך');
    });

    test('שכבת רלוונטיות גוברת על סדר הדורות', () {
      // התאמת כותרת מדויקת (שכבה 2) של אחרון גוברת על התאמת כינוי (שכבה 1)
      // של ראשון, גם אם הדור מאוחר יותר.
      const mixed = [
        BookSearchEntry(
          index: 0,
          title: 'קידושין',
          author: '',
          topics: '',
          acronyms: ['מסכת קידושין'],
          eraOrder: 2,
        ),
        BookSearchEntry(
          index: 1,
          title: 'מסכת קידושין מבוארת',
          author: '',
          topics: '',
          eraOrder: 3,
        ),
      ];
      final results = filterBookSearchEntries(
        entries: mixed,
        queryWords: 'מסכת קידושין'.split(' '),
        topics: const [],
        sortByRatio: true,
        normalizedQuery: 'מסכת קידושין',
      );
      expect(
        results.indexOf(1),
        lessThan(results.indexOf(0)),
        reason: 'התאמת כותרת (שכבה גבוהה) גוברת על דור מוקדם יותר בכינוי',
      );
    });

    test('כותרת מדויקת מדורגת לפני כותרת ארוכה שמכילה את השאילתה', () {
      const withExactAndLong = [
        BookSearchEntry(
          index: 0,
          title: 'ביאור על מסכת סוטה',
          author: '',
          topics: '',
        ),
        BookSearchEntry(index: 1, title: 'מסכת סוטה', author: '', topics: ''),
        BookSearchEntry(index: 2, title: 'סוטה', author: '', topics: ''),
      ];
      final results = filterBookSearchEntries(
        entries: withExactAndLong,
        queryWords: const ['סוטה'],
        topics: const [],
        sortByRatio: true,
        normalizedQuery: 'סוטה',
      );
      expect(
        results.first,
        2,
        reason: "'סוטה' המדויק אמור לצוף מעל כותרות ארוכות שמכילות אותו",
      );
      expect(results.indexOf(1), lessThan(results.indexOf(0)));
    });
  });

  group('buildBookSearchEntry - בידוד מרחבי id של ספר אישי', () {
    // ה-lookups מדמים מאגר רשמי שבו id=7 שייך לספר רשמי זר עם כינוי ודור מוקדם.
    List<String>? acronymsForId(int id) => id == 7 ? const ['רמבם'] : null;
    int eraOrderForId(int? id, bool isUserBook) =>
        (!isUserBook && id == 7) ? 2 : 5;

    test('ספר אישי עם id מתנגש מקבל כינויים ריקים ודור ברירת מחדל', () {
      final userBook = TextBook(id: 7, title: 'הספר שלי', isUserBook: true);
      final entry = buildBookSearchEntry(
        0,
        userBook,
        acronymsForId: acronymsForId,
        eraOrderForId: eraOrderForId,
      );
      expect(
        entry.acronyms,
        isEmpty,
        reason: 'ספר אישי לא יורש כינוי של ספר רשמי בעל אותו id',
      );
      expect(
        entry.eraOrder,
        5,
        reason: 'ספר אישי לא יורש דור מוקדם של ספר רשמי בעל אותו id',
      );
      expect(entry.isUserBook, isTrue);
    });

    test('ספר רשמי עם אותו id כן מקבל את הכינוי והדור מהמאגר', () {
      final officialBook = TextBook(id: 7, title: 'משנה תורה');
      final entry = buildBookSearchEntry(
        0,
        officialBook,
        acronymsForId: acronymsForId,
        eraOrderForId: eraOrderForId,
      );
      expect(entry.acronyms, equals(['רמבם']));
      expect(entry.eraOrder, 2);
      expect(entry.isUserBook, isFalse);
    });
  });
}
