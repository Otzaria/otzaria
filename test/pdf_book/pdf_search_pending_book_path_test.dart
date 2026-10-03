import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:pdfrx/pdfrx.dart';

import '../test_helpers/memory_cache_provider.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockPdfBookBloc extends MockBloc<PdfBookEvent, PdfBookState>
    implements PdfBookBloc {}

class _FakeDocument extends Fake implements PdfDocument {
  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();
}

class _FakeReadyController extends PdfViewerController {
  @override
  bool get isReady => true;

  @override
  int? get pageNumber => null;

  @override
  PdfDocument get document => _FakeDocument();

  @override
  void invalidate() {}

  @override
  FutureOr<T?> useDocument<T>(
    FutureOr<T> Function(PdfDocument document) task, {
    bool ensureLoaded = true,
    Completer<dynamic>? cancelLoading,
  }) => null;
}

class _CountingSearchRepository extends SearchRepository {
  int calls = 0;

  @override
  Future<List<SearchResult>> searchTexts(
    String query,
    List<String> facets,
    int limit, {
    int offset = 0,
    ResultsOrder order = ResultsOrder.relevance,
    bool fuzzy = false,
    int distance = 0,
    String negativeQuery = '',
    int? negativeDistance,
    SearchScope scope = SearchScope.wordDistance,
    SearchScope? negativeScope,
    SearchMode searchMode = SearchMode.exact,
    Map<String, String>? customSpacing,
    Map<String, String>? negativeCustomSpacing,
    Map<int, List<String>>? alternativeWords,
    Map<int, List<String>>? negativeAlternativeWords,
    Map<String, Map<String, bool>>? searchOptions,
    Map<String, Map<String, bool>>? negativeSearchOptions,
    bool matchNikud = false,
    bool matchTaamim = false,
    ResultGrouping? grouping,
    WordMatchMode wordMatchMode = WordMatchMode.all,
    int? wordMatchCount,
  }) async {
    calls++;
    return const [];
  }
}

Future<_CountingSearchRepository> _pumpEngineSearch(
  WidgetTester tester, {
  required String? bookTitle,
}) async {
  final settingsBloc = _MockSettingsBloc();
  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial(),
  );
  final pdfBookBloc = _MockPdfBookBloc();
  whenListen(
    pdfBookBloc,
    const Stream<PdfBookState>.empty(),
    initialState: PdfBookLoaded(
      book: PdfBook(title: 'ספר בדיקה', path: '/nonexistent/test.pdf'),
      currentPageNumber: 1,
      totalPages: 10,
      isLoading: false,
    ),
  );
  final searchController = TextEditingController(text: 'אב');
  final focusNode = FocusNode();
  final textSearcher = PdfTextSearcher(_FakeReadyController());
  final repository = _CountingSearchRepository();

  addTearDown(settingsBloc.close);
  addTearDown(pdfBookBloc.close);
  addTearDown(searchController.dispose);
  addTearDown(focusNode.dispose);
  addTearDown(textSearcher.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<PdfBookBloc>.value(value: pdfBookBloc),
        ],
        child: Scaffold(
          body: PdfBookSearchView(
            textSearcher: textSearcher,
            searchController: searchController,
            focusNode: focusNode,
            bookTitle: bookTitle,
            bookTopics: 'תנך',
            pdfFilePath: '/nonexistent/test.pdf',
            // Fuzzy mode takes the engine route, which needs the book path.
            initialSearchMode: SearchMode.fuzzy,
            initialSearchDistance: 2,
            searchRepository: repository,
          ),
        ),
      ),
    ),
  );
  return repository;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('while the book is identified the search shows as running', (
    tester,
  ) async {
    await _pumpEngineSearch(tester, bookTitle: 'ספר בדיקה');

    expect(find.text('אין תוצאות'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('a book that cannot be identified shows a search error', (
    tester,
  ) async {
    final repository = await _pumpEngineSearch(tester, bookTitle: null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(PdfMessages.searchError), findsOneWidget);
    expect(find.text('אין תוצאות'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(repository.calls, 0);

    await tester.pump(const Duration(milliseconds: 800));
  });
}
