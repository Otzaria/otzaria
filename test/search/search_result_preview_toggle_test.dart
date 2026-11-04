import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../test_helpers/memory_cache_provider.dart';

/// תצוגה מקדימה של תוצאת חיפוש: לחיצה אחת פותחת/סוגרת תצוגה מקדימה
/// (previewTarget בטאב), לחיצה כפולה פותחת בעיון, וכשהתצוגה כבויה
/// (לחצן העין) או במסך צר — לחיצה אחת פותחת בעיון כמו קודם.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    final library = Library(categories: const []);
    library.books
      ..add(TextBook(id: 1, title: 'בראשית'))
      ..add(TextBook(id: 2, title: 'יהושע'));
    DataRepository.instance.library = Future.value(library);
  });

  Future<({SearchingTab tab, _RecordingTabsBloc tabsBloc, Finder resultFinder})>
  pumpResults(
    WidgetTester tester, {
    required bool showPreviewPane,
    bool searchShowPreview = true,
    SearchBloc? providedSearchBloc,
  }) async {
    final searchBloc = providedSearchBloc ?? _StaticSearchBloc(_searchState());
    final settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial().copyWith(
        searchShowPreview: searchShowPreview,
      ),
    );
    final tabsBloc = _RecordingTabsBloc();
    final searchingTab = SearchingTab(
      'חיפוש',
      'תדע זרעך',
      searchBloc: searchBloc,
    );

    addTearDown(() async {
      searchingTab.dispose();
      await searchBloc.close();
      await settingsBloc.close();
      await tabsBloc.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SearchBloc>.value(value: searchBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
          ],
          child: Scaffold(
            body: TantivySearchResults(
              tab: searchingTab,
              showPreviewPane: showPreviewPane,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    return (
      tab: searchingTab,
      tabsBloc: tabsBloc,
      resultFinder: find.text('בראשית, פרק טו').first,
    );
  }

  AdaptiveSidePane previewPane(WidgetTester tester) =>
      tester.widget(find.byType(AdaptiveSidePane));

  BookPreviewPanel previewPanel(WidgetTester tester) =>
      tester.widget(find.byType(BookPreviewPanel));

  void expectChoosePrompt(WidgetTester tester) {
    expect(previewPane(tester).isOpen, isTrue);
    expect(previewPanel(tester).book, isNull);
    expect(find.text('בחר תוצאה לתצוגה מקדימה'), findsOneWidget);
  }

  /// לחיצה אחת + המתנה לחלוף חלון הלחיצה הכפולה (אחרת ה-onTap לא יורה)
  /// ולפתרון האסינכרוני של זיהוי הספר.
  Future<void> singleTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, warnIfMissed: false);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('לחיצה אחת פותחת תצוגה מקדימה בלי לפתוח טאב', (tester) async {
    final harness = await pumpResults(tester, showPreviewPane: true);

    await singleTap(tester, harness.resultFinder);

    final target = harness.tab.previewTarget.value;
    expect(target, isNotNull);
    expect(target!.segment, 389);
    expect(target.filePath, 'id:1');
    expect(target.book.title, 'בראשית');
    expect(harness.tabsBloc.openedTabs, isEmpty);
  });

  testWidgets('לחיצה חוזרת על אותה תוצאה סוגרת את התצוגה המקדימה', (
    tester,
  ) async {
    final harness = await pumpResults(tester, showPreviewPane: true);

    await singleTap(tester, harness.resultFinder);
    expect(harness.tab.previewTarget.value, isNotNull);

    await singleTap(tester, harness.resultFinder);
    expect(harness.tab.previewTarget.value, isNull);
    expect(harness.tabsBloc.openedTabs, isEmpty);
  });

  testWidgets('חיפוש חדש אינו מאפשר לפענוח קודם לפתוח תצוגה מקדימה', (
    tester,
  ) async {
    final searchBloc = _DeferredResolutionSearchBloc(_searchState());
    final harness = await pumpResults(
      tester,
      showPreviewPane: true,
      providedSearchBloc: searchBloc,
    );

    final displayResolutionRequests = searchBloc.resolutionRequests;
    await singleTap(tester, harness.resultFinder);
    expect(searchBloc.resolutionRequests, displayResolutionRequests + 1);

    searchBloc.updateState(_searchState(query: 'חיפוש חדש'));
    await tester.pump();
    searchBloc.completeResolution();
    await tester.pump();

    expect(harness.tab.previewTarget.value, isNull);
  });

  testWidgets('סינון בעץ שבצד משאיר את חלונית התצוגה המקדימה (issue #3257)', (
    tester,
  ) async {
    final searchBloc = _StaticSearchBloc(_searchState());
    final harness = await pumpResults(
      tester,
      showPreviewPane: true,
      providedSearchBloc: searchBloc,
    );
    await singleTap(tester, harness.resultFinder);
    final target = harness.tab.previewTarget.value;
    expect(target, isNotNull);

    // צמצום לספר של התוצאה: החיפוש רץ שוב עם הסינון, והתוצאה נשארת מוצגת.
    const genesis = ['/תנ"ך/תורה/בראשית'];
    searchBloc.updateState(
      _searchState(facets: genesis).copyWith(results: [], isLoading: true),
    );
    await tester.pump();
    searchBloc.updateState(_searchState(facets: genesis));
    await tester.pump();
    expect(harness.tab.previewTarget.value, same(target));
    expect(previewPane(tester).isOpen, isTrue);
    expect(previewPanel(tester).book?.title, 'בראשית');

    // מעבר לספר אחר: התוצאה סוננה, והחלונית מבקשת לבחור תוצאה.
    searchBloc.updateState(
      _searchState(facets: const ['/תנ"ך/נביאים/יהושע'], results: [_joshua]),
    );
    await tester.pump();
    expectChoosePrompt(tester);

    // בחירת תוצאה מהספר החדש מציגה אותה.
    await singleTap(tester, find.text('יהושע, פרק כד').first);
    expect(harness.tab.previewTarget.value?.filePath, 'id:2');
    expect(previewPanel(tester).book?.title, 'יהושע');

    // סינון בלי תוצאות כלל.
    searchBloc.updateState(
      _searchState(
        facets: const ['/תנ"ך/כתובים/רות'],
        results: [],
      ).copyWith(totalResults: 0),
    );
    await tester.pump();
    expectChoosePrompt(tester);

    // שאילתה חדשה עדיין סוגרת את התצוגה המקדימה.
    searchBloc.updateState(_searchState(query: 'חיפוש חדש'));
    await tester.pump();
    expect(harness.tab.previewTarget.value, isNull);
    expect(previewPane(tester).isOpen, isFalse);
  });

  testWidgets('סינון בעץ אינו מבטל תצוגה מקדימה שבפתיחה (issue #3257)', (
    tester,
  ) async {
    final searchBloc = _DeferredResolutionSearchBloc(_searchState());
    final harness = await pumpResults(
      tester,
      showPreviewPane: true,
      providedSearchBloc: searchBloc,
    );
    await singleTap(tester, harness.resultFinder);

    searchBloc.updateState(_searchState(facets: const ['/תנ"ך/תורה/בראשית']));
    await tester.pump();
    searchBloc.completeResolution();
    await tester.pump();

    expect(harness.tab.previewTarget.value?.filePath, 'id:1');
    expect(previewPanel(tester).book?.title, 'בראשית');
  });

  testWidgets('לחיצה כפולה פותחת את התוצאה בעיון', (tester) async {
    final harness = await pumpResults(tester, showPreviewPane: true);

    await tester.tap(harness.resultFinder, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(harness.resultFinder, warnIfMissed: false);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(harness.tabsBloc.openedTabs, hasLength(1));
  });

  testWidgets('תצוגה שבפתיחה נבדקת מול הסינון שהסתיים בזמן הפענוח', (
    tester,
  ) async {
    final searchBloc = _DeferredResolutionSearchBloc(_searchState());
    await pumpResults(
      tester,
      showPreviewPane: true,
      providedSearchBloc: searchBloc,
    );
    await singleTap(tester, find.text('בראשית, פרק טו').first);
    searchBloc.updateState(
      _searchState(facets: const ['/יהושע'], results: [_joshua]),
    );
    await tester.pump();
    searchBloc.completeResolution();
    await tester.pump();
    expectChoosePrompt(tester);
  });

  for (final dimension in const ['/author/אחר', '/era/אחר', '/base']) {
    testWidgets('ממד חדש $dimension מסתיר תוצאה שטרם נטענה ושומר אותה לחזרה', (
      tester,
    ) async {
      final searchBloc = _StaticSearchBloc(_searchState());
      final harness = await pumpResults(
        tester,
        showPreviewPane: true,
        providedSearchBloc: searchBloc,
      );
      await singleTap(tester, harness.resultFinder);
      final target = harness.tab.previewTarget.value;
      searchBloc.updateState(
        _searchState(
          facets: ['/', dimension],
          results: [_joshua],
        ).copyWith(totalResults: 2),
      );
      await tester.pump();
      expectChoosePrompt(tester);
      expect(harness.tab.previewTarget.value, same(target));
      searchBloc.updateState(
        _searchState(results: [_joshua]).copyWith(totalResults: 2),
      );
      await tester.pump();
      expect(previewPanel(tester).book?.title, 'בראשית');
    });
  }

  testWidgets('הרחבת OR שומרת התאמה, צמצום OR והוספת ממד דורשים הוכחה', (
    tester,
  ) async {
    const original = ['/', '/author/א', '/author/ב', '/era/תקופה', '/base'];
    final searchBloc = _StaticSearchBloc(_searchState(facets: original));
    final harness = await pumpResults(
      tester,
      showPreviewPane: true,
      providedSearchBloc: searchBloc,
    );
    await singleTap(tester, harness.resultFinder);
    searchBloc.updateState(
      _searchState(
        facets: const [...original, '/author/ג'],
        results: [_joshua],
      ).copyWith(totalResults: 2),
    );
    await tester.pump();
    expect(previewPanel(tester).book?.title, 'בראשית');
    searchBloc.updateState(
      _searchState(
        facets: const ['/', '/author/א'],
        results: [_joshua],
      ).copyWith(totalResults: 2),
    );
    await tester.pump();
    expectChoosePrompt(tester);
    searchBloc.updateState(
      _searchState(
        facets: original,
        results: [_joshua],
      ).copyWith(totalResults: 2),
    );
    await tester.pump();
    expect(previewPanel(tester).book?.title, 'בראשית');
  });

  testWidgets('הגדרות חדשות עם אותה רשימת תוצאות אינן תעודת התאמה לממד', (
    tester,
  ) async {
    final original = _searchState();
    final searchBloc = _DeferredResolutionSearchBloc(original);
    final harness = await pumpResults(
      tester,
      showPreviewPane: true,
      providedSearchBloc: searchBloc,
    );
    searchBloc.updateState(
      original.copyWith(
        configuration: original.configuration.copyWith(
          currentFacets: const ['/', '/author/חדש'],
        ),
      ),
    );
    await tester.pump();
    await singleTap(tester, harness.resultFinder);
    searchBloc.updateState(
      _searchState(
        facets: const ['/', '/author/חדש'],
        results: [_joshua],
      ).copyWith(totalResults: 2),
    );
    await tester.pump();
    searchBloc.completeResolution();
    await tester.pump();
    expectChoosePrompt(tester);
    expect(harness.tab.previewTarget.value!.matchedDimensionFacets, isEmpty);
  });

  testWidgets('החלפת תוצאות באותו אורך ומונה מסנכרנת את התצוגה', (
    tester,
  ) async {
    final searchBloc = _StaticSearchBloc(_searchState());
    final harness = await pumpResults(
      tester,
      showPreviewPane: true,
      providedSearchBloc: searchBloc,
    );
    await singleTap(tester, harness.resultFinder);
    searchBloc.updateState(_searchState(results: [_joshua]));
    await tester.pump();
    expectChoosePrompt(tester);
    searchBloc.updateState(_searchState());
    await tester.pump();
    expect(previewPanel(tester).book?.title, 'בראשית');
  });

  testWidgets('לחיצה מכרטיס קודם אינה מקבלת את ממדי רשימת התוצאות החדשה', (
    tester,
  ) async {
    final searchBloc = _DeferredResolutionSearchBloc(_searchState());
    final harness = await pumpResults(
      tester,
      showPreviewPane: true,
      providedSearchBloc: searchBloc,
    );
    final oldTap = tester
        .widget<InkWell>(
          find
              .ancestor(
                of: harness.resultFinder,
                matching: find.byType(InkWell),
              )
              .first,
        )
        .onTap!;
    searchBloc.updateState(
      _searchState(
        facets: const ['/', '/author/חדש'],
        results: [_joshua],
      ).copyWith(totalResults: 2),
    );
    await tester.pump();
    oldTap();
    searchBloc.completeResolution();
    await tester.pump();
    expectChoosePrompt(tester);
    expect(harness.tab.previewTarget.value!.matchedDimensionFacets, isEmpty);
  });

  testWidgets('ספירה לא סופית אינה הוכחה שהתוצאה אינה בעמודים הבאים', (
    tester,
  ) async {
    final searchBloc = _StaticSearchBloc(_searchState());
    final harness = await pumpResults(
      tester,
      showPreviewPane: true,
      providedSearchBloc: searchBloc,
    );
    await singleTap(tester, harness.resultFinder);
    final counting = _searchState(
      results: [_joshua],
    ).copyWith(isCounting: true);
    searchBloc.updateState(counting);
    await tester.pump();
    expect(previewPanel(tester).book?.title, 'בראשית');
    searchBloc.updateState(counting.copyWith(isCounting: false));
    await tester.pump();
    expectChoosePrompt(tester);
  });

  testWidgets('עדכון מספר הקבוצות בלבד מסנכרן תצוגה מאוחדת', (tester) async {
    final searchBloc = _StaticSearchBloc(_searchState());
    final harness = await pumpResults(
      tester,
      showPreviewPane: true,
      providedSearchBloc: searchBloc,
    );
    await singleTap(tester, harness.resultFinder);
    final grouped = _searchState(results: [_joshua]).copyWith(
      totalResults: 10,
      totalGroups: 2,
    );
    searchBloc.updateState(grouped);
    await tester.pump();
    expect(previewPanel(tester).book?.title, 'בראשית');
    searchBloc.updateState(grouped.copyWith(totalGroups: 1));
    await tester.pump();
    expectChoosePrompt(tester);
  });

  testWidgets('הרכבת המסך מחדש שומרת את הראיה מהממדים המקוריים', (
    tester,
  ) async {
    final searchBloc = _StaticSearchBloc(
      _searchState(facets: const ['/', '/author/א']),
    );
    final harness = await pumpResults(
      tester,
      showPreviewPane: true,
      providedSearchBloc: searchBloc,
    );
    await singleTap(tester, harness.resultFinder);
    final target = harness.tab.previewTarget.value;
    searchBloc.updateState(
      _searchState(
        facets: const ['/', '/author/ב'],
        results: [_joshua],
      ).copyWith(totalResults: 2),
    );
    await tester.pump();
    expectChoosePrompt(tester);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app);
    await tester.pump();
    expectChoosePrompt(tester);
    expect(harness.tab.previewTarget.value, same(target));
    searchBloc.updateState(
      _searchState(
        facets: const ['/', '/author/א'],
        results: [_joshua],
      ).copyWith(totalResults: 2),
    );
    await tester.pump();
    expect(harness.tab.previewTarget.value, same(target));
    expect(target!.matchedDimensionFacets, ['/author/א']);
    expect(harness.tab.filteredOutPreview.value, isNull);
    await tester.pump();
    expect(previewPanel(tester).book?.title, 'בראשית');
  });

  testWidgets('כשהתצוגה המקדימה כבויה בהגדרה — לחיצה אחת פותחת בעיון', (
    tester,
  ) async {
    final harness = await pumpResults(
      tester,
      showPreviewPane: true,
      searchShowPreview: false,
    );

    await singleTap(tester, harness.resultFinder);

    expect(harness.tab.previewTarget.value, isNull);
    expect(harness.tabsBloc.openedTabs, hasLength(1));
  });

  testWidgets('בלי חלונית תצוגה מקדימה (מסך צר) — לחיצה אחת פותחת בעיון', (
    tester,
  ) async {
    final harness = await pumpResults(tester, showPreviewPane: false);

    await singleTap(tester, harness.resultFinder);

    expect(harness.tab.previewTarget.value, isNull);
    expect(harness.tabsBloc.openedTabs, hasLength(1));
  });
}

SearchState _searchState({
  String query = 'תדע זרעך',
  List<String> facets = const ['/'],
  List<SearchResult>? results,
}) => SearchState(
  searchQuery: query,
  configuration: SearchConfiguration(currentFacets: facets),
  totalResults: 1,
  results:
      results ??
      [
        SearchResult(
          id: BigInt.one,
          title: 'בראשית',
          reference: 'בראשית, פרק טו',
          text: 'ידע תדע כי־גר יהיה זרעך',
          segment: BigInt.from(389),
          isPdf: false,
          filePath: 'id:1',
          mergedCount: 1,
          merged: const [],
          textStatus: TextStatus.ok,
          continuesToNextLine: false,
        ),
      ],
);

final _joshua = SearchResult(
  id: BigInt.two,
  title: 'יהושע',
  reference: 'יהושע, פרק כד',
  text: 'ויתן לו את הזרע',
  segment: BigInt.from(650),
  isPdf: false,
  filePath: 'id:2',
  mergedCount: 1,
  merged: const [],
  textStatus: TextStatus.ok,
  continuesToNextLine: false,
);

class _StaticSearchBloc extends SearchBloc {
  _StaticSearchBloc(SearchState initialSearchState) {
    emit(initialSearchState);
  }

  void updateState(SearchState state) => emit(state);

  @override
  void add(SearchEvent event) {}
}

class _DeferredResolutionSearchBloc extends _StaticSearchBloc {
  _DeferredResolutionSearchBloc(super.initialSearchState);

  final Completer<IndexedBookResolution> _resolution = Completer();

  int resolutionRequests = 0;

  void completeResolution() => _resolution.complete(
    (book: TextBook(id: 1, title: 'בראשית'), isStale: false),
  );

  @override
  Future<IndexedBookResolution> resolveBookForIndexedPath(
    String indexedFilePath, {
    required String indexedTitle,
  }) {
    resolutionRequests++;
    return _resolution.future;
  }
}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _RecordingTabsBloc extends Bloc<TabsEvent, TabsState>
    implements TabsBloc {
  _RecordingTabsBloc() : super(TabsState.initial()) {
    on<TabsEvent>((event, emit) {
      if (event is OpenOrFocusTab) {
        openedTabs.add(event.tab);
      }
    });
  }

  final List<Object> openedTabs = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
