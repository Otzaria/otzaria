import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/search_engine_test_init.dart';
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

/// מצב סריקה והתאמות נשלטים מהבדיקה; פעולות הניווט נרשמות.
class _ControlledSearcher extends PdfTextSearchSession {
  _ControlledSearcher(super.controller);

  List<PdfTextSearchResult> current = const [];
  bool scanning = false;
  int? index;
  final actions = <String>[];

  @override
  List<PdfTextSearchResult> get matches => current;

  @override
  bool get isSearching => scanning;

  @override
  int? get currentIndex => index;

  @override
  void startTextSearch(
    Pattern pattern, {
    bool caseInsensitive = true,
    bool goToFirstMatch = true,
    bool searchImmediately = false,
    int? startPageNumber,
  }) {}

  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async => PdfPageText(
    pageNumber: pageNumber,
    fullText: 'שלום עולם',
    charRects: const [],
    fragments: const [],
  );

  @override
  Future<int> goToNextMatch() async {
    actions.add('next');
    return 0;
  }

  @override
  Future<int> goToPrevMatch() async {
    actions.add('prev');
    return 0;
  }

  @override
  void stopTextSearch() => actions.add('stop');
}

PdfTextSearchResult _match(int page) => PdfTextSearchResult.fromRange(
  PdfPageTextRange(
    pageText: PdfPageText(
      pageNumber: page,
      fullText: 'שלום עולם',
      charRects: List.filled(9, const PdfRect(0, 1, 1, 0)),
      fragments: const [],
    ),
    start: 0,
    end: 4,
  ),
);

Future<_ControlledSearcher> _pump(
  WidgetTester tester, {
  ValueChanged<int>? onNavigationStarted,
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
      totalPages: 12,
      isLoading: false,
    ),
  );
  final searchController = TextEditingController(text: 'שלום');
  final focusNode = FocusNode();
  final searcher = _ControlledSearcher(_FakeReadyController());
  addTearDown(settingsBloc.close);
  addTearDown(pdfBookBloc.close);
  addTearDown(searchController.dispose);
  addTearDown(focusNode.dispose);
  addTearDown(searcher.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<PdfBookBloc>.value(value: pdfBookBloc),
        ],
        child: Scaffold(
          body: SizedBox(
            width: 400,
            child: PdfBookSearchView(
              textSearcher: searcher,
              searchController: searchController,
              focusNode: focusNode,
              pdfFilePath: '/nonexistent/test.pdf',
              onNavigationStarted: onNavigationStarted,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return searcher;
}

Future<void> _notify(WidgetTester tester, _ControlledSearcher s) async {
  s.notifyListeners();
  await tester.pump();
  await tester.pump();
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineReady = await tryInitSearchEngine();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('סרגל התוצאות בחיפוש הפשוט', () {
    testWidgets('נקודת החזרה נשמרת לפני ניווט לתוצאה הבאה', (tester) async {
      late _ControlledSearcher searcher;
      final targets = <int>[];
      searcher = await _pump(
        tester,
        onNavigationStarted: (page) {
          expect(searcher.actions, isEmpty);
          targets.add(page);
        },
      );
      searcher
        ..current = [_match(2), _match(3), _match(5)]
        ..index = 0;
      await _notify(tester, searcher);
      await tester.tap(find.byTooltip('התוצאה הבאה'));
      expect(targets, [3]);
      expect(searcher.actions, ['next']);
    });

    testWidgets('בזמן סריקה — כפתור עצירה שעוצר את ה-searcher', (tester) async {
      final searcher = await _pump(tester);
      searcher
        ..scanning = true
        ..current = [_match(2)];
      await _notify(tester, searcher);

      await tester.tap(find.byTooltip('עצור את החיפוש'));
      expect(searcher.actions, ['stop']);
    });

    testWidgets('אחרי הסריקה — אין עצירה; הבאה/הקודמת לפי המיקום', (
      tester,
    ) async {
      final searcher = await _pump(tester);
      searcher
        ..current = [_match(2), _match(3), _match(5)]
        ..index = 0;
      await _notify(tester, searcher);

      expect(find.byTooltip('עצור את החיפוש'), findsNothing);
      expect(find.text('תוצאה 1 מתוך 3'), findsOneWidget);

      await tester.tap(find.byTooltip('התוצאה הקודמת'));
      await tester.tap(find.byTooltip('התוצאה הבאה'));
      expect(searcher.actions, ['next']);
    });

    testWidgets('בלי תוצאות ובלי סריקה — אין סרגל', (tester) async {
      final searcher = await _pump(tester);
      await _notify(tester, searcher);
      expect(find.byTooltip('התוצאה הבאה'), findsNothing);
    });
  }, skip: engineReady ? false : searchEngineSkipReason);

  testWidgets('טעינה חוזרת מעבירה את מאזין התוצאות ל-searcher החדש', (
    tester,
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
        totalPages: 12,
        isLoading: false,
      ),
    );
    final searchController = TextEditingController();
    final focusNode = FocusNode();
    final controller = _FakeReadyController();
    final first = _ControlledSearcher(controller);
    final second = _ControlledSearcher(controller);
    addTearDown(settingsBloc.close);
    addTearDown(pdfBookBloc.close);
    addTearDown(searchController.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    Widget view(_ControlledSearcher searcher) => MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<PdfBookBloc>.value(value: pdfBookBloc),
        ],
        child: Scaffold(
          body: SizedBox(
            width: 400,
            child: PdfBookSearchView(
              textSearcher: searcher,
              searchController: searchController,
              focusNode: focusNode,
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(view(first));
    first.current = [_match(2)];
    await _notify(tester, first);
    expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);

    await tester.pumpWidget(view(second));
    final page3 = _match(3);
    second.current = [page3];
    await _notify(tester, second);
    expect(find.text('נמצאו 1 תוצאות'), findsOneWidget);

    second.current = [page3, _match(4)];
    await _notify(tester, second);
    expect(find.text('נמצאו 2 תוצאות'), findsOneWidget);
    expect(find.text('עמוד 3'), findsOneWidget);
    expect(find.text('עמוד 4'), findsOneWidget);
  });
}
