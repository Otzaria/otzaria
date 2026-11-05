import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/utils/literal_search_pattern.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text;
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart' as engine;

void main() {
  test('כל התווים השקופים תואמים למתכון הטקסט של המנוע', () {
    const controls = [
      0x200B,
      0x200C,
      0x200D,
      0x200E,
      0x200F,
      0x202A,
      0x202B,
      0x202C,
      0x202D,
      0x202E,
      0x2066,
      0x2067,
      0x2068,
      0x2069,
      0xFEFF,
      0x034F,
      0xFB1E,
    ];
    for (final unit in controls) {
      final c = String.fromCharCode(unit);
      for (final (html, expected) in [
        ('מ$c<sup>נ</sup>שה', 'מנשה'),
        ('מ<sup>$cנ</sup>שה', 'מנשה'),
        ('מ<sup>נ$c</sup>שה', 'מנשה'),
        ('מ<sup>נ</sup>$cשה', 'מנשה'),
        ('מ$c<b>$c<SUB>$c<i>$cנ$cַ$c</i>$c</SUB>$c</b>$cשה', 'מנשה'),
        ('מ$c<sup>נ</sup>$cַשה', 'מנשה'),
        ('מ$c<sup>נ$cש</sup>ה', 'מ נש ה'),
        ('מ$c <sup>נ</sup>$cשה', 'מ נ שה'),
        ('מ$c<sup>נ</sup> $cשה', 'מ נ שה'),
        ('מ$c<br><sup>נ</sup>$cשה', 'מ נ שה'),
        ('מ$c<sup>נ</sup><br>$cשה', 'מ נ שה'),
        ('מ$c<sup><b>נ<br></b></sup>$cשה', 'מ נ שה'),
        ('מ$c<sup class="footnote-marker">נ</sup>$cשה', 'מ שה'),
        ('מ$c<sup>נ</sub>$cשה', 'מ נ שה'),
        ('ַ$c<sup>נ</sup>$cשה', 'נ שה'),
      ]) {
        expect(cleanLineForSearch(html), expected, reason: html);
        final indexed = text.removeSearchInvisibles(
          engine.normalizeTextForIndexing(input: html),
        );
        final searchText = text
            .collapseWhitespace(
              text.removeVolwels(text.stripHtmlForSearch(html)),
            )
            .trim();
        expect(searchText, indexed.trim(), reason: html);
      }
    }
  });

  test('סימני combining נשארים צמודים מעבר לעיצוב ולא מחליפים אות בסיס', () {
    for (final (html, expected) in [
      ('מ\u0307<b><sup>נ\u0307</sup></b>שה', 'מ\u0307נ\u0307שה'),
      ('\u0307<sup>נ</sup>שה', '\u0307 נ שה'),
      ('מ<b><sup>נ</sup></b>ַשה', 'מנַשה'),
      ('מ<sup>נ</sup>', 'מ נ '),
      ('מ<b><sup>נש</sup></b>ה', 'מ נש ה'),
      ('מ<sup><b>נ </b></sup>שה', 'מ נ  שה'),
    ]) {
      expect(text.stripHtmlForSearch(html), expected, reason: html);
    }
  });

  test('גבולות חלקיים וטווחי UTF16 נבדקים בהקשר HTML מלא', () {
    for (final html in [
      '😀 מ<b><sup>נ</sup></b>שה',
      '😀 מ\u200F<sup><b>נ\u034F</b></sup>\u2069שה',
    ]) {
      final ranges = text.computeHighlightRanges(html, 'מנשה');
      expect(ranges, [
        [3, html.length],
      ]);
      final clean = cleanLineForSearch(html);
      for (final query in ['מנשה ', ' מנשה', 'מנ ', ' מנ', 'נש ', ' נש']) {
        final found = buildLiteralPattern(
          query,
          wholeWord: false,
        )!.regExp.hasMatch(clean);
        expect(
          text.countMatches(html, query, partialWordMatch: true) > 0,
          found,
          reason: '$query: $html',
        );
      }
    }
    const numeric = 'תורה<sup>30</sup>המשך';
    expect(text.countMatches(numeric, 'תורה ', partialWordMatch: true), 1);
  });

  test('BOM שקוף במילה ובשאילתה, כמו יתר תווי הכיווניות', () async {
    expect(normalizeLiteralQuery('מ\uFEFFנשה'), 'מנשה');
    final found = await searchInContent(
      content: ['מנשה', 'מ\uFEFFנשה'],
      query: 'מ\uFEFFנשה',
    );
    expect(found.map((r) => r.index), [0, 1]);
  });

  test('הדגשת sup/sub שומרת על האות התלויה ועל עיצוב המספר התחתי', () {
    for (final html in [
      'מְ<sup>נַ</sup>שֶּׁה',
      'מ<b><sup>נ</sup></b>שה',
      'מ<sub>נ</sub>שה',
    ]) {
      final rendered = TextRendererService.processText(
        html,
        const RenderSettings(searchText: 'מנשה', formatParentheses: false),
      );
      expect(rendered, contains('color: otzaria-search-hit'), reason: html);
      expect(
        text.removeSearchInvisibles(
          text.removeVolwels(text.stripHtmlIfNeeded(rendered)),
        ),
        'מנשה',
      );
    }
    final sub = TextRendererService.processText(
      'א<sub>30</sub>ב',
      const RenderSettings(searchText: '30', formatParentheses: false),
    );
    expect(sub, contains('color: otzaria-search-hit'));
    expect(text.removeSearchInvisibles(text.stripHtmlIfNeeded(sub)), 'א₃₀ב');
    expect(
      TextRendererService.processText(
        'א<sub> 30 </sub>ב',
        const RenderSettings(formatParentheses: false),
      ),
      'א\u2066₃₀\u2069ב',
    );
  });

  test('המנוע המקובע דורש סכמה 10', () async {
    final root = Directory.systemTemp.createTempSync('script_schema_');
    addTearDown(() => root.deleteSync(recursive: true));
    final compatibility = await engine.checkIndexCompatibility(path: root.path);
    expect(compatibility.requiredSchemaVersion, 10);
  });
}
