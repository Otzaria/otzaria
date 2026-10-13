import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

/// issue #2006: "שמור על סדר המילים המקורי" מבוטל מוצא את המילים בכל סדר
/// בתוך חלון המרווח — גם בחיפוש הרגיל, שמנותב לשם כך למסלול המתקדם.
Future<void> main() async {
  final ready = await tryInitSearchEngine();
  const book = '/order/book';
  const lines = [
    'בראשית ברא אלהים את השמים', // 0: לפי הסדר
    'ויאמר אלהים יהי אור ברא', // 1: בסדר הפוך, מרחק 2
    'אלהים ברא', // 2: בסדר הפוך, צמודות
    'ברא דבר אחר', // 3: מילה אחת בלבד
  ];

  late Directory temporary;
  late SearchEngine engine;
  late SearchRepository repository;

  setUpAll(() async {
    if (!ready) return;
    temporary = await Directory.systemTemp.createTemp('any-order-');
    engine = await SearchEngine.newInstance(path: temporary.path);
    for (var i = 0; i < lines.length; i++) {
      await engine.addDocument(
        id: BigInt.from(i + 1),
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

  Future<List<int>> segments(SearchEngineRequest request) async {
    final results = await repository.searchTexts(request);
    return results.map((result) => result.segment.toInt()).toList()..sort();
  }

  group('חיפוש בכל סדר מול המנוע', () {
    test('חיפוש רגיל: לפי הסדר מול בכל סדר', () async {
      const ordered = SearchEngineRequest(
        query: 'אלהים ברא',
        facets: [book],
        limit: 10,
      );
      expect(await segments(ordered), [2]);
      expect(await segments(ordered.copyWith(anyOrder: true)), [0, 2]);
      expect(
        await segments(ordered.copyWith(anyOrder: true, distance: 3)),
        [0, 1, 2],
      );
    });

    test('מרווח ידני גובר על בכל סדר', () async {
      const request = SearchEngineRequest(
        query: 'אלהים ברא',
        facets: [book],
        limit: 10,
        searchMode: SearchMode.advanced,
        anyOrder: true,
        customSpacing: {'0-1': '0'},
      );
      expect(await segments(request), [2]);
    });

    test('חיפוש בתוך ספר נושא את המדיניות', () async {
      final results = await searchBookWithEngine(
        repository,
        query: 'אלהים ברא',
        bookPath: book,
        limit: 10,
        settings: const InBookSearchSettings(
          distance: 3,
          matchPolicy: SearchMatchPolicy(anyOrder: true),
        ),
      );
      expect(
        results.map((result) => result.segment.toInt()).toList()..sort(),
        [0, 1, 2],
      );
    });
  }, skip: ready ? false : searchEngineSkipReason);
}
