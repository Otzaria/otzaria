import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_match_policy.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

/// הדגשת `/…/` נעשית במתאם של המנוע, על הטקסט כפי שהוא מוצג.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  List<String> painted(String html) => [
    for (final match in RegExp(
      r'<span style="color: red">([^<]*)</span>',
    ).allMatches(html))
      match.group(1)!,
  ];

  group('הדגשת רג\'קס מהמשתמש', () {
    test('מילה עם ניקוד ובתוך HTML', () {
      const line = 'ויאמר <b>מֹשֶׁה</b> אל מושה ואל משהו';
      expect(painted(highLight(line, '/מו?שה/')), ['מֹשֶׁה', 'מושה']);
      expect(countMatches(line, '/מו?שה/'), 2);
    });

    test('טווחים לרשימת התוצאות', () {
      const line = 'כתב הרמב"ם בהלכות';
      final ranges = computeHighlightRanges(line, '/הרמבם/');
      expect(ranges, hasLength(1));
      expect(line.substring(ranges.single[0], ranges.single[1]), 'הרמב"ם');
    });

    test('חוצה-רווחים מודגש כרצף אחד', () {
      const line = 'שמע בני ישראל את הדברים';
      final ranges = computeHighlightRanges(line, '/שמע .* ישראל/');
      expect(ranges, hasLength(1));
      expect(
        line.substring(ranges.single[0], ranges.single[1]),
        'שמע בני ישראל',
      );
    });

    test('רצף מילים ממשיך לשורה הבאה', () {
      expect(
        painted(highLight('ויאמר משה', '/משה רבנו/', nextLine: 'רבנו אל העם')),
        ['משה'],
      );
      expect(
        painted(
          highLight('רבנו אל העם', '/משה רבנו/', previousLine: 'ויאמר משה'),
        ),
        ['רבנו'],
      );
    });

    test('רצף רג\'קס חוצה שורות אינו תלוי באפשרויות ההתאמה', () {
      for (final policy in const [
        SearchMatchPolicy(anyOrder: true),
        SearchMatchPolicy(
          proximityScope: SearchScope.sameSection,
          wordMatchMode: WordMatchMode.anyWord,
        ),
      ]) {
        expect(
          painted(
            highLight(
              'ויאמר משה',
              '/משה רבנו/',
              nextLine: 'רבנו אל העם',
              matchPolicy: policy,
            ),
          ),
          ['משה'],
        );
        expect(
          painted(
            highLight(
              'רבנו אל העם',
              '/משה רבנו/',
              previousLine: 'ויאמר משה',
              matchPolicy: policy,
            ),
          ),
          ['רבנו'],
        );
      }
    });

    test('שאילתה שאינה עטופה אינה מפורשת כרג\'קס', () {
      expect(painted(highLight('ויאמר משה', 'מ.ה')), isEmpty);
    });
  }, skip: engineReady ? false : 'מנוע החיפוש אינו זמין');
}
