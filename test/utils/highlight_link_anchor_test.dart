import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

import '../support/search_engine_test_init.dart';

const _marker =
    '<a class="link-anchor link-anchor-0" '
    'href="otzaria://anchor?ref=3_0">(א)</a>';

const _markStart = '<span style="background-color: otzaria-mark';

List<String> _painted(String html) => [
  for (final match in RegExp(
    r'<span style="color: otzaria-search-hit">([^<]*)</span>',
  ).allMatches(html))
    match.group(1)!,
];

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  group(
    'קישור עם הדגשת טקסט עובד עם ציוני מפרשים מוצגים ומוסתרים (issue #5745)',
    () {
      test('ציונים מוסתרים: הטקסט מהמקור מודגש', () {
        final result = highLight(
          'ויברך את יעקב ויאמר לו',
          'את יעקב ויאמר',
          yellowBackground: true,
        );
        expect(result, contains(_markStart));
      });

      test('ציונים מוצגים: הטווח שחוצה ציון מודגש, והציון נשאר שלם ויחיד', () {
        const line = 'ויברך את יעקב$_marker ויאמר לו';
        final result = highLight(
          line,
          'את יעקב ויאמר',
          yellowBackground: true,
        );
        expect(result, contains(_markStart));
        expect(result.split(_marker), hasLength(2));
        expect(
          result.replaceAll(RegExp(r'<span style="[^"]*">|</span>'), ''),
          line,
        );
      });

      test('ציון בתוך מילה לא מפריד אותה', () {
        const line =
            'ויברך את יע$_marker'
            'קב ויאמר לו';
        final result = highLight(
          line,
          'את יעקב ויאמר',
          yellowBackground: true,
        );
        expect(result, contains(_markStart));
        expect(result.split(_marker), hasLength(2));
      });

      test('ציון בתוך span (בלי lineIndex) מדולג גם הוא', () {
        const line =
            'ויברך את יעקב<span class="link-anchor link-anchor-2">[ב]</span>'
            ' ויאמר לו';
        final result = highLight(
          line,
          'את יעקב ויאמר',
          yellowBackground: true,
        );
        expect(result, contains(_markStart));
      });

      test('ציטוט לינקר (link-anchor-range) נשאר חלק מהטקסט', () {
        const line =
            'ויברך <a class="link-anchor-range" href="x">את יעקב</a> ויאמר';
        final result = highLight(
          line,
          'את יעקב ויאמר',
          yellowBackground: true,
        );
        expect(result, contains(_markStart));
      });

      test('תגי span בתוך ציון נשארים חלק מהציון', () {
        const nested = '<span class="link-anchor">(<span>א</span> ב)</span>';
        const line = 'ויאמר מש$nestedה רבנו';
        final result = highLight(line, 'משה רבנו');
        expect(_painted(result), ['מש', 'ה', 'רבנו']);
        expect(result.split(nested), hasLength(2));
      });

      test('ציון שלא נסגר אינו מסתיר span של הטקסט', () {
        const line = 'אמר <span class="link-anchor">(א) <span>משה</span> רבנו';
        expect(_painted(highLight(line, 'משה רבנו')), ['משה', 'רבנו']);
      });

      test('שם המחלקה בתוך ערך של מאפיין אחר אינו ציון', () {
        const line =
            '''<span title='example class="link-anchor"'>משה</span> רבנו''';
        expect(_painted(highLight(line, 'משה רבנו')), ['משה', 'רבנו']);
      });

      test('הדגשת חיפוש מדלגת על אות הציון', () {
        const line = 'ויברך את יעקב$_marker ויאמר לו';
        final result = highLight(line, 'יעקב ויאמר');
        expect(result, contains('otzaria-search-hit'));
        expect(result.split(_marker), hasLength(2));
      });

      test('פיסוק נבדק בטקסט המקור גם כשציון קודם לו', () {
        const line = 'ויברך יעקב$_marker, ויאמר לו';
        const query = 'יעקב, ויאמר';
        final start = 'ויברך '.length;
        final result = highLight(line, query, partialWordMatch: true);
        expect(_painted(result), ['יעקב', 'ויאמר']);
        expect(result.split(_marker), hasLength(2));
        expect(countMatches(line, query, partialWordMatch: true), 1);
        expect(searchMatchRangeAt(line, query, 0, partialWordMatch: true), (
          start: start,
          end: line.indexOf(' לו'),
          totalCount: 1,
        ));
        final ranges = computeHighlightRanges(
          line,
          query,
          partialWordMatch: true,
        );
        expect(
          [for (final range in ranges) line.substring(range[0], range[1])],
          ['יעקב', 'ויאמר'],
        );
      });

      test('ציון באמצע מילה אינו גבול מילה לשאילתה עם רווח בקצה', () {
        const line = 'ויאמר מש$_markerהו';
        const query = 'מש ';
        expect(_painted(highLight(line, 'מש', partialWordMatch: true)), ['מש']);
        expect(highLight(line, query, partialWordMatch: true), line);
        expect(countMatches(line, query, partialWordMatch: true), 0);
        expect(
          computeHighlightRanges(line, query, partialWordMatch: true),
          isEmpty,
        );
      });

      test('הדגשה חוצה שורות מדלגת על ציונים בשני צדי המעבר', () {
        const first = 'ויאמר מש$_markerה {פ}';
        const second = '(ג) רב$_markerנו אל העם';
        for (final query in ['משה רבנו', '/משה רבנו/']) {
          final left = highLight(first, query, nextLine: second);
          final right = highLight(second, query, previousLine: first);
          expect(_painted(left), ['מש', 'ה']);
          expect(_painted(right), ['רב', 'נו']);
          expect(left.split(_marker), hasLength(2));
          expect(right.split(_marker), hasLength(2));
        }
      });
    },
    skip: engineReady
        ? false
        : 'ספריית מנוע החיפוש הנייטיבית לא נמצאה — הריצו cargo build בחבילה',
  );
}
