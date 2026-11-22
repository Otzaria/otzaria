import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/utils/text/ref_key.dart';

class MockDataRepository extends Mock implements DataRepository {}

/// איתור ברמת שורה דרך `findRefs` — המסלול שהמשתמש מקליד בו, ולא רק
/// פונקציית הנרמול במנותק.
void main() {
  /// שורות הספרים שמהן נבנה האינדקס המדומה.
  const heRefsByBook = {
    12: {648: 'ישעיהו לב, יא', 650: 'ישעיהו לב, יג'},
    70: {5: 'ברכות ב., א'},
    380: {
      6846: 'טור, חושן משפט,  שט, א',
      6848: 'טור, חושן משפט,  שט, ג',
      7000: 'טור, יורה דעה,  שי, ב',
      7100: 'טור, אבן העזר,  שי, ב',
    },
    3909: {410: 'איסור והיתר הארוך, לה, יא'},
    3133: {20: 'שערי תשובה, שער א, ב'},
  };

  final titles = {
    12: 'ישעיהו',
    70: 'ברכות',
    380: 'טור',
    3909: 'איסור והיתר הארוך',
    3133: 'שערי תשובה',
  };

  late List<({List<int> bookIds, String refKey})> lookups;
  late List<List<String>> altTocQueries;

  FindRefRepository buildRepo({
    bool withIndex = true,
    bool withPartialKeys = true,
    Future<String> Function(int bookId)? getCategoryPath,
    List<String> altToc = const [],
    String tocLocation = 'לב',
    List<int>? altStructureBookIds,
  }) {
    altTocQueries = [];
    lookups = [];
    return FindRefRepository(
      dataRepository: MockDataRepository(),
      getCategoryPath: getCategoryPath,
      isReferenceBooksCacheLoaded: () => true,
      warmUpReferenceBooksCache: () async {},
      searchReferenceBooks: (query, {int limit = 50}) => [
        if (query == 'טור חושן משפט' || query == 'טור חומ')
          ReferenceBookHit(
            bookId: 380,
            title: 'טור',
            normalizedTitle: 'טור',
            filePath: '',
            fileType: 'txt',
            matchRank: 3,
            matchedTerm: query,
            orderIndex: 380,
          ),
        for (final entry in titles.entries)
          if (entry.value.startsWith(query))
            ReferenceBookHit(
              bookId: entry.key,
              title: entry.value,
              normalizedTitle: entry.value,
              filePath: '',
              fileType: 'txt',
              matchRank: 0,
              matchedTerm: query,
              orderIndex: entry.key.toDouble(),
            ),
      ],
      getAltStructureBookIds: altStructureBookIds == null
          ? null
          : () async => altStructureBookIds,
      getTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async => [
        if (tocLocation.isNotEmpty)
          {
            'reference': '$bookTitle $tocLocation',
            'segment': 600,
            'level': 2,
            'dbLineId': 1,
          },
      ],
      getAltTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async {
        altTocQueries.add(queryTokens!);
        return [
          for (final ref in altToc)
            if (queryTokens.every(ref.split(' ').contains))
              {'reference': ref, 'segment': 900, 'level': 2, 'dbLineId': 9},
        ];
      },
      resolvePartialLineRefs: !withIndex || !withPartialKeys
          ? null
          : (bookIds, partialKey) async => {
              for (final bookId in bookIds)
                if ((heRefsByBook[bookId] ?? {}).entries
                        .where(
                          (line) => partialLineRefKeys(line.value, [
                            titles[bookId]!,
                          ]).contains(partialKey),
                        )
                        .toList()
                    case final lines when lines.isNotEmpty)
                  bookId: [
                    for (final line in lines)
                      (
                        lineIndex: line.key,
                        lineId: 1000 + line.key,
                        heRef: line.value,
                      ),
                  ],
            },
      resolveLineRefs: !withIndex
          ? null
          : (bookIds, refKey) async {
              lookups.add((bookIds: bookIds, refKey: refKey));
              final resolved =
                  <int, ({int lineIndex, int lineId, String? heRef})>{};
              for (final bookId in bookIds) {
                for (final line in (heRefsByBook[bookId] ?? {}).entries) {
                  if (buildLineRefKey(line.value, [titles[bookId]!]) ==
                      refKey) {
                    resolved[bookId] = (
                      lineIndex: line.key,
                      lineId: 1000 + line.key,
                      heRef: line.value,
                    );
                    break;
                  }
                }
              }
              return resolved;
            },
    );
  }

  test('"ישעיהו לב יא" מגיע לשורת הפסוק ומדורג ראשון', () async {
    final results = await buildRepo().findRefs('ישעיהו לב יא');

    expect(results.first.isSourceLine, isTrue);
    expect(results.first.segment, 648);
    expect(results.first.sourceLineId, 1648);
    expect(results.first.reference, 'ישעיהו לב, יא');
  });

  test('נתיב קטגוריה אינו מוחק את סימון שורת המקור', () async {
    final results = await buildRepo(
      getCategoryPath: (_) async => 'תנ"ך, נביאים',
    ).findRefs('ישעיהו לב יא');

    expect(results.first.bookPath, 'תנ"ך, נביאים');
    expect(results.first.isSourceLine, isTrue);
    expect(results.first.sourceLineId, 1648);
  });

  test('מילות מיקום בשאילתה שקולות לצורה הקצרה', () async {
    final withLocators = await buildRepo().findRefs('ישעיהו פרק לב פסוק יא');
    final without = await buildRepo().findRefs('ישעיהו לב יא');

    expect(withLocators.first.segment, without.first.segment);
    expect(withLocators.first.isSourceLine, isTrue);
  });

  test('טווח נפתח בתחילתו', () async {
    final results = await buildRepo().findRefs('ישעיהו לב יא-יג');
    expect(results.first.segment, 648);
  });

  test('סימון דף בגמרא נפתר לשורה', () async {
    final results = await buildRepo().findRefs('ברכות ב. א');
    expect(results.first.isSourceLine, isTrue);
    expect(results.first.segment, 5);
  });

  // issue #4893 — "דין" ו"כלל" אינם ב-heRef הממוספר.
  test('מילות מבנה שאינן ב-heRef ("כלל לה דין יא") מגיעות לשורה', () async {
    final results = await buildRepo().findRefs(
      'איסור והיתר הארוך כלל לה דין יא',
    );

    expect(results.first.isSourceLine, isTrue);
    expect(results.first.segment, 410);
  });

  test('מילת מבנה שב-heRef ("שער א ב") נפתרת במפתח המלא בלבד', () async {
    final results = await buildRepo().findRefs('שערי תשובה שער א ב');

    expect(results.first.segment, 20);
    expect(lookups.map((l) => l.refKey), ['שער א ב']);
  });

  test('שאילתה מאוגדת אחת לכל מפתח — לא פנייה לכל ספר', () async {
    final repo = buildRepo();
    await repo.findRefs('ישעיהו לב יא');

    expect(lookups, hasLength(1));
    expect(lookups.single.refKey, 'לב יא');
  });

  test('רכיב יחיד ("ישעיהו לב") נשאר ברמת TOC', () async {
    final repo = buildRepo();
    final results = await repo.findRefs('ישעיהו לב');

    expect(lookups, isEmpty);
    expect(results.every((r) => !r.isSourceLine), isTrue);
  });

  test('מסד בלי אינדקס נופל למסלול ה-TOC', () async {
    final results = await buildRepo(withIndex: false).findRefs('ישעיהו לב יא');

    expect(results, isNotEmpty);
    expect(results.every((r) => !r.isSourceLine), isTrue);
  });

  // issue #1346 — ה-heRef של שורות הטור כולל את החלק ("טור, חושן משפט, שט, ג").
  test('חלק מראש-התיבות ("טור חושן משפט") נכנס למפתח השורה', () async {
    final results = await buildRepo().findRefs('טור חושן משפט שט ג');

    expect(results.first.isSourceLine, isTrue);
    expect(results.first.segment, 6848);
  });

  test('ראשי-תיבות של החלק ("טור חומ") נפרשים לצורה שב-heRef', () async {
    AcronymsCache.instance.setAcronymsForTesting({
      380: ['טור חומ', 'טור חושן משפט'],
    });
    addTearDown(() => AcronymsCache.instance.setAcronymsForTesting({}));

    final results = await buildRepo().findRefs('טור חומ שט ג');

    expect(results.first.isSourceLine, isTrue);
    expect(results.first.segment, 6848);
  });

  test(
    'בלי שם החלק ("טור שט ג") מגיע לשורה בחלק היחיד שבו היא קיימת',
    () async {
      final results = await buildRepo().findRefs('טור שט ג');

      expect(results.first.isSourceLine, isTrue);
      expect(results.first.segment, 6848);
    },
  );

  test('הפניה שקיימת בכמה חלקים מוצעת בכל אחד מהם', () async {
    final results = await buildRepo().findRefs('טור שי ב');

    expect(
      results.where((r) => r.isSourceLine).map((r) => r.segment),
      unorderedEquals([7000, 7100]),
    );
  });

  // issue #5748 — "טור יורה דעה קפד ג" הגיע לשורה "חושן משפט, קפד, ג".
  test('חלק שנקוב בשאילתה ("טור חומ שי ב") אינו מוצע בחלק אחר', () async {
    AcronymsCache.instance.setAcronymsForTesting({
      380: ['טור חומ', 'טור חושן משפט'],
    });
    addTearDown(() => AcronymsCache.instance.setAcronymsForTesting({}));

    final results = await buildRepo(
      tocLocation: 'חושן משפט סימן שי',
    ).findRefs('טור חומ שי ב');

    expect(results, isNotEmpty);
    expect(results.where((r) => r.isSourceLine), isEmpty);
  });

  test('זנב כינוי שאינו בתוכן העניינים אינו חוסם את השורה החלקית', () async {
    AcronymsCache.instance.setAcronymsForTesting({
      380: ['טור חומ', 'טור חושן משפט'],
    });
    addTearDown(() => AcronymsCache.instance.setAcronymsForTesting({}));

    final results = await buildRepo().findRefs('טור חומ שי ב');

    expect(results.where((r) => r.isSourceLine), isNotEmpty);
  });

  test('סעיף מתוכן העניינים החלופי רק בחלק שנקוב בשאילתה', () async {
    final results = await buildRepo(
      altToc: [
        'חושן משפט סימן לג סעיף ב',
        'יורה דעה סימן לג סעיף ב',
      ],
    ).findRefs('טור חושן משפט לג ב');

    expect(altTocQueries.first, ['חושן', 'משפט', 'לג', 'ב']);
    expect(results.where((r) => r.isAltToc).map((r) => r.reference), [
      'טור חושן משפט סימן לג סעיף ב',
    ]);
  });

  test('נסיגת תוכן העניינים מדלגת על ספר בלי מבנה AltToc', () async {
    await buildRepo(
      tocLocation: '',
      altStructureBookIds: [],
    ).findRefs('טור חושן משפט לג ב');

    expect(altTocQueries, isEmpty);
  });

  test('מסד בלי מפתחות חלקיים נשאר ברמת ה-TOC', () async {
    final results = await buildRepo(
      withPartialKeys: false,
    ).findRefs('טור שט ג');
    expect(results.every((r) => !r.isSourceLine), isTrue);
  });
}
