import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SearchScope, WordMatchMode;

import '../support/search_engine_test_init.dart';

/// הדגשה במדיניות התאמה שאינה ברירת המחדל ("באותה פסקה", "תחת אותה כותרת",
/// התאמה חלקית של מילות השאילתה).
///
/// שם המנוע מחזיר שורות שהמילים בהן מפוזרות או חסרות, ולכן תבנית ההתאמה
/// המשולבת (כל המילים בתוך המרווח) פסלה בדיוק את מה שהוא החזיר. ההכרעה מי
/// תוצאה נשארת אצל המנוע: מדגישים מילה-מילה, ורק בשורות שהוא החזיר.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  group(
    'הדגשה לפי מדיניות ההתאמה',
    () {
      const farApart = 'תדע אחת שתים שלוש ארבע חמש שש שבע זרעך';
      const onlyOneWord = 'ויאמר לאברם ידע תדע כי גר יהיה';
      const sameParagraph = SearchMatchPolicy(
        proximityScope: SearchScope.sameParagraph,
      );
      const sameSection = SearchMatchPolicy(
        proximityScope: SearchScope.sameSection,
      );

      test('ברירת המחדל: מילים רחוקות אינן מודגשות', () {
        expect(
          computeHighlightRanges(farApart, 'תדע זרעך', searchDistance: 2),
          isEmpty,
        );
      });

      test('שורה שהמנוע החזיר: כל מילת שאילתה מודגשת בנפרד', () {
        final ranges = computeHighlightRanges(
          farApart,
          'תדע זרעך',
          searchDistance: 2,
          matchPolicy: sameParagraph,
          isSearchResultLine: true,
        );
        expect(
          [for (final range in ranges) farApart.substring(range[0], range[1])],
          ['תדע', 'זרעך'],
        );
      });

      test('שורה שהמנוע לא החזיר אינה מודגשת בכלל', () {
        // מונע את הצד ההפוך של הבאג: הדגשה בשורה שאינה תוצאה.
        expect(
          computeHighlightRanges(
            farApart,
            'תדע זרעך',
            searchDistance: 2,
            matchPolicy: sameParagraph,
          ),
          isEmpty,
        );
      });

      test('"תחת אותה כותרת": שורת תוצאה עם מילה אחת מודגשת', () {
        // חוזה המנוע (word_match_same_section_counts_distinct_words_per_section):
        // בסעיף שעבר את הסף חוזרות כל השורות שנושאות מילת שאילתה — גם שורה
        // שנושאת רק אחת מהן. הסף מחושב על הסעיף, ולכן האפליקציה אינה מנסה
        // לחשב אותו מחדש פר-שורה.
        final ranges = computeHighlightRanges(
          onlyOneWord,
          'תדע זרעך',
          matchPolicy: sameSection,
          isSearchResultLine: true,
        );
        expect(
          [
            for (final range in ranges)
              onlyOneWord.substring(range[0], range[1]),
          ],
          ['תדע'],
        );
      });

      test('אותן מילים בשורה שאינה תוצאה — אין הדגשה', () {
        expect(
          computeHighlightRanges(
            onlyOneWord,
            'תדע זרעך',
            matchPolicy: sameSection,
          ),
          isEmpty,
        );
      });

      test('מילה כפולה בשאילתה אינה משנה את ההכרעה — היא של המנוע', () {
        // חוזה המנוע (duplicate_query_words_count_once_toward_the_threshold):
        // מילים ייחודיות נספרות פעם אחת. האפליקציה לא סופרת בכלל: שורה שלא
        // חזרה מהמנוע אינה מודגשת, ושורה שחזרה — מודגשת במילים שנמצאו בה.
        const policy = SearchMatchPolicy(
          wordMatchMode: WordMatchMode.atLeast,
          wordMatchCount: 2,
        );
        expect(
          computeHighlightRanges(
            onlyOneWord,
            'תדע תדע זרעך',
            matchPolicy: policy,
          ),
          isEmpty,
        );
        expect(
          computeHighlightRanges(
            onlyOneWord,
            'תדע תדע זרעך',
            matchPolicy: policy,
            isSearchResultLine: true,
          ),
          isNotEmpty,
        );
      });

      test(
        'הדגשת HTML: שורת תוצאה מסמנת כל מילה, שורה אחרת נשארת כפי שהיא',
        () {
          final marked = highLight(
            farApart,
            'תדע זרעך',
            matchPolicy: sameParagraph,
            isSearchResultLine: true,
          );
          expect(marked, contains('<span style="color: red">תדע</span>'));
          expect(marked, contains('<span style="color: red">זרעך</span>'));
          // המילים שבין מילות השאילתה נשארות בלי הדגשה.
          expect(marked, isNot(contains('<span style="color: red">שלוש')));

          expect(
            highLight(farApart, 'תדע זרעך', matchPolicy: sameParagraph),
            farApart,
          );
        },
      );

      test('גבולות מילה נשמרים גם בהדגשה לפי מילה', () {
        // "אמר" בתוך "ויאמר" אינו טוקן שלם ולכן אינו מודגש.
        final ranges = computeHighlightRanges(
          'ויאמר משה זרעך',
          'אמר זרעך',
          matchPolicy: const SearchMatchPolicy(
            wordMatchMode: WordMatchMode.anyWord,
          ),
          isSearchResultLine: true,
        );
        expect(
          [
            for (final range in ranges)
              'ויאמר משה זרעך'.substring(range[0], range[1]),
          ],
          ['זרעך'],
        );
      });

      test('אין הדגשה כשאף מילה מהשאילתה אינה בטקסט', () {
        expect(
          computeHighlightRanges(
            'שורה אחרת לגמרי',
            'תדע זרעך',
            matchPolicy: sameParagraph,
            isSearchResultLine: true,
          ),
          isEmpty,
        );
      });

      test('חיפוש מקורב: מילים מפוזרות בשורת תוצאה מודגשות כל אחת', () {
        // המנוע מחפש במקורב כל מילה בנפרד בשורה, בלי סדר ובלי מרווח.
        final ranges = computeHighlightRanges(
          farApart,
          'תדע זרעך',
          isFuzzy: true,
          isSearchResultLine: true,
        );
        expect(
          [for (final range in ranges) farApart.substring(range[0], range[1])],
          ['תדע', 'זרעך'],
        );
        expect(
          computeHighlightRanges(farApart, 'תדע זרעך', isFuzzy: true),
          isEmpty,
        );
      });

      test('חיפוש מקורב: כשהביטוי רציף בשורה — רק הוא מודגש', () {
        const line = 'תדע אחת תדע זרעך שתים זרעך';
        final ranges = computeHighlightRanges(
          line,
          'תדע זרעך',
          isFuzzy: true,
          isSearchResultLine: true,
        );
        expect(ranges, [
          [8, 11],
          [12, 16],
        ]);
      });

      test('הדגל אינו משנה דבר בברירת המחדל — התבנית המשולבת מכריעה', () {
        const line = 'ידע תדע כי גר יהיה זרעך';
        expect(
          computeHighlightRanges(line, 'תדע זרעך', searchDistance: 3),
          computeHighlightRanges(
            line,
            'תדע זרעך',
            searchDistance: 3,
            isSearchResultLine: true,
          ),
        );
      });
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );
}
