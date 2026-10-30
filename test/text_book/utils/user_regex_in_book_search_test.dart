import 'dart:developer' show reachabilityBarrier;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/utils/user_regex_query.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria/utils/text/text_manipulation.dart'
    show computeHighlightRanges;

import '../../support/search_engine_test_init.dart';

/// חיפוש `/…/` בתוך ספר פתוח — במתאם של המנוע, לא ב-RegExp של Dart.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  const content = [
    '<h2>פרק א</h2>',
    'ויאמר <b>מֹשֶׁה</b> אל אהרן ומשה שב',
    'ויאמר משה',
    'רבנו אל העם',
    '<h2>פרק ב</h2>',
    'שמע בני ישראל',
  ];

  Future<({List<TextSearchResult> results, bool truncated})?> search(
    String query, {
    ({int start, int? end})? range,
    bool Function()? isCurrent,
  }) => searchUserRegexInContent(
    content: content,
    query: query,
    matcher: UserRegexQuery.matcher(query)!,
    crossesLines: query.contains(' '),
    range: range,
    isCurrent: isCurrent,
  );

  group('חיפוש רג\'קס בספר', () {
    test('כל הופעה היא תוצאה, עם כתובת והיסט בשורה הנקייה', () async {
      final found = (await search('/ו?משה/'))!;
      final results = found.results;
      expect(results.map((r) => r.index), [1, 1, 2]);
      expect(results.first.address.trim(), 'פרק א');
      final clean = cleanLineForSearch(content[1]);
      expect(
        clean.substring(
          results.first.matchOffset!,
          results.first.matchOffset! + 'משה'.length,
        ),
        'משה',
      );
      expect(found.truncated, isFalse);
    });

    test('רצף מילים שנמשך לשורה הבאה', () async {
      final results = (await search('/משה רבנו/'))!.results;
      expect(results, hasLength(1));
      expect(results.single.index, 2);
      expect(results.single.continuesToNextLine, isTrue);
    });

    test('הגבלה לקטע', () async {
      final results = (await search(
        '/שמע .* ישראל/',
        range: (start: 4, end: null),
      ))!.results;
      expect(results.map((r) => r.index), [5]);
      expect(results.single.address.trim(), 'פרק ב');
    });

    test('הדגשת הקטע מחושבת על השורה המלאה: ^ אינו תחילת הקטע', () async {
      final line = 'ויאמר משה אל אהרן ${'דבר ' * 60}ויאמר ${'לו ' * 28}אהרן';
      const query = '/^ויאמר|אהרן/';
      final last = (await searchUserRegexInContent(
        content: [line],
        query: query,
        matcher: UserRegexQuery.matcher(query)!,
      ))!.results.last;
      expect(last.snippet, startsWith('ויאמר לו'));
      List<String> words(String text, List<List<int>>? ranges) => [
        for (final r in ranges!) text.substring(r[0], r[1]),
      ];
      // בקטע החתוך ^ נופל על תחילת הקטע ומדגיש ויאמר שאינו בתחילת השורה.
      expect(
        words(last.snippet, computeHighlightRanges(last.snippet, query)),
        contains('ויאמר'),
      );
      for (final display in [null, (String t) => t.replaceAll('דבר', 'ד')]) {
        final shown = display?.call(last.snippet) ?? last.snippet;
        final ranges = snippetHighlightRangesInLine(
          line: line,
          snippet: last.snippet,
          matchOffset: last.matchOffset!,
          query: query,
          display: display,
        );
        expect(words(shown, ranges), ['אהרן']);
        expect(ranges!.single.last, shown.length);
      }
    });

    test('חיפוש שהוחלף מחזיר null', () async {
      final many = [for (var i = 0; i < 300; i++) 'ויאמר משה'];
      final found = await searchUserRegexInContent(
        content: many,
        query: '/משה/',
        matcher: UserRegexQuery.matcher('/משה/')!,
        isCurrent: () => false,
      );
      expect(found, isNull);
    });

    test('תוכן ספר שנסגר אינו מוחזק אחרי החיפוש', () async {
      final weak = await _searchDiscardedBook();
      await _forceGc();
      expect(weak.target, isNull);
    });

    test('השאילתה בספר נשמרת כפי שהוקלדה', () {
      expect(searchableInBookQuery(' /מֹשֶׁה|אהרן/ '), '/מֹשֶׁה|אהרן/');
      expect(searchableInBookQuery('מֹשֶׁה|אהרן'), 'משה אהרן');
    });
  }, skip: engineReady ? false : searchEngineSkipReason);
}

// בפונקציה נפרדת: משתנה מקומי בטסט עצמו נשאר חי במסגרת עד סופו.
Future<WeakReference<List<String>>> _searchDiscardedBook() async {
  final book = [for (var i = 0; i < 50; i++) 'ויאמר משה $i'];
  await searchUserRegexInContent(
    content: book,
    query: '/משה/',
    matcher: UserRegexQuery.matcher('/משה/')!,
  );
  return WeakReference(book);
}

Future<void> _forceGc() async {
  final barrier = reachabilityBarrier;
  final storage = <List<int>>[];
  while (reachabilityBarrier < barrier + 2) {
    storage.add(List.generate(30000, (n) => n));
    if (storage.length > 100) storage.removeAt(0);
    await Future<void>.delayed(Duration.zero);
  }
}
