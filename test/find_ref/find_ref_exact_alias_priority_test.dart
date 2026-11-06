import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';

import 'support/seeded_reference_library.dart';

const _target = (
  id: 123,
  title: 'בבא מציעא',
  acronyms: ['ב"מ'],
);

List<SeedBook> _crowdedLibrary() => [
  for (var i = 0; i < 60; i++)
    (id: 1000 + i, title: 'במבחן $i', acronyms: const []),
  for (var i = 0; i < 60; i++)
    (id: 2000 + i, title: 'ספר במבחן $i', acronyms: const []),
  _target,
];

void main() {
  tearDown(resetSeededLibrary);

  test('כינוי מדויק קודם לתחיליות ולתת־מחרוזות גם בחיתוך המועמדים', () {
    seedLibrary(_crowdedLibrary());

    for (final limit in [1, 5, 50, 1000]) {
      final hits = ReferenceBooksCache.instance.search('במ', limit: limit);

      expect(hits.length, lessThanOrEqualTo(limit));
      expect(hits.first.bookId, _target.id, reason: 'limit=$limit');
      expect(hits.first.matchRank, 3);
    }
  });

  test('כותרת מלאה עדיין קודמת לכינוי מדויק של ספר אחר', () async {
    seedLibrary([
      ..._crowdedLibrary(),
      (id: 3000, title: 'במ', acronyms: const []),
    ]);

    final hits = ReferenceBooksCache.instance.search('במ', limit: 2);
    expect(hits.map((hit) => hit.bookId), [3000, _target.id]);
    final batch = ReferenceBooksCache.instance.searchBatch(['במ'], limit: 1000);
    for (final limit in [1, 2]) {
      expect(
        batch.hitsFor('במ', limit: limit)!.map((hit) => hit.bookId),
        [3000, _target.id].take(limit),
      );
    }

    final results = await buildFindRefRepo().findRefs('במ');
    expect(results.take(2).map((result) => result.bookId), [3000, _target.id]);
  });

  for (final query in ['במ ב ב', 'ב"מ ב:', 'בבא מציעא דף ב עמוד ב']) {
    test('"$query" מגיע לאותו דף למרות יותר מ־50 מועמדים חלקיים', () async {
      seedLibrary(_crowdedLibrary());
      final seen = <List<String>?>[];
      final results = await buildFindRefRepo(
        tocQueryTokensSeen: seen,
        tocEntries: const {
          123: [
            {
              'reference': 'בבא מציעא דף ב עמוד ב',
              'segment': 17,
              'level': 1,
            },
          ],
        },
      ).findRefs(query);

      expect(results, isNotEmpty);
      expect(results.first.bookId, _target.id);
      expect(results.first.segment, 17);
      expect(seen.length, lessThanOrEqualTo(50));
    });
  }

  test('כינוי מדויק שורד גם את חיתוך הדירוג הסופי בשאילתת שם בלבד', () async {
    seedLibrary(_crowdedLibrary());

    final results = await buildFindRefRepo().findRefs('במ');

    expect(results.first.bookId, _target.id);
  });

  test(
    'במ ב ב מעדיף כינוי מדויק על פסוק בספר ששמו מתחיל באותן אותיות',
    () async {
      const paths = {
        4: 'תנ"ך, תורה',
        123: 'תלמוד בבלי, סדר נזיקין',
      };
      seedLibrary([
        (id: 4, title: 'במדבר', acronyms: const []),
        _target,
      ], categoryPaths: paths);
      final repo = FindRefRepository(
        isReferenceBooksCacheLoaded: () => true,
        warmUpReferenceBooksCache: () async {},
        getTocEntriesForReference: (id, _, {queryTokens}) async => id == 123
            ? [
                {
                  'reference': 'בבא מציעא דף ב עמוד ב',
                  'segment': 14,
                  'level': 1,
                },
              ]
            : const [],
        getAltTocEntriesForReference: (_, _, {queryTokens}) async => const [],
        getAllAltTocFlatEntries: () async => const [],
        resolveLineRefs: (ids, key) async => {
          if (ids.contains(4) && key == 'ב ב')
            4: (lineIndex: 58, lineId: 6176535, heRef: 'במדבר, ב, ב'),
        },
        getCategoryPath: (id) async => paths[id] ?? '',
      );
      addTearDown(repo.disposeForTesting);

      final results = await repo.findRefs('במ ב ב');

      expect(results.first.bookId, _target.id);
      expect(results.first.segment, 14);
      expect(results.last.bookId, 4);
      expect(results.last.isSourceLine, isTrue);
      expect(results.last.segment, 58);
    },
  );

  test('שם ספר מלא עם מיקום שומר על קדימותו מול כינוי של ספר אחר', () async {
    seedLibrary([
      (id: 1, title: 'ספר המפרש', acronyms: const ['בבא מציעא']),
      _target,
    ]);
    final results = await buildFindRefRepo(
      tocEntries: const {
        1: [
          {'reference': 'ספר המפרש פרק ב', 'segment': 2, 'level': 1},
        ],
        123: [
          {'reference': 'בבא מציעא דף ב', 'segment': 3, 'level': 1},
        ],
      },
    ).findRefs('בבא מציעא ב');

    expect(results.map((result) => result.bookId), [_target.id, 1]);
  });

  test('מספר מיקום אינו מחזיר התאמות חלקיות לפני הכינוי במכסת ה־TOC', () async {
    seedLibrary([
      for (var i = 0; i < 60; i++)
        (id: 1000 + i, title: 'במבחן סו חומר $i', acronyms: const []),
      _target,
    ]);
    final results = await buildFindRefRepo(
      tocEntries: const {
        123: [
          {
            'reference': 'בבא מציעא דף סו עמוד ב',
            'segment': 66,
            'level': 1,
          },
        ],
      },
    ).findRefs('במ סו ב');

    expect(results, isNotEmpty);
    expect(results.first.bookId, _target.id);
    expect(results.first.segment, 66);
  });

  for (final (title, rank) in [('זהר המבואר', 1), ('ספר הזהר', 2)]) {
    test('כינוי מדויק מקבל עדיפות גם כשהוא כלול בכותרת "$title"', () async {
      seedLibrary([
        for (var i = 0; i < 60; i++)
          (id: 1000 + i, title: 'זהרון $i', acronyms: const []),
        (id: 3000, title: title, acronyms: const ['זהר']),
      ]);

      final hits = ReferenceBooksCache.instance.search('זהר', limit: 1);
      expect(hits.single.bookId, 3000);
      expect(hits.single.matchRank, rank);
      expect(hits.single.isExactAlias, isTrue);

      final results = await buildFindRefRepo().findRefs('זהר');
      expect(results.first.bookId, 3000);
    });
  }

  for (final query in ['במ', 'במ ב']) {
    test('"$query" שומר דירוג AltToc כשאין כינוי מדויק בתוצאות', () async {
      seedLibrary([
        (id: 1, title: 'במבחן', acronyms: const []),
        (id: 2, title: 'ספר החכמה', acronyms: const []),
        if (query.contains(' ')) _target,
      ]);
      final lookedUp = <int>[];
      final repo = FindRefRepository(
        isReferenceBooksCacheLoaded: () => true,
        warmUpReferenceBooksCache: () async {},
        getTocEntriesForReference: (id, _, {queryTokens}) async {
          lookedUp.add(id);
          return id == 1
              ? [
                  {
                    'reference': 'במבחן פרק ב',
                    'segment': 3,
                    'level': 1,
                  },
                ]
              : const [];
        },
        getAltTocEntriesForReference: (_, _, {queryTokens}) async => const [],
        searchAltTocFlatEntries:
            (tokens, {maxRefTokens, occupied = const []}) async => [
              {
                'bookId': 2,
                'bookTitle': 'ספר החכמה',
                'bookOrderIndex': 100,
                'reference': query,
                'segment': 4,
                'level': 2,
              },
            ],
        getCategoryPath: (_) async => 'ספרייה',
      );
      addTearDown(repo.disposeForTesting);

      final results = await repo.findRefs(query);

      expect(results.map((result) => result.bookId), [1, 2]);
      expect(results.last.isAltToc, isTrue);
      if (query.contains(' ')) expect(lookedUp, contains(_target.id));
    });
  }

  for (final (count, shortMatches) in [(60, false), (5, true)]) {
    test('כינוי קצר אינו דוחק זיהוי ספר ארוך יותר ($count ספרים)', () async {
      seedLibrary([
        (
          id: 323,
          title: 'משנה תורה הלכות מאכלות אסורות',
          acronyms: const ['רמבם מאכלות אסורות'],
        ),
        for (var i = 0; i < count; i++)
          (
            id: 1000 + i,
            title: 'משנה תורה הלכות נושא $i',
            acronyms: const ['רמבם'],
          ),
      ]);
      final results = await buildFindRefRepo(
        tocEntries: {
          if (shortMatches)
            for (var i = 0; i < count; i++)
              1000 + i: [
                {
                  'reference': 'משנה תורה הלכות נושא $i מאכלות פרק א',
                  'segment': 1,
                  'level': 1,
                },
              ],
          323: [
            {
              'reference': 'משנה תורה הלכות מאכלות אסורות פרק א',
              'segment': 3,
              'level': 1,
            },
          ],
        },
      ).findRefs('רמבם מאכלות א');

      expect(results, isNotEmpty);
      expect(results.first.bookId, 323);
      expect(results.first.segment, 3);
    });
  }
}
