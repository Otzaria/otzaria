import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:otzaria/plugins/services/context_menu_registry.dart';
// ignore: depend_on_referenced_packages
import 'package:super_native_extensions/src/native/context.dart';
// ignore: depend_on_referenced_packages
import 'package:irondash_message_channel/irondash_message_channel.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:otzaria/text_book/view/selection/selected_text_copy.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/models/commentator_group.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_screen.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_notes_column.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';

import '../../../test_helpers/memory_cache_provider.dart';

const _content = [
  '<h2>פרק ראשון</h2>',
  'שורה ב',
  'שורה ג',
  'שורה ד',
  'שורה ה',
  'שורה ו',
  '<h2>פרק שני</h2>',
  'שורה ח',
];
const _columns = ['left', 'right', 'bottom', 'bottomRight'];

BookNotes _notes() {
  final builder = BookNotesBuilder()
    ..add(0, 0, 'א', 'הערה ראשונה על שורה א')
    ..add(0, 1, null, 'הערה שנייה על שורה א')
    ..add(7, 0, 'ב', '<b>הערה על שורה ח</b>');
  return builder.build();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final paragraphProviders = <dynamic>[];
  setUpAll(() {
    final native = superNativeExtensionsContext as MockMessageChannelContext;
    native.registerMockMethodCallHandler('DataProviderManager', (call) async {
      if (call.method == 'registerDataProvider') {
        paragraphProviders.add(call.arguments['representations']);
        return paragraphProviders.length;
      }
      return null;
    });
    native.registerMockMethodCallHandler('ClipboardWriter', (_) async => null);
  });

  setUp(() async {
    final root = Directory.systemTemp.createTempSync('page-shape-notes-');
    AppPaths.debugOverrideDataRootPath(root.path);
    addTearDown(() async {
      AppPaths.debugOverrideDataRootPath(null);
      await root.delete(recursive: true);
    });
    await Settings.init(cacheProvider: MemoryCacheProvider());
    LibraryProviderManager.instance.resetForTesting();
  });

  tearDown(LibraryProviderManager.instance.resetForTesting);

  test('כל הערה היא שורה בטור, מקושרת לשורת המקור שלה לפי הסדר', () {
    final column = buildPageShapeNotesColumn(_content, _notes());
    expect(column.content, hasLength(3));
    expect(column.content[0], contains('הערה ראשונה על שורה א'));
    expect(column.content[1], contains('הערה שנייה על שורה א'));
    expect(column.content[2], contains('הערה על שורה ח'));
    expect(
      [for (final link in column.links) (link.index1, link.index2)],
      [(1, 1), (1, 2), (8, 3)],
    );
  });

  testWidgets('"הערות" שנבחר לטור מציג את הערות הספר (issues #3400, #3507)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const bookTitle = 'חברותא על ברכות';
    await PageShapeSettingsManager.saveConfiguration(
      bookTitle,
      {
        for (final c in _columns)
          c: c == 'left' ? kNotesCommentatorTitle : null,
      },
      columnVisibility: {for (final c in _columns) c: c == 'left'},
    );
    await Settings.setValue<bool>('page_shape_global_highlight', true);
    final book = TextBook(title: bookTitle);
    final bloc = _TestTextBookBloc(
      TextBookLoaded(
        book: book,
        showLeftPane: false,
        content: _content,
        fontSize: 18,
        showSplitView: false,
        showPageShapeView: true,
        activeCommentators: const [kNotesCommentatorTitle],
        commentatorGroups: const [
          CommentatorGroup(
            title: 'שאר מפרשים',
            commentators: [kNotesCommentatorTitle],
          ),
        ],
        availableCommentators: const [kNotesCommentatorTitle],
        commentatorsLoaded: true,
        links: const [],
        visibleLinks: const [],
        linksByLine: const {},
        tableOfContents: const [],
        visibleIndices: const [0],
        selectedIndex: 7,
        pinLeftPane: false,
        searchText: '',
        bookNotes: _notes(),
      ),
    );
    final settings = _TestSettingsBloc(
      SettingsState.initial().copyWith(
        copyWithHeaders: 'book_and_path',
        copyHeaderFormat: 'separate_line_before',
      ),
    );
    final notes = _TestPersonalNotesBloc(const PersonalNotesState.initial());
    final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
    final tabs = _TestTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    final navigation = _TestNavigationBloc(
      const NavigationState(currentScreen: Screen.reading),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bloc.close();
      await settings.close();
      await notes.close();
      await tabs.close();
      await navigation.close();
      tab.dispose();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: bloc),
          BlocProvider<SettingsBloc>.value(value: settings),
          BlocProvider<PersonalNotesBloc>.value(value: notes),
          BlocProvider<TabsBloc>.value(value: tabs),
          BlocProvider<NavigationBloc>.value(value: navigation),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PageShapeScreen(
              openBookCallback: (_) {},
              tab: tab,
              defaultsLoader: (book, available) async => (
                commentators: <String, String?>{
                  for (final c in _columns) c: null,
                },
                visibility: <String, bool>{for (final c in _columns) c: true},
              ),
            ),
          ),
        ),
      ),
    );

    Finder notesViewer() => find.byWidgetPredicate(
      (widget) =>
          widget is SimpleTextViewer &&
          !widget.isMainText &&
          widget.bookTitle == kNotesCommentatorTitle,
    );
    await _pumpUntil(tester, () => notesViewer().evaluate().isNotEmpty);

    expect(notesViewer(), findsOneWidget);
    final viewer = tester.widget<SimpleTextViewer>(notesViewer());
    expect(viewer.content, hasLength(3));
    expect(viewer.content.last, contains('הערה על שורה ח'));
    expect(viewer.highlightedIndices, {2});
    expect(viewer.isBookNotesColumn, isTrue);

    // טעינת טווח תוכן ברקע מחליפה את הרשימה בלי לשנות הערות: הטור לא נבנה מחדש.
    bloc.publish(
      (bloc.state as TextBookLoaded).copyWith(content: List.of(_content)),
    );
    await tester.pump();
    await tester.pump();
    expect(
      tester.widget<SimpleTextViewer>(notesViewer()).content,
      same(viewer.content),
    );

    Future<void> openNoteMenu() async {
      final rect = tester.getRect(
        find
            .descendant(
              of: notesViewer(),
              matching: find.textContaining('הערה על שורה ח'),
            )
            .first,
      );
      final gesture = await tester.startGesture(
        rect.center,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    ContextMenuRegistry.instance.registerPayload('notes-column-test', {
      'id': 'action',
      'title': 'פעולת מפרש לתוסף',
      'contexts': ['reader-commentary', 'reader-commentary-selection'],
    });
    addTearDown(
      () => ContextMenuRegistry.instance.removeAll('notes-column-test'),
    );
    await openNoteMenu();
    expect(find.text('פעולת מפרש לתוסף'), findsNothing);
    expect(find.text('הוסף הערה אישית '), findsNothing);
    await tester.tap(find.text('העתק את כל הפסקה'));
    await tester.pumpAndSettle();
    final expectedParagraph = await Formats.plainText(
      'חברותא על ברכות, פרק שני\nב הערה על שורה ח',
    );
    expect(
      paragraphProviders.last.first,
      expectedParagraph.representations.single.serialize(),
    );

    final copied = <({String plainText, String htmlText})>[];
    debugSelectedTextCopyHandler = copied.add;
    addTearDown(() => debugSelectedTextCopyHandler = null);
    SelectableRegion selectionRegion() => tester.widget<SelectableRegion>(
      find.descendant(
        of: notesViewer(),
        matching: find.byType(SelectableRegion),
      ),
    );
    selectionRegion().onSelectionChanged?.call(
      const SelectedContent(plainText: 'הערה על שורה ח'),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(copied.single.plainText, contains('חברותא על ברכות, פרק שני'));
    expect(copied.single.htmlText, contains('<b>'));

    selectionRegion().onSelectionChanged?.call(null);
    await tester.pumpAndSettle();
    await openNoteMenu();
    await tester.tap(find.text('דווח על טעות בספר'));
    await _pumpUntil(
      tester,
      () => find.byType(TabbedReportDialog).evaluate().isNotEmpty,
    );
    final dialog = tester.widget<TabbedReportDialog>(
      find.byType(TabbedReportDialog),
    );
    expect(dialog.bookTitle, bookTitle);
    expect(dialog.currentLineNumber, 8);
    expect(dialog.selectedText, 'ב הערה על שורה ח');
    Navigator.of(tester.element(find.byType(TabbedReportDialog))).pop();
    await tester.pumpAndSettle();

    bloc.publish((bloc.state as TextBookLoaded).copyWith(selectedIndex: 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SimpleTextViewer>(notesViewer()).highlightedIndices,
      {0, 1},
      reason: 'הערות על כותרת שייכות לכותרת עצמה, בלי דילוג לשורת הגוף',
    );

    final movedNotes =
        (BookNotesBuilder()
              ..add(1, 0, 'א', 'הערה ראשונה על שורה א')
              ..add(1, 1, null, 'הערה שנייה על שורה א')
              ..add(7, 0, 'ב', '<b>הערה על שורה ח</b>'))
            .build();
    bloc.publish(
      (bloc.state as TextBookLoaded).copyWith(
        selectedIndex: 1,
        bookNotes: movedNotes,
      ),
    );
    await tester.pumpAndSettle();
    final movedViewer = tester.widget<SimpleTextViewer>(notesViewer());
    expect(movedViewer.content, same(viewer.content));
    expect(movedViewer.highlightedIndices, {0, 1});
    expect(movedViewer.sourceIndexForIndex!(0), 1);
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  void publish(TextBookState state) => emit(state);

  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPersonalNotesBloc
    extends Bloc<PersonalNotesEvent, PersonalNotesState>
    implements PersonalNotesBloc {
  _TestPersonalNotesBloc(super.initialState) {
    on<PersonalNotesEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState) {
    on<TabsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestNavigationBloc extends Bloc<NavigationEvent, NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc(super.initialState) {
    on<NavigationEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
