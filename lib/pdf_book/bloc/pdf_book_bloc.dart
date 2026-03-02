import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/utils/ref_helper.dart';
import 'package:pdfrx/pdfrx.dart';

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

  Timer? _zoomBarTimer;

  PdfBookBloc({
    required this.tab,
    required PdfBookInitial initialState,
  })  : pdfController = tab.pdfViewerController,
        super(initialState) {
    // Document events
    on<LoadPdfDocument>(_onLoadPdfDocument);
    on<DocumentReady>(_onDocumentReady);
    on<DocumentLoadFailed>(_onDocumentLoadFailed);
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
    return super.close();
  }

  // ============ Document Event Handlers ============

  Future<void> _onLoadPdfDocument(
    LoadPdfDocument event,
    Emitter<PdfBookState> emit,
  ) async {
    final initial = state;
    if (initial is! PdfBookInitial) return;

    emit(PdfBookLoading(book: initial.book));

    // Load headings and links in background
    _loadHeadingsAndLinks(initial.book);
  }

  Future<void> _loadHeadingsAndLinks(PdfBook book) async {
    try {
      debugPrint('=== Loading PDF Headings and Links ===');
      debugPrint('Book title: ${book.title}');

      // Load headings from DB
      final headings = await PdfHeadings.loadFromDatabase(book.title);
      if (headings != null) {
        debugPrint('✅ Loaded ${headings.headingsMap.length} headings');
      }

      // Load links
      final library = await DataRepository.instance.library;
      final textBook = library.findTextBookByTitleAndCategory(
        book.title,
        categoryId: book.categoryId,
      );
      List<Link> links = [];

      if (textBook != null) {
        links = await textBook.links;
        debugPrint('✅ Loaded ${links.length} links');
      }

      add(LoadHeadingsAndLinks(headings: headings, links: links));
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading PDF headings and links: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  void _onDocumentReady(
    DocumentReady event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    final PdfBook book;
    final String searchText;
    final Map<String, Map<String, bool>> searchOptions;
    final Map<int, List<String>> alternativeWords;
    final Map<String, String> spacingValues;
    final SearchMode searchMode;

    if (current is PdfBookInitial) {
      book = current.book;
      searchText = current.searchText;
      searchOptions = current.searchOptions;
      alternativeWords = current.alternativeWords;
      spacingValues = current.spacingValues;
      searchMode = current.searchMode;
    } else if (current is PdfBookLoading) {
      book = current.book;
      searchText = '';
      searchOptions = const {};
      alternativeWords = const {};
      spacingValues = const {};
      searchMode = SearchMode.exact;
    } else if (current is PdfBookLoaded) {
      // Already loaded, just update
      emit(current.copyWith(
        documentRef: event.documentRef,
        outline: event.outline,
        totalPages: event.totalPages,
      ));
      return;
    } else {
      return;
    }

    final showLeftPane = tab.showLeftPane.value || searchText.isNotEmpty;
    final pinLeftPane = Settings.getValue<bool>('key-pin-sidebar') ?? false;
    final sidebarWidth =
        Settings.getValue<double>('key-sidebar-width', defaultValue: 300)!;

    emit(PdfBookLoaded(
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
      isLoading: false, // Document is ready, so no longer loading
      loadSucceeded: true,
    ));

    // Load per-book settings after document is ready
    add(const LoadPerBookSettings());
  }

  void _onDocumentLoadFailed(
    DocumentLoadFailed event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    final PdfBook book;

    if (current is PdfBookInitial) {
      book = current.book;
    } else if (current is PdfBookLoading) {
      book = current.book;
    } else {
      return;
    }

    emit(PdfBookError(book: book, message: event.message));
  }

  void _onLoadHeadingsAndLinks(
    LoadHeadingsAndLinks event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) {
      // Store for later if not loaded yet
      tab.pdfHeadings = event.headings;
      tab.links = event.links;
      return;
    }

    tab.pdfHeadings = event.headings;
    tab.links = event.links;

    emit(current.copyWith(
      pdfHeadings: event.headings,
      links: event.links,
    ));
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

    emit(current.copyWith(
      currentPageNumber: event.pageNumber,
      currentTitle: title,
      currentTextLineNumber: textLineNumber,
    ));
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
    );

    tab.savedZoom = 1.0;

    emit(current.copyWith(zoom: 1.0, showZoomBar: true));
    _startZoomBarTimer(emit);
    add(const SavePerBookSettings());
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

    emit(current.copyWith(
      showRightPane: newShow,
      rightPaneInitialTabIndex:
          event.initialTabIndex ?? current.rightPaneInitialTabIndex,
    ));
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

    emit(current.copyWith(
      searchOptions: event.searchOptions ?? current.searchOptions,
      alternativeWords: event.alternativeWords ?? current.alternativeWords,
      spacingValues: event.spacingValues ?? current.spacingValues,
      searchMode: event.searchMode ?? current.searchMode,
    ));
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

    emit(current.copyWith(
      searchMatches: event.matches,
      currentSearchMatchIndex: event.currentMatchIndex,
    ));
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

    emit(current.copyWith(
      searchText: '',
      clearSearchMatches: true,
      clearCurrentSearchMatchIndex: true,
    ));
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
        Settings.getValue<bool>('key-enable-per-book-settings') ?? false;

    double? zoomToApply;

    if (enablePerBookSettings) {
      // נסה לטעון הגדרות פר-ספר
      final settings = await PdfBookPerBookSettings.load(current.book.title);
      if (settings?.zoom != null) {
        zoomToApply = settings!.zoom;
      }
    }

    // אם אין הגדרות פר-ספר, נסה לשחזר זום מהסשן (שנשמר ב-tab.savedZoom)
    if (zoomToApply == null && tab.savedZoom != null && tab.savedZoom != 1.0) {
      zoomToApply = tab.savedZoom;
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
          );
          tab.savedZoom = zoomToApply;
          emit(current.copyWith(zoom: zoomToApply));
          break;
        }
        // Wait before next attempt
        await Future.delayed(retryDelay);
      }

      // Log warning if zoom couldn't be applied
      if (!pdfController.isReady) {
        debugPrint(
            'Warning: Could not apply saved zoom - controller not ready after $maxAttempts attempts');
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
        Settings.getValue<bool>('key-enable-per-book-settings') ?? false;
    if (!enablePerBookSettings) return;

    if (!pdfController.isReady) return;

    final settings = PdfBookPerBookSettings(
      zoom: pdfController.value.zoom,
    );

    await settings.save(current.book.title);
  }

  Future<void> _onResetPerBookSettings(
    ResetPerBookSettings event,
    Emitter<PdfBookState> emit,
  ) async {
    final current = state;
    if (current is! PdfBookLoaded) return;

    await PdfBookPerBookSettings.delete(current.book.title);

    // Reset zoom to default
    if (pdfController.isReady) {
      pdfController.setZoom(
        pdfController.centerPosition,
        1.0,
      );
      tab.savedZoom = 1.0;
      emit(current.copyWith(zoom: 1.0));
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
    if (current is! PdfBookLoaded) return;

    emit(current.copyWith(
      isLoading: event.isLoading,
      loadSucceeded: event.succeeded,
    ));
  }
}
