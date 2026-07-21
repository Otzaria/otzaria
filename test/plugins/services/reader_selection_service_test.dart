import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';
import 'package:otzaria/plugins/services/text_source_map_service.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

void main() {
  const service = ReaderSelectionService();

  test('locates repeated text only inside the requested rendered section', () {
    final range = service.locateRenderedRange(
      renderedText: 'פתיחה מילה בתוך המקטע',
      selectedText: 'מילה',
    );

    expect(range, isNotNull);
    expect(range!.start, 6);
    expect(range.end, 10);
  });

  test('pointer hint selects the second occurrence in the same section', () {
    final range = service.locateRenderedRange(
      renderedText: 'מילה באמצע מילה',
      selectedText: 'מילה',
      startHint: 13,
    );

    expect(range, isNotNull);
    expect(range!.start, 11);
    expect(range.end, 15);
  });

  test('maps a displayed holy-name replacement back to the source', () {
    const settings = RenderSettings(
      replaceHolyNames: true,
      formatParentheses: false,
    );
    const rawText = 'לפני יהוה אחרי';
    final map = const TextSourceMapService().build(
      bookId: 'book',
      sectionIndex: 8,
      rawText: rawText,
      settings: settings,
    );
    final displayedName = map.renderedText.substring(
      'לפני '.length,
      map.renderedText.length - ' אחרי'.length,
    );
    final range = service.locateRenderedRange(
      renderedText: map.renderedText,
      selectedText: displayedName,
    );
    final resolvedRange = range!;
    final selection = service.build(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 8,
      rawText: rawText,
      settings: settings,
      renderedStartUtf16: resolvedRange.start,
      renderedEndUtf16: resolvedRange.end,
    );

    expect(displayedName, isNot('יהוה'));
    expect(selection, isNotNull);
    expect(selection!.sourceSelectedText, 'יהוה');
    expect(selection.sourceRange.start.utf16, 'לפני '.length);
  });

  test('בונה עוגן source חד-משמעי למופע השני של אותה מילה', () {
    final selection = service.build(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 4,
      rawText: 'אני אומר שאני יודע',
      settings: const RenderSettings(formatParentheses: false),
      renderedStartUtf16: 10,
      renderedEndUtf16: 13,
      currentRef: 'פרק א',
      createdAt: DateTime.utc(2026, 7, 14),
    );

    expect(selection, isNotNull);
    expect(selection!.sourceSelectedText, 'אני');
    expect(selection.sourceRange.start.grapheme, 10);
    expect(selection.sourceRange.occurrenceIndexInSection, 1);
    expect(selection.sourceRange.occurrenceCountInSection, 2);
    expect(selection.sourceRange.beforeText.raw, 'אני אומר ש');
  });

  test('מתרגם בחירה ללא ניקוד בחזרה לטווח המקור המנוקד', () {
    final selection = service.build(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 0,
      rawText: 'אָב אמר',
      settings: const RenderSettings(
        removeNikud: true,
        removeTeamim: false,
        formatParentheses: false,
      ),
      renderedStartUtf16: 0,
      renderedEndUtf16: 2,
    );

    expect(selection, isNotNull);
    expect(selection!.renderedSelectedText, 'אב');
    expect(selection.sourceSelectedText, 'אָב');
    expect(selection.sourceRange.start.grapheme, 0);
    expect(selection.sourceRange.end.grapheme, 2);
  });

  test('דוחה offset שנופל באמצע surrogate pair', () {
    final selection = service.build(
      bookId: 'book',
      bookTitle: 'ספר',
      sectionIndex: 0,
      rawText: 'א😀ב',
      settings: const RenderSettings(formatParentheses: false),
      renderedStartUtf16: 1,
      renderedEndUtf16: 2,
    );

    expect(selection, isNull);
  });
}
