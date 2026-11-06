import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';

import 'support/seeded_reference_library.dart';

void main() {
  tearDown(resetSeededLibrary);

  test(
    'כינוי מדויק של פירוש אינו דוחק ספר יסוד והתאמות של מילים שלמות',
    () async {
      seedLibrary(
        [
          (id: 308, title: 'משנה תורה הלכות שבת', acronyms: const []),
          (
            id: 5325,
            title: 'דברי ירמיהו על משנה תורה הלכות שבת',
            acronyms: const ['הלכות שבת'],
          ),
          for (var i = 0; i < 25; i++)
            (id: 10000 + i, title: 'חיבור נפרד $i', acronyms: const []),
        ],
        categoryPaths: {
          308: 'הלכה, משנה תורה, ספר זמנים',
          5325: 'הלכה, משנה תורה, אחרונים',
          for (var i = 0; i < 25; i++) 10000 + i: 'הלכה, ראשונים',
        },
      );
      final repo = FindRefRepository(
        isReferenceBooksCacheLoaded: () => true,
        warmUpReferenceBooksCache: () async {},
        getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
        getAltTocEntriesForReference: (_, _, {queryTokens}) async => const [],
        getAllAltTocFlatEntries: () async => [
          for (var i = 0; i < 25; i++)
            {
              'bookId': 10000 + i,
              'bookTitle': 'חיבור נפרד $i',
              'bookOrderIndex': i.toDouble(),
              'reference': 'הלכות שבת',
              'segment': 1,
              'level': 2,
            },
        ],
        getCategoryPath: (_) async => '',
      );
      addTearDown(repo.dispose);
      final results = await repo.findRefs('הלכות שבת');
      expect(results.first.bookId, 308);
      expect(results.map((r) => r.bookId), contains(5325));
    },
  );

  test('כינויים קצרים משאירים מכסת תוכן עניינים לנושא המבוקש', () async {
    seedLibrary([
      for (var i = 0; i < 50; i++)
        (
          id: 10000 + i,
          title: 'משנה תורה הלכות נושא $i',
          acronyms: const ['רמבם'],
        ),
      (
        id: 4050,
        title: 'לחם משנה על משנה תורה הלכות שבת',
        acronyms: const ['לחם משנה על רמבם הלכות שבת'],
      ),
    ]);
    final lookedUp = <int>[];
    final repo = FindRefRepository(
      isReferenceBooksCacheLoaded: () => true,
      warmUpReferenceBooksCache: () async {},
      getTocEntriesForReference: (id, _, {queryTokens}) async {
        lookedUp.add(id);
        return id == 4050
            ? [
                {
                  'reference': 'לחם משנה על משנה תורה הלכות שבת פרק א',
                  'segment': 2,
                  'level': 1,
                },
              ]
            : const [];
      },
      getAltTocEntriesForReference: (_, _, {queryTokens}) async => const [],
      getAllAltTocFlatEntries: () async => const [],
      getCategoryPath: (_) async => '',
    );
    addTearDown(repo.dispose);
    final results = await repo.findRefs('רמבם שבת א');
    expect(lookedUp, hasLength(50));
    expect(lookedUp, contains(4050));
    expect(results.map((r) => r.bookId), contains(4050));
  });
  test('כינוי מדויק למסכת קודם לכינוי שמכיל אותו במשנה', () async {
    seedLibrary(
      [
        (id: 123, title: 'בבא מציעא', acronyms: const ['ב"מ']),
        (id: 71, title: 'משנה בבא מציעא', acronyms: const ['משנה במ']),
      ],
      categoryPaths: {
        123: 'תלמוד בבלי, סדר נזיקין',
        71: 'משנה, סדר נזיקין',
      },
    );
    final repo = FindRefRepository(
      isReferenceBooksCacheLoaded: () => true,
      warmUpReferenceBooksCache: () async {},
      getTocEntriesForReference: (id, _, {queryTokens}) async => id == 123
          ? [
              {'reference': 'בבא מציעא דף ב עמוד ב', 'segment': 14, 'level': 1},
            ]
          : const [],
      getAltTocEntriesForReference: (_, _, {queryTokens}) async => const [],
      getAllAltTocFlatEntries: () async => const [],
      resolveLineRefs: (ids, key) async => {
        if (ids.contains(71) && key == 'ב ב')
          71: (lineIndex: 12, lineId: 1, heRef: 'משנה בבא מציעא, ב, ב'),
      },
      getCategoryPath: (_) async => '',
    );
    addTearDown(repo.dispose);
    final results = await repo.findRefs('במ ב ב');
    expect(results.first.bookId, 123);
    expect(results.first.segment, 14);
    expect(results.map((r) => r.bookId), contains(71));
  });
  test('מילת כותרת שלמה שומרת מקום לפני כינויים במכסת תוכן העניינים', () async {
    seedLibrary([
      for (var i = 0; i < 50; i++)
        (id: 10000 + i, title: 'חיבור נפרד $i', acronyms: const ['רמבם']),
      (id: 556, title: 'רמב"ם על משנה ברכות', acronyms: const []),
    ]);
    final lookedUp = <int>[];
    final repo = FindRefRepository(
      isReferenceBooksCacheLoaded: () => true,
      warmUpReferenceBooksCache: () async {},
      getTocEntriesForReference: (id, _, {queryTokens}) async {
        lookedUp.add(id);
        return id == 556
            ? [
                {
                  'reference': 'רמב"ם על משנה ברכות פרק א',
                  'segment': 2,
                  'level': 1,
                },
              ]
            : const [];
      },
      getAltTocEntriesForReference: (_, _, {queryTokens}) async => const [],
      getAllAltTocFlatEntries: () async => const [],
      getCategoryPath: (_) async => '',
    );
    addTearDown(repo.dispose);
    final results = await repo.findRefs('רמבם א');
    expect(lookedUp, hasLength(50));
    expect(lookedUp, contains(556));
    expect(results.map((r) => r.bookId), contains(556));
  });

  test('כינוי מדויק אינו מקדם כל AltToc מעל התאמות הכותרת', () async {
    seedLibrary([
      for (var i = 0; i < 60; i++)
        (id: 1000 + i, title: 'מאירי על ספר $i', acronyms: const []),
      (id: 6418, title: 'אגרות משה אורח חיים א', acronyms: const ['מא']),
      for (var i = 0; i < 25; i++)
        (id: 20000 + i, title: 'חיבור נפרד $i', acronyms: const []),
    ]);
    final repo = FindRefRepository(
      isReferenceBooksCacheLoaded: () => true,
      warmUpReferenceBooksCache: () async {},
      getTocEntriesForReference: (_, _, {queryTokens}) async => const [],
      getAltTocEntriesForReference: (_, _, {queryTokens}) async => const [],
      getAllAltTocFlatEntries: () async => [
        for (var i = 0; i < 25; i++)
          {
            'bookId': 20000 + i,
            'bookTitle': 'חיבור נפרד $i',
            'bookOrderIndex': i.toDouble(),
            'reference': 'סימן מא',
            'segment': 1,
            'level': 2,
          },
      ],
      getCategoryPath: (_) async => '',
    );
    addTearDown(repo.dispose);
    final results = await repo.findRefs('מא');
    expect(results.first.bookId, 6418);
    expect(results.map((r) => r.bookId), contains(1000));
  });
}
