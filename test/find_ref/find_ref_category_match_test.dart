import 'package:flutter_test/flutter_test.dart';

import 'support/seeded_reference_library.dart';

/// זנב שאילתה שהוא שם הקטגוריה שהספר יושב בה ("רמבם המדע"). "מדע" אינו
/// מופיע בשום כותרת, ראש-תיבות או כותרת פנימית — רק בקטגוריה "ספר מדע".

// --- נתוני אמת מ-seforim.db (ראשי-תיבות: מדגם ללא גרש) ---

const _yesodeiHatorah = (
  id: 296,
  title: 'משנה תורה, הלכות יסודי התורה',
  acronyms: [
    'משנה תורה יסודי התורה',
    'רמב"ם הלכות יסודי התורה',
    'רמב"ם יסודי התורה',
    'רמבם יסודי התורה',
  ],
);

const _hilchotShabbat = (
  id: 308,
  title: 'משנה תורה, הלכות שבת',
  acronyms: [
    'משנה תורה הלכות שבת',
    'רמב"ם הלכות שבת',
    'רמב"ם שבת',
    'רמבם שבת',
  ],
);

const _hilchotSanhedrin = (
  id: 375,
  title: 'משנה תורה, הלכות סנהדרין והעונשין המסורין להם',
  acronyms: ['הרמבם הלכות סנהדרין', 'הרמבם סנהדרין', 'רמבם סנהדרין'],
);

const _kiryatSeferShabbat = (
  id: 5042,
  title: 'קרית ספר על משנה תורה, הלכות שבת',
  acronyms: ['קרית ספר על רמבם, הלכות שבת'],
);

const _categoryPaths = {
  296: 'הלכה, משנה תורה, ספר מדע',
  308: 'הלכה, משנה תורה, ספר זמנים',
  375: 'הלכה, משנה תורה, ספר שופטים',
  5042: 'הלכה, משנה תורה, מפרשים, קרית ספר, ספר זמנים',
  7: 'תנ"ך, נביאים',
  7286: 'תלמוד בבלי, אחרונים, שמות בארץ',
  2: 'תנ"ך, תורה',
};

void main() {
  tearDown(resetSeededLibrary);

  group('findRefs — זנב שהוא שם הקטגוריה', () {
    test('"רמבם המדע" מחזיר את הלכות ספר מדע', () async {
      seedLibrary(const [
        _yesodeiHatorah,
        _hilchotShabbat,
      ], categoryPaths: _categoryPaths);

      final titles = (await buildFindRefRepo().findRefs(
        'רמבם המדע',
      )).map((r) => r.title).toList();

      expect(titles, ['משנה תורה, הלכות יסודי התורה']);
    });

    test('"רמבם זמנים" מחזיר רק את הלכות ספר זמנים', () async {
      seedLibrary(const [
        _yesodeiHatorah,
        _hilchotShabbat,
      ], categoryPaths: _categoryPaths);

      final titles = (await buildFindRefRepo().findRefs(
        'רמבם זמנים',
      )).map((r) => r.title).toList();

      expect(titles, ['משנה תורה, הלכות שבת']);
    });

    test(
      'נמצא גם כשספרים שכותרתם "רמבם" גומרים את תקרת חיפושי ה-TOC',
      () async {
        // בספרייה האמיתית כ-60 ספרי "רמב"ם על משנה X" קודמים לספרי משנה תורה.
        seedLibrary([
          for (var i = 0; i < 60; i++)
            (
              id: 1000 + i,
              title: 'רמבם על משנה $i',
              acronyms: const <String>[],
            ),
          _hilchotShabbat,
        ], categoryPaths: _categoryPaths);

        final titles = (await buildFindRefRepo().findRefs(
          'רמבם זמנים',
        )).map((r) => r.title).toList();

        expect(titles, ['משנה תורה, הלכות שבת']);
      },
    );

    test('זנב שהוא גם שם ספר ("שופטים") מחזיר את הלכות ספר שופטים', () async {
      // "שופטים" הוא ספר בתנ"ך, ולכן חיפוש ה-TOC מדולג.
      seedLibrary(const [
        _hilchotSanhedrin,
        (id: 7, title: 'שופטים', acronyms: <String>[]),
      ], categoryPaths: _categoryPaths);

      final titles = (await buildFindRefRepo().findRefs(
        'רמבם שופטים',
      )).map((r) => r.title).toList();

      expect(titles, contains(_hilchotSanhedrin.title));
    });

    test('זנב שהוא שם ספר אינו מתאים לחלק משם התיקייה', () async {
      // "שמות" הוא מילה אחת מתוך "שמות בארץ", ולא שם התיקייה.
      seedLibrary(const [
        (id: 7286, title: 'יום תרועה', acronyms: <String>[]),
        (id: 2, title: 'שמות', acronyms: <String>[]),
      ], categoryPaths: _categoryPaths);

      final titles = (await buildFindRefRepo().findRefs(
        'יום שמות',
      )).map((r) => r.title).toList();

      expect(titles, isNot(contains('יום תרועה')));
    });

    test(
      '"רמבם ספר זמנים": "ספר" בכותרת המפרש אינו מקדים את משנה תורה',
      () async {
        seedLibrary(const [
          _kiryatSeferShabbat,
          _hilchotShabbat,
        ], categoryPaths: _categoryPaths);

        final titles = (await buildFindRefRepo().findRefs(
          'רמבם ספר זמנים',
        )).map((r) => r.title).toList();

        expect(titles, [_hilchotShabbat.title, _kiryatSeferShabbat.title]);
      },
    );

    test('קטגוריה ו-TOC יחד: אותו דירוג בכל סדר ספרייה', () async {
      const kiryatSeferEruvin = (
        id: 5043,
        title: 'קרית ספר על משנה תורה, הלכות עירובין',
        acronyms: ['קרית ספר על רמבם הלכות עירובין'],
      );
      for (final books in [
        [_hilchotShabbat, _kiryatSeferShabbat, kiryatSeferEruvin],
        [_hilchotShabbat, kiryatSeferEruvin, _kiryatSeferShabbat],
        [_kiryatSeferShabbat, _hilchotShabbat, kiryatSeferEruvin],
        [_kiryatSeferShabbat, kiryatSeferEruvin, _hilchotShabbat],
        [kiryatSeferEruvin, _hilchotShabbat, _kiryatSeferShabbat],
        [kiryatSeferEruvin, _kiryatSeferShabbat, _hilchotShabbat],
      ]) {
        seedLibrary(
          books,
          categoryPaths: {
            ..._categoryPaths,
            5043: 'הלכה, משנה תורה, מפרשים, קרית ספר, ספר זמנים',
          },
        );
        final refs = await buildFindRefRepo(
          tocEntries: {
            5043: [
              {'reference': 'ספר זמנים', 'segment': 7, 'level': 2},
            ],
          },
        ).findRefs('רמבם ספר זמנים');

        expect(refs.map((r) => r.bookId), [308, 5042, 5043]);
        expect(refs.map((r) => r.isCategoryMatch), [true, true, false]);
        expect(refs.last.segment, 7);
        resetSeededLibrary();
      }
    });

    test('segment אב ("הלכה") אינו מחזיר כלום', () async {
      // "הלכה" משותף לאלפי ספרים; רק העלה — הקטגוריה הישירה — נבדק.
      seedLibrary(const [
        _yesodeiHatorah,
        _hilchotShabbat,
      ], categoryPaths: _categoryPaths);

      final refs = await buildFindRefRepo().findRefs('רמבם הלכה');

      expect(refs, isEmpty);
    });

    test('כותרת פנימית מנצחת את שם הקטגוריה', () async {
      // ל-296 יש ערך TOC בשם "מדע" — אז התוצאה היא הכותרת הפנימית ולא הספר.
      seedLibrary(const [_yesodeiHatorah], categoryPaths: _categoryPaths);

      final refs = await buildFindRefRepo(
        tocEntries: {
          296: [
            {
              'reference': 'משנה תורה, הלכות יסודי התורה, מדע',
              'segment': 7,
              'level': 2,
            },
          ],
        },
      ).findRefs('רמבם המדע');

      expect(refs.map((r) => r.segment), [7]);
    });
  });
}
