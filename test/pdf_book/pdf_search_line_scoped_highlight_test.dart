import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

/// הטקסטים המודגשים ב-[page], כל אחד עם מספר השורה שלו.
List<(int, String)> _highlighted(Pattern pattern, String page) => [
  for (final match in pattern.allMatches(page))
    (
      '\n'.allMatches(page.substring(0, match.start)).length,
      match.group(0)!,
    ),
];

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('הדגשה שאינה רצף — רק בשורות שהמנוע התאים (#3690)', () {
    const query = 'ממון לו תובעין';

    Pattern build(
      List<String> snippets,
      InBookSearchSettings settings,
    ) => PdfBookSearchView.buildAdvancedHighlightPattern(
      snippets,
      query: query,
      settings: settings.forQuery(query),
    )!;

    test('מקורב: מילים בודדות בשורות אחרות אינן מודגשות', () {
      final pattern = build(
        ['<font>ממון</font> שאין <font>לו</font> <font>תובעין</font>'],
        const InBookSearchSettings(
          searchMode: SearchMode.fuzzy,
          distance: kMaxFuzzyDistance,
        ),
      );
      const page = 'ממון בשורה אחרת\nכאן ממון שאין לו תובעין\nושוב תובעין לבד';

      expect(_highlighted(pattern, page), [
        (1, 'ממון'),
        (1, 'לו'),
        (1, 'תובעין'),
      ]);
    });

    test('טווח פסקה: רק השורה שמכילה את כל המילים, בכל סדר', () {
      final pattern = build(
        ['<font>תובעין</font> הרבה <font>לו</font> אבל <font>ממון</font>'],
        const InBookSearchSettings(
          searchMode: SearchMode.advanced,
          matchPolicy: SearchMatchPolicy(
            proximityScope: SearchScope.sameParagraph,
          ),
        ),
      );
      const page = 'לו לבד\nתובעין הרבה לו אבל ממון\nממון לבד';

      expect(_highlighted(pattern, page), [
        (1, 'תובעין'),
        (1, 'לו'),
        (1, 'ממון'),
      ]);
    });

    test('"לפחות N מילים": שורה עם מילה אחת אינה מודגשת', () {
      final pattern = build(
        ['<font>ממון</font> שאין <font>תובעין</font>'],
        const InBookSearchSettings(
          searchMode: SearchMode.advanced,
          matchPolicy: SearchMatchPolicy(
            wordMatchMode: WordMatchMode.atLeast,
            wordMatchCount: 2,
          ),
        ),
      );
      const page = 'ממון לבד\nממון שאין תובעין\nתובעין לבד';

      expect(_highlighted(pattern, page), [(1, 'ממון'), (1, 'תובעין')]);
    });

    test('המתאם לא מצא רצף בקטעים: המונחים רק בשורת ההתאמה', () {
      // הסדר בקטע הפוך, ובלי "בכל סדר" המתאם אינו מוצא בו רצף.
      final pattern = build(
        ['<font>תובעין</font> <font>לו</font> שאין <font>ממון</font>'],
        const InBookSearchSettings(searchMode: SearchMode.advanced),
      );
      const page = 'ממון לבד\nתובעין לו שאין ממון\nלו';

      expect(_highlighted(pattern, page), [
        (1, 'תובעין'),
        (1, 'לו'),
        (1, 'ממון'),
      ]);
    });

    test('מונחים שונים עם אותה תבנית (`"`/`״`) הם מונח אחד', () {
      final pattern = build(
        [
          '<font>רמב"ם</font> שם <font>ממון</font>',
          '<font>רמב״ם</font> <font>תובעין</font> כאן',
        ],
        const InBookSearchSettings(
          searchMode: SearchMode.fuzzy,
          distance: kMaxFuzzyDistance,
        ),
      );
      const page = 'רמב״ם תובעין כאן\nתובעין לבד';

      expect(_highlighted(pattern, page), [(0, 'רמב״ם'), (0, 'תובעין')]);
    });

    for (final (first, second) in [
      ('Hello', 'hello'),
      ('Σ', 'ς'),
      ('S', 'ſ'),
      ('K', 'K'),
    ]) {
      test('כל מקורות הרגקס שמתאימים למופע נספרים: $first / $second', () {
        final pattern = build(
          [
            '<font>$first</font> <font>world</font>',
            '<font>$second</font> <font>word</font>',
          ],
          const InBookSearchSettings(searchMode: SearchMode.fuzzy),
        );
        final page = '$first world\n$second word\n$second לבד';

        expect(_highlighted(pattern, page), [
          (0, first),
          (0, 'world'),
          (1, second),
          (1, 'word'),
        ]);
      });
    }

    for (final policy in [
      const SearchMatchPolicy(proximityScope: SearchScope.sameParagraph),
      const SearchMatchPolicy(
        wordMatchMode: WordMatchMode.atLeast,
        wordMatchCount: 2,
      ),
    ]) {
      test('מקורות שקולים נספרים גם במדיניות $policy', () {
        final pattern = build(
          [
            '<font>Hello</font> <font>world</font>',
            '<font>hello</font> <font>word</font>',
          ],
          InBookSearchSettings(
            searchMode: SearchMode.advanced,
            matchPolicy: policy,
          ),
        );

        expect(_highlighted(pattern, 'Hello world\nhello word\nhello לבד'), [
          (0, 'Hello'),
          (0, 'world'),
          (1, 'hello'),
          (1, 'word'),
        ]);
      });
    }

    for (final (first, second) in [('I', 'ı'), ('ß', 'ss')]) {
      test('מונחים שהרגקס מבחין ביניהם נשארים נפרדים: $first / $second', () {
        final pattern = build(
          [
            '<font>$first</font> <font>world</font>',
            '<font>$second</font> <font>word</font>',
          ],
          const InBookSearchSettings(searchMode: SearchMode.fuzzy),
        );
        final page = '$first world\n$second word\n$first word\n$second world';

        expect(_highlighted(pattern, page), [
          (0, first),
          (0, 'world'),
          (1, second),
          (1, 'word'),
        ]);
      });
    }

    test('מקורות חופפים חלקית נספרים לפי המופע, גם עם ניקוד', () {
      final pattern = build(
        [
          '<font>יקוק</font> <font>ממון</font>',
          '<font>יהוה</font> <font>תובעין</font>',
        ],
        const InBookSearchSettings(searchMode: SearchMode.fuzzy),
      );
      const page = 'יְהוָה ממון\nיְהוָה תובעין\nיקוק תובעין\nיקוק ממון';

      expect(_highlighted(pattern, page), [
        (0, 'יְהוָה'),
        (0, 'ממון'),
        (1, 'יְהוָה'),
        (1, 'תובעין'),
        (3, 'יקוק'),
        (3, 'ממון'),
      ]);
    });

    test('50 מונחים ב־1000 קטעים שומרים גם את קבוצת המונחים האחרונה', () {
      String term(int i) =>
          'term${String.fromCharCode(97 + i ~/ 26)}${String.fromCharCode(97 + i % 26)}';
      final pattern = build(
        List.generate(
          1000,
          (i) =>
              '<font>${term(i % 50)}</font> <font>${term((i + 1) % 50)}</font>',
        ),
        const InBookSearchSettings(searchMode: SearchMode.fuzzy),
      );
      final lines = List.generate(
        50,
        (i) => '${term(i)} ${term((i + 1) % 50)}',
      );
      final page = [...lines, '${term(49)} לבד'].join('\n');

      expect(_highlighted(pattern, page), [
        for (var i = 0; i < 50; i++) ...[
          (i, term(i)),
          (i, term((i + 1) % 50)),
        ],
      ]);
    });

    test('מקורב באינדקס PDF אמיתי: שני כתיבים נשארים מודגשים', () async {
      final directory = await Directory.systemTemp.createTemp('pdf_highlight_');
      final engine = await SearchEngine.newInstance(path: directory.path);
      addTearDown(() async {
        engine.dispose();
        await directory.delete(recursive: true);
      });
      const page = 'Hello world\nhello word\nhello לבד';
      await engine.addPdfBook(
        title: 'בדיקת כתיבים',
        topics: '/test',
        filePath: 'case.pdf',
        pages: [
          const PdfPageInput(reference: 'עמוד א', text: page, pageIndex: 0),
        ],
      );
      await engine.commit();
      final hits = await engine.searchFuzzy(
        query: 'hello world',
        facets: [],
        limit: 20,
        offset: 0,
        maxDistance: 1,
        order: ResultsOrder.catalogue,
        matchNikud: false,
        matchTaamim: false,
      );
      expect(hits, hasLength(2));
      final pattern = PdfBookSearchView.buildAdvancedHighlightPattern(
        hits.map((hit) => hit.text),
        query: 'hello world',
        settings: const InBookSearchSettings(
          searchMode: SearchMode.fuzzy,
          distance: 1,
        ).forQuery('hello world'),
      )!;

      expect(_highlighted(pattern, page), [
        (0, 'Hello'),
        (0, 'world'),
        (1, 'hello'),
        (1, 'word'),
      ]);
    });

    test('קטע שחוצה שורה: כל צד נבדק מול שורה משלו', () {
      final pattern = build(
        ['<font>ממון</font> שאין<br><font>לו</font> <font>תובעין</font>'],
        const InBookSearchSettings(
          searchMode: SearchMode.fuzzy,
          distance: kMaxFuzzyDistance,
        ),
      );
      const page = 'ממון שאין\nלו תובעין\nלו לבד';

      expect(_highlighted(pattern, page), [
        (0, 'ממון'),
        (1, 'לו'),
        (1, 'תובעין'),
      ]);
    });
  }, skip: engineReady ? false : searchEngineSkipReason);
}
