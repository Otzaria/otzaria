import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';

import 'support/seeded_reference_library.dart';

/// מסלול הרב-מילי שולח את תוכן העניינים של כל הספרים המועמדים בבקשה אחת.
void main() {
  tearDown(resetSeededLibrary);

  const books = <SeedBook>[
    (id: 1, title: 'ספר ראשון', acronyms: []),
    (id: 2, title: 'ספר שני', acronyms: []),
    (id: 3, title: 'ספר שלישי', acronyms: []),
  ];

  // ערכי TOC/AltToc מזויפים; ערך מוחזר כשכל טוקני החיפוש בו.
  const tocByBook = <int, List<String>>{
    1: ['פרק א', 'פרק ב'],
    2: ['פרק א', 'סימן א'],
    3: ['פרק ג'],
  };
  const altByBook = <int, List<String>>{
    3: ['פרשה א', 'פרשה ב'],
  };

  List<Map<String, dynamic>> entriesFor(
    Map<int, List<String>> source,
    int bookId,
    String title,
    List<String>? tokens,
  ) {
    final refs = source[bookId] ?? const <String>[];
    return [
      for (var i = 0; i < refs.length; i++)
        if ((tokens ?? const []).every(refs[i].split(' ').contains))
          {
            'reference': '$title ${refs[i]}',
            'segment': i * 10,
            'level': 2,
            'dbLineId': bookId * 100 + i,
          },
    ];
  }

  Future<List<Map<String, dynamic>>> toc(
    int id,
    String title, {
    List<String>? queryTokens,
  }) async => entriesFor(tocByBook, id, title, queryTokens);

  Future<List<Map<String, dynamic>>> altToc(
    int id,
    String title, {
    List<String>? queryTokens,
  }) async => entriesFor(altByBook, id, title, queryTokens);

  FindRefRepository repoWith({
    Future<List<TocBatchResult>> Function(List<TocBatchRequest>)? batch,
    bool singleBookAllowed = true,
  }) {
    Never unexpected() => fail('בקשת TOC לספר בודד במקום בקשה מאוגדת');
    final repo = FindRefRepository(
      isReferenceBooksCacheLoaded: () => true,
      getAltStructureBookIds: () async => const [3],
      getTocEntriesForReference: (id, title, {queryTokens}) => singleBookAllowed
          ? toc(id, title, queryTokens: queryTokens)
          : unexpected(),
      getAltTocEntriesForReference: (id, title, {queryTokens}) =>
          singleBookAllowed
          ? altToc(id, title, queryTokens: queryTokens)
          : unexpected(),
      getTocForBooks: batch,
      getAllAltTocFlatEntries: () async => const [],
      getCategoryPath: (_) async => 'ספרייה',
    );
    addTearDown(repo.dispose);
    return repo;
  }

  Future<List<TocBatchResult>> fakeBatch(
    List<TocBatchRequest> requests,
  ) async => [
    for (final r in requests)
      (
        toc: await toc(r.bookId, r.bookTitle, queryTokens: r.queryTokens),
        altToc: r.altTocTokens == null
            ? const <Map<String, dynamic>>[]
            : await altToc(r.bookId, r.bookTitle, queryTokens: r.altTocTokens),
      ),
  ];

  List<String> describe(List<DbReferenceResult> results) => [
    for (final r in results)
      '${r.bookId}|${r.reference}|${r.segment}|${r.tocLevel}|${r.isAltToc}',
  ];

  test('שאילתה רב-מילית שולחת בקשת TOC מאוגדת אחת לכל הספרים', () async {
    seedLibrary(books);
    final batches = <List<TocBatchRequest>>[];
    final repo = repoWith(
      singleBookAllowed: false,
      batch: (requests) {
        batches.add(requests);
        return fakeBatch(requests);
      },
    );

    final results = await repo.findRefs('ספר פרק');

    expect(batches, hasLength(1));
    expect([for (final r in batches.single) r.bookId], [1, 2, 3]);
    expect(
      [for (final r in batches.single) r.altTocTokens],
      [
        null,
        null,
        ['פרק'],
      ],
      reason: 'AltToc מתבקש רק לספרים בעלי מבנה חלופי',
    );
    expect(describe(results), contains('3|ספר שלישי פרק ג|0|2|false'));
  });

  test('התוצאות זהות לאלה של בקשה נפרדת לכל ספר', () async {
    seedLibrary(books);
    final single = repoWith();
    final batched = repoWith(singleBookAllowed: false, batch: fakeBatch);

    for (final query in [
      'ספר פרק',
      'ספר פרק א',
      'ספר ראשון פרק ב',
      'ספר פרשה',
    ]) {
      expect(
        describe(await batched.findRefs(query)),
        describe(await single.findRefs(query)),
        reason: query,
      );
    }
  });

  test('ביטול בזמן שהבקשה המאוגדת רצה מבטל את החיפוש כולו', () async {
    seedLibrary(books);
    final entered = Completer<void>();
    final gate = Completer<List<TocBatchResult>>();
    var batches = 0;
    final repo = repoWith(
      singleBookAllowed: false,
      batch: (requests) {
        if (batches++ == 0) {
          entered.complete();
          return gate.future;
        }
        return fakeBatch(requests);
      },
    );

    final old = expectLater(
      repo.findRefs('ספר פרק'),
      throwsA(isA<FindRefQueryCancelled>()),
    );
    await entered.future;
    repo.cancelPendingSearch();
    gate.complete(const []);
    await old;
    expect(batches, 1, reason: 'אין בקשה נוספת אחרי הביטול');
  });
}
