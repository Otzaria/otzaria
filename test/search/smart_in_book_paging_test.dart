import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/utils/smart_lexical_in_book_search.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

class _PagedEngine extends SearchEngineOperations {
  final calls = <({String stream, int offset, int limit})>[];
  final Future<List<SearchResult>> Function(String, int, int) fetch;

  _PagedEngine(this.fetch);

  Future<List<SearchResult>> _fetch(
    String stream,
    SearchEngineRequest request,
  ) {
    calls.add((stream: stream, offset: request.offset, limit: request.limit));
    return fetch(stream, request.offset, request.limit);
  }

  @override
  Future<List<SearchResult>> searchInlineExact(SearchEngineRequest request) =>
      _fetch(request.query, request);

  @override
  Future<List<SearchResult>> searchFuzzy(SearchEngineRequest request) =>
      _fetch('fuzzy', request);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SearchResult _result(int id, {String path = 'book'}) => SearchResult(
  title: 'ספר',
  reference: 'שורה',
  text: 'ברא אלהים הארץ',
  id: BigInt.from(id),
  segment: BigInt.from(100 - id),
  isPdf: false,
  filePath: path,
  mergedCount: 1,
  merged: const [],
  textStatus: TextStatus.ok,
  continuesToNextLine: false,
);

Future<List<SearchResult>> _search(_PagedEngine engine, {int limit = 2}) =>
    searchSmartLexicalInBook(
      SearchRepository(engineProvider: () async => engine),
      query: '"ברא אלהים" "הארץ"',
      bookPath: '/book',
      limit: limit,
      distance: 0,
      phrases: const ['ברא אלהים', 'הארץ'],
    );

Future<void> main() async {
  final ready = await tryInitSearchEngine();
  group('חיתוך ציטוטים מדופדף', () {
    test('מפסיק לקרוא עמודים ברגע שמגבלת התוצאות הושגה', () async {
      final engine = _PagedEngine(
        (stream, offset, limit) async => [
          for (var id = offset; id < offset + limit; id++) _result(id),
        ],
      );
      final results = await _search(engine);
      expect(results.map((r) => r.id.toInt()), [0, 1]);
      expect(engine.calls.every((call) => call.limit == 2), isTrue);
      expect(engine.calls.where((call) => call.offset > 2), isEmpty);
      final callsAtCompletion = engine.calls.length;
      await Future<void>.delayed(Duration.zero);
      expect(engine.calls, hasLength(callsAtCompletion));
    });

    test('חיתוך ריק סוגר זרמים לפני שנטען fuzzy', () async {
      final engine = _PagedEngine((stream, offset, limit) async => []);
      expect(await _search(engine), isEmpty);
      expect(engine.calls, [(stream: 'ברא אלהים', offset: 0, limit: 2)]);
    });

    test('שגיאה אינה גורמת להמשך שליפה מהזרמים האחרים', () async {
      final error = StateError('paging failure');
      final engine = _PagedEngine((stream, offset, limit) async {
        if (stream == 'הארץ') throw error;
        return [for (var id = offset; id < offset + limit; id++) _result(id)];
      });
      await expectLater(_search(engine), throwsA(same(error)));
      final callsAtFailure = engine.calls.length;
      await Future<void>.delayed(Duration.zero);
      expect(engine.calls, hasLength(callsAtFailure));
      expect(engine.calls.where((call) => call.stream == 'fuzzy'), isEmpty);
    });

    test('קבוצת id שווה שחוצה עמודים ממוינת לפני החיתוך', () async {
      final engine = _PagedEngine((stream, offset, limit) async {
        final source = stream == 'fuzzy'
            ? [_result(1, path: 'b'), _result(1, path: 'a'), _result(2)]
            : [_result(1, path: 'a')];
        return source.skip(offset).take(limit).toList();
      });
      final results = await _search(engine, limit: 1);
      expect(results.map((r) => r.filePath), ['a']);
      expect(engine.calls.every((call) => call.limit == 1), isTrue);
    });
  }, skip: ready ? false : searchEngineSkipReason);
}
