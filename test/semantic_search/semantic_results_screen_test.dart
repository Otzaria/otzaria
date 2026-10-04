import "dart:async";

import "package:flutter/services.dart";
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/bloc/semantic_results_bloc.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/semantic_search/view/widgets/semantic_result_card.dart';
import 'package:otzaria/semantic_search/services/semantic_dwell_binding.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/search/view/search_results_layout.dart';
import 'package:otzaria/semantic_search/view/semantic_search_results_screen.dart';
import 'package:otzaria/semantic_search/view/widgets/semantic_facet_filtering.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show SemanticResultSource;

import '../test_helpers/memory_cache_provider.dart';
import 'semantic_ui_test_support.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _RecordingTabsBloc extends Bloc<TabsEvent, TabsState>
    implements TabsBloc {
  _RecordingTabsBloc() : super(TabsState.initial()) {
    on<TabsEvent>((event, emit) {
      if (event is OpenOrFocusTab) opened.add(event);
    });
  }

  final List<OpenOrFocusTab> opened = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  tearDown(SemanticDwellBinding.resetForTesting);

  setUp(() {
    final library = Library(categories: const []);
    for (var i = 1; i <= 35; i++) {
      library.books.add(TextBook(id: i, title: 'ספר $i'));
    }
    DataRepository.instance.library = Future.value(library);
  });

  Future<
    ({
      RecordingRecorder recorder,
      _RecordingTabsBloc tabs,
      SemanticSearchTab tab,
      FakeResultsSource source,
    })
  >
  pumpScreen(
    WidgetTester tester, {
    bool runOnFirstShow = true,
    bool preview = false,
    FakeResultsSource? injectedSource,
    double? paneWidth,
    bool platformSupported = true,
  }) async {
    final recorder = RecordingRecorder();
    final items = [
      resultItem(1, source: SemanticResultSource.both),
      resultItem(2, source: SemanticResultSource.semantic, html: 'בלי סימון'),
      resultItem(3, source: SemanticResultSource.lexical),
      for (var i = 4; i <= 35; i++) resultItem(i),
    ];
    final source = injectedSource ?? FakeResultsSource(items: items);
    final tab = SemanticSearchTab(
      runOnFirstShow: runOnFirstShow,
      options: const SemanticQueryOptions(query: 'כבוד אב'),
      createResultsBloc: (_) => buildResultsBloc(
        source: source,
        recorder: recorder,
      ),
    );
    final settings = _MockSettingsBloc();
    whenListen(
      settings,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial().copyWith(
        searchShowPreview: preview,
      ),
    );
    final navigation = _MockNavigationBloc();
    whenListen(
      navigation,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );
    final tabs = _RecordingTabsBloc();
    final libraryBloc = _MockLibraryBloc();
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: const LibraryState(),
    );
    addTearDown(() async {
      await libraryBloc.close();
      tab.dispose();
      await settings.close();
      await navigation.close();
      await tabs.close();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settings),
          BlocProvider<TabsBloc>.value(value: tabs),
          BlocProvider<NavigationBloc>.value(value: navigation),
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(700, 900)),
            child: Align(
              child: SizedBox(
                width: paneWidth,
                child: SemanticSearchResultsScreen(
                  tab: tab,
                  platformSupported: platformSupported,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return (recorder: recorder, tabs: tabs, tab: tab, source: source);
  }

  testWidgets('restart replaces the list and returns its scroll to zero', (
    tester,
  ) async {
    final source = FakeResultsSource(total: 100);
    final setup = await pumpScreen(tester, injectedSource: source);
    final list = find.byType(ListView);
    await tester.drag(list, const Offset(0, -2000));
    await settle(tester);
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    expect(scroll.position.pixels, greaterThan(0));
    source.restartContinuation = true;
    final oldSearchId = setup.tab.resultsBloc.state.searchId;
    setup.tab.resultsBloc.add(const SemanticMoreResultsRequested());
    await settle(tester);
    expect(setup.tab.resultsBloc.state.searchId, greaterThan(oldSearchId));
    expect(setup.tab.resultsBloc.state.items, hasLength(30));
    expect(scroll.position.pixels, 0);
  });

  testWidgets('הכרטיסים מציגים את תווית המקור', (tester) async {
    await pumpScreen(tester);

    expect(find.text(kSemanticSourceBothLabel), findsWidgets);
    expect(find.text(kSemanticSourceSemanticLabel), findsOneWidget);
    expect(find.text(kSemanticSourceLexicalLabel), findsOneWidget);
  });

  testWidgets('קטע לפי עניין מסומן ברקע בהיר, בלי הדגשה מודגשת', (
    tester,
  ) async {
    final items = [
      resultItem(1),
      resultItem(2, source: SemanticResultSource.semantic, html: 'בלי סימון'),
    ];
    final source = FakeResultsSource(items: items)
      ..highlighter = (items, _) async => markAll(items);
    await pumpScreen(tester, injectedSource: source);

    final card = tester.widget<SemanticResultCard>(
      find.byKey(const ValueKey('semantic-result-1')),
    );
    final spans = card.snippetSpans.whereType<TextSpan>().toList();
    final mark = spans.singleWhere((s) => s.text == 'הקטע הקרוב 2');
    final plain = spans.singleWhere((s) => s.text == 'לפני ');
    final context = tester.element(find.byType(SemanticResultCard).first);
    expect(
      mark.style?.backgroundColor,
      AppSurfaces.semanticPassageHighlight(Theme.of(context).colorScheme),
    );
    expect(mark.style?.fontWeight, plain.style?.fontWeight);
    expect(mark.style?.fontSize, plain.style?.fontSize);
    expect(mark.style?.color, plain.style?.color);
    // התאמה מילולית אינה מסומנת לפי עניין.
    expect(source.highlightCalls.single.items, [items[1]]);
  });

  testWidgets('סימון והצבעה בונים רק את הכרטיסים, לא את מסגרת המסך', (
    tester,
  ) async {
    final gate = Completer<void>();
    final items = [
      resultItem(1),
      resultItem(2, source: SemanticResultSource.semantic, html: 'בלי סימון'),
    ];
    final source = FakeResultsSource(items: items)
      ..highlighter = (items, _) async {
        await gate.future;
        return markAll(items);
      };
    await pumpScreen(tester, injectedSource: source);
    final layout = tester.widget(find.byType(SearchResultsLayout));

    gate.complete();
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('semantic-like-1')));
    await settle(tester);

    expect(
      identical(tester.widget(find.byType(SearchResultsLayout)), layout),
      isTrue,
    );
    final card = tester.widget<SemanticResultCard>(
      find.byKey(const ValueKey('semantic-result-1')),
    );
    expect(
      card.snippetSpans.whereType<TextSpan>().map((s) => s.text),
      contains('הקטע הקרוב 2'),
    );
    expect(
      tester
          .widget<SemanticResultCard>(
            find.byKey(const ValueKey('semantic-result-0')),
          )
          .vote,
      SearchFeedbackVote.like,
    );
  });

  test('מסגרת המסך נבנית מחדש על כל שינוי אחר', () {
    final base = SemanticResultsState(
      status: SemanticResultsStatus.loaded,
      items: [resultItem(1)],
    );
    expect(
      semanticLayoutNeedsRebuild(
        base,
        base.copyWith(
          passageHighlights: {0: '<mark>א</mark>'},
          votes: {0: SearchFeedbackVote.like},
        ),
      ),
      isFalse,
    );
    expect(
      semanticLayoutNeedsRebuild(
        base,
        base.copyWith(items: [resultItem(1), resultItem(2)]),
      ),
      isTrue,
    );
    expect(
      semanticLayoutNeedsRebuild(base, base.copyWith(isDebugPreview: true)),
      isTrue,
    );
    expect(
      semanticLayoutNeedsRebuild(
        base,
        base.copyWith(status: SemanticResultsStatus.loading),
      ),
      isTrue,
    );
  });

  testWidgets('העתקה מעתיקה את הקטע המוצג, גם כשהוא מסומן', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final items = [
      resultItem(1),
      resultItem(2, source: SemanticResultSource.semantic, html: 'בלי סימון'),
    ];
    final source = FakeResultsSource(items: items)
      ..highlighter = (items, _) async => markAll(items);
    await pumpScreen(tester, injectedSource: source);

    tester
        .widget<SemanticResultCard>(
          find.byKey(const ValueKey('semantic-result-1')),
        )
        .onCopy();
    await settle(tester);

    expect(copied, contains('לפני הקטע הקרוב 2 אחרי'));
    expect(copied, isNot(contains('בלי סימון')));
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('אהבתי, לחיצה חוזרת מבטלת; לא אהבתי', (tester) async {
    final harness = await pumpScreen(tester);

    await tester.tap(find.byKey(const ValueKey('semantic-like-1')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('semantic-like-1')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('semantic-dislike-2')));
    await settle(tester);

    expect(harness.recorder.votes.map((vote) => vote.vote), [
      SearchFeedbackVote.like,
      SearchFeedbackVote.cleared,
      SearchFeedbackVote.dislike,
    ]);
    expect(harness.recorder.votes.last.result.rank, 2);
  });

  testWidgets('פתיחה: התאמה לפי עניין בלבד נפתחת בלי הדגשת מילים', (
    tester,
  ) async {
    final harness = await pumpScreen(tester);

    await tester.tap(find.text('ספר 1, א'));
    await settle(tester);
    await tester.tap(find.text('ספר 2, א'));
    await settle(tester);

    final opened = harness.tabs.opened.map((e) => e.tab as TextBookTab);
    expect(opened.map((tab) => tab.searchText), ['כבוד אב', '']);
    expect(opened.last.initialSearchResultLines, {2});
    expect(harness.recorder.opens.map((open) => open.via), [
      SearchFeedbackOpenVia.click,
      SearchFeedbackOpenVia.click,
    ]);
    SemanticDwellBinding.resetForTesting();
  });

  testWidgets('גלילה לסוף טוענת עמוד ורושמת results_shown עם ההיסט', (
    tester,
  ) async {
    final harness = await pumpScreen(tester);

    // גלילה לסוף הרשימה טוענת את העמוד הבא, כמו "טען תוצאות נוספות".
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await settle(tester);
    }

    expect(harness.recorder.shown.map((page) => page.offset), [0, 30]);
    expect(harness.recorder.searches, hasLength(1));
  });

  testWidgets('כרטיסייה משוחזרת אינה מחפשת ואינה רושמת עד לחיצה', (
    tester,
  ) async {
    final harness = await pumpScreen(tester, runOnFirstShow: false);

    expect(harness.recorder.total, 0);
    expect(find.text('ספר 1, א'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('semantic-results-rerun')));
    await settle(tester);

    expect(find.text('ספר 1, א'), findsOneWidget);
    expect(harness.recorder.searches, hasLength(1));
  });
  testWidgets('תצוגה מקדימה מושהית מתבטלת כשהחיפוש מתחלף', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final oldItems = [resultItem(1), resultItem(2)];
    final source = FakeResultsSource(items: oldItems);
    final harness = await pumpScreen(
      tester,
      preview: true,
      injectedSource: source,
    );
    final pending = Completer<Library>();
    DataRepository.instance.library = pending.future;
    await tester.tap(find.text('ספר 1, א'));
    await tester.pump(const Duration(milliseconds: 350));
    oldItems[0] = resultItem(3);
    harness.tab.submit(const SemanticQueryOptions(query: 'שאילתה חדשה'));
    await settle(tester);
    expect(harness.tab.resultsBloc.state.options!.query, 'שאילתה חדשה');
    expect(harness.tab.previewTarget.value, isNull);
    final library = Library(categories: const []);
    library.books.addAll([
      TextBook(id: 1, title: 'ספר 1'),
      TextBook(id: 3, title: 'ספר 3'),
    ]);
    pending.complete(library);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    expect(
      harness.tab.previewTarget.value,
      isNull,
      reason: 'A preview requested before the new search must be invalidated',
    );
  });

  testWidgets('פתיחה מושהית אינה מיוחסת לתוצאה מהחיפוש החדש', (
    tester,
  ) async {
    final items = [resultItem(1), resultItem(2)];
    final source = FakeResultsSource(items: items);
    final harness = await pumpScreen(tester, injectedSource: source);
    final pending = Completer<Library>();
    DataRepository.instance.library = pending.future;
    await tester.tap(find.text('ספר 1, א'));
    await tester.pump();
    items[0] = resultItem(3);
    harness.tab.submit(const SemanticQueryOptions(query: 'שאילתה חדשה'));
    await settle(tester);
    expect(harness.tab.resultsBloc.state.items.first.id, BigInt.from(3));
    final library = Library(categories: const []);
    for (var i = 1; i <= 3; i++) {
      library.books.add(TextBook(id: i, title: 'ספר $i'));
    }
    pending.complete(library);
    await settle(tester);
    expect((harness.tabs.opened.single.tab as TextBookTab).book.title, 'ספר 1');
    expect(
      harness.recorder.opens,
      isEmpty,
      reason: 'A new search invalidates telemetry from the pending old opening',
    );
    SemanticDwellBinding.resetForTesting();
  });

  testWidgets('כשל עמוד נוסף מוצג ומאפשר ניסיון חוזר בלי בקשות אוטומטיות', (
    tester,
  ) async {
    final harness = await pumpScreen(tester);
    harness.source.error = StateError('injected page failure');
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await settle(tester);
    }
    expect(harness.tab.resultsBloc.state.message, isNotNull);
    expect(
      find.text(
        harness.tab.resultsBloc.state.message!.replaceAll(
          '{name}',
          kSemanticSearchModeName,
        ),
      ),
      findsWidgets,
      reason: 'A loaded list must show its subsequent page failure',
    );
    expect(harness.source.fetches, hasLength(2));
    harness.source.error = null;
    await tester.tap(find.byKey(const ValueKey('semantic-results-more')));
    await settle(tester);
    expect(harness.tab.resultsBloc.state.items, hasLength(35));
    expect(harness.tab.resultsBloc.state.message, isNull);
    expect(
      find.byKey(const ValueKey('semantic-results-page-error')),
      findsNothing,
    );
    expect(harness.source.fetches, hasLength(3));
    expect(harness.recorder.shown.map((page) => page.offset), [0, 30]);
  });
  testWidgets('רשימה גדולה בונה רק כרטיסים הנראים במסך', (
    tester,
  ) async {
    final harness = await pumpScreen(
      tester,
      injectedSource: FakeResultsSource(total: 10000),
    );
    expect(harness.tab.resultsBloc.state.items, hasLength(30));
    final rendered = find.byType(SemanticResultCard).evaluate().length;
    expect(rendered, lessThan(30));
    expect(harness.source.fetches, hasLength(1));
  });

  testWidgets(
    'חלונית desktop ברוחב 300 מציגה את הכרטיסים ללא גלישה',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final loader = FontLoader('Roboto')
        ..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'));
      await loader.load();
      await pumpScreen(tester, paneWidth: 300);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('הסרגל מציג את מספר התוצאות שמוצגות כעת', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpScreen(tester);
    expect(find.text('מוצגות כעת 30 תוצאות'), findsOneWidget);
    expect(
      tester.widget<SearchTermsDisplay>(find.byType(SearchTermsDisplay)).query,
      'כבוד אב',
    );
    expect(
      find.textContaining('כבוד', findRichText: true),
      findsWidgets,
    );
    expect(find.byKey(const ValueKey('semantic-results-query')), findsNothing);
  });

  testWidgets('צמצום מהעץ מחפש בקטגוריה בלי לשנות את ההיקף השמור', (
    tester,
  ) async {
    final harness = await pumpScreen(tester);
    SemanticFacetFiltering tree() =>
        tester.widget(find.byType(SemanticFacetFiltering, skipOffstage: false));

    tree().onSetFacet('/הלכה/id:1');
    await settle(tester);
    expect(harness.tab.resultsBloc.state.options!.facets, ['/הלכה/id:1']);
    expect(harness.tab.options.facets, ['/']);
    expect(tree().selectedFacets, ['/הלכה/id:1']);

    tree().onToggleDimension('/era/ראשונים');
    await settle(tester);
    expect(harness.tab.resultsBloc.state.options!.facets, [
      '/era/ראשונים',
      '/הלכה/id:1',
    ]);

    tree().onClearAll();
    await settle(tester);
    expect(harness.tab.resultsBloc.state.options!.facets, ['/']);
    expect(harness.recorder.searches.last.query, 'כבוד אב');
  });

  testWidgets('כרטיסיית מחשב ששוחזרה במכשיר לא נתמך אינה מריצה חיפוש', (
    tester,
  ) async {
    final harness = await pumpScreen(tester, platformSupported: false);
    expect(find.byKey(const ValueKey('semantic-results-query')), findsNothing);
    expect(find.text('החיפוש אינו זמין כרגע'), findsOneWidget);
    expect(harness.source.fetches, isEmpty);
    expect(harness.recorder.total, 0);
  });
}

/// מחכה לעבודה האסינכרונית האמיתית (פענוח הספר) ולפריימים שאחריה.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}
