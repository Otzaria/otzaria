import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

/// ביטול חיפוש לקסיקלי מול המנוע האמיתי.
Future<void> main() async {
  final ready = await tryInitSearchEngine();
  const book = '/cancellation/book';
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
    temporary = await Directory.systemTemp.createTemp('lexical-cancellation-');
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

  group('ביטול במנוע', () {
    for (final mode in SearchMode.values) {
      test('דפדוף וספירה משולבת מכבדים ביטול במצב ${mode.name}', () async {
        final id = LexicalSearchRequestIds.next();
        await repository.cancelLexicalSearch(id);
        final request = SearchEngineRequest(
          query: 'משה',
          facets: const [book],
          limit: 1,
          offset: 1,
          searchMode: mode,
          cancelRequestId: id,
        );
        await expectLater(
          repository.searchTexts(request),
          throwsA(predicate(isSearchCancelledError)),
        );
        await expectLater(
          repository.searchTextsAndCount(request),
          throwsA(predicate(isSearchCancelledError)),
        );
        final fresh = SearchEngineRequest(
          query: 'משה',
          facets: const [book],
          limit: 20,
          searchMode: mode,
          cancelRequestId: LexicalSearchRequestIds.next(),
        );
        expect(await repository.searchTexts(fresh), isNotEmpty);
        expect(
          (await repository.searchTextsAndCount(fresh)).results,
          isNotEmpty,
        );
      });
    }

    test('חיפוש ביטוי בתוך שורה מכבד ביטול', () async {
      final id = LexicalSearchRequestIds.next();
      await repository.cancelLexicalSearch(id);
      await expectLater(
        RustSearchEngineOperations(engine).searchInlineExact(
          SearchEngineRequest(
            query: 'משה',
            facets: const [book],
            limit: 20,
            cancelRequestId: id,
          ),
        ),
        throwsA(predicate(isSearchCancelledError)),
      );
    });

    test('ספירה לקסיקלית שבוטלה נכשלת בשגיאת ביטול', () async {
      final id = LexicalSearchRequestIds.next();
      await repository.cancelLexicalSearch(id);
      final gateway = const SearchEngineGateway();
      final ops = RustSearchEngineOperations(engine);
      final request = SearchEngineRequest(
        query: 'משה',
        facets: const [book],
        cancelRequestId: id,
      );
      await expectLater(
        gateway.count(ops, request),
        throwsA(predicate(isSearchCancelledError)),
      );
      // מזהה אחר אינו מושפע.
      expect(
        await gateway.count(
          ops,
          request.withId(LexicalSearchRequestIds.next()),
        ),
        1,
      );
    });

    test('stream לקסיקלי שבוטל נסגר בלי תוצאות', () async {
      final id = LexicalSearchRequestIds.next();
      await repository.cancelLexicalSearch(id);
      final updates = await repository
          .searchTextsStreamWithCounts(
            SearchEngineRequest(
              query: 'משה',
              facets: const [book],
              limit: 20,
              cancelRequestId: id,
            ),
          )
          .toList();
      expect(updates, isEmpty);
    });

    test('מזהי הבקשה אינם חוזרים', () {
      final ids = {
        for (var i = 0; i < 1000; i++) LexicalSearchRequestIds.next(),
      };
      expect(ids, hasLength(1000));
      expect(ids.every((id) => id > 0 && id <= 0xFFFFFFFF), isTrue);
    });
  }, skip: ready ? false : searchEngineSkipReason);
}

extension on SearchEngineRequest {
  SearchEngineRequest withId(int id) => SearchEngineRequest(
    query: query,
    facets: facets,
    limit: limit,
    cancelRequestId: id,
  );
}
