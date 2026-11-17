import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/utils/file/page_converter.dart';
import 'package:otzaria/utils/file/page_map_builder.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/resolving_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';

import '../helpers/memory_settings_cache.dart';

class _RecordingTabsBloc extends Fake implements TabsBloc {
  final added = <TabsEvent>[];

  @override
  TabsState get state => TabsState.initial();

  @override
  Stream<TabsState> get stream => const Stream.empty();

  @override
  void add(TabsEvent event) => added.add(event);
}

class _MemoryTabsRepository extends TabsRepository {
  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {}
  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {}
}

class _MappedTractate extends TextBook {
  _MappedTractate(Category category)
    : super(title: 'ברכות', id: 103, category: category, categoryId: 10);
  @override
  Future<List<TocEntry>> get tableOfContents async {
    final root = TocEntry(text: 'ברכות', index: 0);
    root.children = [
      TocEntry(text: 'דף ב.', index: 1, level: 2, parent: root),
      TocEntry(text: 'דף ב:', index: 16, level: 2, parent: root),
    ];
    return [root];
  }
}

class _RecordingHistoryBloc extends Fake implements HistoryBloc {
  final added = <HistoryEvent>[];
  List<Bookmark> entries = [];

  @override
  String? get currentWorkspaceName => null;

  @override
  String? get currentWorkspaceId => null;

  @override
  HistoryState get state => HistoryLoaded(entries);

  @override
  Stream<HistoryState> get stream => const Stream.empty();

  @override
  void add(HistoryEvent event) => added.add(event);
}

class _RecordingNavigationBloc extends Fake implements NavigationBloc {
  final added = <NavigationEvent>[];

  @override
  Stream<NavigationState> get stream => const Stream.empty();

  @override
  void add(NavigationEvent event) => added.add(event);
}

Category _category(String title, {Category? parent}) {
  final category = Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: [],
    books: [],
    parent: parent,
  );
  parent?.subCategories.add(category);
  return category;
}

/// ספרייה עם מסכת ברכות: מהדורת טקסט תחת סדר זרעים, ואופציונלית PDF נלווה.
({Library library, TextBook text}) _buildLibrary({
  bool withPdf = true,
  String suffix = '',
}) {
  final bavliRoot = _category('תלמוד בבלי');
  final seder = _category('סדר זרעים', parent: bavliRoot);
  final text = _MappedTractate(seder);
  seder.books.add(text);
  if (withPdf) {
    bavliRoot.books.add(
      PdfBook(
        title: 'ברכות',
        path: 'C:/books/תלמוד בבלי/ברכות$suffix.pdf',
        category: bavliRoot,
      ),
    );
  }
  return (library: Library(categories: [bavliRoot]), text: text);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingTabsBloc tabsBloc;
  late _RecordingHistoryBloc historyBloc;
  late _RecordingNavigationBloc navigationBloc;
  TabsBloc? realTabsBloc;
  late BuildContext capturedContext;

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    tabsBloc = _RecordingTabsBloc();
    historyBloc = _RecordingHistoryBloc();
    navigationBloc = _RecordingNavigationBloc();
    final temp = await Directory.systemTemp.createTemp('bavli_open_test');
    final previousDataRoot = AppPaths.cachedDataRootPath;
    AppPaths.debugOverrideDataRootPath(temp.path);
    addTearDown(() async {
      await CacheDatabaseHolder.instance.close();
      AppPaths.debugOverrideDataRootPath(previousDataRoot);
      await temp.delete(recursive: true);
    });
  });

  Future<bool> run(
    WidgetTester tester,
    Book book,
    int index, {
    bool? forcePdf,
    bool navigateToPositionIfReused = false,
  }) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: realTabsBloc ?? tabsBloc),
          BlocProvider<HistoryBloc>.value(value: historyBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
        ],
        child: Builder(
          builder: (ctx) {
            capturedContext = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return (await tester.runAsync(
      () => openLibraryBookPerTalmudBavliFormat(
        capturedContext,
        book,
        index,
        forcePdf: forcePdf,
        navigateToPositionIfReused: navigateToPositionIfReused,
      ),
    ))!;
  }

  group('openLibraryBookPerTalmudBavliFormat', () {
    testWidgets('הגדרת PDF: מסכת טקסט בלי מיקום נפתחת כ-PDF בדף 1', (
      tester,
    ) async {
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      final built = _buildLibrary();
      DataRepository.instance.library = Future.value(built.library);

      final handled = await run(tester, built.text, 0);

      expect(handled, isTrue);
      final event = tabsBloc.added.single as OpenOrFocusTab;
      final tab = event.tab as PdfBookTab;
      expect(tab.book.title, 'ברכות');
      expect(tab.pageNumber, 1);
      expect(
        navigationBloc.added.single,
        isA<NavigateToScreen>().having(
          (e) => e.screen,
          'screen',
          Screen.reading,
        ),
      );
    });

    testWidgets('פתיחת PDF רגילה עדיין משחזרת מיקום מההיסטוריה', (
      tester,
    ) async {
      final built = _buildLibrary();
      final pdf =
          built.library.getCompanionBook(built.text, PdfBook) as PdfBook;
      DataRepository.instance.library = Future.value(built.library);
      historyBloc.entries = [Bookmark(book: pdf, index: 9, ref: 'ברכות')];
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      expect(await run(tester, built.text, 0), isTrue);
      final event = tabsBloc.added.single as OpenOrFocusTab;
      expect(event.navigateToPositionIfReused, isFalse);
      expect((event.tab as PdfBookTab).pageNumber, 9);
      event.tab.dispose();
    });

    testWidgets('הגדרת PDF עם מיקום מפורש: נפתח טאב-טעינה עם מיפוי עמוד', (
      tester,
    ) async {
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      final built = _buildLibrary();
      DataRepository.instance.library = Future.value(built.library);

      final handled = await run(tester, built.text, 7);

      expect(handled, isTrue);
      final event = tabsBloc.added.single as OpenOrFocusTab;
      final tab = event.tab as ResolvingTab;
      expect(
        tab.fallbackTab,
        isA<TextBookTab>().having((t) => t.book.title, 'title', 'ברכות'),
      );
    });

    testWidgets('מיקום מפורש ממופה ל-PDF ומנווט באותה מסכת פתוחה', (
      tester,
    ) async {
      final built = _buildLibrary();
      final pdf =
          built.library.getCompanionBook(built.text, PdfBook) as PdfBook;
      DataRepository.instance.library = Future.value(built.library);
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      pdfAnchorsReaderForTesting = (_) async => [
        (page: 1, ref: 'ברכות'),
        (page: 2, ref: 'ברכות/דף ב.'),
        (page: 3, ref: 'ברכות/דף ב:'),
      ].map((a) => (page: a.page, ref: normalizeRef(a.ref))).toList();
      final bloc = realTabsBloc = TabsBloc(
        repository: _MemoryTabsRepository(),
        disposeDelay: Duration.zero,
      );
      final existing = PdfBookTab(book: pdf, pageNumber: 2);
      addTearDown(() async {
        realTabsBloc = null;
        pdfAnchorsReaderForTesting = null;
        await bloc.close();
        await tester.pump();
      });
      bloc.add(AddTab(existing));
      await tester.pumpAndSettle();
      final handled = await run(
        tester,
        built.text,
        16,
        navigateToPositionIfReused: true,
      );
      await tester.pumpAndSettle();
      expect(handled, isTrue);
      expect(bloc.state.tabs, [same(existing)]);
      expect(existing.pageNumber, 3);
      // שתי לחיצות לאותו ספר עדיין עוברות בסמנטיקת OpenOrFocusTab.
      await tester.runAsync(() async {
        await Future.wait([
          openLibraryBookPerTalmudBavliFormat(
            capturedContext,
            built.text,
            1,
            navigateToPositionIfReused: true,
          ),
          openLibraryBookPerTalmudBavliFormat(
            capturedContext,
            built.text,
            16,
            navigateToPositionIfReused: true,
          ),
        ]);
      });
      await tester.pumpAndSettle();
      expect(bloc.state.tabs, [same(existing)]);
      expect(existing.pageNumber, 3);
      historyBloc.entries = [Bookmark(book: pdf, index: 9, ref: 'ברכות')];
      await run(tester, built.text, 0, navigateToPositionIfReused: true);
      await tester.pumpAndSettle();
      expect(bloc.state.tabs, [same(existing)]);
      expect(existing.pageNumber, 1);
    });

    testWidgets('מיפוי שמסתיים אחרי הסרת המסך אינו פותח ספר', (tester) async {
      final built = _buildLibrary(suffix: '-disposed');
      DataRepository.instance.library = Future.value(built.library);
      // יצירת context בלי להתחיל מיפוי.
      await run(tester, built.text, 0);
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      late Completer<List<({int page, String ref})>> anchors;
      addTearDown(() => pdfAnchorsReaderForTesting = null);
      late Future<bool> opening;
      await tester.runAsync(() async {
        final started = Completer<void>();
        anchors = Completer<List<({int page, String ref})>>();
        pdfAnchorsReaderForTesting = (_) {
          started.complete();
          return anchors.future;
        };
        opening = openLibraryBookPerTalmudBavliFormat(
          capturedContext,
          built.text,
          16,
          navigateToPositionIfReused: true,
        );
        await started.future;
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        anchors.complete([]);
        expect(await opening, isTrue);
      });
      expect(tabsBloc.added, isEmpty);
      expect(navigationBloc.added, isEmpty);
    });

    testWidgets('שורת אפס מפורשת נשמרת גם ב-fallback טקסט עם היסטוריה', (
      tester,
    ) async {
      final built = _buildLibrary(suffix: '-unmapped');
      DataRepository.instance.library = Future.value(built.library);
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      historyBloc.entries = [
        Bookmark(book: built.text, index: 16, ref: 'ברכות דף ב:'),
      ];
      pdfAnchorsReaderForTesting = (_) async => [];
      addTearDown(() => pdfAnchorsReaderForTesting = null);
      await run(tester, built.text, 0, navigateToPositionIfReused: true);
      final event = tabsBloc.added.single as OpenOrFocusTab;
      expect(event.navigateToPositionIfReused, isTrue);
      expect(event.tab, isA<TextBookTab>());
      expect((event.tab as TextBookTab).index, 0);
      event.tab.dispose();
    });

    testWidgets('הגדרת טקסט (ברירת מחדל): הפתיחה לא מטופלת — נשארת רגילה', (
      tester,
    ) async {
      final built = _buildLibrary();
      DataRepository.instance.library = Future.value(built.library);

      final handled = await run(tester, built.text, 0);

      expect(handled, isFalse);
      expect(tabsBloc.added, isEmpty);
      expect(navigationBloc.added, isEmpty);
    });

    testWidgets('הגדרת PDF אך אין מהדורת PDF בספרייה: fallback לפתיחה רגילה', (
      tester,
    ) async {
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      final built = _buildLibrary(withPdf: false);
      DataRepository.instance.library = Future.value(built.library);

      final handled = await run(tester, built.text, 0);

      expect(handled, isFalse);
      expect(tabsBloc.added, isEmpty);
    });

    testWidgets('forcePdf גובר על הגדרת הטקסט — המסכת נפתחת כ-PDF', (
      tester,
    ) async {
      final built = _buildLibrary();
      DataRepository.instance.library = Future.value(built.library);

      final handled = await run(tester, built.text, 0, forcePdf: true);

      expect(handled, isTrue);
      final tab = (tabsBloc.added.single as OpenOrFocusTab).tab as PdfBookTab;
      expect(tab.book.title, 'ברכות');
      expect(tab.pageNumber, 1);
    });

    testWidgets('forcePdf=false גובר על הגדרת ה-PDF — הפתיחה לא מטופלת', (
      tester,
    ) async {
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      final built = _buildLibrary();
      DataRepository.instance.library = Future.value(built.library);

      final handled = await run(tester, built.text, 0, forcePdf: false);

      expect(handled, isFalse);
      expect(tabsBloc.added, isEmpty);
    });

    testWidgets('forcePdf בלי מהדורת PDF: הפתיחה לא מטופלת', (tester) async {
      final built = _buildLibrary(withPdf: false);
      DataRepository.instance.library = Future.value(built.library);

      final handled = await run(tester, built.text, 0, forcePdf: true);

      expect(handled, isFalse);
      expect(tabsBloc.added, isEmpty);
    });

    testWidgets('ספר שאינו טקסט (PDF) לא מנותב — נפתח כרגיל', (tester) async {
      await Settings.setValue(
        SettingsRepository.keyTalmudBavliOpenFormat,
        'pdf',
      );
      final built = _buildLibrary();
      DataRepository.instance.library = Future.value(built.library);
      final pdf = PdfBook(
        title: 'ברכות',
        path: r'C:\books\תלמוד בבלי\ברכות.pdf',
      );

      final handled = await run(tester, pdf, 1);

      expect(handled, isFalse);
      expect(tabsBloc.added, isEmpty);
    });
  });
}
