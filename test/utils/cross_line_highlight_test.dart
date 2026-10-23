import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/utils/cross_line_result.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

import '../support/search_engine_test_init.dart';

/// ביטוי שהמנוע מצא במעבר משורה לשורה (issue #1703): כל שורה מודגשת בחלק
/// שלה, בעזרת השורה הסמוכה.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  const first = 'ויבדל בין המים אשר מתחת לרקיע ובין המים';
  const second = '(ג) ויאמר אלהים יקוו המים';
  const query = 'ובין המים ויאמר אלהים';

  List<String> painted(String html) => [
    for (final match in RegExp(
      r'<span style="color: red">([^<]*)</span>',
    ).allMatches(html))
      match.group(1)!,
  ];

  group('רווח בקצה בהתאמה חלקית נבדק בטקסט המחובר (#2679)', () {
    const top = 'ויאמר בשל';
    const bottom = 'הבית הזה';

    test('רווח בסוף: סוף המילה בשורה הבאה', () {
      expect(
        painted(
          highLight(top, 'של ה ', nextLine: bottom, partialWordMatch: true),
        ),
        isEmpty,
      );
      expect(
        painted(
          highLight(top, 'של ה', nextLine: bottom, partialWordMatch: true),
        ),
        ['של'],
      );
    });

    test('רווח בהתחלה: תחילת המילה בשורה הקודמת', () {
      expect(
        painted(
          highLight(bottom, ' של ה', previousLine: top, partialWordMatch: true),
        ),
        isEmpty,
      );
      expect(
        painted(
          highLight(bottom, 'של ה', previousLine: top, partialWordMatch: true),
        ),
        ['ה'],
      );
    });
  }, skip: engineReady ? false : searchEngineSkipReason);

  group('הדגשה במעבר בין שורות', () {
    test('בלי השורה הסמוכה אין הדגשה', () {
      expect(painted(highLight(first, query)), isEmpty);
      expect(painted(highLight(second, query)), isEmpty);
    });

    test('השורה הראשונה מדגישה את סופה', () {
      expect(painted(highLight(first, query, nextLine: second)), [
        'ובין',
        'המים',
      ]);
    });

    test('השורה השנייה מדגישה את תחילתה, אחרי הסימון הממוספר', () {
      expect(painted(highLight(second, query, previousLine: first)), [
        'ויאמר',
        'אלהים',
      ]);
    });

    test('ביטוי שאינו חוצה את המעבר אינו מודגש דרכו', () {
      expect(
        painted(highLight(first, 'יקוו המים', nextLine: second)),
        isEmpty,
      );
    });

    test('מילה בודדת מודגשת זהה עם השורות הסמוכות ובלעדיהן', () {
      const line = 'אמר רבי יוחנן המים של מעלה';
      expect(
        highLight(line, 'המים', previousLine: first, nextLine: second),
        highLight(line, 'המים'),
      );
    });

    test('מילה בודדת אינה סורקת את השורות הסמוכות', () {
      const line = 'אמר רבי יוחנן המים של מעלה';
      final neighbour = List.filled(20000, 'של המים').join(' ');
      int elapsedMicros({required bool withNeighbours}) {
        final watch = Stopwatch()..start();
        for (var i = 0; i < 5; i++) {
          highLight(
            line,
            'המים',
            previousLine: withNeighbours ? neighbour : null,
            nextLine: withNeighbours ? neighbour : null,
          );
        }
        return watch.elapsedMicroseconds;
      }

      elapsedMicros(withNeighbours: false);
      final alone = elapsedMicros(withNeighbours: false);
      final withNeighbours = elapsedMicros(withNeighbours: true);
      expect(withNeighbours, lessThan(alone * 10 + 20000));
    });
  }, skip: engineReady ? false : 'מנוע החיפוש אינו זמין');

  group('גבולות התוכן לחיבור שורות', () {
    test('סימון ממוספר בתחילה ובסוף אינו חלק מהתוכן', () {
      const line = '(ג) ויהי כן {פ}';
      final range = crossLineContentRange(line);
      expect(line.substring(range.start, range.end), 'ויהי כן');
    });

    test('תגי HTML סביב הסימון אינם מפריעים', () {
      const line = '<b>(יא)</b> דבר אחר (ב):</p>';
      final range = crossLineContentRange(line);
      expect(line.substring(range.start, range.end), 'דבר אחר');
    });

    test('סוגריים עם מילים רבות אינם סימון', () {
      const line = '(שם הספר) דבר';
      final range = crossLineContentRange(line);
      expect(line.substring(range.start, range.end), line);
    });

    test('שורות התוצאה כוללות את השורה הבאה רק כשהביטוי נמשך', () {
      expect(searchResultLinesFor(4, continuesToNextLine: false), {4});
      expect(searchResultLinesFor(4, continuesToNextLine: true), {4, 5});
    });
  });
}
