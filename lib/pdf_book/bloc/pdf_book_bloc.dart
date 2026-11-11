import 'dart:async';
import 'dart:io';
import 'dart:ui' show Offset, Rect;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/models/pdf_reading_location.dart';
import 'package:otzaria/pdf_book/utils/pdf_viewer_activity.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/utils/file/file_book_path_resolver.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';
import 'package:pdfrx/pdfrx.dart';

/// סוג לפונקציית אתחול pdfrx — ניתן להחלפה בטסטים.
typedef PdfrxInitializer = Future<void> Function();

/// מרכז הזום שמשאיר את ראש [visible] (במרחב המסמך) במקומו. זום סביב המרכז
/// אחרי הקפיצה לעמוד היעד חושף את תחתית העמוד הקודם (#1974).
@visibleForTesting
Offset pdfZoomCenterKeepingTop(
  Rect visible, {
  required double fromZoom,
  required double toZoom,
}) => Offset(
  visible.center.dx,
  visible.top + visible.height * fromZoom / toZoom / 2,
);

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

  /// pdfium פתח את הקובץ בניסיון הנוכחי. לפני כן ניסיון חוזר רק נעמד בתור
  /// ה-worker מאחורי הפתיחה שעדיין רצה, ולכן איטיות אינה סיבה לנסות שוב.
  bool _documentOpened = false;

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
    on<LoadProgressed>(_onLoadProgressed);
    on<LoadWatchdogPaused>(_onLoadWatchdogPaused);
    on<LoadSlow>(_onLoadSlow);

    // Navigation events
    on<RememberPdfLocation>(_onRememberPdfLocation);
    on<ReturnToPreviousPdfLocation>(
      (event, emit) => _travelToPdfLocation(
        emit,
        (history) => history.takePrevious(event.current),
      ),
    );
    on<GoForwardPdfLocation>(
      (event, emit) => _travelToPdfLocation(
        emit,
        (history) => history.takeNext(event.current),
      ),
    );

    // Zoom events
    on<UpdateZoom>(_onUpdateZoom);
    on<ZoomIn>(_onZoomIn);
    on<ZoomOut>(_onZoomOut);
    on<ResetZoom>(_onResetZoom);
    on<FitZoom>(_onFitZoom);
    on<SetLayoutMode>(_onSetLayoutMode);
    on<SetShowZoomBar>(_onSetShowZoomBar);

    // Left pane events
    on<ToggleLeftPane>(_onToggleLeftPane);
    on<TogglePinLeftPane>(_onTogglePinLeftPane);
    on<UpdateSidebarWidth>(_onUpdateSidebarWidth);

    // Right pane events
    on<ToggleRightPane>(_onToggleRightPane);
    on<UpdateRightPaneWidth>(_onUpdateRightPaneWidth);

    // Search events
    on<UpdateSearchText>(_onUpdateSearchText);
    on<UpdateSearchOptions>(_onUpdateSearchOptions);

    // Per-book settings events
    on<LoadPerBookSettings>(_onLoadPerBookSettings);
    on<SavePerBookSettings>(_onSavePerBookSettings);
    on<ResetPerBookSettings>(_onResetPerBookSettings);

    // UI state events
    on<SetLoadingState>(_onSetLoadingState);
  }

  @override
  void onChange(Change<PdfBookState> change) {
    super.onChange(change);
    final wasLoading = change.currentState is PdfBookLoading;
    final isLoading = change.nextState is PdfBookLoading;
    if (!wasLoading && isLoading) PdfViewerActivity.instance.begin();
    if (wasLoading && !isLoading) PdfViewerActivity.instance.end();
  }

  @override
  Future<void> close() {
    _zoomBarTimer?.cancel();
    _loadWatchdog?.cancel();
    if (state is PdfBookLoading) PdfViewerActivity.instance.end();
    return super.close();
  }

  void _startLoadWatchdog() {
    _loadWatchdog?.cancel();
    // הירייה הראשונה (count==0): מפעיל retry שקט אחרי _autoRetryDelay.
    // הירייה השנייה ואילך: מציג כפתור "נסה שוב" אחרי _showButtonDelay.
    final isFirstFire = _watchdogFiredCount == 0;
    final timeout = isFirstFire ? _autoRetryDelay : _showButtonDelay;
    _loadWatchdog = Timer(timeout, () {
      if (isClosed) return;
      if (state is! PdfBookLoading) return;
      _watchdogFiredCount++;
      if (isFirstFire && !_documentOpened) {
        add(const LoadSlow());
        return;
      }
      add(
        DocumentLoadFailed('הטעינה ארכה זמן רב מדי', autoRetry: isFirstFire),
      );
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
    if (!await File(book.path).exists()) {
      emit(PdfBookError(book: book, message: 'הספר איננו קיים'));
      return;
    }

    _watchdogFiredCount = 0;
    _documentOpened = false;
    emit(
      PdfBookLoading(
        book: book,
        searchText: initial.searchText,
        searchOptions: initial.searchOptions,
        alternativeWords: initial.alternativeWords,
        spacingValues: initial.spacingValues,
        searchMode: initial.searchMode,
        searchDistance: initial.searchDistance,
        matchPolicy: initial.matchPolicy,
        layoutMode: initial.layoutMode,
      ),
    );

    // האתחול של pdfrx עלול לקחת 10–20 שניות; ה-watchdog מתחיל רק אחריו.
    // כשל באתחול אינו עוצר: ה-watchdog יציג שגיאה במקום ספינר נצחי.
    try {
      await _pdfrxInit();
    } catch (_) {}
    if (isClosed || state is! PdfBookLoading) return;
    _startLoadWatchdog();
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
      source: book.source,
      externalLibraryId: book.externalLibraryId,
    );
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
    final SearchMatchPolicy matchPolicy;
    final PdfLayoutMode layoutMode;

    if (current is PdfBookInitial) {
      book = current.book;
      searchText = current.searchText;
      searchOptions = current.searchOptions;
      alternativeWords = current.alternativeWords;
      spacingValues = current.spacingValues;
      searchMode = current.searchMode;
      searchDistance = current.searchDistance;
      matchPolicy = current.matchPolicy;
      layoutMode = current.layoutMode;
    } else if (current is PdfBookLoading) {
      book = current.book;
      searchText = current.searchText;
      searchOptions = current.searchOptions;
      alternativeWords = current.alternativeWords;
      spacingValues = current.spacingValues;
      searchMode = current.searchMode;
      searchDistance = current.searchDistance;
      matchPolicy = current.matchPolicy;
      layoutMode = current.layoutMode;
    } else if (current is PdfBookError && !current.autoRetry) {
      // הפתיחה האיטית הסתיימה אחרי שהוצג "נסה שוב": ההצלחה המאוחרת גוברת.
      book = current.book;
      searchText = tab.searchText;
      searchOptions = tab.searchOptions;
      alternativeWords = tab.alternativeWords;
      spacingValues = tab.spacingValues;
      searchMode = tab.searchMode;
      searchDistance = tab.searchDistance;
      matchPolicy = tab.matchPolicy;
      layoutMode = tab.savedLayoutMode ?? PdfLayoutMode.regularView;
    } else if (current is PdfBookLoaded) {
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
      screenWidth: event.screenWidth,
    );
    // בלי סנכרון ה-notifier, כפתור הסגירה בסרגל מחשב כיוון הפוך ונתקע (issue #869)
    tab.showLeftPane.value = showLeftPane;
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
        searchText: searchText,
        searchOptions: searchOptions,
        alternativeWords: alternativeWords,
        spacingValues: spacingValues,
        searchMode: searchMode,
        searchDistance: searchDistance,
        matchPolicy: matchPolicy,
        layoutMode: layoutMode,
        isLoading: false,
        loadSucceeded: true,
      ),
    );

    add(const LoadPerBookSettings());
  }

  Future<void> _onRetryLoad(
    RetryLoad event,
    Emitter<PdfBookState> emit,
  ) async {
    final current = state;
    if (current is! PdfBookError) return;

    final book = _resolvePdfBookPath(current.book);
    if (!await File(book.path).exists()) {
      emit(PdfBookError(book: book, message: 'הספר איננו קיים'));
      return;
    }

    // manual retry (משתמש לחץ כפתור — הייתה שגיאה ללא auto-retry):
    // מאפסים כדי לתת ניסיון שקט נוסף לפני הצגת כפתור.
    // auto-retry (BlocListener): לא מאפסים — הירייה הבאה תציג כפתור.
    if (!current.autoRetry) {
      _watchdogFiredCount = 0;
    }
    _documentOpened = false;

    emit(
      PdfBookLoading(
        book: book,
        searchText: tab.searchText,
        searchOptions: tab.searchOptions,
        alternativeWords: tab.alternativeWords,
        spacingValues: tab.spacingValues,
        searchMode: tab.searchMode,
        searchDistance: tab.searchDistance,
        matchPolicy: tab.matchPolicy,
        layoutMode: tab.savedLayoutMode ?? PdfLayoutMode.regularView,
      ),
    );
    _startLoadWatchdog();
  }

  void _onLoadProgressed(LoadProgressed event, Emitter<PdfBookState> emit) {
    if (event.documentOpened) _documentOpened = true;
    if (state is PdfBookLoading) _startLoadWatchdog();
  }

  void _onLoadSlow(LoadSlow event, Emitter<PdfBookState> emit) {
    final current = state;
    if (current is! PdfBookLoading) return;
    emit(current.copyWith(isSlow: true));
    _startLoadWatchdog();
  }

  void _onLoadWatchdogPaused(
    LoadWatchdogPaused event,
    Emitter<PdfBookState> emit,
  ) {
    _cancelLoadWatchdog();
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

  // ============ Navigation Event Handlers ============

  void _onRememberPdfLocation(
    RememberPdfLocation event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;
    tab.navigationHistory.remember(event.location);
  }

  Future<void> _travelToPdfLocation(
    Emitter<PdfBookState> emit,
    PdfReadingLocation? Function(PdfLocationHistory history) take,
  ) async {
    final current = state;
    if (current is! PdfBookLoaded || !pdfController.isReady) return;
    final pages = pdfController.layout.pageLayouts;
    if (pages.isEmpty) return;
    final location = take(tab.navigationHistory);
    if (location == null) return;
    final page = location.pageNumber.clamp(1, pages.length);
    emit(current.copyWith(zoom: location.zoom));
    await pdfController.goTo(
      pdfController.calcMatrixFor(
        location.centerIn(pages[page - 1], pdfController.viewSize),
        zoom: location.zoom,
      ),
      duration: Duration.zero,
    );
    tab.savedZoom = location.zoom;
    if (!isClosed) add(const SavePerBookSettings());
  }

  // ============ Zoom Event Handlers ============

  void _onUpdateZoom(
    UpdateZoom event,
    Emitter<PdfBookState> emit,
  ) {
    final current = state;
    if (current is! PdfBookLoaded) return;

    tab.savedZoom = event.zoom;

    emit(current.copyWith(zoom: event.zoom));
  }

  void _onZoomIn(ZoomIn event, Emitter<PdfBookState> emit) =>
      _applyZoom(emit, (zoom) => zoom * 1.1);

  void _onZoomOut(ZoomOut event, Emitter<PdfBookState> emit) =>
      _applyZoom(emit, (zoom) => zoom / 1.1);

  void _onFitZoom(FitZoom event, Emitter<PdfBookState> emit) =>
      _applyZoom(emit, (_) => event.zoom, center: event.center);

  void _onResetZoom(ResetZoom event, Emitter<PdfBookState> emit) =>
      _applyZoom(emit, (_) => 1.0);

  /// זום מכפתורי הסרגל ומהקיצורים: מוחל מיד (בלי אנימציה) סביב [center]
  /// או מרכז התצוגה, נשמר בטאב ובהגדרות הספר, וסרגל הזום מוצג.
  void _applyZoom(
    Emitter<PdfBookState> emit,
    double Function(double zoom) zoomFrom, {
    Offset? center,
  }) {
    if (!pdfController.isReady) return;
    final current = state;
    if (current is! PdfBookLoaded) return;

    final zoom = zoomFrom(current.zoom);
    pdfController.setZoom(
      center ?? pdfController.centerPosition,
      zoom,
      duration: Duration.zero,
    );
    tab.savedZoom = zoom;

    emit(current.copyWith(zoom: zoom, showZoomBar: true));
    _startZoomBarTimer(emit);
    add(const SavePerBookSettings());
  }

  Future<void> _onSetLayoutMode(
    SetLayoutMode event,
    Emitter<PdfBookState> emit,
  ) async {
    final current = state;

    tab.savedLayoutMode = event.layoutMode;

    if (current is PdfBookLoaded) {
      if (current.layoutMode == event.layoutMode) return;
      emit(current.copyWith(layoutMode: event.layoutMode));
      if (current.layoutMode.isBookView != event.layoutMode.isBookView) {
        await _fitWidthAfterRelayout();
      } else {
        add(const SavePerBookSettings());
      }
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
          matchPolicy: current.matchPolicy,
          layoutMode: event.layoutMode,
        ),
      );
    }
  }

  /// כמו בפתיחה טרייה: התאמה לרוחב המסמך, אחרי ש-pdfrx פרס אותו מחדש.
  /// FitZoom שומר את הזום החדש בטאב ובהגדרות הספר.
  Future<void> _fitWidthAfterRelayout() async {
    await SchedulerBinding.instance.endOfFrame;
    if (isClosed || !pdfController.isReady) return;
    final documentSize = pdfController.documentSize;
    final zoom = pdfController.viewSize.width / documentSize.width;
    final keepTop = pdfZoomCenterKeepingTop(
      pdfController.visibleRect,
      fromZoom: pdfController.currentZoom,
      toZoom: zoom,
    );
    add(
      FitZoom(zoom: zoom, center: Offset(documentSize.width / 2, keepTop.dy)),
    );
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
        // הזום התייצב — כך נשמר גם זום מגלגלת/צביטה, ולא רק מכפתורי הסרגל.
        add(const SavePerBookSettings());
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

    emit(current.copyWith(showRightPane: newShow));
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
        matchPolicy: event.matchPolicy ?? current.matchPolicy,
        searchDistance: event.searchDistance ?? current.searchDistance,
      ),
    );

    tab.searchOptions = event.searchOptions ?? current.searchOptions;
    tab.alternativeWords = event.alternativeWords ?? current.alternativeWords;
    tab.spacingValues = event.spacingValues ?? current.spacingValues;
    tab.searchMode = event.searchMode ?? current.searchMode;
    tab.searchDistance = event.searchDistance ?? current.searchDistance;
    tab.matchPolicy = event.matchPolicy ?? current.matchPolicy;
    tab.searchOrigin = event.searchOrigin ?? tab.searchOrigin;
    if (!identical(event.searchTemplate, preserveInBookSearchTemplate)) {
      tab.searchTemplate = event.searchTemplate as InBookSearchTemplate?;
    }
  }

  // ============ Per-Book Settings Event Handlers ============

  Future<void> _onLoadPerBookSettings(
    LoadPerBookSettings event,
    Emitter<PdfBookState> emit,
  ) async {
    final current = state;
    if (current is! PdfBookLoaded) return;

    final enablePerBookSettings =
        Settings.getValue<bool>(SettingsRepository.keyEnablePerBookSettings) ??
        false;
    final pdfBookViewByDefault =
        Settings.getValue<bool>(SettingsRepository.keyPdfBookViewByDefault) ??
        false;

    double? zoomToApply;
    PdfLayoutMode? layoutModeToApply;

    if (enablePerBookSettings) {
      final settings = await PdfBookPerBookSettings.load(current.book);
      if (settings?.zoom != null) {
        zoomToApply = settings!.zoom;
      }
      if (settings?.layoutMode != null) {
        layoutModeToApply = settings!.layoutMode;
      }
    }

    // ללא הגדרה פר-ספרית, מצב שמור בטאב (שחזור טאבים) גובר על ברירת
    // המחדל הבוליאנית כשהם מסכימים ברמת ספר/רגיל — משמר את כיוון הזוגות.
    final saved = tab.savedLayoutMode;
    layoutModeToApply ??=
        saved != null && saved.isBookView == pdfBookViewByDefault
        ? saved
        : pdfBookViewByDefault
        ? PdfLayoutMode.bookView
        : PdfLayoutMode.regularView;

    // החלת מצב תצוגה — לפני קריאת tab.savedZoom, שמתבטל במעבר ספר/רגיל.
    tab.savedLayoutMode = layoutModeToApply;

    // אם אין הגדרות פר-ספר, נסה לשחזר זום מהסשן (שנשמר ב-tab.savedZoom)
    if (zoomToApply == null && tab.savedZoom != null && tab.savedZoom != 1.0) {
      zoomToApply = tab.savedZoom;
    }

    final currentForLayout = state;
    if (currentForLayout is! PdfBookLoaded) return;
    if (currentForLayout.layoutMode != layoutModeToApply) {
      emit(currentForLayout.copyWith(layoutMode: layoutModeToApply));
      if (zoomToApply == null &&
          currentForLayout.layoutMode.isBookView !=
              layoutModeToApply.isBookView) {
        await _fitWidthAfterRelayout();
      }
    }

    if (zoomToApply != null) {
      // Use retry loop to ensure controller is ready
      const maxAttempts = 10;
      const retryDelay = Duration(milliseconds: 50);

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        if (pdfController.isReady) {
          pdfController.setZoom(
            pdfZoomCenterKeepingTop(
              pdfController.visibleRect,
              fromZoom: pdfController.currentZoom,
              toZoom: zoomToApply,
            ),
            zoomToApply,
            duration: Duration.zero,
          );
          tab.savedZoom = zoomToApply;
          final currentForZoom = state;
          if (currentForZoom is! PdfBookLoaded) return;
          emit(currentForZoom.copyWith(zoom: zoomToApply));
          break;
        }
        await Future.delayed(retryDelay);
      }

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

    if (pdfController.isReady) {
      pdfController.setZoom(
        pdfController.centerPosition,
        1.0,
      );
      tab.savedLayoutMode = PdfLayoutMode.regularView;
      tab.savedZoom = 1.0;
      emit(current.copyWith(zoom: 1.0, layoutMode: PdfLayoutMode.regularView));
    }
  }

  // ============ UI State Event Handlers ============

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

    // pdfrx עלול לדווח על כישלון לפני onViewerReady או במקומו; בלי המעבר
    // ל-PdfBookError המסך נשאר בספינר אינסופי.
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
