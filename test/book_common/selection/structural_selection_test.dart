import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/personal_notes/utils/personal_note_source_selection.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/utils/inline_section_markers.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

void main() {
  const raw = '  אָמַר רבי <b>יוחנן</b>';
  final html = prependSectionMarker(raw, 'סעיף א');
  const settings = RenderSettings(removeNikud: true);
  SelectionLine line(String value) => renderSelectionLineWithMarkers(
    rawText: value,
    settings: settings,
  );

  test('טווח מבני כולל את הרווח המוזרק והרינדור תואם לתצוגה', () {
    final rendered = line(html);
    expect(
      rendered.text,
      renderSelectionLine(rawText: html, settings: settings),
    );
    expect(rendered.text, '[סעיף א] אמר רבי יוחנן');
    expect(rendered.structural, [(0, '[סעיף א] '.length)]);
    expect(rendered.markers, isEmpty);
  });

  for (final selected in [
    '[סעיף א] אמר רבי יוחנן',
    'סעיף א] אמר רבי יוחנן',
    'א] אמר רבי יוחנן',
    '] אמר רבי יוחנן',
    ' אמר רבי יוחנן',
    'אמר רבי יוחנן',
    'רבי יוחנן',
    '[סעיף א]',
    'סעיף',
  ]) {
    test('בחירה "$selected" ממופה למקור בלי התחילית והרווח שלה', () {
      final rendered = line(html);
      final column = rendered.text.indexOf(selected);
      final selection = SourceSelection.strip(
        shownText: selected,
        lines: [rendered],
        startColumn: column,
      );
      final source = SourceSelection.resolve(selection, selected, column);
      final expected = selected.contains('אמר')
          ? 'אמר רבי יוחנן'
          : selected == 'רבי יוחנן'
          ? selected
          : '';
      expect(source.text, expected);
      expect(source.column, selected == 'רבי יוחנן' ? 4 : 0);
      expect(SourceSelection.forCopy(selection, selected), selected);
      if (expected.isNotEmpty) {
        final note = mapPersonalNoteSourceSelection(
          bookId: 'ספר',
          lineIndex: 1,
          rawLine: raw,
          settings: settings,
          selectedText: source.text,
          startHint: source.column,
        );
        expect(note, isNotNull);
        expect(
          note!.text,
          selected == 'רבי יוחנן' ? 'רבי יוחנן' : 'אָמַר רבי יוחנן',
        );
        expect(
          note.offset,
          raw.indexOf(selected == 'רבי יוחנן' ? 'רבי' : 'אָ'),
        );
      }
    });
  }

  test('שתי שורות מסירות כל תחילית ושומרות את מעבר השורה', () {
    final lines = [
      line(html),
      line(prependSectionMarker('שלום עולם', 'סעיף ב')),
    ];
    final shown = '${lines.first.text}\n${lines.last.text}';
    final restored = restoreSelectedTextLineBreaksDetailed(
      selectedText: shown,
      visibleLines: lines.map((l) => l.text).toList(),
    );
    expect(restored.startLine, 0);
    expect(restored.endLine, 1);
    final selection = SourceSelection.strip(
      shownText: restored.text,
      lines: lines,
      startColumn: restored.startColumn!,
    );
    expect(SourceSelection.resolve(selection, restored.text, 0), (
      text: 'אמר רבי יוחנן\nשלום עולם',
      column: 0,
    ));
    expect(SourceSelection.forCopy(selection, restored.text), shown);
  });

  test('פרופיל שמסתיר ציוני קישורים שומר סמן מבני', () async {
    final rendered = line(
      prependSectionMarker(
        'אמר <a class="link-anchor link-anchor-0" href="x">(ב)</a>רבי יוחנן',
        'סעיף א',
      ),
    );
    final selection = SourceSelection.strip(
      shownText: rendered.text,
      lines: [rendered],
      startColumn: 0,
    );
    expect(SourceSelection.resolve(selection, rendered.text, 0), (
      text: 'אמר רבי יוחנן',
      column: 0,
    ));
    for (final anchors in MarkVisibility.values) {
      final copied = await buildSelectedTextCopy(
        plainText: rendered.text,
        selectedIndex: 0,
        sourceContent: const ['אמר רבי יוחנן'],
        textBookState: null,
        settingsState: SettingsState.initial(),
        source: selection,
        copyProfile: TextDisplayProfile(anchorMarkers: anchors),
      );
      expect(
        copied!.plainText,
        anchors == MarkVisibility.hide
            ? '[סעיף א] אמר רבי יוחנן'
            : rendered.text,
      );
    }
    final start = rendered.text.indexOf('יוחנן');
    final suffix = SourceSelection.strip(
      shownText: 'יוחנן',
      lines: [rendered],
      startColumn: start,
    );
    expect(SourceSelection.resolve(suffix, 'יוחנן', start), (
      text: 'יוחנן',
      column: 8,
    ));
    expect(SourceSelection.forCopy(selection, 'בחירה אחרת'), 'בחירה אחרת');
  });
  test('כותרות בלוק יוצרות גבול רך בלבד; רווחים בגוף עדיין מחייבים', () {
    final first = renderSelectionLineWithMarkers(
      rawText: prependSectionMarker(
        'אמר <a class="link-anchor link-anchor-0" href="x">(ב)</a>רבי יוחנן',
        'סעיף א',
      ),
      settings: settings,
      blockHeadings: const ['כותרת א', 'כותרת ב'],
    );
    final second = line(prependSectionMarker('שלום עולם', 'סעיף ב'));
    final lines = [first, second];
    const flat = 'כותרת אכותרת ב[סעיף א] אמר (ב)רבי יוחנן\n[סעיף ב] שלום עולם';
    final restored = restoreSelectedTextLineBreaksDetailed(
      selectedText: flat,
      visibleLines: lines.map((l) => l.text).toList(),
    );
    expect(restored.startLine, 0);
    expect(restored.endLine, 1);
    expect(
      restored.text,
      'כותרת א\nכותרת ב\n[סעיף א] אמר (ב)רבי יוחנן\n[סעיף ב] שלום עולם',
    );
    final source = SourceSelection.strip(
      shownText: restored.text,
      lines: lines,
      startColumn: 0,
    );
    expect(SourceSelection.resolve(source, restored.text, 0), (
      text: 'אמר רבי יוחנן\nשלום עולם',
      column: 0,
    ));
    expect(
      SourceSelection.forCopy(source, restored.text),
      'כותרת א\nכותרת ב\n[סעיף א] אמר רבי יוחנן\n[סעיף ב] שלום עולם',
    );
    expect(first.blockPrefixLength, 'כותרת א\nכותרת ב\n'.length);
    expect(SourceSelection.paragraphForLine(source, restored.text, 0), (
      text: '[סעיף א] אמר (ב)רבי יוחנן',
      column: 0,
    ));
    expect(SourceSelection.paragraphForLine(source, restored.text, 1), (
      text: '[סעיף ב] שלום עולם',
      column: 0,
    ));
    expect(
      SourceSelection.paragraphForLine(
        source,
        restored.text,
        0,
        blockRange: (0, 7),
      ),
      (
        text: 'כותרת א',
        column: 0,
      ),
    );
    expect(
      SourceSelection.paragraphForLine(
        source,
        restored.text,
        0,
        blockRange: (8, 15),
      ),
      (
        text: 'כותרת ב',
        column: 0,
      ),
    );
    final wrong = restoreSelectedTextLineBreaksDetailed(
      selectedText: flat.replaceFirst('אמר (ב)רבי', 'אמר(ב)רבי'),
      visibleLines: lines.map((l) => l.text).toList(),
    );
    expect(wrong.startLine, isNull);
  });
}
