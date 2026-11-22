import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';

import 'support/seeded_reference_library.dart';

/// כינויי ספרים שנגזרים בכללי הקוד (book_aliases.dart) באיתור מקורות: שם קיבוצי
/// של סט, הכותרת בלי מילות קישור, וקדימות לכינוי מילולי (#5599). הכותרות
/// והכינויים מנתוני הספרייה (seforim.db / SeforimAcronymizer).

const _rambamSukka = (
  id: 521,
  title: 'רמב"ם על משנה סוכה',
  acronyms: ['רמבם משנה סוכה'],
);

const _rambamBerakhot = (
  id: 556,
  title: 'רמב"ם על משנה ברכות',
  acronyms: [
    'פירוש הרמבם למשנה ברכות',
    'רמבם ברכות',
    'רמבם משנה ברכות',
    'רמבם ע"מ ברכות',
    'רמבם על משנה',
    'פרוש המשניות להרמבם ברכות',
  ],
);

const _rambamTaanit = (
  id: 522,
  title: 'רמב"ם על משנה תענית',
  acronyms: [
    'משנה תורה תענית',
    'משנתורה תענית',
    'רמב"ם תענית',
    'רמבם משנה תורה תענית',
  ],
);

const _kesefMishnehTaaniyot = (
  id: 3134,
  title: 'כסף משנה על משנה תורה, הלכות תעניות',
  acronyms: ['כסף משנה תעניות'],
);

const _rashbaBavaKamma = (
  id: 5739,
  title: 'רשב"א על בבא קמא',
  acronyms: ['רשבא בבא קמא', 'רשב"א', 'רשבא על בק'],
);

const _rashbaBavaBatra = (
  id: 5738,
  title: 'רשב"א על בבא בתרא',
  acronyms: ['רשב"א', 'רשבא על בב', 'רשבא ב"ב'],
);

const _mishnehTorahShevuot = (
  id: 329,
  title: 'משנה תורה, הלכות שבועות',
  acronyms: ['משנה תורה שבועות', 'רמב"ם הלכות שבועות', 'רמב"ם שבועות'],
);

void main() {
  tearDown(resetSeededLibrary);

  Future<List<String>> titlesFor(String query, List<SeedBook> books) async {
    seedLibrary(books);
    return [for (final r in await buildFindRefRepo().findRefs(query)) r.title];
  }

  ReferenceBookHit? hitFor(String query, int bookId) => ReferenceBooksCache
      .instance
      .search(query)
      .where((h) => h.bookId == bookId)
      .firstOrNull;

  group('שם קיבוצי של סט', () {
    for (final query in [
      'פיה"מ סוכה',
      'פירוש המשניות סוכה',
      'פרוש המשניות לרמב"ם סוכה',
    ]) {
      test('"$query" — "רמב"ם על משנה סוכה", שאין לו כינוי כזה', () async {
        final titles = await titlesFor(query, const [
          _rambamBerakhot,
          _rambamSukka,
        ]);

        expect(hitFor(query, _rambamSukka.id)?.namesBookExactly, isTrue);
        expect(titles.first, _rambamSukka.title);
      });
    }

    test('"פירוש המשניות" לבדו מחזיר את כל ספרי הסט', () {
      seedLibrary(const [_rambamBerakhot, _rambamSukka]);

      for (final book in [_rambamBerakhot, _rambamSukka]) {
        final hit = hitFor('פירוש המשניות', book.id);
        expect(hit?.matchRank, 4, reason: book.title);
        expect(hit!.acronymTailIsTitleWords, isTrue, reason: book.title);
      }
    });
  });

  test('הכותרת בלי מילות קישור היא כינוי', () async {
    final titles = await titlesFor('רמב"ם משנה תענית', const [
      _kesefMishnehTaaniyot,
      _rambamBerakhot,
      _rambamTaanit,
    ]);

    expect(
      hitFor('רמב"ם משנה תענית', _rambamTaanit.id)?.namesBookExactly,
      true,
    );
    expect(titles.first, _rambamTaanit.title);
  });

  group('מקרי השרשור (#5599)', () {
    test('"רשב"א בק" — רשב"א על בבא קמא', () async {
      final titles = await titlesFor('רשב"א בק', const [
        _rashbaBavaBatra,
        _rashbaBavaKamma,
      ]);
      expect(titles.first, _rashbaBavaKamma.title);
    });

    test('"רשב"א בב" — רשב"א על בבא בתרא', () async {
      final titles = await titlesFor('רשב"א בב', const [
        _rashbaBavaKamma,
        _rashbaBavaBatra,
      ]);
      expect(titles.first, _rashbaBavaBatra.title);
    });
  });

  test('כותרת מדויקת בלי "על" קודמת לכתיב חלופי של ספר אחר (#5710)', () async {
    const kilayim = (
      id: 557,
      title: 'רמב"ם על משנה כלאים',
      acronyms: ['רמב"ם משנה כלאים'],
    );
    const kelim = (
      id: 558,
      title: 'רמב"ם על משנה כלים',
      acronyms: ['ספר רמבם כלים', 'כלים לרמבם'],
    );
    final titles = await titlesFor('רמבם משנה כלים', const [kilayim, kelim]);

    expect(titles.first, kelim.title);
  });

  group('מילה אחרונה קטועה בהקלדה (#5721)', () {
    const nimukeiBavaKamma = (
      id: 2379,
      title: 'נימוקי יוסף על בבא קמא',
      acronyms: ['נימוקי יוסף בבא קמא', 'נימוקי יוסף על בק'],
    );
    const nimukeiBavaBatra = (
      id: 2382,
      title: 'נימוקי יוסף על בבא בתרא',
      acronyms: ['נימוקי יוסף בבא בתרא', 'נימוקי יוסף על בב'],
    );
    for (final query in [
      'נימוקי יוסף בבא ק',
      'נימוקי יוסף בבא קמ',
      'נימוקי יוסף על בבא ק',
    ]) {
      test('"$query" — נימוקי יוסף על בבא קמא', () async {
        final titles = await titlesFor(query, const [
          nimukeiBavaBatra,
          nimukeiBavaKamma,
        ]);
        expect(titles, [nimukeiBavaKamma.title]);
      });
    }

    test('נימוקי יוסף בב מציע את בבא קמא אחרי הכינוי המדויק', () async {
      final titles = await titlesFor('נימוקי יוסף בב', const [
        nimukeiBavaKamma,
        nimukeiBavaBatra,
      ]);

      expect(titles, [nimukeiBavaBatra.title, nimukeiBavaKamma.title]);
    });

    test('מיקום אחרי הכינוי המדויק נשאר הפניה לספר שבו נמצא', () async {
      seedLibrary(const [nimukeiBavaKamma, nimukeiBavaBatra]);
      final reference = '${nimukeiBavaBatra.title} דף ג';
      final results = await buildFindRefRepo(
        tocEntries: {
          nimukeiBavaBatra.id: [
            {'reference': reference, 'segment': 7, 'level': 1},
          ],
        },
      ).findRefs('נימוקי יוסף בב ג');

      expect(results.map((r) => r.reference), [reference]);
    });

    test('דף שאינו קיים אינו מחזיר ספר ששמו אינו מכיל את המילה', () async {
      final titles = await titlesFor('נימוקי יוסף בבא ש', const [
        nimukeiBavaBatra,
        nimukeiBavaKamma,
      ]);
      expect(titles, isEmpty);
    });
  });

  test('כינוי מילולי של ספר קודם לכותרת בלי מילת קישור של ספר אחר', () async {
    final titles = await titlesFor('רמב"ם שבועות', const [
      (id: 540, title: 'רמב"ם על שבועות', acronyms: <String>[]),
      _mishnehTorahShevuot,
    ]);

    expect(titles.first, _mishnehTorahShevuot.title);
  });

  test('חיפוש קבוצתי במסד מצורף עם מזהה SQLite רחב', () {
    const id = 4294967297;
    final index = BookTitleIndex(
      books: const [
        BookCacheEntry(
          id: id,
          title: 'פירוש על קורבן תודה',
          filePath: '',
          fileType: 'txt',
          categoryId: 0,
          orderIndex: 0,
        ),
      ],
      normalizedTitles: const {id: 'פירוש על קורבן תודה'},
    );
    const query = 'פירוש קורבן תודה';
    final book = index
        .searchBatch(['פירוש', query], limit: 20)
        .hitsFor(query, limit: 20)!
        .single;
    expect(book.bookId, id);
    expect(book.namesBookExactly, isTrue);
  });
}
