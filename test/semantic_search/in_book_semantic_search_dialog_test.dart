import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/search_scope_preferences.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/view/in_book_advanced_search_dialog.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';

import '../test_helpers/memory_cache_provider.dart';
import 'semantic_test_support.dart';

class _MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class _MockIndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockTabsBloc extends MockBloc<TabsEvent, TabsState>
    implements TabsBloc {}

class _FakeTabsEvent extends Fake implements TabsEvent {}

class _FakeNavigationEvent extends Fake implements NavigationEvent {}

/// מאגר מוכן לחיפוש, שהספרים המכוסים שלו נקבעים בבדיקה.
class _CoveredRepository extends SemanticSearchRepository {
  _CoveredRepository(this.covered)
    : super(
        backend: FakeBackend(),
        consent: () => FakeConsentStore(),
        settings: FakeSettingsStore(),
      );

  Set<String>? covered;

  /// כשמוגדר, התשובה מגיעה רק כשהוא מושלם.
  Completer<void>? answerGate;
  static const _ready = SemanticAvailability(
    phase: SemanticAvailabilityPhase.ready,
    consentGranted: true,
  );

  @override
  SemanticAvailability get availability => _ready;

  @override
  Stream<SemanticAvailability> get availabilityChanges => const Stream.empty();

  @override
  Future<SemanticAvailability> refresh() async => _ready;

  @override
  Future<Set<String>?> loadCoveredBookFilePaths() async {
    await answerGate?.future;
    return covered;
  }
}

final _semanticSegment = find.byKey(
  const ValueKey('search-dialog-semantic-mode'),
);
final _queryField = find.byKey(const ValueKey('semantic-query-field'));

void main() {
  final book = TextBook(title: 'בראשית', id: 1);
  final library = Library(
    categories: [
      Category(
        title: 'תנ״ך',
        description: '',
        shortDescription: '',
        order: 1,
        subCategories: [],
        books: [
          book,
          TextBook(title: 'שמות', id: 2),
        ],
        parent: null,
      ),
    ],
  );
  final bookFacet = FacetHelper.buildBookFacet(
    FacetHelper.resolveCategoryPath(book),
    book,
  );
  final coveredBook = {BookIdentity.indexedFilePath(book)};

  setUpAll(() {
    registerFallbackValue(_FakeTabsEvent());
    registerFallbackValue(_FakeNavigationEvent());
  });

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    SearchDefaults.rememberSessionSemantic(false);
  });

  tearDown(UiSnack.hide);

  Future<
    ({
      _MockTabsBloc tabs,
      _MockNavigationBloc navigation,
      _CoveredRepository repository,
      List<SearchDialogResult?> results,
    })
  >
  pumpInBookDialog(
    WidgetTester tester,
    Set<String>? covered, {
    bool inBook = true,
    Completer<void>? answerGate,
    Book? openBook,
  }) async {
    final history = _MockHistoryBloc();
    final indexing = _MockIndexingBloc();
    final navigation = _MockNavigationBloc();
    final libraryBloc = _MockLibraryBloc();
    final tabs = _MockTabsBloc();
    whenListen(
      history,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([]),
    );
    whenListen(
      indexing,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      navigation,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.reading),
    );
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(library: library),
    );
    whenListen(
      tabs,
      const Stream<TabsState>.empty(),
      initialState: const TabsState(tabs: [], currentTabIndex: 0),
    );
    addTearDown(() async {
      await history.close();
      await indexing.close();
      await navigation.close();
      await libraryBloc.close();
      await tabs.close();
    });

    const settings = InBookSearchSettings();
    final tab = createInBookSearchDialogTab(
      query: '',
      searchMode: settings.searchMode,
      distance: settings.distance,
      matchPolicy: settings.requestedMatchPolicy,
      searchOptions: settings.searchOptions,
      alternativeWords: settings.alternativeWords,
      spacingValues: settings.spacingValues,
    );
    addTearDown(tab.dispose);
    final results = <SearchDialogResult?>[];
    final repository = _CoveredRepository(covered)..answerGate = answerGate;

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<HistoryBloc>.value(value: history),
          BlocProvider<IndexingBloc>.value(value: indexing),
          BlocProvider<NavigationBloc>.value(value: navigation),
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
          BlocProvider<TabsBloc>.value(value: tabs),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => GestureDetector(
                key: const ValueKey('launch'),
                behavior: HitTestBehavior.opaque,
                onTap: () async => results.add(
                  await showDialog<SearchDialogResult>(
                    context: context,
                    builder: (_) => MediaQuery(
                      data: const MediaQueryData(size: Size(1280, 900)),
                      child: inBook
                          ? SearchDialog(
                              existingTab: tab,
                              bookTitle: (openBook ?? book).title,
                              returnResultOnSubmit: true,
                              semanticBook: openBook ?? book,
                              semanticRepository: repository,
                              semanticDebugPreview: false,
                            )
                          : SearchDialog(
                              semanticRepository: repository,
                              semanticDebugPreview: false,
                            ),
                    ),
                  ),
                ),
                child: const SizedBox(width: 40, height: 40),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('launch')));
    await tester.pumpAndSettle();
    return (
      tabs: tabs,
      navigation: navigation,
      repository: repository,
      results: results,
    );
  }

  testWidgets('ספר עם וקטורים: המצב החכם מוצע, אבל לא נבחר מעצמו', (
    tester,
  ) async {
    SearchDefaults.rememberSessionSemantic(true);
    await pumpInBookDialog(tester, coveredBook);
    expect(_semanticSegment, findsOneWidget);
    expect(_queryField, findsNothing);
  });

  testWidgets('המצב החכם מופיע בדיאלוג הפתוח כשהתשובה מגיעה', (tester) async {
    final gate = Completer<void>();
    await pumpInBookDialog(tester, coveredBook, answerGate: gate);
    expect(_semanticSegment, findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(_semanticSegment, findsOneWidget);
  });

  testWidgets('ספר בלי וקטורים: אין מצב חכם, גם כשהסשן זוכר חכם', (
    tester,
  ) async {
    SearchDefaults.rememberSessionSemantic(true);
    await pumpInBookDialog(tester, {'id:2'});
    expect(_semanticSegment, findsNothing);
    expect(_queryField, findsNothing);
  });

  testWidgets('כיסוי לא ידוע: אין מצב חכם', (tester) async {
    await pumpInBookDialog(tester, null);
    expect(_semanticSegment, findsNothing);
  });

  testWidgets('שליחה פותחת כרטיסייה בספר בלבד, גם כשנשמר היקף רחב', (
    tester,
  ) async {
    await SearchScopePreferences.save(
      searchAllCategories: true,
      manualFacets: const {},
    );
    await SearchScopePreferences.saveDimensionFacets({'/base'});
    final harness = await pumpInBookDialog(tester, coveredBook);

    await tester.tap(_semanticSegment);
    await tester.pumpAndSettle();
    expect(find.byType(SearchScopeMenuButton), findsNothing);
    await tester.enterText(_queryField, 'בריאת העולם');
    await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
    await tester.pumpAndSettle();

    final added = verify(
      () => harness.tabs.add(captureAny()),
    ).captured.whereType<AddTab>().single;
    final tab = added.tab as SemanticSearchTab;
    addTearDown(tab.dispose);
    expect(tab.options.query, 'בריאת העולם');
    expect(tab.options.facets, [bookFacet]);
    expect(tab.lockedBookFacet, bookFacet);
    verify(
      () => harness.navigation.add(const NavigateToScreen(Screen.search)),
    ).called(1);
    expect(harness.results, [null]);
    expect(SearchDefaults.initialSemanticForNewSearch(), isFalse);
  });

  testWidgets('שליחה מתוך ספר בודקת מחדש כיסוי שהשתנה אחרי פתיחת הדיאלוג', (
    tester,
  ) async {
    final harness = await pumpInBookDialog(tester, coveredBook);
    await tester.tap(_semanticSegment);
    await tester.pumpAndSettle();
    await tester.enterText(_queryField, 'בריאת העולם');

    harness.repository.covered = {'id:2'};
    await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
    await tester.pumpAndSettle();

    verifyNever(() => harness.tabs.add(any()));
    expect(find.byType(SearchDialog), findsOneWidget);
    expect(_semanticSegment, findsNothing);
  });

  group('חיפוש בספרייה לפי ספרים עם וקטורים', () {
    Future<_MockTabsBloc> submitScope(
      WidgetTester tester,
      Set<String> scope,
    ) async {
      SearchDefaults.rememberSessionSemantic(true);
      final harness = await pumpInBookDialog(tester, {
        ...coveredBook,
        'id:9',
      }, inBook: false);
      final picker = tester.widget<SearchScopeMenuButton>(
        find.byType(SearchScopeMenuButton),
      );
      if (picker.officialBooksOnly == false) {
        await tester.tap(
          find.byKey(const ValueKey('semantic-include-lexical')),
        );
        await tester.pumpAndSettle();
      }
      final narrowed = tester.widget<SearchScopeMenuButton>(
        find.byType(SearchScopeMenuButton),
      );
      expect(narrowed.officialBooksOnly, isTrue);
      expect(narrowed.coveredFilePaths, {...coveredBook, 'id:9'});
      narrowed.onChanged(scope);
      await tester.pumpAndSettle();
      await tester.enterText(_queryField, 'שאלה');
      await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
      await tester.pumpAndSettle();
      return harness.tabs;
    }

    testWidgets('ספר רשמי בלי וקטורים אינו נשלח', (tester) async {
      final tabs = await submitScope(tester, {'/תנ״ך/id:2'});
      verifyNever(() => tabs.add(any()));
    });

    testWidgets('ספר מכוסה נשלח', (tester) async {
      final tabs = await submitScope(tester, {bookFacet});
      final tab =
          verify(
                () => tabs.add(captureAny()),
              ).captured.whereType<AddTab>().single.tab
              as SemanticSearchTab;
      addTearDown(tab.dispose);
      expect(tab.options.facets, [bookFacet]);
    });
  });

  group('PDF', () {
    testWidgets('PDF עם id שאול מספר הטקסט: אין מצב חכם', (tester) async {
      final pdf = PdfBook(id: 1, title: 'בראשית', path: '/pdf/a.pdf');
      await pumpInBookDialog(tester, {
        BookIdentity.indexedFilePath(pdf),
        BookIdentity.indexedFilePath(book),
      }, openBook: pdf);
      expect(_semanticSegment, findsNothing);
    });

    testWidgets('PDF בלי id: ההיקף הוא ה-PDF עצמו', (tester) async {
      final pdf = PdfBook(title: 'בראשית', path: '/pdf/a.pdf');
      final harness = await pumpInBookDialog(tester, {
        BookIdentity.indexedFilePath(pdf),
      }, openBook: pdf);
      await tester.tap(_semanticSegment);
      await tester.pumpAndSettle();
      await tester.enterText(_queryField, 'שאלה');
      await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
      await tester.pumpAndSettle();
      final tab =
          verify(
                () => harness.tabs.add(captureAny()),
              ).captured.whereType<AddTab>().single.tab
              as SemanticSearchTab;
      addTearDown(tab.dispose);
      expect(tab.options.facets.single, endsWith('/pdf/a.pdf'));
    });
  });
}
