import 'dart:developer' show reachabilityBarrier;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/utils/user_regex_query.dart';
import 'package:otzaria/text_book/models/search_results.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria/utils/text/text_manipulation.dart'
    show computeHighlightRanges, replaceHolyNames, HolyNameStyle;

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
      final ranges = UserRegexSnippetHighlighter().rangesFor(
        line: line,
        snippet: last.snippet,
        matchOffset: last.matchOffset!,
        query: query,
      );
      expect(words(last.snippet, ranges), ['אהרן']);
      expect(ranges!.single.last, last.snippet.length);
    });

    test('ביטוי ללא עוגן אינו מעבד את שורת המקור', () {
      final highlighter = UserRegexSnippetHighlighter();
      for (final query in ['/משה/', '/[^מ]שה/']) {
        expect(
          highlighter.rangesFor(
            line: 'ויאמר משה',
            snippet: 'משה',
            matchOffset: 6,
            query: query,
          ),
          isNull,
        );
      }
    });

    test('כמה קטעים מאותה שורה מקבלים טווחים יחסיים להופעה הנכונה', () async {
      final line = 'משה ${'דבר ' * 100}אהרן ${'דבר ' * 100}אהרן';
      const query = '/^משה|אהרן/';
      final results = (await searchUserRegexInContent(
        content: [line],
        query: query,
        matcher: UserRegexQuery.matcher(query)!,
      ))!.results;
      final highlighter = UserRegexSnippetHighlighter();
      for (var repeat = 0; repeat < 2; repeat++) {
        for (final result in results) {
          final ranges = highlighter.rangesFor(
            line: line,
            snippet: result.snippet,
            matchOffset: result.matchOffset!,
            query: query,
          );
          expect(ranges, hasLength(1));
          final range = ranges!.single;
          expect(
            result.snippet.substring(range[0], range[1]),
            result == results.first ? 'משה' : 'אהרן',
          );
        }
      }
    });

    test('החלפת תצוגה, שאילתה או תוכן אינה משתמשת בטווחים ישנים', () {
      const name = 'יהוה';
      final line = 'משה ${'$name דבר ' * 30}אהרן';
      const snippet = '$name דבר אהרן';
      final highlighter = UserRegexSnippetHighlighter();
      for (final style in [null, ...HolyNameStyle.values, null]) {
        String display(String text) =>
            style == null ? text : replaceHolyNames(text, style: style);
        final ranges = highlighter.rangesFor(
          line: line,
          snippet: snippet,
          matchOffset: line.indexOf('אהרן'),
          query: '/^משה|אהרן/',
          holyNameStyle: style,
        );
        final shown = display(snippet);
        expect(ranges, [
          [shown.length - 4, shown.length],
        ]);
      }
      expect(
        highlighter.rangesFor(
          line: line,
          snippet: snippet,
          matchOffset: line.indexOf('אהרן'),
          query: '/^משה/',
        ),
        isEmpty,
      );
      expect(
        highlighter.rangesFor(
          line: 'אהרן סוף',
          snippet: 'אהרן',
          matchOffset: 0,
          query: '/^אהרן/',
        ),
        [
          [0, 4],
        ],
      );
    });

    test('סוף קטע אינו סוף שורה, וגם HTML ושמות קודש ממופים לתצוגה', () {
      final highlighter = UserRegexSnippetHighlighter();
      expect(
        highlighter.rangesFor(
          line: 'משה אהרן דבר סוף',
          snippet: 'משה אהרן',
          matchOffset: 0,
          query: r'/משה|אהרן$/',
        ),
        [
          [0, 3],
        ],
      );
      const line = '<p>מֹשֶׁה &amp;amp; יהוה <b>אהרן</b></p>';
      const snippet = '&amp; יהוה אהרן';
      expect(
        highlighter.rangesFor(
          line: line,
          snippet: snippet,
          matchOffset: cleanLineForSearch(line).indexOf('אהרן'),
          query: '/^משה|אהרן/',
          holyNameStyle: HolyNameStyle.hehApostrophe,
        ),
        [
          [5, 9],
        ],
      );
    });

    test('סימני Mn שנשארים בשם קודש אינם מזיזים קטע להופעה קודמת', () {
      const name = 'י\u0301הו\u0301ה';
      final line = 'משה ${'$name ' * 10}דבר אהרן דבר אהרן';
      for (final style in HolyNameStyle.values) {
        expect(
          UserRegexSnippetHighlighter().rangesFor(
            line: line,
            snippet: 'דבר אהרן',
            matchOffset: line.lastIndexOf('אהרן'),
            query: r'/^משה|אהרן$/',
            holyNameStyle: style,
          ),
          [
            [4, 8],
          ],
          reason: style.name,
        );
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
