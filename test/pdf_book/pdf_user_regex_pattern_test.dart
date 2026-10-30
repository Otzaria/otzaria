import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_user_regex_pattern.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/search_engine_test_init.dart';

/// `/…/` בשכבת הטקסט של PDF: המתאם של המנוע, בהיסטים של טקסט העמוד.
Future<void> main() async {
  final ready = await tryInitSearchEngine();

  PdfPageText page(String text) => PdfPageText(
    pageNumber: 1,
    fullText: text,
    charRects: List.filled(text.length, const PdfRect(0, 1, 1, 0)),
    fragments: const [],
  );

  group('PdfUserRegexPattern', () {
    test('רק `/…/` שהמנוע מקבל', () {
      expect(PdfUserRegexPattern.tryParse(' /מש.ה/ '), isNotNull);
      for (final raw in ['מש.ה', '/(/', '/שמע']) {
        expect(PdfUserRegexPattern.tryParse(raw), isNull, reason: raw);
      }
    });

    test('חוצה-רווחים: היסטים בטקסט העמוד, ניקוד ומעבר שורה נשמרים', () {
      const text = 'אמר < & שְׁמַע בני ישראל\nשמע';
      final pattern = PdfUserRegexPattern.tryParse(r'/שמע \S+ ישראל/')!;
      final matches = pattern.allMatches(text).toList();
      expect(matches, hasLength(1));
      expect(matches.single.group(0), 'שְׁמַע בני ישראל');
      expect(pattern.allMatches(text, 10).toList(), isEmpty);
    });

    test('< ו-& בתבנית מוצאים את התווים עצמם בטקסט העמוד', () {
      const text = 'אמר א&ב ו-ג<ד';
      // מונח בודד אינו מכיל `&`/`<` (אינם אותיות) — רק תבנית חוצת-רווחים.
      for (final (raw, found) in [
        (r'/א&ב\s*/', 'א&ב'),
        (r'/א\&ב\W*/', 'א&ב'),
        (r'/א[&]ב\W*/', 'א&ב'),
        (r'/ו-ג<ד\s*/', 'ו-ג<ד'),
        (r'/(?P<x>ו)-ג<ד\s*/', 'ו-ג<ד'),
      ]) {
        final pattern = PdfUserRegexPattern.tryParse(raw);
        expect(pattern, isNotNull, reason: raw);
        expect(
          pattern!.allMatches(text).map((m) => m.group(0)),
          [found],
          reason: raw,
        );
      }
    });

    test('^ ו-\$ מעוגנים לשורת הטקסט, לא לעמוד', () {
      const text = 'ויאמר משה\nויאמר אהרן\r\nאמר משה';
      List<String?> found(String raw, [int start = 0]) =>
          PdfUserRegexPattern.tryParse(
            raw,
          )!.allMatches(text, start).map((m) => m.group(0)).toList();
      expect(found('/^ויאמר/'), ['ויאמר', 'ויאמר']);
      expect(found(r'/משה$/'), ['משה', 'משה']);
      expect(found(r'/^ויאמר \S+$/'), ['ויאמר משה', 'ויאמר אהרן']);
      // היסט באמצע שורה אינו תחילת שורה.
      expect(found('/^משה/', 6), isEmpty);
      expect(found('/^ויאמר/', 6), ['ויאמר']);
      expect(
        PdfUserRegexPattern.tryParse('/^ויאמר/')!.matchAsPrefix(text, 10),
        isNotNull,
      );
    });

    test('מילה: מילים שלמות בלבד', () {
      final pattern = PdfUserRegexPattern.tryParse('/מ.ה/')!;
      expect(
        pattern.allMatches('ויאמר משה ומשה').map((m) => m.group(0)),
        ['משה'],
      );
    });

    test('pdfrx מקבל את התבנית ומחזיר טווחים בעמוד', () async {
      const text = 'אמר שמע בני ישראל';
      final ranges = await page(
        text,
      ).allMatches(PdfUserRegexPattern.tryParse(r'/שמע \S+ ישראל/')!).toList();
      expect(ranges.map((r) => (r.start, r.end)), [(4, text.length)]);
    });
  }, skip: ready ? false : searchEngineSkipReason);
}
