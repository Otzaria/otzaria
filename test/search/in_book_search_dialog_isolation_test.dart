import 'dart:async';
import 'dart:io';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
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
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/view/advanced_search_controls.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/text_book_search_screen.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  late Directory dataRoot;
  setUpAll(() async {
    dataRoot = await Directory.systemTemp.createTemp('in-book-dialog-test-');
    AppPaths.debugOverrideDataRootPath(dataRoot.path);
    TantivyDataProvider.instance = _IdleIndex();
  });
  tearDownAll(() async {
    AppPaths.debugOverrideDataRootPath(null);
    await dataRoot.delete(recursive: true);
  });

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    DataRepository.instance.library = Future.value(Library(categories: []));
  });

  for (final pdf in [false, true]) {
    testWidgets(
      '${pdf ? 'PDF' : 'טקסט'}: ביטול מבודד את ההגדרות ופתיחה חוזרת אחרי חיפוש מאפשרת עריכה (issue #1734)',
      (tester) async {
        final previous = SearchQueryBuilder.normalizeParametersForMode(
          SearchMode.advanced,
          alternativeWords: {
            0: ['שלם'],
          },
          searchOptions: {
            'שלום_0': {'קידומות': true},
          },
          customSpacing: {'שלום_0': '2'},
        );
        await _pumpSearchView(tester, pdf: pdf, previous: previous);

        Future<SearchingTab> openDialog() async {
          await tester.tap(find.byTooltip('הגדרות חיפוש'));
          await _settle(tester);
          expect(find.byType(SearchDialog), findsOneWidget);
          final tab = tester
              .widget<AdvancedSearchControls>(
                find.byType(AdvancedSearchControls),
              )
              .tab;
          tab.queryController.selection = const TextSelection.collapsed(
            offset: 2,
          );
          await tester.pump();
          return tab;
        }

        Future<void> addAlternative(String word) async {
          final field = find.byWidgetPredicate(
            (widget) =>
                widget is RtlTextField &&
                widget.decoration?.labelText == 'מילה חילופית',
          );
          await tester.ensureVisible(field);
          await tester.enterText(field, word);
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();
          expect(tester.takeException(), isNull);
        }

        final cancelled = await openDialog();
        await addAlternative('שולם');
        cancelled.searchOptions['שלום_0']!['סיומות'] = true;
        cancelled.spacingValues['שלום_0'] = '9';
        await tester.tap(find.byTooltip('סגור'));
        await _settle(tester);
        await tester.pump(const Duration(milliseconds: 600));

        final accepted = await openDialog();
        expect(accepted.alternativeWords, {
          0: ['שלם'],
        });
        expect(accepted.searchOptions, {
          'שלום_0': {'קידומות': true},
        });
        expect(accepted.spacingValues, {'שלום_0': '2'});
        expect(previous.alternativeWords, {
          0: ['שלם'],
        });
        expect(previous.searchOptions, {
          'שלום_0': {'קידומות': true},
        });
        expect(previous.customSpacing, {'שלום_0': '2'});
        await addAlternative('שולם');
        await tester.tap(find.byTooltip('חפש'));
        await _settle(tester);
        await tester.pump(const Duration(milliseconds: 600));

        final reopened = await openDialog();
        expect(reopened.alternativeWords[0], ['שלם', 'שולם']);
        final remove = find.descendant(
          of: find.widgetWithText(ListTile, 'שלם'),
          matching: find.byType(IconButton),
        );
        await tester.ensureVisible(remove);
        await tester.tap(remove);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await addAlternative('שלום');
        expect(reopened.alternativeWords[0], ['שולם', 'שלום']);
        await tester.tap(find.byTooltip('סגור'));
        await _settle(tester);
        await tester.pump(const Duration(milliseconds: 600));
      },
      skip: !engineReady,
    );

    testWidgets(
      '${pdf ? 'PDF' : 'טקסט'}: אפשרויות חיפוש מדויק נשמרות ומוצגות אחרי אישור ועריכה',
      (tester) async {
        await _pumpSearchView(
          tester,
          pdf: pdf,
          previous: const SearchModeScopedParameters(),
          searchMode: SearchMode.exact,
        );

        Future<SearchingTab> openDialog() async {
          await tester.tap(find.byTooltip('הגדרות חיפוש'));
          await _settle(tester);
          return tester
              .widget<SearchDialog>(find.byType(SearchDialog))
              .existingTab!;
        }

        Finder option(String label) => find.widgetWithText(FilterChip, label);

        Future<void> submit() async {
          await tester.tap(find.byTooltip('חפש'));
          await _settle(tester);
          await tester.pump(const Duration(milliseconds: 600));
        }

        await openDialog();
        await tester.tap(option('קידומות דקדוקיות'));
        await tester.pump();
        await submit();

        final reopened = await openDialog();
        expect(
          tester.widget<FilterChip>(option('קידומות דקדוקיות')).selected,
          isTrue,
        );
        expect(reopened.effectiveSearchOptions(), {
          'שלום_0': {'קידומות דקדוקיות': true},
          'עולם_1': {'קידומות דקדוקיות': true},
        });
        await tester.tap(option('סיומות דקדוקיות'));
        await tester.pump();
        await submit();

        final edited = await openDialog();
        expect(
          tester.widget<FilterChip>(option('קידומות דקדוקיות')).selected,
          isTrue,
        );
        expect(
          tester.widget<FilterChip>(option('סיומות דקדוקיות')).selected,
          isTrue,
        );
        expect(edited.effectiveSearchOptions(), {
          'שלום_0': {'קידומות דקדוקיות': true, 'סיומות דקדוקיות': true},
          'עולם_1': {'קידומות דקדוקיות': true, 'סיומות דקדוקיות': true},
        });
        await tester.tap(option('קידומות דקדוקיות'));
        await tester.pump();
        await submit();

        final disabled = await openDialog();
        expect(
          tester.widget<FilterChip>(option('קידומות דקדוקיות')).selected,
          isFalse,
        );
        expect(
          tester.widget<FilterChip>(option('סיומות דקדוקיות')).selected,
          isTrue,
        );
        expect(disabled.effectiveSearchOptions(), {
          'שלום_0': {'סיומות דקדוקיות': true},
          'עולם_1': {'סיומות דקדוקיות': true},
        });
        disabled.queryController.text = 'שלום גדול עולם';
        await tester.pump();
        await submit();
        final changedQuery = await openDialog();
        expect(changedQuery.effectiveSearchOptions(), {
          'שלום_0': {'סיומות דקדוקיות': true},
          'גדול_1': {'סיומות דקדוקיות': true},
          'עולם_2': {'סיומות דקדוקיות': true},
        });
        await tester.tap(find.byTooltip('סגור'));
        await _settle(tester);
      },
      skip: !engineReady,
    );

    for (final mode in [SearchMode.advanced, SearchMode.exact]) {
      testWidgets(
        '${pdf ? 'PDF' : 'טקסט'}: אפשרויות מעורבות נשמרות פר-מילה ב-$mode',
        (tester) async {
          final previous = SearchQueryBuilder.normalizeParametersForMode(
            mode,
            searchOptions: {
              'שלום_0': {'קידומות דקדוקיות': true},
              'עולם_1': {'סיומות דקדוקיות': true},
            },
          );
          await _pumpSearchView(
            tester,
            pdf: pdf,
            previous: previous,
            searchMode: mode,
          );

          Future<SearchingTab> openDialog() async {
            await tester.tap(find.byTooltip('הגדרות חיפוש'));
            await _settle(tester);
            return tester
                .widget<SearchDialog>(find.byType(SearchDialog))
                .existingTab!;
          }

          final tab = await openDialog();
          expect(tab.useGlobalSearchOptions.value, isFalse);
          expect(tab.effectiveSearchOptions(), previous.searchOptions);
          await tester.tap(find.byTooltip('חפש'));
          await _settle(tester);
          final reopened = await openDialog();
          expect(reopened.useGlobalSearchOptions.value, isFalse);
          expect(reopened.effectiveSearchOptions(), previous.searchOptions);
          await tester.tap(find.byTooltip('סגור'));
          await _settle(tester);
        },
        skip: !engineReady,
      );
    }
  }
}

Future<void> _pumpSearchView(
  WidgetTester tester, {
  required bool pdf,
  required SearchModeScopedParameters previous,
  SearchMode searchMode = SearchMode.advanced,
}) async {
  await tester.binding.setSurfaceSize(const Size(1100, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final navigation = _NavigationBloc();
  whenListen(
    navigation,
    const Stream<NavigationState>.empty(),
    initialState: const NavigationState(currentScreen: Screen.reading),
  );
  final settings = _SettingsBloc();
  final indexing = _IndexingBloc();
  final history = _HistoryBloc();
  final library = _LibraryBloc();
  final text = _TextBloc();
  final pdfBloc = _PdfBloc();
  whenListen(
    settings,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial(),
  );
  whenListen(
    indexing,
    const Stream<IndexingState>.empty(),
    initialState: IndexingInitial(),
  );
  whenListen(
    history,
    const Stream<HistoryState>.empty(),
    initialState: HistoryLoaded([]),
  );
  whenListen(
    library,
    const Stream<LibraryState>.empty(),
    initialState: const LibraryState(),
  );
  whenListen(
    text,
    const Stream<TextBookState>.empty(),
    initialState: _textState(),
  );
  whenListen(
    pdfBloc,
    const Stream<PdfBookState>.empty(),
    initialState: PdfBookLoaded(
      book: PdfBook(title: 'ספר בדיקה', path: '/nonexistent/test.pdf'),
      currentPageNumber: 1,
      totalPages: 10,
      isLoading: false,
    ),
  );
  final focus = FocusNode();
  final controller = TextEditingController(text: 'שלום עולם');
  final searcher = PdfTextSearcher(_ReadyController());
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    for (final bloc in [
      navigation,
      settings,
      indexing,
      history,
      library,
      text,
      pdfBloc,
    ]) {
      await bloc.close();
    }
    focus.dispose();
    controller.dispose();
    searcher.dispose();
  });
  final view = pdf
      ? PdfBookSearchView(
          textSearcher: searcher,
          searchController: controller,
          focusNode: focus,
          bookTitle: 'ספר בדיקה',
          bookTopics: 'תנך',
          pdfFilePath: '/nonexistent/test.pdf',
          initialSearchMode: searchMode,
          initialSearchOptions: previous.searchOptions,
          initialAlternativeWords: previous.alternativeWords,
          initialSpacingValues: previous.customSpacing,
          searchRepository: _EmptySearchRepository(),
        )
      : TextBookSearchView(
          contentLoader: () async => ['שלום עולם'],
          scrollControler: ItemScrollController(),
          focusNode: focus,
          closeLeftPaneCallback: () {},
          initialQuery: 'שלום עולם',
          initialSearchMode: searchMode,
          initialSearchOptions: previous.searchOptions,
          initialAlternativeWords: previous.alternativeWords,
          initialSpacingValues: previous.customSpacing,
          searchRepository: _EmptySearchRepository(),
        );
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<NavigationBloc>.value(value: navigation),
        BlocProvider<SettingsBloc>.value(value: settings),
        BlocProvider<IndexingBloc>.value(value: indexing),
        BlocProvider<HistoryBloc>.value(value: history),
        BlocProvider<LibraryBloc>.value(value: library),
        BlocProvider<TextBookBloc>.value(value: text),
        BlocProvider<PdfBookBloc>.value(value: pdfBloc),
      ],
      child: MaterialApp(home: Scaffold(body: view)),
    ),
  );
  await _settle(tester);
}

class _SettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _IndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class _HistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class _LibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _TextBloc extends MockBloc<TextBookEvent, TextBookState>
    implements TextBookBloc {}

class _PdfBloc extends MockBloc<PdfBookEvent, PdfBookState>
    implements PdfBookBloc {}

class _Document extends Fake implements PdfDocument {
  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();
}

class _ReadyController extends PdfViewerController {
  @override
  bool get isReady => true;
  @override
  int? get pageNumber => null;
  @override
  PdfDocument get document => _Document();
  @override
  void invalidate() {}
  @override
  FutureOr<T?> useDocument<T>(
    FutureOr<T> Function(PdfDocument) task, {
    bool ensureLoaded = true,
    Completer<dynamic>? cancelLoading,
  }) => null;
}

TextBookLoaded _textState() => TextBookLoaded(
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: true,
  content: const ['שלום עולם'],
  fontSize: 18,
  showSplitView: false,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  visibleLinks: const [],
  linksByLine: const {},
  tableOfContents: const [],
  removeNikud: false,
  visibleIndices: const [0],
  selectedIndex: 0,
  pinLeftPane: false,
  searchText: '',
  scrollController: ItemScrollController(),
  positionsListener: ItemPositionsListener.create(),
);

class _EmptySearchRepository extends SearchRepository {
  @override
  Future<List<SearchResult>> searchTexts(SearchEngineRequest request) async =>
      const [];
}

class _NavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

class _IdleIndex extends Fake implements TantivyDataProvider {
  @override
  final Future<SearchEngine> engine = Future.value(_EmptyEngine());
  @override
  final ValueNotifier<bool> isInitialized = ValueNotifier(false);
  @override
  final ValueNotifier<bool> isIndexing = ValueNotifier(false);
  @override
  final Set<String> indexedFilePaths = {};
}

class _EmptyEngine extends Fake implements SearchEngine {
  @override
  Future<BigInt> getBookTextFingerprint({required String filePath}) async =>
      BigInt.zero;
}
