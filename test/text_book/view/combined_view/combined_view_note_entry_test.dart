import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/personal_notes/widgets/inline_note_editor.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../test_helpers/memory_cache_provider.dart';

const _lines = ['פסקה ראשונה', 'פסקה שניה', 'פסקה שלישית'];

const _genesisLines = [
  "<h1>בראשית</h1>",
  "<h2>פרק א</h2>",
  "(א) <big>בְּ</big>רֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֥ת הַשָּׁמַ֖יִם וְאֵ֥ת הָאָֽרֶץ׃",
  "(ב) וְהָאָ֗רֶץ הָיְתָ֥ה תֹ֙הוּ֙ וָבֹ֔הוּ וְחֹ֖שֶׁךְ עַל־פְּנֵ֣י תְה֑וֹם וְר֣וּחַ אֱלֹהִ֔ים מְרַחֶ֖פֶת עַל־פְּנֵ֥י הַמָּֽיִם׃",
  "(ג) וַיֹּ֥אמֶר אֱלֹהִ֖ים יְהִ֣י א֑וֹר וַֽיְהִי־אֽוֹר׃",
];

void main() {
  testWidgets('markers loaded during drag update cached selection lines', (
    tester,
  ) async {
    final fixture = await _pumpView(
      tester,
      continuous: false,
      selectedIndex: 0,
      data: const ['אמר רבי יוחנן הלכה'],
      linksByLine: const {},
    );
    final first = _textBox(tester, 'רבי');
    var last = _textBox(tester, 'יוחנן');
    final gesture = await tester.startGesture(
      Offset(first.right - 1, first.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(Offset(last.left + 1, last.center.dy));
    await tester.pump();
    expect(fixture.selectedText, 'רבי יוחנן');
    final viewContext = tester.element(find.byType(CombinedView));
    final bloc = viewContext.read<TextBookBloc>();
    bloc.add(
      UpdateLinks([
        Link(
          heRef: 'מפרש בדיקה א, ב',
          index1: 1,
          path2: 'מפרש בדיקה',
          index2: 1,
          connectionType: 'commentary',
          anchorStart: 7,
          anchorLabel: 'ב',
        ),
      ]),
    );
    await tester.pump();
    await tester.pump();
    expect(_textBox(tester, '(ב)'), isNotNull);
    last = _textBox(tester, 'יוחנן');
    await gesture.moveTo(Offset(last.left + 1, last.center.dy));
    await tester.pump();
    expect(fixture.selectedText, 'רבי יוחנן');
    await gesture.up();
    // מסיימים את I/O הבאנר לפני שחרור השעון המדומה של הבדיקה.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(SqliteDataProvider.instance.debugIsInitializing, isFalse);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('continuous note after headings and wrapped pointed text', (
    tester,
  ) async {
    final fixture = await _pumpView(
      tester,
      continuous: true,
      selectedIndex: 2,
      data: _genesisLines,
      book: TextBook(title: 'בראשית', id: 1),
    );
    final note = await _openNote(
      tester,
      fixture,
      _textBox(tester, '(ג)').center,
    );
    expect(note.lineNumber, 5);
    expect(note.bookId, 'בראשית');
    expect(note.selectedText, anyOf(isNull, isEmpty));
  });

  testWidgets('"הערה" באותה שורה משחזרת טיוטה שהעורך שמר עם categoryId', (
    tester,
  ) async {
    final book = TextBook(title: 'ספר בדיקה', categoryId: 42);
    // העורך מקבל מהחלונית את categoryId של הספר, וסגירה בלי שמירה שומרת טיוטה.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineNoteEditor(
            bookId: 'ספר בדיקה',
            categoryId: book.categoryId,
            draftLineNumber: 2,
            initialContent: 'טקסט שלא נשמר',
            linkableNotes: const [],
            onSave: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    final fixture = await _pumpView(tester, continuous: false, book: book);
    final note = await _openNote(
      tester,
      fixture,
      _textBox(tester, 'שניה').center,
    );
    expect(note.lineNumber, 2);
    expect(note.initialContent, contains('טקסט שלא נשמר'));
  });

  for (final continuous in [false, true]) {
    for (final selectedIndex in <int?>[null, 0, 1]) {
      for (final selection in ['none', 'cleared', 'active', 'outside']) {
        testWidgets(
          'note at clicked source line: continuous=$continuous, '
          'selectedIndex=$selectedIndex, selection=$selection',
          (tester) async {
            final fixture = await _pumpView(
              tester,
              continuous: continuous,
              selectedIndex: selectedIndex,
            );
            var click = _textBox(tester, 'שניה').center;
            if (selection != 'none') {
              await _selectText(tester, 'שניה', 'שניה');
              expect(fixture.selectedText?.trim(), 'שניה');
              expect(fixture.selectedLine, 1);
              if (selection == 'cleared') {
                await tester.sendKeyEvent(LogicalKeyboardKey.escape);
                await tester.pump();
                expect(fixture.selectedText, isNull);
              } else if (selection == 'outside') {
                click = _textBox(tester, 'שלישית').center;
              }
            }

            final note = await _openNote(tester, fixture, click);
            expect(note.lineNumber, 2);
            expect(note.bookId, 'ספר בדיקה');
            expect(
              note.selectedText,
              selection == 'active' || selection == 'outside'
                  ? 'שניה'
                  : anyOf(isNull, isEmpty),
            );
          },
        );
      }
    }

    testWidgets('cross-paragraph selection keeps its start: $continuous', (
      tester,
    ) async {
      final fixture = await _pumpView(tester, continuous: continuous);
      await _selectText(tester, 'ראשונה', 'שלישית');
      expect(fixture.selectedLine, 0);
      expect(fixture.selectedText, contains('שניה'));
      final selectedText = fixture.selectedText!.trim();
      final note = await _openNote(
        tester,
        fixture,
        _textBox(tester, 'שניה').center,
      );
      expect(note.lineNumber, 1);
      expect(note.selectedText, selectedText);
      expect(note.bookId, 'ספר בדיקה');
    });

    testWidgets('keyboard selection keeps its start: $continuous', (
      tester,
    ) async {
      final fixture = await _pumpView(tester, continuous: continuous);
      await _selectText(tester, 'שניה', 'שניה');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(fixture.selectedLine, 1);
      expect(fixture.selectedText, startsWith('שניה'));
      final selectedText = fixture.selectedText!.trim();
      final note = await _openNote(
        tester,
        fixture,
        _textBox(tester, 'שניה').center,
      );
      expect(note.lineNumber, 2);
      expect(note.selectedText, selectedText);
      expect(note.bookId, 'ספר בדיקה');
    });

    // #1859: ציון המפרש מוזרק לתצוגה ולכן נבחר עם הטקסט, אך אינו בשורת המקור.
    testWidgets('selection across a commentary marker: $continuous', (
      tester,
    ) async {
      final fixture = await _pumpView(
        tester,
        continuous: continuous,
        selectedIndex: 0,
        data: const ['פסקה ראשונה', 'אמר רבי יוחנן הלכה', 'פסקה שלישית'],
        linksByLine: {
          2: [_anchorLink],
        },
      );
      expect(_textBox(tester, '(ב)'), isNotNull);
      await _selectText(tester, 'רבי', 'יוחנן');
      expect(fixture.selectedLine, 1);
      expect(fixture.selectedText?.trim(), 'רבי יוחנן');
      final note = await _openNote(
        tester,
        fixture,
        _textBox(tester, 'יוחנן').center,
      );
      expect(note.lineNumber, 2);
      expect(note.selectedText, 'רבי יוחנן');
      expect(note.selectionColumn, 4);
    });

    testWidgets('selection after a commentary marker: $continuous', (
      tester,
    ) async {
      final fixture = await _pumpView(
        tester,
        continuous: continuous,
        selectedIndex: 0,
        data: const ['פסקה ראשונה', 'אמר רבי יוחנן הלכה', 'פסקה שלישית'],
        linksByLine: {
          2: [_anchorLink],
        },
      );
      await _selectText(tester, 'יוחנן', 'הלכה');
      expect(fixture.selectedLine, 1);
      final note = await _openNote(
        tester,
        fixture,
        _textBox(tester, 'יוחנן').center,
      );
      expect(note.selectedText, 'יוחנן הלכה');
      expect(note.selectionColumn, 8);
    });

    testWidgets('Ctrl+C follows the copy channel: $continuous', (
      tester,
    ) async {
      final copied = <String>[];
      debugSelectedTextCopyHandler = (content) => copied.add(content.plainText);
      addTearDown(() => debugSelectedTextCopyHandler = null);
      await _pumpView(
        tester,
        continuous: continuous,
        selectedIndex: 0,
        data: const ['פסקה ראשונה', 'אמר רבי יוחנן הֲלָכָה', 'פסקה שלישית'],
        linksByLine: {
          2: [_anchorLink],
        },
        displayPolicy: _hiddenInCopy,
      );
      await _selectText(tester, 'רבי', 'הֲלָכָה');
      await _pressCtrlC(tester);
      expect(copied, ['רבי יוחנן הלכה']);
    });

    testWidgets('error report gets the source selection: $continuous', (
      tester,
    ) async {
      await _pumpView(
        tester,
        continuous: continuous,
        selectedIndex: 0,
        book: TextBook(title: 'ספר בדיקה', id: 7),
        data: const ['פסקה ראשונה', 'אמר רבי יוחנן הלכה', 'פסקה שלישית'],
        linksByLine: {
          2: [_anchorLink],
        },
      );
      await _selectText(tester, 'רבי', 'יוחנן');
      await tester.tapAt(
        _textBox(tester, 'יוחנן').center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(find.text('דווח על טעות בספר'));
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        if (find.byType(TabbedReportDialog).evaluate().isNotEmpty) break;
      }
      final dialog = tester.widget<TabbedReportDialog>(
        find.byType(TabbedReportDialog),
      );
      expect(dialog.selectedText, 'רבי יוחנן');
    });
  }
}

final _hiddenInCopy = TextDisplayPolicy.empty.merged(
  TextDisplayBookClass.general,
  const TextDisplaySlot(
    target: TextTarget.body,
    view: TextView.regular,
    channel: TextChannel.copy,
  ),
  const TextDisplayPatch(
    anchorMarkers: MarkVisibility.hide,
    nikud: MarkVisibility.hide,
  ),
);

Future<void> _pressCtrlC(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

final _anchorLink = Link(
  heRef: 'מפרש בדיקה א, ב',
  index1: 2,
  path2: 'מפרש בדיקה',
  index2: 1,
  connectionType: 'commentary',
  anchorStart: 7,
  anchorLabel: 'ב',
);

class _Fixture {
  final _PersonalNotesBloc notesBloc;
  String? selectedText;
  int? selectedLine;

  _Fixture(this.notesBloc);
}

Future<_Fixture> _pumpView(
  WidgetTester tester, {
  required bool continuous,
  int? selectedIndex,
  List<String> data = _lines,
  TextBook? book,
  Map<int, List<Link>>? linksByLine,
  TextDisplayPolicy? displayPolicy,
}) async {
  book ??= TextBook(title: 'ספר בדיקה');
  final bloc = _TextBookBloc(
    _loadedState(
      book: book,
      availableCommentators: const [],
      selectedIndex: selectedIndex,
      continuous: continuous,
      data: data,
      linksByLine: linksByLine,
      displayPolicy: displayPolicy,
    ),
  );
  final settingsBloc = _SettingsBloc(SettingsState.initial());
  final notesBloc = _PersonalNotesBloc(const PersonalNotesState.initial());
  final fixture = _Fixture(notesBloc);
  final tab = TextBookTab(book: book, index: 0);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 20));
    tab.dispose();
    await bloc.close();
    await settingsBloc.close();
    await notesBloc.close();
  });

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('he', 'IL')],
      home: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
        ],
        child: Scaffold(
          body: CombinedView(
            data: data,
            openBookCallback: (_) {},
            openLeftPaneTab: (_, {searchText}) {},
            textSize: 18,
            showCommentaryAsExpansionTiles: true,
            onOpenPersonalNotes: () {},
            onSelectedTextChanged: (text, line, column) {
              fixture.selectedText = text;
              fixture.selectedLine = line;
            },
            tab: tab,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return fixture;
}

Rect _textBox(WidgetTester tester, String text) {
  final paragraph = tester.allRenderObjects
      .whereType<RenderParagraph>()
      .firstWhere(
        (paragraph) => paragraph.text.toPlainText().contains(text),
      );
  final offset = paragraph.text.toPlainText().indexOf(text);
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

Future<void> _selectText(WidgetTester tester, String start, String end) async {
  final first = _textBox(tester, start);
  final last = _textBox(tester, end);
  final gesture = await tester.startGesture(
    Offset(first.right - 1, first.center.dy),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveTo(Offset(last.left + 1, last.center.dy));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

Future<StartCreatingPersonalNote> _openNote(
  WidgetTester tester,
  _Fixture fixture,
  Offset position,
) async {
  await tester.tapAt(
    position,
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
  expect(find.text('הערה'), findsOneWidget);
  await tester.tap(find.text('הערה'));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  return fixture.notesBloc.received
      .whereType<StartCreatingPersonalNote>()
      .single;
}

TextBookLoaded _loadedState({
  required TextBook book,
  required List<String> availableCommentators,
  int? selectedIndex,
  required bool continuous,
  required List<String> data,
  Map<int, List<Link>>? linksByLine,
  TextDisplayPolicy? displayPolicy,
}) {
  return TextBookLoaded(
    book: book,
    showLeftPane: false,
    content: data,
    fontSize: 18,
    showSplitView: false,
    showPageShapeView: false,
    activeCommentators: const [],
    commentatorGroups: [
      if (availableCommentators.isNotEmpty)
        CommentatorGroup(title: 'ראשונים', commentators: availableCommentators),
    ],
    availableCommentators: availableCommentators,
    links: const [],
    visibleLinks: const [],
    linksByLine:
        linksByLine ??
        {
          1: [
            for (final title in availableCommentators) _commentaryLink(title),
          ],
        },
    tableOfContents: const [],
    removeNikud: false,
    visibleIndices: List.generate(data.length, (index) => index),
    selectedIndex: selectedIndex,
    selectedIndices: selectedIndex == null ? const {} : {selectedIndex},
    continuousReadingMode: continuous,
    readingSegments: buildReadingSegments(data, continuous: continuous),
    pinLeftPane: false,
    searchText: '',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
    displayPolicy: displayPolicy,
  );
}

Link _commentaryLink(String title) => Link(
  heRef: '',
  index1: 1,
  path2: title,
  index2: 1,
  connectionType: 'commentary',
);

class _TextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {
      if (event is UpdateLinks && state is TextBookLoaded) {
        final links = event.links.cast<Link>();
        emit(
          (state as TextBookLoaded).copyWith(
            links: links,
            linksByLine: {1: links},
          ),
        );
      }
    });
  }

  @override
  late final TextBookRepository repository = _TextBookRepository(
    (state as TextBookLoaded).availableCommentators,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TextBookRepository implements TextBookRepository {
  _TextBookRepository(this.commentators);

  final List<String> commentators;

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => [for (final title in commentators) _commentaryLink(title)];

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
