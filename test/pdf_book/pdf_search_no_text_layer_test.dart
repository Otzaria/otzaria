import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
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

/// קונטרולר "מוכן" בלי PdfViewer אמיתי — [PdfTextSearchSession] דורש מסמך חי
/// בבנייה, ו-useDocument מוחזר null כדי שהחיפוש לא יגע ב-pdfium.
class _FakeReadyController extends PdfViewerController {
  _FakeReadyController({this.visiblePage});

  final int? visiblePage;

  @override
  bool get isReady => true;

  @override
  int? get pageNumber => visiblePage;

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

/// מחזיר שכבת טקסט קבועה לכל עמוד, במקום לטעון מ-pdfium.
class _FakeTextSearcher extends PdfTextSearchSession {
  _FakeTextSearcher(super.controller, this.pageFullText);

  final String pageFullText;
  final List<int> requestedPages = [];

  // pdfrx מסמן חיפוש פעיל לפני useDocument, והקונטרולר המזויף לא מריץ אותו.
  @override
  bool get isSearching => false;

  @override
  double get searchProgress => 1;

  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async {
    requestedPages.add(pageNumber);
    return PdfPageText(
      pageNumber: pageNumber,
      fullText: pageFullText,
      charRects: const [],
      fragments: const [],
    );
  }
}

/// שכבת טקסט אופיינית ל-PDF סרוק של ABBYY: פיסוק וספרות בלבד, בלי אף
/// אות עברית — ואינה ריקה, ולכן בדיקת isEmpty לא הייתה תופסת אותה.
final String _scannedOnlyPageText = List.generate(
  120,
  (i) => '.,;:${i % 10}"\'()[]-',
).join(' ');

PdfBookLoaded _loadedState() => PdfBookLoaded(
  book: PdfBook(title: 'ספר בדיקה', path: '/nonexistent/test.pdf'),
  currentPageNumber: 3,
  totalPages: 12,
  isLoading: false,
);

Future<void> _pumpSearchView(
  WidgetTester tester,
  PdfTextSearchSession textSearcher,
  TextEditingController searchController,
  FocusNode focusNode,
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
    initialState: _loadedState(),
  );
  addTearDown(settingsBloc.close);
  addTearDown(pdfBookBloc.close);

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('ספר בלי אות עברית בשכבת הטקסט מציג שהספר סריקה בלבד', (
    tester,
  ) async {
    final searchController = TextEditingController(text: 'אשר');
    final focusNode = FocusNode();
    final textSearcher = _FakeTextSearcher(
      _FakeReadyController(),
      _scannedOnlyPageText,
    );
    addTearDown(searchController.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(textSearcher.dispose);

    await _pumpSearchView(tester, textSearcher, searchController, focusNode);

    expect(_scannedOnlyPageText.isNotEmpty, isTrue);
    expect(find.text('אין תוצאות'), findsOneWidget);

    // סיום סריקה ללא התאמות.
    textSearcher.notifyListeners();
    await tester.pump();
    await tester.pump();

    expect(find.text(PdfMessages.noTextLayer), findsOneWidget);
    expect(find.text('אין תוצאות'), findsNothing);
    // העמוד המוצג נדגם ראשון, ולא רק עמוד 1 שעלול להיות שער ריק.
    expect(textSearcher.requestedPages.first, 3);
  });

  testWidgets('הדגימה מתחילה מהעמוד המוצג בפועל ולא מעמוד הפתיחה שב-state', (
    tester,
  ) async {
    final searchController = TextEditingController(text: 'אשר');
    final focusNode = FocusNode();
    final textSearcher = _FakeTextSearcher(
      _FakeReadyController(visiblePage: 7),
      _scannedOnlyPageText,
    );
    addTearDown(searchController.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(textSearcher.dispose);

    await _pumpSearchView(tester, textSearcher, searchController, focusNode);
    textSearcher.notifyListeners();
    await tester.pump();
    await tester.pump();

    // ה-state נשאר בעמוד הפתיחה (3); המשתמש גלל לעמוד 7.
    expect(textSearcher.requestedPages.first, 7);
  });

  testWidgets('ספר עם טקסט עברי ובלי התאמות נשאר ב"אין תוצאות"', (
    tester,
  ) async {
    final searchController = TextEditingController(text: 'אשר');
    final focusNode = FocusNode();
    final textSearcher = _FakeTextSearcher(
      _FakeReadyController(),
      'בראשית ברא אלהים את השמים ואת הארץ',
    );
    addTearDown(searchController.dispose);
    addTearDown(focusNode.dispose);
    addTearDown(textSearcher.dispose);

    await _pumpSearchView(tester, textSearcher, searchController, focusNode);

    textSearcher.notifyListeners();
    await tester.pump();
    await tester.pump();

    expect(find.text(PdfMessages.noTextLayer), findsNothing);
    expect(find.text('אין תוצאות'), findsOneWidget);
  });

  group('דגימת עמודים לבדיקת הטקסט', () {
    test('דוגמת את העמוד המוצג ועוד שניים פרושים על הספר', () {
      expect(
        PdfBookSearchView.textLayerProbePages(currentPage: 3, totalPages: 12),
        [3, 4, 8],
      );
    });

    test('ספר קצר ועמוד מחוץ לטווח אינם חורגים מגבולות הספר', () {
      expect(
        PdfBookSearchView.textLayerProbePages(currentPage: 99, totalPages: 1),
        [1],
      );
      expect(
        PdfBookSearchView.textLayerProbePages(currentPage: 1, totalPages: 0),
        isEmpty,
      );
    });
  });

  group('קריטריון הטקסט השמיש', () {
    test('פיסוק וספרות בלבד אינם טקסט שמיש', () {
      expect(
        PdfBookSearchView.hasSearchableText([_scannedOnlyPageText]),
        isFalse,
      );
    });

    test('אות עברית או אנגלית בעמוד כלשהו מספיקה', () {
      expect(
        PdfBookSearchView.hasSearchableText(['123', '', 'ץ']),
        isTrue,
      );
      expect(
        PdfBookSearchView.hasSearchableText(['123', '', 'English']),
        isTrue,
      );
    });
  });
}
