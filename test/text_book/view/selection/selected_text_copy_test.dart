import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/utils/file/toc_parser.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  group('resolveHtmlTextForSelection', () {
    test('מחזיר HTML מקורי כשהבחירה מכסה את כל השורה', () {
      final resolved = resolveHtmlTextForSelection(
        plainText: 'שלום עולם',
        selectedIndex: 0,
        sourceContent: const ['<b>שלום</b> עולם'],
      );

      expect(resolved, '<b>שלום</b> עולם');
    });

    test('מחזיר HTML חתוך כשהבחירה היא רק חלק מהשורה', () {
      final resolved = resolveHtmlTextForSelection(
        plainText: 'שלום',
        selectedIndex: 0,
        sourceContent: const ['<b>שלום</b> עולם'],
      );

      expect(resolved, '<b>שלום</b>');
    });

    test('שומר עיצוב גם בבחירה שחוצה תגית', () {
      final resolved = resolveHtmlTextForSelection(
        plainText: 'לום עו',
        selectedIndex: 0,
        sourceContent: const ['<b>שלום</b> עולם'],
      );

      expect(resolved, '<b>לום</b> עו');
    });

    test('נופל לטקסט פשוט כשהבחירה אינה נמצאת בשורה', () {
      final resolved = resolveHtmlTextForSelection(
        plainText: 'טקסט משורה אחרת',
        selectedIndex: 0,
        sourceContent: const ['<b>שלום</b> עולם'],
      );

      expect(resolved, 'טקסט משורה אחרת');
    });

    test('מחזיר fallback לטקסט פשוט כשאין אינדקס תקין', () {
      final resolved = resolveHtmlTextForSelection(
        plainText: 'שלום',
        selectedIndex: null,
        sourceContent: const ['<b>שלום</b> עולם'],
      );

      expect(resolved, 'שלום');
    });
  });

  group('העתקת בחירה לפי ערוץ ההעתקה (#1859)', () {
    final link = Link(
      heRef: 'מפרש בדיקה א, ב',
      index1: 1,
      path2: 'מפרש בדיקה',
      index2: 1,
      connectionType: 'commentary',
      anchorStart: 7,
      anchorLabel: 'ב',
    );
    final marker = anchorMarkerText(link)!;

    Future<String> copyOfSelection({
      required String line,
      required String Function(String shownLine) select,
      TextDisplayPatch copy = const TextDisplayPatch(),
    }) async {
      final state = _state(line, link, copy);
      final shown = renderSelectionLineWithMarkers(
        rawText: injectLinkAnchorMarkers(
          rawLine: line,
          anchorLinks: [link],
          styleIndexByCommentator: anchorStyleIndexByCommentator([link]),
          lineIndex: 0,
        ),
        settings: const RenderSettings(),
      );
      final selected = select(shown.text);
      final copied = await buildSelectedTextCopy(
        plainText: selected,
        selectedIndex: 0,
        sourceContent: [line],
        textBookState: state,
        settingsState: SettingsState.initial(),
        copyTarget: TextTarget.body,
        source: SourceSelection.strip(
          shownText: selected,
          lines: [shown],
          startColumn: shown.text.indexOf(selected),
        ),
      );
      return copied!.plainText;
    }

    String rabbiYochanan(String shown) =>
        shown.substring(shown.indexOf('רבי'), shown.indexOf('יוחנן') + 5);

    test('ערוץ ההעתקה מסתיר ציונים — הציון שנבחר אינו מועתק', () async {
      expect(
        await copyOfSelection(
          line: 'אמר רבי יוחנן הלכה',
          select: rabbiYochanan,
          copy: const TextDisplayPatch(anchorMarkers: MarkVisibility.hide),
        ),
        'רבי יוחנן',
      );
    });

    test('ערוץ ההעתקה כמו התצוגה — הציון מועתק כפי שהוא מוצג', () async {
      expect(
        await copyOfSelection(
          line: 'אמר רבי יוחנן הלכה',
          select: rabbiYochanan,
        ),
        'רבי$marker יוחנן',
      );
    });

    test('טקסט זהה לציון שמודפס בספר עצמו נשמר', () async {
      expect(
        await copyOfSelection(
          line: 'אמר רבי יוחנן $marker הלכה',
          select: (shown) => shown.substring(shown.indexOf('רבי')),
          copy: const TextDisplayPatch(anchorMarkers: MarkVisibility.hide),
        ),
        'רבי יוחנן $marker הלכה',
      );
    });

    test('Ctrl+C מסיר ניקוד ופיסוק כשערוץ ההעתקה מסתיר אותם', () async {
      const line = 'אָמַר, רַבִּי יוֹחָנָן.';
      final copied = await buildSelectedTextCopy(
        plainText: line,
        selectedIndex: 0,
        sourceContent: const [line],
        textBookState: _state(
          line,
          link,
          const TextDisplayPatch(
            nikud: MarkVisibility.hide,
            punctuation: MarkVisibility.hide,
          ),
        ),
        settingsState: SettingsState.initial(),
        copyTarget: TextTarget.body,
      );
      expect(copied!.plainText, 'אמר רבי יוחנן.');
    });

    test('"העתק בלי ניקוד" מסיר ניקוד גם כשערוץ ההעתקה מציג אותו', () async {
      const line = 'אָמַר רַבִּי';
      final copied = await buildSelectedTextCopy(
        plainText: line,
        selectedIndex: 0,
        sourceContent: const [line],
        textBookState: _state(line, link, const TextDisplayPatch()),
        settingsState: SettingsState.initial(),
        copyTarget: TextTarget.body,
        removeNikud: true,
      );
      expect(copied!.plainText, 'אמר רבי');
    });

    for (final continuous in [false, true]) {
      test('בחירה משלימה הורה חסר במצב רציף=$continuous', () async {
        const full = [
          '<h1>ספר</h1>',
          '<h2>פרק א</h2>',
          '',
          '<h3>הלכה א</h3><h4>סעיף א</h4>',
          'טקסט',
        ];
        const partial = ['', '', '', '<h3>הלכה א</h3><h4>סעיף א</h4>', 'טקסט'];
        final state = _state('טקסט', link, const TextDisplayPatch()).copyWith(
          book: _TocBook(TocParser.parseEntriesFromContent(full.join('\n'))),
          content: partial,
          readingSegments: buildReadingSegments(
            partial,
            continuous: continuous,
            loadedLineFlags: const [false, false, false, true, true],
          ),
        );
        final copied = await buildSelectedTextCopy(
          plainText: 'טקסט',
          selectedIndex: 4,
          sourceContent: state.content,
          textBookState: state,
          settingsState: SettingsState.initial().copyWith(
            copyWithHeaders: 'book_and_path',
            copyHeaderFormat: 'separate_line_before',
          ),
        );
        expect(copied!.plainText, 'ספר, פרק א, הלכה א, סעיף א\nטקסט');
        expect(state.isContentLineLoaded(0), isFalse);
        expect(state.isContentLineLoaded(2), isFalse);
        expect(state.isContentLineLoaded(3), isTrue);
      });
    }

    test('metadata אינו נלקח מתוכן או מספר אחר בכותרת override', () async {
      final content = ['<h2>פרק א</h2>', '', '<h3>הלכה א</h3>', 'טקסט'];
      final book = _TocBook(const []);
      final state = _state('טקסט', link, const TextDisplayPatch()).copyWith(
        book: book,
        content: content,
        readingSegments: buildReadingSegments(
          content,
          continuous: true,
          loadedLineFlags: const [false, false, true, true],
        ),
      );
      for (final otherBook in [false, true]) {
        final copied = await buildSelectedTextCopy(
          plainText: 'טקסט',
          selectedIndex: 3,
          sourceContent: state.content,
          textBookState: state,
          settingsState: SettingsState.initial().copyWith(
            copyWithHeaders: 'book_and_path',
            copyHeaderFormat: 'separate_line_before',
          ),
          headerBookOverride: otherBook ? _TocBook(const []) : book,
          headerContentOverride: otherBook ? state.content : List.of(content),
        );
        expect(copied!.plainText, 'ספר, פרק א, הלכה א\nטקסט');
      }
    });

    test('אותם overrides שומרים את מידע הטעינה של אותו ספר ותוכן', () async {
      const full = [
        '<h1>ספר</h1>',
        '<h2>פרק א</h2>',
        '',
        '<h3>הלכה א</h3>',
        'טקסט',
      ];
      const partial = ['', '', '', '<h3>הלכה א</h3>', 'טקסט'];
      final state = _state('טקסט', link, const TextDisplayPatch()).copyWith(
        book: _TocBook(TocParser.parseEntriesFromContent(full.join('\n'))),
        content: partial,
        readingSegments: buildReadingSegments(
          partial,
          continuous: true,
          loadedLineFlags: const [false, false, false, true, true],
        ),
      );
      final copied = await buildSelectedTextCopy(
        plainText: 'טקסט',
        selectedIndex: 4,
        sourceContent: state.content,
        textBookState: state,
        headerBookOverride: state.book,
        headerContentOverride: state.content,
        settingsState: SettingsState.initial().copyWith(
          copyWithHeaders: 'book_and_path',
          copyHeaderFormat: 'separate_line_before',
        ),
      );
      expect(copied!.plainText, 'ספר, פרק א, הלכה א\nטקסט');
    });

    test('זמינות שורה בלי segments משמרת את חוזה התוכן הישן', () async {
      final content = ['<h2>פרק א</h2>', '', 'טקסט'];
      final state = _state(
        'טקסט',
        link,
        const TextDisplayPatch(),
      ).copyWith(book: _TocBook(const []), content: content);
      expect(state.isContentLineLoaded(1), isTrue);
      final copied = await buildSelectedTextCopy(
        plainText: 'טקסט',
        selectedIndex: 2,
        sourceContent: state.content,
        textBookState: state,
        settingsState: SettingsState.initial().copyWith(
          copyWithHeaders: 'book_and_path',
          copyHeaderFormat: 'separate_line_before',
        ),
      );
      expect(copied!.plainText, 'ספר, פרק א\nטקסט');
    });

    test('חיפוש זמינות מבחין בגבולות ובטווח חסר, ומאפשר מידע חסר', () {
      final state = _state('טקסט', link, const TextDisplayPatch()).copyWith(
        readingSegments: const [
          ReadingSegment(
            text: '',
            sourceLineIndices: [0],
            lineRanges: [],
            isHeader: false,
          ),
          ReadingSegment(
            text: '',
            sourceLineIndices: [2, 3],
            lineRanges: [],
            isHeader: false,
            isLoaded: false,
          ),
          ReadingSegment(
            text: '',
            sourceLineIndices: [5],
            lineRanges: [],
            isHeader: false,
          ),
        ],
      );
      for (final i in [-1, 0, 1, 4, 5, 6]) {
        expect(state.isContentLineLoaded(i), isTrue, reason: 'index=$i');
      }
      for (final i in [2, 3]) {
        expect(state.isContentLineLoaded(i), isFalse, reason: 'index=$i');
      }
    });

    test('בחירה של הציון בלבד אינה דורסת את הלוח בריק', () async {
      const line = 'אמר רבי יוחנן הלכה';
      final shown = renderSelectionLineWithMarkers(
        rawText: injectLinkAnchorMarkers(
          rawLine: line,
          anchorLinks: [link],
          styleIndexByCommentator: anchorStyleIndexByCommentator([link]),
        ),
        settings: const RenderSettings(),
      );
      final copied = await buildSelectedTextCopy(
        plainText: marker,
        selectedIndex: 0,
        sourceContent: const [line],
        textBookState: _state(
          line,
          link,
          const TextDisplayPatch(anchorMarkers: MarkVisibility.hide),
        ),
        settingsState: SettingsState.initial(),
        copyTarget: TextTarget.body,
        source: SourceSelection.strip(
          shownText: marker,
          lines: [shown],
          startColumn: shown.text.indexOf(marker),
        ),
      );
      expect(copied, isNull);
    });
  });
}

TextBookLoaded _state(String line, Link link, TextDisplayPatch copy) {
  return TextBookLoaded(
    book: TextBook(title: 'ספר בדיקה'),
    showLeftPane: false,
    content: [line],
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: [link],
    linksByLine: {
      1: [link],
    },
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
    displayPolicy: TextDisplayPolicy.empty.merged(
      TextDisplayBookClass.general,
      const TextDisplaySlot(
        target: TextTarget.body,
        view: TextView.regular,
        channel: TextChannel.copy,
      ),
      copy,
    ),
  );
}

class _TocBook extends TextBook {
  _TocBook(this.toc) : super(title: 'ספר');
  final List<TocEntry> toc;
  @override
  Future<List<TocEntry>> get tableOfContents async => toc;
}
