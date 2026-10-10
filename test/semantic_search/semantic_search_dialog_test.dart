import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/models/book_source.dart';
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
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/semantic_search/bloc/semantic_search_bloc.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

import '../test_helpers/memory_cache_provider.dart';
import 'semantic_test_support.dart';
import 'semantic_ui_test_support.dart';

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

/// מאגר שמחזיר זמינות קבועה ורושם את פעולות ההורדה.
class _FakeRepository extends SemanticSearchRepository {
  _FakeRepository(this.current)
    : super(
        backend: FakeBackend(),
        consent: () => FakeConsentStore(),
        settings: FakeSettingsStore(),
      );

  SemanticAvailability current;
  final _controller = StreamController<SemanticAvailability>.broadcast();
  int downloads = 0;
  int cancels = 0;

  @override
  SemanticAvailability get availability => current;

  @override
  Stream<SemanticAvailability> get availabilityChanges => _controller.stream;

  @override
  Future<SemanticAvailability> refresh() async => current;

  /// הבדיקה הראשונה הסתיימה: המאגר משדר מצב חדש.
  void emit(SemanticAvailability next) {
    current = next;
    _controller.add(next);
  }

  @override
  Future<void> enableAndDownload() async => downloads++;

  @override
  Future<void> cancelDownload() async => cancels++;
}

SemanticAvailability _availability(
  SemanticAvailabilityPhase phase, {
  bool consent = true,
  SemanticHiddenReason? hiddenReason,
  SemanticDownloadProgress? progress,
  SemanticFailure? failure,
}) => SemanticAvailability(
  phase: phase,
  consentGranted: consent,
  hiddenReason: hiddenReason,
  progress: progress,
  failure: failure,
);

final _semanticSegment = find.byKey(
  const ValueKey('search-dialog-semantic-mode'),
);
final _consentCard = find.byKey(const ValueKey('semantic-consent-card'));
final _statusCard = find.byKey(const ValueKey('semantic-status-card'));
final _queryField = find.byKey(const ValueKey('semantic-query-field'));
final _debugBanner = find.byKey(const ValueKey('semantic-debug-banner'));

class _DelayedConsent extends FakeConsentStore {
  _DelayedConsent() : super(SearchFeedbackConsent.unknown);
  final pending = Completer<void>();
  @override
  Future<void> grant() async {
    await pending.future;
    set(SearchFeedbackConsent.granted);
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTabsEvent());
    registerFallbackValue(_FakeNavigationEvent());
  });

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(UiSnack.hide);

  Future<
    ({
      _FakeRepository repository,
      FakeConsentStore consent,
      _MockTabsBloc tabs,
      List<TabsEvent> addedEvents,
      _MockNavigationBloc navigation,
    })
  >
  pumpDialog(
    WidgetTester tester,
    SemanticAvailability availability, {
    bool debug = false,
    SearchMode? initialMode = SearchMode.exact,
    SearchingTab? existingTab,
    SearchingTab? editTab,
    FakeConsentStore? injectedConsent,
    Library? library,
    bool showMessages = false,
  }) async {
    final repository = _FakeRepository(availability);
    final consent =
        injectedConsent ??
        FakeConsentStore(
          availability.consentGranted
              ? SearchFeedbackConsent.granted
              : SearchFeedbackConsent.unknown,
        );
    final history = _MockHistoryBloc();
    final indexing = _MockIndexingBloc();
    final navigation = _MockNavigationBloc();
    final libraryBloc = _MockLibraryBloc();
    final tabs = _MockTabsBloc();
    final addedEvents = <TabsEvent>[];
    when(() => tabs.add(any())).thenAnswer((invocation) {
      addedEvents.add(invocation.positionalArguments.single as TabsEvent);
    });
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
      initialState: const NavigationState(currentScreen: Screen.library),
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
          navigatorKey: showMessages ? navigatorKey : null,
          home: Scaffold(
            body: Center(
              child: ElevatedButtonLauncher(
                dialog: SearchDialog(
                  initialSearchMode: initialMode,
                  existingTab: existingTab,
                  editTab: editTab,
                  semanticRepository: repository,
                  semanticConsent: consent,
                  semanticDebugPreview: debug,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(ElevatedButtonLauncher.launchKey));
    await tester.pumpAndSettle();
    return (
      repository: repository,
      consent: consent,
      tabs: tabs,
      addedEvents: addedEvents,
      navigation: navigation,
    );
  }

  ActionButton submitButton(WidgetTester tester) => tester.widget<ActionButton>(
    find.byKey(const ValueKey('search-dialog-submit')),
  );

  group('נראות המצב', () {
    testWidgets('בשחרור, כשהמצב מוסתר — אין מקטע רביעי', (tester) async {
      await pumpDialog(
        tester,
        _availability(
          SemanticAvailabilityPhase.hidden,
          hiddenReason: SemanticHiddenReason.engineNotInBuild,
        ),
      );
      expect(_semanticSegment, findsNothing);
    });

    testWidgets('בשחרור, כשנדרשת הסכמה — המקטע מוצג', (tester) async {
      await pumpDialog(
        tester,
        _availability(
          SemanticAvailabilityPhase.consentRequired,
          consent: false,
        ),
      );
      expect(_semanticSegment, findsOneWidget);
    });

    testWidgets('בפיתוח, מוסתר ועם הסכמה — תצוגה מקדימה עם באנר', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        _availability(
          SemanticAvailabilityPhase.hidden,
          hiddenReason: SemanticHiddenReason.engineNotInBuild,
        ),
        debug: true,
      );
      await tester.tap(_semanticSegment);
      await tester.pumpAndSettle();

      expect(_debugBanner, findsOneWidget);
      expect(_queryField, findsOneWidget);
      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('בפיתוח, מוסתר בלי הסכמה — קודם מסך ההסכמה', (tester) async {
      await pumpDialog(
        tester,
        _availability(SemanticAvailabilityPhase.hidden, consent: false),
        debug: true,
      );
      await tester.tap(_semanticSegment);
      await tester.pumpAndSettle();

      expect(_consentCard, findsOneWidget);
      expect(_queryField, findsNothing);
      expect(_debugBanner, findsNothing);
    });
  });

  group('שער ההסכמה', () {
    testWidgets('בלי הסכמה אין שדה חיפוש וכפתור החיפוש מושבת', (tester) async {
      final harness = await pumpDialog(
        tester,
        _availability(
          SemanticAvailabilityPhase.consentRequired,
          consent: false,
        ),
      );
      await tester.tap(_semanticSegment);
      await tester.pumpAndSettle();

      expect(_consentCard, findsOneWidget);
      expect(_queryField, findsNothing);
      expect(submitButton(tester).onPressed, isNull);
      verifyNever(() => harness.tabs.add(any()));

      await tester.tap(find.byKey(const ValueKey('semantic-consent-grant')));
      await tester.pumpAndSettle();
      expect(harness.consent.consent, SearchFeedbackConsent.granted);
    });

    testWidgets('"לא עכשיו" רושם סירוב וחוזר לחיפוש הרגיל', (tester) async {
      final harness = await pumpDialog(
        tester,
        _availability(
          SemanticAvailabilityPhase.consentRequired,
          consent: false,
        ),
      );
      await tester.tap(_semanticSegment);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('semantic-consent-decline')));
      await tester.pumpAndSettle();

      expect(harness.consent.consent, SearchFeedbackConsent.declined);
      expect(_consentCard, findsNothing);
    });
  });

  group('כרטיס המצב', () {
    testWidgets('הורדה מפורשת בלבד, ממקש "הורד"', (tester) async {
      final harness = await pumpDialog(
        tester,
        _availability(SemanticAvailabilityPhase.needsDownload),
      );
      await tester.tap(_semanticSegment);
      await tester.pumpAndSettle();

      expect(_statusCard, findsOneWidget);
      expect(_queryField, findsNothing);
      expect(harness.repository.downloads, 0);
      await tester.tap(find.byKey(const ValueKey('semantic-status-download')));
      await tester.pumpAndSettle();
      expect(harness.repository.downloads, 1);
    });

    testWidgets('בזמן הורדה — התקדמות וביטול', (tester) async {
      final harness = await pumpDialog(
        tester,
        _availability(
          SemanticAvailabilityPhase.downloading,
          progress: const SemanticDownloadProgress(
            item: SemanticDownloadItem.vectors,
            receivedBytes: 25,
            totalBytes: 100,
            step: 2,
            stepCount: 3,
          ),
        ),
      );
      await tester.tap(_semanticSegment);
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        find.text('מוריד את נתוני החיפוש (25%)'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('semantic-status-cancel')));
      await tester.pump();
      expect(harness.repository.cancels, 1);
    });

    testWidgets('בדיקת קבצים שהוכנו מראש — שלב בלי אחוז ופס בלי ערך', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        _availability(
          SemanticAvailabilityPhase.downloading,
          progress: const SemanticDownloadProgress(
            item: SemanticDownloadItem.vectors,
            receivedBytes: 25,
            totalBytes: 100,
            step: 2,
            stepCount: 3,
            checking: true,
          ),
        ),
      );
      await tester.tap(_semanticSegment);
      await tester.pump();

      expect(
        find.text('בודק את הקבצים שהוכנו מראש'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
    });

    testWidgets('כשל — ההודעה העברית וניסיון חוזר', (tester) async {
      final harness = await pumpDialog(
        tester,
        _availability(
          SemanticAvailabilityPhase.failed,
          failure: const SemanticFailure(SemanticFailureKind.network),
        ),
      );
      await tester.tap(_semanticSegment);
      await tester.pumpAndSettle();

      expect(
        find.text('ההורדה נכשלה בגלל בעיית רשת. נסו שוב מאוחר יותר.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('semantic-status-retry')));
      await tester.pumpAndSettle();
      expect(harness.repository.downloads, 1);
    });
  });

  testWidgets('כשהכול מוכן — שליחה פותחת כרטיסיית תוצאות סמנטית', (
    tester,
  ) async {
    final harness = await pumpDialog(
      tester,
      _availability(SemanticAvailabilityPhase.ready),
    );
    await tester.tap(_semanticSegment);
    await tester.pumpAndSettle();
    await tester.enterText(_queryField, 'כבוד אב ואם');
    await tester.tap(
      find.byKey(const ValueKey('semantic-include-lexical')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
    await tester.pumpAndSettle();

    final added = verify(
      () => harness.tabs.add(captureAny()),
    ).captured.whereType<AddTab>().single;
    final tab = added.tab as SemanticSearchTab;
    addTearDown(tab.dispose);
    expect(tab.options.query, 'כבוד אב ואם');
    expect(tab.options.includeLexical, isFalse);
    expect(tab.options.groupIdenticalText, isTrue);
    expect(tab.options.facets, ['/']);
    verify(
      () => harness.navigation.add(const NavigateToScreen(Screen.search)),
    ).called(1);
    expect(tab.runOnFirstShow, isTrue);
  });

  // אחרי השליחה שלמעלה הסשן "זוכר" את המצב הסמנטי.
  testWidgets('בלי מצב מבוקש — נפתח במצב הסמנטי שנזכר', (tester) async {
    await pumpDialog(
      tester,
      _availability(SemanticAvailabilityPhase.ready),
      initialMode: null,
    );
    expect(_queryField, findsOneWidget);
  });

  testWidgets('מצב מבוקש במפורש גובר על זיכרון הסשן', (tester) async {
    await pumpDialog(tester, _availability(SemanticAvailabilityPhase.ready));
    expect(_queryField, findsNothing);
  });

  testWidgets('טאב זמני מבחוץ (איתור/ספרייה) נסגר אחרי שליחה סמנטית', (
    tester,
  ) async {
    final existing = SearchingTab('חיפוש', 'צדקה');
    final harness = await pumpDialog(
      tester,
      _availability(SemanticAvailabilityPhase.ready),
      initialMode: null,
      existingTab: existing,
    );
    expect(_queryField, findsNothing);
    await tester.tap(_semanticSegment);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
    await tester.pumpAndSettle();

    final added = verify(
      () => harness.tabs.add(captureAny()),
    ).captured.whereType<AddTab>().single;
    addTearDown(added.tab.dispose);
    expect(existing.searchBloc.isClosed, isTrue);
  });
  testWidgets('סגירת הדיאלוג בזמן שמירת ההסכמה אינה שולחת אירוע מאוחר', (
    tester,
  ) async {
    final consent = _DelayedConsent();
    await pumpDialog(
      tester,
      _availability(SemanticAvailabilityPhase.consentRequired, consent: false),
      injectedConsent: consent,
    );
    await tester.tap(_semanticSegment);
    await tester.pumpAndSettle();
    final dialogState = tester.state(find.byType(SearchDialog));
    final capturedBloc = tester
        .widgetList<BlocBuilder<SemanticSearchBloc, SemanticSearchState>>(
          find.byType(BlocBuilder<SemanticSearchBloc, SemanticSearchState>),
        )
        .first
        .bloc!;
    final callback = tester
        .widget<ActionButton>(
          find.byKey(const ValueKey('semantic-consent-grant')),
        )
        .onPressed!;
    final pendingGrant = (callback as dynamic)() as Future<void>;
    await tester.pump();
    Navigator.of(tester.element(find.byType(SearchDialog))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(SearchDialog), findsNothing);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(() async {
      for (var i = 0; i < 20 && !capturedBloc.isClosed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(dialogState.mounted, isFalse);
    expect(capturedBloc.isClosed, isTrue);
    final completionCheck = expectLater(pendingGrant, completes);
    consent.pending.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await completionCheck;
    expect(tester.takeException(), isNull);
  });
  testWidgets('ספר יחיד וממד נשלחים כמו שהם; ספר אישי מושמט מההיקף', (
    tester,
  ) async {
    final harness = await pumpDialog(
      tester,
      _availability(SemanticAvailabilityPhase.ready),
    );
    await tester.tap(_semanticSegment);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SearchScopeMenuButton>(find.byType(SearchScopeMenuButton))
          .officialBooksOnly,
      isTrue,
    );
    final facet = FacetHelper.buildBookFacet(
      '/הלכה',
      TextBook(id: 1, title: 'ספר 1'),
    );
    final hint = find.byKey(const ValueKey('semantic-narrow-scope-hint'));
    expect(hint, findsOneWidget);
    tester
        .widget<SearchScopeMenuButton>(find.byType(SearchScopeMenuButton))
        .onChanged({facet, '/author/רש״י', '/uid:4'});
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    expect(submitButton(tester).onPressed, isNotNull);
    const rawQuery = '  כָּבוֹד אב  ';
    await tester.enterText(_queryField, rawQuery);
    await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
    await tester.pumpAndSettle();
    final tab =
        verify(
              () => harness.tabs.add(captureAny()),
            ).captured.whereType<AddTab>().single.tab
            as SemanticSearchTab;
    addTearDown(tab.dispose);
    expect(tab.options.facets, ['/author/רש״י', facet]);
    expect(tab.options.query, rawQuery);
  });
  testWidgets('תחביר @ מצמצם את החיפוש החכם לקטגוריה ונמחק מהשאילתה', (
    tester,
  ) async {
    final library = Library(
      categories: [
        Category(
          title: 'הלכה',
          description: '',
          shortDescription: '',
          order: 0,
          subCategories: const [],
          books: [TextBook(id: 1, title: 'ספר 1')],
          parent: null,
        ),
      ],
    );
    final harness = await pumpDialog(
      tester,
      _availability(SemanticAvailabilityPhase.ready),
      library: library,
    );
    await tester.tap(_semanticSegment);
    await tester.pumpAndSettle();
    await tester.enterText(_queryField, 'חסד@הלכה');
    await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
    await tester.pumpAndSettle();
    final tab =
        verify(
              () => harness.tabs.add(captureAny()),
            ).captured.whereType<AddTab>().single.tab
            as SemanticSearchTab;
    addTearDown(tab.dispose);
    expect(tab.options.query, 'חסד');
    expect(tab.options.facets, ['/הלכה']);
  });
  group('תחביר @ שומר על ההיקף המפורש', () {
    Library scopeLibrary() {
      Category category(String title, List<Book> books) {
        final result = Category(
          title: title,
          description: '',
          shortDescription: '',
          order: 0,
          subCategories: const [],
          books: books,
          parent: null,
        );
        return result;
      }

      return Library(
        categories: [
          category('הלכה', [
            TextBook(id: 1, title: 'ספר רשמי', categoryPath: '/הלכה'),
            TextBook(id: 5, title: 'שם משותף', categoryPath: '/הלכה'),
            TextBook(
              id: 6,
              title: 'שם משותף',
              categoryPath: '/הלכה',
              source: BookSource.user,
            ),
            TextBook(
              id: 2,
              title: 'מחברת פרטית',
              categoryPath: '/הלכה',
              source: BookSource.user,
            ),
            PdfBook(
              title: 'קובץ סרוק',
              categoryPath: '/הלכה',
              path: '/tmp/library/scan.pdf',
            ),
          ]),
          category('תנ״ך', [
            TextBook(id: 7, title: 'בראשית', categoryPath: '/תנ״ך'),
          ]),
          category('ספריית אוצריא', [TextBook(id: 4, title: 'ספר כולל')]),
          category('אוסף נוסף', [
            TextBook(
              id: 3,
              title: 'ספר מצורף',
              categoryPath: '/אוסף נוסף',
              source: BookSource.attached('lib'),
            ),
          ]),
        ],
      );
    }

    const unsupportedMessage =
        'הצמצום המבוקש אינו נתמך במלואו בחיפוש החכם. בחרו צמצום אחר או עברו לחיפוש רגיל.';
    for (final suffix in [
      '@מחברת פרטית',
      '@שם משותף',
      '@ספר מצורף',
      '@אוסף נוסף',
      '@קובץ סרוק',
      '@ספר רשמי@מחברת פרטית',
      '@הלכה@ספר מצורף',
      '@ספריית אוצריא@מחברת פרטית',
    ]) {
      testWidgets('צמצום לא נתמך $suffix נעצר ואפשר לתקן ולהגיש', (
        tester,
      ) async {
        final harness = await pumpDialog(
          tester,
          _availability(SemanticAvailabilityPhase.ready),
          library: scopeLibrary(),
          showMessages: true,
        );
        await tester.tap(_semanticSegment);
        await tester.pumpAndSettle();
        tester
            .widget<SearchScopeMenuButton>(find.byType(SearchScopeMenuButton))
            .onChanged({'/הלכה', '/era/ראשונים'});
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('semantic-narrow-scope-hint')),
          findsNothing,
        );
        final rawQuery = 'חסד$suffix';
        await tester.enterText(_queryField, rawQuery);
        await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
        await tester.pumpAndSettle();
        final added = harness.addedEvents;
        for (final event in added.whereType<AddTab>()) {
          addTearDown(event.tab.dispose);
        }
        expect(
          added,
          isEmpty,
          reason: added
              .whereType<AddTab>()
              .map((event) => (event.tab as SemanticSearchTab).options.facets)
              .toString(),
        );
        verifyNever(() => harness.navigation.add(any()));
        expect(find.byType(SearchDialog), findsOneWidget);
        expect(find.text(unsupportedMessage), findsOneWidget);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).first)
              .controller
              .text,
          rawQuery,
        );
        expect(
          tester
              .widget<SearchScopeMenuButton>(find.byType(SearchScopeMenuButton))
              .selected,
          {'/הלכה', '/era/ראשונים'},
        );
        UiSnack.hide();
        await tester.enterText(_queryField, 'חסד@ספר רשמי');
        await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
        await tester.pumpAndSettle();
        final tab =
            verify(
                  () => harness.tabs.add(captureAny()),
                ).captured.whereType<AddTab>().single.tab
                as SemanticSearchTab;
        addTearDown(tab.dispose);
        expect(tab.options.query, 'חסד');
        expect(tab.options.facets, ['/era/ראשונים', '/הלכה/id:1']);
      });
    }

    for (final sample in [
      (
        raw: 'חסד@ספריית אוצריא@ספר רשמי',
        query: 'חסד',
        facets: ['/', '/era/ראשונים'],
      ),
      (raw: 'חסד@הלכה', query: 'חסד', facets: ['/era/ראשונים', '/הלכה']),
      (
        raw: 'חסד@ספר רשמי',
        query: 'חסד',
        facets: ['/era/ראשונים', '/הלכה/id:1'],
      ),
      (
        raw: 'חסד@הלכה@ספר רשמי',
        query: 'חסד',
        facets: ['/era/ראשונים', '/הלכה', '/הלכה/id:1'],
      ),
      (
        raw: 'חסד@ספר רשמי@@ספר רשמי@',
        query: 'חסד',
        facets: ['/era/ראשונים', '/הלכה/id:1'],
      ),
      (raw: 'חסד@', query: 'חסד', facets: ['/era/ראשונים', '/תנ״ך']),
      (
        raw: '  כָּבוֹד אב  ',
        query: '  כָּבוֹד אב  ',
        facets: ['/era/ראשונים', '/תנ״ך'],
      ),
    ]) {
      testWidgets('צמצום תקין ${sample.raw} שומר על ממדים', (tester) async {
        final harness = await pumpDialog(
          tester,
          _availability(SemanticAvailabilityPhase.ready),
          library: scopeLibrary(),
          showMessages: true,
        );
        await tester.tap(_semanticSegment);
        await tester.pumpAndSettle();
        tester
            .widget<SearchScopeMenuButton>(find.byType(SearchScopeMenuButton))
            .onChanged({'/תנ״ך', '/era/ראשונים'});
        await tester.enterText(_queryField, sample.raw);
        await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
        await tester.pumpAndSettle();
        final tab =
            verify(
                  () => harness.tabs.add(captureAny()),
                ).captured.whereType<AddTab>().single.tab
                as SemanticSearchTab;
        addTearDown(tab.dispose);
        expect(tab.options.query, sample.query);
        expect(tab.options.facets, sample.facets);
      });
    }

    for (final raw in [
      'חסד@שם חסר לגמרי',
      'חסד@ספר רשמי@שם חסר לגמרי',
      '@הלכה',
      '@@',
    ]) {
      testWidgets('צמצום שגוי או שאילתה ריקה $raw אינם נשלחים', (tester) async {
        final harness = await pumpDialog(
          tester,
          _availability(SemanticAvailabilityPhase.ready),
          library: scopeLibrary(),
          showMessages: true,
        );
        await tester.tap(_semanticSegment);
        await tester.pumpAndSettle();
        await tester.enterText(_queryField, raw);
        await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
        await tester.pumpAndSettle();
        verifyNever(() => harness.tabs.add(any()));
        expect(find.byType(SearchDialog), findsOneWidget);
        expect(
          find.text(
            raw.startsWith('@')
                ? LibraryMessages.emptySearchQuery
                : LibraryMessages.categoryOrBookNotFound(['שם חסר לגמרי']),
          ),
          findsOneWidget,
        );
        UiSnack.hide();
        await tester.pump();
      });
    }

    testWidgets('עריכת חיפוש חכם אינה מחליפה את ההיקף כשהצמצום לא נתמך', (
      tester,
    ) async {
      final tab = SemanticSearchTab(
        options: const SemanticQueryOptions(
          query: 'צדקה',
          facets: ['/הלכה', '/era/ראשונים'],
          includeLexical: false,
          groupIdenticalText: false,
        ),
        createResultsBloc: (_) =>
            buildResultsBloc(source: null, recorder: RecordingRecorder()),
      );
      addTearDown(tab.dispose);
      final harness = await pumpDialog(
        tester,
        _availability(SemanticAvailabilityPhase.ready),
        editTab: tab,
        library: scopeLibrary(),
        showMessages: true,
      );
      await tester.enterText(_queryField, 'חסד@מחברת פרטית');
      await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
      await tester.pumpAndSettle();
      expect(tab.options.query, 'צדקה');
      expect(tab.options.facets, ['/הלכה', '/era/ראשונים']);
      expect(find.text(unsupportedMessage), findsOneWidget);
      UiSnack.hide();
      await tester.enterText(_queryField, 'חסד@ספר רשמי');
      await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
      await tester.pumpAndSettle();
      verifyNever(() => harness.tabs.add(any()));
      expect(tab.options.query, 'חסד');
      expect(tab.options.facets, ['/era/ראשונים', '/הלכה/id:1']);
      expect(tab.options.includeLexical, isFalse);
      expect(tab.options.groupIdenticalText, isFalse);
    });
  });

  testWidgets('בשדה החיפוש החכם יש ניקוי והיסטוריה', (tester) async {
    await pumpDialog(tester, _availability(SemanticAvailabilityPhase.ready));
    await tester.tap(_semanticSegment);
    await tester.pumpAndSettle();
    final clear = find.byKey(const ValueKey('semantic-query-clear'));
    expect(find.byTooltip('היסטוריית חיפושים'), findsOneWidget);
    await tester.enterText(_queryField, 'צדקה');
    await tester.pump();
    await tester.tap(clear);
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      isEmpty,
    );
    expect(clear, findsNothing);
  });

  testWidgets('עריכת חיפוש חכם מעדכנת את אותה כרטיסייה', (tester) async {
    final tab = SemanticSearchTab(
      options: const SemanticQueryOptions(
        query: 'צדקה',
        facets: ['/הלכה'],
        includeLexical: false,
        groupIdenticalText: false,
      ),
      createResultsBloc: (_) =>
          buildResultsBloc(source: null, recorder: RecordingRecorder()),
    );
    addTearDown(tab.dispose);
    final harness = await pumpDialog(
      tester,
      _availability(SemanticAvailabilityPhase.ready),
      editTab: tab,
    );
    expect(
      tester
          .widget<SearchScopeMenuButton>(find.byType(SearchScopeMenuButton))
          .selected,
      {'/הלכה'},
    );
    await tester.enterText(_queryField, 'חסד');
    await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
    await tester.pumpAndSettle();
    verifyNever(() => harness.tabs.add(any()));
    expect(tab.options.query, 'חסד');
    expect(tab.options.facets, ['/הלכה']);
    expect(tab.options.includeLexical, isFalse);
    expect(tab.options.groupIdenticalText, isFalse);
  });
  // הסשן זוכר מצב חכם מהשליחות שלמעלה; עריכה נפתחת במצב של הכרטיסייה.
  testWidgets('עריכת חיפוש רגיל מציעה את המצב החכם, ושליחה בו פותחת '
      'כרטיסייה חכמה חדשה', (tester) async {
    final edited = SearchingTab('חיפוש', 'צדקה');
    addTearDown(edited.dispose);
    final harness = await pumpDialog(
      tester,
      _availability(SemanticAvailabilityPhase.ready),
      initialMode: null,
      editTab: edited,
    );
    expect(_queryField, findsNothing);
    expect(_semanticSegment, findsOneWidget);
    await tester.tap(_semanticSegment);
    await tester.pumpAndSettle();
    await tester.enterText(_queryField, 'חסד');
    await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
    await tester.pumpAndSettle();

    final added = verify(
      () => harness.tabs.add(captureAny()),
    ).captured.whereType<AddTab>().single;
    final tab = added.tab as SemanticSearchTab;
    addTearDown(tab.dispose);
    expect(tab.options.query, 'חסד');
    expect(edited.queryController.text, 'צדקה');
  });

  testWidgets('עריכת חיפוש חכם לפני שהזמינות נבדקה נשארת חכמה', (
    tester,
  ) async {
    final tab = SemanticSearchTab(
      options: const SemanticQueryOptions(query: 'צדקה'),
      createResultsBloc: (_) =>
          buildResultsBloc(source: null, recorder: RecordingRecorder()),
    );
    addTearDown(tab.dispose);
    final harness = await pumpDialog(
      tester,
      SemanticAvailability.initial,
      editTab: tab,
    );
    expect(_semanticSegment, findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);
    await tester.tap(
      find.byKey(const ValueKey('search-dialog-submit')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    verifyNever(() => harness.tabs.add(any()));

    harness.repository.emit(_availability(SemanticAvailabilityPhase.ready));
    await tester.pumpAndSettle();
    await tester.enterText(_queryField, 'חסד');
    await tester.tap(find.byKey(const ValueKey('search-dialog-submit')));
    await tester.pumpAndSettle();
    verifyNever(() => harness.tabs.add(any()));
    expect(tab.options.query, 'חסד');
  });

  testWidgets('גם בדיבאג פלטפורמה לא נתמכת אינה מציגה מצב או הסכמה', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      _availability(
        SemanticAvailabilityPhase.hidden,
        consent: false,
        hiddenReason: SemanticHiddenReason.unsupportedPlatform,
      ),
      debug: true,
    );
    expect(_semanticSegment, findsNothing);
    expect(_consentCard, findsNothing);
    expect(_debugBanner, findsNothing);
  });

  testWidgets('"קבע מצב זה" במצב החכם שומר את החכם ולא את המצב שלפניו', (
    tester,
  ) async {
    addTearDown(() {
      SearchDefaults.rememberSessionMode(SearchMode.exact);
      SearchDefaults.rememberSessionSemantic(false);
    });
    await pumpDialog(tester, _availability(SemanticAvailabilityPhase.ready));

    Future<void> setCurrentModeAsDefault() async {
      await tester.tap(
        find.byKey(const ValueKey('search-dialog-defaults-menu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('search-dialog-default-mode')),
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(_semanticSegment);
    await tester.pumpAndSettle();
    await setCurrentModeAsDefault();
    expect(
      find.text(
        'כל חיפוש חדש ייפתח מעכשיו במצב "$kSemanticSearchModeLabel". ניתן לשנות זאת שוב בכל עת.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('קבע כברירת מחדל'));
    await tester.pumpAndSettle();
    expect(SearchDefaults.loadSemanticDefault(), isTrue);

    await tester.tap(find.text('מקורב'));
    await tester.pumpAndSettle();
    await setCurrentModeAsDefault();
    await tester.tap(find.text('קבע כברירת מחדל'));
    await tester.pumpAndSettle();
    expect(SearchDefaults.loadSemanticDefault(), isFalse);
    expect(SearchDefaults.loadModeDefault(), SearchMode.fuzzy);
  });
}

/// פותח את הדיאלוג כמו באפליקציה (showDialog), כדי ש-pop יעבוד.
class ElevatedButtonLauncher extends StatelessWidget {
  const ElevatedButtonLauncher({super.key, required this.dialog});

  static const launchKey = ValueKey('launch-search-dialog');
  final Widget dialog;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: launchKey,
      behavior: HitTestBehavior.opaque,
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => MediaQuery(
          data: const MediaQueryData(size: Size(1280, 900)),
          child: dialog,
        ),
      ),
      child: const SizedBox(width: 40, height: 40),
    );
  }
}
