import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:otzaria/search/in_book_search_settings.dart';
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

class _ManyResultsRepository extends SearchRepository {
  _ManyResultsRepository(this.count);

  final int count;
  final limits = <int>[];

  @override
  Future<List<SearchResult>> searchTexts(SearchEngineRequest request) async {
    limits.add(request.limit);
    return [
      for (var i = 0; i < count; i++)
        SearchResult(
          id: BigInt.from(i),
          title: 'ספר בדיקה',
          reference: 'עמוד ${i + 1}',
          text: 'אב',
          segment: BigInt.from(i),
          isPdf: true,
          filePath: '/nonexistent/test.pdf',
          mergedCount: 1,
          merged: const [],
          textStatus: TextStatus.ok,
          continuesToNextLine: false,
        ),
    ];
  }
}

Future<void> _pumpEngineSearch(
  WidgetTester tester,
  _ManyResultsRepository repository,
) async {
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
            bookTitle: 'ספר בדיקה',
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('shows the first results and says that there are more', (
    tester,
  ) async {
    final repository = _ManyResultsRepository(kInBookResultsShown + 200);
    await _pumpEngineSearch(tester, repository);
    await settle(tester);

    expect(repository.limits.last, kInBookEngineFetchLimit);
    expect(
      find.text('מוצגות $kInBookResultsShown התוצאות הראשונות'),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('counts all the results when they fit', (tester) async {
    await _pumpEngineSearch(tester, _ManyResultsRepository(3));
    await settle(tester);

    expect(find.text('נמצאו 3 תוצאות'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
  });
}
