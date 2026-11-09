import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/utils/in_book_search_routing.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticLexicalMode;

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
  const red = '<span style="color: otzaria-search-hit">';

  String render(
    String line,
    InBookSearchParameters params, {
    required bool isSearchResultLine,
  }) => highLight(
    line,
    query,
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
      // לכן קטע של תוצאה לפי עניין בלבד אינו מסומן כשורת תוצאה בפתיחה.
      expect(render(reversed, smart, isSearchResultLine: false), reversed);
    });
  }, skip: engineReady ? false : 'search engine native library unavailable');
}
