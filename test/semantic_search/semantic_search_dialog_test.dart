import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

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

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTabsEvent());
    registerFallbackValue(_FakeNavigationEvent());
  });

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<
    ({
      _FakeRepository repository,
      FakeConsentStore consent,
      _MockTabsBloc tabs,
      _MockNavigationBloc navigation,
    })
  >
  pumpDialog(
    WidgetTester tester,
    SemanticAvailability availability, {
    bool debug = false,
    SearchMode? initialMode = SearchMode.exact,
    SearchingTab? existingTab,
  }) async {
    final repository = _FakeRepository(availability);
    final consent = FakeConsentStore(
      availability.consentGranted
          ? SearchFeedbackConsent.granted
          : SearchFeedbackConsent.unknown,
    );
    final history = _MockHistoryBloc();
    final indexing = _MockIndexingBloc();
    final navigation = _MockNavigationBloc();
    final library = _MockLibraryBloc();
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
      initialState: const NavigationState(currentScreen: Screen.library),
    );
    whenListen(
      library,
      const Stream<LibraryState>.empty(),
      initialState: const LibraryState(),
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
      await library.close();
      await tabs.close();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<HistoryBloc>.value(value: history),
          BlocProvider<IndexingBloc>.value(value: indexing),
          BlocProvider<NavigationBloc>.value(value: navigation),
          BlocProvider<LibraryBloc>.value(value: library),
          BlocProvider<TabsBloc>.value(value: tabs),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButtonLauncher(
                dialog: SearchDialog(
                  initialSearchMode: initialMode,
                  existingTab: existingTab,
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
          ),
        ),
      );
      await tester.tap(_semanticSegment);
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('25%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('semantic-status-cancel')));
      await tester.pump();
      expect(harness.repository.cancels, 1);
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
