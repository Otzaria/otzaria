/// טסט אינטגרציה מקיף לקריאת PDF
///
/// מדמה מסע קריאה שלם ברמת ה-BLoC:
/// פתיחה → חיפוש → חלוניות → זום → הגדרות → סגירה
/// ומעבר בין טאבים דרך TabsBloc.
///
/// הערה: PdfViewer (pdfrx) דורש rendering פיזי ולא ניתן ל-widget test ישיר.
/// לכן מדמים את DocumentReady באופן ישיר, כפי שעושה ה-viewer בפועל.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart' show BlocBase;
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart'
    show PdfLayoutMode;
import 'package:pdfrx/pdfrx.dart';
import '../helpers/memory_settings_cache.dart';

// ─── fakes ───────────────────────────────────────────────────────────────────

class _FakeDocumentRef extends Fake implements PdfDocumentRef {}

class _FakeTabsRepository extends TabsRepository {
  @override
  List<OpenedTab> loadTabs({bool newRuntime = false}) => [];
  @override
  int loadCurrentTabIndex() => 0;
  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {}
  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {}
}

// ─── seed helper ─────────────────────────────────────────────────────────────

extension _Seed<S> on BlocBase<S> {
  void seed(S state) {
    // ignore: invalid_use_of_visible_for_testing_member
    emit(state);
  }
}

// ─── helpers ─────────────────────────────────────────────────────────────────

PdfBook _book({
  String path = '/nonexistent/ספר_בדיקה.pdf',
  String title = 'ספר בדיקה',
}) => PdfBook(title: title, path: path);

PdfBookTab _tab({String title = 'ספר בדיקה', int page = 1}) => PdfBookTab(
  book: _book(title: title),
  pageNumber: page,
);

PdfBookBloc _makeBloc(PdfBookTab tab) => PdfBookBloc(
  tab: tab,
  initialState: PdfBookInitial(
    book: tab.book,
    initialPageNumber: tab.pageNumber,
  ),
  pdfrxInit: () async {},
);

/// מחכה שה-bloc יגיע למצב מסוים
Future<S> _waitFor<S extends PdfBookState>(PdfBookBloc bloc) async {
  if (bloc.state is S) return bloc.state as S;
  return bloc.stream.firstWhere((s) => s is S).then((s) => s as S);
}

/// מדמה DocumentReady (מה-PdfViewer) ומחכה ל-PdfBookLoaded
Future<PdfBookLoaded> _readyDoc(
  PdfBookBloc bloc, {
  int totalPages = 100,
}) async {
  bloc.seed(PdfBookLoading(book: bloc.tab.book));
  bloc.add(
    DocumentReady(
      documentRef: _FakeDocumentRef(),
      totalPages: totalPages,
      outline: const [],
    ),
  );
  return _waitFor<PdfBookLoaded>(bloc);
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('מסע קריאה שלם', () {
    test('פתיחת PDF, חיפוש, חלוניות, זום, תצוגה, הגדרות, סגירה', () async {
      final tab = _tab(page: 1);
      final bloc = _makeBloc(tab);
      addTearDown(bloc.close);

      // ── שלב 1: מצב ראשוני ─────────────────────────────────────────────────
      expect(bloc.state, isA<PdfBookInitial>());
      expect((bloc.state as PdfBookInitial).book.title, 'ספר בדיקה');
      expect((bloc.state as PdfBookInitial).initialPageNumber, 1);

      // ── שלב 2: ניסיון פתיחה של קובץ שלא קיים → שגיאה ────────────────────
      bloc.add(const LoadPdfDocument());
      final errorState = await _waitFor<PdfBookError>(bloc);
      expect(errorState.message, 'הספר איננו קיים');

      // ── שלב 3: איפוס ופתיחה מוצלחת עם DocumentReady ─────────────────────
      bloc.seed(PdfBookInitial(book: tab.book, initialPageNumber: 1));
      final loaded = await _readyDoc(bloc, totalPages: 120);
      expect(loaded.totalPages, 120);
      expect(loaded.currentPageNumber, 1);
      expect(loaded.isLoading, isFalse);

      // ── שלב 4: חיפוש ──────────────────────────────────────────────────────
      // 4a: UpdateSearchText
      bloc.add(const UpdateSearchText('אלהים'));
      await Future.delayed(Duration.zero);
      expect((bloc.state as PdfBookLoaded).searchText, 'אלהים');

      // 4b: אפשרויות חיפוש מתקדמות
      bloc.add(
        const UpdateSearchOptions(
          searchMode: SearchMode.fuzzy,
          alternativeWords: {
            0: ['אלהים', 'השם', 'ה׳'],
          },
        ),
      );
      await Future.delayed(Duration.zero);
      expect((bloc.state as PdfBookLoaded).searchMode, SearchMode.fuzzy);
      expect(
        (bloc.state as PdfBookLoaded).alternativeWords[0],
        contains('השם'),
      );

      // ── שלב 5: חלוניות ────────────────────────────────────────────────────
      // 5a: חלונית שמאל (תוכן עניינים)
      bloc.add(const ToggleLeftPane(true));
      await Future.delayed(Duration.zero);
      expect((bloc.state as PdfBookLoaded).showLeftPane, isTrue);

      // 5b: עדכון רוחב sidebar
      bloc.add(const UpdateSidebarWidth(400.0));
      await Future.delayed(Duration.zero);
      expect((bloc.state as PdfBookLoaded).sidebarWidth, 400.0);

      // 5c: חלונית ימין (מפרשים)
      bloc.add(const ToggleRightPane(show: true));
      await Future.delayed(Duration.zero);
      expect((bloc.state as PdfBookLoaded).showRightPane, isTrue);

      // 5d: סגירת חלונית ימין
      bloc.add(const ToggleRightPane(show: false));
      await Future.delayed(Duration.zero);
      expect((bloc.state as PdfBookLoaded).showRightPane, isFalse);

      // 5e: סגירת חלונית שמאל
      bloc.add(const ToggleLeftPane(false));
      await Future.delayed(Duration.zero);
      expect((bloc.state as PdfBookLoaded).showLeftPane, isFalse);

      // ── שלב 6: זום ────────────────────────────────────────────────────────
      bloc.add(const UpdateZoom(2.0));
      await Future.delayed(Duration.zero);
      expect((bloc.state as PdfBookLoaded).zoom, 2.0);

      bloc.add(const SetShowZoomBar(true));
      await Future.delayed(Duration.zero);
      expect((bloc.state as PdfBookLoaded).showZoomBar, isTrue);

      // ZoomIn/ZoomOut/ResetZoom - side effects על controller, לא משנים state
      bloc.add(const ZoomIn());
      bloc.add(const ZoomOut());
      bloc.add(const ResetZoom());
      await Future.delayed(Duration.zero);

      bloc.add(const SetShowZoomBar(false));
      await Future.delayed(Duration.zero);
      expect((bloc.state as PdfBookLoaded).showZoomBar, isFalse);

      // ── שלב 7: מצבי תצוגה ─────────────────────────────────────────────────
      bloc.add(const SetLayoutMode(PdfLayoutMode.bookView));
      await Future.delayed(Duration.zero);
      expect((bloc.state as PdfBookLoaded).layoutMode, PdfLayoutMode.bookView);

      bloc.add(const SetLayoutMode(PdfLayoutMode.regularView));
      await Future.delayed(Duration.zero);
      expect(
        (bloc.state as PdfBookLoaded).layoutMode,
        PdfLayoutMode.regularView,
      );

      // אותו mode → לא מפעיל emit
      final beforeRepeat = bloc.state;
      bloc.add(const SetLayoutMode(PdfLayoutMode.regularView));
      await Future.delayed(Duration.zero);
      expect(identical(bloc.state, beforeRepeat), isTrue);

      // ── שלב 8: הגדרות per-book ─────────────────────────────────────────────
      bloc.add(const LoadPerBookSettings());
      bloc.add(const SavePerBookSettings());
      bloc.add(const ResetPerBookSettings());
      await Future.delayed(Duration.zero);

      // ── שלב 9: pin חלונית ─────────────────────────────────────────────────
      bloc.add(const TogglePinLeftPane());
      await Future.delayed(Duration.zero);
      expect((bloc.state as PdfBookLoaded).pinLeftPane, isTrue);

      bloc.add(const TogglePinLeftPane());
      await Future.delayed(Duration.zero);
      expect((bloc.state as PdfBookLoaded).pinLeftPane, isFalse);

      // ── שלב 10: מצב טעינה ─────────────────────────────────────────────────
      bloc.add(const SetLoadingState(isLoading: true));
      await Future.delayed(Duration.zero);
      expect((bloc.state as PdfBookLoaded).isLoading, isTrue);

      bloc.add(const SetLoadingState(isLoading: false, succeeded: false));
      await Future.delayed(Duration.zero);
      expect((bloc.state as PdfBookLoaded).isLoading, isFalse);
      expect((bloc.state as PdfBookLoaded).loadSucceeded, isFalse);

      // ── שלב 11: סגירה ─────────────────────────────────────────────────────
      await bloc.close();
      expect(bloc.isClosed, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('תרחישי גבול', () {
    test('DocumentLoadFailed → PdfBookError עם הודעה', () async {
      final tab = _tab();
      final bloc = _makeBloc(tab);
      addTearDown(bloc.close);

      bloc.seed(PdfBookLoading(book: tab.book));
      bloc.add(const DocumentLoadFailed('שגיאת רשת'));
      final err = await _waitFor<PdfBookError>(bloc);
      expect(err.message, 'שגיאת רשת');
      expect(err.book.title, 'ספר בדיקה');
    });

    test('אירועים על Initial לפני DocumentReady → מוזנחים', () async {
      final tab = _tab();
      final bloc = _makeBloc(tab);
      addTearDown(bloc.close);

      bloc.add(const ToggleLeftPane());
      bloc.add(const UpdateZoom(3.0));
      await Future.delayed(Duration.zero);

      expect(bloc.state, isA<PdfBookInitial>());
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('חיפוש מתקדם', () {
    blocTest<PdfBookBloc, PdfBookState>(
      'spacingValues מעדכן מרווחים בין מילים',
      build: () {
        final tab = _tab();
        final bloc = _makeBloc(tab);
        bloc.seed(PdfBookLoading(book: tab.book));
        bloc.add(
          DocumentReady(documentRef: _FakeDocumentRef(), totalPages: 50),
        );
        return bloc;
      },
      act: (b) async {
        await Future.delayed(Duration.zero);
        b.add(
          const UpdateSearchOptions(spacingValues: {'0-1': '3', '1-2': '5'}),
        );
      },
      verify: (b) {
        final s = b.state as PdfBookLoaded;
        expect(s.spacingValues['0-1'], '3');
        expect(s.spacingValues['1-2'], '5');
      },
    );

    blocTest<PdfBookBloc, PdfBookState>(
      'מחזור searchMode: exact → fuzzy → advanced',
      build: () {
        final tab = _tab();
        final bloc = _makeBloc(tab);
        bloc.seed(PdfBookLoading(book: tab.book));
        bloc.add(
          DocumentReady(documentRef: _FakeDocumentRef(), totalPages: 10),
        );
        return bloc;
      },
      act: (b) async {
        await Future.delayed(Duration.zero);
        b.add(const UpdateSearchOptions(searchMode: SearchMode.fuzzy));
        b.add(const UpdateSearchOptions(searchMode: SearchMode.advanced));
        b.add(const UpdateSearchOptions(searchMode: SearchMode.exact));
      },
      verify: (b) {
        expect((b.state as PdfBookLoaded).searchMode, SearchMode.exact);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('מעבר בין טאבי PDF', () {
    test('פתיחת שני טאבים, מעבר ביניהם, סגירת אחד', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      addTearDown(bloc.close);

      final tab1 = _tab(title: 'ספר בראשית');
      final tab2 = _tab(title: 'ספר שמות');

      bloc.add(AddTab(tab1));
      await bloc.stream.firstWhere(
        (s) => s.tabs.any((t) => t.title == 'ספר בראשית'),
      );
      expect(bloc.state.tabs, hasLength(1));

      bloc.add(AddTab(tab2));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);
      expect(bloc.state.currentTabIndex, 1);

      // מעבר לטאב ראשון
      bloc.add(SetCurrentTab(0));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 0);
      expect(bloc.state.currentTab?.title, 'ספר בראשית');

      // מעבר לטאב שני
      bloc.add(SetCurrentTab(1));
      await bloc.stream.firstWhere((s) => s.currentTabIndex == 1);
      expect(bloc.state.currentTab?.title, 'ספר שמות');

      // סגירת הטאב הנוכחי
      bloc.add(RemoveTab(tab2));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);
      expect(bloc.state.tabs.first.title, 'ספר בראשית');
    });

    test(
      'ניווט קדימה ואחורה NavigateToPreviousTab/NavigateToNextTab',
      () async {
        final bloc = TabsBloc(repository: _FakeTabsRepository());
        addTearDown(bloc.close);

        bloc.add(AddTab(_tab(title: 'ספר א')));
        await bloc.stream.firstWhere((s) => s.tabs.length == 1);
        bloc.add(AddTab(_tab(title: 'ספר ב')));
        await bloc.stream.firstWhere((s) => s.tabs.length == 2);
        bloc.add(AddTab(_tab(title: 'ספר ג')));
        await bloc.stream.firstWhere((s) => s.tabs.length == 3);
        expect(bloc.state.currentTabIndex, 2);

        bloc.add(NavigateToPreviousTab());
        await bloc.stream.firstWhere((s) => s.currentTabIndex == 1);
        expect(bloc.state.currentTab?.title, 'ספר ב');

        bloc.add(NavigateToPreviousTab());
        await bloc.stream.firstWhere((s) => s.currentTabIndex == 0);
        expect(bloc.state.currentTab?.title, 'ספר א');

        bloc.add(NavigateToNextTab());
        await bloc.stream.firstWhere((s) => s.currentTabIndex == 1);
        expect(bloc.state.currentTab?.title, 'ספר ב');
      },
    );

    test('CloneTab יוצר עותק עצמאי של טאב PDF', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      addTearDown(bloc.close);

      final tab = _tab(title: 'ספר בדיקה', page: 42);
      bloc.add(AddTab(tab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      bloc.add(CloneTab(tab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      final cloned = bloc.state.tabs[1] as PdfBookTab;
      expect(cloned.title, 'ספר בדיקה');
      expect(cloned.pageNumber, 42);
      expect(identical(tab, cloned), isFalse);
    });
  });
}
