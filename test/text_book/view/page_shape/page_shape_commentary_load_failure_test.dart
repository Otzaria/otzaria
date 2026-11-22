// טור מפרש שטעינתו נכשלה בצורת הדף אינו נתקע: כשל זמני לא נשמר במטמון,
// והחלונית מציעה "נסה שוב" (issue #5744).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
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
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_screen.dart';
import 'package:otzaria/text_book/view/page_shape/simple_text_viewer.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_navigation_bloc.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';
import '../../../test_helpers/stub_tabs_bloc.dart';

const _content = ['שורה א', 'שורה ב'];
const _columns = ['left', 'right', 'bottom', 'bottomRight'];
const _commentator = 'מפרש זמני';
const _failedMessage = 'לא ניתן לטעון את $_commentator';
const _retry = 'נסה שוב';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final root = Directory.systemTemp.createTempSync('page-shape-failure-');
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

  Future<_TestTextBookBloc> pumpPageShape(
    WidgetTester tester,
    _FakeLibraryProvider provider, {
    required String bookTitle,
  }) async {
    final commentator = provider.titles.single;
    tester.view.physicalSize = const Size(2400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    LibraryProviderManager.instance.seedMappingsForTesting(
      mapping: {
        BookCompositeKey.create(
          title: commentator,
          categoryId: 1,
          fileType: 'txt',
        ): provider,
      },
      providers: [provider],
    );

    await PageShapeSettingsManager.saveConfiguration(
      bookTitle,
      {for (final c in _columns) c: c == 'right' ? commentator : null},
      columnVisibility: {for (final c in _columns) c: c == 'right'},
    );
    final book = TextBook(title: bookTitle);
    final bloc = _TestTextBookBloc(_state(book, commentator));
    final settings = StubSettingsBloc(SettingsState.initial());
    final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
    final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
    final tabs = StubTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    final navigation = StubNavigationBloc(
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
                  for (final c in _columns)
                    c: c == 'right' ? commentator : null,
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
  testWidgets('כשל זמני בטעינת מפרש מציע "נסה שוב" ואינו נשמר במטמון '
      '(issue #5744)', (tester) async {
    // חריגה זמנית: הטור נשאר עם הודעה וכפתור, והלחיצה טוענת את המפרש.
    final provider = _FakeLibraryProvider(const [_commentator])
      ..textFailures = 1;
    await pumpPageShape(tester, provider, bookTitle: 'ספר א');
    await _pumpUntil(tester, () => provider.textFailures == 0);
    await _pumpUntil(tester, () => false);
    expect(find.text(_failedMessage), findsOneWidget);
    expect(find.text(_retry), findsOneWidget);
    await tester.runAsync(ErrorLogFile.flushPending);
    expect(
      File(ErrorLogFile.resolvePath()).readAsStringSync(),
      contains('database is locked'),
    );
    await tester.tap(find.text(_retry));
    await _pumpUntil(tester, () => commentaryViewer().evaluate().isNotEmpty);
    expect(find.text(_failedMessage), findsNothing);
    expect(
      tester.widget<SimpleTextViewer>(commentaryViewer()).bookTitle,
      _commentator,
    );

    // טקסט ריק: הטור מוסתר כמקודם, אבל הכשל אינו נשמר במטמון — פתיחה
    // מחדש של הספר טוענת את המפרש.
    const missing = 'מפרש ריק';
    final empty = _FakeLibraryProvider(const [missing])..emptyTexts = 1;
    await pumpPageShape(tester, empty, bookTitle: 'ספר ב');
    await _pumpUntil(tester, () => empty.emptyTexts == 0);
    await _pumpUntil(tester, () => false);
    expect(find.text('לא ניתן לטעון את $missing'), findsNothing);
    expect(commentaryViewer(), findsNothing);
    await pumpPageShape(tester, empty, bookTitle: 'ספר ב');
    await _pumpUntil(tester, () => commentaryViewer().evaluate().isNotEmpty);
    expect(
      tester.widget<SimpleTextViewer>(commentaryViewer()).bookTitle,
      missing,
    );
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

TextBookLoaded _state(TextBook book, String commentator) => TextBookLoaded(
  book: book,
  showLeftPane: false,
  content: _content,
  fontSize: 18,
  showSplitView: false,
  showPageShapeView: true,
  activeCommentators: [commentator],
  commentatorGroups: const [],
  availableCommentators: [commentator],
  commentatorsLoaded: true,
  links: [
    for (var line = 0; line < _content.length; line++) _link(commentator, line),
  ],
  visibleLinks: const [],
  linksByLine: {
    for (var line = 0; line < _content.length; line++)
      line + 1: [_link(commentator, line)],
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

class _FakeLibraryProvider implements LibraryProvider {
  _FakeLibraryProvider(this.titles);

  final List<String> titles;

  /// מספר הקריאות הבאות לטקסט המפרש שייכשלו (כשל זמני של המסד).
  int textFailures = 0;

  /// מספר הקריאות הבאות שיחזירו טקסט ריק.
  int emptyTexts = 0;

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
  }) async {
    if (titles.contains(title) && textFailures > 0) {
      textFailures--;
      throw StateError('database is locked');
    }
    if (titles.contains(title) && emptyTexts > 0) {
      emptyTexts--;
      return '';
    }
    return '$title שורה 1\n$title שורה 2';
  }

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
