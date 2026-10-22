import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/marker/services/marker_selection.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

void main() {
  const settings = RenderSettings(formatParentheses: false);

  TextBookLoaded state(
    List<String> lines, {
    BookProtection protection = BookProtection.none,
  }) => TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה', id: 7),
    showLeftPane: false,
    content: lines,
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: null,
    pinLeftPane: false,
    searchText: '',
    protection: protection,
  );

  test('a selection in one paragraph is anchored in the source text', () {
    const lines = ['<b>שלום</b> עולם ומלואו', 'שורה שנייה'];
    final draft = markerDraftFromSelection(
      state: state(lines),
      lines: lines,
      paragraphIndex: 0,
      selectedText: 'עולם',
      anchor: (lineStart: 0, lineEnd: 0, startColumn: 5, pointerColumn: null),
      settings: settings,
    )!;
    final segment = draft.segments.single;
    expect(segment.sectionIndex, 0);
    expect(segment.range.exactText, 'עולם');
    expect(segment.start, 'שלום '.length);
    expect(draft.bookUid, isNotEmpty);
  });

  test('the start column picks the right occurrence of a repeated word', () {
    const lines = ['אלף בית אלף גימל'];
    final draft = markerDraftFromSelection(
      state: state(lines),
      lines: lines,
      paragraphIndex: 0,
      selectedText: 'אלף',
      anchor: (lineStart: 0, lineEnd: 0, startColumn: 8, pointerColumn: null),
      settings: settings,
    )!;
    expect(draft.segments.single.start, 8);
    expect(draft.segments.single.range.occurrenceIndexInSection, 1);
  });

  test('a selection across paragraphs gets one segment per paragraph', () {
    const lines = ['ראשונה אחת', 'שנייה שתיים', 'שלישית'];
    final draft = markerDraftFromSelection(
      state: state(lines),
      lines: lines,
      paragraphIndex: 1,
      selectedText: 'אחת\nשנייה שתיים\nשלישית',
      anchor: (lineStart: 0, lineEnd: 2, startColumn: 7, pointerColumn: null),
      settings: settings,
    )!;
    expect(draft.segments.map((s) => s.sectionIndex), [0, 1, 2]);
    expect(draft.segments.map((s) => s.range.exactText), [
      'אחת',
      'שנייה שתיים',
      'שלישית',
    ]);
  });

  test('a selection hidden niqqud maps to the voweled source', () {
    const lines = ['בְּרֵאשִׁית בָּרָא אֱלֹהִים'];
    final draft = markerDraftFromSelection(
      state: state(lines),
      lines: lines,
      paragraphIndex: 0,
      selectedText: 'ברא',
      anchor: (lineStart: 0, lineEnd: 0, startColumn: null, pointerColumn: 8),
      settings: const RenderSettings(
        formatParentheses: false,
        removeNikud: true,
      ),
    )!;
    expect(draft.segments.single.range.exactText, 'בָּרָא');
  });

  test('text that is not in the paragraph is not marked', () {
    const lines = ['שלום עולם'];
    expect(
      markerDraftFromSelection(
        state: state(lines),
        lines: lines,
        paragraphIndex: 0,
        selectedText: 'לא קיים',
        anchor: (
          lineStart: 0,
          lineEnd: 0,
          startColumn: null,
          pointerColumn: null,
        ),
        settings: settings,
      ),
      isNull,
    );
  });
}
