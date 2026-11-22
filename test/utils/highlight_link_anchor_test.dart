import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

import '../support/search_engine_test_init.dart';

const _marker =
    '<a class="link-anchor link-anchor-0" '
    'href="otzaria://anchor?ref=3_0">(א)</a>';

const _markStart = '<span style="background-color: otzaria-mark';

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

      test('הדגשת חיפוש מדלגת על אות הציון', () {
        const line = 'ויברך את יעקב$_marker ויאמר לו';
        final result = highLight(line, 'יעקב ויאמר');
        expect(result, contains('otzaria-search-hit'));
        expect(result.split(_marker), hasLength(2));
      });
    },
    skip: engineReady
        ? false
        : 'ספריית מנוע החיפוש הנייטיבית לא נמצאה — הריצו cargo build בחבילה',
  );
}
