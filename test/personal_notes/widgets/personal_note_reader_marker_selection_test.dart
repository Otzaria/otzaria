import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart'
    show HtmlWidget;
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

import '../../test_helpers/memory_cache_provider.dart';

const _bookId = 'שופטים';
const _firstWord = 'הַבֹּכִ֑ים';
const _lastWord = 'וַיֹּ֩אמֶר֩';
const _selectedAnchor = 'הבכים {פ} ויאמר';

// Judges 2:1: structural reproduction of #3260, not a v36 database dump.
// https://github.com/Sefaria/Sefaria-Export-Archive/blob/3f1013631fdfe452e953a93a2c5f921319e394ed/json/Tanakh/Prophets/Judges/Hebrew/merged.json
const _verseHtml =
    'וַיַּ֧עַל מַלְאַךְ־יְהֹוָ֛ה מִן־הַגִּלְגָּ֖ל אֶל־הַבֹּכִ֑ים'
    '&nbsp;<span class="mam-spi-pe">{פ}</span><br>'
    'וַיֹּ֩אמֶר֩ אַעֲלֶ֨ה אֶתְכֶ֜ם מִמִּצְרַ֗יִם וָאָבִ֤יא אֶתְכֶם֙ '
    'אֶל־הָאָ֗רֶץ אֲשֶׁ֤ר נִשְׁבַּ֙עְתִּי֙ לַאֲבֹ֣תֵיכֶ֔ם וָאֹמַ֕ר '
    'לֹֽא־אָפֵ֧ר בְּרִיתִ֛י אִתְּכֶ֖ם לְעוֹלָֽם׃';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  for (final removeMarks in [false, true]) {
    for (final forceHtml in [false, true]) {
      testWidgets(
        'Judges reader selection crosses paragraph marker '
        '(removeMarks=$removeMarks, HtmlWidget=$forceHtml)',
        (tester) async {
          final previousPlatform = debugDefaultTargetPlatformOverride;
          final database = _NotesDatabase();
          final repository = _NotesRepository(database);
          final notesBloc = PersonalNotesBloc(repository: repository);
          final readerBloc = _ReaderBloc(_loadedState(removeMarks));
          final settingsBloc = _SettingsBloc(SettingsState.initial());
          addTearDown(notesBloc.close);
          addTearDown(readerBloc.close);
          addTearDown(settingsBloc.close);
          try {
            debugDefaultTargetPlatformOverride = TargetPlatform.windows;
            SmartTextWidget.debugForceHtmlWidget = forceHtml;
            await tester.binding.setSurfaceSize(const Size(900, 700));
            notesBloc.add(const LoadPersonalNotes(_bookId));
            await tester.pumpWidget(
              MultiBlocProvider(
                providers: [
                  BlocProvider<TextBookBloc>.value(value: readerBloc),
                  BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
                  BlocProvider<SettingsBloc>.value(value: settingsBloc),
                ],
                child: MaterialApp(
                  locale: const Locale('he'),
                  supportedLocales: const [Locale('he')],
                  localizationsDelegates: const [
                    ...GlobalMaterialLocalizations.delegates,
                    quill.FlutterQuillLocalizations.delegate,
                  ],
                  home: Scaffold(
                    body: SimpleTextViewer(
                      content: const [_verseHtml],
                      fontSize: 20,
                      openBookCallback: (_) {},
                      isMainText: true,
                      notesRepository: repository,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            final htmlWidgets = find.descendant(
              of: find.byType(SimpleTextViewer),
              matching: find.byType(HtmlWidget),
            );
            expect(htmlWidgets, forceHtml ? findsWidgets : findsNothing);

            final start = _wordGeometry(
              tester,
              removeMarks ? 'הבכים' : _firstWord,
            );
            final end = _wordGeometry(
              tester,
              removeMarks ? 'ויאמר' : _lastWord,
            );
            expect(end.end.dy, greaterThan(start.start.dy));
            final drag = await tester.startGesture(
              start.start,
              kind: PointerDeviceKind.mouse,
            );
            await tester.pump();
            await drag.moveTo(end.end);
            await tester.pump();
            await drag.up();
            await tester.pumpAndSettle();

            final selections = readerBloc.selections
                .where((event) => event.text?.isNotEmpty == true)
                .toList();
            expect(
              selections,
              isNotEmpty,
              reason: 'The mouse drag selected text',
            );
            final selection = selections.last;
            expect(normalizeAnchorText(selection.text!), _selectedAnchor);
            expect(selection.sectionIndex, 0);

            // Use the reader's real context-menu action, retaining the real
            // selection. No selectedText/sourceSelectedText is injected.
            final rightClick = await tester.startGesture(
              start.inside,
              kind: PointerDeviceKind.mouse,
              buttons: kSecondaryMouseButton,
            );
            await tester.pump();
            await rightClick.up();
            await tester.pumpAndSettle();
            expect(find.text('הערה'), findsOneWidget);
            await tester.tap(find.text('הערה'));
            await tester.pumpAndSettle();
            expect(find.byType(PersonalNoteEditorDialog), findsOneWidget);

            final editor = tester.widget<quill.QuillEditor>(
              find.byType(quill.QuillEditor),
            );
            const noteBody = 'הערה על המעבר בתוך הפסוק';
            editor.controller.replaceText(
              0,
              0,
              noteBody,
              TextSelection.collapsed(offset: noteBody.length),
            );
            await tester.pump();
            await tester.tap(find.widgetWithText(ActionButton, 'שמור'));
            await tester.pumpAndSettle();
            expect(find.byType(PersonalNoteEditorDialog), findsNothing);
            expect(database.rows, hasLength(1));

            // The expected offsets come directly from the pinned verse,
            // independently of the production source mapper/anchor locator.
            final rawStart = _verseHtml.indexOf(_firstWord);
            final rawEnd = _verseHtml.indexOf(_lastWord) + _lastWord.length;
            expect(repository.createdAtLine, 1);
            expect(
              normalizeAnchorText(repository.selectedText!),
              _selectedAnchor,
            );
            expect(repository.sourceText, isNotNull);
            expect(repository.sourceText, startsWith(_firstWord));
            expect(repository.sourceText, endsWith(_lastWord));
            expect(
              normalizeAnchorText(repository.sourceText!),
              _selectedAnchor,
            );
            // No HTML precedes the first word, so source-text and raw HTML
            // offsets coincide here even when the displayed marks are hidden.
            expect(repository.sourceOffset, rawStart);
            final stored = (await database.loadNotes(_bookId)).single;
            expect(stored.anchorText, _selectedAnchor);
            expect(stored.anchorStart, rawStart);
            expect(stored.anchorEnd, rawEnd);
            expect(stored.isWordAnchored, isTrue);

            // A fresh service reads a JSON round trip and reconciles location.
            final reopened = (await PersonalNotesService(
              database: database,
            ).loadNotes(bookId: _bookId, bookContent: _verseHtml)).single;
            expect(reopened.status, PersonalNoteStatus.located);
            expect(reopened.lineNumber, 1);
            expect(reopened.anchorText, _selectedAnchor);
            expect(reopened.anchorStart, rawStart);
            expect(reopened.anchorEnd, rawEnd);
            expect(reopened.anchorStart, greaterThan(0));
            expect(reopened.anchorEnd, lessThan(_verseHtml.length));
            expect(reopened.contentPlain, noteBody);
            expect(tester.takeException(), isNull);
          } finally {
            try {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.binding.setSurfaceSize(null);
            } finally {
              SmartTextWidget.debugForceHtmlWidget = false;
              debugDefaultTargetPlatformOverride = previousPlatform;
            }
          }
        },
      );
    }
  }
}

({Offset start, Offset end, Offset inside}) _wordGeometry(
  WidgetTester tester,
  String word,
) {
  final text = find.descendant(
    of: find.byType(SimpleTextViewer),
    matching: find.byType(RichText),
  );
  for (final element in text.evaluate()) {
    final paragraph = element.findRenderObject();
    if (paragraph is! RenderParagraph) continue;
    final start = paragraph.text.toPlainText().indexOf(word);
    if (start < 0) continue;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + word.length),
    );
    expect(boxes, isNotEmpty);
    final first = boxes.first.toRect();
    final last = boxes.last.toRect();
    final startCaret = paragraph.getOffsetForCaret(
      TextPosition(offset: start),
      Rect.zero,
    );
    final endCaret = paragraph.getOffsetForCaret(
      TextPosition(
        offset: start + word.length,
        affinity: TextAffinity.upstream,
      ),
      Rect.zero,
    );
    return (
      start: paragraph.localToGlobal(
        Offset(startCaret.dx - .1, first.center.dy),
      ),
      end: paragraph.localToGlobal(Offset(endCaret.dx + .1, last.center.dy)),
      inside: paragraph.localToGlobal(first.center),
    );
  }
  throw TestFailure('The reader did not render the requested word: $word');
}

class _NotesDatabase extends Fake implements PersonalNotesDatabase {
  final rows = <Map<String, dynamic>>[];

  @override
  Future<void> insertNote(PersonalNote note) async => rows.add(note.toJson());

  @override
  Future<List<PersonalNote>> loadNotes(String bookId) async => rows
      .map(PersonalNote.fromJson)
      .where((note) => note.bookId == bookId)
      .toList();

  @override
  Future<void> batchUpdateNotes(List<PersonalNote> notes) async {
    for (final note in notes) {
      rows[rows.indexWhere((row) => row['id'] == note.id)] = note.toJson();
    }
  }
}

class _NotesRepository extends PersonalNotesRepository {
  _NotesRepository(this.database)
    : service = PersonalNotesService(database: database);

  final _NotesDatabase database;
  final PersonalNotesService service;
  String? selectedText;
  String? sourceText;
  int? sourceOffset;
  int? createdAtLine;

  @override
  Future<List<PersonalNote>> loadNotes(String bookId, {int? categoryId}) =>
      service.loadNotes(bookId: bookId, bookContent: _verseHtml);

  @override
  Future<List<PersonalNote>> loadStoredNotes(String bookId) =>
      database.loadNotes(bookId);

  @override
  Future<PersonalNote> createNote({
    required String bookId,
    required int lineNumber,
    required String content,
    required String contentPlain,
    required PersonalNoteContentFormat contentFormat,
    String? selectedText,
    int? selectionColumn,
    String? sourceSelectedText,
    int? sourceSelectionOffset,
    bool punctuationHidden = false,
    PdfNoteAnchor? pdfAnchor,
    int? categoryId,
  }) {
    this.selectedText = selectedText;
    sourceText = sourceSelectedText;
    sourceOffset = sourceSelectionOffset;
    createdAtLine = lineNumber;
    return service.createNote(
      bookId: bookId,
      bookContent: _verseHtml,
      lineNumber: lineNumber,
      content: content,
      contentPlain: contentPlain,
      contentFormat: contentFormat,
      selectedText: selectedText,
      selectionColumn: selectionColumn,
      sourceSelectedText: sourceSelectedText,
      sourceSelectionOffset: sourceSelectionOffset,
      punctuationHidden: punctuationHidden,
      pdfAnchor: pdfAnchor,
    );
  }
}

TextBookLoaded _loadedState(bool removeMarks) => TextBookLoaded(
  book: TextBook(title: _bookId),
  showLeftPane: false,
  content: const [_verseHtml],
  fontSize: 20,
  showSplitView: false,
  showPageShapeView: true,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  linksByLine: const {},
  tableOfContents: const [],
  isTanach: true,
  displayOverrides: TextDisplayLayer({
    TextDisplaySlot.root: TextDisplayPatch(
      nikud: removeMarks ? MarkVisibility.hide : MarkVisibility.show,
      teamim: removeMarks ? TeamimVisibility.hide : TeamimVisibility.show,
    ),
  }),
  visibleIndices: const [0],
  selectedIndex: 0,
  pinLeftPane: false,
  searchText: '',
);

class _ReaderBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _ReaderBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  final selections = <UpdateSelectedTextForNote>[];

  @override
  final TextBookRepository repository = _ReaderRepository();

  @override
  void onEvent(TextBookEvent event) {
    super.onEvent(event);
    if (event is UpdateSelectedTextForNote) selections.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReaderRepository extends Fake implements TextBookRepository {
  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];
}

class _SettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _SettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
