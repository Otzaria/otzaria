import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/plugins/services/reader_section_sync_gate.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/text_book/view/selection/text_selection_manager.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';

import '../../../test_helpers/memory_cache_provider.dart';

// פסקה אחת של חמש שורות; "מילה" מופיעה גם בשורה הראשונה וגם בשלישית.
const _lines = [
  'שורה ראשונה מילה',
  'שורה שניה',
  'שורה שלישית מילה',
  'שורה רביעית',
  'שורה חמישית',
];

final _referenceLink = Link(
  heRef: 'ספר אחר א',
  index1: 3,
  path2: 'ספר אחר',
  index2: 1,
  connectionType: 'reference',
);

final _rashiLink = Link(
  heRef: 'רש"י על ספר בדיקה א',
  index1: 3,
  path2: 'commentary/רש"י.txt',
  index2: 1,
  connectionType: 'COMMENTARY',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  for (final simple in [false, true]) {
    final screen = simple ? 'צורת הדף' : 'עיון';

    testWidgets('$screen: יצירת הערה כשחלונית ההערות סגורה פותחת דיאלוג', (
      tester,
    ) async {
      final h = await _pump(tester, simple: simple);
      await _openMenuAt(tester, _textRect(tester, 'מילה', occurrence: 1));
      await tester.tap(find.text('הערה'));
      await _pumpUntil(
        tester,
        () => find.byType(PersonalNoteEditorDialog).evaluate().isNotEmpty,
      );
      final dialog = tester.widget<PersonalNoteEditorDialog>(
        find.byType(PersonalNoteEditorDialog),
      );
      expect(dialog.bookId, 'ספר בדיקה');
      expect(dialog.draftLineNumber, 3);
      expect(h.notes.received.whereType<StartCreatingPersonalNote>(), isEmpty);
      expect(h.notesPanelOpenCalls, 0);
      await tester.tap(find.text('ביטול'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonalNoteEditorDialog), findsNothing);
    });

    testWidgets('$screen: לחיצה בתוך פסקה בוחרת את השורה שנלחצה', (
      tester,
    ) async {
      final h = await _pump(tester, simple: simple);
      await tester.tapAt(
        _textRect(tester, 'שלישית').center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        h.bloc.received.whereType<UpdateSelectedIndex>().last,
        const UpdateSelectedIndex(2),
      );
    });

    testWidgets('$screen: Ctrl+לחיצה מוסיפה את השורה שנלחצה', (tester) async {
      final h = await _pump(tester, simple: simple);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tapAt(
        _textRect(tester, 'רביעית').center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        h.bloc.received.whereType<UpdateSelectedIndex>(),
        contains(const UpdateSelectedIndex(3, additive: true)),
      );
    });

    testWidgets('$screen: המיקום בפסקה מתורגם לשורה ולעמודה שבתוכה', (
      tester,
    ) async {
      await _pump(tester, simple: simple);
      final lines = tester.renderObject<RenderReaderParagraphLines>(
        find.byType(ReaderParagraphLines),
      );
      final hit = lines.locate(
        _textRect(tester, 'מילה', occurrence: 1).center,
      )!;
      expect(hit.lineIndex, 2);
      expect(hit.column, inInclusiveRange(12, 16));
      final text = lines.paragraph!.text.toPlainText();
      expect(hit.lineRange!.textInside(text), _lines[2]);
      expect(lines.rangeForLine(0)!.textInside(text), _lines[0]);
    });

    testWidgets('$screen: תפריט ההקשר פועל על השורה שנלחצה', (tester) async {
      await _pump(
        tester,
        simple: simple,
        linksByLine: {
          3: [_referenceLink],
        },
      );
      final region = find.byType(AppContextMenuRegion).first;
      // טעינת הקישורים של השורה אסינכרונית; ממתינים עד שהפריט מגיע למצבו.
      Future<bool> linksEnabledAt(
        Offset position, {
        required bool until,
      }) async {
        bool enabled() => tester
            .widget<AppContextMenuRegion>(region)
            .menuBuilder(tester.element(region), position)
            .singleWhere((entry) => entry.label == 'קישורים')
            .enabled;
        await _pumpUntil(tester, () => enabled() == until);
        return enabled();
      }

      expect(
        await linksEnabledAt(
          _textRect(tester, 'מילה', occurrence: 1).center,
          until: true,
        ),
        isTrue,
      );
      expect(
        await linksEnabledAt(_textRect(tester, 'מילה').center, until: false),
        isFalse,
      );
    });

    testWidgets('$screen: סימניה מהתפריט נשמרת לשורה שנלחצה', (tester) async {
      final h = await _pump(tester, simple: simple, book: _NoTocBook());
      await _openMenuAt(tester, _textRect(tester, 'מילה', occurrence: 1));
      await tester.tap(find.text('הוסף סימניה לקטע זה'));
      await _pumpUntil(tester, () => h.bookmarks.indices.isNotEmpty);
      expect(h.bookmarks.indices, [2]);
    });

    testWidgets('$screen: סימון קבוע מצויר רק מאחורי השורה המסומנת', (
      tester,
    ) async {
      await _pump(
        tester,
        simple: simple,
        adjust: (s) => s.copyWith(permanentHighlightLine: 2),
      );
      final paragraph = tester.widget<ContinuousReadingParagraph>(
        find.byType(ContinuousReadingParagraph),
      );
      final mark = AppSurfaces.permanentMark(
        Theme.of(
          tester.element(find.byType(ContinuousReadingParagraph)),
        ).colorScheme,
      );
      expect(
        [for (final line in paragraph.lines) line.background],
        [null, null, mark, null, null],
      );
      final lines = tester.renderObject<RenderReaderParagraphLines>(
        find.byType(ReaderParagraphLines),
      );
      final rects = lines.lineRects(2);
      expect(rects, isNotEmpty);
      final third = _textRect(tester, 'שלישית');
      final local = lines.globalToLocal(third.center);
      expect(rects.any((rect) => rect.contains(local)), isTrue);
      expect(
        rects.any(
          (rect) => rect.contains(
            lines.globalToLocal(_textRect(tester, 'שניה').center),
          ),
        ),
        isFalse,
      );
    });

    testWidgets('$screen: ?mark עם טקסט מדגיש בתוך השורה בלבד', (
      tester,
    ) async {
      await _pump(
        tester,
        simple: simple,
        adjust: (s) =>
            s.copyWith(permanentHighlightLine: 2, highlightText: 'מילה'),
      );
      final paragraph = tester.widget<ContinuousReadingParagraph>(
        find.byType(ContinuousReadingParagraph),
      );
      bool marked(int line) =>
          paragraph.lines[line].htmlText!.contains('background-color');
      expect(marked(2), isTrue);
      expect(marked(0), isFalse);
      expect(paragraph.lines.every((line) => line.background == null), isTrue);
    });

    testWidgets('$screen: בולט ויישור מההגדרות חלים על הפסקה', (
      tester,
    ) async {
      await _pump(
        tester,
        simple: simple,
        settings: SettingsState.initial().copyWith(
          fontBold: true,
          commentatorsFontBold: true,
        ),
      );
      final paragraph = tester.widget<ContinuousReadingParagraph>(
        find.byType(ContinuousReadingParagraph),
      );
      expect(paragraph.baseStyle.fontWeight, FontWeight.bold);
      expect(paragraph.textAlign, TextAlign.justify);
    });

    testWidgets('$screen: שורה ממורכזת היא בלוק ממורכז בתוך הפריט', (
      tester,
    ) async {
      await _pump(
        tester,
        simple: simple,
        data: [
          ..._lines.take(2),
          '<center>שורה ממורכזת</center>',
          ..._lines.skip(3),
        ],
      );
      expect(
        tester
            .widgetList<ContinuousReadingParagraph>(
              find.byType(ContinuousReadingParagraph),
            )
            .map((p) => [for (final line in p.lines) line.lineIndex]),
        [
          [0, 1],
          [3, 4],
        ],
      );
      final block = find.byType(ReaderLineBlock);
      expect(tester.widget<ReaderLineBlock>(block).lineIndex, 2);
      final centered = _textRect(tester, 'שורה ממורכזת');
      expect(
        (centered.center.dx - tester.getRect(block).center.dx).abs(),
        lessThan(8),
      );
      final hit = readerLineAt(
        tester.renderObject(find.byType(ReaderLineGutter)),
        centered.center,
      );
      expect(hit?.lineIndex, 2);
    });

    testWidgets('$screen: סמן הבחירה נמתח רק לאורך השורה הנבחרת', (
      tester,
    ) async {
      await _pump(
        tester,
        simple: simple,
        adjust: (s) => s.copyWith(selectedIndex: 2, selectedIndices: {2}),
      );
      final gutter = tester.renderObject<RenderReaderLineGutter>(
        find.byType(ReaderLineGutter),
      );
      final bars = gutter.barRects();
      expect(bars, hasLength(1));
      final top = gutter.localToGlobal(bars.single.topLeft).dy;
      final bottom = gutter.localToGlobal(bars.single.bottomLeft).dy;
      final third = _textRect(tester, 'שלישית');
      expect(top, lessThanOrEqualTo(third.top + 0.5));
      expect(bottom, greaterThanOrEqualTo(third.bottom - 0.5));
      expect(bottom - top, lessThan(gutter.size.height));
    });
  }

  testWidgets('שני המסכים מציירים אותו רקע לשורה המודגשת', (tester) async {
    final backgrounds = <List<Color?>>[];
    for (final simple in [false, true]) {
      await _pump(
        tester,
        simple: simple,
        adjust: (s) => s.copyWith(highlightedLine: 3),
      );
      backgrounds.add([
        for (final line
            in tester
                .widget<ContinuousReadingParagraph>(
                  find.byType(ContinuousReadingParagraph),
                )
                .lines)
          line.background,
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    expect(backgrounds.first, backgrounds.last);
    expect(backgrounds.first.whereType<Color>(), hasLength(1));
    expect(backgrounds.first[3], isNotNull);
  });

  testWidgets('צורת הדף: דיווח טעות מהתפריט מכוון לשורה שנלחצה', (
    tester,
  ) async {
    await _pump(
      tester,
      simple: true,
      book: TextBook(title: 'ספר בדיקה', id: 7),
    );
    await _openMenuAt(tester, _textRect(tester, 'מילה', occurrence: 1));
    await tester.tap(find.text('דווח על טעות בספר'));
    // פרטי הספר נקראים מהספרייה (I/O אמיתי) לפני פתיחת הדיאלוג.
    await _pumpUntil(
      tester,
      () => find.byType(TabbedReportDialog).evaluate().isNotEmpty,
      step: const Duration(milliseconds: 50),
    );
    final dialog = tester.widget<TabbedReportDialog>(
      find.byType(TabbedReportDialog),
    );
    // מספור מ-1: שורה 2 בפסקה.
    expect(dialog.currentLineNumber, 3);
  });

  testWidgets('עיון: תפריט בכרטיס המפרשים שבתוך פסקה פועל על השורה הנבחרת', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      simple: false,
      book: _NoTocBook(),
      commentaryCards: true,
      linksByLine: {
        3: [_rashiLink],
      },
      adjust: (s) => s.copyWith(
        selectedIndex: 2,
        selectedIndices: {2},
        activeCommentators: const ['רש"י'],
      ),
    );
    final card = find.byKey(const ValueKey('commentary_card_2'));
    expect(card, findsOneWidget);
    final cardRect = tester.getRect(card);
    await _openMenuAt(
      tester,
      Rect.fromLTWH(cardRect.right - 6, cardRect.top + 2, 4, 4),
    );
    await tester.tap(find.text('הוסף סימניה לקטע זה'));
    await _pumpUntil(tester, () => h.bookmarks.indices.isNotEmpty);
    expect(h.bookmarks.indices, [2]);
  });

  testWidgets('עיון: Shift+לחיצה בפסקה מעגנת את הבחירה בשורה שנלחצה', (
    tester,
  ) async {
    final anchors = <int>[];
    debugOnSelectionAnchor = anchors.add;
    addTearDown(() => debugOnSelectionAnchor = null);
    await _pump(tester, simple: false);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tapAt(
      _textRect(tester, 'רביעית').center,
      kind: PointerDeviceKind.mouse,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 500));
    expect(anchors, isNotEmpty);
    expect(anchors.first, 3);
  });

  testWidgets('שורה בתוך פסקה ממוזגת מסונכרנת לתוספים כקטע משלה', (
    tester,
  ) async {
    ReaderSectionSyncGate.instance.clear();
    await _pump(tester, simple: false, book: TextBook(title: 'ספר סנכרון'));
    expect(find.byType(ContinuousReadingParagraph), findsOneWidget);
    expect(ReaderSectionSyncGate.instance.trackedSections, _lines.length);
    ReaderSectionSyncGate.instance.forget(
      bookId: 'ספר סנכרון',
      sectionIndex: 2,
    );
    expect(ReaderSectionSyncGate.instance.trackedSections, _lines.length - 1);
  });

  testWidgets('צורת הדף: לחיצה ימנית על בחירה בפסקה שומרת אותה', (
    tester,
  ) async {
    final copied = <String>[];
    debugSelectedTextCopyHandler = (content) => copied.add(content.plainText);
    addTearDown(() => debugSelectedTextCopyHandler = null);
    await _pump(tester, simple: true);
    final word = _textRect(tester, 'רביעית');
    await _selectWord(tester, word);
    await _openMenuAt(tester, word);
    await tester.pumpAndSettle();
    expect(find.text('דווח על טעות בספר'), findsOneWidget);
    await _pressCtrlC(tester, copied);
    expect(copied.map((text) => text.trim()), ['רביעית']);
  });

  testWidgets('עיון: הערה מהתפריט נוצרת לשורה שנלחצה', (tester) async {
    final h = await _pump(tester, simple: false, notesPanelOpen: true);
    await _openMenuAt(tester, _textRect(tester, 'מילה', occurrence: 1));
    await tester.tap(find.text('הערה'));
    await _pumpUntil(
      tester,
      () => h.notes.received.whereType<StartCreatingPersonalNote>().isNotEmpty,
    );
    expect(
      h.notes.received.whereType<StartCreatingPersonalNote>().single.lineNumber,
      3,
    );
  });

  testWidgets('עיון: בחירה במילה שחוזרת בפסקה מזוהה בשורה שנלחצה', (
    tester,
  ) async {
    final h = await _pump(tester, simple: false);
    await _selectWord(tester, _textRect(tester, 'מילה', occurrence: 1));
    expect(h.selectedText?.trim(), 'מילה');
    expect(h.selectedLine, 2);
  });

  testWidgets('עיון: לחיצה ימנית על בחירה בפסקה שומרת אותה ו-Ctrl+C מעתיק', (
    tester,
  ) async {
    final copied = <String>[];
    debugSelectedTextCopyHandler = (content) => copied.add(content.plainText);
    addTearDown(() => debugSelectedTextCopyHandler = null);
    final h = await _pump(tester, simple: false);
    final word = _textRect(tester, 'רביעית');
    await _selectWord(tester, word);
    expect(h.selectedLine, 3);
    await _openMenuAt(tester, word);
    await tester.pumpAndSettle();
    expect(find.text('הערה'), findsOneWidget);
    expect(h.selectedText?.trim(), 'רביעית');
    // התפריט אינו לוקח פוקוס; Ctrl+C מגיע לאזור הקריאה כשהוא פתוח.
    await _pressCtrlC(tester, copied);
    expect(copied, ['רביעית']);
  });

  for (final simple in [false, true]) {
    final screen = simple ? 'צורת הדף' : 'עיון';
    for (final continuous in [true, false]) {
      testWidgets(
        '$screen: העתקת בחירה על פני שורות — continuous=$continuous',
        (tester) async {
          final copied = <String>[];
          debugSelectedTextCopyHandler = (content) =>
              copied.add(content.plainText);
          addTearDown(() => debugSelectedTextCopyHandler = null);
          await _pump(
            tester,
            simple: simple,
            adjust: (s) => s.copyWith(continuousReadingMode: continuous),
          );
          await _selectRange(
            tester,
            _textRect(tester, 'ראשונה'),
            _textRect(tester, 'שלישית'),
          );
          await _pressCtrlC(tester, copied);
          final separator = continuous ? ' ' : '\n';
          expect(copied, [
            ['ראשונה מילה', 'שורה שניה', 'שורה שלישית'].join(separator),
          ]);
        },
      );
    }
  }

  testWidgets('עיון: העתקה עם שם הספר במצב רציף נשארת פסקה אחת', (
    tester,
  ) async {
    final copied = <String>[];
    debugSelectedTextCopyHandler = (content) => copied.add(content.plainText);
    addTearDown(() => debugSelectedTextCopyHandler = null);
    await _pump(
      tester,
      simple: false,
      book: _NoTocBook(),
      settings: SettingsState.initial().copyWith(
        copyWithHeaders: 'book_name',
        copyHeaderFormat: 'same_line_after_brackets',
      ),
    );
    await _selectRange(
      tester,
      _textRect(tester, 'שניה'),
      _textRect(tester, 'רביעית'),
    );
    await _pressCtrlC(tester, copied);
    expect(copied, ['שניה שורה שלישית מילה שורה רביעית (ספר בדיקה)']);
  });

  testWidgets('עיון: הדגשת ?mark אינה זולגת לפריט שמספרו כמספר השורה', (
    tester,
  ) async {
    // פריטים: 0 כותרת, 1 פסקה [1-3], 2 כותרת (שורה 4), 3 פסקה [5-6].
    const data = [
      '<h2>פרק א</h2>',
      'שורה אחת',
      'שורה שתיים מילה',
      'שורה שלוש',
      '<h2>פרק מילה</h2>',
      'שורה חמש',
      'שורה שש',
    ];
    await _pump(
      tester,
      simple: false,
      data: data,
      toc: [
        TocEntry(text: 'פרק א', index: 0, level: 2),
        TocEntry(text: 'פרק מילה', index: 4, level: 2),
      ],
      adjust: (s) =>
          s.copyWith(permanentHighlightLine: 2, highlightText: 'מילה'),
    );
    final header = tester
        .widgetList<SmartTextWidget>(find.byType(SmartTextWidget))
        .singleWhere((w) => w.highlightSectionIndex == 4);
    expect(header.settings.highlightYellowBackground, isFalse);
    final paragraph = tester
        .widgetList<ContinuousReadingParagraph>(
          find.byType(ContinuousReadingParagraph),
        )
        .first;
    expect(
      paragraph.lines.singleWhere((line) => line.lineIndex == 2).htmlText,
      contains('background-color'),
    );
  });
}

/// עץ כותרות ריק בלי לטעון את ספקי הספרייה (I/O אמיתי שנתקע בין טסטים).
class _NoTocBook extends TextBook {
  _NoTocBook() : super(title: 'ספר בדיקה');

  @override
  Future<List<TocEntry>> get tableOfContents async => const [];
}

class _Harness {
  _Harness(this.bloc, this.notes, this.bookmarks);

  final _TextBookBloc bloc;
  final _PersonalNotesBloc notes;
  final _BookmarkBloc bookmarks;
  int notesPanelOpenCalls = 0;
  String? selectedText;
  int? selectedLine;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required bool simple,
  List<String> data = _lines,
  TextBook? book,
  Map<int, List<Link>> linksByLine = const {},
  List<TocEntry> toc = const [],
  SettingsState? settings,
  bool commentaryCards = false,
  bool notesPanelOpen = false,
  TextBookLoaded Function(TextBookLoaded state)? adjust,
}) async {
  book ??= TextBook(title: 'ספר בדיקה');
  var state = TextBookLoaded(
    book: book,
    showLeftPane: false,
    content: data,
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const [],
    visibleLinks: const [],
    linksByLine: linksByLine,
    tableOfContents: toc,
    removeNikud: false,
    visibleIndices: List.generate(data.length, (i) => i),
    pinLeftPane: false,
    searchText: '',
    continuousReadingMode: true,
  );
  if (adjust != null) state = adjust(state);
  final bloc = _TextBookBloc(state);
  final settingsBloc = _SettingsBloc(settings ?? SettingsState.initial());
  final notes = _PersonalNotesBloc(const PersonalNotesState.initial());
  final bookmarks = _BookmarkBloc();
  final h = _Harness(bloc, notes, bookmarks);
  final tab = TextBookTab(book: book, index: 0);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
    tab.dispose();
    await bloc.close();
    await settingsBloc.close();
    await notes.close();
    await bookmarks.close();
  });

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('he', 'IL')],
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<BookmarkBloc>.value(value: bookmarks),
        ],
        child: Scaffold(
          body: simple
              ? SimpleTextViewer(
                  content: data,
                  fontSize: 18,
                  isMainText: true,
                  isPersonalNotesTabActive: notesPanelOpen,
                  onOpenSidebarTab: (_) => h.notesPanelOpenCalls++,
                  openBookCallback: (_) {},
                )
              : CombinedView(
                  data: data,
                  openBookCallback: (_) {},
                  openLeftPaneTab: (_, {searchText}) {},
                  textSize: 18,
                  showCommentaryAsExpansionTiles: commentaryCards,
                  onOpenPersonalNotes: () => h.notesPanelOpenCalls++,
                  isPersonalNotesTabActive: () => notesPanelOpen,
                  onSelectedTextChanged: (text, line, _) {
                    h.selectedText = text;
                    h.selectedLine = line;
                  },
                  tab: tab,
                ),
        ),
      ),
    ),
  );
  await tester.pump();
  // אתחול ה-DB שבאנר המקור מתחיל חייב להסתיים בשעון אמיתי; אחרת הוא נשאר
  // תקוע ותוקע את כל קריאות הספרייה בטסטים הבאים.
  await _pumpUntil(
    tester,
    () => !SqliteDataProvider.instance.debugIsInitializing,
  );
  return h;
}

Rect _textRect(WidgetTester tester, String text, {int occurrence = 0}) {
  final paragraph = tester.allRenderObjects
      .whereType<RenderParagraph>()
      .firstWhere((p) => p.text.toPlainText().contains(text));
  final plain = paragraph.text.toPlainText();
  var offset = plain.indexOf(text);
  for (var i = 0; i < occurrence; i++) {
    offset = plain.indexOf(text, offset + 1);
  }
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + text.length),
      )
      .first
      .toRect();
  return Rect.fromPoints(
    paragraph.localToGlobal(box.topLeft),
    paragraph.localToGlobal(box.bottomRight),
  );
}

Future<void> _selectWord(WidgetTester tester, Rect word) async {
  final gesture = await tester.startGesture(
    Offset(word.right - 1, word.center.dy),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(Offset(word.left + 1, word.center.dy));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

/// גרירה מתחילת [from] עד סוף [to] (מימין לשמאל).
Future<void> _selectRange(WidgetTester tester, Rect from, Rect to) async {
  final gesture = await tester.startGesture(
    Offset(from.right - 1, from.center.dy),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(Offset(to.left + 1, to.center.dy));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

/// Ctrl+C, וממתין עד שההעתקה (אסינכרונית) מגיעה ל-[copied].
Future<void> _pressCtrlC(WidgetTester tester, List<String> copied) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await _pumpUntil(tester, () => copied.isNotEmpty);
}

/// מריץ את התור האמיתי ובונה פריימים עד ש-[condition] מתקיים (או עד חסם).
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration step = const Duration(milliseconds: 10),
}) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump();
  }
}

Future<void> _openMenuAt(WidgetTester tester, Rect target) async {
  await tester.tapAt(
    target.center,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

class _TextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) => received.add(event));
  }

  final List<TextBookEvent> received = [];

  @override
  final TextBookRepository repository = _TextBookRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TextBookRepository implements TextBookRepository {
  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PersonalNotesBloc extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _PersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) => received.add(event));
  }

  final List<PersonalNotesEvent> received = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _BookmarkBloc() : super(BookmarkState.initial());

  final List<int> indices = [];

  @override
  bool addBookmark({
    required String ref,
    required Book book,
    required int index,
    List<String>? commentatorsToShow,
    BookmarkTargetKind targetKind = BookmarkTargetKind.book,
    String? label,
  }) {
    indices.add(index);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
