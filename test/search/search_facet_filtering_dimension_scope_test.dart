import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart' hide UpdateSearchQuery;
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/view/full_text_facet_filtering.dart';
import 'package:otzaria/search/view/search_navigation_tree.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../helpers/memory_settings_cache.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _NoEngineRepository extends SearchRepository {
  const _NoEngineRepository();

  @override
  Stream<SearchStreamUpdate> searchTextsStreamWithCounts(
    SearchEngineRequest request, {
    int chunkSize = 50,
  }) => const Stream.empty();
}

class _TwoBookRepository extends SearchRepository {
  final requests = <SearchEngineRequest>[];
  final List<Book> books;

  _TwoBookRepository(this.books);

  @override
  Stream<SearchStreamUpdate> searchTextsStreamWithCounts(
    SearchEngineRequest request, {
    int chunkSize = 50,
  }) {
    requests.add(request);
    final categories = FacetHelper.categoryFacetsOf(request.facets);
    final matchingBooks = books.where(
      (book) => categories.any(
        (facet) => SearchBloc.facetContains(
          facet,
          FacetHelper.buildBookFacet(book.category!.path, book),
        ),
      ),
    );
    final results = [
      for (final book in matchingBooks)
        SearchResult(
          id: BigInt.from(book.id!),
          title: book.title,
          reference: 'פרק א',
          text: 'שלום',
          segment: BigInt.one,
          isPdf: false,
          filePath: 'id:${book.id}',
          mergedCount: 1,
          merged: const [],
          textStatus: TextStatus.ok,
          continuesToNextLine: false,
        ),
    ];
    return Stream.value(
      SearchStreamUpdate(
        totalCount: results.length,
        bookCounts: {for (final result in results) result.filePath: 1},
        results: results,
        truncated: false,
      ),
    );
  }
}

Library _twoBookLibrary() {
  final category = Category(
    title: 'תנך',
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: [],
    parent: null,
  );
  final library = Library(categories: [category]);
  category.parent = library;
  category.books.addAll([
    TextBook(id: 1, title: 'ספר א', category: category),
    TextBook(id: 2, title: 'ספר ב', category: category),
  ]);
  return library;
}

Future<SearchBloc> _pumpFiltering(
  WidgetTester tester,
  List<String> scope, {
  Library? fixture,
  SearchRepository repository = const _NoEngineRepository(),
  SearchConfiguration? configuration,
}) async {
  final searchBloc = SearchBloc(
    repository: repository,
    initialConfiguration:
        configuration ??
        SearchConfiguration(
          currentFacets: scope,
          searchScopeFacets: scope,
        ),
  );
  final library = fixture ?? Library(categories: []);
  DataRepository.instance.library = Future.value(library);
  final libraryBloc = _MockLibraryBloc();
  whenListen(
    libraryBloc,
    const Stream<LibraryState>.empty(),
    initialState: LibraryState(
      library: library,
      isLoading: false,
      currentCategory: library,
    ),
  );
  final settingsBloc = _MockSettingsBloc();
  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial(),
  );
  final tab = SearchingTab('חיפוש', null);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tab.dispose();
    await searchBloc.close();
    await libraryBloc.close();
    await settingsBloc.close();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<SearchBloc>.value(value: searchBloc),
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: SizedBox(
            width: 320,
            height: 600,
            child: SearchFacetFiltering(tab: tab),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return searchBloc;
}

SearchNavigationTree _tree(WidgetTester tester) =>
    tester.widget<SearchNavigationTree>(find.byType(SearchNavigationTree));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets(
    'עם סינון "ספרי יסוד": לחיצה על קטגוריה ואז על השורש מחזירה לכל ההיקף',
    (tester) async {
      const scope = ['/', '/base'];
      final searchBloc = await _pumpFiltering(tester, scope);

      _tree(tester).onSetFacet('/תנ"ך');
      await tester.pumpAndSettle();
      expect(searchBloc.state.currentFacets, ['/תנ"ך', '/base']);
      expect(searchBloc.state.searchScopeFacets, scope);

      _tree(tester).onSetFacet('/');
      await tester.pumpAndSettle();
      expect(searchBloc.state.currentFacets, scope);
      expect(searchBloc.state.searchScopeFacets, scope);
    },
  );

  testWidgets(
    'עם סינון ממד: ביטול הקטגוריה האחרונה בבחירה מרובה חוזר להיקף ולא לכל הספרייה',
    (tester) async {
      const scope = ['/תנ"ך', '/base'];
      final searchBloc = await _pumpFiltering(tester, scope);

      _tree(tester).onToggleFacet('/תנ"ך');
      await tester.pumpAndSettle();
      expect(searchBloc.state.currentFacets, scope);
      expect(searchBloc.state.searchScopeFacets, scope);
    },
  );

  for (final dimension in ['/base', '/era/ראשונים']) {
    for (final toggle in [false, true]) {
      testWidgets(
        'היקף ספר עם $dimension: בחירת האב (toggle=$toggle) משאירה תוצאות ומניינים בהיקף',
        (tester) async {
          final library = _twoBookLibrary();
          final repository = _TwoBookRepository(library.getAllBooks());
          final scope = ['/תנך/id:1', dimension];
          final bloc = await _pumpFiltering(
            tester,
            scope,
            fixture: library,
            repository: repository,
          );
          bloc.add(UpdateSearchQuery('שלום'));
          await tester.pumpAndSettle();
          expect(bloc.state.results.single.filePath, 'id:1');
          expect(bloc.state.facetCounts['/תנך'], 1);

          if (toggle) {
            _tree(tester).onToggleFacet('/תנך');
          } else {
            await tester.tap(find.text('תנך'));
          }
          await tester.pumpAndSettle();
          expect(repository.requests.last.facets, scope);
          expect(bloc.state.currentFacets, scope);
          expect(bloc.state.searchScopeFacets, scope);
          expect(bloc.state.totalResults, 1);
          expect(bloc.state.results.map((result) => result.filePath), ['id:1']);
          expect(_tree(tester).facetCounts['/תנך'], 1);
          expect(_tree(tester).facetCounts['/תנך/id:2'], isNull);

          _tree(tester).onSetFacet('/');
          await tester.pumpAndSettle();
          expect(bloc.state.currentFacets, scope);
          expect(bloc.state.results.single.filePath, 'id:1');
        },
      );
    }

    testWidgets(
      'היקף שני ספרים עם $dimension: צמצום והרחבה מהעץ משמרים את מנייני שני הספרים',
      (tester) async {
        final library = _twoBookLibrary();
        final repository = _TwoBookRepository(library.getAllBooks());
        final scope = ['/תנך/id:1', '/תנך/id:2', dimension];
        final bloc = await _pumpFiltering(
          tester,
          scope,
          fixture: library,
          repository: repository,
          configuration: SearchConfiguration(
            currentFacets: scope,
            searchScopeFacets: scope,
            searchMode: SearchMode.advanced,
            proximityScope: SearchScope.sameParagraph,
          ),
        );
        bloc.add(
          UpdateSearchQuery(
            'שלום',
            negativeQuery: 'תוהו',
            customSpacing: const {'0-1': '3'},
            alternativeWords: const {
              0: ['ברכה'],
            },
            searchOptions: const {
              'שלום_0': {'ניקוד': true},
            },
            negativeCustomSpacing: const {'0-1': '2'},
            negativeAlternativeWords: const {
              0: ['בהו'],
            },
            negativeSearchOptions: const {
              'תוהו_0': {'טעמים': true},
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(bloc.state.results.map((result) => result.filePath), [
          'id:1',
          'id:2',
        ]);
        expect(_tree(tester).facetCounts['/תנך'], 2);

        _tree(tester).onSetFacet('/תנך/id:1');
        await tester.pumpAndSettle();
        expect(bloc.state.totalResults, 1);
        expect(bloc.state.results.single.filePath, 'id:1');
        expect(bloc.state.searchScopeFacets, scope);
        expect(_tree(tester).facetCounts['/תנך/id:2'], 1);

        _tree(tester).onToggleFacet('/תנך');
        await tester.pumpAndSettle();
        expect(repository.requests.last.facets.toSet(), scope.toSet());
        expect(bloc.state.totalResults, 2);
        expect(bloc.state.results.map((result) => result.filePath), [
          'id:1',
          'id:2',
        ]);
        expect(_tree(tester).facetCounts['/תנך'], 2);
        expect(_tree(tester).facetCounts['/תנך/id:1'], 1);
        expect(_tree(tester).facetCounts['/תנך/id:2'], 1);

        _tree(tester).onToggleFacet('/תנך/id:2');
        await tester.pumpAndSettle();
        expect(bloc.state.results.single.filePath, 'id:1');
        _tree(tester).onToggleFacet('/תנך/id:1');
        await tester.pumpAndSettle();
        expect(bloc.state.currentFacets, scope);
        expect(bloc.state.totalResults, 2);
        expect(bloc.state.searchScopeFacets, scope);
        final request = repository.requests.last;
        expect(request.searchMode, SearchMode.advanced);
        expect(request.scope, SearchScope.sameParagraph);
        expect(request.negativeScope, SearchScope.sameParagraph);
        expect(request.negativeQuery, 'תוהו');
        expect(request.customSpacing, {'0-1': '3'});
        expect(request.alternativeWords, {
          0: ['ברכה'],
        });
        expect(request.searchOptions, {
          'שלום_0': {'ניקוד': true},
        });
        expect(request.negativeCustomSpacing, {'0-1': '2'});
        expect(request.negativeAlternativeWords, {
          0: ['בהו'],
        });
        expect(request.negativeSearchOptions, {
          'תוהו_0': {'טעמים': true},
        });
      },
    );
  }
}
