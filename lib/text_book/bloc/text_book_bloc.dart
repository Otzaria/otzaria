import 'dart:async';
import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart';
import 'package:otzaria/models/books.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/services/nikud_display_service.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/text_book/view/page_shape/utils/default_commentators.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/text_book/utils/link_processing.dart';
import 'package:otzaria/text_book/utils/he_categories_enricher.dart';
import 'package:otzaria/text_book/utils/commentator_group_builder.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart' as notes;
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class TextBookBloc extends Bloc<TextBookEvent, TextBookState> {
  static const int _linkLookBehindLines = 60;
  static const int _linkLookAheadLines = 140;
  static const int _linksReloadThresholdLines = 20;
  static const int _initialContentLookBehindLines = 80;
  static const int _initialContentLookAheadLines = 180;
  static const int _contentLookBehindLines = 120;
  static const int _contentLookAheadLines = 260;
  static const int _contentWarmChunkLines = 640;
  static const int _warmFlushChunkCount = 8;
  static const int _contentReloadThresholdLines = 60;
  static const Duration _visibleIndicesDebounceDuration =
      Duration(milliseconds: 160);
  static const String _allTargetBookTitlesSignature =
      '__all_target_book_titles__';

  final TextBookRepository repository;
  final Future<String?> Function(
    String title,
    int currentLine, {
    int? categoryId,
    String? fileType,
    bool preferUserBooks,
  }) _quickPreviewLoader;
  final ItemScrollController scrollController;
  final ItemPositionsListener positionsListener;
  final ScrollOffsetController? scrollOffsetController;

  Timer? _debounceTimer;
  Timer? _highlightTimer;
  VoidCallback? _positionListenerCallback;
  int? _loadedLinksStart;
  int? _loadedLinksEnd;
  String? _loadedLinksBookTitle;
  String? _loadedLinksTargetBookTitlesSignature;
  String? _activeLinksTargetBookTitlesSignature;
  String? _loadedContentBookTitle;
  List<({int startLine, int endLine})> _loadedContentRanges = const [];
  List<bool> _loadedContentFlags = const [];
  int? _loadedContentTotalLines;
  bool _isLoadingContentRange = false;
  bool _pendingContentRangeReload = false;
  bool _isWarmingContentCache = false;
  String? _cachedPageShapeTargetBookTitlesKey;
  List<String>? _cachedPageShapeTargetBookTitles;
  bool _isLoadingLinks = false;
  bool _pendingLinksReload = false;
  List<int>? _pendingForceLoadIndices;
  bool _pendingForceLoadAll = false;
  bool _awaitingInitialPageShapeVisibleSync = false;

  /// סימון אם המשתמש שינה ידנית את בחירת המפרשים. בשונה מ-`activeCommentators.isEmpty`,
  /// הדגל הזה מבחין בין "עוד לא נבחר כלום" (false) לבין "המשתמש ריקן את הבחירה
  /// במכוון" (true) — וכך מונע אוטו-בחירה חוזרת של 'הערות' אחרי שהמשתמש כיבה אותן.
  bool _userTouchedCommentators = false;

  /// true אחרי שסרקנו את כל ה-content (ApplyFullBookContent) — מאפשר לדלג
  /// על סריקות עתידיות גם אם 'הערות' לא נוסף ל-availableCommentators.
  bool _inlineNotesFullScanDone = false;

  /// מאפס את הדגלים הספציפיים-לספר. נקרא מ-_onLoadContent כשבלוק עובר
  /// לטעון ספר חדש (כיום בייצור bloc נוצר חדש לכל תא, אבל הקריאה כאן
  /// מגינה מפני דליפת state בין ספרים אם זה ישתנה בעתיד).
  @visibleForTesting
  void resetInlineNotesStateForNewBook() {
    _userTouchedCommentators = false;
    _inlineNotesFullScanDone = false;
  }

  @visibleForTesting
  bool get userTouchedCommentatorsForTesting => _userTouchedCommentators;

  @visibleForTesting
  bool get inlineNotesFullScanDoneForTesting => _inlineNotesFullScanDone;

  // pinpoint highlight ממתין להחלה כשה-bloc יגיע ל-Loaded
  ({String text, int? sectionIndex})? _pendingPinpoint;

  /// גודל גופן שהגיע (דרך `UpdateFontSize`) לפני שהטעינה הסתיימה. בעליית
  /// התוכנה ההגדרות נטענות מהר יותר מתוכן הספר, כך שעדכון הגופן עלול להגיע
  /// בזמן `Loading`. נשמר כאן ויוחל ב-`_onLoadContent` במעבר ל-`Loaded`.
  double? _pendingFontSize;

  TextBookBloc({
    required this.repository,
    Future<String?> Function(
      String title,
      int currentLine, {
      int? categoryId,
      String? fileType,
      bool preferUserBooks,
    })? quickPreviewLoader,
    required TextBookInitial initialState,
    required this.scrollController,
    required this.positionsListener,
    this.scrollOffsetController,
  })  : _quickPreviewLoader = quickPreviewLoader ??
            SqliteDataProvider.instance.getBookQuickPreview,
        super(initialState) {
    on<LoadContent>(_onLoadContent);
    on<UpdateResolvedBookId>(_onUpdateResolvedBookId);
    on<UpdateFontSize>(_onUpdateFontSize);
    on<ToggleLeftPane>(_onToggleLeftPane);
    on<ToggleSplitView>(_onToggleSplitView);
    on<ToggleTzuratHadafView>(_onToggleTzuratHadafView);
    on<TogglePageShapeView>(_onTogglePageShapeView);
    on<UpdateCommentators>(_onUpdateCommentators);
    on<ToggleNikud>(_onToggleNikud);
    on<TogglePunctuation>(_onTogglePunctuation);
    on<ToggleContinuousReadingMode>(_onToggleContinuousReadingMode);
    on<UpdateVisibleIndecies>(_onUpdateVisibleIndecies);
    on<UpdateSelectedIndex>(_onUpdateSelectedIndex);
    on<HighlightLine>(_onHighlightLine);
    on<ClearHighlightedLine>(_onClearHighlightedLine);
    on<ApplyMarkHighlight>(_onApplyMarkHighlight);
    on<TogglePinLeftPane>(_onTogglePinLeftPane);
    on<UpdateSearchText>(_onUpdateSearchText);
    on<ApplyFullBookContent>(_onApplyFullBookContent);
    on<ApplyBookContentRange>(_onApplyBookContentRange);
    on<ApplyBookContentRanges>(_onApplyBookContentRanges);
    on<CreateNoteFromToolbar>(_onCreateNoteFromToolbar);
    on<UpdateSelectedTextForNote>(_onUpdateSelectedTextForNote);
    on<UpdateLinks>(_onUpdateLinks);
    on<SetLinksLoading>(_onSetLinksLoading);
    on<UpdateAvailableCommentators>(_onUpdateAvailableCommentators);
    on<RefreshLinksForCurrentWindow>(_onRefreshLinksForCurrentWindow);
    on<LoadAllLinksForIndices>(_onLoadAllLinksForIndices);
  }

  /// מחזירה את הערך האפקטיבי של מצב הרצף לאחר אירוע
  /// [ToggleContinuousReadingMode].
  ///
  /// ספר שלא תומך → תמיד false (גם אם בקשו true ידנית — דרך קיצור מקלדת
  /// או plugin).
  @visibleForTesting
  static bool computeEffectiveContinuousReading({
    required bool requestedEnabled,
    required bool stateSupportsContinuous,
  }) =>
      requestedEnabled && stateSupportsContinuous;

  /// קובעת את הערך של `continuousReadingMode` ב-`emit` של `_onLoadContent`.
  ///
  /// - ספר שלא תומך → תמיד false.
  /// - אם הדגל [preserveFlag] פעיל ו-currentState הוא Loaded → שומרים
  ///   את הערך הקודם של המשתמש.
  /// - אחרת — default (false). זה המסלול שמאפס בעת `_resetPerBookSettings`.
  @visibleForTesting
  static bool resolvePreservedContinuousReadingMode({
    required bool supportsContinuous,
    required bool preserveFlag,
    required TextBookState? currentState,
  }) {
    if (!supportsContinuous) return false;
    if (!preserveFlag) return false;
    if (currentState is! TextBookLoaded) return false;
    return currentState.continuousReadingMode;
  }

  @visibleForTesting
  static int? expectedInitialPageShapeVisibleIndexForTesting({
    required List<int> visibleIndices,
    required int? selectedIndex,
  }) {
    if (visibleIndices.isNotEmpty) {
      return visibleIndices.first;
    }
    return selectedIndex;
  }

  static const int _initialVisibleSyncTolerance = 2;

  static ({int min, int max}) _visibleBounds(List<int> indices) {
    return (
      min: indices.reduce((a, b) => a < b ? a : b),
      max: indices.reduce((a, b) => a > b ? a : b),
    );
  }

  @visibleForTesting
  static bool isInitialPageShapeVisibleSyncAlignedForTesting({
    required List<int> currentVisibleIndices,
    required int? selectedIndex,
    required List<int> nextVisibleIndices,
  }) {
    final expectedIndex = expectedInitialPageShapeVisibleIndexForTesting(
      visibleIndices: currentVisibleIndices,
      selectedIndex: selectedIndex,
    );
    if (expectedIndex == null || nextVisibleIndices.isEmpty) {
      return true;
    }

    final bounds = _visibleBounds(nextVisibleIndices);
    return expectedIndex >= (bounds.min - _initialVisibleSyncTolerance) &&
        expectedIndex <= (bounds.max + _initialVisibleSyncTolerance);
  }

  static bool _looksLikeStaleInitialStartReport({
    required int? expectedIndex,
    required List<int> nextVisibleIndices,
  }) {
    if (expectedIndex == null || nextVisibleIndices.isEmpty) {
      return false;
    }

    final bounds = _visibleBounds(nextVisibleIndices);
    return expectedIndex > _initialVisibleSyncTolerance &&
        bounds.min <= _initialVisibleSyncTolerance &&
        bounds.max < expectedIndex - _initialVisibleSyncTolerance;
  }

  @visibleForTesting
  static List<({int startLine, int endLine})>
      mergeLoadedContentRangesForTesting(
    List<({int startLine, int endLine})> ranges, {
    required int startLine,
    required int endLine,
  }) {
    final normalizedStart = startLine < 0 ? 0 : startLine;
    if (endLine < normalizedStart) {
      return List<({int startLine, int endLine})>.unmodifiable(ranges);
    }

    final sorted = [
      ...ranges,
      (startLine: normalizedStart, endLine: endLine),
    ]..sort((a, b) => a.startLine.compareTo(b.startLine));

    final merged = <({int startLine, int endLine})>[];
    for (final range in sorted) {
      if (merged.isEmpty) {
        merged.add(range);
        continue;
      }

      final last = merged.last;
      if (range.startLine <= last.endLine + 1) {
        merged[merged.length - 1] = (
          startLine: last.startLine,
          endLine: range.endLine > last.endLine ? range.endLine : last.endLine,
        );
        continue;
      }

      merged.add(range);
    }

    return List<({int startLine, int endLine})>.unmodifiable(merged);
  }

  @visibleForTesting
  static bool isContentWindowSufficientForTesting({
    required List<({int startLine, int endLine})> loadedRanges,
    required int startLine,
    required int endLine,
    required int reloadThresholdLines,
  }) {
    if (loadedRanges.isEmpty) {
      return false;
    }

    final normalizedStart = startLine < 0 ? 0 : startLine;
    for (final range in loadedRanges) {
      final hasStartMargin = (normalizedStart == 0 && range.startLine == 0) ||
          normalizedStart >= range.startLine + reloadThresholdLines;
      if (hasStartMargin && endLine <= range.endLine - reloadThresholdLines) {
        return true;
      }
    }

    return false;
  }

  @visibleForTesting
  static int? nextWarmContentStartForTesting({
    required List<({int startLine, int endLine})> loadedRanges,
    required int totalLines,
  }) {
    if (totalLines <= 0) {
      return null;
    }
    if (loadedRanges.isEmpty) {
      return 0;
    }

    var nextStart = 0;
    for (final range in loadedRanges) {
      if (nextStart < range.startLine) {
        return nextStart;
      }
      if (nextStart <= range.endLine) {
        nextStart = range.endLine + 1;
        if (nextStart >= totalLines) {
          return null;
        }
      }
    }

    return nextStart < totalLines ? nextStart : null;
  }

  @visibleForTesting
  static int? nextWarmContentStartNearViewportForTesting({
    required List<({int startLine, int endLine})> loadedRanges,
    required int totalLines,
    required List<int> visibleIndices,
    required int chunkLines,
  }) {
    if (totalLines <= 0) {
      return null;
    }

    if (loadedRanges.isEmpty) {
      return 0;
    }

    final firstVisible = visibleIndices.isEmpty ? 0 : visibleIndices.first;
    final lastVisible =
        visibleIndices.isEmpty ? firstVisible : visibleIndices.last;

    ({int startLine, int endLine})? anchorRange;
    for (final range in loadedRanges) {
      final overlapsViewport =
          range.startLine <= lastVisible && range.endLine >= firstVisible;
      if (overlapsViewport) {
        anchorRange = range;
        break;
      }
    }

    if (anchorRange == null) {
      return nextWarmContentStartForTesting(
        loadedRanges: loadedRanges,
        totalLines: totalLines,
      );
    }

    final forwardStart = anchorRange.endLine + 1;
    if (forwardStart < totalLines) {
      return forwardStart;
    }

    if (anchorRange.startLine > 0) {
      final backwardStart = anchorRange.startLine - chunkLines;
      return backwardStart < 0 ? 0 : backwardStart;
    }

    return nextWarmContentStartForTesting(
      loadedRanges: loadedRanges,
      totalLines: totalLines,
    );
  }

  @visibleForTesting
  static ({bool shouldIgnore, bool shouldDispatchImmediately})
      classifyRawPositionsDuringInitialPageShapeVisibleSyncForTesting({
    required bool awaitingInitialPageShapeVisibleSync,
    required bool showPageShapeView,
    required List<int> currentVisibleIndices,
    required int? selectedIndex,
    required List<int> nextVisibleIndices,
  }) =>
          _classifyRawPositionsDuringInitialPageShapeVisibleSync(
            awaitingInitialPageShapeVisibleSync:
                awaitingInitialPageShapeVisibleSync,
            showPageShapeView: showPageShapeView,
            currentVisibleIndices: currentVisibleIndices,
            selectedIndex: selectedIndex,
            nextVisibleIndices: nextVisibleIndices,
          );

  static ({bool shouldIgnore, bool shouldDispatchImmediately})
      _classifyRawPositionsDuringInitialPageShapeVisibleSync({
    required bool awaitingInitialPageShapeVisibleSync,
    required bool showPageShapeView,
    required List<int> currentVisibleIndices,
    required int? selectedIndex,
    required List<int> nextVisibleIndices,
  }) {
    if (!awaitingInitialPageShapeVisibleSync ||
        !showPageShapeView ||
        nextVisibleIndices.isEmpty) {
      return (
        shouldIgnore: false,
        shouldDispatchImmediately: false,
      );
    }

    final isAligned = isInitialPageShapeVisibleSyncAlignedForTesting(
      currentVisibleIndices: currentVisibleIndices,
      selectedIndex: selectedIndex,
      nextVisibleIndices: nextVisibleIndices,
    );
    final expectedIndex = expectedInitialPageShapeVisibleIndexForTesting(
      visibleIndices: currentVisibleIndices,
      selectedIndex: selectedIndex,
    );
    final shouldIgnore = !isAligned &&
        _looksLikeStaleInitialStartReport(
          expectedIndex: expectedIndex,
          nextVisibleIndices: nextVisibleIndices,
        );
    return (
      shouldIgnore: shouldIgnore,
      shouldDispatchImmediately: !shouldIgnore,
    );
  }

  void _setAwaitingInitialPageShapeVisibleSync(bool value) {
    _awaitingInitialPageShapeVisibleSync = value;
  }

  @visibleForTesting
  static List<Link> mergeLinksForTesting(
          List<Link> existing, List<Link> incoming) =>
      mergeLinksByIdentity(existing, incoming);

  @visibleForTesting
  static List<String> buildPreviewLinesForTesting(
          String previewContent, int previewStartLine) =>
      buildPreviewLines(previewContent, previewStartLine);

  Future<void> _onLoadContent(
    LoadContent event,
    Emitter<TextBookState> emit,
  ) async {
    TextBook book;
    String searchText;
    String highlightText = '';
    int? permanentHighlightLine;
    Map<String, Map<String, bool>> searchOptions = {};
    Map<int, List<String>> alternativeWords = {};
    Map<String, String> spacingValues = {};
    SearchMode searchMode = SearchMode.exact;
    int searchDistance = 0;
    bool showLeftPane;
    List<String> commentators;
    late final List<int> visibleIndices;

    bool initialShowPageShapeView = false;
    int? pinpointHighlightIndex;
    String? pinpointHighlightText;

    List<String> existingAvailableCommentators = const [];
    List<CommentatorGroup> existingCommentatorGroups = const [];
    bool? preservedRemoveNikud;
    bool? preservedPinLeftPane;

    if (state is TextBookLoaded && event.preserveState) {
      final currentState = state as TextBookLoaded;
      book = currentState.book;
      searchText = currentState.searchText;
      highlightText = currentState.highlightText;
      permanentHighlightLine = currentState.permanentHighlightLine;
      searchOptions = currentState.searchOptions;
      alternativeWords = currentState.alternativeWords;
      spacingValues = currentState.spacingValues;
      searchMode = currentState.searchMode;
      searchDistance = currentState.searchDistance;
      showLeftPane = currentState.showLeftPane;
      commentators = currentState.activeCommentators;
      visibleIndices = currentState.visibleIndices;
      initialShowPageShapeView = currentState.showPageShapeView;
      existingAvailableCommentators = currentState.availableCommentators;
      existingCommentatorGroups = currentState.commentatorGroups;
      preservedRemoveNikud = currentState.removeNikud;
      preservedPinLeftPane = currentState.pinLeftPane;
      pinpointHighlightIndex = currentState.pinpointHighlightIndex;
      pinpointHighlightText = currentState.pinpointHighlightText;
    } else if (state is TextBookInitial) {
      // איפוס דגלי ה-inline-notes כשמתחילים טעינה של ספר חדש דרך ה-BLoC.
      // הדגלים האלה תלויים בספר ספציפי ולא צריכים לדלוף בין ספרים, גם
      // אם בעתיד מישהו ישתמש שוב באותו instance של BLoC לספר אחר.
      resetInlineNotesStateForNewBook();

      final initial = state as TextBookInitial;
      book = initial.book;
      searchText = initial.searchText;
      highlightText = initial.highlightText;
      permanentHighlightLine = initial.permanentHighlightLine;
      searchOptions = initial.searchOptions;
      alternativeWords = initial.alternativeWords;
      spacingValues = initial.spacingValues;
      searchMode = initial.searchMode;
      searchDistance = initial.searchDistance;
      showLeftPane = initial.showLeftPane;
      commentators = initial.commentators;
      visibleIndices = [initial.index < 0 ? 0 : initial.index];
      initialShowPageShapeView = initial.showPageShapeView;
      pinpointHighlightIndex = initial.pinpointHighlightIndex;
      pinpointHighlightText = initial.pinpointHighlightText;

      emit(TextBookLoading(
          book, initial.index, initial.showLeftPane, initial.commentators));
    } else if (!event.preserveState) {
      if (state is TextBookLoaded) {
        emit(state);
      }
      return;
    } else {
      return;
    }

    try {
      final tocFuture = repository.getTableOfContents(book);

      List<String>? contentLines;
      List<bool>? loadedLineFlags;
      if (state is TextBookLoaded && event.preserveState) {
        contentLines = (state as TextBookLoaded).content;
        loadedLineFlags = _loadedContentFlags;
      } else {
        final initialRange = await repository.getBookContentRange(
          book,
          startLine: visibleIndices.first - _initialContentLookBehindLines,
          endLine: visibleIndices.first + _initialContentLookAheadLines,
        );

        if (initialRange != null) {
          contentLines = _contentWithAppliedRange(initialRange);
          loadedLineFlags = _loadedContentFlagsWithAppliedRange(initialRange);
          _setLoadedContentFlags(book, loadedLineFlags);
          _markLoadedContentRange(
            book,
            initialRange.startLine,
            initialRange.endLine,
            totalLines: initialRange.totalLines,
          );
        } else {
          final preview = await _quickPreviewLoader(
            book.title,
            visibleIndices.first,
            categoryId: book.categoryId,
            fileType: book.fileType,
            preferUserBooks: book.isUserBook,
          );

          if (preview != null && preview.isNotEmpty) {
            final previewStartLine =
                (visibleIndices.first - 10).clamp(0, visibleIndices.first);
            contentLines = buildPreviewLines(preview, previewStartLine);
            loadedLineFlags = _buildPreviewLoadedLineFlags(
              preview,
              previewStartLine,
            );
            _setLoadedContentFlags(book, loadedLineFlags);
            _markLoadedContentRange(
              book,
              previewStartLine,
              contentLines.isEmpty ? previewStartLine : contentLines.length - 1,
            );
            _loadFullBookInBackground(book);
          }
        }
      }

      if (contentLines == null) {
        final content = await repository.getBookContent(book);
        contentLines = await splitContentLines(content);
        loadedLineFlags = List<bool>.filled(contentLines.length, true);
        _setLoadedContentFlags(book, loadedLineFlags);
        _markLoadedContentRange(
          book,
          0,
          contentLines.isEmpty ? 0 : contentLines.length - 1,
          totalLines: contentLines.length,
        );
      }

      loadedLineFlags ??= _loadedContentFlags;

      final tableOfContents = await tocFuture;

      String? currentTitle;
      if (visibleIndices.isNotEmpty) {
        try {
          currentTitle = await refFromIndex(
              visibleIndices.first, Future.value(tableOfContents));
        } catch (_) {
          currentTitle = null;
        }
      }

      final defaultRemoveNikud =
          Settings.getValue<bool>('key-default-nikud') ?? false;
      final removeNikudFromTanach =
          Settings.getValue<bool>('key-remove-nikud-tanach') ?? false;
      final isTanach = await FileSystemData.instance.isTanachBook(
        book.title,
        categoryId: book.categoryId,
        fileType: book.fileType,
      );
      final supportsContinuousReading =
          await FileSystemData.instance.supportsContinuousReadingMode(
        book.title,
        categoryId: book.categoryId,
        fileType: book.fileType,
      );
      final removeNikud = shouldRemoveNikudForBook(
        defaultRemoveNikud: defaultRemoveNikud,
        removeNikudFromTanach: removeNikudFromTanach,
        isTanach: isTanach,
      );

      // מצב הרצף שומר את הערך הנוכחי רק כש-preserveContinuousReadingMode=true.
      // הלוגיקה הזו מנופית ל-`resolvePreservedContinuousReadingMode` כדי
      // שתוכל להיבדק טהורה: _resetPerBookSettings סומך על default=false,
      // וה-listener על שינוי גופן/ניקוד מעביר preserveFlag=true כדי לא
      // לכבות מצב רצף שהמשתמש בחר.
      final effectiveContinuousReading = resolvePreservedContinuousReadingMode(
        supportsContinuous: supportsContinuousReading,
        preserveFlag: event.preserveContinuousReadingMode,
        currentState: state,
      );
      final readingSegments = buildReadingSegments(
        contentLines,
        continuous: effectiveContinuousReading,
        loadedLineFlags: loadedLineFlags,
      );

      const List<Link> emptyLinks = [];
      const List<Link> emptyVisibleLinks = [];

      if (_positionListenerCallback != null) {
        positionsListener.itemPositions
            .removeListener(_positionListenerCallback!);
      }

      _positionListenerCallback = () {
        final rawPositions = positionsListener.itemPositions.value.toList()
          ..sort((a, b) => a.index.compareTo(b.index));
        final currentState = state;
        if (currentState is! TextBookLoaded) {
          return;
        }

        final visibleIndicesNow = _resolveVisibleSourceIndices(
          currentState,
          rawPositions,
        );
        if (visibleIndicesNow.isEmpty) {
          return;
        }

        if (!_hasMeaningfulVisibleIndicesChange(
          currentState.visibleIndices,
          visibleIndicesNow,
        )) {
          return;
        }

        final initialSyncClassification =
            _classifyRawPositionsDuringInitialPageShapeVisibleSync(
          awaitingInitialPageShapeVisibleSync:
              _awaitingInitialPageShapeVisibleSync,
          showPageShapeView: currentState.showPageShapeView,
          currentVisibleIndices: currentState.visibleIndices,
          selectedIndex: currentState.selectedIndex,
          nextVisibleIndices: visibleIndicesNow,
        );
        if (initialSyncClassification.shouldIgnore) {
          return;
        }
        if (initialSyncClassification.shouldDispatchImmediately) {
          _debounceTimer?.cancel();
          add(UpdateVisibleIndecies(visibleIndicesNow));
          return;
        }

        add(UpdateVisibleIndecies(visibleIndicesNow));
        _debounceTimer?.cancel();
        _debounceTimer = Timer(_visibleIndicesDebounceDuration, () {
          if (isClosed) {
            return;
          }

          final debouncedRawPositions = positionsListener.itemPositions.value
              .toList()
            ..sort((a, b) => a.index.compareTo(b.index));
          final latestState = state;
          if (latestState is TextBookLoaded) {
            final visibleIndicesNow = _resolveVisibleSourceIndices(
              latestState,
              debouncedRawPositions,
            );
            if (visibleIndicesNow.isNotEmpty &&
                _hasMeaningfulVisibleIndicesChange(
                  latestState.visibleIndices,
                  visibleIndicesNow,
                )) {
              add(UpdateVisibleIndecies(visibleIndicesNow));
            }
          }
        });
      };

      positionsListener.itemPositions.addListener(_positionListenerCallback!);

      _setAwaitingInitialPageShapeVisibleSync(initialShowPageShapeView);

      TextBookLoaded loadedState = TextBookLoaded(
        book: book,
        content: contentLines,
        contentVersion: contentLines.isEmpty ? 0 : 1,
        links: emptyLinks,
        linksByLine: const {},
        availableCommentators: existingAvailableCommentators,
        tableOfContents: tableOfContents,
        fontSize: _pendingFontSize ?? event.fontSize,
        showLeftPane: event.forceCloseLeftPane
            ? false
            : resolveInitialReadingLeftPaneVisibility(
                explicitOpen: showLeftPane,
                hasSearchText: searchText.isNotEmpty,
              ),
        showSplitView: event.showSplitView,
        showPageShapeView: initialShowPageShapeView,
        activeCommentators: commentators,
        commentatorGroups: existingCommentatorGroups,
        removeNikud: (event.preserveRemoveNikud && preservedRemoveNikud != null)
            ? preservedRemoveNikud
            : removeNikud,
        isTanach: isTanach,
        supportsContinuousReadingMode: supportsContinuousReading,
        continuousReadingMode: effectiveContinuousReading,
        readingSegments: readingSegments,
        linksLoading: false,
        visibleIndices: visibleIndices,
        pinLeftPane: preservedPinLeftPane ??
            (Settings.getValue<bool>('key-pin-sidebar') ?? false),
        searchText: searchText,
        searchOptions: searchOptions,
        alternativeWords: alternativeWords,
        spacingValues: spacingValues,
        searchMode: searchMode,
        searchDistance: searchDistance,
        scrollController: scrollController,
        positionsListener: positionsListener,
        scrollOffsetController: scrollOffsetController,
        currentTitle: currentTitle,
        visibleLinks: emptyVisibleLinks,
        selectedTextForNote: state is TextBookLoaded
            ? (state as TextBookLoaded).selectedTextForNote
            : null,
        selectedTextStart: state is TextBookLoaded
            ? (state as TextBookLoaded).selectedTextStart
            : null,
        selectedTextEnd: state is TextBookLoaded
            ? (state as TextBookLoaded).selectedTextEnd
            : null,
        highlightText: _pendingPinpoint?.text ?? highlightText,
        permanentHighlightLine: _pendingPinpoint != null
            ? _pendingPinpoint!.sectionIndex
            : permanentHighlightLine,
        pinpointHighlightIndex: pinpointHighlightIndex,
        pinpointHighlightText: pinpointHighlightText,
      );

      // סריקה סינכרונית של ה-content שכבר בזיכרון לזיהוי הערות inline
      // לפני ה-emit הראשון. מסלולי preview/range מקבלים הרחבה הדרגתית
      // דרך ApplyBookContentRange / ApplyFullBookContent (ראה
      // _withInlineNotesCommentator).
      if (notes.hasInlineNotes(contentLines)) {
        loadedState = _attachInlineNotesCommentator(loadedState);
      }

      emit(loadedState);

      _pendingPinpoint = null;
      _pendingFontSize = null;

      _resetLoadedLinksWindow(book);

      _loadContentRangeInBackground(book, visibleIndices);
      _warmContentCacheInBackground(book);

      _loadLinksInBackground(book, visibleIndices);

      if (event.loadCommentators) {
        _loadCommentatorsInBackground(book);
      }

      _enrichHeCategoriesInBackground(book);
    } catch (e, st) {
      debugPrint('Error loading textbook: $e\n$st');
      if (state is TextBookInitial) {
        final initial = state as TextBookInitial;
        emit(TextBookError(e.toString(), initial.book, initial.index,
            initial.showLeftPane, initial.commentators));
      } else if (state is TextBookLoading) {
        final loading = state as TextBookLoading;
        emit(TextBookError(e.toString(), loading.book, loading.index,
            loading.showLeftPane, loading.commentators));
      } else if (state is TextBookLoaded && event.preserveState) {
        final current = state as TextBookLoaded;
        emit(TextBookError(
            e.toString(),
            current.book,
            current.visibleIndices.isNotEmpty
                ? current.visibleIndices.first
                : 0,
            current.showLeftPane,
            current.activeCommentators));
      }
    }
  }

  void _onUpdateFontSize(
    UpdateFontSize event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      emit(currentState.copyWith(
        fontSize: event.fontSize,
        selectedIndex: currentState.selectedIndex,
      ));
    } else {
      // האירוע הגיע לפני סיום הטעינה (מרוץ בעליית התוכנה). שומרים כ-pending
      // כדי שלא יאבד, ומחילים ב-_onLoadContent בבניית מצב ה-Loaded.
      _pendingFontSize = event.fontSize;
    }
  }

  void _onToggleLeftPane(
    ToggleLeftPane event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      if (currentState.showLeftPane == event.show) {
        return;
      }
      final updatedState = currentState.copyWith(
        showLeftPane: event.show,
        selectedIndex: currentState.selectedIndex,
        visibleLinks: event.show
            ? computeVisibleLinks(
                links: currentState.links,
                visibleIndices: currentState.visibleIndices,
                selectedIndices: currentState.selectedIndices,
                linksByLine: currentState.linksByLine,
              )
            : currentState.visibleLinks,
      );
      emit(updatedState);

      if (event.show && _shouldLoadLinksForState(updatedState)) {
        _loadLinksInBackground(
          updatedState.book,
          updatedState.visibleIndices,
        );
      }
    }
  }

  void _onToggleSplitView(
    ToggleSplitView event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      Settings.setValue<bool>('key-splited-view', event.show);
      final updatedState = currentState.copyWith(
        showSplitView: event.show,
        selectedIndex: currentState.selectedIndex,
      );
      emit(updatedState);
      _loadLinksInBackground(
        updatedState.book,
        updatedState.visibleIndices,
        force: true,
      );
    }
  }

  void _onToggleTzuratHadafView(
    ToggleTzuratHadafView event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;

      emit(currentState.copyWith(
        showTzuratHadafView: event.show,
        showPageShapeView: false,
        selectedIndex: currentState.selectedIndex,
        showLeftPane: event.show ? false : currentState.showLeftPane,
      ));
    }
  }

  void _onTogglePageShapeView(
    TogglePageShapeView event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;

      PageShapeSettingsManager.saveViewModePreference(
        currentState.book.title,
        event.show,
      );

      _setAwaitingInitialPageShapeVisibleSync(event.show);
      final updatedState = currentState.copyWith(
        showPageShapeView: event.show,
        showTzuratHadafView: false,
        selectedIndex: currentState.selectedIndex,
        showLeftPane: event.show ? false : currentState.showLeftPane,
      );
      emit(updatedState);
      _loadLinksInBackground(
        updatedState.book,
        updatedState.visibleIndices,
        force: true,
      );

      if (!event.show && currentState.selectedIndex != null) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (scrollController.isAttached) {
            scrollController.scrollTo(
              index: currentState.selectedIndex!,
              duration: const Duration(milliseconds: 300),
            );
          }
        });
      }
    }
  }

  void _onUpdateCommentators(
    UpdateCommentators event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;

      // בחירה אוטומטית (ברירת מחדל) ושחזור שמור גוברים על בחירה אוטומטית
      // קודמת (כגון אוטו-בחירת 'הערות'), כל עוד המשתמש לא בחר ידנית בסשן זה.
      if (!event.isUserAction) {
        if (_userTouchedCommentators) return;
        // שחזור בחירה שמורה הוא בחירת המשתמש האמיתית — נועלים אותה מפני
        // אוטו-בחירה מאוחרת (כולל הוספת 'הערות' אוטומטית), גם כשהיא ריקה.
        if (event.isRestore) _userTouchedCommentators = true;
      } else {
        _userTouchedCommentators = true;
        // שמירה פר-ספר של בחירת המשתמש (כולל בחירה ריקה) — תמיד, כדי שתיטען
        // בכל פתיחה. ספרים אישיים אינם נשמרים פר-ספר.
        if (!currentState.book.isUserBook) {
          unawaited(_saveActiveCommentatorsPerBook(
            currentState.book,
            event.commentators,
          ));
        }
      }

      final updatedState = currentState.copyWith(
        activeCommentators: event.commentators,
        selectedIndex: currentState.selectedIndex,
      );
      emit(updatedState);
      if (_shouldLoadLinksForState(updatedState)) {
        final targetIndices = _targetIndicesForCommentaryRefresh(updatedState);
        _loadLinksInBackground(
          updatedState.book,
          targetIndices,
          targetBookTitlesOverride:
              _normalizeCommentaryTargets(updatedState.activeCommentators),
        );
      }
    }
  }

  void _onToggleNikud(
    ToggleNikud event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      emit(currentState.copyWith(
        removeNikud: event.remove,
        selectedIndex: currentState.selectedIndex,
      ));
    }
  }

  void _onTogglePunctuation(
    TogglePunctuation event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      emit(currentState.copyWith(
        removePunctuation: event.remove,
        selectedIndex: currentState.selectedIndex,
      ));
    }
  }

  void _onToggleContinuousReadingMode(
    ToggleContinuousReadingMode event,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) {
      return;
    }

    final currentState = state as TextBookLoaded;
    // אם הספר לא תומך — מתעלמים. הכפתור ב-UI ממילא לא מוצג, אבל זה מגן
    // גם מקריאות תוכנתיות (קיצורי מקלדת, plugins).
    final effectiveEnabled = computeEffectiveContinuousReading(
      requestedEnabled: event.enabled,
      stateSupportsContinuous: currentState.supportsContinuousReadingMode,
    );
    if (currentState.continuousReadingMode == effectiveEnabled) {
      return;
    }

    emit(currentState.copyWith(
      continuousReadingMode: effectiveEnabled,
      readingSegments: buildReadingSegments(
        currentState.content,
        continuous: effectiveEnabled,
        loadedLineFlags: _loadedContentFlags,
      ),
    ));
  }

  Future<void> _onUpdateVisibleIndecies(
    UpdateVisibleIndecies event,
    Emitter<TextBookState> emit,
  ) async {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;

      if (_awaitingInitialPageShapeVisibleSync &&
          currentState.showPageShapeView) {
        final initialSyncClassification =
            _classifyRawPositionsDuringInitialPageShapeVisibleSync(
          awaitingInitialPageShapeVisibleSync:
              _awaitingInitialPageShapeVisibleSync,
          showPageShapeView: currentState.showPageShapeView,
          currentVisibleIndices: currentState.visibleIndices,
          selectedIndex: currentState.selectedIndex,
          nextVisibleIndices: event.visibleIndecies,
        );
        if (initialSyncClassification.shouldIgnore) {
          return;
        }

        _setAwaitingInitialPageShapeVisibleSync(false);
      }

      if (_listsEqual(currentState.visibleIndices, event.visibleIndecies)) {
        return;
      }

      String? newTitle = currentState.currentTitle;

      if (event.visibleIndecies.isNotEmpty &&
          (currentState.visibleIndices.isEmpty ||
              currentState.visibleIndices.first !=
                  event.visibleIndecies.first)) {
        newTitle = await refFromIndex(event.visibleIndecies.first,
            Future.value(currentState.tableOfContents));
      }

      int? index = currentState.selectedIndex;
      if (index != null &&
          !event.visibleIndecies.contains(index) &&
          event.visibleIndecies.isNotEmpty) {
        // כמה שורות הקטע הנבחר יצא מעבר לקצה הקרוב של החלון הנראה. נמדד מול
        // הקטע עצמו (עוגן יציב) ולא מהשורה הקודמת, אחרת בגלילה רציפה כל אירוע
        // זז מעט והבחירה לא משתחררת. מול הקצה הקרוב כדי שיהיה סימטרי בשני הכיוונים.
        final distance = index < event.visibleIndecies.first
            ? event.visibleIndecies.first - index
            : index - event.visibleIndecies.last;
        if (distance > 3) {
          index = null;
        }
      }

      // גלילה רחוקה אִפסה את העוגן הראשי — מנקים גם את ריבוי-הבחירה.
      final newIndices =
          index == null ? const <int>{} : currentState.selectedIndices;

      final List<Link> visibleLinks;
      if (currentState.showLeftPane || index != null) {
        visibleLinks = computeVisibleLinks(
          links: currentState.links,
          visibleIndices: event.visibleIndecies,
          selectedIndices: newIndices,
          linksByLine: currentState.linksByLine,
        );
      } else {
        visibleLinks = currentState.visibleLinks;
      }

      emit(currentState.copyWith(
        visibleIndices: event.visibleIndecies,
        currentTitle: newTitle,
        selectedIndex: index,
        clearSelectedIndex: index == null && currentState.selectedIndex != null,
        selectedIndices: newIndices,
        clearSelectedIndices: newIndices.isEmpty,
        visibleLinks: visibleLinks,
      ));

      _loadContentRangeInBackground(currentState.book, event.visibleIndecies);

      if (_shouldLoadLinksForVisibleIndicesChange(currentState)) {
        _loadLinksInBackground(
          currentState.book,
          event.visibleIndecies,
        );
      }
    }
  }

  void _resetLoadedLinksWindow(TextBook book) {
    _loadedLinksBookTitle = book.title;
    _loadedLinksStart = null;
    _loadedLinksEnd = null;
    _loadedLinksTargetBookTitlesSignature = null;
    _activeLinksTargetBookTitlesSignature = null;
    _isLoadingLinks = false;
    _pendingLinksReload = false;
  }

  ({int start, int end}) _calculateLinksWindow(List<int> visibleIndices) {
    if (visibleIndices.isEmpty) {
      return (start: 0, end: _linkLookAheadLines);
    }

    final minVisible = visibleIndices.reduce((a, b) => a < b ? a : b);
    final maxVisible = visibleIndices.reduce((a, b) => a > b ? a : b);

    return (
      start: (minVisible - _linkLookBehindLines).clamp(0, minVisible),
      end: maxVisible + _linkLookAheadLines,
    );
  }

  bool _isLinksWindowSufficient(
    String bookTitle,
    int start,
    int end,
    String targetBookTitlesSignature,
  ) {
    return _loadedLinksBookTitle == bookTitle &&
        _loadedLinksStart != null &&
        _loadedLinksEnd != null &&
        _loadedLinksTargetBookTitlesSignature == targetBookTitlesSignature &&
        start >= (_loadedLinksStart! - _linksReloadThresholdLines) &&
        end <= (_loadedLinksEnd! + _linksReloadThresholdLines);
  }

  List<String>? _normalizeTargetBookTitles(Iterable<String>? targetBookTitles) {
    if (targetBookTitles == null) {
      return null;
    }

    return targetBookTitles
        .map((title) => title.trim())
        .where((title) => title.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  String _targetBookTitlesSignature(Iterable<String>? targetBookTitles) {
    final normalized = _normalizeTargetBookTitles(targetBookTitles);
    if (normalized == null) {
      return _allTargetBookTitlesSignature;
    }

    return normalized.join('||');
  }

  String _serializePageShapeConfiguration(Map<String, String?>? configuration) {
    if (configuration == null) {
      return '__default__';
    }

    return [
      'left=${configuration['left'] ?? 'null'}',
      'right=${configuration['right'] ?? 'null'}',
      'bottom=${configuration['bottom'] ?? 'null'}',
      'bottomRight=${configuration['bottomRight'] ?? 'null'}',
    ].join('|');
  }

  String _serializeColumnVisibility(Map<String, bool> columnVisibility) {
    return [
      'left=${columnVisibility['left'] ?? true}',
      'right=${columnVisibility['right'] ?? true}',
      'bottom=${columnVisibility['bottom'] ?? true}',
      'bottomRight=${columnVisibility['bottomRight'] ?? true}',
    ].join('|');
  }

  Future<List<String>?> _resolvePageShapeTargetBookTitlesForLinks(
    TextBookLoaded state,
    String? workspaceId,
  ) async {
    final candidateCommentators = {
      ...state.availableCommentators,
      ...state.activeCommentators,
    }.where((commentator) => commentator.trim().isNotEmpty).toList()
      ..sort();

    if (candidateCommentators.isEmpty) {
      return null;
    }

    final storedConfiguration = PageShapeSettingsManager.loadConfiguration(
      state.book.title,
      heCategories: state.book.heCategories,
    );
    final columnVisibility = PageShapeSettingsManager.getColumnVisibility(
      state.book.title,
      workspaceId: workspaceId,
    );
    final cacheKey = [
      state.book.title,
      state.book.heCategories ?? '',
      workspaceId ?? '',
      candidateCommentators.join('||'),
      _serializePageShapeConfiguration(storedConfiguration),
      _serializeColumnVisibility(columnVisibility),
    ].join('::');

    if (_cachedPageShapeTargetBookTitlesKey == cacheKey) {
      return _cachedPageShapeTargetBookTitles;
    }

    final configuration = storedConfiguration ??
        await DefaultCommentators.getDefaults(
          state.book,
          availableCommentators: candidateCommentators,
        );

    final selectedCommentators = resolvePageShapeDisplayedCommentators(
      leftSelection: configuration['left'],
      rightSelection: configuration['right'],
      bottomSelection: configuration['bottom'],
      bottomRightSelection: configuration['bottomRight'],
      availableCommentators: candidateCommentators,
      columnVisibility: columnVisibility,
    );

    _cachedPageShapeTargetBookTitlesKey = cacheKey;
    _cachedPageShapeTargetBookTitles = selectedCommentators;
    return selectedCommentators;
  }

  List<String> _normalizeCommentaryTargets(Iterable<String> titles) {
    return titles
        .map((title) => title.trim())
        .where((title) => title.isNotEmpty && title != kNotesCommentatorTitle)
        .toSet()
        .toList()
      ..sort();
  }

  Future<List<String>?> _resolveTargetBookTitlesForLinks(
    TextBookLoaded state,
    String? workspaceId,
  ) async {
    if (state.showPageShapeView) {
      final pageShapeTargets =
          await _resolvePageShapeTargetBookTitlesForLinks(state, workspaceId);
      return pageShapeTargets ?? const <String>[];
    }

    if (state.showSplitView || state.activeCommentators.isNotEmpty) {
      return _normalizeCommentaryTargets(state.activeCommentators);
    }

    return const <String>[];
  }

  bool _isCommentariesBelowMode(TextBookLoaded state) {
    return !state.showSplitView && !state.showPageShapeView;
  }

  bool _shouldLoadLinksForState(TextBookLoaded state) {
    return _isCommentariesBelowMode(state) ||
        state.showSplitView ||
        state.showPageShapeView ||
        state.activeCommentators.isNotEmpty;
  }

  bool _shouldLoadLinksForVisibleIndicesChange(TextBookLoaded state) {
    return _isCommentariesBelowMode(state) ||
        state.showSplitView ||
        state.showPageShapeView ||
        state.showLeftPane;
  }

  List<int> _targetIndicesForCommentaryRefresh(TextBookLoaded state) {
    if (state.showSplitView || state.showPageShapeView) {
      return state.visibleIndices;
    }

    return state.selectedIndex != null
        ? [state.selectedIndex!]
        : state.visibleIndices;
  }

  bool _listsEqual(List<int> list1, List<int> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }

  bool _hasMeaningfulVisibleIndicesChange(
    List<int> currentIndices,
    List<int> nextIndices,
  ) {
    if (_listsEqual(currentIndices, nextIndices)) {
      return false;
    }

    if (currentIndices.isEmpty || nextIndices.isEmpty) {
      return true;
    }

    return currentIndices.first != nextIndices.first ||
        currentIndices.last != nextIndices.last;
  }

  List<int> _resolveVisibleSourceIndices(
    TextBookLoaded state,
    Iterable<ItemPosition> visibleItemPositions,
  ) {
    final allItemPositions = visibleItemPositions.toList();
    if (allItemPositions.isEmpty) {
      return const [];
    }

    // גלילה ע"י ניווט משתמשת ב-alignment: 0.05, כך שהקטע הקודם נשאר גלוי
    // ב-5% העליונים של ה-viewport. בלי סינון, visibleIndices.first נופל על
    // השורה האחרונה של הקטע הקודם, וזיהוי הכותרת (currentTitle ו-
    // closestTocEntryIndex) מצביע על הסעיף הקודם במקום על זה שאליו ניווטו.
    final itemPositions = _filterBarelyVisiblePositions(allItemPositions);

    if (!state.continuousReadingMode) {
      return itemPositions.map((position) => position.index).toSet().toList()
        ..sort();
    }

    // במצב רציף: ה-positions הם segmentIndex. ממירים בחזרה לשורות מקור
    // כדי ש-visibleIndices ב-state יישאר תמיד ברמת שורות.
    return sourceLineIndicesForSegmentViewports(
      state.readingSegments,
      itemPositions.map(
        (position) => ReadingSegmentViewport(
          segmentIndex: position.index,
          leadingEdge: position.itemLeadingEdge,
          trailingEdge: position.itemTrailingEdge,
        ),
      ),
    );
  }

  /// סינון item positions שאינם חלק מ"המיקום הנוכחי" בספר:
  /// - קטע שנוכחותו מתחת לקו העוגן זניחה הוא שייר של הסעיף הקודם שאליו הניווט
  ///   מיישר (isRemnantAbovePositionAnchor) - גם אם הוא שורה קצרה הגלויה
  ///   במלואה סביב קו העוגן.
  /// - קטע שגלוי פחות מ-15% מה-extent שלו (שייר בתחתית ה-viewport).
  ///
  /// אם הסינון מותיר רשימה ריקה (לא צפוי בפועל), חוזרים לרשימה המקורית.
  @visibleForTesting
  static List<ItemPosition> filterBarelyVisiblePositionsForTesting(
    List<ItemPosition> positions,
  ) =>
      _filterBarelyVisiblePositions(positions);

  static List<ItemPosition> _filterBarelyVisiblePositions(
    List<ItemPosition> positions,
  ) {
    if (positions.length <= 1) return positions;
    final filtered = positions.where((p) {
      final extent = p.itemTrailingEdge - p.itemLeadingEdge;
      if (extent <= 0) return false;
      if (isRemnantAbovePositionAnchor(p.itemLeadingEdge, p.itemTrailingEdge)) {
        return false;
      }
      final visibleTop = p.itemLeadingEdge.clamp(0.0, 1.0);
      final visibleBottom = p.itemTrailingEdge.clamp(0.0, 1.0);
      final visiblePortion = visibleBottom - visibleTop;
      if (visiblePortion <= 0) return false;
      return visiblePortion / extent >= 0.15;
    }).toList();
    return filtered.isEmpty ? positions : filtered;
  }

  void _onUpdateSelectedIndex(
    UpdateSelectedIndex event,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) return;
    final currentState = state as TextBookLoaded;

    final Set<int> newIndices;
    final int? newPrimary;
    if (event.index == null) {
      newIndices = const {};
      newPrimary = null;
    } else if (event.additive) {
      final updated = Set<int>.from(currentState.selectedIndices);
      if (updated.remove(event.index)) {
        newPrimary = updated.isEmpty ? null : updated.last;
      } else {
        updated.add(event.index!);
        newPrimary = event.index;
      }
      newIndices = updated;
    } else {
      newIndices = {event.index!};
      newPrimary = event.index;
    }

    final visibleLinks = computeVisibleLinks(
      links: currentState.links,
      visibleIndices: currentState.visibleIndices,
      selectedIndices: newIndices,
      linksByLine: currentState.linksByLine,
    );
    emit(currentState.copyWith(
      selectedIndex: newPrimary,
      clearSelectedIndex: newPrimary == null,
      selectedIndices: newIndices,
      clearSelectedIndices: newIndices.isEmpty,
      visibleLinks: visibleLinks,
    ));
    if (_isCommentariesBelowMode(currentState) &&
        !currentState.showPageShapeView &&
        event.index != null &&
        newIndices.contains(event.index)) {
      _loadLinksInBackground(currentState.book, [event.index!]);
    }
  }

  void _onHighlightLine(
    HighlightLine event,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) return;
    final currentState = state as TextBookLoaded;
    emit(currentState.copyWith(highlightedLine: event.lineIndex));

    _highlightTimer?.cancel();

    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (!isClosed) {
        add(ClearHighlightedLine(event.lineIndex));
      }
    });
  }

  void _onClearHighlightedLine(
    ClearHighlightedLine event,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) return;
    final currentState = state as TextBookLoaded;
    if (currentState.highlightedLine == null) return;
    if (event.lineIndex != null &&
        currentState.highlightedLine != event.lineIndex) {
      return;
    }
    emit(currentState.copyWith(clearHighlight: true));
  }

  /// מחיל highlight מ-deep link על לוגיקת קיימת.
  /// אם ה-bloc עדיין ב-Initial/Loading, שומר כ-pending ומחיל כשמגיע ל-Loaded.
  void _onApplyMarkHighlight(
    ApplyMarkHighlight event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      emit(currentState.copyWith(
        highlightText: event.highlightText,
        permanentHighlightLine: event.permanentHighlightLine,
        clearPermanentHighlight: event.permanentHighlightLine == null,
        searchText: '',
      ));
      // גלילה לסעיף המבוקש כדי שההדגשה תהיה גלויה
      final scrollIndex = event.scrollToIndex ?? event.permanentHighlightLine;
      if (scrollIndex != null && scrollController.isAttached) {
        scrollController.scrollTo(
          index: scrollIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } else {
      // Initial או Loading — שומרים כ-pending, יוחל ב-_onLoadContent
      _pendingPinpoint = (
        text: event.highlightText,
        sectionIndex: event.permanentHighlightLine,
      );
    }
  }

  void _onTogglePinLeftPane(
    TogglePinLeftPane event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      emit(currentState.copyWith(
        pinLeftPane: event.pin,
        selectedIndex: currentState.selectedIndex,
      ));
    }
  }

  void _onUpdateSearchText(
    UpdateSearchText event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      // חיפוש ידני חדש מנקה הדגשה ממוקדת קודמת מ‑deep link, אחרת ההדגשה
      // הממוקדת הייתה ממשיכה לחסום את החיפוש החדש בשאר הסעיפים.
      emit(currentState.copyWith(
        searchText: event.text,
        searchOptions: event.searchOptions,
        alternativeWords: event.alternativeWords,
        spacingValues: event.spacingValues,
        searchMode: event.searchMode,
        searchDistance: event.searchDistance,
        selectedIndex: currentState.selectedIndex,
        clearPinpointHighlight: true,
      ));
    }
  }

  void _onApplyFullBookContent(
    ApplyFullBookContent event,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) {
      return;
    }

    final currentState = state as TextBookLoaded;
    if (currentState.book.title != event.bookTitle) {
      return;
    }

    final nextLoadedFlags = List<bool>.filled(event.content.length, true);
    final hasLoadedFlagsChanged =
        _loadedContentFlags.length != event.content.length ||
            _loadedContentFlags.any((loaded) => !loaded);
    if (listEquals(currentState.content, event.content) &&
        !hasLoadedFlagsChanged) {
      return;
    }

    _setLoadedContentFlags(currentState.book, nextLoadedFlags);

    final updatedState = _withInlineNotesCommentator(currentState.copyWith(
      content: event.content,
      contentVersion: currentState.contentVersion + 1,
      readingSegments: buildReadingSegments(
        event.content,
        continuous: currentState.continuousReadingMode,
        loadedLineFlags: nextLoadedFlags,
      ),
    ));
    // אחרי שסרקנו את התוכן המלא, אין יותר טעם בסריקה נוספת על הרחבות
    // טווח עתידיות — או שכבר הוסף 'הערות' ל-availableCommentators (ואז
    // early-return שומר עלינו), או שאין הערות בכלל בספר.
    _inlineNotesFullScanDone = true;
    emit(updatedState);
    _markLoadedContentRange(
      currentState.book,
      0,
      event.content.isEmpty ? 0 : event.content.length - 1,
      totalLines: event.content.length,
    );
  }

  void _onApplyBookContentRange(
    ApplyBookContentRange event,
    Emitter<TextBookState> emit,
  ) {
    _applyContentRanges(
      event.bookTitle,
      [
        (
          startLine: event.startLine,
          totalLines: event.totalLines,
          lines: event.lines,
        ),
      ],
      emit,
    );
  }

  void _onApplyBookContentRanges(
    ApplyBookContentRanges event,
    Emitter<TextBookState> emit,
  ) {
    _applyContentRanges(event.bookTitle, event.ranges, emit);
  }

  void _applyContentRanges(
    String bookTitle,
    List<BookContentRangeChunk> ranges,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) {
      return;
    }

    final currentState = state as TextBookLoaded;
    final applicable = ranges.where((range) => range.lines.isNotEmpty).toList();
    if (currentState.book.title != bookTitle || applicable.isEmpty) {
      return;
    }

    final nextContent = List<String>.of(currentState.content);
    final nextLoadedFlags = List<bool>.of(_loadedContentFlags);
    var hasContentChanged = false;
    var hasLoadedFlagsChanged = false;

    for (final range in applicable) {
      final targetLength = range.startLine + range.lines.length;
      if (nextContent.length < targetLength) {
        hasContentChanged = true;
        nextContent.addAll(
          List<String>.filled(targetLength - nextContent.length, ''),
        );
      }
      if (nextLoadedFlags.length < targetLength) {
        hasLoadedFlagsChanged = true;
        nextLoadedFlags.addAll(
          List<bool>.filled(targetLength - nextLoadedFlags.length, false),
        );
      }

      for (var offset = 0; offset < range.lines.length; offset++) {
        final targetIndex = range.startLine + offset;
        if (targetIndex >= 0 && targetIndex < nextContent.length) {
          if (nextContent[targetIndex] != range.lines[offset]) {
            hasContentChanged = true;
          }
          if (!nextLoadedFlags[targetIndex]) {
            hasLoadedFlagsChanged = true;
          }
          nextContent[targetIndex] = range.lines[offset];
          nextLoadedFlags[targetIndex] = true;
        }
      }
    }

    void markAllRanges() {
      for (final range in applicable) {
        _markLoadedContentRange(
          currentState.book,
          range.startLine,
          range.startLine + range.lines.length - 1,
          totalLines: range.totalLines,
        );
      }
    }

    if (!hasContentChanged && !hasLoadedFlagsChanged) {
      markAllRanges();
      return;
    }

    _setLoadedContentFlags(currentState.book, nextLoadedFlags);
    markAllRanges();

    // מיזוג טווחים סמוכים/חופפים: עדכון הסגמנטים מעתיק את הרשימה המלאה לכל
    // טווח, ואצוות חימום הן כמעט תמיד רצף אחד — כך נשארת העתקה אחת לאצווה.
    var mergedRanges = const <({int startLine, int endLine})>[];
    for (final range in applicable) {
      mergedRanges = mergeLoadedContentRangesForTesting(
        mergedRanges,
        startLine: range.startLine,
        endLine: range.startLine + range.lines.length - 1,
      );
    }

    var readingSegments = currentState.readingSegments;
    for (final range in mergedRanges) {
      readingSegments = updateReadingSegmentsForRange(
        readingSegments,
        nextContent,
        loadedLineFlags: nextLoadedFlags,
        continuous: currentState.continuousReadingMode,
        startLine: range.startLine,
        endLine: range.endLine,
      );
    }

    emit(_withInlineNotesCommentator(
      currentState.copyWith(
        content: nextContent,
        contentVersion: currentState.contentVersion + 1,
        readingSegments: readingSegments,
      ),
      // אופטימיזציה: לסרוק רק את השורות החדשות במקום את כל ה-content
      // המצטבר (מונע עבודה ריבועית במהלך warming הדרגתי של ספר ארוך).
      scanOnly: [for (final range in applicable) ...range.lines],
    ));
  }

  /// בודק אם בתוכן העדכני יש הערות inline. אם כן ועדיין לא הוסף המפרש
  /// הוירטואלי 'הערות' ל-availableCommentators - מוסיף אותו ובוחר אותו
  /// אוטומטית רק אם המשתמש עדיין לא נגע ידנית בבחירת המפרשים.
  ///
  /// נדרש כי בעת `_loadCommentatorsInBackground` ה-content עלול להיות
  /// חלון חלקי בלבד, וההערות יכולות להיות מחוץ לחלון. ההרחבה הבאה של
  /// התוכן (ApplyBookContentRange / ApplyFullBookContent) חייבת לרענן.
  ///
  /// [scanOnly] - אם ניתן, סורקים רק את השורות האלו (אופטימיזציה: על
  /// הרחבת טווח אנחנו מקבלים רק את השורות החדשות, אין סיבה לסרוק שוב
  /// את כל ה-content).
  TextBookLoaded _withInlineNotesCommentator(
    TextBookLoaded state, {
    List<String>? scanOnly,
  }) {
    if (state.availableCommentators.contains(kNotesCommentatorTitle)) {
      return state;
    }
    if (_inlineNotesFullScanDone) {
      return state;
    }
    final linesToScan = scanOnly ?? state.content;
    if (!notes.hasInlineNotes(linesToScan)) {
      return state;
    }
    return _attachInlineNotesCommentator(state);
  }

  /// מצרף את מפרש ההערות הוירטואלי ל-availableCommentators ולקבוצת "שאר
  /// מפרשים", ובוחר אותו אוטומטית אם המשתמש עוד לא נגע ידנית בבחירה.
  /// משותף לסריקה הסינכרונית ב-_onLoadContent ולסריקות ההדרגתיות
  /// ב-_withInlineNotesCommentator (מסלולי preview/range).
  TextBookLoaded _attachInlineNotesCommentator(TextBookLoaded state) {
    if (state.availableCommentators.contains(kNotesCommentatorTitle)) {
      return state;
    }
    final updatedAvailable = [
      ...state.availableCommentators,
      kNotesCommentatorTitle,
    ];
    final updatedGroups = _addNotesToOtherCommentatorsGroup(
      state.commentatorGroups,
    );
    final shouldAutoSelect =
        state.activeCommentators.isEmpty && !_userTouchedCommentators;
    return state.copyWith(
      availableCommentators: updatedAvailable,
      commentatorGroups: updatedGroups,
      activeCommentators: shouldAutoSelect
          ? const [kNotesCommentatorTitle]
          : state.activeCommentators,
    );
  }

  List<CommentatorGroup> _addNotesToOtherCommentatorsGroup(
    List<CommentatorGroup> groups,
  ) {
    const otherGroupTitle = 'שאר מפרשים';
    var inserted = false;
    final next = groups.map((group) {
      if (group.title == otherGroupTitle &&
          !group.commentators.contains(kNotesCommentatorTitle)) {
        inserted = true;
        return group.copyWith(
          commentators: [...group.commentators, kNotesCommentatorTitle],
        );
      }
      return group;
    }).toList();
    if (!inserted) {
      next.add(const CommentatorGroup(
        title: otherGroupTitle,
        commentators: [kNotesCommentatorTitle],
      ));
    }
    return next;
  }

  void _onCreateNoteFromToolbar(
    CreateNoteFromToolbar event,
    Emitter<TextBookState> emit,
  ) {
    // הלוגיקה האמיתית תהיה בכפתור בשורת הכלים
  }

  void _onUpdateSelectedTextForNote(
    UpdateSelectedTextForNote event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;
      emit(currentState.copyWith(
        selectedTextForNote: event.text,
        selectedTextStart: event.start,
        selectedTextEnd: event.end,
      ));
    }
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    _highlightTimer?.cancel();

    if (_positionListenerCallback != null) {
      positionsListener.itemPositions
          .removeListener(_positionListenerCallback!);
    }

    return super.close();
  }

  // אורך הרשימה חייב להיות אורך הספר המלא (totalLines) ולא רק עד endLine,
  // אחרת itemCount של הרשימה/פס-הגלילה קטן מדי בפתיחה באמצע הספר, ופס
  // הגלילה מתחיל קרוב לתחתית ו"גולש" למקומו רק כשהתוכן המלא נטען ברקע.
  // השורות שמעבר לחלון הטעון נשארות placeholders ריקים — בדיוק כמו השורות
  // שלפני תחילת החלון.
  int _fullContentLength(BookContentRange range) =>
      range.totalLines > range.endLine + 1
          ? range.totalLines
          : range.endLine + 1;

  List<String> _contentWithAppliedRange(BookContentRange range) {
    final content = List<String>.filled(_fullContentLength(range), '');
    for (var offset = 0; offset < range.lines.length; offset++) {
      final targetIndex = range.startLine + offset;
      if (targetIndex >= 0 && targetIndex < content.length) {
        content[targetIndex] = range.lines[offset];
      }
    }
    return content;
  }

  List<bool> _loadedContentFlagsWithAppliedRange(BookContentRange range) {
    final loadedFlags = List<bool>.filled(_fullContentLength(range), false);
    for (var offset = 0; offset < range.lines.length; offset++) {
      final targetIndex = range.startLine + offset;
      if (targetIndex >= 0 && targetIndex < loadedFlags.length) {
        loadedFlags[targetIndex] = true;
      }
    }
    return loadedFlags;
  }

  List<bool> _buildPreviewLoadedLineFlags(
    String previewContent,
    int previewStartLine,
  ) {
    final previewLineCount =
        previewContent.isEmpty ? 0 : previewContent.split('\n').length;
    final loadedFlags =
        List<bool>.filled(previewStartLine + previewLineCount, false);
    for (var index = previewStartLine; index < loadedFlags.length; index++) {
      loadedFlags[index] = true;
    }
    return loadedFlags;
  }

  void _ensureLoadedContentTrackingBook(TextBook book) {
    if (_loadedContentBookTitle == book.title) {
      return;
    }

    _loadedContentBookTitle = book.title;
    _loadedContentRanges = const [];
    _loadedContentFlags = const [];
    _loadedContentTotalLines = null;
  }

  void _setLoadedContentFlags(TextBook book, List<bool> loadedFlags) {
    _ensureLoadedContentTrackingBook(book);
    _loadedContentFlags = List<bool>.unmodifiable(loadedFlags);
  }

  void _markLoadedContentRange(
    TextBook book,
    int startLine,
    int endLine, {
    int? totalLines,
  }) {
    _ensureLoadedContentTrackingBook(book);

    _loadedContentTotalLines = totalLines ?? _loadedContentTotalLines;
    _loadedContentRanges = mergeLoadedContentRangesForTesting(
      _loadedContentRanges,
      startLine: startLine,
      endLine: endLine,
    );
  }

  bool _isContentWindowSufficient(TextBook book, int startLine, int endLine) {
    if (_loadedContentBookTitle != book.title || _loadedContentRanges.isEmpty) {
      return false;
    }

    return isContentWindowSufficientForTesting(
      loadedRanges: _loadedContentRanges,
      startLine: startLine,
      endLine: endLine,
      reloadThresholdLines: _contentReloadThresholdLines,
    );
  }

  ({int startLine, int endLine}) _calculateContentWindow(
    List<int> visibleIndices,
  ) {
    final firstVisible = visibleIndices.isEmpty ? 0 : visibleIndices.first;
    final lastVisible =
        visibleIndices.isEmpty ? firstVisible : visibleIndices.last;

    return (
      startLine: firstVisible - _contentLookBehindLines,
      endLine: lastVisible + _contentLookAheadLines,
    );
  }

  Future<void> _loadContentRangeInBackground(
    TextBook book,
    List<int> visibleIndices, {
    bool force = false,
  }) async {
    final window = _calculateContentWindow(visibleIndices);
    if (!force &&
        _isContentWindowSufficient(book, window.startLine, window.endLine)) {
      return;
    }

    if (_isLoadingContentRange) {
      _pendingContentRangeReload = true;
      return;
    }

    _isLoadingContentRange = true;
    try {
      final range = await repository.getBookContentRange(
        book,
        startLine: window.startLine,
        endLine: window.endLine,
      );
      if (range != null && !isClosed) {
        add(ApplyBookContentRange(
          bookTitle: book.title,
          startLine: range.startLine,
          totalLines: range.totalLines,
          lines: range.lines,
        ));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '⚠️ TextBookBloc::loadContentRange failed for ${book.title}: $e');
      }
    } finally {
      _isLoadingContentRange = false;
      if (_pendingContentRangeReload && !isClosed) {
        _pendingContentRangeReload = false;
        final currentState = state;
        if (currentState is TextBookLoaded &&
            currentState.book.title == book.title) {
          _loadContentRangeInBackground(
            book,
            currentState.visibleIndices,
            force: true,
          );
        }
      }
    }
  }

  Future<void> _warmContentCacheInBackground(TextBook book) async {
    if (_isWarmingContentCache) {
      return;
    }

    _isWarmingContentCache = true;

    // chunks שנטענו וטרם נשלחו ל-state. שליחה פר-chunk גררה rebuild מלא של
    // ה-viewport עשרות פעמים לספר — לכן צוברים ושולחים באצוות.
    final pendingChunks = <BookContentRangeChunk>[];
    // הטווחים שהחימום כבר טען (כולל אלו שבהמתנה) — _loadedContentRanges
    // מתעדכן רק כשה-chunk מוחל בפועל, ולכן לבדו היה גורר טעינה חוזרת.
    var warmedRanges = <({int startLine, int endLine})>[];

    void flushPendingChunks() {
      if (pendingChunks.isEmpty || isClosed) {
        return;
      }
      add(ApplyBookContentRanges(
        bookTitle: book.title,
        ranges: List.of(pendingChunks),
      ));
      pendingChunks.clear();
    }

    try {
      List<int> lastWarmVisible = const [];
      while (!isClosed) {
        final currentState = state;
        if (currentState is! TextBookLoaded ||
            currentState.book.title != book.title) {
          return;
        }

        // השהיית warming בזמן גלילה: אם החלון הנראה זז המשתמש גולל (warming
        // לא מזיזו), ונותנים קדימות לטעינה האינטראקטיבית במקום להתחרות עליה.
        if (!_listsEqual(lastWarmVisible, currentState.visibleIndices)) {
          lastWarmVisible = currentState.visibleIndices;
          await Future<void>.delayed(_visibleIndicesDebounceDuration);
          continue;
        }

        final totalLines = _loadedContentTotalLines;
        if (totalLines == null) {
          return;
        }

        var effectiveRanges = _loadedContentRanges;
        for (final range in warmedRanges) {
          effectiveRanges = mergeLoadedContentRangesForTesting(
            effectiveRanges,
            startLine: range.startLine,
            endLine: range.endLine,
          );
        }
        final nextStart = nextWarmContentStartNearViewportForTesting(
          loadedRanges: effectiveRanges,
          totalLines: totalLines,
          visibleIndices: currentState.visibleIndices,
          chunkLines: _contentWarmChunkLines,
        );
        if (nextStart == null || nextStart >= totalLines) {
          return;
        }

        final range = await repository.getBookContentRange(
          book,
          startLine: nextStart,
          endLine: nextStart + _contentWarmChunkLines - 1,
        );
        if (range == null || range.lines.isEmpty) {
          return;
        }

        if (isClosed) {
          return;
        }

        pendingChunks.add((
          startLine: range.startLine,
          totalLines: range.totalLines,
          lines: range.lines,
        ));
        warmedRanges = mergeLoadedContentRangesForTesting(
          warmedRanges,
          startLine: range.startLine,
          endLine: range.startLine + range.lines.length - 1,
        );
        if (pendingChunks.length >= _warmFlushChunkCount) {
          flushPendingChunks();
        }

        await SchedulerBinding.instance.endOfFrame;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '⚠️ TextBookBloc::warmContentCache failed for ${book.title}: $e');
      }
    } finally {
      flushPendingChunks();
      _isWarmingContentCache = false;
    }
  }

  Future<void> _loadFullBookInBackground(TextBook book) async {
    try {
      final fullContent = await repository.getBookContent(book);

      if (fullContent.isEmpty) {
        return;
      }

      if (isClosed || state is! TextBookLoaded) {
        return;
      }

      final currentState = state as TextBookLoaded;
      if (currentState.book.title != book.title) {
        return;
      }

      final lines = await splitContentLines(fullContent);
      if (isClosed) {
        return;
      }
      add(ApplyFullBookContent(
        bookTitle: book.title,
        content: lines,
      ));
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '⚠️ TextBookBloc::loadFullBook failed for ${book.title}: $e');
      }
    }
  }

  Future<void> _loadLinksInBackground(
    TextBook book,
    List<int> visibleIndices, {
    bool force = false,
    Iterable<String>? targetBookTitlesOverride,
    bool forceLoadAll = false,
    String? workspaceId,
  }) async {
    final runtimeStateBeforeWindowCheck = state;
    if (!force &&
        runtimeStateBeforeWindowCheck is TextBookLoaded &&
        !_shouldLoadLinksForState(runtimeStateBeforeWindowCheck)) {
      return;
    }

    final window = _calculateLinksWindow(visibleIndices);

    if (_isLoadingLinks) {
      _pendingLinksReload = true;
      // שמור את ה-indices המבוקשים אם זו טעינה מאולצת (forceLoadAll)
      if (forceLoadAll) {
        _pendingForceLoadIndices = List<int>.of(visibleIndices);
        _pendingForceLoadAll = true;
      }
      return;
    }

    List<String>? targetBookTitles;
    var targetBookTitlesSignature = _allTargetBookTitlesSignature;
    if (forceLoadAll) {
      // null = ללא פילטר — מחזיר את כל הקישורים כולל מפרשים
      targetBookTitles = null;
      targetBookTitlesSignature = _allTargetBookTitlesSignature;
    } else if (targetBookTitlesOverride != null) {
      targetBookTitles = _normalizeTargetBookTitles(targetBookTitlesOverride);
      targetBookTitlesSignature = _targetBookTitlesSignature(targetBookTitles);
    } else {
      final runtimeState = state;
      if (runtimeState is TextBookLoaded) {
        targetBookTitles = await _resolveTargetBookTitlesForLinks(
          runtimeState,
          workspaceId,
        );
        targetBookTitlesSignature =
            _targetBookTitlesSignature(targetBookTitles);
      }
    }

    if (isClosed) return;

    if (!force &&
        _isLinksWindowSufficient(
          book.title,
          window.start,
          window.end,
          targetBookTitlesSignature,
        )) {
      _pendingLinksReload = false;
      return;
    }

    _isLoadingLinks = true;
    _pendingLinksReload = false;
    if (isClosed) {
      _isLoadingLinks = false;
      return;
    }
    add(const SetLinksLoading(true));

    try {
      final links = await repository.getBookLinksInRange(
        book,
        startIndex: window.start,
        endIndex: window.end,
        targetBookTitles: targetBookTitles,
      );

      if (isClosed || state is! TextBookLoaded) {
        _isLoadingLinks = false;
        return;
      }

      final currentState = state as TextBookLoaded;
      if (currentState.book.title != book.title) {
        _isLoadingLinks = false;
        return;
      }

      _loadedLinksBookTitle = book.title;
      _loadedLinksStart = window.start;
      _loadedLinksEnd = window.end;
      _loadedLinksTargetBookTitlesSignature = targetBookTitlesSignature;
      _isLoadingLinks = false;
      final replaceExistingLinks = currentState.links.isNotEmpty &&
          _activeLinksTargetBookTitlesSignature != targetBookTitlesSignature;

      if (isClosed) {
        _isLoadingLinks = false;
        return;
      }
      add(UpdateLinks(
        links,
        replaceExisting: replaceExistingLinks,
        targetBookTitlesSignature: targetBookTitlesSignature,
      ));

      if (!isClosed && state is TextBookLoaded) {
        final latestState = state as TextBookLoaded;
        final latestWindow = _calculateLinksWindow(latestState.visibleIndices);
        final windowOutdated = !_isLinksWindowSufficient(
          latestState.book.title,
          latestWindow.start,
          latestWindow.end,
          targetBookTitlesSignature,
        );
        if (_pendingLinksReload || windowOutdated) {
          // אם ממתין טעינה מאולצת (LoadAllLinksForIndices), השתמש ב-indices שנשמרו
          final pendingIndices = _pendingForceLoadIndices;
          final pendingForce = _pendingForceLoadAll;
          _pendingForceLoadIndices = null;
          _pendingForceLoadAll = false;
          if (pendingForce && pendingIndices != null) {
            _loadLinksInBackground(
              latestState.book,
              pendingIndices,
              force: true,
              forceLoadAll: true,
            );
          } else if (!forceLoadAll) {
            // במצב forceLoadAll (כרטסיית מפרשים עצמאית), אין לבצע תיקון windowOutdated
            // כי visibleIndices תקוע ב-startIndex ותיקון כזה יחליף את ה-commentary
            // links שנטענו זה עתה ב-links ריקים (targetBookTitles=[]).
            _loadLinksInBackground(
              latestState.book,
              latestState.visibleIndices,
              workspaceId: workspaceId,
            );
          }
        }
      }
    } catch (e) {
      _isLoadingLinks = false;
      if (!isClosed) {
        add(const SetLinksLoading(false));
      }
      if (kDebugMode) {
        debugPrint(
          '⚠️ TextBookBloc::loadLinks failed for ${book.title} '
          '(window ${window.start}-${window.end}): $e',
        );
      }
    }
  }

  Future<void> _onUpdateLinks(
    UpdateLinks event,
    Emitter<TextBookState> emit,
  ) async {
    if (state is! TextBookLoaded) return;
    final stateBeforeAwait = state as TextBookLoaded;
    final processedLinks = await processLinksForState(
      existingLinks: stateBeforeAwait.links,
      incomingLinks: event.links.cast<Link>(),
      replaceExisting: event.replaceExisting,
      visibleIndices: stateBeforeAwait.visibleIndices,
      selectedIndices: stateBeforeAwait.selectedIndices,
    );

    if (state is! TextBookLoaded) return;
    final currentState = state as TextBookLoaded;
    if (currentState.book.title != stateBeforeAwait.book.title) return;

    emit(currentState.copyWith(
      links: processedLinks.links,
      linksByLine: processedLinks.linksByLine,
      visibleLinks: processedLinks.visibleLinks,
      linksLoading: false,
    ));
    _activeLinksTargetBookTitlesSignature =
        event.targetBookTitlesSignature ?? _allTargetBookTitlesSignature;

    // טעינת דורות הספרים מראש למטמון, כדי שתפריט ההקשר יוכל למיין
    // את הקישורים לפי סדר הדורות באופן סינכרוני.
    _preloadLinkEras(processedLinks.links);
  }

  /// טוען מראש את דורות ספרי היעד של הקישורים הרגילים (לא מפרשים)
  void _preloadLinkEras(List<Link> links) {
    final titles = <String>{
      for (final link in links)
        if (!LinkTypes.isDependentTextLink(link.connectionType))
          utils.getTitleFromPath(link.path2),
    };
    if (titles.isEmpty) return;
    CommentaryService.preloadEras(titles);
  }

  void _onSetLinksLoading(
    SetLinksLoading event,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) return;
    final currentState = state as TextBookLoaded;
    if (currentState.linksLoading == event.isLoading) return;
    emit(currentState.copyWith(linksLoading: event.isLoading));
  }

  void _onUpdateAvailableCommentators(
    UpdateAvailableCommentators event,
    Emitter<TextBookState> emit,
  ) {
    if (state is TextBookLoaded) {
      final currentState = state as TextBookLoaded;

      final updatedState = _withInlineNotesCommentator(currentState.copyWith(
        availableCommentators: event.availableCommentators,
        commentatorGroups: event.commentatorGroups.cast<CommentatorGroup>(),
        rareCommentators: event.rareCommentators,
      ));
      emit(updatedState);

      if (updatedState.showPageShapeView) {
        _loadLinksInBackground(updatedState.book, updatedState.visibleIndices);
      }
    }
  }

  void _onRefreshLinksForCurrentWindow(
    RefreshLinksForCurrentWindow event,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) {
      return;
    }

    final currentState = state as TextBookLoaded;
    _loadLinksInBackground(
      currentState.book,
      currentState.visibleIndices,
      force: true,
      workspaceId: event.workspaceId,
    );
  }

  void _onLoadAllLinksForIndices(
    LoadAllLinksForIndices event,
    Emitter<TextBookState> emit,
  ) {
    if (state is! TextBookLoaded) return;
    final currentState = state as TextBookLoaded;
    _loadLinksInBackground(
      currentState.book,
      event.indices,
      force: true,
      forceLoadAll: true,
    );
  }

  Future<void> _loadCommentatorsInBackground(TextBook book) async {
    try {
      final commentatorsData = await repository.getCommentatorsWithRarity(book);
      final availableCommentators = commentatorsData.all;
      final rareCommentators = commentatorsData.rare;
      final baseCommentators =
          await DefaultCommentators.getBaseCommentators(book);

      final eras = await utils.splitByEra(availableCommentators);
      final groups = buildCommentatorGroups(
        eras,
        availableCommentators,
        baseCommentators: baseCommentators,
      );

      if (isClosed || state is! TextBookLoaded) {
        return;
      }

      final loaded = state as TextBookLoaded;
      if (loaded.book.title != book.title) {
        return;
      }

      // הזיהוי של 'הערות' כמפרש וירטואלי נעשה בנפרד דרך
      // _withInlineNotesCommentator שמופעל בכל עדכון של ה-content.
      if (isClosed) return;
      add(UpdateAvailableCommentators(
          availableCommentators, groups, rareCommentators));

      // בחירה שמורה פר-ספר גוברת על ברירת המחדל: אם המשתמש בחר בעבר (כולל
      // בחירה ריקה) — משחזרים אותה; אחרת בוחרים את מפרשי ברירת המחדל.
      final saved =
          book.isUserBook ? null : await TextBookPerBookSettings.load(book);
      if (isClosed) return;

      if (saved?.activeCommentators != null) {
        if (isClosed) return;
        add(UpdateCommentators(saved!.activeCommentators!,
            isUserAction: false, isRestore: true));
        return;
      }

      // בחירה אוטומטית של מפרשי ברירת המחדל בפתיחה — מוחלת רק אם המשתמש
      // עוד לא בחר ידנית ואין מפרשים פעילים (נאכף ב-_onUpdateCommentators).
      final initialSelection = await DefaultCommentators.getInitialSelection(
        book,
        availableCommentators: availableCommentators,
        baseCommentators: baseCommentators,
      );
      if (initialSelection.isNotEmpty && !isClosed) {
        add(UpdateCommentators(initialSelection, isUserAction: false));
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load commentators in background: $e');
    }
  }

  /// שומר את בחירת המפרשים פר-ספר (תמיד, ללא תלות ב-enablePerBookSettings),
  /// כדי שתיטען בכל פתיחה. בחירה ריקה נשמרת אף היא (המשתמש ביטל את הכל).
  Future<void> _saveActiveCommentatorsPerBook(
    Book book,
    List<String> commentators,
  ) async {
    try {
      await TextBookPerBookSettings.mutate(
        book,
        (existing) => (existing ?? TextBookPerBookSettings())
            .copyWith(activeCommentators: List<String>.from(commentators)),
      );
    } catch (e) {
      debugPrint('⚠️ Failed to save active commentators per book: $e');
    }
  }

  Future<void> _enrichHeCategoriesInBackground(TextBook book) async {
    final enriched = await enrichHeCategories(book);
    if (isClosed) return;

    final heCategoriesChanged = enriched.heCategories != null &&
        enriched.heCategories != book.heCategories;
    final authorChanged =
        enriched.author != null && enriched.author != book.author;
    final heEraChanged = enriched.heEra != null && enriched.heEra != book.heEra;

    // ה-enrichment רץ ברקע; אם ה-bloc נסגר בינתיים אסור להוסיף event.
    if (isClosed) return;

    if ((book.id == null && enriched.resolvedId != null) ||
        heCategoriesChanged ||
        authorChanged ||
        heEraChanged) {
      if (isClosed) return;
      add(UpdateResolvedBookId(
        bookTitle: book.title,
        resolvedId: enriched.resolvedId,
        heCategories: heCategoriesChanged ? enriched.heCategories : null,
        author: authorChanged ? enriched.author : null,
        heEra: heEraChanged ? enriched.heEra : null,
      ));
    }
  }

  void _onUpdateResolvedBookId(
    UpdateResolvedBookId event,
    Emitter<TextBookState> emit,
  ) {
    final current = state;
    if (current is! TextBookLoaded) return;
    if (current.book.title != event.bookTitle) return;

    final needsIdUpdate = current.book.id == null && event.resolvedId != null;
    final needsCategoriesUpdate = event.heCategories != null &&
        event.heCategories != current.book.heCategories;
    final needsAuthorUpdate =
        event.author != null && event.author != current.book.author;
    final needsHeEraUpdate =
        event.heEra != null && event.heEra != current.book.heEra;

    if (!needsIdUpdate &&
        !needsCategoriesUpdate &&
        !needsAuthorUpdate &&
        !needsHeEraUpdate) {
      return;
    }

    final updatedBook = current.book.copyWith(
      id: needsIdUpdate ? event.resolvedId : null,
      heCategories: needsCategoriesUpdate ? event.heCategories : null,
      author: needsAuthorUpdate ? event.author : null,
      heEra: needsHeEraUpdate ? event.heEra : null,
    );
    emit(current.copyWith(book: updatedBook));
  }
}
