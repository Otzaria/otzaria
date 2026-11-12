import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

const _name = '\u05d9\u05d4\u05d5\u05d4';

List<String> _paintedWords(
  String text,
  String query, {
  SearchMatchPolicy policy = SearchMatchPolicy.smart,
  int distance = 0,
  bool resultLine = false,
}) => [
  for (final range in utils.computeHighlightRanges(
    text,
    query,
    isFuzzy: true,
    searchDistance: distance,
    matchPolicy: policy,
    isSearchResultLine: resultLine,
  ))
    text.substring(range[0], range[1]),
];

Future<void> main() async {
  final ready = await tryInitSearchEngine();
  group('הדגשת חיפוש חכם בספר פתוח', () {
    late Directory temporary;
    late SearchEngine engine;

    setUpAll(() async {
      temporary = await Directory.systemTemp.createTemp('smart-reader-');
      engine = await SearchEngine.newInstance(path: temporary.path);
      const lines = ['$_name טוב ידוד', 'אב גד הו אבב טוב', 'יקוק', _name];
      for (var i = 0; i < lines.length; i++) {
        await engine.addDocument(
          ordinal: i,
          title: 'ספר',
          reference: 'שורה $i',
          topics: '/reader',
          text: lines[i],
          segment: BigInt.from(i),
          isPdf: false,
          filePath: 'reader',
        );
      }
      await engine.commit();
    });

    tearDownAll(() async {
      engine.dispose();
      if (Platform.isWindows) return;
      try {
        await temporary.delete(recursive: true);
      } on FileSystemException {
        // תהליכוני מיזוג עשויים עדיין להחזיק קובצי אינדקס זמניים.
      }
    });

    Future<void> prime(
      String query,
      SearchQuerySemantics semantics, {
      int distance = 0,
      Future<HighlightPattern?> Function()? fetch,
    }) => utils.primeHighlightPattern(
      searchQuery: query,
      searchOptions: const {},
      alternativeWords: const {},
      spacingValues: const {},
      searchDistance: distance,
      isFuzzy: true,
      querySemantics: semantics,
      fetch:
          fetch ??
          () => semantics == SearchQuerySemantics.smart
              ? engine.generateIndexSmartHighlightPattern(
                  query: query,
                  lexicalMode: SemanticLexicalMode.fuzzy,
                  maxDistance: distance,
                )
              : engine.generateIndexFuzzyHighlightPattern(
                  query: query,
                  maxDistance: distance,
                ),
    );

    test('לפני priming הכינוי החכם מדגיש כתיב קנוני מנוקד בלבד במצב חכם', () {
      const text = '😀 <b>יְהֹוָה</b>';
      for (final query in ['יקוק', 'ידוד']) {
        expect(_paintedWords(text, query), ['יְהֹוָה']);
        expect(
          _paintedWords(text, query, policy: SearchMatchPolicy.standard),
          isEmpty,
        );
        expect(
          utils.highLight(
            text,
            query,
            isFuzzy: true,
            matchPolicy: SearchMatchPolicy.smart,
          ),
          contains('color: otzaria-search-hit'),
        );
      }
    });

    test('fallback שומר ציטוט חלקי בתוך שורה גם לפני priming', () {
      const query = '"אב גד" הו';
      expect(
        utils.highLight(
          'אב',
          query,
          isFuzzy: true,
          matchPolicy: SearchMatchPolicy.smart,
          nextLine: 'גד הו',
        ),
        isNot(contains('color: otzaria-search-hit')),
      );
      expect(_paintedWords('אב רחוק גד הו', query), isEmpty);
      expect(_paintedWords('אב גד הו', query), ['אב', 'גד', 'הו']);
    });

    test(
      'כשל priming משאיר fallback חיובי ששומר ציטוטים וגבולות שורה',
      () async {
        const query = '"ידוד אמת" סוף';
        await prime(
          query,
          SearchQuerySemantics.smart,
          fetch: () async =>
              throw StateError('index is temporarily unavailable'),
        );
        expect(_paintedWords('$_name אמת סוף', query), [_name, 'אמת', 'סוף']);
        expect(_paintedWords('$_name רחוק אמת סוף', query), isEmpty);
        expect(
          utils.highLight(
            _name,
            query,
            isFuzzy: true,
            matchPolicy: SearchMatchPolicy.smart,
            nextLine: 'אמת סוף',
          ),
          isNot(contains('color: otzaria-search-hit')),
        );
      },
    );

    test('מטמוני smart ו־regular נפרדים בשני סדרי ההזנה', () async {
      for (final entry in {'יקוק': false, 'ידוד': true}.entries) {
        final modes = entry.value
            ? [SearchQuerySemantics.smart, SearchQuerySemantics.regular]
            : [SearchQuerySemantics.regular, SearchQuerySemantics.smart];
        for (final mode in modes) {
          await prime(entry.key, mode);
          expect(_paintedWords(_name, entry.key), [_name]);
          expect(
            _paintedWords(_name, entry.key, policy: SearchMatchPolicy.standard),
            isEmpty,
          );
        }
      }
    });

    test('בקשת regular ממתינה אינה חוסמת priming חכם לאותה שאילתה', () async {
      const query = 'בידוד';
      final pending = Completer<HighlightPattern?>();
      final regular = prime(
        query,
        SearchQuerySemantics.regular,
        fetch: () => pending.future,
      );
      await prime(query, SearchQuerySemantics.smart);
      expect(_paintedWords('ב$_name', query), ['ב$_name']);
      pending.complete(
        await engine.generateIndexFuzzyHighlightPattern(
          query: query,
          maxDistance: 0,
        ),
      );
      await regular;
      expect(_paintedWords('ב$_name', query), ['ב$_name']);
      expect(
        _paintedWords('ב$_name', query, policy: SearchMatchPolicy.standard),
        isEmpty,
      );
    });

    test('ציטוטים וחלופות מעורבות מודגשים בטקסט הפתוח ובטווחים', () async {
      const query = '"יקוק טוב" ידוד';
      const text = '😀 <b>$_name טוב</b> $_name';
      await prime(query, SearchQuerySemantics.smart);
      expect(_paintedWords(text, query), [_name, 'טוב', _name]);
      final html = utils.highLight(
        text,
        query,
        isFuzzy: true,
        matchPolicy: SearchMatchPolicy.smart,
      );
      expect('color: otzaria-search-hit'.allMatches(html), hasLength(3));
    });

    test('אותה מילה מחוץ לציטוט מתרחבת בלי לפרק את הציטוט', () async {
      const query = '"אב גד" אב';
      await prime(query, SearchQuerySemantics.smart, distance: 1);
      expect(_paintedWords('אב גד אבב', query, distance: 1), [
        'אב',
        'גד',
        'אבב',
      ]);
      expect(_paintedWords('גד אבב', query, distance: 1), isEmpty);
      expect(_paintedWords('גד אבב', query, distance: 1, resultLine: true), [
        'אבב',
      ]);
    });

    test('ציטוטים חופפים שומרים כל מילה פעם אחת והיסטי emoji ו־HTML', () async {
      const query = '"אב גד" "גד הו"';
      const text = '😀 <b>אב גד הו</b>';
      await prime(query, SearchQuerySemantics.smart);
      expect(_paintedWords(text, query), ['אב', 'גד', 'הו']);
      expect(
        utils.computeHighlightRanges(
          text,
          query,
          isFuzzy: true,
          matchPolicy: SearchMatchPolicy.smart,
        ),
        [
          [6, 8],
          [9, 11],
          [12, 14],
        ],
      );
    });

    test('רק ציטוט מלא יכול להשלים הדגשה מהשורה הסמוכה', () async {
      const full = '"יקוק שמו"';
      const partial = '"יקוק שמו" לעולם';
      await prime(full, SearchQuerySemantics.smart);
      await prime(partial, SearchQuerySemantics.smart);
      expect(
        utils.highLight(
          'שם $_name',
          full,
          isFuzzy: true,
          matchPolicy: SearchMatchPolicy.smart,
          nextLine: 'שמו לעולם',
        ),
        contains('color: otzaria-search-hit'),
      );
      expect(
        utils.highLight(
          'שם $_name',
          partial,
          isFuzzy: true,
          matchPolicy: SearchMatchPolicy.smart,
          nextLine: 'שמו לעולם',
        ),
        isNot(contains('color: otzaria-search-hit')),
      );
      expect(_paintedWords('$_name שמו לעולם', partial), [
        _name,
        'שמו',
        'לעולם',
      ]);
    });

    test('הכנת תבנית חכמה דרך ה־gateway פועלת גם בלי שליפה', () async {
      const query = '"ידוד טוב"';
      final prepared = Completer<void>();
      void changed() {
        if (!prepared.isCompleted) prepared.complete();
      }

      utils.highlightPatternRevision.addListener(changed);
      try {
        RustSearchEngineOperations(engine).primeSmartHighlightPattern(
          const SearchEngineRequest(
            query: query,
            facets: [],
            searchMode: SearchMode.fuzzy,
          ),
        );
        await prepared.future.timeout(const Duration(seconds: 30));
      } finally {
        utils.highlightPatternRevision.removeListener(changed);
      }
      expect(_paintedWords('$_name טוב', query), [_name, 'טוב']);
    });

    test('מדיניות smart שנשמרה במצב לא מקורב משתמשת במטמון הרגיל', () async {
      const query = 'מדיניותשמורה';
      await utils.primeHighlightPattern(
        searchQuery: query,
        searchOptions: const {},
        alternativeWords: const {},
        spacingValues: const {},
        searchDistance: 0,
        isFuzzy: false,
        anyOrder: true,
        fetch: () async => const HighlightPattern(
          combinedPattern: 'חלופה',
          wordPatterns: ['חלופה'],
          wordBoundaryEligible: [true],
        ),
      );
      const policy = SearchMatchPolicy(
        querySemantics: SearchQuerySemantics.smart,
        anyOrder: true,
      );
      expect(
        utils.highLight(
          'חלופה',
          query,
          matchPolicy: policy,
          isSearchResultLine: true,
        ),
        contains('color: otzaria-search-hit'),
      );
      expect(
        utils.computeHighlightRanges(
          'חלופה',
          query,
          matchPolicy: policy,
          isSearchResultLine: true,
        ),
        [
          [0, 5],
        ],
      );
    });
  }, skip: ready ? false : searchEngineSkipReason);
}
