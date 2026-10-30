// טור "הערות" בצורת הדף מציג את הערות הספר עצמו — גם כשאין לספר מפרש
// מקושר אחר (issues #3400, #3507).
import 'dart:io';

import 'package:flutter/material.dart';
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

const _content = ['שורה א', 'שורה ב', 'שורה ג'];
const _columns = ['left', 'right', 'bottom', 'bottomRight'];

BookNotes _notes() {
  final builder = BookNotesBuilder()
    ..add(0, 0, 'א', 'הערה ראשונה על שורה א')
    ..add(0, 1, null, 'הערה שנייה על שורה א')
    ..add(2, 0, 'ב', 'הערה על שורה ג');
  return builder.build();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    expect(column.content[2], contains('הערה על שורה ג'));
    expect(
      [for (final link in column.links) (link.index1, link.index2)],
      [(1, 1), (1, 2), (3, 3)],
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
        selectedIndex: 2,
        pinLeftPane: false,
        searchText: '',
        bookNotes: _notes(),
      ),
    );
    final settings = _TestSettingsBloc(SettingsState.initial());
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
    expect(viewer.content.last, contains('הערה על שורה ג'));
    // השורה הנבחרת (ג) מדגישה את ההערה שלה בטור.
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
