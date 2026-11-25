import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/utils/literal_search_pattern.dart';
import 'package:otzaria/search/utils/user_regex_query.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

import '../support/search_engine_test_init.dart';

/// #5699: טקסט ארוך שהודבק לחיפוש בספר תקע את ה-UI בהדגשת כל שורה, אף
/// שהחיפוש עצמו דוחה שאילתה ארוכה מ-1000 תווים.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();
  const line = 'ויאמר משה אל העם אל תיראו התיצבו וראו את ישועת ה׳';
  final overlong = List.filled(150, 'ויאמר משה').join(' ');

  test(
    'שאילתה ארוכה מסף החיפוש אינה מודגשת, גם כשהשורה מכילה אותה',
    () {
      expect(isOverlongSearchQuery(overlong), isTrue);
      expect(highLight(overlong, overlong), overlong);
      expect(countMatches(overlong, overlong), 0);
    },
    skip: engineReady ? false : 'search engine unavailable',
  );

  test(
    'ציטוט ארוך (רקע צהוב) עדיין מודגש',
    () {
      expect(
        highLight(overlong, overlong, yellowBackground: true),
        contains('otzaria-mark'),
      );
    },
    skip: engineReady ? false : 'search engine unavailable',
  );

  test('ניקוד אינו נספר: אחרי נרמול השאילתה בתוך הסף', () {
    final pointed = List.filled(70, 'וַיֹּאמֶר מֹשֶׁה').join(' ');
    expect(pointed.length, greaterThan(1000));
    expect(isOverlongSearchQuery(pointed), isFalse);
  });

  test(
    'שאילתה רגילה עדיין מודגשת',
    () {
      expect(isOverlongSearchQuery('משה'), isFalse);
      expect(highLight(line, 'משה'), contains('otzaria-search-hit'));
    },
    skip: engineReady ? false : 'search engine unavailable',
  );

  test(
    'רג׳קס תקין נשאר מודגש ונספר',
    () {
      const regex = '/מו?שה/';
      const text = 'ויאמר מֹשֶׁה אל מושה';
      expect(UserRegexQuery.isValid(regex), isTrue);
      expect(isOverlongSearchQuery(regex), isFalse);
      expect(highLight(text, regex), contains('otzaria-search-hit'));
      expect(countMatches(text, regex), 2);
    },
    skip: engineReady ? false : 'search engine unavailable',
  );
}
