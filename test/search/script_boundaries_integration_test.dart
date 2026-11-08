import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text;
import 'package:otzaria/text_book/utils/section_search_utils.dart';
import 'package:otzaria/search/utils/literal_search_pattern.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';
import 'package:otzaria/personal_notes/utils/personal_note_source_selection.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

void main() {
  for (final html in [
    'מ<b><sup>נ</sup></b>שה',
    'מ<sup>נ</sup><b>שה</b>',
    'מ<sup><b>נ</b></sup>שה',
    'מ\u200F<sup>נ</sup>שה',
    'מ<sup>\u200Fנ</sup>שה',
    'מ<sup>נ</sup>\u200Fשה',
    'מ<sup>\u034Fנ</sup>שה',
    'מ<sup>נ</sup>ַשה',
  ]) {
    test('אות תלויה בחיפוש: $html', () {
      expect(cleanLineForSearch(html), 'מנשה');
      expect(
        buildLiteralPattern('מנשה')!.regExp.hasMatch(cleanLineForSearch(html)),
        isTrue,
      );
    });
  }

  test('סימן ללא אות קודמת אינו מצרף אות תלויה', () {
    expect(cleanLineForSearch('ַ<sup>נ</sup>שה'), 'נ שה');
  });

  test('בחירה החוצה sup נשארת מעוגנת דרך מפת המקור', () {
    const raw = 'ראש גוף<sup>1</sup>המשך סוף';
    const settings = RenderSettings(formatParentheses: false);
    final displayed = TextRendererService.stripHtml(
      TextRendererService.processText(raw, settings),
    );
    final selected = mapPersonalNoteSourceSelection(
      bookId: 'review',
      lineIndex: 0,
      rawLine: raw,
      settings: settings,
      selectedText: displayed,
    );
    expect(selected, isNotNull);
    final anchor = computeAnchorForSelection(
      rawLine: raw,
      selectedText: selected!.text,
      sourceSelectionOffset: selected.offset,
      sourceSelectionText: text.stripHtmlIfNeeded(raw),
      selectionColumnHint: 0,
    );
    expect(anchor, isNotNull);
    expect(
      locateAnchor(rawLine: raw, anchorText: 'ראש גוף1המשך סוף'),
      isNotNull,
    );
  });

  test('היסט מקור מדויק בוחר במופע השני ליד sup', () {
    const raw = 'גוף<sup>1</sup>המשך ואז גוף<sup>1</sup>המשך';
    final source = text.stripHtmlIfNeeded(raw);
    final anchor = computeAnchorForSelection(
      rawLine: raw,
      selectedText: 'המשך',
      sourceSelectionOffset: source.lastIndexOf('המשך'),
      sourceSelectionText: source,
    );
    expect(anchor?.start, raw.lastIndexOf('המשך'));
  });

  test('רינדור מדגיש מילה הגובלת ב-sup לפני המרתו', () {
    const raw = 'תורה<sup>30</sup>המשך';
    final highlighted = TextRendererService.processText(
      raw,
      const RenderSettings(formatParentheses: false, searchText: 'תורה'),
    );
    expect(highlighted, contains('color: otzaria-search-hit'));
  });

  test('חיפוש ב-worker מוצא אות תלויה מעוצבת', () async {
    final results = await searchInContent(
      content: ['מ<b><sup>נ</sup></b>שה'],
      query: 'מנשה',
    );
    expect(results, hasLength(1));
  });
  test('גבולות sup נשמרים גם בחיפוש בגוף הערת שוליים', () {
    const line =
        'גוף<sup class="footnote-marker">א</sup>'
        '<i class="footnote">רישא<sup>30</sup>סיפא</i> המשך';
    expect(queryMatchesInlineNoteOnly(line, 'רישא'), isTrue);
    expect(queryMatchesInlineNoteOnly(line, 'סיפא'), isTrue);
    expect(queryMatchesInlineNoteOnly(line, 'גוף'), isFalse);
  });
}
