import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/text_book/utils/reader_menu_entries.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

Future<void> main() async {
  final ready = await tryInitSearchEngine();
  const topic = '/books/selection-footnote-3384';
  const source =
      'הרי שסמך על מקצת הודאתו<sup class="footnote-marker">3963</sup>';
  const selected = 'הודאתו\u20663963\u2069';
  late Directory directory;
  late SearchEngine engine;
  late SearchRepository repository;

  setUpAll(() async {
    if (!ready) return;
    directory = await Directory.systemTemp.createTemp('reader-footnote-3384-');
    engine = await SearchEngine.newInstance(path: directory.path);
    await engine.addDocument(
      ordinal: 0,
      title: 'ספר בדיקה',
      reference: 'שורה 6262',
      topics: topic,
      text: source,
      segment: BigInt.from(6262),
      isPdf: false,
      filePath: 'id:8010',
    );
    await engine.commit();
    repository = SearchRepository(
      engineProvider: () async => RustSearchEngineOperations(engine),
    );
  });

  tearDownAll(() async {
    if (!ready) return;
    engine.dispose();
    if (Platform.isWindows) return;
    await directory.delete(recursive: true);
  });

  for (final inBook in [false, true]) {
    test(
      'בחירה המסתיימת בסמן נמצאת ${inBook ? 'בתוך הספר' : 'בחיפוש הכללי'}',
      () async {
        Future<List<BigInt>> segments(String query) async {
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
          return results.map((result) => result.segment).toList();
        }

        expect(await segments(selected), isEmpty);
        final query = ReaderMenuSelection(
          selected,
          sourceLines: const [source],
          lineStart: 0,
          lineEnd: 0,
        ).cleaned;
        expect(query, 'הודאתו');
        expect(await segments(query), [BigInt.from(6262)]);
        expect(
          await segments('הרי שסמך על מקצת הודאתו'),
          [BigInt.from(6262)],
        );
      },
      skip: ready ? false : searchEngineSkipReason,
    );
  }
}
