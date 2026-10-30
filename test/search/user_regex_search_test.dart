import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/utils/user_regex_query.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

/// רג'קס מהמשתמש (`/…/`) וביטול חיפוש במנוע, מול מנוע אמיתי.
Future<void> main() async {
  final ready = await tryInitSearchEngine();
  const book = '/regex/book';
  const lines = [
    'ויאמר משה אל אהרן', // 0
    'וידבר מושה אל העם', // 1
    'כתב הרמב"ם בהלכות', // 2
    'שמע בני ישראל את הדברים', // 3
    'ספר הזכרונות', // 4
  ];

  late Directory temporary;
  late SearchEngine engine;
  late SearchRepository repository;

  setUpAll(() async {
    if (!ready) return;
    temporary = await Directory.systemTemp.createTemp('user-regex-');
    engine = await SearchEngine.newInstance(path: temporary.path);
    for (var i = 0; i < lines.length; i++) {
      await engine.addDocument(
        ordinal: i,
        title: 'ספר',
        reference: 'שורה $i',
        topics: book,
        text: lines[i],
        segment: BigInt.from(i),
        isPdf: false,
        filePath: 'id:1',
      );
    }
    await engine.commit();
    repository = SearchRepository(
      engineProvider: () async => RustSearchEngineOperations(engine),
    );
  });

  tearDownAll(() async {
    if (!ready) return;
    engine.dispose();
    if (Platform.isWindows) return;
    try {
      await temporary.delete(recursive: true);
    } on FileSystemException {
      // ignore
    }
  });

  Future<List<int>> segments(String query, {int? cancelRequestId}) async {
    final results = await repository.searchTexts(
      SearchEngineRequest(
        query: query,
        facets: const [book],
        limit: 20,
        cancelRequestId: cancelRequestId,
      ),
    );
    return results.map((result) => result.segment.toInt()).toList()..sort();
  }

  group('זיהוי `/…/`', () {
    test('רק עטיפה שהמנוע מקבל היא רג\'קס', () {
      expect(UserRegexQuery.plan('/מש.ה/')?.kind, UserRegexKind.singleWord);
      expect(
        UserRegexQuery.plan(' /שמע .* ישראל/ ')?.kind,
        UserRegexKind.crossSpace,
      );
      for (final raw in [
        'מש.ה',
        '/(/',
        '/שמע',
        '//',
        '/   /',
        '/תורה/ /משה/',
        '/תורה /משה/',
      ]) {
        expect(UserRegexQuery.plan(raw), isNull, reason: raw);
        expect(UserRegexQuery.matcher(raw), isNull, reason: raw);
      }
    });

    test('engineQuery: רג\'קס נשאר כפי שהוקלד, רג\'קס פסול מנוקה', () {
      expect(SearchQueryBuilder.engineQuery(' /מש.ה|אהרן/ '), '/מש.ה|אהרן/');
      expect(
        SearchQueryBuilder.engineQuery('/(/'),
        SearchQueryBuilder.sanitizeQuery('/(/'),
      );
      expect(
        SearchQueryBuilder.engineQuery('/תורה/ /משה/'),
        SearchQueryBuilder.sanitizeQuery('/תורה/ /משה/'),
      );
      expect(
        SearchQueryBuilder.engineQuery('משה־רבנו'),
        SearchQueryBuilder.sanitizeQuery('משה־רבנו'),
      );
    });
  }, skip: ready ? false : searchEngineSkipReason);

  group('חיפוש `/…/` בספרייה', () {
    test('מילה: התבנית מותאמת למילים שלמות', () async {
      expect(await segments('/מו?שה/'), [0, 1]);
    });

    test('בלי גרשיים מוצא את הכתיב בגרשיים', () async {
      expect(await segments('/הרמבם/'), [2]);
    });

    test('חוצה-רווחים נסרק בשורות', () async {
      expect(await segments('/שמע .* ישראל/'), [3]);
    });

    test('ה-stream המשולב נושא ספירה וספירה לפי ספר', () async {
      final updates = await repository
          .searchTextsStreamWithCounts(
            const SearchEngineRequest(
              query: '/שמע .* ישראל/',
              facets: [book],
              limit: 20,
            ),
          )
          .toList();
      final counts = updates.lastWhere((u) => u.bookCounts != null);
      expect(counts.totalCount, 1);
      expect(counts.bookCounts, {'id:1': 1});
      expect(updates.expand((u) => u.results).map((r) => r.text), [
        contains('ישראל'),
      ]);
    });

    test('ספירה וספירה לפי ספר', () async {
      final gateway = const SearchEngineGateway();
      final ops = RustSearchEngineOperations(engine);
      const request = SearchEngineRequest(query: '/מו?שה/', facets: [book]);
      expect(await gateway.count(ops, request), 2);
      expect(await gateway.countByBook(ops, request), {'id:1': 2});
    });
  }, skip: ready ? false : searchEngineSkipReason);

  group('טען עוד ברג\'קס חוצה-רווחים', () {
    const bigBook = '/regex/big';
    late Directory bigTemporary;
    late SearchEngine bigEngine;

    setUpAll(() async {
      if (!ready) return;
      bigTemporary = await Directory.systemTemp.createTemp('user-regex-big-');
      bigEngine = await SearchEngine.newInstance(path: bigTemporary.path);
      await bigEngine.addTextBook(
        title: 'ספר גדול',
        topics: bigBook,
        filePath: 'id:2',
        text: List.filled(3000, 'שמע בני ישראל').join('\n'),
        textStorage: TextStorage.inIndex,
      );
      await bigEngine.commit();
    });

    tearDownAll(() async {
      if (!ready) return;
      bigEngine.dispose();
      if (Platform.isWindows) return;
      try {
        await bigTemporary.delete(recursive: true);
      } on FileSystemException {
        // ignore
      }
    });

    test('עמוד נוסף אחרי ביטול ממשיך את הסריקה ואינו קורא שוב', () async {
      final ops = RustSearchEngineOperations(bigEngine);
      const pattern = r'/שמע \S+ ישראל/';
      final first = LexicalSearchRequestIds.next();
      final stopped = await ops
          .searchUserRegexStream(
            SearchEngineRequest(
              query: pattern,
              facets: const [bigBook],
              limit: 50,
              cancelRequestId: first,
            ),
            chunkSize: 50,
          )
          .map((update) {
            if (update.progressTotal > 0) {
              unawaited(ops.cancelLexicalSearch(first));
            }
            return update;
          })
          .last;
      // הביטול מגיע אחרי שהסריקה כבר התקדמה; ייתכן שאף הסתיימה.
      final read = stopped.cancelled ? stopped.progressDone : 3000;

      final nextPage = await ops
          .searchUserRegexStream(
            SearchEngineRequest(
              query: pattern,
              facets: const [bigBook],
              limit: 50,
              offset: 50,
              cancelRequestId: LexicalSearchRequestIds.next(),
            ),
            chunkSize: 50,
          )
          .toList();
      expect(nextPage.last.totalCount, 3000);
      expect(nextPage.expand((u) => u.results), hasLength(50));
      final progress = [
        for (final update in nextPage)
          if (!update.done && update.progressTotal > 0) update.progressDone,
      ];
      expect(
        progress.every((done) => done > read),
        isTrue,
        reason: '$progress',
      );
    });
  }, skip: ready ? false : searchEngineSkipReason);

  group('ביטול רג\'קס במנוע', () {
    test('רג\'קס שבוטל: ספירה נכשלת וה-stream נסגר', () async {
      final id = LexicalSearchRequestIds.next();
      await repository.cancelLexicalSearch(id);
      final request = SearchEngineRequest(
        query: r'/^\S+\s\S+$/',
        facets: const [book],
        limit: 20,
        cancelRequestId: id,
      );
      await expectLater(
        const SearchEngineGateway().count(
          RustSearchEngineOperations(engine),
          request,
        ),
        throwsA(predicate(isSearchCancelledError)),
      );
      expect(
        await repository.searchTextsStreamWithCounts(request).toList(),
        isEmpty,
      );
      // מזהה אחר אינו מושפע; ^ ו-$ מעגנים לשורה: רק שורה של שתי מילים.
      expect(await segments(r'/^\S+\s\S+$/'), [4]);
    });
  }, skip: ready ? false : searchEngineSkipReason);
}
