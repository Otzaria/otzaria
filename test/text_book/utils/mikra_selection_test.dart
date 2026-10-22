/// בחירה בספר מקרא: חלון הבחירה רואה את השורות כפי שהן מוצגות, והעמודה
/// מוחזרת לצרכנים בשורה הרגילה. הנתונים סינתטיים, במבנה השורות של המסד.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:characters/characters.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/models/text_source_map.dart';
import 'package:otzaria/plugins/services/plugin_highlight_renderer.dart';
import 'package:otzaria/text_book/utils/mikra_selection.dart';
import 'package:otzaria/text_book/utils/mikra_structure.dart';
import 'package:otzaria/text_book/utils/reading_layout.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/utils/reader_paragraph_copy.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_spec.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';

const String _pe = '&nbsp;<span class="mam-spi-pe">{פ}</span><br>';

final List<String> _book = [
  '<h1>ספר</h1>', // 0
  '<h2>פרק א</h2>', // 1
  '(א) אבג דהו:', // 2
  '(ב) זחט יכל:', // 3
  '(ג) מנס עפצ:', // 4
  '<h2>פרק ב</h2>', // 5
  '(א) קרש תאב:$_pe', // 6
  '(ב) גדה וזח:', // 7
];

const RenderSettings _settings = RenderSettings();

List<String> _windowLines({required bool mikraAware}) {
  final mikra = MikraStructure.parse(_book)!;
  return [
    for (var i = 0; i < _book.length; i++)
      renderSelectionLine(
        rawText: mikraAware ? mikraSelectionHtml(mikra, i, _book[i]) : _book[i],
        settings: _settings,
      ),
  ];
}

SelectionParagraphs _paragraphs() {
  final mikra = MikraStructure.parse(_book)!;
  final layout = ReadingLayout.continuous(
    lineCount: _book.length,
    breakLines: mikra.bookTitleLines,
    splitAfterLines: mikra.paragraphEndLines,
  );
  return readerSelectionParagraphs(
    layout: layout,
    lines: _book,
    baseIndex: 0,
    mikra: mikra,
  )!;
}

void main() {
  group('חלון הבחירה במקרא', () {
    test('שורות החלון כמו בתצוגה: בלי מספר פסוק, כותרת פרק ריקה', () {
      final lines = _windowLines(mikraAware: true);
      expect(lines[2], 'אבג דהו:');
      expect(lines[5], '');
      expect(lines[6], 'קרש תאב: {פ}');
    });

    test('בחירה שחוצה פסוקים נמצאת, ובלי היישור — לא', () {
      // מה שהמשתמש רואה ובוחר: סוף פסוק א׳ ותחילת פסוק ב׳, בלי "(ב)".
      const selected = 'דהו: זחט';
      final aligned = restoreSelectedTextLineBreaksDetailed(
        selectedText: selected,
        visibleLines: _windowLines(mikraAware: true),
        paragraphs: _paragraphs(),
      );
      expect(aligned.startLine, 2);
      expect(aligned.endLine, 3);
      expect(aligned.startColumn, 4);

      final standard = restoreSelectedTextLineBreaksDetailed(
        selectedText: selected,
        visibleLines: _windowLines(mikraAware: false),
        paragraphs: _paragraphs(),
      );
      expect(standard.startLine, isNull);
    });

    test('בחירה שחוצה פרק (דרך כותרת מוסתרת) נמצאת', () {
      const selected = 'עפצ: קרש';
      final aligned = restoreSelectedTextLineBreaksDetailed(
        selectedText: selected,
        visibleLines: _windowLines(mikraAware: true),
        paragraphs: _paragraphs(),
      );
      expect(aligned.startLine, 4);
      expect(aligned.endLine, 6);
    });
  });

  group('mikraColumnShift', () {
    test('אורך מספר הפסוק ברינדור הרגיל', () {
      final mikra = MikraStructure.parse(_book)!;
      expect(
        mikraColumnShift(
          rawLine: _book[3],
          line: 3,
          mikra: mikra,
          settings: _settings,
        ),
        '(ב) '.length,
      );
    });

    test('עמודה מוצגת + הסטה = עמודה בשורה הרגילה', () {
      final mikra = MikraStructure.parse(_book)!;
      final standard = renderSelectionLine(
        rawText: _book[6],
        settings: _settings,
      );
      final shown = renderSelectionLine(
        rawText: mikraSelectionHtml(mikra, 6, _book[6]),
        settings: _settings,
      );
      final shownColumn = shown.indexOf('תאב');
      final shift = mikraColumnShift(
        rawLine: _book[6],
        line: 6,
        mikra: mikra,
        settings: _settings,
      );
      expect(standard.substring(shownColumn + shift).startsWith('תאב'), isTrue);
    });

    test('כותרת פרק ושורת ספר — בלי הסטה', () {
      final mikra = MikraStructure.parse(_book)!;
      expect(
        mikraColumnShift(
          rawLine: _book[5],
          line: 5,
          mikra: mikra,
          settings: _settings,
        ),
        0,
      );
    });

    test('גם בהסרת פיסוק (הסוגריים נעלמים) ההסטה נכונה', () {
      final mikra = MikraStructure.parse(_book)!;
      const settings = RenderSettings(removePunctuation: true);
      final standard = renderSelectionLine(
        rawText: _book[3],
        settings: settings,
      );
      final shift = mikraColumnShift(
        rawLine: _book[3],
        line: 3,
        mikra: mikra,
        settings: settings,
      );
      expect(standard.substring(shift).startsWith('זחט'), isTrue);
    });
  });
  group('העתקה במקרא', () {
    const samekh = '&nbsp;<span class="mam-spi-samekh">{ס}</span><br>';

    test('שורת פסוק: בלי מספר הפסוק ובלי {פ}', () {
      expect(mikraCopyHtml(_book[6]), 'קרש תאב:');
    });

    test('סתומה באמצע: רווח אחד במקום הסימון', () {
      expect(
        mikraCopyHtml(
          '(ג) אבג:$samekh'
          'דהו',
        ),
        'אבג: דהו',
      );
    });

    test('טקסט נבחר: {פ} ו-{ס} וריווח הסתומה מוסרים', () {
      expect(mikraCopyText('קרש תאב:\u00A0{פ}'), 'קרש תאב:');
      expect(
        mikraCopyText('אבג:\u00A0{ס}\u2003\u2003\u2003\u2003 דהו'),
        'אבג: דהו',
      );
      expect(mikraCopyText('עפצ: {פ}\nקרש'), 'עפצ:\nקרש');
      expect(mikraCopyText('אבג דהו'), 'אבג דהו');
    });

    test('העתקת פסקה: הטקסט כמו בתצוגה', () async {
      final copy = await buildParagraphCopyText(
        processedText: mikraCopyHtml(_book[6]),
        index: 6,
        copyWithHeaders: 'none',
        copyHeaderFormat: 'same_line_after_brackets',
      );
      expect(copy.plainText, 'קרש תאב:');
    });

    test('העתקת בחירה של פסוק שלם: טקסט ו-HTML בלי מספר ובלי {פ}', () async {
      final copy = await buildSelectedTextCopy(
        plainText: 'קרש תאב:\u00A0{פ}',
        selectedIndex: 6,
        sourceContent: mikraCopyContent(_book, 6),
        textBookState: null,
        settingsState: SettingsState.initial(),
        plainTextFilter: mikraCopyText,
      );
      expect(copy!.plainText, 'קרש תאב:');
      expect(copy.htmlText, isNot(contains('{פ}')));
      expect(copy.htmlText, isNot(contains('(א)')));
    });

    test('ציון מקור אמיתי ב«שם וכותרת» — בחירה', () async {
      final copy = await buildSelectedTextCopy(
        plainText: 'זחט יכל:',
        selectedIndex: 3,
        sourceContent: mikraCopyContent(_book, 3),
        textBookState: null,
        headerBookOverride: TextBook(title: 'ויקרא'),
        settingsState: SettingsState.initial().copyWith(
          copyWithHeaders: 'book_and_path',
          copyHeaderFormat: 'same_line_after_brackets',
        ),
        plainTextFilter: mikraCopyText,
        sourceCitation: (index) => index == 3 ? 'ויקרא, פרשת אמור, ששי' : null,
      );
      expect(copy!.plainText, 'זחט יכל: (ויקרא, פרשת אמור, ששי)');
    });

    test('ציון מקור אינו חל ב«שם הספר» בלבד', () async {
      final copy = await buildSelectedTextCopy(
        plainText: 'זחט יכל:',
        selectedIndex: 3,
        sourceContent: _book,
        textBookState: null,
        headerBookOverride: TextBook(title: 'ויקרא'),
        settingsState: SettingsState.initial().copyWith(
          copyWithHeaders: 'book_name',
          copyHeaderFormat: 'same_line_after_brackets',
        ),
        sourceCitation: (_) => 'אמור, ששי',
      );
      expect(copy!.plainText, 'זחט יכל: (ויקרא)');
    });

    test('ציון מקור אמיתי ב«שם וכותרת» — פסקה', () async {
      final copy = await buildParagraphCopyText(
        processedText: mikraCopyHtml(_book[3]),
        index: 3,
        copyWithHeaders: 'book_and_path',
        copyHeaderFormat: 'same_line_after_brackets',
        headerBook: TextBook(title: 'ויקרא'),
        sourceCitation: (_) => 'אמור, ששי',
      );
      expect(copy.plainText, 'זחט יכל: (אמור, ששי)');
    });

    test('mikraCopyContent משנה רק את השורה הנבחרת, לא את המקור', () {
      final source = List<String>.unmodifiable(_book);
      final copy = mikraCopyContent(source, 6);
      expect(copy[6], 'קרש תאב:');
      expect(copy[3], _book[3]);
      expect(source[6], _book[6]);
    });
  });

  group('הדגשות תוספים', () {
    test(
      'הדגשה שמעוגנת בשורת המקור נופלת על אותה מילה אחרי הסרת מספר הפסוק',
      () {
        const raw = '(יא) אבג דהו זחט:$_pe';
        final source = TextRendererService.stripHtml(raw);
        final start = source.characters.toList().indexOf('ד');
        final processed = TextRendererService.processText(
          mikraDisplayHtml(raw),
          _settings,
        );
        final result = const PluginHighlightRenderer().renderWithRanges(
          bookId: 'book',
          sectionIndex: 0,
          rawText: raw,
          processedHtml: processed,
          highlights: [
            _highlight(start: start, end: start + 3, exactText: 'דהו'),
          ],
        );
        expect(result.ranges, hasLength(1));
        final shown = TextRendererService.stripHtml(
          processed,
        ).characters.toList();
        expect(
          shown
              .sublist(result.ranges.single.start, result.ranges.single.end)
              .join(),
          'דהו',
        );
      },
    );
  });
}

PluginHighlight _highlight({
  required int start,
  required int end,
  required String exactText,
}) {
  const context = PluginAnchorContext(
    raw: '',
    normalized: '',
    maxGraphemes: 30,
    actualGraphemes: 0,
    truncatedAtBoundary: true,
  );
  return PluginHighlight(
    highlightId: 'h',
    ownerPluginId: 'plugin',
    bookId: 'book',
    sectionIndex: 0,
    range: PluginTextRangeAnchor(
      layer: 'source',
      start: PluginTextOffset(grapheme: start, codePoint: start, utf16: start),
      end: PluginTextOffset(grapheme: end, codePoint: end, utf16: end),
      exactText: exactText,
      beforeText: context,
      afterText: context,
      occurrenceIndexInSection: 0,
      occurrenceCountInSection: 1,
    ),
    style: const PluginHighlightStyle(backgroundColor: '#FFE066'),
    createdAt: DateTime.utc(2026, 10, 17),
    updatedAt: DateTime.utc(2026, 10, 17),
  );
}
