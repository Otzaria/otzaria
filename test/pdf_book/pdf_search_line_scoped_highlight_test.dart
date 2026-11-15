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
