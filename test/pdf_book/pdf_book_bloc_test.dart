import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/memory_settings_cache.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:path/path.dart' as path;
import 'package:pdfrx/pdfrx.dart';

// ─── fakes ───────────────────────────────────────────────────────────────────
class _FakeDocumentRef extends Fake implements PdfDocumentRef {}

class _ReadyPdfViewerController extends PdfViewerController {
  double? lastZoom;

  @override
  bool get isReady => true;

  @override
  Offset get centerPosition => Offset.zero;

  @override
  Future<void> setZoom(
    Offset position,
    double zoom, {
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    lastZoom = zoom;
  }
}

// ─── helpers ─────────────────────────────────────────────────────────────────
PdfBook _book({String path = '/nonexistent/test.pdf'}) =>
    PdfBook(title: 'ספר בדיקה', path: path);

PdfBookTab _tab({String path = '/nonexistent/test.pdf', int page = 1}) =>
    PdfBookTab(
      book: _book(path: path),
      pageNumber: page,
    );

PdfBookBloc _makeBloc(PdfBookTab tab, {Duration? loadTimeout}) => PdfBookBloc(
  tab: tab,
  initialState: PdfBookInitial(
    book: tab.book,
    initialPageNumber: tab.pageNumber,
  ),
  loadTimeout: loadTimeout,
  // בטסטים: מדלגים על אתחול pdfrx (שדורש platform channels)
  pdfrxInit: () async {},
);

PdfBookLoaded _loaded({
  PdfBook? book,
  int currentPageNumber = 1,
  int totalPages = 100,
  bool showLeftPane = false,
  bool showRightPane = false,
  bool pinLeftPane = false,
  bool isRightPaneHovering = false,
  double zoom = 1.0,
  bool showZoomBar = false,
  PdfLayoutMode layoutMode = PdfLayoutMode.regularView,
  String searchText = '',
  String currentTitle = '',
  List<PdfPageTextRange>? searchMatches,
  int? currentSearchMatchIndex,
}) => PdfBookLoaded(
  book: book ?? _book(),
  currentPageNumber: currentPageNumber,
  totalPages: totalPages,
  showLeftPane: showLeftPane,
  showRightPane: showRightPane,
  pinLeftPane: pinLeftPane,
  isRightPaneHovering: isRightPaneHovering,
  zoom: zoom,
  showZoomBar: showZoomBar,
  layoutMode: layoutMode,
  searchText: searchText,
  currentTitle: currentTitle,
  searchMatches: searchMatches,
  currentSearchMatchIndex: currentSearchMatchIndex,
  isLoading: false,
);

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('מצב ראשוני', () {
    test('מצב ראשוני הוא PdfBookInitial', () {
      final tab = _tab();
      final bloc = _makeBloc(tab);
      expect(bloc.state, isA<PdfBookInitial>());
      bloc.close();
    });

    test('המצב הראשוני מכיל את הספר הנכון', () {
      final tab = _tab();
      final bloc = _makeBloc(tab);
      expect((bloc.state as PdfBookInitial).book.title, 'ספר בדיקה');
      expect((bloc.state as PdfBookInitial).initialPageNumber, 1);
      bloc.close();
    });

    test('המצב הראשוני שומר את מספר העמוד ההתחלתי', () {
      final tab = _tab(page: 42);
      final bloc = _makeBloc(tab);
      expect((bloc.state as PdfBookInitial).initialPageNumber, 42);
      bloc.close();
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('טעינת מסמך - LoadPdfDocument', () {
    blocTest<PdfBookBloc, PdfBookState>(
      'קובץ שלא קיים → PdfBookError',
      build: () => _makeBloc(_tab()),
      act: (b) => b.add(const LoadPdfDocument()),
      expect: () => [isA<PdfBookError>()],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'שגיאת "ספר איננו קיים" כשהקובץ לא נמצא',
      build: () => _makeBloc(_tab()),
      act: (b) => b.add(const LoadPdfDocument()),
      verify: (b) {
        final s = b.state as PdfBookError;
        expect(s.message, 'הספר איננו קיים');
        expect(s.book.title, 'ספר בדיקה');
      },
    );

    test('מתקן נתיב PDF ישן לפי הספרייה הפעילה לפני בדיקת קיום', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'otzaria_pdf_bloc_path',
      );
      final activeLibrary = path.join(tempDir.path, 'new', 'books');
      final stalePath = path.join(
        tempDir.path,
        'old',
        'books',
        DatabaseConstants.talmudBavliFolderName,
        'ברכות.pdf',
      );
      final activePath = path.join(
        activeLibrary,
        DatabaseConstants.talmudBavliFolderName,
        'ברכות.pdf',
      );
      final previousLibraryPath = Settings.getValue<String>(
        SettingsRepository.keyLibraryPath,
      );

      addTearDown(() async {
        await Settings.setValue<String>(
          SettingsRepository.keyLibraryPath,
          previousLibraryPath ?? '',
        );
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      await Directory(path.dirname(activePath)).create(recursive: true);
      await File(activePath).writeAsBytes([1]);
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        activeLibrary,
      );

      final tab = PdfBookTab(
        book: PdfBook(title: 'ברכות', path: stalePath),
        pageNumber: 1,
      );
      final bloc = _makeBloc(tab);
      addTearDown(bloc.close);

      bloc.add(const LoadPdfDocument());
      final loading =
          await bloc.stream.firstWhere(
                (state) => state is PdfBookLoading,
              )
              as PdfBookLoading;

      expect(loading.book.path, activePath);
    });

    blocTest<PdfBookBloc, PdfBookState>(
      'LoadPdfDocument מוזנח כשהמצב הוא כבר Loaded',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) => b.add(const LoadPdfDocument()),
      expect: () => [],
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('מסמך מוכן - DocumentReady', () {
    blocTest<PdfBookBloc, PdfBookState>(
      'DocumentReady מ-Loading → PdfBookLoaded',
      build: () => _makeBloc(_tab()),
      seed: () => PdfBookLoading(book: _book()),
      act: (b) =>
          b.add(DocumentReady(documentRef: _FakeDocumentRef(), totalPages: 50)),
      expect: () => [isA<PdfBookLoaded>()],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'DocumentReady מ-Initial → PdfBookLoaded',
      build: () => _makeBloc(_tab()),
      act: (b) =>
          b.add(DocumentReady(documentRef: _FakeDocumentRef(), totalPages: 10)),
      expect: () => [isA<PdfBookLoaded>()],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'DocumentReady מגדיר totalPages נכון',
      build: () => _makeBloc(_tab()),
      seed: () => PdfBookLoading(book: _book()),
      act: (b) =>
          b.add(DocumentReady(documentRef: _FakeDocumentRef(), totalPages: 42)),
      verify: (b) {
        final s = b.state as PdfBookLoaded;
        expect(s.totalPages, 42);
        expect(s.isLoading, isFalse);
      },
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'DocumentReady מ-Loaded → מעדכן totalPages בלבד',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(totalPages: 10),
      act: (b) =>
          b.add(DocumentReady(documentRef: _FakeDocumentRef(), totalPages: 20)),
      expect: () => [
        isA<PdfBookLoaded>().having((s) => s.totalPages, 'totalPages', 20),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'DocumentReady עם outline שומר outline במצב',
      build: () => _makeBloc(_tab()),
      seed: () => PdfBookLoading(book: _book()),
      act: (b) => b.add(
        DocumentReady(
          documentRef: _FakeDocumentRef(),
          totalPages: 5,
          outline: const [],
        ),
      ),
      verify: (b) {
        final s = b.state as PdfBookLoaded;
        expect(s.outline, isNotNull);
      },
    );

    // תרחיש רגיל (פתיחה ישירה, ללא סיכון לקפיצות): requiresStableLayout=false
    // ועמוד ראשון → אין overlay טעינה, כדי לא לאט את הפתיחה (רגרסיית fbed10c5d).
    blocTest<PdfBookBloc, PdfBookState>(
      'עמוד ראשון בלי requiresStableLayout → isLoading=false (מהיר)',
      build: () => _makeBloc(_tab(page: 1)),
      seed: () => PdfBookLoading(book: _book()),
      act: (b) =>
          b.add(DocumentReady(documentRef: _FakeDocumentRef(), totalPages: 50)),
      verify: (b) => expect((b.state as PdfBookLoaded).isLoading, isFalse),
    );

    // תרחיש סיכון: requiresStableLayout=true (דף יומי / מעבר טקסט→PDF וכדומה)
    // → overlay טעינה עד שה-layout מתייצב, גם אם זה עמוד 1.
    blocTest<PdfBookBloc, PdfBookState>(
      'requiresStableLayout=true → isLoading=true גם בעמוד ראשון',
      build: () => _makeBloc(
        PdfBookTab(book: _book(), pageNumber: 1, requiresStableLayout: true),
      ),
      seed: () => PdfBookLoading(book: _book()),
      act: (b) =>
          b.add(DocumentReady(documentRef: _FakeDocumentRef(), totalPages: 50)),
      verify: (b) => expect((b.state as PdfBookLoaded).isLoading, isTrue),
    );

    // עמוד עמוק (היסטוריה/סימנייה) גם בלי requiresStableLayout מפורש עדיין
    // בסיכון לקפיצות → overlay טעינה.
    blocTest<PdfBookBloc, PdfBookState>(
      'עמוד>1 בלי requiresStableLayout → isLoading=true',
      build: () => _makeBloc(_tab(page: 10)),
      seed: () => PdfBookLoading(book: _book()),
      act: (b) =>
          b.add(DocumentReady(documentRef: _FakeDocumentRef(), totalPages: 50)),
      verify: (b) => expect((b.state as PdfBookLoaded).isLoading, isTrue),
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('כישלון טעינה - DocumentLoadFailed', () {
    blocTest<PdfBookBloc, PdfBookState>(
      'כישלון מ-Loading → PdfBookError',
      build: () => _makeBloc(_tab()),
      seed: () => PdfBookLoading(book: _book()),
      act: (b) => b.add(const DocumentLoadFailed('שגיאה בטעינה')),
      expect: () => [isA<PdfBookError>()],
      verify: (b) {
        expect((b.state as PdfBookError).message, 'שגיאה בטעינה');
      },
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'כישלון מ-Initial → PdfBookError',
      build: () => _makeBloc(_tab()),
      act: (b) => b.add(const DocumentLoadFailed('שגיאה כלשהי')),
      expect: () => [isA<PdfBookError>()],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'כישלון מ-Loaded → מוזנח',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) => b.add(const DocumentLoadFailed('שגיאה')),
      expect: () => [],
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('ניווט בדפים', () {
    blocTest<PdfBookBloc, PdfBookState>(
      'UpdatePageNumber מעדכן דף נוכחי',
      build: () => _makeBloc(_tab(page: 1)),
      seed: () => _loaded(currentPageNumber: 1, totalPages: 10),
      act: (b) => b.add(const UpdatePageNumber(pageNumber: 5)),
      expect: () => [
        isA<PdfBookLoaded>().having((s) => s.currentPageNumber, 'page', 5),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'UpdatePageNumber עם title מפורש שומר אותו',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) => b.add(const UpdatePageNumber(pageNumber: 3, title: 'פרק ג')),
      verify: (b) {
        final s = b.state as PdfBookLoaded;
        expect(s.currentTitle, 'פרק ג');
        expect(s.currentPageNumber, 3);
      },
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'UpdatePageNumber בלי outline משתמש בפורמט ברירת מחדל',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) => b.add(const UpdatePageNumber(pageNumber: 7)),
      verify: (b) {
        expect((b.state as PdfBookLoaded).currentTitle, 'עמוד 7');
      },
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'UpdatePageNumber מחוץ למצב Loaded → מוזנח',
      build: () => _makeBloc(_tab()),
      act: (b) => b.add(const UpdatePageNumber(pageNumber: 5)),
      expect: () => [],
    );

    // שמירה שאין קריסה כשה-controller לא מוכן
    for (final event in <PdfBookEvent>[
      const GoToPage(5),
      const GoToNextPage(),
      const GoToPreviousPage(),
      const GoToFirstPage(),
      const GoToLastPage(),
    ]) {
      blocTest<PdfBookBloc, PdfBookState>(
        '$event לא קורס כשה-controller לא מוכן',
        build: () => _makeBloc(_tab()),
        seed: () => _loaded(currentPageNumber: 3, totalPages: 10),
        act: (b) => b.add(event),
        expect: () => [], // אין שינוי מצב, רק side effect ב-controller
      );
    }
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('זום', () {
    blocTest<PdfBookBloc, PdfBookState>(
      'UpdateZoom מעדכן זום',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(zoom: 1.0),
      act: (b) => b.add(const UpdateZoom(2.5)),
      expect: () => [
        isA<PdfBookLoaded>().having((s) => s.zoom, 'zoom', 2.5),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'UpdateZoom מחוץ למצב Loaded → מוזנח',
      build: () => _makeBloc(_tab()),
      act: (b) => b.add(const UpdateZoom(2.0)),
      expect: () => [],
    );

    // ZoomIn/Out/Reset כשה-controller לא מוכן → לא קורסים, לא מעדכנים
    for (final event in <PdfBookEvent>[
      const ZoomIn(),
      const ZoomOut(),
      const ResetZoom(),
    ]) {
      blocTest<PdfBookBloc, PdfBookState>(
        '$event לא קורס כשה-controller לא מוכן',
        build: () => _makeBloc(_tab()),
        seed: () => _loaded(zoom: 1.5),
        act: (b) => b.add(event),
        expect: () => [],
      );
    }

    blocTest<PdfBookBloc, PdfBookState>(
      'SetShowZoomBar(true) מציג את פס הזום',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(showZoomBar: false),
      act: (b) => b.add(const SetShowZoomBar(true)),
      expect: () => [
        isA<PdfBookLoaded>().having((s) => s.showZoomBar, 'showZoomBar', true),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'SetShowZoomBar(false) מסתיר את פס הזום',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(showZoomBar: true),
      act: (b) => b.add(const SetShowZoomBar(false)),
      expect: () => [
        isA<PdfBookLoaded>().having((s) => s.showZoomBar, 'showZoomBar', false),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'SetShowZoomBar מחוץ ל-Loaded → מוזנח',
      build: () => _makeBloc(_tab()),
      act: (b) => b.add(const SetShowZoomBar(true)),
      expect: () => [],
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('מצב תצוגה - SetLayoutMode', () {
    blocTest<PdfBookBloc, PdfBookState>(
      'SetLayoutMode מ-Initial משנה layoutMode',
      build: () => _makeBloc(_tab()),
      act: (b) => b.add(const SetLayoutMode(PdfLayoutMode.bookView)),
      expect: () => [
        isA<PdfBookInitial>().having(
          (s) => s.layoutMode,
          'layoutMode',
          PdfLayoutMode.bookView,
        ),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'SetLayoutMode מ-Loaded משנה layoutMode',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(layoutMode: PdfLayoutMode.regularView),
      act: (b) => b.add(const SetLayoutMode(PdfLayoutMode.bookView)),
      expect: () => [
        isA<PdfBookLoaded>().having(
          (s) => s.layoutMode,
          'layoutMode',
          PdfLayoutMode.bookView,
        ),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'SetLayoutMode עם אותו מצב מ-Loaded → לא מפעיל emit',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(layoutMode: PdfLayoutMode.regularView),
      act: (b) => b.add(const SetLayoutMode(PdfLayoutMode.regularView)),
      expect: () => [],
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('הגדרות פר-ספר', () {
    test(
      'LoadPerBookSettings עם savedZoom לא דורס את layoutMode החדש',
      () async {
        final previousEnablePerBookSettings = Settings.getValue<bool>(
          SettingsRepository.keyEnablePerBookSettings,
        );
        final previousPdfBookViewByDefault = Settings.getValue<bool>(
          SettingsRepository.keyPdfBookViewByDefault,
        );
        addTearDown(() async {
          await Settings.setValue<bool>(
            SettingsRepository.keyEnablePerBookSettings,
            previousEnablePerBookSettings ?? false,
          );
          await Settings.setValue<bool>(
            SettingsRepository.keyPdfBookViewByDefault,
            previousPdfBookViewByDefault ?? false,
          );
        });

        await Settings.setValue<bool>(
          SettingsRepository.keyEnablePerBookSettings,
          false,
        );
        await Settings.setValue<bool>(
          SettingsRepository.keyPdfBookViewByDefault,
          true,
        );

        final tab = _tab();
        final controller = _ReadyPdfViewerController();
        tab.pdfViewerController = controller;
        tab.savedZoom = 2.5;

        final bloc = _makeBloc(tab);
        addTearDown(bloc.close);

        bloc.add(
          DocumentReady(documentRef: _FakeDocumentRef(), totalPages: 12),
        );
        await Future<void>.delayed(Duration.zero);
        expect(bloc.state, isA<PdfBookLoaded>());

        bloc.add(const LoadPerBookSettings());
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final state = bloc.state as PdfBookLoaded;
        expect(state.layoutMode, PdfLayoutMode.bookView);
        expect(state.zoom, 2.5);
        expect(tab.savedLayoutMode, PdfLayoutMode.bookView);
        expect(controller.lastZoom, 2.5);
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('חלונית שמאל', () {
    blocTest<PdfBookBloc, PdfBookState>(
      'ToggleLeftPane מחליף מ-false ל-true',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(showLeftPane: false),
      act: (b) => b.add(const ToggleLeftPane()),
      expect: () => [
        isA<PdfBookLoaded>().having(
          (s) => s.showLeftPane,
          'showLeftPane',
          true,
        ),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'ToggleLeftPane מחליף מ-true ל-false',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(showLeftPane: true),
      act: (b) => b.add(const ToggleLeftPane()),
      expect: () => [
        isA<PdfBookLoaded>().having(
          (s) => s.showLeftPane,
          'showLeftPane',
          false,
        ),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'ToggleLeftPane עם ערך מפורש',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(showLeftPane: false),
      act: (b) => b.add(const ToggleLeftPane(true)),
      expect: () => [
        isA<PdfBookLoaded>().having(
          (s) => s.showLeftPane,
          'showLeftPane',
          true,
        ),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'ToggleLeftPane מחוץ ל-Loaded → מוזנח',
      build: () => _makeBloc(_tab()),
      act: (b) => b.add(const ToggleLeftPane()),
      expect: () => [],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'TogglePinLeftPane מחליף pin',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(pinLeftPane: false),
      act: (b) => b.add(const TogglePinLeftPane()),
      expect: () => [
        isA<PdfBookLoaded>().having((s) => s.pinLeftPane, 'pinLeftPane', true),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'UpdateLeftPaneTab מעדכן אינדקס טאב',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) => b.add(const UpdateLeftPaneTab(2)),
      expect: () => [
        isA<PdfBookLoaded>().having(
          (s) => s.leftPaneTabIndex,
          'leftPaneTabIndex',
          2,
        ),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'UpdateSidebarWidth מעדכן רוחב',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) => b.add(const UpdateSidebarWidth(450.0)),
      expect: () => [
        isA<PdfBookLoaded>().having(
          (s) => s.sidebarWidth,
          'sidebarWidth',
          450.0,
        ),
      ],
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('חלונית ימין (מפרשים)', () {
    blocTest<PdfBookBloc, PdfBookState>(
      'ToggleRightPane פותח חלונית',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(showRightPane: false),
      act: (b) => b.add(const ToggleRightPane()),
      expect: () => [
        isA<PdfBookLoaded>().having(
          (s) => s.showRightPane,
          'showRightPane',
          true,
        ),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'ToggleRightPane סגירה מאפסת isRightPaneHovering',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(showRightPane: true, isRightPaneHovering: true),
      act: (b) => b.add(const ToggleRightPane(show: false)),
      verify: (b) {
        final s = b.state as PdfBookLoaded;
        expect(s.showRightPane, isFalse);
        expect(s.isRightPaneHovering, isFalse);
      },
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'ToggleRightPane עם initialTabIndex מגדיר טאב',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(showRightPane: false),
      act: (b) => b.add(const ToggleRightPane(show: true, initialTabIndex: 2)),
      expect: () => [
        isA<PdfBookLoaded>().having(
          (s) => s.rightPaneInitialTabIndex,
          'rightPaneInitialTabIndex',
          2,
        ),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'UpdateRightPaneWidth מעדכן רוחב',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) => b.add(const UpdateRightPaneWidth(500.0)),
      expect: () => [
        isA<PdfBookLoaded>().having(
          (s) => s.rightPaneWidth,
          'rightPaneWidth',
          500.0,
        ),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'SetRightPaneHovering מעדכן hover',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(isRightPaneHovering: false),
      act: (b) => b.add(const SetRightPaneHovering(true)),
      expect: () => [
        isA<PdfBookLoaded>().having(
          (s) => s.isRightPaneHovering,
          'hovering',
          true,
        ),
      ],
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('חיפוש', () {
    blocTest<PdfBookBloc, PdfBookState>(
      'UpdateSearchText מעדכן טקסט חיפוש',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(searchText: ''),
      act: (b) => b.add(const UpdateSearchText('תורה')),
      expect: () => [
        isA<PdfBookLoaded>().having((s) => s.searchText, 'searchText', 'תורה'),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'UpdateSearchOptions עם searchMode מעדכן את ה-state',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) =>
          b.add(const UpdateSearchOptions(searchMode: SearchMode.fuzzy)),
      expect: () => [
        isA<PdfBookLoaded>().having(
          (s) => s.searchMode,
          'searchMode',
          SearchMode.fuzzy,
        ),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'UpdateSearchOptions עם alternativeWords מעדכן את ה-state',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) => b.add(
        const UpdateSearchOptions(
          alternativeWords: {
            1: ['תורה', 'Torah'],
          },
        ),
      ),
      expect: () => [
        isA<PdfBookLoaded>().having(
          (s) => s.alternativeWords,
          'alternativeWords',
          const {
            1: ['תורה', 'Torah'],
          },
        ),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'UpdateSearchOptions עם spacingValues מעדכן',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) => b.add(const UpdateSearchOptions(spacingValues: {'0-1': '2'})),
      expect: () => [
        isA<PdfBookLoaded>().having((s) => s.spacingValues, 'spacingValues', {
          '0-1': '2',
        }),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'UpdateSearchOptions עם searchOptions מעדכן',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) => b.add(
        const UpdateSearchOptions(
          searchOptions: {
            'תורה_0': {'סיומות': true},
          },
        ),
      ),
      expect: () => [
        isA<PdfBookLoaded>().having((s) => s.searchOptions, 'searchOptions', {
          'תורה_0': {'סיומות': true},
        }),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'UpdateSearchOptions ללא שינוי → אין emit',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) => b.add(const UpdateSearchOptions()),
      expect: () => [],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'UpdateSearchOptions עם אותו searchMode → אין emit',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) =>
          b.add(const UpdateSearchOptions(searchMode: SearchMode.exact)),
      expect: () => [],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'StartSearch מעדכן טקסט חיפוש',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(searchText: ''),
      act: (b) => b.add(const StartSearch('בראשית')),
      expect: () => [
        isA<PdfBookLoaded>().having(
          (s) => s.searchText,
          'searchText',
          'בראשית',
        ),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'ClearSearch מנקה טקסט ותוצאות',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(
        searchText: 'תורה',
        searchMatches: const [],
        currentSearchMatchIndex: 0,
      ),
      act: (b) => b.add(const ClearSearch()),
      verify: (b) {
        final s = b.state as PdfBookLoaded;
        expect(s.searchText, '');
        expect(s.searchMatches, isNull);
        expect(s.currentSearchMatchIndex, isNull);
      },
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'ClearSearch מחוץ ל-Loaded → מוזנח',
      build: () => _makeBloc(_tab()),
      act: (b) => b.add(const ClearSearch()),
      expect: () => [],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'UpdateSearchText מחוץ ל-Loaded → מוזנח',
      build: () => _makeBloc(_tab()),
      act: (b) => b.add(const UpdateSearchText('תורה')),
      expect: () => [],
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('LoadHeadingsAndLinks', () {
    test('כשהמצב אינו Loaded → שומר ב-tab ולא מפעיל emit', () async {
      final tab = _tab();
      final bloc = _makeBloc(tab);

      bloc.add(const LoadHeadingsAndLinks(links: []));
      await Future.delayed(Duration.zero);

      expect(bloc.state, isA<PdfBookInitial>());
      bloc.close();
    });

    blocTest<PdfBookBloc, PdfBookState>(
      'כשהמצב הוא Loaded → שומר ב-tab',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) => b.add(const LoadHeadingsAndLinks(links: [])),
      verify: (b) {
        // links שווה לstate הקודם (ריק=ריק) → אין emit
        expect(b.tab.links, isEmpty);
      },
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'אירוע headings בלבד לא דורס links קיימים ב-tab וב-state',
      build: () {
        final tab = _tab();
        tab.links = [
          Link(
            heRef: 'א',
            index1: 10,
            path2: 'x.txt',
            index2: 1,
            connectionType: 'commentary',
          ),
        ];
        return _makeBloc(tab);
      },
      seed: () => _loaded().copyWith(
        links: [
          Link(
            heRef: 'א',
            index1: 10,
            path2: 'x.txt',
            index2: 1,
            connectionType: 'commentary',
          ),
        ],
      ),
      act: (b) => b.add(const LoadHeadingsAndLinks(links: [])),
      verify: (b) {
        expect(b.tab.links, hasLength(1));
        expect((b.state as PdfBookLoaded).links, hasLength(1));
      },
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'כשlinks חדשים עם אותו אורך אך תוכן שונה → emit state חדש',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded().copyWith(
        links: [
          Link(
            heRef: 'א',
            index1: 10,
            path2: 'x.txt',
            index2: 1,
            connectionType: 'commentary',
          ),
        ],
      ),
      act: (b) => b.add(
        LoadHeadingsAndLinks(
          links: [
            Link(
              heRef: 'ב',
              index1: 20,
              path2: 'y.txt',
              index2: 2,
              connectionType: 'commentary',
            ),
          ],
        ),
      ),
      expect: () => [
        isA<PdfBookLoaded>().having(
          (s) => s.links.first.index1,
          'index1',
          20,
        ),
      ],
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('מצב טעינה - SetLoadingState', () {
    blocTest<PdfBookBloc, PdfBookState>(
      'SetLoadingState(isLoading: true) מעדכן',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) => b.add(const SetLoadingState(isLoading: true)),
      expect: () => [
        isA<PdfBookLoaded>().having((s) => s.isLoading, 'isLoading', true),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'SetLoadingState(succeeded: false) מעדכן loadSucceeded',
      build: () => _makeBloc(_tab()),
      seed: () => _loaded(),
      act: (b) =>
          b.add(const SetLoadingState(isLoading: false, succeeded: false)),
      verify: (b) {
        final s = b.state as PdfBookLoaded;
        expect(s.isLoading, isFalse);
        expect(s.loadSucceeded, isFalse);
      },
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'SetLoadingState מ-Initial (succeeded=true ברירת מחדל) → מוזנח',
      build: () => _makeBloc(_tab()),
      act: (b) => b.add(const SetLoadingState(isLoading: true)),
      expect: () => [],
    );

    // ─── רגרסיה: PDF הראשון בסשן נתקע לפעמים על ספינר אינסופי ───────────────
    //
    // pdfrx קורא ל-`onDocumentLoadFinished(succeeded)` כדי לדווח על סיום
    // טעינה — לפעמים *לפני* או *במקום* `onViewerReady` (שמשגר DocumentReady).
    // ה-handler הקודם של SetLoadingState החזיר `return` מוקדם כש-state אינו
    // PdfBookLoaded, ולכן דיווח כישלון מ-Loading פשוט נבלע: state נשאר
    // PdfBookLoading ל-נצח ואין אירוע נוסף שיוציא אותו ממנו → ספינר תקוע.
    blocTest<PdfBookBloc, PdfBookState>(
      'SetLoadingState(succeeded=false) מ-Loading → PdfBookError '
      '(מונע ספינר אינסופי כש-onViewerReady לא נורה)',
      build: () => _makeBloc(_tab()),
      seed: () => PdfBookLoading(book: _book()),
      act: (b) =>
          b.add(const SetLoadingState(isLoading: false, succeeded: false)),
      expect: () => [isA<PdfBookError>()],
      verify: (b) {
        final s = b.state as PdfBookError;
        expect(s.book.title, 'ספר בדיקה');
        expect(s.message, 'נכשלה טעינת ה-PDF');
      },
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'SetLoadingState(succeeded=true) מ-Loading → לא משנה state '
      '(ממתינים ל-DocumentReady מ-onViewerReady)',
      build: () => _makeBloc(_tab()),
      seed: () => PdfBookLoading(book: _book()),
      act: (b) =>
          b.add(const SetLoadingState(isLoading: false, succeeded: true)),
      expect: () => [],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'SetLoadingState(succeeded=false) מ-Initial לא מייצר אירוע '
      '(LoadPdfDocument עוד לא רץ — לא קיים book context)',
      build: () => _makeBloc(_tab()),
      act: (b) =>
          b.add(const SetLoadingState(isLoading: false, succeeded: false)),
      expect: () => [],
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Watchdog: רגרסיה לבעיה ש-PDF הראשון בסשן לפעמים נתקע על ספינר אינסופי
  // כש-pdfrx לא קורא לאף callback (לא onViewerReady ולא
  // onDocumentLoadFinished) בגלל race-condition פנימי בטעינה הראשונה.
  group('מצב טעינה - load watchdog', () {
    late Directory tmpDir;
    late String existingPdfPath;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('pdf_watchdog_');
      // הקובץ לא חייב להיות PDF תקין — רק לעבור את בדיקת existsSync
      // ב-`_onLoadPdfDocument`. pdfrx לא נטען בטסטים.
      existingPdfPath = '${tmpDir.path}${Platform.pathSeparator}stub.pdf';
      File(existingPdfPath).writeAsBytesSync(const [0x25, 0x50, 0x44, 0x46]);
    });

    tearDown(() {
      try {
        tmpDir.deleteSync(recursive: true);
      } catch (_) {
        // best-effort cleanup
      }
    });

    blocTest<PdfBookBloc, PdfBookState>(
      'אחרי loadTimeout ראשון → PdfBookError עם autoRetry=true',
      build: () => _makeBloc(
        _tab(path: existingPdfPath),
        loadTimeout: const Duration(milliseconds: 50),
      ),
      act: (b) => b.add(const LoadPdfDocument()),
      wait: const Duration(milliseconds: 150),
      expect: () => [isA<PdfBookLoading>(), isA<PdfBookError>()],
      verify: (b) {
        final s = b.state as PdfBookError;
        expect(s.message, 'הטעינה ארכה זמן רב מדי');
        expect(s.autoRetry, isTrue);
      },
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'אחרי שני timeouts (auto-retry + show-button) → PdfBookError עם autoRetry=false',
      build: () => _makeBloc(
        _tab(path: existingPdfPath),
        loadTimeout: const Duration(milliseconds: 50),
      ),
      act: (b) async {
        b.add(const LoadPdfDocument());
        // מחכה לiriyah הראשונה (auto-retry)
        await Future<void>.delayed(const Duration(milliseconds: 80));
        // מדמה את מה שה-BlocListener בscreen יעשה
        b.add(const RetryLoad());
        // מחכה לiriyah השנייה (show button)
        await Future<void>.delayed(const Duration(milliseconds: 80));
      },
      wait: const Duration(milliseconds: 50),
      expect: () => [
        isA<PdfBookLoading>(),
        isA<PdfBookError>(), // autoRetry=true
        isA<PdfBookLoading>(), // אחרי RetryLoad
        isA<PdfBookError>(), // autoRetry=false
      ],
      verify: (b) {
        final s = b.state as PdfBookError;
        expect(s.autoRetry, isFalse);
      },
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'DocumentReady מבטל את ה-watchdog — לא עוברים ל-Error',
      build: () => _makeBloc(
        _tab(path: existingPdfPath),
        loadTimeout: const Duration(milliseconds: 50),
      ),
      act: (b) async {
        b.add(const LoadPdfDocument());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        b.add(DocumentReady(documentRef: _FakeDocumentRef(), totalPages: 5));
      },
      wait: const Duration(milliseconds: 150),
      expect: () => [
        isA<PdfBookLoading>(),
        isA<PdfBookLoaded>(),
      ],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'SetLoadingState(succeeded=false) מבטל את ה-watchdog — '
      'לא מקבלים שני אירועי PdfBookError',
      build: () => _makeBloc(
        _tab(path: existingPdfPath),
        loadTimeout: const Duration(milliseconds: 50),
      ),
      act: (b) async {
        b.add(const LoadPdfDocument());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        b.add(const SetLoadingState(isLoading: false, succeeded: false));
      },
      wait: const Duration(milliseconds: 150),
      expect: () => [isA<PdfBookLoading>(), isA<PdfBookError>()],
      verify: (b) {
        final s = b.state as PdfBookError;
        // ההודעה מ-SetLoadingState, לא מה-watchdog
        expect(s.message, 'נכשלה טעינת ה-PDF');
      },
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'RetryLoad מ-PdfBookError → PdfBookLoading (כפתור "נסה שוב")',
      build: () => _makeBloc(_tab(path: existingPdfPath)),
      seed: () => PdfBookError(
        book: _book(path: existingPdfPath),
        message: 'הטעינה ארכה זמן רב מדי',
      ),
      act: (b) => b.add(const RetryLoad()),
      expect: () => [isA<PdfBookLoading>()],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'RetryLoad מתעלם כשה-state אינו PdfBookError',
      build: () => _makeBloc(_tab(path: existingPdfPath)),
      seed: () => PdfBookLoading(book: _book(path: existingPdfPath)),
      act: (b) => b.add(const RetryLoad()),
      expect: () => [],
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'RetryLoad כשהקובץ הוסר → PdfBookError חדש עם הודעה מתאימה',
      build: () => _makeBloc(_tab(path: '/totally/missing/file.pdf')),
      seed: () => PdfBookError(
        book: _book(path: '/totally/missing/file.pdf'),
        message: 'שגיאה קודמת',
      ),
      act: (b) => b.add(const RetryLoad()),
      expect: () => [isA<PdfBookError>()],
      verify: (b) {
        expect((b.state as PdfBookError).message, 'הספר איננו קיים');
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  group('סגירת bloc', () {
    test('close() לא קורס', () async {
      final bloc = _makeBloc(_tab());
      await bloc.close();
      expect(bloc.isClosed, isTrue);
    });

    test('close() בזמן שפס הזום פעיל לא קורס', () async {
      final tab = _tab();
      final bloc = _makeBloc(tab);
      bloc
        ..seed(_loaded(showZoomBar: false))
        ..add(const SetShowZoomBar(true));
      await Future.delayed(Duration.zero);
      await bloc.close();
      expect(bloc.isClosed, isTrue);
    });
  });
}

// helper: seed outside blocTest
extension _BlocSeed<S> on BlocBase<S> {
  void seed(S state) {
    // ignore: invalid_use_of_visible_for_testing_member
    emit(state);
  }
}
