import 'dart:io';

import 'package:flutter/material.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/book_composite_key.dart';
import 'package:otzaria/data/data_providers/library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
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

import '../../../helpers/seforim_fixture_db.dart';
import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_navigation_bloc.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';
import '../../../test_helpers/stub_tabs_bloc.dart';

const _content = ['שורה א', 'שורה ב'];
const _columns = ['left', 'right', 'bottom', 'bottomRight'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('page-shape-retry-');
    AppPaths.debugOverrideDataRootPath(root.path);
    addTearDown(() async {
      await ErrorLogFile.flushPending();
      AppPaths.debugOverrideDataRootPath(null);
      LibraryProviderManager.instance.resetForTesting();
      await root.delete(recursive: true);
    });
    await Settings.init(cacheProvider: MemoryCacheProvider());
    LibraryProviderManager.instance.resetForTesting();
  });

  testWidgets('כשל זמני במפרש מתאושש וטור שהוסתר נטען שוב', (tester) async {
    final temporary = _FakeCommentaryProvider('מפרש זמני')..textFailures = 1;
    await _pumpPageShape(
      tester,
      temporary,
      bookTitle: 'ספר א',
      columns: const {'left', 'right'},
    );
    await _pumpUntil(tester, () => _commentaryViewer().evaluate().length == 2);
    expect(_commentaryViewer(), findsNWidgets(2));
    expect(temporary.reads, 2);

    final unavailable = _FakeCommentaryProvider('מפרש שהיה עסוק')
      ..textFailures = 2;
    await _pumpPageShape(tester, unavailable, bookTitle: 'ספר ב');
    await _pumpUntil(tester, () => unavailable.reads >= 2);
    final layout = tester.state(find.byType(PageShapeScreen));
    await _pumpUntil(
      tester,
      () => find.text('מפרש שהיה עסוק').evaluate().isEmpty,
    );
    expect(unavailable.reads, 2);
    expect(_commentaryViewer(), findsNothing);
    (layout as PageShapeColumnsControl).showHiddenColumns();
    await _pumpUntil(tester, () => _commentaryViewer().evaluate().isNotEmpty);
    expect(_commentaryViewer(), findsOneWidget);
    expect(unavailable.reads, 3);

    final missing = _FakeCommentaryProvider('מפרש חסר')..missing = true;
    await _pumpPageShape(tester, missing, bookTitle: 'ספר ג');
    await _pumpUntil(tester, () => missing.reads != 0);
    await _pumpUntil(tester, () => find.text('מפרש חסר').evaluate().isEmpty);
    expect(missing.reads, 1);
    expect(_commentaryViewer(), findsNothing);
    missing.missing = false;
    (tester.state(find.byType(PageShapeScreen)) as PageShapeColumnsControl)
        .showHiddenColumns();
    await _pumpUntil(tester, () => _commentaryViewer().evaluate().isNotEmpty);
    expect(_commentaryViewer(), findsOneWidget);
    expect(missing.reads, 2);

    final closed = _FakeCommentaryProvider('מפרש שנסגר')..textFailures = 1;
    await _pumpPageShape(tester, closed, bookTitle: 'ספר ד');
    await _pumpUntil(tester, () => closed.reads != 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(closed.reads, 1);
  });

  testWidgets('כשל אמיתי בקריאת SQLite נשמר באבחון וניתן לטעון שוב', (
    tester,
  ) async {
    final path = SeforimFixtureDb.create(root, SeforimFixtureVariant.full);
    final writer = sqlite3.open(path);
    writer.execute('ALTER TABLE line RENAME TO saved_line');
    final sqlite = SqliteDataProvider.instance;
    addTearDown(() async {
      writer.close();
      DbReadWorker.disposeForTesting();
      await sqlite.dispose();
      sqlite.keepWalJournal = false;
    });
    await tester.runAsync(() async {
      sqlite.keepWalJournal = true;
      await Settings.setValue(SettingsRepository.keyDbEffectivePath, path);
      await sqlite.initialize();
    });
    const commentator = SeforimFixtureIds.rashiTitle;
    await _pumpPageShape(
      tester,
      _FakeCommentaryProvider(commentator),
      bookTitle: 'ספר עם מפרש רשמי',
    );
    await _pumpUntil(tester, () => find.text(commentator).evaluate().isEmpty);
    expect(_commentaryViewer(), findsNothing);
    await tester.runAsync(ErrorLogFile.flushPending);
    expect(
      File(ErrorLogFile.resolvePath()).readAsStringSync(),
      allOf(contains('כשל בטעינת מפרש בצורת הדף'), contains('no such table')),
    );

    writer.execute('ALTER TABLE saved_line RENAME TO line');
    (tester.state(find.byType(PageShapeScreen)) as PageShapeColumnsControl)
        .showHiddenColumns();
    await _pumpUntil(tester, () => _commentaryViewer().evaluate().isNotEmpty);
    expect(tester.widget<SimpleTextViewer>(_commentaryViewer()).content, [
      'דיבור ראשון',
      'דיבור שני',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpUntil(tester, () => !DbReadWorker.hasPendingReads);
    expect(DbReadWorker.hasPendingReads, isFalse);
  });

  test('מסד מצורף שלא נפתח זמנית מדווח על כשל ונקרא לאחר מכן', () async {
    final path = SeforimFixtureDb.create(root, SeforimFixtureVariant.full);
    final previousRegistry = AttachedLibraryRegistry.instance;
    final previousOpenCheck = AttachedLibraryRegistry.openCheck;
    final registry = AttachedLibraryRegistry(idleTimeout: null);
    AttachedLibraryRegistry.instance = registry;
    registry.update([
      AttachedLibrary(
        slug: 'commentary',
        displayName: 'מפרשים מצורפים',
        path: path,
        addedAt: DateTime(2026),
      ),
    ]);
    var attempts = 0;
    AttachedLibraryRegistry.openCheck = (_, _) async => ++attempts > 1;
    addTearDown(() async {
      AttachedLibraryRegistry.openCheck = previousOpenCheck;
      AttachedLibraryRegistry.instance = previousRegistry;
      await registry.closeAll();
    });
    final source = BookSource.attached('commentary');
    Future<ResolvedDbBookRecord?> resolve() => BookDatabaseResolver.resolveBook(
      title: SeforimFixtureIds.rashiTitle,
      preferSource: source,
      throwIfUnavailable: true,
    );
    await expectLater(resolve(), throwsStateError);
    final record = (await resolve())!;
    final text = await DatabaseLibraryProvider.instance.readResolvedBookText(
      record,
    );
    expect(text, 'דיבור ראשון\nדיבור שני');
    expect(attempts, 2);

    final writer = sqlite3.open(path);
    try {
      writer.execute('DROP TABLE line');
      await expectLater(
        DatabaseLibraryProvider.instance.readResolvedBookText(record),
        throwsA(
          predicate((error) => error.toString().contains('no such table')),
        ),
      );
    } finally {
      writer.close();
    }
  });
}

Finder _commentaryViewer() => find.byWidgetPredicate(
  (widget) => widget is SimpleTextViewer && !widget.isMainText,
);

Future<void> _pumpPageShape(
  WidgetTester tester,
  _FakeCommentaryProvider provider, {
  required String bookTitle,
  Set<String> columns = const {'right'},
}) async {
  final commentator = provider.title;
  tester.view.physicalSize = const Size(1800, 1000);
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
    {for (final c in _columns) c: columns.contains(c) ? commentator : null},
    columnVisibility: {for (final c in _columns) c: columns.contains(c)},
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
                  c: columns.contains(c) ? commentator : null,
              },
              visibility: <String, bool>{
                for (final c in _columns) c: columns.contains(c),
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
  searchText: '',
);

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCommentaryProvider extends Fake implements LibraryProvider {
  _FakeCommentaryProvider(this.title);

  final String title;
  int textFailures = 0;
  int reads = 0;
  bool missing = false;

  @override
  String get displayName => 'Fake';

  @override
  bool get isInitialized => true;

  @override
  int get priority => 0;

  @override
  String get providerId => 'fake';

  @override
  Future<List<Link>> getAllLinksForBook(
    String title,
    int categoryId,
    String fileType,
  ) async => const [];

  @override
  Future<Set<String>> getAvailableBookTitles() async => {'$title|1|txt'};

  @override
  Future<String?> getBookText(
    String title,
    int categoryId,
    String fileType, {
    BookSource preferSource = BookSource.official,
  }) async {
    reads++;
    if (textFailures > 0) {
      textFailures--;
      throw const DbReadWorkerBusy('test commentary load');
    }
    if (missing) return null;
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
}
