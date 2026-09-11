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

const _categoryPaths = {
  296: 'הלכה, משנה תורה, ספר מדע',
  308: 'הלכה, משנה תורה, ספר זמנים',
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
