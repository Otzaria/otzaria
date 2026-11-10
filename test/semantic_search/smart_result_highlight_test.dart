import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart'
    show RustSearchEngineOperations;
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/utils/in_book_search_routing.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show ResultsOrder, SearchEngine, SemanticLexicalMode;

import '../support/search_engine_test_init.dart';

/// הדגשת מילות החיפוש החכם בספר שנפתח מתוצאה (issue #2508), באותו מסלול
/// רינדור של הקורא: [highLight] עם פרמטרי הטאב ושורות התוצאה.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  // הפרמטרים שמסך התוצאות מוסר לטאב הקריאה.
  final smart = InBookSearchRouting.resolveForReadingTab(
    searchMode: switch (kSmartSearchLexicalMode) {
      SemanticLexicalMode.exact => SearchMode.exact,
      SemanticLexicalMode.fuzzy => SearchMode.fuzzy,
    },
    distance: kSmartSearchFuzzyMaxDistance,
    matchPolicy: SearchMatchPolicy.smart,
  );

  const query = 'ברך לחם';
  const reversed = 'לחם ואחר כך ברך עליו';
  const missingWord = 'לחם בלבד';
  const red = '<span style="color: otzaria-search-hit">';

  String render(
    String line,
    InBookSearchParameters params, {
    required bool isSearchResultLine,
    String searchQuery = query,
  }) => highLight(
    line,
    searchQuery,
    isFuzzy: params.searchMode == SearchMode.fuzzy,
    searchDistance: params.distance,
    matchPolicy: params.matchPolicy,
    isSearchResultLine: isSearchResultLine,
  );

  group('הדגשה בספר שנפתח מתוצאת חיפוש חכם', () {
    test('שורת תוצאה: מילים מפוזרות ובסדר הפוך מודגשות כל אחת', () {
      final html = render(reversed, smart, isSearchResultLine: true);
      expect(html, contains('$redלחם</span>'));
      expect(html, contains('$redברך</span>'));
    });

    test('הפרמטרים של גרסה 0.9.98 (מדויק, 0) לא הדגישו דבר', () {
      // לפני 0e30a6ff7 תוצאה חכמה נפתחה כחיפוש מדויק — רצף ליטרלי בלבד.
      const legacy = InBookSearchParameters(
        searchMode: SearchMode.exact,
        distance: 0,
      );
      expect(render(reversed, legacy, isSearchResultLine: true), reversed);
    });

    test('שורה שהחיפוש בספר לא החזיר אינה מודגשת מילה-מילה', () {
      // מילה אחת בלבד אינה התאמת AND; השליפה מאומתת בבדיקה הבאה.
      expect(
        render(missingWord, smart, isSearchResultLine: false),
        missingWord,
      );
    });

    test('שליפה והדגשה מסכימות על AND וציטוט לפני ואחרי priming', () async {
      const quoted = '"ברך לחם"';
      const lines = [reversed, query, missingWord];
      const highlighted = [
        '$redלחם</span> ואחר כך $redברך</span> עליו',
        '$redברך</span> $redלחם</span>',
        '$redלחם</span> בלבד',
      ];
      const facet = '/smart-result-highlight';
      final temporary = await Directory.systemTemp.createTemp(
        'smart-result-highlight-',
      );
      await Directory('${temporary.path}/index').create();
      final engine = await SearchEngine.newInstance(
        path: '${temporary.path}/index',
      );
      addTearDown(() async {
        engine.dispose();
        if (Platform.isWindows) return;
        try {
          await temporary.delete(recursive: true);
        } on FileSystemException {
          // תהליכוני מיזוג עשויים עדיין להחזיק קובצי אינדקס זמניים.
        }
      });
      for (var i = 0; i < lines.length; i++) {
        await engine.addDocument(
          ordinal: i,
          title: 'ספר',
          reference: 'שורה $i',
          topics: facet,
          text: lines[i],
          segment: BigInt.from(i),
          isPdf: false,
          filePath: 'smart-result-highlight',
        );
      }
      await engine.commit();

      void checkHighlights(String phase) {
        for (final searchQuery in [query, quoted]) {
          for (final marked in [false, true]) {
            for (var i = 0; i < lines.length; i++) {
              final expected = searchQuery == quoted
                  ? (i == 1 ? highlighted[i] : lines[i])
                  : (i < 2 || marked ? highlighted[i] : lines[i]);
              expect(
                render(
                  lines[i],
                  smart,
                  isSearchResultLine: marked,
                  searchQuery: searchQuery,
                ),
                expected,
                reason: '$phase query=$searchQuery line=$i marker=$marked',
              );
            }
          }
        }
      }

      checkHighlights('before priming');
      // המסלול הקודם לשאילתה לא מצוטטת, על אותו בינארי מאומת.
      final previousRoute = await engine.searchFuzzy(
        query: query,
        facets: const [facet],
        limit: 100,
        offset: 0,
        maxDistance: smart.distance,
        order: ResultsOrder.catalogue,
        matchNikud: false,
        matchTaamim: false,
      );
      expect(previousRoute.map((hit) => hit.segment.toInt()), [0, 1]);

      for (final searchQuery in [query, quoted]) {
        final pattern = await engine.generateIndexSmartHighlightPattern(
          query: searchQuery,
          lexicalMode: kSmartSearchLexicalMode,
          maxDistance: smart.distance,
        );
        expect(pattern, isNotNull);
        final revision = highlightPatternRevision.value;
        await primeHighlightPattern(
          searchQuery: searchQuery,
          searchOptions: const {},
          alternativeWords: const {},
          spacingValues: const {},
          searchDistance: smart.distance,
          isFuzzy: smart.searchMode == SearchMode.fuzzy,
          querySemantics: smart.matchPolicy.querySemantics,
          fetch: () async => pattern,
        );
        expect(highlightPatternRevision.value, greaterThan(revision));
      }
      checkHighlights('after priming');

      final repository = SearchRepository(
        engineProvider: () async => RustSearchEngineOperations(engine),
      );
      final settings = InBookSearchSettings(
        searchMode: smart.searchMode,
        distance: smart.distance,
        matchPolicy: smart.matchPolicy,
      );
      for (final searchQuery in [query, quoted]) {
        final results = await searchBookWithEngine(
          repository,
          query: searchQuery,
          bookPath: facet,
          limit: 100,
          settings: settings,
        );
        expect(
          results.map((hit) => hit.segment.toInt()),
          searchQuery == query ? [0, 1] : [1],
        );
      }
    });
  }, skip: engineReady ? false : 'search engine native library unavailable');
}
