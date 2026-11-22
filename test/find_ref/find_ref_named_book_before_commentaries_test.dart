import 'package:flutter_test/flutter_test.dart';

import 'support/seeded_reference_library.dart';

/// ספר שאינו ספר יסוד ומפרשיו: השם המדויק בשאילתה קודם לסדר הספרייה (#5741).
/// הכותרות, הכינויים והתיקיות מ-seforim.db; הספר אחרון כמו ב-orderIndex שלו.

const _yedeiMoshe = (
  id: 3069,
  title: 'ידי משה על שמות רבה',
  acronyms: ['ידי משה', 'ידי משה על שר'],
);

const _etzYosef = (
  id: 3090,
  title: 'עץ יוסף על שמות רבה',
  acronyms: ['עץ יוסף', 'עץ יוסף על שר', 'עץ יוסף שמות רבה'],
);

const _shemotRabbah = (
  id: 257,
  title: 'שמות רבה',
  acronyms: ['רבה שמות', 'שמו"ר', 'שמות רבא', 'שמר', 'שר'],
);

const _paths = {
  3069: 'מדרש, אגדה, מדרש רבה, מפרשים, ידי משה',
  3090: 'מדרש, אגדה, מדרש רבה, מפרשים, עץ יוסף',
  257: 'מדרש, אגדה, מדרש רבה',
};

Map<String, dynamic> _chapter(String title) => {
  'reference': '$title פרק מה',
  'segment': 40,
  'level': 1,
};

void main() {
  tearDown(resetSeededLibrary);

  test('"שמות רבה מה" — שמות רבה לפני מפרשיו', () async {
    seedLibrary(const [
      _yedeiMoshe,
      _etzYosef,
      _shemotRabbah,
    ], categoryPaths: _paths);
    final results = await buildFindRefRepo(
      tocEntries: {
        for (final book in [_yedeiMoshe, _etzYosef, _shemotRabbah])
          book.id: [_chapter(book.title)],
      },
    ).findRefs('שמות רבה מה');

    expect(results.map((r) => r.title), [
      _shemotRabbah.title,
      _yedeiMoshe.title,
      _etzYosef.title,
    ]);
  });

  test('הפניה מלאה במפרש קודמת להפניה חלקית בספר', () async {
    seedLibrary(const [_yedeiMoshe, _shemotRabbah], categoryPaths: _paths);
    final results = await buildFindRefRepo(
      tocEntries: {
        _yedeiMoshe.id: [
          {
            'reference': '${_yedeiMoshe.title} פרק מה פסקה ב אות ג',
            'segment': 590,
            'level': 3,
          },
        ],
        _shemotRabbah.id: [
          {
            'reference': '${_shemotRabbah.title} פרק מה אות ב',
            'segment': 465,
            'level': 2,
            'partialMatch': true,
          },
        ],
      },
    ).findRefs('שמות רבה מה ב ג');

    expect(results.map((r) => r.title), [
      _yedeiMoshe.title,
      _shemotRabbah.title,
    ]);
  });

  test('כינוי שמשותף לכמה ספרים אינו מקדים אחד מהם', () async {
    const rashbaBavaKamma = (
      id: 5739,
      title: 'רשב"א על בבא קמא',
      acronyms: ['רשב"א'],
    );
    const rashbaBavaBatra = (
      id: 5738,
      title: 'רשב"א על בבא בתרא',
      acronyms: ['רשב"א'],
    );
    const students = (
      id: 9001,
      title: 'תלמידי רשב"א על בבא מציעא',
      acronyms: <String>[],
    );
    seedLibrary(const [students, rashbaBavaKamma, rashbaBavaBatra]);
    final results = await buildFindRefRepo(
      tocEntries: {
        for (final book in [students, rashbaBavaKamma, rashbaBavaBatra])
          book.id: [_chapter(book.title)],
      },
    ).findRefs('רשבא מה');

    expect(results.map((r) => r.title), [
      students.title,
      rashbaBavaKamma.title,
      rashbaBavaBatra.title,
    ]);
  });
}
