import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

Future<void> main() async {
  final ready = await tryInitSearchEngine();
  const topic = '/books/note-annotation-3292';
  const path = '/notes-3292-fixture.txt';
  // קטע סינתטי; ספר זה אינו מתחזה לפסקה המקורית שבמסד הספרים.
  const source =
      'גוף<sup class="footnote-marker">12</sup>'
      '<i class="footnote">מפורשת</i> סוף';
  late Directory directory;
  late SearchEngine engine;
  late SearchRepository repository;

  setUpAll(() async {
    if (!ready) return;
    directory = await Directory.systemTemp.createTemp('snippet-note-3292-');
    engine = await SearchEngine.newInstance(path: directory.path);
    await engine.addTextBook(
      title: 'ספר בדיקת הערות',
      topics: topic,
      filePath: path,
      text: source,
      textStorage: TextStorage.inIndex,
    );
    await engine.commit();
    repository = SearchRepository(
      engineProvider: () async => RustSearchEngineOperations(engine),
    );
  });

  tearDownAll(() async {
    if (!ready) return;
    engine.dispose();
    if (!Platform.isWindows) await directory.delete(recursive: true);
  });

  for (final inBook in [false, true]) {
    for (final query in ['גוף', 'מפורשת']) {
      test('הערות native ${inBook ? 'בספר' : 'כללי'}: $query', () async {
        final results = inBook
            ? await searchBookWithEngine(
                repository,
                query: query,
                bookPath: topic,
                limit: 10,
                settings: const InBookSearchSettings(distance: 0),
              )
            : await repository.searchTexts(
                SearchEngineRequest(
                  query: query,
                  facets: const ['/'],
                  limit: 10,
                ),
              );
        expect(results, hasLength(1));
        final result = results.single;
        expect(result.filePath, path);
        expect(result.textStatus, TextStatus.ok);
        expect(result.text, contains('<otzaria-note>'));
        expect(result.text, contains('<otzaria-note-marker>'));
        expect(
          SnippetBuilder.htmlToPlainText(result.text),
          'גוף 12 מפורשת סוף',
        );
        final spans = SnippetBuilder.fromHighlightedHtml(
          html: result.text,
          defaultStyle: const TextStyle(fontSize: 20),
          highlightStyle: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ).cast<TextSpan>();
        expect(
          spans.map((span) => span.text).join(),
          'גוף 12 [הערה: מפורשת] סוף',
        );
        final matched = spans
            .where((span) => span.style?.fontWeight == FontWeight.bold)
            .toList();
        expect(matched.map((span) => span.text).join(), query);
        expect(
          matched.every((span) => span.style?.fontStyle == FontStyle.italic),
          query == 'מפורשת',
        );
        expect(
          spans.singleWhere((span) => span.text == '12').style!.fontSize,
          15,
        );
      }, skip: ready ? false : searchEngineSkipReason);
    }
  }
}
