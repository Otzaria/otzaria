import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/divine_names/repository/divine_names_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as highlights;
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../../support/search_engine_test_init.dart';
import '../../test_helpers/memory_cache_provider.dart';

const _query = 'ללבות דקל';
const _text = 'לבבות דקל';
const _options = {
  'ללבות_0': {
    'שגיאות כתיב': true,
    'קידומות דקדוקיות': true,
    'סיומות דקדוקיות': true,
  },
  'דקל_1': {'קידומות דקדוקיות': true, 'סיומות דקדוקיות': true},
};
const _bodyKey = ValueKey('book-body');

class _DelayedEngine implements SearchEngine {
  final pattern = Completer<HighlightPattern?>();
  int patternRequests = 0;

  @override
  Future<HighlightPattern?> generateIndexHighlightPattern({
    required String query,
    required int distance,
    required Map<String, String> customSpacing,
    required Map<int, List<String>> alternativeWords,
    required Map<String, Map<String, bool>> searchOptions,
    bool? anyOrder,
    int? cancelRequestId,
  }) {
    patternRequests++;
    expectSync(query, _query);
    expectSync(searchOptions, _options);
    return pattern.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Provider extends TantivyDataProvider {
  _Provider(this.searchEngine) : super.forTesting(Future.value(searchEngine));

  final SearchEngine searchEngine;
  int engineReads = 0;

  @override
  Future<SearchEngine> get engine {
    engineReads++;
    return Future.value(searchEngine);
  }
}

class _Repository extends TextBookRepository {
  _Repository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async => const BookContentRange(
    startLine: 0,
    endLine: 0,
    totalLines: 1,
    lines: [_text],
  );

  @override
  Future<String> getBookContent(TextBook book) async => _text;

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async => const [];

  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async =>
      const [];

  @override
  Future<bool> supportsContinuousReadingMode(TextBook book) async => false;
}

class _FileSystem implements FileSystemData {
  @override
  Future<bool> isTanachBook(
    String title, {
    int? categoryId,
    String? fileType,
  }) async => false;

  @override
  Future<Library> getLibrary() async => Library(categories: []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<String> _markedText(WidgetTester tester) {
  final marked = <String>[];
  final hit = AppSurfaces.searchHit(
    Theme.of(tester.element(find.byKey(_bodyKey))).colorScheme,
  );
  void visit(InlineSpan span, TextStyle inherited) {
    if (span is! TextSpan) return;
    final style = inherited.merge(span.style);
    if (span.text != null && style.color == hit) {
      marked.add(span.text!);
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child, style);
    }
  }

  for (final rich in tester.widgetList<RichText>(
    find.descendant(
      of: find.byKey(_bodyKey),
      matching: find.byWidgetPredicate((widget) => widget is RichText),
    ),
  )) {
    visit(rich.text, const TextStyle());
  }
  return marked;
}

Future<void> _closeBook(WidgetTester tester, TextBookBloc bloc) async {
  // Start closing before pumping: the queued-event regressions depend on the
  // event still being pending when close marks the bloc as closed.
  var closed = false;
  final closing = bloc.close().whenComplete(() => closed = true);
  for (var i = 0; i < 100 && !closed; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(closed, isTrue, reason: 'The isolated reader must finish closing.');
  await closing;
  // Content warming is unawaited and may still own its 160ms debounce timer.
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();
  late HighlightPattern indexedPattern;
  var cacheGeneration = 0;

  Future<void> prime(
    String query,
    HighlightPattern pattern, {
    Map<String, Map<String, bool>> options = const {},
  }) => highlights.primeHighlightPattern(
    searchQuery: query,
    searchOptions: options,
    alternativeWords: const {},
    spacingValues: const {},
    searchDistance: 0,
    isFuzzy: false,
    fetch: () async => pattern,
  );

  Future<void> fillOtherQueries() async {
    final generation = cacheGeneration++;
    for (var i = 0; i < 8; i++) {
      await prime(
        'cache$generation-$i',
        const HighlightPattern(
          combinedPattern: 'cache',
          wordPatterns: ['cache'],
          wordBoundaryEligible: [true],
        ),
      );
    }
  }

  group('תבנית הדגשה של חיפוש מדויק עם הרחבות', () {
    setUpAll(() async {
      if (!engineReady) return;
      final directory = Directory.systemTemp.createTempSync(
        'highlight-native-',
      );
      final engine = await SearchEngine.newInstance(path: directory.path);
      try {
        await engine.addDocument(
          ordinal: 0,
          title: 'ספר בדיקה',
          reference: 'קטע ראשון',
          topics: '/highlight',
          text: _text,
          segment: BigInt.zero,
          isPdf: false,
          filePath: 'highlight:book',
        );
        await engine.commit();
        final results = await RustSearchEngineOperations(engine).searchExact(
          const SearchEngineRequest(
            query: _query,
            facets: ['/highlight'],
            limit: 10,
            searchOptions: _options,
          ),
        );
        expect(results, hasLength(1));
        indexedPattern = (await engine.generateIndexHighlightPattern(
          query: _query,
          distance: 0,
          customSpacing: const {},
          alternativeWords: const {},
          searchOptions: _options,
        ))!;
        final local = generateHighlightPattern(
          query: _query,
          distance: 0,
          customSpacing: const {},
          alternativeWords: const {},
          searchOptions: _options,
        )!;
        expect(
          local.matcher!.findMatches(
            data: _text,
            requireTokenBoundaries: local.wordBoundaryEligible,
          ),
          isEmpty,
        );
        expect(
          indexedPattern.matcher!.findMatches(
            data: _text,
            requireTokenBoundaries: indexedPattern.wordBoundaryEligible,
          ),
          hasLength(1),
        );
      } finally {
        engine.dispose();
        directory.deleteSync(recursive: true);
      }
    });

    setUp(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      // LoadContent also reads this singleton directly for the display policy.
      FileSystemData.instance = _FileSystem();
      DataRepository.instance.library = Future.value(Library(categories: []));
      DivineNamesRepository.instance
        ..clear()
        ..debugIsDatabaseBook = (title, {categoryId, fileType}) async => false;
      await fillOtherQueries();
    });

    tearDown(() {
      SmartTextWidget.debugForceHtmlWidget = false;
      DivineNamesRepository.instance
        ..debugIsDatabaseBook = null
        ..clear();
    });

    Future<(TextBookBloc, _DelayedEngine, _Provider)> openBook(
      WidgetTester tester, {
      String query = _query,
      Map<String, Map<String, bool>> options = _options,
      bool forceHtml = false,
    }) async {
      final engine = _DelayedEngine();
      final provider = _Provider(engine);
      TantivyDataProvider.instance = provider;
      final bloc = TextBookBloc(
        repository: _Repository(),
        protectionLoader: (_) async => BookProtection.none,
        bookNotesLoader: (_) async => BookNotes.empty,
        initialState: TextBookInitial.named(
          TextBook(
            title: 'ספר בדיקה',
            id: 1,
            author: 'מחבר בדיקה',
            heCategories: 'בדיקה',
          ),
          0,
          false,
          const [],
          searchText: query,
          searchMode: SearchMode.exact,
          searchOptions: options,
        ),
      );
      addTearDown(() async {
        if (!bloc.isClosed) await _closeBook(tester, bloc);
      });
      addTearDown(() {
        if (!engine.pattern.isCompleted) engine.pattern.complete(null);
      });
      SmartTextWidget.debugForceHtmlWidget = forceHtml;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocBuilder<TextBookBloc, TextBookState>(
              bloc: bloc,
              builder: (context, state) => state is TextBookLoaded
                  ? SmartTextWidget(
                      key: _bodyKey,
                      text: state.content.single,
                      settings: RenderSettings(
                        fontSize: state.fontSize,
                        searchText: state.searchText,
                        searchOptions: state.searchOptions,
                        searchMode: state.searchMode,
                        searchDistance: state.searchDistance,
                        matchPolicy: state.matchPolicy,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );
      bloc.add(
        const LoadContent(
          fontSize: 20,
          showSplitView: false,
          removeNikud: false,
          loadCommentators: false,
        ),
      );
      for (var i = 0; i < 100 && bloc.state is! TextBookLoaded; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(bloc.state, isA<TextBookLoaded>());
      // Drain the initial content-warming debounce even when a red assertion
      // below ends the test before its normal widget cleanup is reached.
      await tester.pump(const Duration(milliseconds: 200));
      return (bloc, engine, provider);
    }

    for (final forceHtml in [false, true]) {
      testWidgets('טאב משוחזר מכין תבנית אחרי שינוי גופן: html=$forceHtml', (
        tester,
      ) async {
        final (bloc, engine, provider) = await openBook(
          tester,
          forceHtml: forceHtml,
        );
        expect(_markedText(tester), isEmpty);
        bloc.add(const UpdateFontSize(32));
        await tester.pump();
        expect(_markedText(tester), isEmpty);
        expect(
          provider.engineReads,
          1,
          reason: 'Restored expanded searches must request the index pattern.',
        );
        expect(engine.patternRequests, 1);
        engine.pattern.complete(indexedPattern);
        await tester.pumpAndSettle();
        expect(_markedText(tester).join(), contains('לבבות'));
        expect(_markedText(tester).join(), contains('דקל'));
        bloc.add(const UpdateFontSize(18));
        await tester.pumpAndSettle();
        expect(_markedText(tester).join(), contains('לבבות'));
        expect(engine.patternRequests, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('שמונה שאילתות אחרות אינן מפנות תבנית של ספר גלוי', (
      tester,
    ) async {
      await prime(_query, indexedPattern, options: _options);
      final (bloc, _, _) = await openBook(tester);
      expect(_markedText(tester).join(), contains('לבבות'));
      // Complete all eight patterns before the next frame: an LRU read alone
      // cannot protect an active book while these completions fill the cache.
      await fillOtherQueries();
      bloc.add(const UpdateFontSize(32));
      await tester.pumpAndSettle();
      expect(
        _markedText(tester).join(),
        contains('לבבות'),
        reason: 'Visible readers must retain their indexed highlight pattern.',
      );
      bloc.add(const UpdateFontSize(18));
      await tester.pumpAndSettle();
      expect(_markedText(tester).join(), contains('לבבות'));
      await tester.pumpWidget(const SizedBox.shrink());
      await _closeBook(tester, bloc);
      await fillOtherQueries();
      expect(
        highlights.computeHighlightRanges(
          _text,
          _query,
          searchOptions: _options,
        ),
        isEmpty,
      );
    });

    testWidgets('טאב ברקע משחרר תבנית ומכין אותה שוב כשחוזרים אליו', (
      tester,
    ) async {
      await prime(_query, indexedPattern, options: _options);
      final (bloc, engine, _) = await openBook(tester);
      expect(_markedText(tester).join(), contains('לבבות'));
      bloc.add(const SetTabVisibility(false));
      await tester.pump();
      await fillOtherQueries();
      await tester.pump();
      expect(
        highlights.computeHighlightRanges(
          _text,
          _query,
          searchOptions: _options,
        ),
        isEmpty,
      );
      bloc.add(const SetTabVisibility(true));
      await tester.pump();
      expect(
        engine.patternRequests,
        1,
        reason: 'Returning to a reader must reload its evicted index pattern.',
      );
      engine.pattern.complete(indexedPattern);
      // Returning to a visible reader starts another warming debounce.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(_markedText(tester).join(), contains('לבבות'));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('שינוי אפשרויות מכין תבנית והחלפת השאילתה משחררת אותה', (
      tester,
    ) async {
      final (bloc, engine, provider) = await openBook(
        tester,
        options: const {},
      );
      expect(provider.engineReads, 0);
      bloc.add(const UpdateSearchText(_query, searchOptions: _options));
      await tester.pump();
      expect(
        engine.patternRequests,
        1,
        reason: 'Changed expansion options must request the new index pattern.',
      );
      engine.pattern.complete(indexedPattern);
      await tester.pumpAndSettle();
      expect(_markedText(tester).join(), contains('לבבות'));
      bloc.add(const UpdateSearchText('דקל', searchOptions: {}));
      await tester.pump();
      await fillOtherQueries();
      await tester.pumpAndSettle();
      expect(provider.engineReads, 1);
      expect(
        highlights.computeHighlightRanges(
          _text,
          _query,
          searchOptions: _options,
        ),
        isEmpty,
      );
      expect(_markedText(tester).join(), contains('דקל'));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('קישור מסומן משחרר את תבנית החיפוש שנמחקה', (tester) async {
      await prime(_query, indexedPattern, options: _options);
      final (bloc, _, provider) = await openBook(tester);
      final engineReads = provider.engineReads;
      bloc.add(
        const ApplyMarkHighlight(
          highlightText: 'דקל',
          permanentHighlightLine: 0,
        ),
      );
      await tester.pump();
      expect((bloc.state as TextBookLoaded).searchText, isEmpty);
      expect((bloc.state as TextBookLoaded).highlightText, 'דקל');
      await fillOtherQueries();
      expect(
        highlights.computeHighlightRanges(
          _text,
          _query,
          searchOptions: _options,
        ),
        isEmpty,
        reason:
            'Applying a marked link must release the previous search pattern.',
      );
      bloc.add(const SetTabVisibility(false));
      await tester.pump();
      bloc.add(const SetTabVisibility(true));
      // Visibility restarts warming independently of the highlight pattern.
      await tester.pump(const Duration(milliseconds: 200));
      expect(provider.engineReads, engineReads);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final reload in [false, true]) {
      testWidgets(
        reload
            ? 'טעינה חוזרת ממתינה בסגירה אינה משאירה תבנית נעולה'
            : 'אירוע חיפוש ממתין בסגירה אינו משאיר תבנית נעולה',
        (tester) async {
          final query = reload ? '$_query ' : _query;
          await prime(query, indexedPattern, options: _options);
          final (bloc, _, provider) = await openBook(
            tester,
            query: query,
            options: reload ? _options : const {},
          );
          final engineReads = provider.engineReads;
          bloc.add(
            reload
                ? const LoadContent(
                    fontSize: 20,
                    showSplitView: false,
                    removeNikud: false,
                    loadCommentators: false,
                    preserveState: true,
                  )
                : const UpdateSearchText(_query, searchOptions: _options),
          );
          await _closeBook(tester, bloc);
          await tester.pump();
          await fillOtherQueries();
          expect(
            highlights.computeHighlightRanges(
              _text,
              query,
              searchOptions: _options,
            ),
            isEmpty,
            reason: 'Pending events must not retain a closed reader pattern.',
          );
          expect(provider.engineReads, engineReads);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }

    for (final query in ['', 'לבבות דקל', '/לבבות/']) {
      testWidgets('שאילתה מקומית "$query" אינה פותחת את מנוע האינדקס', (
        tester,
      ) async {
        final (_, engine, provider) = await openBook(
          tester,
          query: query,
          options: const {},
        );
        expect(provider.engineReads, 0);
        expect(engine.patternRequests, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }, skip: engineReady ? false : searchEngineSkipReason);
}
