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
import 'package:otzaria/search/in_book_search_preferences.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
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

Future<void> _pumpPane(WidgetTester tester) async {
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
  final searchController = TextEditingController();
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
            pdfFilePath: '/nonexistent/test.pdf',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

const _wholeWordTooltip = 'מחפש מילים שלמות בלבד';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await InBookSearchPreferences.saveWholeWord(false);
  });

  testWidgets('new settings pick up a whole-word change from another tab', (
    tester,
  ) async {
    await _pumpPane(tester);
    expect(find.byTooltip(_wholeWordTooltip), findsNothing);

    // Another tab turns the preference on.
    await InBookSearchPreferences.saveWholeWord(true);

    final pane = tester.state<PdfBookSearchViewState>(
      find.byType(PdfBookSearchView),
    );
    pane.applySearchDialogResult(
      const SearchDialogResult(
        query: '',
        searchOptions: {},
        alternativeWords: {},
        spacingValues: {},
        searchMode: SearchMode.exact,
        distance: 0,
      ),
      tester.element(find.byType(PdfBookSearchView)).read<PdfBookBloc>(),
    );
    await tester.pump();

    expect(find.byTooltip(_wholeWordTooltip), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
  });
}
