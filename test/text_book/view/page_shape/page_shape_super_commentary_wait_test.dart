// בחירה שמורה שאינה בין המפרשים, כשאין מפרש-על אפשרי (#3979), לא נתקעת בטעינה.
import 'dart:io';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/view/page_shape/page_shape_settings_panel.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

import 'package:flutter/material.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
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
import 'package:otzaria/personal_notes/bloc/personal_notes_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
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
import 'package:otzaria/widgets/feedback/loading_indicator.dart';

import '../../../test_helpers/memory_cache_provider.dart';
import '../../../test_helpers/stub_personal_notes_bloc.dart';
import '../../../test_helpers/stub_settings_bloc.dart';

const _content = ['שורה א', 'שורה ב'];
const _columns = ['left', 'right', 'bottom', 'bottomRight'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final root = Directory.systemTemp.createTempSync('page-shape-wait-');
    AppPaths.debugOverrideDataRootPath(root.path);
    addTearDown(() async {
      AppPaths.debugOverrideDataRootPath(null);
      try {
        await root.delete(recursive: true);
      } on FileSystemException {
        // ה-DB עוד פתוח ב-Windows; התיקייה זמנית.
      }
    });
    await Settings.init(cacheProvider: MemoryCacheProvider());
    LibraryProviderManager.instance.resetForTesting();
  });

  tearDown(LibraryProviderManager.instance.resetForTesting);

  /// צורת הדף כשבטור 'left' בלבד נבחר [right] (הפרמטר), ורשימת המפרשים הזמינים
  /// היא [available].
  Future<_TestTextBookBloc> pumpPageShape(
    WidgetTester tester, {
    required String bookTitle,
    required List<String> names,
    required String right,
    required List<String> available,
    required bool commentatorsLoaded,
    ValueNotifier<int>? openSettings,
    int? categoryId,
    List<String>? linkTitles,
    int selectedIndex = 0,
    String column = 'left',
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
      {for (final c in _columns) c: c == column ? right : null},
      columnVisibility: {for (final c in _columns) c: c == column},
    );
    final book = TextBook(title: bookTitle, categoryId: categoryId);
    final bloc = _TestTextBookBloc(
      _state(book, linkTitles ?? names, available, commentatorsLoaded).copyWith(
        selectedIndex: selectedIndex,
        visibleIndices: [selectedIndex],
      ),
    );
    final settings = StubSettingsBloc(SettingsState.initial());
    final notes = StubPersonalNotesBloc(const PersonalNotesState.initial());
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
              openSettingsNotifier: openSettings,
              defaultsLoader: (book, available) async => (
                commentators: <String, String?>{
                  for (final c in _columns) c: c == column ? right : null,
                },
                visibility: <String, bool>{
                  for (final c in _columns) c: c == column,
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

  testWidgets(
    'מפרש שמור שאינו ברשימה, בלי מפרש-על אפשרי, אינו נתקע בטעינה אינסופית',
    (
      tester,
    ) async {
      const stale = 'מפרש ישן';
      final bloc = await pumpPageShape(
        tester,
        bookTitle: 'ספר בלי מפרשים',
        names: const [stale],
        right: stale,
        available: const [],
        commentatorsLoaded: false,
      );
      // הרשימה מגיעה ריקה, כלומר זהה למה שהיה: רק commentatorsLoaded משתנה.
      bloc.publish(
        (bloc.state as TextBookLoaded).copyWith(commentatorsLoaded: true),
      );
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(LoadingIndicator), findsNothing);
      expect(
        PageShapeSettingsManager.loadConfiguration('ספר בלי מפרשים')?['left'],
        stale,
      );
    },
  );
  testWidgets('שאר המפרשים אינו נשלח לגילוי כספר או כמפרש על', (tester) async {
    final fixture = await tester.runAsync(
      () => _createSuperCommentaryFixture(
        superTitle: pageShapeRemainingCommentatorsValue,
      ),
    );
    addTearDown(() async {
      await DatabaseLibraryProvider.instance.sqliteProvider.dispose();
      SqliteDataProvider.instance.keepWalJournal = false;
      await fixture!.delete(recursive: true);
    });
    final openSettings = ValueNotifier<int>(0);
    addTearDown(openSettings.dispose);
    await pumpPageShape(
      tester,
      bookTitle: 'שולחן ערוך, אורח חיים',
      names: const ['משנה ברורה', pageShapeRemainingCommentatorsValue],
      right: pageShapeRemainingCommentatorsValue,
      available: const ['משנה ברורה'],
      commentatorsLoaded: true,
      categoryId: 61,
      linkTitles: const ['משנה ברורה'],
      openSettings: openSettings,
    );
    openSettings.value++;
    await _pumpUntil(
      tester,
      () => find.byType(PageShapeSettingsPanel).evaluate().isNotEmpty,
    );
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    final panel = tester.widget<PageShapeSettingsPanel>(
      find.byType(PageShapeSettingsPanel),
    );
    expect(panel.superCommentatorParents, isEmpty);
    await _finishDbReads(tester);
  });

  for (final column in ['left', 'bottom', 'bottomRight']) {
    for (final restoreOnly in [false, true]) {
      testWidgets(
        restoreOnly
            ? 'משחזר מפרש על יחיד בטור $column בלי אב נבחר או מטמון קודם'
            : 'החלפת האב היחיד במפרש העל המוצע משמרת את הטור $column',
        (tester) async {
          final openSettings = ValueNotifier<int>(0);
          addTearDown(openSettings.dispose);
          final fixture = await tester.runAsync(_createSuperCommentaryFixture);
          addTearDown(() async {
            await DatabaseLibraryProvider.instance.sqliteProvider.dispose();
            SqliteDataProvider.instance.keepWalJournal = false;
            await fixture!.delete(recursive: true);
          });
          await PageShapeSettingsManager.saveHighlightSetting(
            'שולחן ערוך, אורח חיים',
            true,
          );
          await pumpPageShape(
            tester,
            bookTitle: 'שולחן ערוך, אורח חיים',
            names: const ['משנה ברורה', 'שער הציון'],
            right: restoreOnly ? 'שער הציון' : 'משנה ברורה',
            openSettings: openSettings,
            categoryId: 61,
            column: column,
            linkTitles: const ['משנה ברורה'],
            selectedIndex: 1,
            available: const ['משנה ברורה'],
            commentatorsLoaded: true,
          );
          for (var i = 0; i < 25; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
          openSettings.value++;
          await _pumpUntil(
            tester,
            () => find.byType(PageShapeSettingsPanel).evaluate().isNotEmpty,
          );
          for (var i = 0; i < 25; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
          AppDropdownField<String> field() =>
              tester.widget<AppDropdownField<String>>(
                find.descendant(
                  of: find
                      .ancestor(
                        of: find.text(
                          switch (column) {
                            'left' => 'מפרש ימני',
                            'bottom' => 'מפרש תחתון',
                            _ => 'מפרש תחתון נוסף',
                          },
                        ),
                        matching: find.byType(Row),
                      )
                      .first,
                  matching: find.byType(AppDropdownField<String>),
                ),
              );
          expect(field().entries.map((e) => e.value), contains('שער הציון'));
          expect(
            find.byWidgetPredicate(
              (w) => w is SimpleTextViewer && !w.isMainText,
            ),
            findsOneWidget,
          );
          if (!restoreOnly) field().onSelected!('שער הציון');
          for (var i = 0; i < 40; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(
            PageShapeSettingsManager.loadConfiguration(
              'שולחן ערוך, אורח חיים',
            )?[column],
            'שער הציון',
          );
          expect(
            find.byWidgetPredicate(
              (w) => w is SimpleTextViewer && !w.isMainText,
            ),
            findsOneWidget,
            reason:
                'the offered super-commentary must not disappear when replacing its parent',
          );
          final viewer = tester.widget<SimpleTextViewer>(
            find.byWidgetPredicate(
              (w) => w is SimpleTextViewer && !w.isMainText,
            ),
          );
          expect(viewer.bookTitle, 'שער הציון');
          expect(viewer.highlightedIndices, contains(1));
          await _finishDbReads(tester);
        },
      );
    }
  }
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

/// קריאת ה-worker רצה ב-isolate אמיתי, אבל ה-timeout שלה הוא טיימר מזויף;
/// בלי להמתין לה, הטיימר נשאר תלוי בסוף הבדיקה כשה-CI איטי.
Future<void> _finishDbReads(WidgetTester tester) async {
  final deadline = Stopwatch()..start();
  while (DbReadWorker.hasPendingReads &&
      deadline.elapsed < const Duration(seconds: 10)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(DbReadWorker.hasPendingReads, isFalse);
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

Future<Directory> _createSuperCommentaryFixture({
  String superTitle = 'שער הציון',
}) async {
  final dir = await Directory.systemTemp.createTemp(
    'super-commentary-graph-',
  );
  final path = '${dir.path}/seforim.db';
  final database = MyDatabase.withPath(path);
  final repository = SeforimRepository(database);
  await repository.ensureInitialized();
  final db = await database.database;
  db.execute(
    "INSERT INTO category (id,title,level) VALUES (61,'ראשי',0),(703,'מפרשים',0)",
  );
  db.execute("INSERT INTO source (id,name) VALUES (1,'test')");
  for (final entry in [
    (1, 'שולחן ערוך, אורח חיים', 61),
    (2, 'משנה ברורה', 703),
    (3, superTitle, 703),
  ]) {
    db.execute(
      "INSERT INTO book (id,categoryId,sourceId,title,orderIndex,totalLines,filePath,fileType) VALUES (?,?,1,?,1,2,'','txt')",
      [entry.$1, entry.$3, entry.$2],
    );
    for (var i = 0; i < 2; i++) {
      db.execute(
        'INSERT INTO line (id,bookId,lineIndex,content,heRef) VALUES (?,?,?,?,?)',
        [
          entry.$1 * 100 + i,
          entry.$1,
          i,
          '${entry.$2} שורה $i',
          '${entry.$2} $i',
        ],
      );
    }
  }
  db.execute(
    'INSERT INTO link (sourceBookId,sourceLineId,targetLineId,targetBookId,connectionTypeId) VALUES (1,101,201,2,2),(2,201,301,3,2)',
  );
  db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  db.execute('PRAGMA journal_mode=DELETE');
  database.close();
  final provider = DatabaseLibraryProvider.instance;
  await provider.sqliteProvider.dispose();
  provider.sqliteProvider.keepWalJournal = true;
  await Settings.setValue<String>(
    SettingsRepository.keyDbEffectivePath,
    path,
  );
  await provider.initialize();
  expect(
    provider.sqliteProvider.repository!.database.isReadOnly,
    isTrue,
  );
  return dir;
}
