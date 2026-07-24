import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/utils/file/file_book_path_resolver.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:pdfrx/pdfrx.dart';

/// סוג לפונקציית אתחול pdfrx — ניתן להחלפה בטסטים.
typedef PdfrxInitializer = Future<void> Function();

/// Bloc for managing PDF book state
///
/// This bloc handles:
/// - Document loading and readiness
/// - Page navigation
/// - Zoom control
/// - Left/Right pane visibility
/// - Search functionality
/// - Per-book settings
class PdfBookBloc extends Bloc<PdfBookEvent, PdfBookState> {
  final PdfBookTab tab;
  final PdfViewerController pdfController;
  final PdfrxInitializer _pdfrxInit;

  /// זמן המתנה עד ל-retry אוטומטי שקט (ברירת מחדל: 3 שניות).
  final Duration _autoRetryDelay;

  /// זמן המתנה עד להצגת כפתור "נסה שוב" אחרי ה-retry האוטומטי (ברירת מחדל: 6 שניות).
  final Duration _showButtonDelay;

  Timer? _zoomBarTimer;
  Timer? _loadWatchdog;

  /// כמה פעמים ה-watchdog כבר ירה בסבב הנוכחי.
  /// 0 → הירייה הבאה תהיה auto-retry; 1+ → הירייה הבאה תציג כפתור.
  int _watchdogFiredCount = 0;

  PdfBookBloc({
    required this.tab,
    required PdfBookInitial initialState,
    Duration? loadTimeout,
    PdfrxInitializer? pdfrxInit,
  }) : pdfController = tab.pdfViewerController,
       _autoRetryDelay = loadTimeout ?? const Duration(seconds: 3),
       _showButtonDelay = loadTimeout ?? const Duration(seconds: 6),
       _pdfrxInit = pdfrxInit ?? pdfrxFlutterInitialize,
       super(initialState) {
    // Document events
    on<LoadPdfDocument>(_onLoadPdfDocument);
    on<DocumentReady>(_onDocumentReady);
    on<DocumentLoadFailed>(_onDocumentLoadFailed);
    on<RetryLoad>(_onRetryLoad);
    on<LoadHeadingsAndLinks>(_onLoadHeadingsAndLinks);

    // Navigation events
    on<UpdatePageNumber>(_onUpdatePageNumber);
    on<GoToPage>(_onGoToPage);
    on<GoToNextPage>(_onGoToNextPage);
    on<GoToPreviousPage>(_onGoToPreviousPage);
    on<GoToFirstPage>(_onGoToFirstPage);
    on<GoToLastPage>(_onGoToLastPage);

    // Zoom events
    on<UpdateZoom>(_onUpdateZoom);
    on<ZoomIn>(_onZoomIn);
    on<ZoomOut>(_onZoomOut);
    on<ResetZoom>(_onResetZoom);
    on<SetLayoutMode>(_onSetLayoutMode);
    on<SetShowZoomBar>(_onSetShowZoomBar);

    // Left pane events
    on<ToggleLeftPane>(_onToggleLeftPane);
    on<TogglePinLeftPane>(_onTogglePinLeftPane);
    on<UpdateLeftPaneTab>(_onUpdateLeftPaneTab);
    on<UpdateSidebarWidth>(_onUpdateSidebarWidth);

    // Right pane events
    on<ToggleRightPane>(_onToggleRightPane);
    on<UpdateRightPaneWidth>(_onUpdateRightPaneWidth);

    // Search events
    on<UpdateSearchText>(_onUpdateSearchText);
    on<UpdateSearchOptions>(_onUpdateSearchOptions);
    on<UpdateSearchResults>(_onUpdateSearchResults);
    on<StartSearch>(_onStartSearch);
    on<ClearSearch>(_onClearSearch);

    // Per-book settings events
    on<LoadPerBookSettings>(_onLoadPerBookSettings);
    on<SavePerBookSettings>(_onSavePerBookSettings);
    on<ResetPerBookSettings>(_onResetPerBookSettings);

    // UI state events
    on<SetRightPaneHovering>(_onSetRightPaneHovering);
    on<SetLoadingState>(_onSetLoadingState);
  }

  @override
  Future<void> close() {
    _zoomBarTimer?.cancel();
    _loadWatchdog?.cancel();
    return super.close();
  }

  void _startLoadWatchdog() {
    _loadWatchdog?.cancel();
    // הירייה הראשונה (count==0): מפעיל retry שקט אחרי _autoRetryDelay.
    // הירייה השנייה ואילך: מציג כפתור "נסה שוב" אחרי _showButtonDelay.
    final isAutoRetry = _watchdogFiredCount == 0;
    final timeout = isAutoRetry ? _autoRetryDelay : _showButtonDelay;
    _loadWatchdog = Timer(timeout, () {
      if (isClosed) return;
      if (state is PdfBookLoading) {
        _watchdogFiredCount++;
        add(
          DocumentLoadFailed(
            'הטעינה ארכה זמן רב מדי',
            autoRetry: isAutoRetry,
          ),
        );
      }
    });
  }

  void _cancelLoadWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = null;
  }

  // ============ Document Event Handlers ============

  Future<void> _onLoadPdfDocument(
    LoadPdfDocument event,
    Emitter<PdfBookState> emit,
  ) async {
    final initial = state;
    if (initial is! PdfBookInitial) return;

    final book = _resolvePdfBookPath(initial.book);
    if (!File(book.path).existsSync()) {
      emit(PdfBookError(book: book, message: 'הספר איננו קיים'));
      return;
    }

    _watchdogFiredCount = 0;
    emit(
      PdfBookLoading(
        book: book,
        searchText: initial.searchText,
        searchOptions: initial.searchOptions,
        alternativeWords: initial.alternativeWords,
        spacingValues: initial.spacingValues,
        searchMode: initial.searchMode,
        layoutMode: initial.layoutMode,
      ),
    );

    // pdfrxFlutterInitialize() spawns a native Dart isolate on first call and
    // can take 10–20 seconds. Don't start the watchdog until it returns so the
    // timer only counts actual PDF loading time, not init time.
    // _pdfrxInit is injectable for tests (pass () async {} to skip init).
    // try/catch: אם האתחול עצמו זורק (למשל, platform channel חסר בבדיקות),
    // ממשיכים — ה-watchdog ייתן timeout ויציג שגיאה במקום לתקוע לנצח.
    try {
      await _pdfrxInit();
    } catch (_) {}
    if (isClosed || state is! PdfBookLoading) return;
    _startLoadWatchdog();

    // Load headings and links in background
    _loadHeadingsAndLinks(book);
  }

  PdfBook _resolvePdfBookPath(PdfBook book) {
    final resolvedPath = resolveMovedFileBookPath(book.path);
    if (resolvedPath == book.path) return book;

    return PdfBook(
      id: book.id,
      title: book.title,
      category: book.category,
      path: resolvedPath,
      topics: book.topics,
      author: book.author,
      heCategories: book.heCategories,
      heEra: book.heEra,
      compDateStringHe: book.compDateStringHe,
      compPlaceStringHe: book.compPlaceStringHe,
      pubDateStringHe: book.pubDateStringHe,
      pubPlaceStringHe: book.pubPlaceStringHe,
      heShortDesc: book.heShortDesc,
      heDesc: book.heDesc,
      pubDate: book.pubDate,
      pubPlace: book.pubPlace,
      filePath: resolvedPath,
      categoryPath: book.categoryPath,
      categoryId: book.categoryId,
      fileType: book.fileType,
      order: book.order,
      isUserBook: book.isUserBook,
      externalLibraryId: book.externalLibraryId,
    );
  }

  Future<void> _loadHeadingsAndLinks(PdfBook book) async {
    try {
      debugPrint('=== Loading PDF Headings ===');
      debugPrint('Book title: ${book.title}');

      // הקישורים עצמם נטענים ב-PdfBookScreen (חלון סביב המיקום הנוכחי) —
      // הטעינה המלאה שהייתה כאן רצה במקביל אליה ושכפלה את כל קישורי הספר.
      final headings = await PdfHeadings.loadFromDatabase(
        book.title,
        categoryId: book.categoryId,
        filePath: book.filePath,
        preferUserBooks: book.isUserBook,
      );
      if (headings != null) {
        debugPrint('✅ Loaded ${headings.headingsMap.length} headings');
      }

      if (!isClosed) {
        add(LoadHeadingsAndLinks(headings: headings));
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading PDF headings: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  void _onDocumentReady(
    DocumentReady event,
    Emitter<PdfBookState> emit,
  ) {
    _cancelLoadWatchdog();
    final current = state;
    final PdfBook book;
    final String searchText;
    final Map<String, Map<String, bool>> searchOptions;
    final Map<int, List<String>> alternativeWords;
    final Map<String, String> spacingValues;
    final SearchMode searchMode;
    final int searchDistance;
    final PdfLayoutMode layoutMode;

    if (current is PdfBookInitial) {
      book = current.book;
      searchText = current.searchText;
      searchOptions = current.searchOptions;
      alternativeWords = current.alternativeWords;
      spacingValues = current.spacingValues;
      searchMode = current.searchMode;
      searchDistance = current.searchDistance;
      layoutMode = current.layoutMode;
    } else if (current is PdfBookLoading) {
      book = current.book;
      searchText = current.searchText;
      searchOptions = current.searchOptions;
      alternativeWords = current.alternativeWords;
      spacingValues = current.spacingValues;
      searchMode = current.searchMode;
      searchDistance = current.searchDistance;
      layoutMode = current.layoutMode;
    } else if (current is PdfBookLoaded) {
      // Already loaded, just update
      emit(
        current.copyWith(
          documentRef: event.documentRef,
          outline: event.outline,
          totalPages: event.totalPages,
        ),
      );
      return;
    } else {
      return;
    }

    final showLeftPane = resolveInitialReadingLeftPaneVisibility(
      explicitOpen: tab.showLeftPane.value,
      hasSearchText: searchText.isNotEmpty,
    );
    final pinLeftPane = Settings.getValue<bool>('key-pin-sidebar') ?? false;
    final sidebarWidth = Settings.getValue<double>(
      'key-sidebar-width',
      defaultValue: 300,
    )!;

    emit(
      PdfBookLoaded(
        book: book,
        documentRef: event.documentRef,
        outline: event.outline,
        currentPageNumber: tab.pageNumber,
        totalPages: event.totalPages,
        showLeftPane: showLeftPane,
        pinLeftPane: pinLeftPane,
        sidebarWidth: sidebarWidth,
        leftPaneTabIndex: searchText.isNotEmpty ? 1 : 0,
        searchText: searchText,
        searchOptions: searchOptions,
        alternativeWords: alternativeWords,
        spacingValues: spacingValues,
        searchMode: searchMode,
        searchDistance: searchDistance,
        layoutMode: layoutMode,
        // כל פתיחה לעמוד שאינו הראשון (היסטוריה, סימניות, דף יומי,
        // חיפוש, קישור→PDF) צריכה overlay עד ש-stability tracking
        // ב-screen מסיים. בפתיחה לעמוד הראשון אין סיכון לקפיצות —
        // הספינר נסגר מיד.
        isLoading: tab.requiresStableLayout || tab.pageNumber > 1,
        loadSucceeded: true,
      ),
    );

    // Load per-book settings after document is ready
    add(const LoadPerBookSettings());
  }

  Future<void> _onRetryLoad(
    RetryLoad event,
    Emitter<PdfBookState> emit,
  ) async {
    final current = state;
    if (current is! PdfBookError) return;

    final book = _resolvePdfBookPath(current.book);
    if (!File(book.path).existsSync()) {
      emit(PdfBookError(book: book, message: 'הספר איננו קיים'));
      return;
    }

    // manual retry (משתמש לחץ כפתור — הייתה שגיאה ללא auto-retry):
    // מאפסים כדי לתת ניסיון שקט נוסף לפני הצגת כפתור.
    // auto-retry (BlocListener): לא מאפסים — הירייה הבאה תציג כפתור.
    if (!current.autoRetry) {
      _watchdogFiredCount = 0;
    }

    emit(
      PdfBookLoading(
        book: book,
        searchText: tab.searchText,
        searchOptions: tab.searchOptions,
        alternativeWords: tab.alternativeWords,
        spacingValues: tab.spacingValues,
        searchMode: tab.searchMode,
        searchDistance: tab.searchDistance,
        layoutMode: tab.savedLayoutMode ?? PdfLayoutMode.regularView,
      ),
    );
    _startLoadWatchdog();
    _loadHeadingsAndLinks(book);
  }

  void _onDocumentLoadFailed(
    DocumentLoadFailed event,
    Emitter<PdfBookState> emit,
  ) {
    _cancelLoadWatchdog();
    final current = state;
    final PdfBook book;

    if (current is PdfBookInitial) {
      book = current.book;
    } else if (current is PdfBookLoading) {
      book = current.book;
    } else {
      return;
    }

    emit(
      PdfBookError(
        book: book,
        message: event.message,
        autoRetry: event.autoRetry,
      ),
    );
  }

  void _onLoadHeadingsAndLinks(
    LoadHeadingsAndLinks event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    // אירוע ללא קישורים (טעינת headings בלבד) לא דורס את חלון הקישורים
    // ש-PdfBookScreen כבר מילא ב-tab.links.
    if (current is! PdfBookLoaded) {
      // Store for later if not loaded yet
      tab.pdfHeadings = event.headings;
      if (event.links.isNotEmpty) tab.links = event.links;
      return;
    }

    tab.pdfHeadings = event.headings;
    if (event.links.isNotEmpty) tab.links = event.links;

    emit(
      current.copyWith(
        pdfHeadings: event.headings,
        links: event.links.isEmpty ? null : event.links,
      ),
    );
  }

  // ============ Navigation Event Handlers ============

  Future<void> _onUpdatePageNumber(
    UpdatePageNumber event,
    Emitter<PdfBookState> emit,
  ) async {
    final current = state;
    if (current is! PdfBookLoaded) return;

    // Update tab
    tab.pageNumber = event.pageNumber;

    String title = event.title ?? 'עמוד ${event.pageNumber}';
    int? textLineNumber = event.textLineNumber;

    // Calculate title from outline if not provided
    if (event.title == null && current.outline != null) {
      title = await refFromPageNumber(
        event.pageNumber,
        current.outline!,
        current.book.title,
      );
    }

    // Calculate text line number from headings if not provided
    if (textLineNumber == null &&
        current.pdfHeadings != null &&
        title.isNotEmpty) {
      textLineNumber = current.pdfHeadings!.getLineNumberForHeading(title);
    }

    // Update tab values
    tab.currentTitle.value = title;
    if (textLineNumber != null) {
      tab.currentTextLineNumber = textLineNumber;
    }

    emit(
      current.copyWith(
        currentPageNumber: event.pageNumber,
        currentTitle: title,
        currentTextLineNumber: textLineNumber,
      ),
    );
  }

  void _onGoToPage(
    GoToPage event,
    Emitter<PdfBookState> emit,
  ) {
    if (!pdfController.isReady) return;
    pdfController.goToPage(pageNumber: event.pageNumber);
  }

  void _onGoToNextPage(
    GoToNextPage event,
    Emitter<PdfBookState> emit,
  ) {
    if (!pdfController.isReady) {
      return;
    }
    final current = state;
    if (current is! PdfBookLoaded) {
      return;
    }

    final nextPage = min(current.currentPageNumber + 1, current.totalPages);
    pdfController.goToPage(pageNumber: nextPage);
  }

  void _onGoToPreviousPage(
    GoToPreviousPage event,
    Emitter<PdfBookState> emit,
  ) {
    if (!pdfController.isReady) {
      return;
    }
    final current = state;
    if (current is! PdfBookLoaded) {
      return;
    }

    final prevPage = max(current.currentPageNumber - 1, 1);
    pdfController.goToPage(pageNumber: prevPage);
  }

  void _onGoToFirstPage(
    GoToFirstPage event,
    Emitter<PdfBookState> emit,
  ) {
    if (!pdfController.isReady) return;
    pdfController.goToPage(pageNumber: 1);
  }

  void _onGoToLastPage(
    GoToLastPage event,
    Emitter<PdfBookState> emit,
  ) {
    if (!pdfController.isReady) return;
    final current = state;
    if (current is! PdfBookLoaded) return;

    pdfController.goToPage(pageNumber: current.totalPages);
  }

  // ============ Zoom Event Handlers ============

  void _onUpdateZoom(
    UpdateZoom event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;

    // Save zoom for restoration
    tab.savedZoom = event.zoom;

    emit(current.copyWith(zoom: event.zoom));
  }

  void _onZoomIn(
    ZoomIn event,
    Emitter<PdfBookState> emit,
  ) {
    if (!pdfController.isReady) return;
    final current = state;
    if (current is! PdfBookLoaded) return;

    final newZoom = current.zoom * 1.1;
    pdfController.setZoom(
      pdfController.centerPosition,
      newZoom,
      duration: Duration.zero,
    );

    tab.savedZoom = newZoom;

    emit(current.copyWith(zoom: newZoom, showZoomBar: true));
    _startZoomBarTimer(emit);
    add(const SavePerBookSettings());
  }

  void _onZoomOut(
    ZoomOut event,
    Emitter<PdfBookState> emit,
  ) {
    if (!pdfController.isReady) return;
    final current = state;
    if (current is! PdfBookLoaded) return;

    final newZoom = current.zoom / 1.1;
    pdfController.setZoom(
      pdfController.centerPosition,
      newZoom,
      duration: Duration.zero,
    );

    tab.savedZoom = newZoom;

    emit(current.copyWith(zoom: newZoom, showZoomBar: true));
    _startZoomBarTimer(emit);
    add(const SavePerBookSettings());
  }

  void _onResetZoom(
    ResetZoom event,
    Emitter<PdfBookState> emit,
  ) {
    if (!pdfController.isReady) return;
    final current = state;
    if (current is! PdfBookLoaded) return;

    pdfController.setZoom(
      pdfController.centerPosition,
      1.0,
      duration: Duration.zero,
    );

    tab.savedZoom = 1.0;

    emit(current.copyWith(zoom: 1.0, showZoomBar: true));
    _startZoomBarTimer(emit);
    add(const SavePerBookSettings());
  }

  void _onSetLayoutMode(
    SetLayoutMode event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;

    tab.savedLayoutMode = event.layoutMode;

    if (current is PdfBookLoaded) {
      if (current.layoutMode == event.layoutMode) return;
      emit(current.copyWith(layoutMode: event.layoutMode));
      add(const SavePerBookSettings());
    } else if (current is PdfBookInitial) {
      emit(
        PdfBookInitial(
          book: current.book,
          initialPageNumber: current.initialPageNumber,
          searchText: current.searchText,
          searchOptions: current.searchOptions,
          alternativeWords: current.alternativeWords,
          spacingValues: current.spacingValues,
          searchMode: current.searchMode,
          searchDistance: current.searchDistance,
          layoutMode: event.layoutMode,
        ),
      );
    }
  }

  void _onSetShowZoomBar(
    SetShowZoomBar event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;

    emit(current.copyWith(showZoomBar: event.show));

    if (event.show) {
      _startZoomBarTimer(emit);
    }
  }

  void _startZoomBarTimer(Emitter<PdfBookState> emit) {
    _zoomBarTimer?.cancel();
    _zoomBarTimer = Timer(const Duration(seconds: 2), () {
      final current = state;
      if (current is PdfBookLoaded && current.showZoomBar) {
        // Can't emit here directly - need to use add()
        add(const SetShowZoomBar(false));
      }
    });
  }

  // ============ Left Pane Event Handlers ============

  void _onToggleLeftPane(
    ToggleLeftPane event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;

    final newShow = event.show ?? !current.showLeftPane;
    tab.showLeftPane.value = newShow;

    emit(current.copyWith(showLeftPane: newShow));
  }

  void _onTogglePinLeftPane(
    TogglePinLeftPane event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;

    final newPin = event.pin ?? !current.pinLeftPane;
    tab.pinLeftPane.value = newPin;

    emit(current.copyWith(pinLeftPane: newPin));
  }

  void _onUpdateLeftPaneTab(
    UpdateLeftPaneTab event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;

    emit(current.copyWith(leftPaneTabIndex: event.tabIndex));
  }

  void _onUpdateSidebarWidth(
    UpdateSidebarWidth event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;

    emit(current.copyWith(sidebarWidth: event.width));
  }

  // ============ Right Pane Event Handlers ============

  void _onToggleRightPane(
    ToggleRightPane event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;

    final newShow = event.show ?? !current.showRightPane;

    emit(
      current.copyWith(
        showRightPane: newShow,
        isRightPaneHovering: newShow ? current.isRightPaneHovering : false,
        rightPaneInitialTabIndex:
            event.initialTabIndex ?? current.rightPaneInitialTabIndex,
      ),
    );
  }

  void _onUpdateRightPaneWidth(
    UpdateRightPaneWidth event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;

    emit(current.copyWith(rightPaneWidth: event.width));
  }

  // ============ Search Event Handlers ============

  void _onUpdateSearchText(
    UpdateSearchText event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;

    tab.searchController.text = event.searchText;
    emit(current.copyWith(searchText: event.searchText));
  }

  void _onUpdateSearchOptions(
    UpdateSearchOptions event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;

    emit(
      current.copyWith(
        searchOptions: event.searchOptions ?? current.searchOptions,
        alternativeWords: event.alternativeWords ?? current.alternativeWords,
        spacingValues: event.spacingValues ?? current.spacingValues,
        searchMode: event.searchMode ?? current.searchMode,
        searchDistance: event.searchDistance ?? current.searchDistance,
      ),
    );

    tab.searchOptions = event.searchOptions ?? current.searchOptions;
    tab.alternativeWords = event.alternativeWords ?? current.alternativeWords;
    tab.spacingValues = event.spacingValues ?? current.spacingValues;
    tab.searchMode = event.searchMode ?? current.searchMode;
    tab.searchDistance = event.searchDistance ?? current.searchDistance;
  }

  void _onUpdateSearchResults(
    UpdateSearchResults event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;

    // Update tab values
    tab.pdfSearchMatches = event.matches;
    tab.pdfSearchCurrentMatchIndex = event.currentMatchIndex;

    emit(
      current.copyWith(
        searchMatches: event.matches,
        currentSearchMatchIndex: event.currentMatchIndex,
      ),
    );
  }

  void _onStartSearch(
    StartSearch event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;

    // Update search text
    tab.searchController.text = event.query;
    tab.searchText = event.query;

    emit(current.copyWith(searchText: event.query));
  }

  void _onClearSearch(
    ClearSearch event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;

    tab.searchController.clear();
    tab.searchText = '';
    tab.pdfSearchMatches = null;
    tab.pdfSearchCurrentMatchIndex = null;

    emit(
      current.copyWith(
        searchText: '',
        clearSearchMatches: true,
        clearCurrentSearchMatchIndex: true,
      ),
    );
  }

  // ============ Per-Book Settings Event Handlers ============

  Future<void> _onLoadPerBookSettings(
    LoadPerBookSettings event,
    Emitter<PdfBookState> emit,
  ) async {
    final current = state;
    if (current is! PdfBookLoaded) return;

    // בדיקה אם הגדרות פר-ספר מופעלות
    final enablePerBookSettings =
        Settings.getValue<bool>(SettingsRepository.keyEnablePerBookSettings) ??
        false;
    final pdfBookViewByDefault =
        Settings.getValue<bool>(SettingsRepository.keyPdfBookViewByDefault) ??
        false;

    double? zoomToApply;
    PdfLayoutMode? layoutModeToApply;

    if (enablePerBookSettings) {
      // נסה לטעון הגדרות פר-ספר
      final settings = await PdfBookPerBookSettings.load(current.book);
      if (settings?.zoom != null) {
        zoomToApply = settings!.zoom;
      }
      if (settings?.layoutMode != null) {
        layoutModeToApply = settings!.layoutMode;
      }
    }

    layoutModeToApply ??= pdfBookViewByDefault
        ? PdfLayoutMode.bookView
        : PdfLayoutMode.regularView;

    // אם אין הגדרות פר-ספר, נסה לשחזר זום מהסשן (שנשמר ב-tab.savedZoom)
    if (zoomToApply == null && tab.savedZoom != null && tab.savedZoom != 1.0) {
      zoomToApply = tab.savedZoom;
    }

    // החלת מצב תצוגה
    tab.savedLayoutMode = layoutModeToApply;
    final currentForLayout = state;
    if (currentForLayout is! PdfBookLoaded) return;
    if (currentForLayout.layoutMode != layoutModeToApply) {
      emit(currentForLayout.copyWith(layoutMode: layoutModeToApply));
    }

    // אם יש זום להחיל, מחילים אותו
    if (zoomToApply != null) {
      // Use retry loop to ensure controller is ready
      const maxAttempts = 10;
      const retryDelay = Duration(milliseconds: 50);

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        if (pdfController.isReady) {
          pdfController.setZoom(
            pdfController.centerPosition,
            zoomToApply,
            duration: Duration.zero,
          );
          tab.savedZoom = zoomToApply;
          final currentForZoom = state;
          if (currentForZoom is! PdfBookLoaded) return;
          emit(currentForZoom.copyWith(zoom: zoomToApply));
          break;
        }
        // Wait before next attempt
        await Future.delayed(retryDelay);
      }

      // Log warning if zoom couldn't be applied
      if (!pdfController.isReady) {
        debugPrint(
          'Warning: Could not apply saved zoom - controller not ready after $maxAttempts attempts',
        );
      }
    }
  }

  Future<void> _onSavePerBookSettings(
    SavePerBookSettings event,
    Emitter<PdfBookState> emit,
  ) async {
    final current = state;
    if (current is! PdfBookLoaded) return;

    final enablePerBookSettings =
        Settings.getValue<bool>(SettingsRepository.keyEnablePerBookSettings) ??
        false;
    if (!enablePerBookSettings) return;

    if (!pdfController.isReady) return;

    double? zoom;
    try {
      zoom = pdfController.value.zoom;
    } catch (e) {
      debugPrint('Warning: Could not get zoom from controller: $e');
    }

    final settings = PdfBookPerBookSettings(
      zoom: zoom,
      activeCommentators: List.from(tab.activeCommentators),
      layoutMode: current.layoutMode,
    );

    await settings.save(current.book);
  }

  Future<void> _onResetPerBookSettings(
    ResetPerBookSettings event,
    Emitter<PdfBookState> emit,
  ) async {
    final current = state;
    if (current is! PdfBookLoaded) return;

    await PdfBookPerBookSettings.delete(current.book);

    // Reset zoom and layout mode to default
    if (pdfController.isReady) {
      pdfController.setZoom(
        pdfController.centerPosition,
        1.0,
      );
      tab.savedZoom = 1.0;
      tab.savedLayoutMode = PdfLayoutMode.regularView;
      emit(current.copyWith(zoom: 1.0, layoutMode: PdfLayoutMode.regularView));
    }
  }

  // ============ UI State Event Handlers ============

  void _onSetRightPaneHovering(
    SetRightPaneHovering event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;

    emit(current.copyWith(isRightPaneHovering: event.isHovering));
  }

  void _onSetLoadingState(
    SetLoadingState event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;

    if (current is PdfBookLoaded) {
      emit(
        current.copyWith(
          isLoading: event.isLoading,
          loadSucceeded: event.succeeded,
        ),
      );
      return;
    }

    // pdfrx מדווח על סיום טעינה דרך onDocumentLoadFinished — לפעמים לפני (או
    // במקום) onViewerReady. אם הדיווח הוא על כישלון בזמן שאנחנו עדיין
    // ב-PdfBookLoading, ה-handler המקורי החזיר return מוקדם והאירוע נבלע.
    // התוצאה: state נשאר Loading ל-נצח (אין DocumentReady שיירה כי הטעינה
    // נכשלה), והמסך מציג ספינר אינסופי. עוברים ל-PdfBookError כדי שהמשתמש
    // יקבל משוב במקום להיתקע.
    if (current is PdfBookLoading && !event.succeeded) {
      _cancelLoadWatchdog();
      emit(
        PdfBookError(
          book: current.book,
          message: 'נכשלה טעינת ה-PDF',
        ),
      );
    }
  }
}
