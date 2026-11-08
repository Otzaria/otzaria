// הטור שמפתחו 'right' בצורת הדף לא מציג "בחר מפרש" בזמן שרשימת המפרשים
// עוד נטענת (issue #3156).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
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
import 'package:otzaria/text_book/view/page_shape/page_shape_screen.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';

import '../../../test_helpers/memory_cache_provider.dart';

const _content = ['שורה א', 'שורה ב'];
const _columns = ['left', 'right', 'bottom', 'bottomRight'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final root = Directory.systemTemp.createTempSync('page-shape-wait-');
    AppPaths.debugOverrideDataRootPath(root.path);
    addTearDown(() async {
      AppPaths.debugOverrideDataRootPath(null);
      await root.delete(recursive: true);
    });
    await Settings.init(cacheProvider: MemoryCacheProvider());
    LibraryProviderManager.instance.resetForTesting();
  });

  tearDown(LibraryProviderManager.instance.resetForTesting);

  Finder commentaryViewer() => find.byWidgetPredicate(
    (widget) => widget is SimpleTextViewer && !widget.isMainText,
  );

  /// צורת הדף כשבטור 'right' בלבד נבחר [right], ורשימת המפרשים הזמינים
  /// היא [available].
  Future<_TestTextBookBloc> pumpPageShape(
    WidgetTester tester, {
    required String bookTitle,
    required List<String> names,
    required String right,
    required List<String> available,
    required bool commentatorsLoaded,
  }) async {
    tester.view.physicalSize = const Size(2400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final provider = _FakeLibraryProvider(names);
    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        for (final title in names)
          BookCompositeKey.create(
            title: title,
            categoryId: 1,
            fileType: 'txt',
          ): provider,
      },
      providers: [provider],
    );

    await PageShapeSettingsManager.saveConfiguration(
      bookTitle,
      {for (final c in _columns) c: c == 'right' ? right : null},
      columnVisibility: {for (final c in _columns) c: c == 'right'},
    );
    final book = TextBook(title: bookTitle);
    final bloc = _TestTextBookBloc(
      _state(book, names, available, commentatorsLoaded),
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

    await tester.pumpWidget(const SizedBox.shrink());
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
                  for (final c in _columns) c: c == 'right' ? right : null,
                },
                visibility: <String, bool>{
                  for (final c in _columns) c: c == 'right',
                },
              ),
            ),
          ),
        ),
      ),
    );
    // הטקסט הראשי מוצג רק אחרי שהגדרת הטורים נטענה.
    await _pumpUntil(
      tester,
      () => find
          .byWidgetPredicate((w) => w is SimpleTextViewer && w.isMainText)
          .evaluate()
          .isNotEmpty,
    );
    await tester.pump();
    return bloc;
  }

  // תרחיש אחד לקובץ: אתחול המסד שמתחיל בבדיקת צורת הדף נשאר תלוי באזור
  // הזמן שלה, ובדיקה נוספת בקובץ הייתה ממתינה לו לנצח.
  testWidgets('טור המפרשים לא מציג "בחר מפרש" לפני שהרשימה נטענה '
      '(issue #3156)', (tester) async {
    // בחירה ללא רשימה ממתינה לאימות לפני טעינת תוכן המפרש.
    const single = ['מפרש יחיד'];
    final singleBloc = await pumpPageShape(
      tester,
      bookTitle: 'ספר יחיד',
      names: single,
      right: single.first,
      available: const [],
      commentatorsLoaded: false,
    );
    await _pumpUntil(tester, () => commentaryViewer().evaluate().isNotEmpty);
    expect(commentaryViewer(), findsNothing);
    expect(find.byType(LoadingIndicator), findsOneWidget);
    expect(find.text('בחר מפרש'), findsNothing);
    singleBloc.publish(
      (singleBloc.state as TextBookLoaded).copyWith(
        availableCommentators: single,
        commentatorsLoaded: true,
      ),
    );
    await _pumpUntil(tester, () => commentaryViewer().evaluate().isNotEmpty);
    expect(
      tester.widget<SimpleTextViewer>(commentaryViewer()).bookTitle,
      single.first,
    );
    expect(find.text('בחר מפרש'), findsNothing);

    // כמה מפרשים: מצב טעינה עד שהרשימה מגיעה.
    const multi = ['מפרש ראשון', 'מפרש שני'];
    final multiSelection = encodePageShapeCommentatorsSelection(
      multi,
      forceMultipleMode: true,
    )!;
    await pumpPageShape(
      tester,
      bookTitle: 'ספר כמה מפרשים',
      names: multi,
      right: multiSelection,
      available: const [],
      commentatorsLoaded: false,
    );
    expect(find.byType(LoadingIndicator), findsOneWidget);
    expect(find.text('בחר מפרש'), findsNothing);

    // ספר שנטען ואין לו מפרשים: לא נתקע בטעינה.
    await pumpPageShape(
      tester,
      bookTitle: 'ספר בלי מפרשים',
      names: multi,
      right: multiSelection,
      available: const [],
      commentatorsLoaded: true,
    );
    expect(find.byType(LoadingIndicator), findsNothing);
    expect(find.text('בחר מפרש'), findsOneWidget);

    for (final available in [
      const ['מפרש מתאים'],
      const <String>[],
    ]) {
      const stale = 'מפרש זר';
      final bookTitle = 'בחירה ישנה ${available.length}';
      final bloc = await pumpPageShape(
        tester,
        bookTitle: bookTitle,
        names: [stale, ...available],
        right: stale,
        available: const [],
        commentatorsLoaded: false,
      );
      await _pumpUntil(tester, () => commentaryViewer().evaluate().isNotEmpty);
      expect(commentaryViewer(), findsNothing);
      expect(find.byType(LoadingIndicator), findsOneWidget);
      bloc.publish(
        (bloc.state as TextBookLoaded).copyWith(
          availableCommentators: available,
          commentatorsLoaded: true,
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('בחר מפרש').evaluate().isNotEmpty,
      );
      expect(commentaryViewer(), findsNothing);
      expect(find.text('בחר מפרש'), findsOneWidget);
      expect(
        PageShapeSettingsManager.loadConfiguration(bookTitle)?['right'],
        stale,
      );
    }

    const valid = 'מפרש קיים';
    final validBloc = await pumpPageShape(
      tester,
      bookTitle: 'בחירה תקפה',
      names: const [valid],
      right: valid,
      available: const [valid],
      commentatorsLoaded: false,
    );
    await _pumpUntil(tester, () => commentaryViewer().evaluate().isNotEmpty);
    final viewerState = tester.state(commentaryViewer());
    for (final available in [
      const [valid],
      const [valid, 'מפרש נוסף'],
    ]) {
      validBloc.publish(
        (validBloc.state as TextBookLoaded).copyWith(
          availableCommentators: available,
          commentatorsLoaded: true,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.state(commentaryViewer()), same(viewerState));
      expect(
        tester.widget<SimpleTextViewer>(commentaryViewer()).bookTitle,
        valid,
      );
    }
    validBloc.publish(
      (validBloc.state as TextBookLoaded).copyWith(
        availableCommentators: const ['מפרש אחר'],
      ),
    );
    await _pumpUntil(tester, () => commentaryViewer().evaluate().isEmpty);
    expect(commentaryViewer(), findsNothing);
    expect(
      PageShapeSettingsManager.loadConfiguration('בחירה תקפה')?['right'],
      valid,
    );

    final savedMulti = encodePageShapeCommentatorsSelection(
      const [valid, 'מפרש זר'],
      forceMultipleMode: true,
    )!;
    final multiBloc = await pumpPageShape(
      tester,
      bookTitle: 'בחירה מרובה שמורה',
      names: const [valid, 'מפרש זר'],
      right: savedMulti,
      available: const [],
      commentatorsLoaded: false,
    );
    expect(find.byType(LoadingIndicator), findsOneWidget);
    multiBloc.publish(
      (multiBloc.state as TextBookLoaded).copyWith(
        availableCommentators: const [valid],
        commentatorsLoaded: true,
      ),
    );
    await _pumpUntil(
      tester,
      () => find.byType(CommentaryListBase).evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<CommentaryListBase>(find.byType(CommentaryListBase))
          .selectedCommentatorsOverride,
      const [valid],
    );
    expect(
      PageShapeSettingsManager.loadConfiguration('בחירה מרובה שמורה')?['right'],
      savedMulti,
    );
    tester
        .widget<CommentaryListBase>(find.byType(CommentaryListBase))
        .onSelectedCommentatorsOverrideChanged!(const []);
    await _pumpUntil(
      tester,
      () => tester
          .widget<CommentaryListBase>(find.byType(CommentaryListBase))
          .selectedCommentatorsOverride!
          .isEmpty,
    );
    expect(find.byType(CommentaryListBase), findsOneWidget);
    expect(
      PageShapeSettingsManager.loadConfiguration('בחירה מרובה שמורה')?['right'],
      pageShapeMultipleCommentatorsModeValue,
    );

    // R7-4: המחוון "גודל גופן מפרשים (צורת הדף)" בהגדרות התצוגה הכלליות
    // שומר בלי לבנות את המסך מחדש. גם הטור הימני במצב "מפרשים מרובים"
    // מתעדכן מיד, כמו הטורים שמתחת.
    double listFontSize() => tester
        .widget<CommentaryListBase>(find.byType(CommentaryListBase))
        .fontSize;
    final resized = listFontSize() + 4;
    await tester.runAsync(
      () => PageShapeSettingsManager.saveCommentaryFontSize(resized),
    );
    await tester.pump();
    expect(listFontSize(), resized);
  });
}

/// טעינת טור מפרש עוברת דרך Isolate.run, ולכן ממתינים בזמן אמת עד לתנאי.
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Link _link(String title, int line) => Link(
  heRef: '$title ${line + 1}',
  index1: line + 1,
  path2: '$title.txt',
  index2: line + 1,
  connectionType: LinkTypes.commentary,
  targetCategoryId: 1,
  targetFileType: 'txt',
);

TextBookLoaded _state(
  TextBook book,
  List<String> names,
  List<String> available,
  bool commentatorsLoaded,
) => TextBookLoaded(
  book: book,
  showLeftPane: false,
  content: _content,
  fontSize: 18,
  showSplitView: false,
  showPageShapeView: true,
  activeCommentators: names,
  commentatorGroups: const [],
  availableCommentators: available,
  commentatorsLoaded: commentatorsLoaded,
  links: [
    for (var line = 0; line < _content.length; line++)
      for (final title in names) _link(title, line),
  ],
  visibleLinks: const [],
  linksByLine: {
    for (var line = 0; line < _content.length; line++)
      line + 1: [for (final title in names) _link(title, line)],
  },
  tableOfContents: const [],
  visibleIndices: const [0],
  selectedIndex: 0,
  pinLeftPane: false,
  searchText: '',
);

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

class _FakeLibraryProvider implements LibraryProvider {
  _FakeLibraryProvider(this.titles);

  final List<String> titles;

  @override
  String get displayName => 'Fake';

  @override
  bool get isInitialized => true;

  @override
  int get priority => 0;

  @override
  String get providerId => 'fake';

  @override
  String get sourceIndicator => 'T';

  @override
  Future<Library> buildLibraryCatalog(
    Map<String, Map<String, dynamic>> metadata,
    String rootPath,
  ) async => throw UnimplementedError();

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async => const [];

  @override
  Future<Set<String>> getAvailableBookTitles() async => {
    for (final title in titles) '$title|1|txt',
  };

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => '$title שורה 1\n$title שורה 2';

  @override
  Future<List<TocEntry>?> getBookToc(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async => const [];

  @override
  Future<String> getLinkContent(Link link) async => '';

  @override
  Future<bool> hasBook(String title, int categoryId, String fileType) async =>
      true;

  @override
  Future<void> initialize() async {}

  @override
  Future<Map<String, List<Book>>> loadBooks(
    Map<String, Map<String, dynamic>> metadata,
  ) async => const {};
}
