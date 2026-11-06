import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/semantic_search/models/semantic_mode_gate.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final ready = await tryInitSearchEngine();

  group('היקף אישי ומצורף במנוע החיפוש המשולב', () {
    late Directory temporary;
    late SearchEngine engine;
    late SearchRepository repository;
    const books = [
      (key: 'id:1', facet: '/תנ״ך/id:1', text: 'מרקחת רשמית'),
      (key: 'uid:4', facet: '/uid:4', text: 'מרקחת אישית'),
      (key: 'db:lib:3', facet: '/db:lib:3', text: 'מרקחת מצורפת'),
    ];

    setUpAll(() async {
      temporary = await Directory.systemTemp.createTemp('semantic-scope-');
      engine = await SearchEngine.newInstance(path: temporary.path);
      for (var i = 0; i < books.length; i++) {
        final book = books[i];
        await engine.addDocument(
          ordinal: i,
          title: book.key,
          reference: 'שורה ראשונה',
          topics: book.facet,
          text: book.text,
          segment: BigInt.zero,
          isPdf: false,
          filePath: book.key,
        );
      }
      await engine.commit();
      repository = SearchRepository(
        engineProvider: () async => RustSearchEngineOperations(engine),
      );
    });

    tearDownAll(() async {
      await engine.optimize();
      engine.dispose();
      if (!Platform.isWindows) await temporary.delete(recursive: true);
    });

    for (final mode in SemanticLexicalMode.values) {
      test('השליפה מכבדת את הבחירה ואינה מתרחבת לכל הספרייה: $mode', () async {
        for (final selection in [
          [books[1]],
          [books[2]],
          [books[0], books[1]],
          books,
        ]) {
          final facets = selection.map((book) => book.facet).toList();
          expect(
            facets.every(
              (facet) => isSemanticScopeFacetSupported(
                facet,
                includeLexical: true,
              ),
            ),
            isTrue,
          );
          final response = await repository.searchSemantic(
            SemanticSearchRequest(
              query: 'מרקחת',
              facets: semanticScopeFacets(facets),
              limit: 10,
              lexicalMode: mode,
            ),
          );
          expect(
            response.results.map((result) => result.filePath).toSet(),
            selection.map((book) => book.key).toSet(),
          );
          expect(response.lexicalTotalCount, selection.length);
        }
      });
    }
  }, skip: ready ? false : searchEngineSkipReason);
}
