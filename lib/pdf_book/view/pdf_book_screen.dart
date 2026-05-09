import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart' as otz_links;
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart' as pdf_events;
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_page_number_display.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/navigation/open_book.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'pdf_search_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'pdf_outlines_screen.dart';
import 'package:otzaria/widgets/dialogs/password_dialog.dart';
import 'pdf_thumbnails_screen.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/utils/file/page_converter.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';
import 'package:flutter/gestures.dart';
import 'package:otzaria/widgets/layout/dual_adaptive_reader_pane.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'pdf_zoom_bar.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/pdf_book/view/pdf_scrollbar.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/printing/printing_helpers.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';

final GlobalKey pdfBookNavigationTourTargetKey = GlobalKey(
  debugLabel: 'pdf_book_navigation_tour_target',
);
final GlobalKey pdfBookBookmarkTourTargetKey = GlobalKey(
  debugLabel: 'pdf_book_bookmark_tour_target',
);
final GlobalKey pdfBookSearchTourTargetKey = GlobalKey(
  debugLabel: 'pdf_book_search_tour_target',
);
final GlobalKey pdfBookPrintTourTargetKey = GlobalKey(
  debugLabel: 'pdf_book_print_tour_target',
);
final GlobalKey pdfBookOverflowTourTargetKey = GlobalKey(
  debugLabel: 'pdf_book_overflow_tour_target',
);
final GlobalKey pdfBookOverflowBookmarkTourTargetKey = GlobalKey(
  debugLabel: 'pdf_book_overflow_bookmark_tour_target',
);
final GlobalKey pdfBookOverflowSearchTourTargetKey = GlobalKey(
  debugLabel: 'pdf_book_overflow_search_tour_target',
);
final GlobalKey pdfBookOverflowPrintTourTargetKey = GlobalKey(
  debugLabel: 'pdf_book_overflow_print_tour_target',
);

class PdfBookScreen extends StatefulWidget {
  final PdfBookTab tab;
  final bool isInCombinedView;
  final bool enableTourTargets;

  const PdfBookScreen({
    super.key,
    required this.tab,
    this.isInCombinedView = false,
    this.enableTourTargets = false,
  });

  @override
  State<PdfBookScreen> createState() => _PdfBookScreenState();
}

@visibleForTesting
bool shouldShowOpenPdfCommentaryPaneEntry({
  required bool hasRelevantCommentators,
  required bool isPaneOpen,
}) {
  return hasRelevantCommentators && !isPaneOpen;
}

@visibleForTesting
bool shouldShowOpenPdfLinksPaneEntry({
  required bool hasRelevantLinks,
  required bool isPaneOpen,
}) {
  return hasRelevantLinks && !isPaneOpen;
}

class _PdfBookScreenState extends State<PdfBookScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  static const int _defaultPdfLineRange = 50;
  static const double _bookViewGap = 3.0;
  static const double _bookViewScale = 0.5;
  static const double _verticalScrollbarGutter = 16.0;
  static const double _horizontalScrollbarGutter = 10.0;
  static const double _scrollbarGutterGap = 4.0;
  static const Duration _pointerScrollFlushDelay = Duration(milliseconds: 12);
  static const double _maxPointerScrollBurstDelta = 160.0;
  static const String _connectionTypeCommentary = 'COMMENTARY';
  static const String _connectionTypeTargum = 'TARGUM';

  @override
  bool get wantKeepAlive => true;

  late final PdfViewerController pdfController;
  late final PdfBookBloc _bloc;
  late final bool _pdfFileExists;
  PdfTextSearcher? textSearcher;
  TabController? _leftPaneTabController;
  int _currentLeftPaneTabIndex = 0;
  final FocusNode _searchFieldFocusNode = FocusNode();
  final FocusNode _navigationFieldFocusNode = FocusNode();
  final FocusNode _pdfViewFocusNode = FocusNode();
  final GlobalKey _pdfViewportBoundaryKey = GlobalKey();
  late final StreamSubscription<SettingsState> _settingsSub;
  late final AnimationController _pageTurnController;

  // גלילה רציפה
  Timer? _scrollTimer;
  Timer? _pointerScrollFlushTimer;
  LogicalKeyboardKey? _currentScrollKey;
  int? _scrollAnchorPage;
  Matrix4? _panZoomBaseMatrix;
  double _pendingPointerScrollDx = 0.0;
  double _pendingPointerScrollDy = 0.0;
  int? _lockedSpreadStartPage;
  ui.Image? _pageTurnSnapshot;
  ui.Image? _pageTurnTargetSnapshot;
  _BookPageTurnTransition? _pageTurnTransition;
  bool _isPageTurnInProgress = false;
  bool _pdfViewerSuspended = false;
  bool _readerFocusAndHideQueued = false;
  bool _bookHasCommentaryLinks = false;
  // FIFO queue of page-turns that came in while another was already running.
  // Each click gets its own animation; rapid clicks accumulate and play in
  // order, instead of being collapsed into a single animation toward the
  // latest target.
  final List<_PendingBookPageTurn> _pendingPageTurns = [];
  // Tracks left/right arrow keys that have fired KeyRepeatEvent so we can
  // distinguish a held key (drain queue on release) from a short tap (let
  // its queued turn play out).
  final Set<LogicalKeyboardKey> _heldArrowKeys = {};

  // Pre-rendered spread cache: lets the page-turn animation start instantly
  // because the target spread snapshot is already in memory at click time.
  // Key = spread start page (1-indexed). Pages are rendered via pdfrx's
  // page.render() in the background and composited on-demand into a
  // viewport-sized ui.Image when a page-turn fires.
  final Map<int, _PdfSpreadCacheEntry> _spreadCache = {};
  final Set<int> _spreadRenderInProgress = {};
  final Map<int, PdfPageRenderCancellationToken> _spreadCancellationTokens = {};
  int? _lastPrerenderTriggeredSpread;

  // Tracks the most recent page-turn target we *initiated* (animation started
  // or queued). next/prev navigation reads this instead of
  // `controller.pageNumber` while a goToPage is in flight, so rapid clicks
  // advance from the last-known intent rather than the stale viewer state.
  // Cleared in `_onPdfViewerControllerUpdate` once the controller's spread
  // catches up.
  int? _lastInitiatedTargetPage;
  // Target of the page-turn currently being animated (NOT including queued
  // ones). Set when an animation starts, cleared after its goToPage settles.
  // When we drop the held-key queue, `_lastInitiatedTargetPage` snaps back
  // to this so the next click advances from where this animation will land.
  int? _inFlightAnimationTarget;

  // Local UI state that syncs with Bloc
  int _rightPaneInitialTabIndex = 0;

  // קבוצות מפרשים לסדר בתפריט
  List<CommentatorGroup> _commentatorGroups = [];

  // Named listeners for proper cleanup
  late final VoidCallback _leftPaneTabControllerListener;
  late final VoidCallback _showLeftPaneListener;

  Future<void> _runInitialSearchIfNeeded() async {
    final controller = widget.tab.searchController;
    final String query = controller.text.trim();
    if (query.isEmpty) return;

    // שיטה 1: הוספה והסרה מהירה
    controller.text = '$query '; // הוסף תו זמני

    // המתן רגע קצרצר כדי שהשינוי יתפוס
    await Future.delayed(const Duration(milliseconds: 50));

    controller.text = query; // החזר את הטקסט המקורי
    // הזז את הסמן לסוף הטקסט
    controller.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length));

    //ברוב המקרים, שינוי הטקסט עצמו יפעיל את ה-listener של הספרייה.
    // אם לא, ייתכן שעדיין צריך לקרוא לזה ידנית:
    textSearcher?.startTextSearch(query, goToFirstMatch: false);
  }

  void _ensureSearchTabIsActive() {
    _setLeftPaneVisibility(true);
    if (_leftPaneTabController != null && _leftPaneTabController!.index != 1) {
      _leftPaneTabController!.animateTo(1);
    }
    _searchFieldFocusNode.requestFocus();
  }

  void _setLeftPaneVisibility(bool show) {
    final current = _bloc.state;
    if (current is PdfBookLoaded && current.showLeftPane == show) {
      return;
    }
    _bloc.add(pdf_events.ToggleLeftPane(show));
  }

  void _scheduleReaderFocusAndHidePaneIfNeeded() {
    if (widget.tab.pinLeftPane.value ||
        (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
        _readerFocusAndHideQueued) {
      return;
    }

    _readerFocusAndHideQueued = true;
    Future.microtask(() {
      _readerFocusAndHideQueued = false;
      if (!mounted) {
        return;
      }

      _setLeftPaneVisibility(false);
      _pdfViewFocusNode.requestFocus();
    });
  }

  int? _lastProcessedSearchSessionId;

  void _onTextSearcherUpdated() {
    String currentSearchTerm = widget.tab.searchController.text;
    int? persistedIndexFromTab = widget.tab.pdfSearchCurrentMatchIndex;

    widget.tab.searchText = currentSearchTerm;
    widget.tab.pdfSearchMatches =
        textSearcher != null ? List.from(textSearcher!.matches) : null;
    widget.tab.pdfSearchCurrentMatchIndex = textSearcher?.currentIndex;

    if (mounted) {
      setState(() {});
    }

    if (textSearcher != null) {
      bool isNewSearchExecution =
          (_lastProcessedSearchSessionId != textSearcher!.searchSession);
      if (isNewSearchExecution) {
        _lastProcessedSearchSessionId = textSearcher!.searchSession;
      }

      if (isNewSearchExecution &&
          currentSearchTerm.isNotEmpty &&
          textSearcher!.matches.isNotEmpty &&
          persistedIndexFromTab != null &&
          persistedIndexFromTab >= 0 &&
          persistedIndexFromTab < textSearcher!.matches.length &&
          textSearcher!.currentIndex != persistedIndexFromTab) {
        textSearcher!.goToMatchOfIndex(persistedIndexFromTab);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _pageTurnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    if (widget.tab.pageNumber < 1) {
      widget.tab.pageNumber = 1;
    }
    _initialPageNumber = widget.tab.pageNumber;
    pdfController = PdfViewerController();
    widget.tab.pdfViewerController = pdfController;

    final settingsBloc = context.read<SettingsBloc>();
    final initialGlobalLayoutMode = settingsBloc.state.pdfBookViewByDefault
        ? PdfLayoutMode.bookView
        : PdfLayoutMode.regularView;
    final initialLayoutMode = settingsBloc.state.enablePerBookSettings
        ? (widget.tab.savedLayoutMode ?? initialGlobalLayoutMode)
        : initialGlobalLayoutMode;

    if (!settingsBloc.state.enablePerBookSettings) {
      widget.tab.savedLayoutMode = initialGlobalLayoutMode;
    }

    _bloc = PdfBookBloc(
      tab: widget.tab,
      initialState: PdfBookInitial(
        book: widget.tab.book,
        initialPageNumber: widget.tab.pageNumber,
        searchText: widget.tab.searchText,
        searchOptions: widget.tab.searchOptions,
        alternativeWords: widget.tab.alternativeWords,
        spacingValues: widget.tab.spacingValues,
        searchMode: widget.tab.searchMode,
        layoutMode: initialLayoutMode,
      ),
    );

    _loadInitialLayoutMode();

    // PDF is always a file on the file system — use book.path directly

    // הגדרת ערכים התחלתיים מ-Settings
    _settingsSub = settingsBloc.stream.listen((state) {
      _bloc.add(pdf_events.UpdateSidebarWidth(state.sidebarWidth));
      _bloc.add(pdf_events.UpdateRightPaneWidth(state.commentaryPaneWidth));

      if (!state.enablePerBookSettings) {
        final desiredLayoutMode = state.pdfBookViewByDefault
            ? PdfLayoutMode.bookView
            : PdfLayoutMode.regularView;
        final currentLayoutMode = switch (_bloc.state) {
          PdfBookInitial initial => initial.layoutMode,
          PdfBookLoaded loaded => loaded.layoutMode,
          _ => null,
        };

        if (currentLayoutMode != desiredLayoutMode) {
          _lockedSpreadStartPage = null;
          _bloc.add(pdf_events.SetLayoutMode(desiredLayoutMode));
        }
      }
    });

    pdfController.addListener(_onPdfViewerControllerUpdate);
    if (widget.tab.searchText.isNotEmpty) {
      _currentLeftPaneTabIndex = 1;
    } else {
      _currentLeftPaneTabIndex = 0;
    }

    _leftPaneTabController = TabController(
      length: 3, // חזרה ל-3: ניווט, חיפוש, דפים (ללא מפרשים)
      vsync: this,
      initialIndex: _currentLeftPaneTabIndex,
    );

    // הוספת listeners לשדות טקסט - ללא החזרה אוטומטית של פוקוס ל-PDF
    // כדי לאפשר לדיאלוגים וחלוניות אחרות לקבל פוקוס
    _searchFieldFocusNode.addListener(() {});
    _navigationFieldFocusNode.addListener(() {});

    // טעינת headings וlinks
    _loadPdfHeadingsAndLinks();

    // טעינת המפרשים הפעילים
    _loadActiveCommentators();

    // בדיקת קיום הקובץ — פעם אחת ב-initState, לפני הבנייה הראשונה
    _pdfFileExists = File(widget.tab.book.path).existsSync();

    // הגדרת Bloc לטיפול בקיום הקובץ ושאר מצבים
    _bloc.add(const pdf_events.LoadPdfDocument());

    // אם ה-PDF כבר טעון, קפוץ לעמוד הנכון
    if (widget.tab.pdfViewerController.isReady && widget.tab.pageNumber > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted && widget.tab.pdfViewerController.isReady) {
          await widget.tab.pdfViewerController
              .goToPage(pageNumber: widget.tab.pageNumber);
        }
      });
    }

    if (_currentLeftPaneTabIndex == 1) {
      _searchFieldFocusNode.requestFocus();
    } else {
      _navigationFieldFocusNode.requestFocus();
    }

    // הגדרת listeners עם שמות לצורך הסרה נכונה ב-dispose
    _leftPaneTabControllerListener = () {
      if (_currentLeftPaneTabIndex != _leftPaneTabController!.index) {
        setState(() {
          _currentLeftPaneTabIndex = _leftPaneTabController!.index;
        });
        if (_leftPaneTabController!.index == 1 &&
            widget.tab.showLeftPane.value) {
          _searchFieldFocusNode.requestFocus();
        } else if (_leftPaneTabController!.index == 0 &&
            widget.tab.showLeftPane.value) {
          _navigationFieldFocusNode.requestFocus();
        } else if (!widget.tab.showLeftPane.value) {
          // אם חלונית הצד סגורה, החזר focus ל-PDF
          _pdfViewFocusNode.requestFocus();
        }
      }
    };
    _leftPaneTabController!.addListener(_leftPaneTabControllerListener);

    _showLeftPaneListener = () {
      if (widget.tab.showLeftPane.value) {
        if (_leftPaneTabController!.index == 1) {
          _searchFieldFocusNode.requestFocus();
        } else if (_leftPaneTabController!.index == 0) {
          _navigationFieldFocusNode.requestFocus();
        }
      } else {
        // כשסוגרים את חלונית הצד, החזר focus ל-PDF
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _pdfViewFocusNode.requestFocus();
          }
        });
      }
    };
    widget.tab.showLeftPane.addListener(_showLeftPaneListener);
  }

  Future<void> _loadInitialLayoutMode() async {
    final enablePerBookSettings =
        Settings.getValue<bool>(SettingsRepository.keyEnablePerBookSettings) ??
            false;
    final pdfBookViewByDefault =
        Settings.getValue<bool>(SettingsRepository.keyPdfBookViewByDefault) ??
            false;

    PdfLayoutMode layoutMode = pdfBookViewByDefault
        ? PdfLayoutMode.bookView
        : PdfLayoutMode.regularView;

    if (enablePerBookSettings && widget.tab.savedLayoutMode == null) {
      final settings = await PdfBookPerBookSettings.load(widget.tab.book.title);
      if (settings?.layoutMode != null) {
        layoutMode = settings!.layoutMode!;
      }
    }

    if (mounted) {
      widget.tab.savedLayoutMode = layoutMode;
      _bloc.add(pdf_events.SetLayoutMode(layoutMode));
    }
  }

  ({int startLine, int endLine})? _getCurrentPdfLinesRange() {
    final currentLine = widget.tab.currentTextLineNumber;
    if (currentLine == null) {
      debugPrint(
          '🔍 [PDF-DEBUG] _getCurrentPdfLinesRange: currentTextLineNumber=null → returning null');
      return null;
    }

    final int startLine = currentLine;
    final int endLine =
        widget.tab.currentTextLineNumberEnd ?? startLine + _defaultPdfLineRange;

    return (startLine: startLine, endLine: endLine);
  }

  Future<({int start, int? end})> _resolveTextLineNumberForPage(
    int pageNumber, {
    String? resolvedTitle,
  }) async {
    debugPrint(
        '📖 [PDF-DEBUG] _resolveTextLineNumberForPage: page=$pageNumber resolvedTitle="$resolvedTitle"');
    final outline = widget.tab.outline.value ?? const <PdfOutlineNode>[];
    if (outline.isNotEmpty) {
      final textIndex =
          await pdfToTextPage(widget.tab.book, outline, pageNumber, context);
      if (textIndex != null) {
        if (!mounted) return (start: textIndex + 1, end: null);
        final nextIndex = await pdfToTextPage(
            widget.tab.book, outline, pageNumber + 1, context);
        debugPrint(
            '📖 [PDF-DEBUG] pdfToTextPage → raw=$textIndex → start=${textIndex + 1}, end=${nextIndex ?? "null (last page)"}');
        return (start: textIndex + 1, end: nextIndex);
      }
      debugPrint('📖 [PDF-DEBUG] pdfToTextPage → null (no match)');
    } else {
      debugPrint('📖 [PDF-DEBUG] outline empty, skipping pdfToTextPage');
    }

    final title = resolvedTitle ??
        await refFromPageNumber(pageNumber, outline, widget.tab.book.title);
    debugPrint('📖 [PDF-DEBUG] title for page $pageNumber = "$title"');
    if (widget.tab.pdfHeadings != null && title.isNotEmpty) {
      final lineNumber = widget.tab.pdfHeadings!.getLineNumberForHeading(title);
      debugPrint(
          '📖 [PDF-DEBUG] getLineNumberForHeading("$title") → $lineNumber');
      if (lineNumber != null) {
        return (start: lineNumber, end: null);
      }
    } else {
      debugPrint(
          '📖 [PDF-DEBUG] pdfHeadings=${widget.tab.pdfHeadings == null ? "null" : "loaded"}, title empty=${title.isEmpty}');
    }

    debugPrint(
        '📖 [PDF-DEBUG] fallback: returning pageNumber=$pageNumber as lineNumber');
    return (start: pageNumber, end: null);
  }

  ({List<String> commentators, List<otz_links.Link> links})
      _getRelevantContent() {
    final range = _getCurrentPdfLinesRange();
    if (range == null) return (commentators: const [], links: const []);

    final commentators = <String>{};
    final links = <otz_links.Link>[];

    for (final link in widget.tab.links) {
      if (link.index1 > range.endLine) break;
      if (link.index1 < range.startLine) continue;

      final connectionType = link.connectionType.toUpperCase();
      if (connectionType == _connectionTypeCommentary ||
          connectionType == _connectionTypeTargum) {
        commentators.add(utils.getTitleFromPath(link.path2));
        continue;
      }

      if (link.start == null && link.end == null) {
        links.add(link);
      }
    }

    final sortedCommentators = commentators.toList()..sort();

    return (commentators: sortedCommentators, links: links);
  }

  void _recordCommentaryOpenedIfNeeded() {
    if (_getRelevantContent().commentators.isNotEmpty) {
      context.read<TourCubit>().recordInteraction(
            TourInteraction(
              type: TourInteractionType.commentaryUsed,
              primaryValue: widget.tab.title,
            ),
          );
    }
  }

  void _openCommentaryPane() {
    _recordCommentaryOpenedIfNeeded();
    setState(() {
      _rightPaneInitialTabIndex = 0;
    });
    _bloc.add(const pdf_events.ToggleRightPane(show: true));
  }

  void _openLinksPane() {
    setState(() {
      _rightPaneInitialTabIndex = 1;
    });
    _bloc.add(const pdf_events.ToggleRightPane(show: true));
  }

  void _maybeRegisterPdfCommentaryOpportunity() {
    if (_linksLoading) {
      return;
    }

    if (!_bookHasCommentaryLinks) {
      return;
    }

    final currentState = _bloc.state;
    if (currentState is! PdfBookLoaded) {
      return;
    }

    final tourCubit = context.read<TourCubit>();
    if (tourCubit.hasRegisteredCommentaryOpportunity) {
      return;
    }

    if (_getRelevantContent().commentators.isEmpty) {
      return;
    }

    tourCubit.recordInteraction(
      TourInteraction(
        type: TourInteractionType.commentaryAvailable,
        primaryValue: widget.tab.title,
      ),
    );
  }

  void _toggleCommentator(String commentator) {
    if (widget.tab.activeCommentators.contains(commentator)) {
      widget.tab.activeCommentators.remove(commentator);
    } else {
      widget.tab.activeCommentators.add(commentator);
    }
    _saveActiveCommentators();
    _openCommentaryPane();
  }

  void _toggleAllCommentators(List<String> commentators) {
    final allActive = widget.tab.activeCommentators.containsAll(commentators);
    if (allActive) {
      widget.tab.activeCommentators.removeAll(commentators);
    } else {
      widget.tab.activeCommentators.addAll(commentators);
    }
    _saveActiveCommentators();
    _openCommentaryPane();
  }

  List<AppContextMenuEntry> _buildGroupedCommentatorEntries(
      List<String> relevantCommentators) {
    final items = <AppContextMenuEntry>[];

    AppContextMenuEntry buildItem(String commentator) => AppContextMenuEntry(
          label: commentator,
          icon: widget.tab.activeCommentators.contains(commentator)
              ? FluentIcons.checkmark_24_regular
              : null,
          onTap: () => _toggleCommentator(commentator),
        );

    if (_commentatorGroups.isNotEmpty) {
      final allGrouped =
          _commentatorGroups.expand((group) => group.commentators).toSet();

      for (final group in _commentatorGroups) {
        final groupItems = group.commentators
            .where((commentator) => relevantCommentators.contains(commentator))
            .toList();
        if (groupItems.isNotEmpty) {
          if (items.isNotEmpty) {
            items.add(const AppContextMenuEntry.divider());
          }
          items.addAll(groupItems.map(buildItem));
        }
      }

      final ungrouped = relevantCommentators
          .where((commentator) => !allGrouped.contains(commentator))
          .toList();
      if (ungrouped.isNotEmpty) {
        if (items.isNotEmpty) {
          items.add(const AppContextMenuEntry.divider());
        }
        items.addAll(ungrouped.map(buildItem));
      }
    } else {
      items.addAll(relevantCommentators.map(buildItem));
    }

    return items;
  }

  List<AppContextMenuEntry> _buildPdfContextMenuEntries(
      BuildContext menuContext, Offset _) {
    final (commentators: relevantCommentators, links: relevantLinks) =
        _getRelevantContent();

    final allActive = relevantCommentators.isNotEmpty &&
        widget.tab.activeCommentators.containsAll(relevantCommentators);

    final isRightPaneClosed = switch (_bloc.state) {
      PdfBookLoaded(showRightPane: final isShown) => !isShown,
      _ => true,
    };
    final shouldShowOpenPaneEntry = shouldShowOpenPdfCommentaryPaneEntry(
      hasRelevantCommentators: relevantCommentators.isNotEmpty,
      isPaneOpen: !isRightPaneClosed,
    );

    final commentatorChildren = <AppContextMenuEntry>[
      if (shouldShowOpenPaneEntry) ...[
        AppContextMenuEntry(
          label: 'פתח את חלונית המפרשים',
          icon: FluentIcons.panel_right_24_regular,
          onTap: () => _openCommentaryPane(),
        ),
        const AppContextMenuEntry.divider(),
      ],
      AppContextMenuEntry(
        label: 'הצג את כל המפרשים',
        icon: allActive ? FluentIcons.checkmark_24_regular : null,
        onTap: () => _toggleAllCommentators(relevantCommentators),
      ),
      if (relevantCommentators.isNotEmpty) const AppContextMenuEntry.divider(),
      ..._buildGroupedCommentatorEntries(relevantCommentators),
    ];

    final showOpenLinksPaneEntry = shouldShowOpenPdfLinksPaneEntry(
      hasRelevantLinks: relevantLinks.isNotEmpty,
      isPaneOpen: !isRightPaneClosed,
    );

    final linkChildren = <AppContextMenuEntry>[
      if (showOpenLinksPaneEntry) ...[
        AppContextMenuEntry(
          label: 'פתח את חלונית הקישורים',
          icon: FluentIcons.panel_right_24_regular,
          onTap: () => _openLinksPane(),
        ),
        const AppContextMenuEntry.divider(),
      ],
      ...relevantLinks.map((link) => AppContextMenuEntry(
            label: link.fallbackDisplayReference,
            labelWidget: FutureBuilder<String>(
              future: link.displayReference,
              builder: (context, snapshot) => Text(
                snapshot.data ?? link.fallbackDisplayReference,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.rtl,
              ),
            ),
            onTap: () => openBook(
              menuContext,
              TextBook(title: utils.getTitleFromPath(link.path2)),
              link.index2 - 1,
              '',
              ignoreHistory: false,
            ),
          )),
    ];

    return [
      AppContextMenuEntry(
        label: 'חיפוש',
        icon: FluentIcons.search_24_regular,
        onTap: _ensureSearchTabIsActive,
      ),
      AppContextMenuEntry(
        label: 'מפרשים',
        icon: FluentIcons.book_24_regular,
        enabled: relevantCommentators.isNotEmpty,
        children: commentatorChildren,
      ),
      AppContextMenuEntry(
        label: 'קישורים',
        icon: FluentIcons.link_24_regular,
        enabled: relevantLinks.isNotEmpty,
        children: linkChildren,
      ),
    ];
  }

  PdfViewerParams _buildPdfViewerParams(PdfLayoutMode layoutMode) {
    if (layoutMode == PdfLayoutMode.bookView) {
      _lockedSpreadStartPage ??= _spreadStartPageFor(widget.tab.pageNumber);
    }

    return PdfViewerParams(
      layoutPages: layoutMode == PdfLayoutMode.bookView
          ? (pages, params) {
              final pageLayouts = <Rect>[];
              const gap = _bookViewGap;
              const scale = _bookViewScale;
              double maxWidth = 0;
              double totalHeight = 0;

              if (pages.isNotEmpty) {
                maxWidth = pages[0].width * scale * 2 + gap;
              }

              for (int i = 0; i < pages.length; i++) {
                final currentPage = pages[i];
                final scaledWidth = currentPage.width * scale;
                final scaledHeight = currentPage.height * scale;

                if (i == 0) {
                  // עמוד 0 (שער) - לבדו
                  pageLayouts.add(
                    Rect.fromLTWH(0, totalHeight, scaledWidth, scaledHeight),
                  );
                  totalHeight += scaledHeight + params.margin;
                } else {
                  final pageIndex = i - 1;
                  final isRightPage = pageIndex % 2 == 0;

                  if (isRightPage) {
                    final nextPage = i + 1 < pages.length ? pages[i + 1] : null;

                    pageLayouts.add(
                      Rect.fromLTWH(
                        scaledWidth + gap,
                        totalHeight,
                        scaledWidth,
                        scaledHeight,
                      ),
                    );

                    if (nextPage != null) {
                      final nextScaledWidth = nextPage.width * scale;
                      final nextScaledHeight = nextPage.height * scale;

                      pageLayouts.add(
                        Rect.fromLTWH(
                            0, totalHeight, nextScaledWidth, nextScaledHeight),
                      );
                      totalHeight +=
                          max(scaledHeight, nextScaledHeight) + params.margin;
                      i++;
                    } else {
                      totalHeight += scaledHeight + params.margin;
                    }
                  }
                }
              }

              return PdfPageLayout(
                pageLayouts: pageLayouts,
                documentSize: Size(maxWidth, totalHeight),
              );
            }
          : null,
      normalizeMatrix: layoutMode == PdfLayoutMode.bookView
          ? (matrix, viewSize, layout, controller) {
              if (_isPageTurnInProgress) {
                return matrix;
              }
              return _normalizeBookViewMatrix(
                matrix: matrix,
                viewSize: viewSize,
                layout: layout,
                controller: controller,
              );
            }
          : null,
      enableKeyboardNavigation: false,
      scrollByArrowKey: 25.0,
      scrollByMouseWheel: 0.0,
      onDocumentLoadFinished: (documentRef, succeeded) {
        if (!mounted) return;
        _bloc.add(pdf_events.SetLoadingState(
          isLoading: false,
          succeeded: succeeded,
        ));
      },
      backgroundColor:
          Colors.white, // תמיד לבן - ה-ColorFilter יהפוך לשחור במצב כהה
      maxScale: 10,
      horizontalCacheExtent: 0,
      verticalCacheExtent: layoutMode == PdfLayoutMode.bookView
          ? 2
          : 1, // במצב ספר: פריסה אחת קדימה/אחורה נוספת
      pageAnchor: PdfPageAnchor.top, // עיגון לראש הדף
      onInteractionStart: (_) {
        if (!(widget.tab.pinLeftPane.value ||
            (Settings.getValue<bool>('key-pin-sidebar') ?? false))) {
          _setLeftPaneVisibility(false);
        }
      },
      onGeneralTap: (tapContext, _, details) {
        return details.type == PdfViewerGeneralTapType.secondaryTap;
      },
      onKey: (params, key, isRealKeyPress) {
        if (key == LogicalKeyboardKey.arrowLeft) {
          if (isRealKeyPress) {
            _goNextPage();
          }
          return true;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          if (isRealKeyPress) {
            _goPreviousPage();
          }
          return true;
        }
        return null;
      },
      viewerOverlayBuilder: (context, size, handleLinkTap) => [
        Positioned.fill(
          child: AppContextMenuRegion(
            menuBuilder: _buildPdfContextMenuEntries,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        _buildBookViewViewportMask(size),
        _buildBookViewStackDecoration(context, size),
        _buildBookViewTurnButtons(context, size),
      ],
      loadingBannerBuilder: (context, bytesDownloaded, totalBytes) => Center(
        child: CircularProgressIndicator(
          value: totalBytes != null ? bytesDownloaded / totalBytes : null,
          backgroundColor: Colors.grey,
        ),
      ),
      linkWidgetBuilder: (context, link, size) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            if (link.url != null) {
              navigateToUrl(link.url!);
            } else if (link.dest != null) {
              widget.tab.pdfViewerController.goToDest(link.dest);
            }
          },
          hoverColor: Colors.blue.withValues(alpha: 0.2),
        ),
      ),
      pagePaintCallbacks: textSearcher != null
          ? [textSearcher!.pageTextMatchPaintCallback]
          : null,
      onDocumentChanged: (document) async {
        if (document == null) {
          widget.tab.documentRef.value = null;
          widget.tab.outline.value = null;
        }
      },
      onViewerReady: (document, controller) async {
        if (!mounted) return;
        // Only grab focus if neither of the pane text-fields is focused.
        // Unconditional requestFocus() here stole focus from open search/nav fields.
        if (!_searchFieldFocusNode.hasFocus &&
            !_navigationFieldFocusNode.hasFocus) {
          _pdfViewFocusNode.requestFocus();
        }
        textSearcher = PdfTextSearcher(pdfController)
          ..addListener(_onTextSearcherUpdated);

        widget.tab.documentRef.value = controller.documentRef;
        widget.tab.outline.value = await document.loadOutline();
        final totalPages = document.pages.length;
        final initialTargetPage = widget.tab.pageNumber.clamp(1, totalPages);
        widget.tab.pageNumber = initialTargetPage;

        _bloc.add(pdf_events.DocumentReady(
          documentRef: controller.documentRef,
          outline: widget.tab.outline.value,
          totalPages: totalPages,
        ));

        // חישוב currentTextLineNumber אחרי טעינת ה-outline
        final targetPage = initialTargetPage;
        final targetTitle = await refFromPageNumber(
            targetPage, widget.tab.outline.value ?? [], widget.tab.book.title);
        if (!mounted) return;
        widget.tab.currentTitle.value = targetTitle;
        final initialResolved = await _resolveTextLineNumberForPage(
          targetPage,
          resolvedTitle: targetTitle,
        );
        if (!mounted) return;
        widget.tab.currentTextLineNumber = initialResolved.start;
        widget.tab.currentTextLineNumberEnd = initialResolved.end;
        setState(() {});

        if (!mounted) return;
        final enablePerBookSettings =
            context.read<SettingsBloc>().state.enablePerBookSettings;

        final savedZoom = widget.tab.savedZoom;
        final hasSavedZoom = savedZoom != null && savedZoom != 1.0;
        bool shouldFitToWidth =
            layoutMode != PdfLayoutMode.bookView && !hasSavedZoom;
        if (enablePerBookSettings) {
          final settings =
              await PdfBookPerBookSettings.load(widget.tab.book.title);
          shouldFitToWidth = shouldFitToWidth && settings?.zoom == null;

          // טעינת המפרשים הפעילים
          if (settings?.activeCommentators != null) {
            widget.tab.activeCommentators.clear();
            widget.tab.activeCommentators.addAll(settings!.activeCommentators!);
          }
        }

        final currentReadyPage = controller.pageNumber;
        final needsInitialPageNavigation =
            currentReadyPage == null || currentReadyPage != initialTargetPage;
        if (needsInitialPageNavigation) {
          _isJumping = true;
          try {
            await WidgetsBinding.instance.endOfFrame;
            if (mounted && controller.isReady) {
              await controller.goToPage(
                pageNumber: initialTargetPage,
                duration: Duration.zero,
              );
              await Future.delayed(const Duration(milliseconds: 200));
            }
          } finally {
            _isJumping = false;
            _initialPageNumber = null;
          }
        } else {
          _initialPageNumber = null;
        }

        if (shouldFitToWidth) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && controller.isReady) {
              final currentPage = controller.pageNumber ?? initialTargetPage;
              final matrix = controller.calcMatrixFitWidthForPage(
                pageNumber: currentPage,
              );
              if (matrix != null) {
                controller.goTo(matrix);
                Future.delayed(const Duration(milliseconds: 50), () {
                  if (mounted && controller.isReady) {
                    final currentZoom = controller.value.zoom;
                    controller.setZoom(
                      controller.centerPosition,
                      currentZoom * 0.98,
                    );
                  }
                });
              }
            }
          });
        }

        _runInitialSearchIfNeeded();

        final shouldShowLeftPane = resolveInitialReadingLeftPaneVisibility(
          explicitOpen: widget.tab.showLeftPane.value,
          hasSearchText: widget.tab.searchText.isNotEmpty,
        );
        if (mounted) {
          if (shouldShowLeftPane) {
            _setLeftPaneVisibility(true);
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _pdfViewFocusNode.requestFocus();
              }
            });
          }
        }
      },
    );
  }

  Widget _buildPdfViewerFromFile(String filePath) {
    return BlocBuilder<PdfBookBloc, PdfBookState>(
      bloc: _bloc,
      buildWhen: (prev, curr) {
        PdfLayoutMode? layoutModeFor(PdfBookState state) {
          if (state is PdfBookInitial) return state.layoutMode;
          if (state is PdfBookLoading) return state.layoutMode;
          if (state is PdfBookLoaded) return state.layoutMode;
          return null;
        }

        return layoutModeFor(prev) != layoutModeFor(curr);
      },
      builder: (context, state) {
        if (state is PdfBookError || !_pdfFileExists) {
          return const SizedBox.shrink();
        }

        final layoutMode = switch (state) {
          PdfBookInitial initial => initial.layoutMode,
          PdfBookLoading loading => loading.layoutMode,
          PdfBookLoaded loaded => loaded.layoutMode,
          _ => PdfLayoutMode.regularView,
        };

        return Focus(
          focusNode: _pdfViewFocusNode,
          autofocus: false,
          onKeyEvent: (FocusNode node, KeyEvent event) {
            if (event is KeyDownEvent) {
              final printShortcut =
                  Settings.getValue<String>('key-shortcut-print') ?? 'ctrl+p';
              if (ShortcutHelper.matchesShortcut(event, printShortcut)) {
                _handlePrintPress(context);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                _goNextPage();
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _goPreviousPage();
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                _startContinuousScroll(LogicalKeyboardKey.arrowUp);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _startContinuousScroll(LogicalKeyboardKey.arrowDown);
                return KeyEventResult.handled;
              }
            } else if (event is KeyRepeatEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                _heldArrowKeys.add(event.logicalKey);
                _goNextPage();
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _heldArrowKeys.add(event.logicalKey);
                _goPreviousPage();
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                _startContinuousScroll(LogicalKeyboardKey.arrowUp);
                return KeyEventResult.handled;
              } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _startContinuousScroll(LogicalKeyboardKey.arrowDown);
                return KeyEventResult.handled;
              }
            } else if (event is KeyUpEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                  event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _stopContinuousScroll();
                return KeyEventResult.handled;
              }
              // Releasing left/right arrow: only drain the queue if the key
              // was HELD (had at least one KeyRepeatEvent). Short taps must
              // keep their queued turn so the second click in a fast 1-2
              // tap doesn't get dropped along with the first click's hold-
              // less queue clear.
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                  event.logicalKey == LogicalKeyboardKey.arrowRight) {
                final wasHeld = _heldArrowKeys.remove(event.logicalKey);
                if (wasHeld) {
                  _pendingPageTurns.clear();
                  // Snap the "last initiated" intent back to the target of
                  // the animation that's actually in flight, so the next
                  // click advances ONE step from where the user is about
                  // to land — instead of from the discarded held-key
                  // intent that may be many spreads further ahead.
                  _lastInitiatedTargetPage = _inFlightAnimationTarget;
                }
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: _pdfViewerSuspended
              ? const SizedBox.expand()
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _pdfViewFocusNode.requestFocus();
                  },
                  child: PdfViewer.file(
                    filePath,
                    controller: widget.tab.pdfViewerController,
                    initialPageNumber:
                        widget.tab.pageNumber < 1 ? 1 : widget.tab.pageNumber,
                    useProgressiveLoading: false,
                    passwordProvider: () => passwordDialog(context),
                    params: _buildPdfViewerParams(layoutMode),
                  ),
                ),
        );
      },
    );
  }

  // ============ Book view spread helpers ============

  bool _isBookViewModeActive() {
    final state = _bloc.state;
    return state is PdfBookLoaded && state.layoutMode == PdfLayoutMode.bookView;
  }

  int _spreadStartPageFor(int pageNumber) {
    if (pageNumber <= 1) return 1;
    return pageNumber.isEven ? pageNumber : pageNumber - 1;
  }

  Rect? _spreadRectForPageLayout(PdfPageLayout layout, int spreadStartPage) {
    final pageLayouts = layout.pageLayouts;
    if (pageLayouts.isEmpty || spreadStartPage - 1 >= pageLayouts.length) {
      return null;
    }
    final rightPageRect = pageLayouts[spreadStartPage - 1];

    if (spreadStartPage == 1) {
      return Rect.fromLTWH(
        0,
        rightPageRect.top,
        layout.documentSize.width,
        rightPageRect.height,
      );
    }
    if (spreadStartPage >= pageLayouts.length) {
      return rightPageRect;
    }
    return rightPageRect.expandToInclude(pageLayouts[spreadStartPage]);
  }

  Rect? _currentSpreadRect(PdfViewerController controller) {
    if (!controller.isReady || !_isBookViewModeActive()) return null;
    final currentPage = controller.pageNumber ?? widget.tab.pageNumber;
    final spreadStartPage =
        _lockedSpreadStartPage ?? _spreadStartPageFor(currentPage);
    return _spreadRectForPageLayout(controller.layout, spreadStartPage);
  }

  Rect? _currentVerticalScrollbarBounds(PdfViewerController controller) {
    if (!controller.isReady) return null;
    if (_isBookViewModeActive()) {
      return _currentSpreadRect(controller);
    }
    // תצוגה רגילה - החזר את גבולות המסמך המלא
    // controller.layout זורק אם ה-PdfViewer state לא חובר עדיין (race condition ב-pdfrx)
    try {
      final layout = controller.layout;
      final pageLayouts = layout.pageLayouts;
      if (pageLayouts.isEmpty) return null;
      return Rect.fromLTRB(
        0,
        pageLayouts.first.top,
        layout.documentSize.width,
        pageLayouts.last.bottom,
      );
    } catch (_) {
      return null;
    }
  }

  Rect? _currentSpreadViewportRect(
      PdfViewerController controller, Size viewportSize) {
    final spreadRect = _currentSpreadRect(controller);
    if (spreadRect == null) return null;
    final viewportRect =
        MatrixUtils.transformRect(controller.value, spreadRect);
    final clippedRect = viewportRect.intersect(Offset.zero & viewportSize);
    if (clippedRect.width <= 0 || clippedRect.height <= 0) return null;
    return clippedRect;
  }

  Widget _buildBookViewViewportMask(Size viewportSize) {
    if (!_isBookViewModeActive()) return const SizedBox.shrink();
    final spreadViewportRect = _currentSpreadViewportRect(
        widget.tab.pdfViewerController, viewportSize);
    if (spreadViewportRect == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _BookViewViewportMaskPainter(spreadViewportRect),
        ),
      ),
    );
  }

  List<_VisibleBookPage> _currentSpreadPages(
    PdfViewerController controller,
    Size viewportSize,
  ) {
    if (!controller.isReady || !_isBookViewModeActive()) return const [];

    final currentPage = controller.pageNumber ?? widget.tab.pageNumber;
    final spreadStartPage =
        _lockedSpreadStartPage ?? _spreadStartPageFor(currentPage);
    final totalPages = controller.pageCount;
    final pageNumbers = <int>[
      spreadStartPage,
      if (spreadStartPage > 1 && spreadStartPage < totalPages)
        spreadStartPage + 1,
    ];

    final viewportBounds = Offset.zero & viewportSize;
    final pages = <_VisibleBookPage>[];

    for (final pageNumber in pageNumbers) {
      final pageRect = MatrixUtils.transformRect(
        controller.value,
        controller.layout.pageLayouts[pageNumber - 1],
      );
      if (!pageRect.overlaps(viewportBounds)) continue;

      final isLeftPage =
          spreadStartPage == 1 || pageNumber == spreadStartPage + 1;
      final outerStackPages =
          isLeftPage ? totalPages - pageNumber : pageNumber - 1;

      pages.add(_VisibleBookPage(
        pageNumber: pageNumber,
        viewportRect: pageRect,
        isLeftPage: isLeftPage,
        outerStackPages: outerStackPages,
      ));
    }

    return pages;
  }

  Widget _buildBookViewStackDecoration(
      BuildContext context, Size viewportSize) {
    if (!_isBookViewModeActive()) return const SizedBox.shrink();

    final visiblePages =
        _currentSpreadPages(widget.tab.pdfViewerController, viewportSize);
    if (visiblePages.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _BookSpreadPainter(
            pages: visiblePages,
            pageEdgeColor: colorScheme.outlineVariant,
            stackColor: colorScheme.surfaceContainerHighest,
            stackShadowColor: colorScheme.shadow.withValues(alpha: 0.18),
            spineColor: colorScheme.outline.withValues(alpha: 0.28),
          ),
        ),
      ),
    );
  }

  Widget _buildBookViewTurnButtons(BuildContext context, Size viewportSize) {
    if (!_isBookViewModeActive() || !widget.tab.pdfViewerController.isReady) {
      return const SizedBox.shrink();
    }

    final currentPage = widget.tab.pdfViewerController.pageNumber ?? 1;
    final totalPages = widget.tab.pdfViewerController.pageCount;
    final canGoPrevious = currentPage > 1;
    final canGoNext = currentPage < totalPages;
    final buttonSize = min(72.0, max(48.0, viewportSize.shortestSide * 0.10));
    final horizontalPadding = min(28.0, viewportSize.width * 0.018);
    final colorScheme = Theme.of(context).colorScheme;

    return Positioned.fill(
      child: Stack(
        children: [
          if (canGoPrevious)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: horizontalPadding),
                child: _BookViewTurnButton(
                  icon: FluentIcons.chevron_left_24_regular,
                  tooltip: 'הזוג הקודם',
                  size: buttonSize,
                  backgroundColor: colorScheme.surface.withValues(alpha: 0.78),
                  iconColor: colorScheme.onSurface,
                  borderColor: colorScheme.outline.withValues(alpha: 0.22),
                  shadowColor: colorScheme.shadow.withValues(alpha: 0.16),
                  onPressed: _goPreviousPage,
                ),
              ),
            ),
          if (canGoNext)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: horizontalPadding),
                child: _BookViewTurnButton(
                  icon: FluentIcons.chevron_right_24_regular,
                  tooltip: 'הזוג הבא',
                  size: buttonSize,
                  backgroundColor: colorScheme.surface.withValues(alpha: 0.78),
                  iconColor: colorScheme.onSurface,
                  borderColor: colorScheme.outline.withValues(alpha: 0.22),
                  shadowColor: colorScheme.shadow.withValues(alpha: 0.16),
                  onPressed: _goNextPage,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPageTurnOverlay(BuildContext context) {
    final snapshot = _pageTurnSnapshot;
    final transition = _pageTurnTransition;

    if (snapshot == null || transition == null) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    // Two-layer overlay:
    // 1. Full-viewport background: draws the snapshot everywhere EXCEPT the
    //    already-revealed portion of the spread (so new pages show through there).
    // 2. Spread-rect animation overlay: draws the curl + unrevealed snapshot.
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _pageTurnController,
              builder: (context, child) {
                final progress = Curves.easeOutCubic.transform(
                  _pageTurnController.value,
                );
                return CustomPaint(
                  painter: _BookPageTurnBackgroundPainter(
                    snapshot: snapshot,
                    targetSnapshot: _pageTurnTargetSnapshot,
                    spreadRect: transition.viewportRect,
                    progress: progress,
                    direction: transition.direction,
                    shadowColor: colorScheme.shadow,
                    edgeColor: colorScheme.outlineVariant,
                  ),
                );
              },
            ),
          ),
        ),
        Positioned.fromRect(
          rect: transition.viewportRect,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _pageTurnController,
              builder: (context, child) {
                final progress = Curves.easeOutCubic.transform(
                  _pageTurnController.value,
                );

                return CustomPaint(
                  size: transition.viewportRect.size,
                  painter: _BookPageTurnPainter(
                    snapshot: snapshot,
                    targetSnapshot: _pageTurnTargetSnapshot,
                    snapshotViewportRect: transition.viewportRect,
                    viewportLogicalSize: transition.viewportLogicalSize,
                    progress: progress,
                    direction: transition.direction,
                    pageBackColor: colorScheme.surface,
                    pageHighlightColor: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.94),
                    shadowColor: colorScheme.shadow,
                    edgeColor: colorScheme.outlineVariant,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  int _dominantPageForRect(
      Rect rect, List<Rect> pageLayouts, int fallbackPage) {
    var bestPage = fallbackPage;
    var bestArea = 0.0;
    for (var i = 0; i < pageLayouts.length; i++) {
      final intersection = rect.intersect(pageLayouts[i]);
      final area = intersection.width <= 0 || intersection.height <= 0
          ? 0.0
          : intersection.width * intersection.height;
      if (area > bestArea) {
        bestArea = area;
        bestPage = i + 1;
      }
    }
    return bestPage;
  }

  Matrix4 _normalizeBookViewMatrix({
    required Matrix4 matrix,
    required Size viewSize,
    required PdfPageLayout layout,
    required PdfViewerController? controller,
  }) {
    if (controller == null || !controller.isReady) return matrix;

    if (_scrollAnchorPage != null) {
      final anchoredSpreadStartPage = _spreadStartPageFor(_scrollAnchorPage!);
      _lockedSpreadStartPage = anchoredSpreadStartPage;
      return _clampMatrixToSpread(
        matrix: matrix,
        viewSize: viewSize,
        layout: layout,
        controller: controller,
        spreadStartPage: anchoredSpreadStartPage,
      );
    }

    final currentPage = controller.pageNumber ?? widget.tab.pageNumber;
    final candidateVisibleRect = matrix.calcVisibleRect(viewSize);

    var spreadStartPage =
        _lockedSpreadStartPage ?? _spreadStartPageFor(currentPage);
    var spreadRect = _spreadRectForPageLayout(layout, spreadStartPage);

    // layout עדיין לא כולל את הדפים הנדרשים (טעינה פרוגרסיבית) — לא נחסום
    if (spreadRect == null) return matrix;

    if (!candidateVisibleRect.overlaps(spreadRect)) {
      final targetPage = _dominantPageForRect(
        candidateVisibleRect,
        layout.pageLayouts,
        currentPage,
      );
      spreadStartPage = _spreadStartPageFor(targetPage);
      spreadRect = _spreadRectForPageLayout(layout, spreadStartPage);
      if (spreadRect == null) return matrix;
    }

    _lockedSpreadStartPage = spreadStartPage;

    return _clampMatrixToSpread(
      matrix: matrix,
      viewSize: viewSize,
      layout: layout,
      controller: controller,
      spreadStartPage: spreadStartPage,
    );
  }

  Matrix4 _clampMatrixToSpread({
    required Matrix4 matrix,
    required Size viewSize,
    required PdfPageLayout layout,
    required PdfViewerController controller,
    required int spreadStartPage,
  }) {
    final candidateVisibleRect = matrix.calcVisibleRect(viewSize);
    final spreadRect = _spreadRectForPageLayout(layout, spreadStartPage);

    // layout עדיין לא כולל את הדפים הנדרשים (טעינה פרוגרסיבית) — לא נחסום
    if (spreadRect == null) return matrix;

    final newZoom = matrix.zoom;
    final halfWidth = viewSize.width / 2 / newZoom;
    final halfHeight = viewSize.height / 2 / newZoom;

    final minCenterX = spreadRect.left + halfWidth;
    final maxCenterX = spreadRect.right - halfWidth;
    final minCenterY = spreadRect.top + halfHeight;
    final maxCenterY = spreadRect.bottom - halfHeight;

    final targetCenterX = minCenterX <= maxCenterX
        ? candidateVisibleRect.center.dx
            .clamp(minCenterX, maxCenterX)
            .toDouble()
        : spreadRect.center.dx;
    final targetCenterY = minCenterY <= maxCenterY
        ? candidateVisibleRect.center.dy
            .clamp(minCenterY, maxCenterY)
            .toDouble()
        : spreadRect.center.dy;

    return controller.calcMatrixFor(
      Offset(targetCenterX, targetCenterY),
      zoom: newZoom,
      viewSize: viewSize,
    );
  }

  bool _wasMatrixClamped({
    required Matrix4 original,
    required Matrix4 clamped,
    required Size viewSize,
  }) {
    final originalRect = original.calcVisibleRect(viewSize);
    final clampedRect = clamped.calcVisibleRect(viewSize);

    return (original.zoom - clamped.zoom).abs() > 0.001 ||
        (originalRect.center.dx - clampedRect.center.dx).abs() > 0.1 ||
        (originalRect.center.dy - clampedRect.center.dy).abs() > 0.1;
  }

  Future<void> _goToPageWithSpreadLock(int pageNumber) async {
    final controller = widget.tab.pdfViewerController;
    if (!controller.isReady) return;
    final totalPages = controller.pageCount;
    final safePage = pageNumber.clamp(1, totalPages);

    if (_isBookViewModeActive()) {
      // Capture current spread BEFORE updating _lockedSpreadStartPage, because
      // _currentSpreadRect reads _lockedSpreadStartPage to find the spread rect.
      final currentSpreadRect = _currentSpreadRect(controller);
      _lockedSpreadStartPage = _spreadStartPageFor(safePage);

      // Calculate the target matrix directly so we jump to the correct vertical
      // position in one shot — avoiding a flash-to-top that would occur if we
      // called goToPage and then corrected afterwards.
      final newSpreadRect =
          _spreadRectForPageLayout(controller.layout, _lockedSpreadStartPage!);
      if (currentSpreadRect != null &&
          newSpreadRect != null &&
          currentSpreadRect.height > 0 &&
          newSpreadRect.height > 0) {
        final visibleRect = controller.visibleRect;
        final visibleHeight = min(visibleRect.height, currentSpreadRect.height);
        final currentScrollableExtent =
            max(currentSpreadRect.height - visibleHeight, 0.0);

        // Relative scroll: 0.0 = top of spread, 1.0 = bottom.
        // Uses scroll offset (not center) to avoid placing center outside spread.
        double relativeScroll = 0.0;
        if (currentScrollableExtent > 0) {
          final currentScrollTop = (visibleRect.top - currentSpreadRect.top)
              .clamp(0.0, currentScrollableExtent);
          relativeScroll = currentScrollTop / currentScrollableExtent;
        }

        final newScrollableExtent =
            max(newSpreadRect.height - visibleHeight, 0.0);
        final newScrollTop = relativeScroll * newScrollableExtent;
        final targetCenterY =
            newSpreadRect.top + newScrollTop + visibleHeight / 2;

        await controller
            .goTo(controller.calcMatrixFor(
              Offset(newSpreadRect.center.dx, targetCenterY),
              zoom: controller.value.zoom,
              viewSize: controller.viewSize,
            ))
            .timeout(const Duration(seconds: 3), onTimeout: () {});
        if (!_pdfViewFocusNode.hasFocus) {
          _pdfViewFocusNode.requestFocus();
        }
        return;
      }
    }

    // During progressive PDF loading, pdfrx may wait indefinitely for the
    // viewport to settle while new tiles keep arriving. Time out the await so
    // page-turn state cannot deadlock the navigation flow.
    await controller
        .goToPage(pageNumber: safePage)
        .timeout(const Duration(seconds: 3), onTimeout: () {});

    if (!_pdfViewFocusNode.hasFocus) {
      _pdfViewFocusNode.requestFocus();
    }
  }

  Future<({ui.Image image, Size viewportLogicalSize})?>
      _capturePdfViewportSnapshot() async {
    final boundaryContext = _pdfViewportBoundaryKey.currentContext;
    if (boundaryContext == null) {
      return null;
    }

    final renderObject = boundaryContext.findRenderObject();
    if (renderObject is! RenderRepaintBoundary || renderObject.size.isEmpty) {
      return null;
    }

    var needsPaint = false;
    assert(() {
      needsPaint = renderObject.debugNeedsPaint;
      return true;
    }());

    if (needsPaint) {
      for (var attempt = 0; attempt < 2; attempt++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) {
          return null;
        }

        needsPaint = false;
        assert(() {
          needsPaint = renderObject.debugNeedsPaint;
          return true;
        }());

        if (!needsPaint) {
          break;
        }
      }

      if (needsPaint) {
        return null;
      }
    }

    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    const maxCapturePixels = 1600000.0;
    final viewportPixels = renderObject.size.width * renderObject.size.height;
    final cappedPixelRatio =
        viewportPixels <= 0 ? 1.0 : sqrt(maxCapturePixels / viewportPixels);
    final pixelRatio =
        min(devicePixelRatio, min(1.35, cappedPixelRatio)).clamp(0.85, 1.35);

    try {
      final image = await renderObject.toImage(pixelRatio: pixelRatio);
      return (image: image, viewportLogicalSize: renderObject.size);
    } catch (error, stackTrace) {
      debugPrint('Failed to capture PDF snapshot: $error\n$stackTrace');
      return null;
    }
  }

  void _disposePageTurnSnapshot() {
    _pageTurnSnapshot?.dispose();
    _pageTurnSnapshot = null;
    _pageTurnTargetSnapshot?.dispose();
    _pageTurnTargetSnapshot = null;
  }

  void _clearPageTurnOverlay() {
    _disposePageTurnSnapshot();
    _pageTurnTransition = null;
  }

  Future<void> _processPendingPageTurnIfNeeded() async {
    if (_pendingPageTurns.isEmpty || !mounted) {
      return;
    }

    final pending = _pendingPageTurns.removeAt(0);
    await _animateBookPageTurn(
      targetPage: pending.targetPage,
      direction: pending.direction,
    );
  }

  // ============================================================
  // Spread pre-render cache
  // ============================================================

  List<int> _pagesInSpread(int spreadStartPage) {
    final controller = widget.tab.pdfViewerController;
    if (!controller.isReady) return const [];
    final totalPages = controller.pageCount;
    if (spreadStartPage < 1 || spreadStartPage > totalPages) return const [];
    if (spreadStartPage == 1) return const [1];
    return spreadStartPage + 1 <= totalPages
        ? [spreadStartPage, spreadStartPage + 1]
        : [spreadStartPage];
  }

  /// Renders the pages of [spreadStartPage] via pdfrx and stores the rendered
  /// images in the cache. Safe to call repeatedly: returns immediately if the
  /// spread is already cached or being rendered.
  Future<void> _renderSpreadPagesIntoCache(int spreadStartPage) async {
    if (_spreadCache.containsKey(spreadStartPage)) return;
    if (_spreadRenderInProgress.contains(spreadStartPage)) return;

    final controller = widget.tab.pdfViewerController;
    if (!controller.isReady) return;

    final pageNumbers = _pagesInSpread(spreadStartPage);
    if (pageNumbers.isEmpty) return;

    _spreadRenderInProgress.add(spreadStartPage);

    final pageImages = <int, ui.Image>{};

    try {
      for (final pageNum in pageNumbers) {
        if (!mounted || !controller.isReady) {
          _disposeImageMap(pageImages);
          return;
        }

        final pages = controller.document.pages;
        final pageIdx = pageNum - 1;
        if (pageIdx < 0 || pageIdx >= pages.length) continue;

        final page = pages[pageIdx];
        final cancellationToken = page.createCancellationToken();
        _spreadCancellationTokens[spreadStartPage] = cancellationToken;

        // 2.0 = render at 2x the page's natural 72-DPI size; sharp on most
        // displays without blowing memory. The painter scales down on draw
        // when the viewport is smaller.
        const renderScale = 2.0;
        final pdfImage = await page.render(
          fullWidth: page.width * renderScale,
          fullHeight: page.height * renderScale,
          backgroundColor: 0xFFFFFFFF,
          flags: PdfPageRenderFlags.limitedImageCache,
          cancellationToken: cancellationToken,
        );

        if (_spreadCancellationTokens[spreadStartPage] == cancellationToken) {
          _spreadCancellationTokens.remove(spreadStartPage);
        }

        if (pdfImage == null || !mounted) {
          _disposeImageMap(pageImages);
          return;
        }

        final uiImage = await pdfImage.createImage();
        pdfImage.dispose();

        if (!mounted) {
          uiImage.dispose();
          _disposeImageMap(pageImages);
          return;
        }

        pageImages[pageNum] = uiImage;
      }

      // Replace any stale entry (e.g. from previous render at different zoom).
      _spreadCache[spreadStartPage]?.dispose();
      _spreadCache[spreadStartPage] =
          _PdfSpreadCacheEntry(pageImages: pageImages);
    } catch (e, s) {
      debugPrint('Spread pre-render failed for $spreadStartPage: $e\n$s');
      _disposeImageMap(pageImages);
    } finally {
      _spreadRenderInProgress.remove(spreadStartPage);
      _spreadCancellationTokens.remove(spreadStartPage);
    }
  }

  void _disposeImageMap(Map<int, ui.Image> images) {
    for (final image in images.values) {
      image.dispose();
    }
    images.clear();
  }

  /// Composes a viewport-sized [ui.Image] from cached page images by
  /// predicting the post-navigation viewer matrix (preserves zoom, centers on
  /// the target spread) and drawing each page at its predicted viewport rect.
  /// Returns null if the spread isn't cached, the controller isn't ready, or
  /// the viewport size is empty.
  Future<ui.Image?> _composeCachedSpreadSnapshot(int spreadStartPage) async {
    final entry = _spreadCache[spreadStartPage];
    if (entry == null || entry.pageImages.isEmpty) return null;

    final controller = widget.tab.pdfViewerController;
    if (!controller.isReady) return null;

    final layout = controller.layout;
    final pageLayouts = layout.pageLayouts;
    final viewSize = controller.viewSize;
    if (viewSize.width <= 0 || viewSize.height <= 0) return null;

    final newSpreadRect = _spreadRectForPageLayout(layout, spreadStartPage);
    if (newSpreadRect == null) return null;

    // Predict the post-navigation viewer matrix using the same arithmetic as
    // `_goToPageWithSpreadLock`, so the composed snapshot lands on the same
    // pixels the live viewer will show after `goTo`. Otherwise zoomed-in
    // reading (where relative scroll != 0.5) would produce a "snap" at the
    // end of the curl as the snapshot is replaced by the actual viewer.
    final currentSpreadRect = _currentSpreadRect(controller);
    final visibleRect = controller.visibleRect;
    final zoom = controller.value.zoom;

    var targetCenterY = newSpreadRect.center.dy;
    if (currentSpreadRect != null &&
        currentSpreadRect.height > 0 &&
        newSpreadRect.height > 0) {
      final visibleHeight = min(visibleRect.height, currentSpreadRect.height);
      final currentScrollableExtent =
          max(currentSpreadRect.height - visibleHeight, 0.0);
      var relativeScroll = 0.0;
      if (currentScrollableExtent > 0) {
        final currentScrollTop = (visibleRect.top - currentSpreadRect.top)
            .clamp(0.0, currentScrollableExtent);
        relativeScroll = currentScrollTop / currentScrollableExtent;
      }
      final newScrollableExtent =
          max(newSpreadRect.height - visibleHeight, 0.0);
      final newScrollTop = relativeScroll * newScrollableExtent;
      targetCenterY = newSpreadRect.top + newScrollTop + visibleHeight / 2;
    }

    final targetMatrix = controller.calcMatrixFor(
      Offset(newSpreadRect.center.dx, targetCenterY),
      zoom: zoom,
      viewSize: viewSize,
    );

    final viewportPixels = viewSize.width * viewSize.height;
    const maxCapturePixels = 1600000.0;
    final cappedPixelRatio =
        viewportPixels <= 0 ? 1.0 : sqrt(maxCapturePixels / viewportPixels);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final pixelRatio =
        min(devicePixelRatio, min(1.35, cappedPixelRatio)).clamp(0.85, 1.35);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio);

    // Background — match the dark/light viewer surface so the area outside
    // the spread doesn't show as a stark transparent strip during the curl.
    final bgColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.black
        : const Color(0xFFFFFFFF);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, viewSize.width, viewSize.height),
      Paint()..color = bgColor,
    );

    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (final pageNum in entry.pageImages.keys) {
      final pageIdx = pageNum - 1;
      if (pageIdx < 0 || pageIdx >= pageLayouts.length) continue;

      final pageDocRect = pageLayouts[pageIdx];
      final pageViewportRect =
          MatrixUtils.transformRect(targetMatrix, pageDocRect);

      final pageImage = entry.pageImages[pageNum]!;
      canvas.drawImageRect(
        pageImage,
        Rect.fromLTWH(
          0,
          0,
          pageImage.width.toDouble(),
          pageImage.height.toDouble(),
        ),
        pageViewportRect,
        paint,
      );
    }

    final picture = recorder.endRecording();
    try {
      return await picture.toImage(
        (viewSize.width * pixelRatio).round(),
        (viewSize.height * pixelRatio).round(),
      );
    } finally {
      picture.dispose();
    }
  }

  /// Kicks off background pre-rendering of the current, next, and previous
  /// spreads so that `_animateBookPageTurn` finds them already cached.
  /// Cheap to call repeatedly: skips spreads that are already cached or
  /// rendering, and de-dupes via [_lastPrerenderTriggeredSpread].
  void _schedulePrerenderForAdjacentSpreads() {
    if (!_isBookViewModeActive()) return;
    final controller = widget.tab.pdfViewerController;
    if (!controller.isReady) return;

    final currentPage = controller.pageNumber ?? 1;
    final currentSpread = _spreadStartPageFor(currentPage);

    if (_lastPrerenderTriggeredSpread == currentSpread &&
        _spreadCache.containsKey(currentSpread)) {
      return;
    }
    _lastPrerenderTriggeredSpread = currentSpread;

    final totalPages = controller.pageCount;
    final candidates = <int>[
      currentSpread,
      currentSpread + 2,
      currentSpread - 2,
    ];

    for (final spread in candidates) {
      if (spread >= 1 && spread <= totalPages) {
        unawaited(_renderSpreadPagesIntoCache(spread));
      }
    }

    _evictSpreadCacheFarFrom(currentSpread);
  }

  /// Keeps cache memory bounded by evicting spreads more than [keepRange]
  /// pages away from the current spread.
  void _evictSpreadCacheFarFrom(int currentSpread) {
    const keepRange = 4;
    final toRemove = <int>[];
    for (final spread in _spreadCache.keys) {
      if ((spread - currentSpread).abs() > keepRange) {
        toRemove.add(spread);
      }
    }
    for (final spread in toRemove) {
      _spreadCache.remove(spread)?.dispose();
    }
  }

  void _disposeAllSpreadCache() {
    for (final entry in _spreadCache.values) {
      entry.dispose();
    }
    _spreadCache.clear();
    for (final token in _spreadCancellationTokens.values) {
      token.cancel();
    }
    _spreadCancellationTokens.clear();
    _spreadRenderInProgress.clear();
    _lastPrerenderTriggeredSpread = null;
    _lastInitiatedTargetPage = null;
    _inFlightAnimationTarget = null;
  }

  Future<void> _animateBookPageTurn({
    required int targetPage,
    required _BookPageTurnDirection direction,
  }) async {
    if (!mounted || !widget.tab.pdfViewerController.isReady) {
      return;
    }

    final currentPage = widget.tab.pdfViewerController.pageNumber ?? 1;
    if (targetPage == currentPage) {
      return;
    }

    if (!_isBookViewModeActive()) {
      await _goToPageWithSpreadLock(targetPage);
      return;
    }

    if (_pageTurnController.isAnimating || _isPageTurnInProgress) {
      // Animation already in flight: queue this turn FIFO so it plays after
      // the current one finishes. Each click gets its own curl, in order.
      _pendingPageTurns.add(_PendingBookPageTurn(
        targetPage: targetPage,
        direction: direction,
      ));
      return;
    }

    // Set the flag BEFORE any goToPage call so that the normalizeMatrix
    // callback is disabled for the entire duration. Without this, when
    // currentSpreadViewportRect is null (layout not ready during progressive
    // loading), goToPage hangs because normalization keeps fighting it.
    _isPageTurnInProgress = true;
    _inFlightAnimationTarget = targetPage;

    try {
      final currentSpreadViewportRect = _currentSpreadViewportRect(
        widget.tab.pdfViewerController,
        widget.tab.pdfViewerController.viewSize,
      );

      if (currentSpreadViewportRect == null) {
        await _goToPageWithSpreadLock(targetPage);
        return;
      }

      final captureResult = await _capturePdfViewportSnapshot();

      if (!mounted || captureResult == null) {
        captureResult?.image.dispose();
        await _goToPageWithSpreadLock(targetPage);
        return;
      }

      // Reset to 0 before setState so that when the AnimatedBuilder first
      // paints the overlay it uses progress=0 (full snapshot, no hole).
      // Without this, a previous completed animation leaves the controller
      // at 1.0, punching a full-spread hole in the snapshot and exposing
      // the loading tiles underneath before the animation even starts.
      _pageTurnController.reset();
      final transition = _BookPageTurnTransition(
        direction: direction,
        viewportRect: currentSpreadViewportRect,
        viewportLogicalSize: captureResult.viewportLogicalSize,
      );
      setState(() {
        _disposePageTurnSnapshot();
        _pageTurnSnapshot = captureResult.image;
        _pageTurnTransition = transition;
      });

      // Wait for the overlay frame to actually paint before jumping to the
      // new page. Without this, goToPage fires while the snapshot is still
      // scheduled (not yet on screen) and the new PDF tiles appear
      // underneath a blank overlay.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      // Cache lookup: if the target spread was pre-rendered, compose its
      // snapshot now (cheap, page renders are already in memory) and run
      // navigation in parallel with the curl. The user gets an instant
      // page-turn with the new page fully visible from frame 1.
      final targetSpreadStartPage = _spreadStartPageFor(targetPage);
      final hasCachedTarget = _spreadCache.containsKey(targetSpreadStartPage);

      if (hasCachedTarget) {
        final composed =
            await _composeCachedSpreadSnapshot(targetSpreadStartPage);

        if (!mounted) {
          composed?.dispose();
          return;
        }

        if (composed != null) {
          setState(() {
            _pageTurnTargetSnapshot?.dispose();
            _pageTurnTargetSnapshot = composed;
          });
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted) return;
        }

        // Run navigation concurrently with the animation. The cached snapshot
        // covers the reveal so any tile churn from goTo is invisible. We
        // capture the future and await it AFTER the animation so the next
        // queued page-turn (if any) starts from the actual settled spread,
        // not a stale viewer mid-transition. The overlay stays visible (at
        // progress=1) until finally clears it, so the user sees no flash.
        final navigationFuture =
            _goToPageWithSpreadLock(targetPage).catchError((Object _) {});

        await _pageTurnController.forward(from: 0);
        await navigationFuture;
      } else {
        // Cache miss — fall back to sequential flow (the cost on first visit
        // before pre-rendering completes for this spread).
        await _goToPageWithSpreadLock(targetPage);

        if (!mounted) return;

        // Capture the target spread after navigation. During the animation we
        // draw this snapshot in the revealed area, so the new page looks
        // fully rendered from the very first frame of the curl — instead of
        // showing pdfrx tile-loading progress that reads as "scrolling in".
        await Future<void>.delayed(const Duration(milliseconds: 90));

        if (!mounted) return;

        final targetCaptureResult = await _capturePdfViewportSnapshot();

        if (mounted && targetCaptureResult != null) {
          setState(() {
            _pageTurnTargetSnapshot?.dispose();
            _pageTurnTargetSnapshot = targetCaptureResult.image;
          });
          await WidgetsBinding.instance.endOfFrame;
        }

        if (!mounted) return;

        await _pageTurnController.forward(from: 0);
      }
    } finally {
      _isPageTurnInProgress = false;
      _inFlightAnimationTarget = null;
      if (mounted) {
        setState(_clearPageTurnOverlay);
      } else {
        _clearPageTurnOverlay();
      }
      await _processPendingPageTurnIfNeeded();
    }
  }

  Future<void> _saveActiveCommentators() async {
    final settingsBloc = context.read<SettingsBloc>();
    if (!settingsBloc.state.enablePerBookSettings) return;

    final settings = PdfBookPerBookSettings(
      activeCommentators: List.from(widget.tab.activeCommentators),
    );
    await settings.save(widget.tab.book.title);
  }

  Future<void> _loadActiveCommentators() async {
    final settingsBloc = context.read<SettingsBloc>();
    if (!settingsBloc.state.enablePerBookSettings) return;

    final settings = await PdfBookPerBookSettings.load(widget.tab.book.title);
    if (settings?.activeCommentators != null && mounted) {
      widget.tab.activeCommentators.clear();
      widget.tab.activeCommentators.addAll(settings!.activeCommentators!);
    }
  }

  Future<void> _loadCommentatorGroups() async {
    final commentatorsSet = <String>{};
    for (final link in widget.tab.links) {
      if (link.connectionType == 'COMMENTARY' ||
          link.connectionType == 'TARGUM') {
        commentatorsSet.add(utils.getTitleFromPath(link.path2));
      }
    }
    final eras = await utils.splitByEra(commentatorsSet.toList());
    final known = <String>{
      ...?eras['תורה שבכתב'],
      ...?eras['חז"ל'],
      ...?eras['ראשונים'],
      ...?eras['אחרונים'],
      ...?eras['מחברי זמננו'],
    };
    final others = (eras['מפרשים נוספים'] ?? [])
        .toSet()
        .union(commentatorsSet.where((c) => !known.contains(c)).toSet())
        .toList();
    if (!mounted) return;
    setState(() {
      _commentatorGroups = [
        CommentatorGroup(
            title: 'תורה שבכתב', commentators: eras['תורה שבכתב'] ?? const []),
        CommentatorGroup(title: 'חז"ל', commentators: eras['חז"ל'] ?? const []),
        CommentatorGroup(
            title: 'ראשונים', commentators: eras['ראשונים'] ?? const []),
        CommentatorGroup(
            title: 'אחרונים', commentators: eras['אחרונים'] ?? const []),
        CommentatorGroup(
            title: 'מחברי זמננו',
            commentators: eras['מחברי זמננו'] ?? const []),
        CommentatorGroup(title: 'שאר מפרשים', commentators: others),
      ];
    });
  }

  Future<void> _loadPdfHeadingsAndLinks() async {
    final bookTitle = widget.tab.book.title;
    final categoryId = widget.tab.book.categoryId;
    final filePath = widget.tab.book.filePath;
    debugPrint(
        '📚 [PDF-DEBUG] _loadPdfHeadingsAndLinks START: title="$bookTitle" categoryId=$categoryId filePath="$filePath"');

    try {
      // טעינת headings מה-DB
      final headings = await PdfHeadings.loadFromDatabase(
        bookTitle,
        categoryId: categoryId,
        filePath: filePath,
      );
      if (headings != null) {
        widget.tab.pdfHeadings = headings;
        debugPrint(
            '📚 [PDF-DEBUG] pdfHeadings loaded: ${headings.headingsMap.length} entries. First 3: ${headings.headingsMap.entries.take(3).map((e) => "${e.key}→${e.value}").join(", ")}');
      } else {
        debugPrint('📚 [PDF-DEBUG] pdfHeadings NOT FOUND for "$bookTitle"');
      }

      // טעינת links
      final library = await DataRepository.instance.library;
      final allBooks = library.getAllBooks();
      debugPrint(
          '📚 [PDF-DEBUG] Library loaded: ${allBooks.length} total books');

      TextBook? textBook =
          library.findBookByTitle(bookTitle, TextBook) as TextBook?;
      debugPrint(
          '📚 [PDF-DEBUG] findBookByTitle("$bookTitle", TextBook) → ${textBook == null ? "NOT FOUND" : "FOUND: ${textBook.runtimeType}, categoryId=${textBook.categoryId}"}');

      if (textBook == null) {
        // ניסיון חיפוש גמיש
        textBook =
            library.findBookByTitleFlexible(bookTitle, TextBook) as TextBook?;
        debugPrint(
            '📚 [PDF-DEBUG] findBookByTitleFlexible → ${textBook == null ? "NOT FOUND" : "FOUND: ${textBook.title}"}');
        // הצג ספרים בשם דומה לעזרת דיבוג
        final similar = allBooks
            .where((b) =>
                b.runtimeType == TextBook &&
                b.title.contains(bookTitle.substring(
                    0, bookTitle.length > 5 ? 5 : bookTitle.length)))
            .take(5)
            .map((b) => '"${b.title}" (cat=${b.categoryId})')
            .toList();
        debugPrint('📚 [PDF-DEBUG] Similar TextBooks: $similar');
      }

      if (textBook != null) {
        final loadedLinks = await textBook.links
          ..sort((a, b) => a.index1.compareTo(b.index1));
        widget.tab.links = loadedLinks;
        final commentaryCount = loadedLinks
            .where((l) =>
                l.connectionType.toUpperCase() == 'COMMENTARY' ||
                l.connectionType.toUpperCase() == 'TARGUM')
            .length;
        _bookHasCommentaryLinks = commentaryCount > 0;
        debugPrint(
            '📚 [PDF-DEBUG] Links loaded: ${loadedLinks.length} total, $commentaryCount commentary/targum');
        if (loadedLinks.isNotEmpty) {
          debugPrint(
              '📚 [PDF-DEBUG] Links index1 range: ${loadedLinks.first.index1}–${loadedLinks.last.index1}');
        }
        await _loadCommentatorGroups();
      }

      final currentPage = widget.tab.pdfViewerController.isReady
          ? (widget.tab.pdfViewerController.pageNumber ?? widget.tab.pageNumber)
          : widget.tab.pageNumber;
      final currentTitle = await refFromPageNumber(
        currentPage,
        widget.tab.outline.value ?? const <PdfOutlineNode>[],
        widget.tab.book.title,
      );
      if (!mounted) return;
      widget.tab.currentTitle.value = currentTitle;
      final resolved = await _resolveTextLineNumberForPage(
        currentPage,
        resolvedTitle: currentTitle,
      );
      if (!mounted) return;
      widget.tab.currentTextLineNumber = resolved.start;
      widget.tab.currentTextLineNumberEnd = resolved.end;

      if (mounted) {
        _linksLoading = false;
        _maybeRegisterPdfCommentaryOpportunity();
        setState(() {});
      }
    } catch (e, stackTrace) {
      debugPrint(
          '📚 [PDF-DEBUG] ERROR in _loadPdfHeadingsAndLinks: $e\n$stackTrace');
      if (mounted) {
        _linksLoading = false;
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _stopContinuousScroll();
    _pointerScrollFlushTimer?.cancel();
    _disposePageTurnSnapshot();
    _disposeAllSpreadCache();
    _pendingPageTurns.clear();
    _pageTurnController.dispose();
    textSearcher?.removeListener(_onTextSearcherUpdated);
    pdfController.removeListener(_onPdfViewerControllerUpdate);
    _leftPaneTabController?.removeListener(_leftPaneTabControllerListener);
    widget.tab.showLeftPane.removeListener(_showLeftPaneListener);
    _leftPaneTabController?.dispose();
    _searchFieldFocusNode.dispose();
    _navigationFieldFocusNode.dispose();
    _pdfViewFocusNode.dispose();
    _settingsSub.cancel();
    _bloc.close();

    // לא מוחקים את הקובץ הזמני - הוא משותף בין tabs
    // הקבצים יימחקו אוטומטית כשהמערכת תנקה את temp directory

    super.dispose();
  }

  Future<void> _resetPerBookSettings() async {
    _bloc.add(const pdf_events.ResetPerBookSettings());
    widget.tab.activeCommentators.clear();
    if (mounted) {
      UiSnack.show('ההגדרות הפר-ספריות אופסו בהצלחה');
    }
  }

  int _lastComputedForPage = -1;
  int? _initialPageNumber; // שמירת מספר העמוד ההתחלתי
  bool _isJumping = false; // flag לציון שאנחנו בתהליך קפיצה
  bool _linksLoading = true; // true עד שטעינת הקישורים מסתיימת

  void _onPdfViewerControllerUpdate() async {
    if (!widget.tab.pdfViewerController.isReady) return;

    // Keep adjacent-spread pre-renders warm so page-turn animations can
    // open the cached snapshot instantly without waiting on goToPage + tile
    // loading. Cheap & idempotent — guarded by `_lastPrerenderTriggeredSpread`.
    _schedulePrerenderForAdjacentSpreads();

    final tourCubit = context.read<TourCubit>();
    widget.tab.savedZoom = widget.tab.pdfViewerController.value.zoom;

    final newPage = widget.tab.pdfViewerController.pageNumber ?? 1;

    // Once the controller's spread catches up to the most recently initiated
    // target, the staleness window is closed — clear the override so future
    // clicks read directly from the controller again.
    if (_lastInitiatedTargetPage != null) {
      final initiatedSpread = _spreadStartPageFor(_lastInitiatedTargetPage!);
      final newSpread = _spreadStartPageFor(newPage);
      if (initiatedSpread == newSpread) {
        _lastInitiatedTargetPage = null;
      }
    }
    // אם אנחנו בתהליך קפיצה, לא נעדכן את pageNumber
    if (_isJumping) {
      return;
    }

    // אם זו הפעם הראשונה וה-pageNumber המקורי גדול מ-1, לא נעדכן
    // (כי אנחנו עדיין ממתינים לקפיצה לעמוד הנכון)
    if (_initialPageNumber != null && _initialPageNumber! > 1 && newPage == 1) {
      return; // לא נאפס כדי להמשיך לחסום
    }

    if (newPage == widget.tab.pageNumber) return;
    widget.tab.pageNumber = newPage;
    final token = _lastComputedForPage = newPage;

    widget.tab.currentTitle.value = 'עמוד $newPage';

    final title = await refFromPageNumber(
        newPage, widget.tab.outline.value ?? [], widget.tab.book.title);
    if (!mounted) return;
    if (token == _lastComputedForPage) {
      widget.tab.currentTitle.value = title;

      final resolved = await _resolveTextLineNumberForPage(
        newPage,
        resolvedTitle: title,
      );
      if (!mounted) return;
      widget.tab.currentTextLineNumber = resolved.start;
      widget.tab.currentTextLineNumberEnd = resolved.end;
      _maybeRegisterPdfCommentaryOpportunity();
      tourCubit.recordInteraction(
        TourInteraction(
          type: TourInteractionType.readerPositionChanged,
          primaryValue: widget.tab.title,
        ),
      );
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return BlocProvider.value(
      value: _bloc,
      child: BlocListener<PdfBookBloc, PdfBookState>(
        listener: _onBlocStateChanged,
        child: _buildContent(context),
      ),
    );
  }

  void _onBlocStateChanged(BuildContext context, PdfBookState state) {}

  Widget _buildContent(BuildContext context) {
    final wideScreen = MediaQuery.of(context).size.width >= 600;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
            _ensureSearchTabIsActive,
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.equal):
            _zoomIn,
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.add):
            _zoomIn,
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.numpadAdd):
            _zoomIn,
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.minus):
            _zoomOut,
        LogicalKeySet(
                LogicalKeyboardKey.control, LogicalKeyboardKey.numpadSubtract):
            _zoomOut,
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
          shape: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 0.3,
            ),
          ),
          elevation: 0,
          scrolledUnderElevation: 0,
          title: ValueListenableBuilder(
            valueListenable: widget.tab.currentTitle,
            builder: (context, value, child) {
              String displayTitle = value;
              if (value.isNotEmpty && !value.contains(widget.tab.book.title)) {
                displayTitle = "${widget.tab.book.title}, $value";
              }
              return SelectionArea(
                child: Text(
                  displayTitle,
                  style: const TextStyle(fontSize: 17),
                  textAlign: TextAlign.end,
                ),
              );
            },
          ),
          leading: IconButton(
            key: widget.enableTourTargets
                ? pdfBookNavigationTourTargetKey
                : null,
            icon: const Icon(FluentIcons.navigation_24_regular),
            tooltip: 'חיפוש וניווט',
            onPressed: () {
              _setLeftPaneVisibility(!widget.tab.showLeftPane.value);
            },
          ),
          actions: _buildPdfActions(context, wideScreen),
        ),
        body: BlocBuilder<PdfBookBloc, PdfBookState>(
          buildWhen: (prev, curr) {
            if (prev is PdfBookLoaded && curr is PdfBookLoaded) {
              return prev.showLeftPane != curr.showLeftPane ||
                  prev.sidebarWidth != curr.sidebarWidth ||
                  prev.showRightPane != curr.showRightPane ||
                  prev.rightPaneWidth != curr.rightPaneWidth;
            }
            return true;
          },
          builder: (context, state) {
            final leftPaneWidth =
                state is PdfBookLoaded ? state.sidebarWidth : 300.0;
            final rightPaneWidth =
                state is PdfBookLoaded ? state.rightPaneWidth : 300.0;
            final showLeftPane =
                state is PdfBookLoaded ? state.showLeftPane : false;
            final showRightPane =
                state is PdfBookLoaded ? state.showRightPane : false;
            return DualAdaptiveReaderPane(
              mainContent: _buildReaderMainContent(),
              showLeftPane: showLeftPane,
              leftPaneContent: _buildLeftPaneContent(),
              leftPaneWidth: leftPaneWidth,
              leftMinPaneWidth: 200,
              leftMaxPaneWidth: 600,
              onLeftPaneWidthChanged: (nextWidth) {
                _bloc.add(pdf_events.UpdateSidebarWidth(nextWidth));
              },
              onCloseLeftPane: () => _setLeftPaneVisibility(false),
              onLeftPaneResizeEnd: () {
                final current = _bloc.state;
                if (current is PdfBookLoaded) {
                  context
                      .read<SettingsBloc>()
                      .add(UpdateSidebarWidth(current.sidebarWidth));
                }
              },
              showRightPane: showRightPane,
              rightPaneContent: _buildRightPaneContent(),
              rightPaneWidth: rightPaneWidth,
              rightMinPaneWidth: 250,
              rightMaxPaneWidth: 600,
              onRightPaneWidthChanged: (nextWidth) {
                _bloc.add(pdf_events.UpdateRightPaneWidth(nextWidth));
              },
              onCloseRightPane: () {
                _bloc.add(const pdf_events.ToggleRightPane(show: false));
              },
              onRightPaneResizeEnd: () {
                final current = _bloc.state;
                if (current is PdfBookLoaded) {
                  context
                      .read<SettingsBloc>()
                      .add(UpdateCommentaryPaneWidth(current.rightPaneWidth));
                }
              },
              minMainContentWidth: 200,
            );
          },
        ),
      ),
    );
  }

  Widget _buildReaderMainContent() {
    const readerContentPadding = EdgeInsets.only(
      right: _verticalScrollbarGutter + _scrollbarGutterGap,
      bottom: _horizontalScrollbarGutter + _scrollbarGutterGap,
    );

    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            _scheduleReaderFocusAndHidePaneIfNeeded();
            return false;
          },
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                if (HardwareKeyboard.instance.isControlPressed) {
                  return;
                }

                _queuePointerScroll(event);
                _scheduleReaderFocusAndHidePaneIfNeeded();
              }
            },
            onPointerPanZoomStart: (_) {
              _captureScrollAnchor();
              if (widget.tab.pdfViewerController.isReady) {
                _panZoomBaseMatrix =
                    widget.tab.pdfViewerController.value.clone();
              }
            },
            onPointerPanZoomUpdate: (event) {
              if (HardwareKeyboard.instance.isControlPressed) {
                return;
              }

              _applyPanZoomScroll(event);

              if (!(widget.tab.pinLeftPane.value ||
                  (Settings.getValue<bool>('key-pin-sidebar') ?? false))) {
                _setLeftPaneVisibility(false);
                Future.microtask(() {
                  _pdfViewFocusNode.requestFocus();
                });
              }
            },
            onPointerPanZoomEnd: (_) {
              _panZoomBaseMatrix = null;
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: readerContentPadding,
                  child: RepaintBoundary(
                    key: _pdfViewportBoundaryKey,
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.white,
                        Provider.of<SettingsBloc>(context, listen: true)
                                .state
                                .isDarkMode
                            ? BlendMode.difference
                            : BlendMode.dst,
                      ),
                      child: Stack(
                        children: [
                          _buildPdfViewerFromFile(widget.tab.book.path),
                          BlocBuilder<PdfBookBloc, PdfBookState>(
                            buildWhen: (prev, curr) {
                              if (prev is PdfBookLoaded &&
                                  curr is PdfBookLoaded) {
                                return prev.isLoading != curr.isLoading ||
                                    prev.loadSucceeded != curr.loadSucceeded;
                              }
                              return true;
                            },
                            builder: (context, state) {
                              if (state is PdfBookError) {
                                return const SizedBox.shrink();
                              }
                              if (state is! PdfBookLoaded || state.isLoading) {
                                return const Positioned.fill(
                                  child: ColoredBox(
                                    color: Color(0xFFFFFFFF),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                );
                              }
                              if (!state.loadSucceeded) {
                                return const Positioned.fill(
                                  child:
                                      Center(child: Text('Failed to load PDF')),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // שגיאת טעינה - מחוץ ל-ColorFiltered כדי שהצבעים יהיו נכונים
                BlocBuilder<PdfBookBloc, PdfBookState>(
                  buildWhen: (prev, curr) =>
                      (prev is PdfBookError) != (curr is PdfBookError),
                  builder: (context, state) {
                    if (state is! PdfBookError) return const SizedBox.shrink();
                    return Positioned.fill(
                      child: Padding(
                        padding: readerContentPadding,
                        child: ColoredBox(
                          color: Theme.of(context).colorScheme.surface,
                          child: Center(
                            child: Text(
                              state.message,
                              textDirection: TextDirection.rtl,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: readerContentPadding,
                  child: _buildPageTurnOverlay(context),
                ),
                PdfScrollbar(
                  controller: widget.tab.pdfViewerController,
                  orientation: ScrollbarOrientation.right,
                  trackThickness: _verticalScrollbarGutter,
                  thumbMinSize: 50.0,
                  scrollBoundsBuilder: _currentVerticalScrollbarBounds,
                  freezeThumb: _pageTurnTransition != null,
                ),
                Positioned(
                  left: 0,
                  right: readerContentPadding.right,
                  bottom: 0,
                  child: PdfHorizontalScrollbar(
                    controller: widget.tab.pdfViewerController,
                    trackThickness: _horizontalScrollbarGutter,
                  ),
                ),
              ],
            ),
          ),
        ),
        BlocBuilder<PdfBookBloc, PdfBookState>(
          buildWhen: (prev, curr) {
            if (prev is PdfBookLoaded && curr is PdfBookLoaded) {
              return prev.showRightPane != curr.showRightPane ||
                  prev.isRightPaneHovering != curr.isRightPaneHovering;
            }
            return true;
          },
          builder: (context, state) {
            if (state is! PdfBookLoaded || state.showRightPane) {
              return const SizedBox.shrink();
            }

            final isHovering = state.isRightPaneHovering;

            return Positioned(
              left: 0,
              top: MediaQuery.of(context).size.height * 0.10,
              child: MouseRegion(
                onEnter: (_) =>
                    _bloc.add(const pdf_events.SetRightPaneHovering(true)),
                onExit: (_) =>
                    _bloc.add(const pdf_events.SetRightPaneHovering(false)),
                child: GestureDetector(
                  onTap: _openCommentaryPane,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: isHovering ? 48 : 20,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: isHovering ? 0.95 : 0.8),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(40),
                        bottomRight: Radius.circular(40),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: isHovering ? 8 : 4,
                          offset: const Offset(2, 0),
                        ),
                      ],
                    ),
                    child: Center(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: isHovering ? 1.0 : 0.6,
                        child: Icon(
                          FluentIcons.chevron_right_24_regular,
                          size: isHovering ? 24 : 18,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        BlocBuilder<PdfBookBloc, PdfBookState>(
          buildWhen: (prev, curr) {
            if (prev is PdfBookLoaded && curr is PdfBookLoaded) {
              return prev.showZoomBar != curr.showZoomBar;
            }
            return true;
          },
          builder: (context, state) {
            final showZoomBar = state is PdfBookLoaded && state.showZoomBar;
            if (!showZoomBar || !widget.tab.pdfViewerController.isReady) {
              return const SizedBox.shrink();
            }
            return Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: PdfZoomBar(
                  currentZoom: widget.tab.pdfViewerController.value.zoom,
                  onZoomIn: _zoomIn,
                  onZoomOut: _zoomOut,
                  onResetZoom: _resetZoom,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLeftPaneContent() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _leftPaneTabController,
                  tabs: const [
                    Tab(
                      icon: Icon(FluentIcons.navigation_24_regular, size: 16),
                      iconMargin: EdgeInsets.only(bottom: 1),
                      height: 44,
                      child: Text('ניווט', style: TextStyle(fontSize: 11)),
                    ),
                    Tab(
                      icon: Icon(FluentIcons.search_24_regular, size: 16),
                      iconMargin: EdgeInsets.only(bottom: 1),
                      height: 44,
                      child: Text('חיפוש', style: TextStyle(fontSize: 11)),
                    ),
                    Tab(
                      icon: Icon(FluentIcons.document_multiple_24_regular,
                          size: 16),
                      iconMargin: EdgeInsets.only(bottom: 1),
                      height: 44,
                      child: Text('דפים', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  dividerColor: Colors.transparent,
                  splashBorderRadius: BorderRadius.circular(12),
                ),
              ),
              if (MediaQuery.of(context).size.width >= 600)
                ValueListenableBuilder(
                  valueListenable: widget.tab.pinLeftPane,
                  builder: (context, pinLeftPanel, child) => IconButton(
                    onPressed:
                        (Settings.getValue<bool>('key-pin-sidebar') ?? false)
                            ? null
                            : () {
                                widget.tab.pinLeftPane.value =
                                    !widget.tab.pinLeftPane.value;
                              },
                    icon: AnimatedRotation(
                      turns: (pinLeftPanel ||
                              (Settings.getValue<bool>('key-pin-sidebar') ??
                                  false))
                          ? -0.125
                          : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        (pinLeftPanel ||
                                (Settings.getValue<bool>('key-pin-sidebar') ??
                                    false))
                            ? FluentIcons.pin_24_filled
                            : FluentIcons.pin_24_regular,
                      ),
                    ),
                    color: (pinLeftPanel ||
                            (Settings.getValue<bool>('key-pin-sidebar') ??
                                false))
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    isSelected: pinLeftPanel ||
                        (Settings.getValue<bool>('key-pin-sidebar') ?? false),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _leftPaneTabController,
            children: [
              ValueListenableBuilder(
                valueListenable: widget.tab.outline,
                builder: (context, outline, child) => OutlineView(
                  outline: outline,
                  controller: widget.tab.pdfViewerController,
                  focusNode: _navigationFieldFocusNode,
                  onNavigateToPage: _goToPageWithSpreadLock,
                ),
              ),
              ValueListenableBuilder(
                valueListenable: widget.tab.documentRef,
                builder: (context, documentRef, child) {
                  if (widget.tab.searchController.text.isNotEmpty) {
                    _lastProcessedSearchSessionId = null;
                  }
                  return child!;
                },
                child: textSearcher != null
                    ? PdfBookSearchView(
                        textSearcher: textSearcher!,
                        searchController: widget.tab.searchController,
                        focusNode: _searchFieldFocusNode,
                        outline: widget.tab.outline.value,
                        bookTitle: widget.tab.book.title,
                        bookTopics: widget.tab.book.topics,
                        bookCategoryPath: widget.tab.book.categoryPath,
                        pdfFilePath: widget.tab.book.path,
                        initialSearchText: widget.tab.searchText,
                        initialSearchOptions: widget.tab.searchOptions,
                        initialAlternativeWords: widget.tab.alternativeWords,
                        initialSpacingValues: widget.tab.spacingValues,
                        initialSearchMode: widget.tab.searchMode,
                        initialSearchDistance: widget.tab.searchDistance,
                        onSearchResultNavigated: _ensureSearchTabIsActive,
                      )
                    : const Center(
                        child: CircularProgressIndicator(),
                      ),
              ),
              ValueListenableBuilder(
                valueListenable: widget.tab.documentRef,
                builder: (context, documentRef, child) => child!,
                child: ThumbnailsView(
                    documentRef: widget.tab.documentRef.value,
                    controller: widget.tab.pdfViewerController),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRightPaneContent() {
    return PdfCommentaryPanel(
      tab: widget.tab,
      linksCount: widget.tab.links.length,
      linksLoading: _linksLoading,
      openBookCallback: (tab) {
        if (tab is TextBookTab) {
          openBook(context, tab.book, tab.index, '', ignoreHistory: false);
        }
      },
      fontSize: 16.0,
      onClose: () {
        _bloc.add(const pdf_events.ToggleRightPane(show: false));
      },
      initialTabIndex: _rightPaneInitialTabIndex,
    );
  }

  void _zoomIn() {
    _bloc.add(const pdf_events.ZoomIn());
  }

  void _zoomOut() {
    _bloc.add(const pdf_events.ZoomOut());
  }

  void _resetZoom() {
    _bloc.add(const pdf_events.ResetZoom());
  }

  /// Returns the page that next/prev navigation should treat as the user's
  /// current position. When a navigation is in flight (cache-hit path runs
  /// goToPage in parallel with the animation, so `controller.pageNumber`
  /// lags), prefer the latest target we already initiated. Without this,
  /// rapid double-clicks compute the same target twice (controller still
  /// reports the pre-click page) and the second click animates without
  /// advancing the page.
  int _effectiveCurrentPageForNavigation() {
    final controller = widget.tab.pdfViewerController;
    return _lastInitiatedTargetPage ?? (controller.pageNumber ?? 1);
  }

  void _goNextPage() {
    if (!widget.tab.pdfViewerController.isReady) return;

    final isBookViewMode = _isBookViewModeActive();
    final basePage = _effectiveCurrentPageForNavigation();
    final totalPages = widget.tab.pdfViewerController.pageCount;
    final pageStep = isBookViewMode ? 2 : 1;
    final nextPage = min(basePage + pageStep, totalPages);

    if (nextPage == basePage) {
      return;
    }

    // Record the user-initiated target so the next click computes its own
    // target relative to this one — even if controller.pageNumber hasn't
    // updated yet (parallel goToPage in cache-hit flow).
    _lastInitiatedTargetPage = nextPage;

    if (isBookViewMode) {
      _animateBookPageTurn(
        targetPage: nextPage,
        direction: _BookPageTurnDirection.next,
      );
      return;
    }

    _goToPageWithSpreadLock(nextPage);
  }

  void _goPreviousPage() {
    if (!widget.tab.pdfViewerController.isReady) return;

    final isBookViewMode = _isBookViewModeActive();
    final basePage = _effectiveCurrentPageForNavigation();
    final pageStep = isBookViewMode ? 2 : 1;
    final prevPage = max(basePage - pageStep, 1);

    if (prevPage == basePage) {
      return;
    }

    _lastInitiatedTargetPage = prevPage;

    if (isBookViewMode) {
      _animateBookPageTurn(
        targetPage: prevPage,
        direction: _BookPageTurnDirection.previous,
      );
      return;
    }

    _goToPageWithSpreadLock(prevPage);
  }

  void _startContinuousScroll(LogicalKeyboardKey key) {
    if (_scrollTimer != null) return;

    _currentScrollKey = key;
    _captureScrollAnchor();

    if (key == LogicalKeyboardKey.arrowUp) {
      _scrollUpSimple();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _scrollDownSimple();
    }

    _scrollTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || !widget.tab.pdfViewerController.isReady) {
        _stopContinuousScroll();
        return;
      }

      if (!_pdfViewFocusNode.hasFocus) {
        _pdfViewFocusNode.requestFocus();
      }

      final isUpPressed = HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.arrowUp);
      final isDownPressed = HardwareKeyboard.instance.logicalKeysPressed
          .contains(LogicalKeyboardKey.arrowDown);

      if (_currentScrollKey == LogicalKeyboardKey.arrowUp && isUpPressed) {
        _scrollUpSimple();
      } else if (_currentScrollKey == LogicalKeyboardKey.arrowDown &&
          isDownPressed) {
        _scrollDownSimple();
      } else {
        _stopContinuousScroll();
      }
    });
  }

  void _stopContinuousScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _currentScrollKey = null;
    _scrollAnchorPage = null;

    if (mounted && !_pdfViewFocusNode.hasFocus) {
      _pdfViewFocusNode.requestFocus();
    }
  }

  void _captureScrollAnchor() {
    if (!widget.tab.pdfViewerController.isReady) return;
    _scrollAnchorPage = widget.tab.pdfViewerController.pageNumber ?? 1;
  }

  void _queuePointerScroll(PointerScrollEvent event) {
    if (!widget.tab.pdfViewerController.isReady) {
      return;
    }

    if (_pointerScrollFlushTimer == null) {
      _captureScrollAnchor();
    }

    _pendingPointerScrollDx += event.scrollDelta.dx;
    _pendingPointerScrollDy += event.scrollDelta.dy;
    _pointerScrollFlushTimer ??=
        Timer(_pointerScrollFlushDelay, _flushQueuedPointerScroll);
  }

  void _flushQueuedPointerScroll() {
    _pointerScrollFlushTimer = null;

    var remainingDeltaX = _pendingPointerScrollDx;
    var remainingDeltaY = _pendingPointerScrollDy;
    _pendingPointerScrollDx = 0.0;
    _pendingPointerScrollDy = 0.0;

    if (remainingDeltaX == 0.0 && remainingDeltaY == 0.0) {
      return;
    }

    while (remainingDeltaX != 0.0 || remainingDeltaY != 0.0) {
      final stepDeltaX = remainingDeltaX.clamp(
        -_maxPointerScrollBurstDelta,
        _maxPointerScrollBurstDelta,
      );
      final stepDeltaY = remainingDeltaY.clamp(
        -_maxPointerScrollBurstDelta,
        _maxPointerScrollBurstDelta,
      );

      _applyPointerScrollDelta(
        deltaX: stepDeltaX,
        deltaY: stepDeltaY,
      );

      remainingDeltaX -= stepDeltaX;
      remainingDeltaY -= stepDeltaY;
    }
  }

  void _applyPointerScrollDelta({
    required double deltaX,
    required double deltaY,
  }) {
    if (!widget.tab.pdfViewerController.isReady) return;

    final currentMatrix = widget.tab.pdfViewerController.value;
    final zoom = currentMatrix.zoom;
    final candidateMatrix = currentMatrix.clone()
      ..translateByDouble(
        -deltaX / zoom,
        -deltaY / zoom,
        0,
        1,
      );

    if (!_isBookViewModeActive()) {
      widget.tab.pdfViewerController.goTo(candidateMatrix);
      return;
    }

    final anchorPage =
        _scrollAnchorPage ?? (widget.tab.pdfViewerController.pageNumber ?? 1);
    final clampedMatrix = _clampMatrixToSpread(
      matrix: candidateMatrix,
      viewSize: widget.tab.pdfViewerController.viewSize,
      layout: widget.tab.pdfViewerController.layout,
      controller: widget.tab.pdfViewerController,
      spreadStartPage: _spreadStartPageFor(anchorPage),
    );

    widget.tab.pdfViewerController.goTo(clampedMatrix);

    if (_wasMatrixClamped(
      original: candidateMatrix,
      clamped: clampedMatrix,
      viewSize: widget.tab.pdfViewerController.viewSize,
    )) {
      _stopContinuousScroll();
    }
  }

  void _applyPanZoomScroll(PointerPanZoomUpdateEvent event) {
    if (!widget.tab.pdfViewerController.isReady) return;
    final baseMatrix = _panZoomBaseMatrix;
    if (baseMatrix == null) return;

    final candidateMatrix = baseMatrix.clone()
      ..translateByDouble(
        event.pan.dx,
        event.pan.dy,
        0,
        1,
      );

    if (!_isBookViewModeActive()) {
      widget.tab.pdfViewerController.goTo(candidateMatrix);
      return;
    }

    final anchorPage =
        _scrollAnchorPage ?? (widget.tab.pdfViewerController.pageNumber ?? 1);
    final clampedMatrix = _clampMatrixToSpread(
      matrix: candidateMatrix,
      viewSize: widget.tab.pdfViewerController.viewSize,
      layout: widget.tab.pdfViewerController.layout,
      controller: widget.tab.pdfViewerController,
      spreadStartPage: _spreadStartPageFor(anchorPage),
    );

    widget.tab.pdfViewerController.goTo(clampedMatrix);

    if (_wasMatrixClamped(
      original: candidateMatrix,
      clamped: clampedMatrix,
      viewSize: widget.tab.pdfViewerController.viewSize,
    )) {
      _stopContinuousScroll();
    }
  }

  void _applyVerticalScroll(double deltaY) {
    if (!widget.tab.pdfViewerController.isReady) return;

    final currentMatrix = widget.tab.pdfViewerController.value;
    final currentTranslation = currentMatrix.getTranslation();
    final candidateMatrix = currentMatrix.clone()
      ..setTranslationRaw(
        currentTranslation.x,
        currentTranslation.y + deltaY,
        currentTranslation.z,
      );

    if (!_isBookViewModeActive()) {
      widget.tab.pdfViewerController.goTo(candidateMatrix);
      return;
    }

    final anchorPage =
        _scrollAnchorPage ?? (widget.tab.pdfViewerController.pageNumber ?? 1);
    final clampedMatrix = _clampMatrixToSpread(
      matrix: candidateMatrix,
      viewSize: widget.tab.pdfViewerController.viewSize,
      layout: widget.tab.pdfViewerController.layout,
      controller: widget.tab.pdfViewerController,
      spreadStartPage: _spreadStartPageFor(anchorPage),
    );

    widget.tab.pdfViewerController.goTo(clampedMatrix);

    if (_wasMatrixClamped(
      original: candidateMatrix,
      clamped: clampedMatrix,
      viewSize: widget.tab.pdfViewerController.viewSize,
    )) {
      _stopContinuousScroll();
    }
  }

  void _scrollUpSimple() {
    const double scrollAmount = 100.0;
    _applyVerticalScroll(scrollAmount);
  }

  void _scrollDownSimple() {
    const double scrollAmount = 100.0;
    _applyVerticalScroll(-scrollAmount);
  }

  Future<void> navigateToUrl(Uri url) async {
    if (await shouldOpenUrl(context, url)) {
      await launchUrl(url);
    }
  }

  Future<bool> shouldOpenUrl(BuildContext context, Uri url) async {
    final result = await showDialog<bool?>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('לעבור לURL?'),
          content: SelectionArea(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'האם לעבור לכתובת הבאה\n'),
                  TextSpan(
                    text: url.toString(),
                    style: const TextStyle(color: Colors.blue),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ביטול'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('עבור'),
            ),
          ],
        );
      },
    );

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _pdfViewFocusNode.requestFocus();
        }
      });
    }

    return result ?? false;
  }

  List<Widget> _buildPdfActions(BuildContext context, bool wideScreen) {
    final screenWidth = MediaQuery.of(context).size.width;

    int maxButtons;

    if (screenWidth < 400) {
      maxButtons = 2;
    } else if (screenWidth < 500) {
      maxButtons = 4;
    } else if (screenWidth < 600) {
      maxButtons = 6;
    } else if (screenWidth < 700) {
      maxButtons = 8;
    } else if (screenWidth < 900) {
      maxButtons = 10;
    } else {
      maxButtons = 999;
    }

    return [
      ResponsiveActionBar(
        key: const ValueKey('pdf_actions'),
        overflowMenuOffset: const Offset(0, 8),
        overflowButtonKey:
            widget.enableTourTargets ? pdfBookOverflowTourTargetKey : null,
        menuItemKeysByTooltip: widget.enableTourTargets
            ? {
                'הוסף סימניה': pdfBookOverflowBookmarkTourTargetKey,
                'חיפוש': pdfBookOverflowSearchTourTargetKey,
                'הדפס': pdfBookOverflowPrintTourTargetKey,
              }
            : null,
        actions: _buildDisplayOrderPdfActions(context),
        alwaysInMenu: _buildAlwaysInMenuPdfActions(context),
        maxVisibleButtons: maxButtons,
      ),
    ];
  }

  List<ActionButtonData> _buildDisplayOrderPdfActions(BuildContext context) {
    return [
      ActionButtonData(
        widget: _buildTextButton(
            context, widget.tab.book, widget.tab.pdfViewerController),
        icon: FluentIcons.document_text_24_regular,
        tooltip: 'פתח ספר במהדורת טקסט',
        onPressed: () => _handleTextButtonPress(context),
      ),
      ActionButtonData(
        widget: BlocBuilder<PdfBookBloc, PdfBookState>(
          bloc: _bloc,
          builder: (context, state) {
            if (state is! PdfBookLoaded) return const SizedBox.shrink();
            return _buildLayoutModeDropdown(context, state);
          },
        ),
        icon: FluentIcons.book_open_24_regular,
        tooltip: 'מצב תצוגה',
        onPressed: null,
      ),
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.zoom_in_24_regular),
          tooltip: 'הגדל את גודל הטקסט',
          onPressed: _zoomIn,
        ),
        icon: FluentIcons.zoom_in_24_regular,
        tooltip: 'הגדל את גודל הטקסט',
        onPressed: _zoomIn,
      ),
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.zoom_out_24_regular),
          tooltip: 'הקטן את גודל הטקסט',
          onPressed: _zoomOut,
        ),
        icon: FluentIcons.zoom_out_24_regular,
        tooltip: 'הקטן את גודל הטקסט',
        onPressed: _zoomOut,
      ),
      ActionButtonData(
        widget: IconButton(
          key: widget.enableTourTargets ? pdfBookSearchTourTargetKey : null,
          icon: const Icon(FluentIcons.search_24_regular),
          tooltip: 'חיפוש',
          onPressed: _ensureSearchTabIsActive,
        ),
        icon: FluentIcons.search_24_regular,
        tooltip: 'חיפוש',
        onPressed: _ensureSearchTabIsActive,
      ),
      if (!widget.isInCombinedView) ...[
        ActionButtonData(
          widget: IconButton(
            icon: const Icon(FluentIcons.arrow_previous_24_filled),
            tooltip: 'תחילת הספר (CTRL + HOME)',
            onPressed: () => _goToPageWithSpreadLock(1),
          ),
          icon: FluentIcons.arrow_previous_24_filled,
          tooltip: 'תחילת הספר (CTRL + HOME)',
          onPressed: () => _goToPageWithSpreadLock(1),
        ),
        ActionButtonData(
          widget: IconButton(
            icon: const Icon(FluentIcons.chevron_left_24_regular),
            tooltip: 'הקודם',
            onPressed: _goPreviousPage,
          ),
          icon: FluentIcons.chevron_left_24_regular,
          tooltip: 'הקודם',
          onPressed: _goPreviousPage,
        ),
        ActionButtonData(
          widget: PageNumberDisplay(controller: widget.tab.pdfViewerController),
          icon: FluentIcons.text_font_24_regular,
          tooltip: 'מספר עמוד',
          onPressed: null,
        ),
        ActionButtonData(
          widget: IconButton(
            onPressed: _goNextPage,
            icon: const Icon(FluentIcons.chevron_right_24_regular),
            tooltip: 'הבא',
          ),
          icon: FluentIcons.chevron_right_24_regular,
          tooltip: 'הבא',
          onPressed: _goNextPage,
        ),
        ActionButtonData(
          widget: IconButton(
            icon: const Icon(FluentIcons.arrow_next_24_filled),
            tooltip: 'סוף הספר (CTRL + END)',
            onPressed: () => _goToPageWithSpreadLock(
                widget.tab.pdfViewerController.pageCount),
          ),
          icon: FluentIcons.arrow_next_24_filled,
          tooltip: 'סוף הספר (CTRL + END)',
          onPressed: () =>
              _goToPageWithSpreadLock(widget.tab.pdfViewerController.pageCount),
        ),
      ],
    ];
  }

  List<ActionButtonData> _buildAlwaysInMenuPdfActions(BuildContext context) {
    return [
      if (widget.isInCombinedView) ...[
        ActionButtonData(
          widget: IconButton(
            icon: const Icon(FluentIcons.arrow_previous_24_filled),
            tooltip: 'תחילת הספר (CTRL + HOME)',
            onPressed: () => _goToPageWithSpreadLock(1),
          ),
          icon: FluentIcons.arrow_previous_24_filled,
          tooltip: 'תחילת הספר (CTRL + HOME)',
          onPressed: () => _goToPageWithSpreadLock(1),
        ),
        ActionButtonData(
          widget: IconButton(
            icon: const Icon(FluentIcons.chevron_left_24_regular),
            tooltip: 'הקודם',
            onPressed: _goPreviousPage,
          ),
          icon: FluentIcons.chevron_left_24_regular,
          tooltip: 'הקודם',
          onPressed: _goPreviousPage,
        ),
        ActionButtonData(
          widget: IconButton(
            onPressed: _goNextPage,
            icon: const Icon(FluentIcons.chevron_right_24_regular),
            tooltip: 'הבא',
          ),
          icon: FluentIcons.chevron_right_24_regular,
          tooltip: 'הבא',
          onPressed: _goNextPage,
        ),
        ActionButtonData(
          widget: IconButton(
            icon: const Icon(FluentIcons.arrow_next_24_filled),
            tooltip: 'סוף הספר (CTRL + END)',
            onPressed: () => _goToPageWithSpreadLock(
                widget.tab.pdfViewerController.pageCount),
          ),
          icon: FluentIcons.arrow_next_24_filled,
          tooltip: 'סוף הספר (CTRL + END)',
          onPressed: () =>
              _goToPageWithSpreadLock(widget.tab.pdfViewerController.pageCount),
        ),
      ],
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.note_24_regular),
          tooltip: 'הצג הערות אישיות',
          onPressed: () {
            setState(() {
              _rightPaneInitialTabIndex = 2;
            });
            _bloc.add(const pdf_events.ToggleRightPane(show: true));
          },
        ),
        icon: FluentIcons.note_24_regular,
        tooltip: 'הצג הערות אישיות',
        onPressed: () {
          setState(() {
            _rightPaneInitialTabIndex = 2;
          });
          _bloc.add(const pdf_events.ToggleRightPane(show: true));
        },
      ),
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.note_add_24_regular),
          tooltip: 'הוסף הערה לעמוד זה',
          onPressed: () => _handleAddNotePress(context),
        ),
        icon: FluentIcons.note_add_24_regular,
        tooltip: 'הוסף הערה לעמוד זה',
        onPressed: () => _handleAddNotePress(context),
      ),
      ActionButtonData(
        widget: IconButton(
          key: widget.enableTourTargets ? pdfBookBookmarkTourTargetKey : null,
          icon: const Icon(FluentIcons.bookmark_add_24_regular),
          tooltip: 'הוסף סימניה',
          onPressed: () => _handleBookmarkPress(context),
        ),
        icon: FluentIcons.bookmark_add_24_regular,
        tooltip: 'הוסף סימניה',
        onPressed: () => _handleBookmarkPress(context),
      ),
      if (!widget.isInCombinedView &&
          context.read<SettingsBloc>().state.enablePerBookSettings)
        ActionButtonData(
          widget: IconButton(
            icon: const Icon(FluentIcons.arrow_reset_24_regular),
            tooltip: 'אפס הגדרות ספר זה',
            onPressed: () => _resetPerBookSettings(),
          ),
          icon: FluentIcons.arrow_reset_24_regular,
          tooltip: 'אפס הגדרות ספר זה',
          onPressed: () => _resetPerBookSettings(),
        ),
      if (!widget.isInCombinedView)
        ActionButtonData(
          widget: IconButton(
            key: widget.enableTourTargets ? pdfBookPrintTourTargetKey : null,
            icon: const Icon(FluentIcons.print_24_regular),
            tooltip: 'הדפס',
            onPressed: () => _handlePrintPress(context),
          ),
          icon: FluentIcons.print_24_regular,
          tooltip: 'הדפס',
          onPressed: () => _handlePrintPress(context),
        ),
      if (widget.isInCombinedView)
        ActionButtonData(
          widget: const SizedBox.shrink(),
          icon: FluentIcons.more_horizontal_24_regular,
          tooltip: 'פעולות נוספות',
          onPressed: null,
          submenuItems: [
            if (context.read<SettingsBloc>().state.enablePerBookSettings)
              ActionButtonData(
                widget: const SizedBox.shrink(),
                icon: FluentIcons.arrow_reset_24_regular,
                tooltip: 'אפס הגדרות ספר זה',
                onPressed: () => _resetPerBookSettings(),
              ),
            ActionButtonData(
              widget: const SizedBox.shrink(),
              icon: FluentIcons.print_24_regular,
              tooltip: 'הדפס',
              onPressed: () => _handlePrintPress(context),
            ),
          ],
        ),
    ];
  }

  Future<void> _handleTextButtonPress(BuildContext context) async {
    final currentPage = widget.tab.pdfViewerController.isReady
        ? widget.tab.pdfViewerController.pageNumber ?? 1
        : widget.tab.pageNumber;
    widget.tab.pageNumber = currentPage;
    final currentOutline = widget.tab.outline.value ?? [];

    final library = await DataRepository.instance.library;
    final textBook = library.findBookByTitle(widget.tab.book.title, TextBook);
    if (textBook == null) return;

    if (!context.mounted) return;

    final index = await pdfToTextPage(
        widget.tab.book, currentOutline, currentPage, context);

    if (!context.mounted) return;

    openBook(context, textBook, index ?? 0, '', ignoreHistory: true);
  }

  void _handleBookmarkPress(BuildContext context) {
    if (!mounted) return;
    int index = widget.tab.pdfViewerController.isReady
        ? (widget.tab.pdfViewerController.pageNumber ?? 1)
        : 1;

    String ref;
    final outline = widget.tab.outline.value;
    if (outline != null && outline.isNotEmpty) {
      final heading = _findHeadingForPage(outline, index);
      if (heading != null) {
        ref = '${widget.tab.title} $heading';
      } else {
        ref = '${widget.tab.title} עמוד $index';
      }
    } else {
      ref = '${widget.tab.title} עמוד $index';
    }

    try {
      bool bookmarkAdded = context
          .read<BookmarkBloc>()
          .addBookmark(ref: ref, book: widget.tab.book, index: index);
      if (mounted) {
        UiSnack.show(
            bookmarkAdded ? 'הסימניה נוספה בהצלחה' : 'הסימניה כבר קיימת');
      }
    } catch (e) {
      debugPrint('Error adding bookmark: $e');
      if (mounted) {
        UiSnack.show('שגיאה בהוספת הסימניה');
      }
    }

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _pdfViewFocusNode.requestFocus();
        }
      });
    }
  }

  String? _findHeadingForPage(List<PdfOutlineNode> outline, int page) {
    PdfOutlineNode? bestMatch;

    void searchNodes(List<PdfOutlineNode> nodes) {
      for (final node in nodes) {
        final nodePage = node.dest?.pageNumber;
        if (nodePage != null && nodePage <= page) {
          if (bestMatch == null ||
              nodePage > (bestMatch!.dest?.pageNumber ?? 0)) {
            bestMatch = node;
          }
          if (node.children.isNotEmpty) {
            searchNodes(node.children);
          }
        }
      }
    }

    searchNodes(outline);
    return bestMatch?.title;
  }

  Future<void> _handleAddNotePress(BuildContext context) async {
    final currentPage = widget.tab.pdfViewerController.isReady
        ? (widget.tab.pdfViewerController.pageNumber ?? 1)
        : 1;

    final notesBloc = context.read<PersonalNotesBloc>();

    final library = await DataRepository.instance.library;
    final textBook = library.findBookByTitle(widget.tab.book.title, TextBook);

    String dialogTitle = 'הוסף הערה לעמוד $currentPage';
    if (textBook != null && widget.tab.pdfHeadings != null) {
      final currentTitle = widget.tab.currentTitle.value;
      final currentLineNumber =
          widget.tab.pdfHeadings!.getLineNumberForHeading(currentTitle);

      if (currentLineNumber != null) {
        final sortedHeadings = widget.tab.pdfHeadings!.getSortedHeadings();
        final currentIndex =
            sortedHeadings.indexWhere((e) => e.value == currentLineNumber);

        if (currentIndex != -1) {
          final nextLineNumber = currentIndex < sortedHeadings.length - 1
              ? sortedHeadings[currentIndex + 1].value
              : null;

          if (nextLineNumber != null) {
            dialogTitle =
                'הוסף הערה לעמוד $currentPage\n(שורות $currentLineNumber-${nextLineNumber - 1} בטקסט)';
          } else {
            dialogTitle =
                'הוסף הערה לעמוד $currentPage\n(משורה $currentLineNumber בטקסט)';
          }
        }
      }
    }

    if (!mounted) return;

    final draftService = PersonalNoteDraftService();
    final draft = await draftService.loadDraft(
      bookId: widget.tab.book.title,
      lineNumber: currentPage,
    );

    if (!context.mounted) return;

    final noteContent = await showDialog<PersonalNoteEditorResult>(
      context: context,
      builder: (context) => PersonalNoteEditorDialog(
        title: dialogTitle,
        bookId: widget.tab.book.title,
        categoryId: widget.tab.book.categoryId,
        draftLineNumber: currentPage,
        initialContent: draft?.content ?? '',
        initialContentFormat:
            draft?.contentFormat ?? PersonalNoteContentFormat.plain,
        linkableNotes: [
          ...notesBloc.state.locatedNotes,
          ...notesBloc.state.missingNotes,
        ],
      ),
    );

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _pdfViewFocusNode.requestFocus();
        }
      });
    }

    if (!mounted) return;

    if (noteContent == null) {
      return;
    }

    final trimmed = noteContent.contentPlain.trim();
    if (trimmed.isEmpty) {
      UiSnack.show('ההערה ריקה, לא נשמרה');
      return;
    }

    if (!mounted) return;

    try {
      final bookId = widget.tab.book.title;

      notesBloc.add(AddPersonalNote(
        bookId: bookId,
        lineNumber: currentPage,
        content: noteContent.content,
        contentPlain: noteContent.contentPlain,
        contentFormat: noteContent.contentFormat,
      ));

      setState(() {
        _rightPaneInitialTabIndex = 2;
      });
      _bloc.add(const pdf_events.ToggleRightPane(show: true));

      await Future.delayed(const Duration(milliseconds: 100));

      if (textBook != null) {
        UiSnack.show('ההערה נשמרה ותוצג בכל שורות העמוד בתצוגת הטקסט');
      } else {
        UiSnack.show('ההערה נשמרה בהצלחה');
      }
    } catch (e) {
      debugPrint('Error adding note: $e');
      UiSnack.showError('שמירת ההערה נכשלה: $e');
    }
  }

  Future<void> _handlePrintPress(BuildContext context) async {
    if (!context.mounted) return;
    final file = File(widget.tab.book.path);
    final currentPage = widget.tab.pdfViewerController.isReady
        ? (widget.tab.pdfViewerController.pageNumber ?? widget.tab.pageNumber)
        : widget.tab.pageNumber;
    final currentLayoutMode = switch (_bloc.state) {
      PdfBookInitial initial => initial.layoutMode,
      PdfBookLoaded loaded => loaded.layoutMode,
      _ => PdfLayoutMode.regularView,
    };
    final initialPrintPage = resolveInitialPdfPrintPage(
      currentPage: currentPage,
      layoutMode: currentLayoutMode,
    );
    setState(() => _pdfViewerSuspended = true);
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PrintingScreen(
        data: Future.value(''),
        bookId: widget.tab.book.title,
        createPdfOverride: (_) => file.readAsBytes(),
        initialPage: initialPrintPage,
        isBookView: currentLayoutMode == PdfLayoutMode.bookView,
        pdfOutline: widget.tab.outline.value ?? [],
      ),
    );
    if (mounted) {
      try {
        // Always reset the pdfrx worker when leaving the print screen:
        // - If printing happened: FPDF_DestroyLibrary() was called by the printing plugin,
        //   corrupting the shared PDFium state that pdfrx depends on.
        // - If preview loading was stuck: the worker may be blocked on PdfDocument.openData.
        // A 3-second timeout ensures _pdfViewerSuspended is always cleared even if the
        // worker is unresponsive.
        await PdfrxEntryFunctions.instance
            .stopBackgroundWorker()
            .timeout(const Duration(seconds: 3));
      } catch (_) {
      } finally {
        if (mounted) {
          setState(() => _pdfViewerSuspended = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _pdfViewFocusNode.requestFocus();
          });
        }
      }
    }
  }

  Widget _buildTextButton(
      BuildContext context, PdfBook book, PdfViewerController controller) {
    return FutureBuilder(
      future: DataRepository.instance.library
          .then((library) => library.findBookByTitle(book.title, TextBook)),
      builder: (context, snapshot) => snapshot.hasData
          ? IconButton(
              icon: const Icon(FluentIcons.document_text_24_regular),
              tooltip: 'פתח ספר במהדורת טקסט',
              onPressed: () async {
                final currentPage = controller.isReady
                    ? controller.pageNumber ?? 1
                    : widget.tab.pageNumber;
                widget.tab.pageNumber = currentPage;
                final currentOutline = widget.tab.outline.value ?? [];

                final index = await pdfToTextPage(
                    book, currentOutline, currentPage, context);

                if (!context.mounted) return;

                openBook(context, snapshot.data!, index ?? 0, '',
                    ignoreHistory: true);
              })
          : const SizedBox.shrink(),
    );
  }

  Widget _buildLayoutModeDropdown(BuildContext context, PdfBookLoaded state) {
    final isBookViewMode = state.layoutMode == PdfLayoutMode.bookView;

    return PopupMenuButton<PdfLayoutMode>(
      tooltip: 'בחר מצב תצוגה',
      icon: Icon(
        isBookViewMode
            ? FluentIcons.book_open_24_regular
            : FluentIcons.book_24_regular,
      ),
      position: PopupMenuPosition.under,
      onSelected: (layoutMode) {
        _lockedSpreadStartPage = null;

        final settingsBloc = context.read<SettingsBloc>();
        if (!settingsBloc.state.enablePerBookSettings) {
          settingsBloc.add(
            UpdatePdfBookViewByDefault(layoutMode == PdfLayoutMode.bookView),
          );
        }

        _bloc.add(pdf_events.SetLayoutMode(layoutMode));
      },
      itemBuilder: (context) {
        final primaryColor = Theme.of(context).colorScheme.primary;

        PopupMenuItem<PdfLayoutMode> buildItem({
          required PdfLayoutMode value,
          required String text,
          required IconData icon,
          required bool isSelected,
        }) {
          final style = isSelected ? TextStyle(color: primaryColor) : null;
          return PopupMenuItem<PdfLayoutMode>(
            value: value,
            child: Row(
              children: [
                Icon(icon, color: isSelected ? primaryColor : null),
                const SizedBox(width: 12),
                Text(text, style: style, textDirection: TextDirection.rtl),
                if (isSelected) ...[
                  const Spacer(),
                  Icon(FluentIcons.checkmark_24_regular,
                      size: 16, color: primaryColor),
                ],
              ],
            ),
          );
        }

        return [
          buildItem(
            value: PdfLayoutMode.regularView,
            text: 'תצוגה רגילה',
            icon: FluentIcons.book_24_regular,
            isSelected: !isBookViewMode,
          ),
          buildItem(
            value: PdfLayoutMode.bookView,
            text: 'תצוגת ספר',
            icon: FluentIcons.book_open_24_regular,
            isSelected: isBookViewMode,
          ),
        ];
      },
    );
  }
}

// ============================================================
// Helper classes for book view spread visualization
// ============================================================

enum _BookPageTurnDirection { next, previous }

class _PendingBookPageTurn {
  final int targetPage;
  final _BookPageTurnDirection direction;

  const _PendingBookPageTurn({
    required this.targetPage,
    required this.direction,
  });
}

class _BookPageTurnTransition {
  final _BookPageTurnDirection direction;
  final Rect viewportRect;
  final Size viewportLogicalSize;

  const _BookPageTurnTransition({
    required this.direction,
    required this.viewportRect,
    required this.viewportLogicalSize,
  });
}

/// Holds pre-rendered images for the pages of a single book-view spread.
/// The animation flow composites these page images into a viewport-sized
/// snapshot on demand (cheap, ~5-15ms) instead of waiting on goToPage +
/// tile loading + viewport capture (~150-250ms total).
class _PdfSpreadCacheEntry {
  final Map<int, ui.Image> pageImages;

  _PdfSpreadCacheEntry({required this.pageImages});

  void dispose() {
    for (final image in pageImages.values) {
      image.dispose();
    }
  }
}

class _BookViewViewportMaskPainter extends CustomPainter {
  final Rect spreadViewportRect;

  const _BookViewViewportMaskPainter(this.spreadViewportRect);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;

    if (spreadViewportRect.top > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, spreadViewportRect.top),
        paint,
      );
    }
    if (spreadViewportRect.left > 0) {
      canvas.drawRect(
        Rect.fromLTWH(
          0,
          spreadViewportRect.top,
          spreadViewportRect.left,
          spreadViewportRect.height,
        ),
        paint,
      );
    }
    if (spreadViewportRect.right < size.width) {
      canvas.drawRect(
        Rect.fromLTWH(
          spreadViewportRect.right,
          spreadViewportRect.top,
          size.width - spreadViewportRect.right,
          spreadViewportRect.height,
        ),
        paint,
      );
    }
    if (spreadViewportRect.bottom < size.height) {
      canvas.drawRect(
        Rect.fromLTWH(
          0,
          spreadViewportRect.bottom,
          size.width,
          size.height - spreadViewportRect.bottom,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BookViewViewportMaskPainter oldDelegate) =>
      oldDelegate.spreadViewportRect != spreadViewportRect;
}

class _VisibleBookPage {
  final int pageNumber;
  final Rect viewportRect;
  final bool isLeftPage;
  final int outerStackPages;

  const _VisibleBookPage({
    required this.pageNumber,
    required this.viewportRect,
    required this.isLeftPage,
    required this.outerStackPages,
  });
}

class _BookSpreadPainter extends CustomPainter {
  final List<_VisibleBookPage> pages;
  final Color pageEdgeColor;
  final Color stackColor;
  final Color stackShadowColor;
  final Color spineColor;

  const _BookSpreadPainter({
    required this.pages,
    required this.pageEdgeColor,
    required this.stackColor,
    required this.stackShadowColor,
    required this.spineColor,
  });

  static const double _layerOffsetX = 1.4;
  static const double _layerOffsetY = 0.85;
  static const double _pageEdgeInset = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    for (final page in pages) {
      _paintOuterStack(canvas, page);
    }

    if (pages.length == 2) {
      final spineX =
          (pages[0].viewportRect.right + pages[1].viewportRect.left) / 2;
      final top = min(pages[0].viewportRect.top, pages[1].viewportRect.top);
      final bottom =
          max(pages[0].viewportRect.bottom, pages[1].viewportRect.bottom);
      final spinePaint = Paint()
        ..color = spineColor
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(spineX, top), Offset(spineX, bottom), spinePaint);
    }

    canvas.restore();
  }

  void _paintOuterStack(Canvas canvas, _VisibleBookPage page) {
    final layerCount = _stackLayerCount(page.outerStackPages);
    if (layerCount == 0) return;

    final rect = page.viewportRect;
    final direction = page.isLeftPage ? -1.0 : 1.0;
    final baseShadowPaint = Paint()
      ..color = stackShadowColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (var i = layerCount; i >= 1; i--) {
      final offsetX = direction * i * _layerOffsetX;
      final offsetY = i * _layerOffsetY;
      final outerX =
          page.isLeftPage ? rect.left + offsetX : rect.right + offsetX;
      final sidePath = Path()
        ..moveTo(
          page.isLeftPage
              ? rect.left + _pageEdgeInset
              : rect.right - _pageEdgeInset,
          rect.top,
        )
        ..lineTo(outerX, rect.top + offsetY)
        ..lineTo(outerX, rect.bottom + offsetY)
        ..lineTo(
          page.isLeftPage
              ? rect.left + _pageEdgeInset
              : rect.right - _pageEdgeInset,
          rect.bottom,
        )
        ..close();

      final alphaFactor = 0.22 + ((layerCount - i) * 0.06);
      final fillPaint = Paint()
        ..color = stackColor.withValues(alpha: alphaFactor.clamp(0.0, 0.55))
        ..style = PaintingStyle.fill;
      canvas.drawPath(sidePath, fillPaint);
      canvas.drawPath(sidePath, baseShadowPaint);
    }

    final edgePaint = Paint()
      ..color = pageEdgeColor.withValues(alpha: 0.38)
      ..strokeWidth = 1.0;
    final edgeX = page.isLeftPage ? rect.left : rect.right;
    canvas.drawLine(
        Offset(edgeX, rect.top), Offset(edgeX, rect.bottom), edgePaint);
  }

  int _stackLayerCount(int pagesCount) {
    if (pagesCount <= 0) return 0;
    return ((pagesCount / 36).ceil()).clamp(1, 10);
  }

  @override
  bool shouldRepaint(_BookSpreadPainter oldDelegate) =>
      oldDelegate.pages != pages ||
      oldDelegate.pageEdgeColor != pageEdgeColor ||
      oldDelegate.stackColor != stackColor ||
      oldDelegate.stackShadowColor != stackShadowColor ||
      oldDelegate.spineColor != spineColor;
}

/// Full-viewport background painter for the page-turn animation.
///
/// Draws the pre-animation snapshot over the **entire** viewer area, but
/// punches a transparent hole in the portion of the spread that has already
/// been revealed by the animation — so the new PDF pages show through there
/// while the rest of the viewer still shows the old snapshot.
class _BookPageTurnBackgroundPainter extends CustomPainter {
  final ui.Image snapshot;
  final ui.Image? targetSnapshot;

  /// Position of the spread (book pages) inside the full viewer, in logical
  /// pixels of the viewer's coordinate space.
  final Rect spreadRect;
  final double progress;
  final _BookPageTurnDirection direction;
  final Color shadowColor;
  final Color edgeColor;

  const _BookPageTurnBackgroundPainter({
    required this.snapshot,
    required this.targetSnapshot,
    required this.spreadRect,
    required this.progress,
    required this.direction,
    required this.shadowColor,
    required this.edgeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final destRect = Offset.zero & size;
    final sourceRect = Rect.fromLTWH(
      0,
      0,
      snapshot.width.toDouble(),
      snapshot.height.toDouble(),
    );

    final revealedPath = _computeRevealedPath();
    final revealedEdgeX = _computeRevealedEdgeX();

    if (revealedPath == null) {
      // Nothing revealed yet — draw full snapshot without clipping.
      canvas.drawImageRect(snapshot, sourceRect, destRect, Paint());
      return;
    }

    // Draw snapshot everywhere EXCEPT the revealed portion of the spread.
    // Using an even-odd path (outer rect + hole rect) as a clip means the
    // inner (hole) region is not drawn into — the new PDF shows through there.
    canvas.save();
    final clipPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(destRect)
      ..addPath(revealedPath, Offset.zero);
    canvas.clipPath(clipPath);
    canvas.drawImageRect(snapshot, sourceRect, destRect, Paint());
    canvas.restore();

    final target = targetSnapshot;
    if (target != null) {
      canvas.save();
      canvas.clipPath(revealedPath);
      canvas.drawImageRect(
        target,
        Rect.fromLTWH(
          0,
          0,
          target.width.toDouble(),
          target.height.toDouble(),
        ),
        destRect,
        Paint(),
      );
      canvas.restore();
    }

    if (revealedEdgeX != null) {
      _paintRevealedPageEdge(canvas, revealedEdgeX);
    }
  }

  void _paintRevealedPageEdge(Canvas canvas, double edgeX) {
    final isNext = direction == _BookPageTurnDirection.next;
    final shadowWidth = min(spreadRect.width * 0.045, 34.0);
    final shadowRect = isNext
        ? Rect.fromLTWH(
            edgeX - shadowWidth, spreadRect.top, shadowWidth, spreadRect.height)
        : Rect.fromLTWH(edgeX, spreadRect.top, shadowWidth, spreadRect.height);

    canvas.drawRect(
      shadowRect,
      Paint()
        ..shader = LinearGradient(
          begin: isNext ? Alignment.centerRight : Alignment.centerLeft,
          end: isNext ? Alignment.centerLeft : Alignment.centerRight,
          colors: [
            shadowColor.withValues(alpha: 0.16),
            shadowColor.withValues(alpha: 0.0),
          ],
        ).createShader(shadowRect),
    );

    canvas.drawLine(
      Offset(edgeX, spreadRect.top),
      Offset(edgeX, spreadRect.bottom),
      Paint()
        ..color = edgeColor.withValues(alpha: 0.52)
        ..strokeWidth = 1,
    );
  }

  /// Returns the portion of the spread rect that the animation has already
  /// swept past (where the new page should be visible).
  Path? _computeRevealedPath() {
    if (progress <= 0.0 || spreadRect.isEmpty) {
      return null;
    }

    final viewportRect = Offset.zero & spreadRect.size;
    final turnLeftPage = direction == _BookPageTurnDirection.next;
    final isFrontFace = progress <= 0.5;
    final pageWidth = viewportRect.width / 2;
    final angle = progress * pi;
    final projectedWidth = max(8.0, pageWidth * cos(angle).abs());
    final pageRect = _turningPageDestinationRect(
      spineX: viewportRect.center.dx,
      projectedWidth: projectedWidth,
      height: viewportRect.height,
      turnLeftPage: turnLeftPage,
      isFrontFace: isFrontFace,
    );

    if (pageRect.width <= 1) {
      return Path()..addRect(spreadRect);
    }

    final path = Path();
    final revealedEdgeX = _computeLocalRevealedEdgeX(pageRect, isFrontFace);
    if (direction == _BookPageTurnDirection.next) {
      final revealedWidth = revealedEdgeX.clamp(0.0, viewportRect.width);
      if (revealedWidth > 0) {
        path.addRect(
          Rect.fromLTWH(
            spreadRect.left,
            spreadRect.top,
            revealedWidth,
            spreadRect.height,
          ),
        );
      }
    } else {
      final revealedLeft = revealedEdgeX.clamp(0.0, viewportRect.width);
      final revealedWidth = viewportRect.width - revealedLeft;
      if (revealedWidth > 0) {
        path.addRect(
          Rect.fromLTWH(
            spreadRect.left + revealedLeft,
            spreadRect.top,
            revealedWidth,
            spreadRect.height,
          ),
        );
      }
    }

    const stripCount = 36;
    final spineX = viewportRect.center.dx;
    final pageToLeft = pageRect.right <= spineX;
    final sign = pageToLeft ? -1.0 : 1.0;
    final depthLift = 10.0 * sin(angle).clamp(0.0, 1.0);

    for (var i = 0; i < stripCount; i++) {
      final u0 = i / stripCount;
      final u1 = (i + 1) / stripCount;
      final x0 = spineX + sign * pageRect.width * u0;
      final x1 = spineX + sign * pageRect.width * u1;
      final left = min(x0, x1);
      final width = (x1 - x0).abs() + 0.5;
      final mid = (u0 + u1) / 2;
      final topInset = depthLift * mid;
      final bottomInset = depthLift * (1 - mid) * 0.35;
      final stripTop = topInset;
      final stripBottom = viewportRect.height - bottomInset;
      final stripLeft = spreadRect.left + left;
      final stripWidth = min(width, spreadRect.right - stripLeft);

      if (stripWidth <= 0) {
        continue;
      }

      if (stripTop > 0) {
        path.addRect(
          Rect.fromLTWH(
            stripLeft,
            spreadRect.top,
            stripWidth,
            stripTop,
          ),
        );
      }

      if (stripBottom < viewportRect.height) {
        path.addRect(
          Rect.fromLTWH(
            stripLeft,
            spreadRect.top + stripBottom,
            stripWidth,
            viewportRect.height - stripBottom,
          ),
        );
      }
    }

    return path;
  }

  double? _computeRevealedEdgeX() {
    if (progress <= 0.0 || spreadRect.isEmpty) {
      return null;
    }

    final viewportRect = Offset.zero & spreadRect.size;
    final pageWidth = viewportRect.width / 2;
    final projectedWidth = max(8.0, pageWidth * cos(progress * pi).abs());
    final pageRect = _turningPageDestinationRect(
      spineX: viewportRect.center.dx,
      projectedWidth: projectedWidth,
      height: viewportRect.height,
      turnLeftPage: direction == _BookPageTurnDirection.next,
      isFrontFace: progress <= 0.5,
    );

    return spreadRect.left +
        _computeLocalRevealedEdgeX(pageRect, progress <= 0.5);
  }

  double _computeLocalRevealedEdgeX(Rect pageRect, bool isFrontFace) {
    if (direction == _BookPageTurnDirection.next) {
      return isFrontFace ? pageRect.left : pageRect.right;
    }
    return isFrontFace ? pageRect.right : pageRect.left;
  }

  Rect _turningPageDestinationRect({
    required double spineX,
    required double projectedWidth,
    required double height,
    required bool turnLeftPage,
    required bool isFrontFace,
  }) {
    if (turnLeftPage) {
      return isFrontFace
          ? Rect.fromLTWH(spineX - projectedWidth, 0, projectedWidth, height)
          : Rect.fromLTWH(spineX, 0, projectedWidth, height);
    }

    return isFrontFace
        ? Rect.fromLTWH(spineX, 0, projectedWidth, height)
        : Rect.fromLTWH(spineX - projectedWidth, 0, projectedWidth, height);
  }

  @override
  bool shouldRepaint(_BookPageTurnBackgroundPainter old) =>
      old.progress != progress ||
      old.snapshot != snapshot ||
      old.targetSnapshot != targetSnapshot ||
      old.spreadRect != spreadRect ||
      old.direction != direction ||
      old.shadowColor != shadowColor ||
      old.edgeColor != edgeColor;
}

class _BookPageTurnPainter extends CustomPainter {
  final ui.Image snapshot;
  final ui.Image? targetSnapshot;
  final Rect snapshotViewportRect;
  final Size viewportLogicalSize;
  final double progress;
  final _BookPageTurnDirection direction;
  final Color pageBackColor;
  final Color pageHighlightColor;
  final Color shadowColor;
  final Color edgeColor;

  const _BookPageTurnPainter({
    required this.snapshot,
    required this.targetSnapshot,
    required this.snapshotViewportRect,
    required this.viewportLogicalSize,
    required this.progress,
    required this.direction,
    required this.pageBackColor,
    required this.pageHighlightColor,
    required this.shadowColor,
    required this.edgeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    if (progress <= 0.001) {
      return;
    }

    final viewportRect = Offset.zero & size;
    final pageWidth = viewportRect.width / 2;
    final angle = progress * pi;
    final isFrontFace = progress <= 0.5;
    final projectedWidth = max(8.0, pageWidth * cos(angle).abs());
    final spineX = viewportRect.center.dx;
    final turnLeftPage = direction == _BookPageTurnDirection.next;
    final shadeStrength = sin(angle).clamp(0.0, 1.0);

    final pageRect = _turningPageDestinationRect(
      spineX: spineX,
      projectedWidth: projectedWidth,
      height: viewportRect.height,
      turnLeftPage: turnLeftPage,
      isFrontFace: isFrontFace,
    );

    if (pageRect.width <= 1) {
      _paintSpineShadow(canvas, viewportRect, shadeStrength);
      return;
    }

    _paintUnderPageShadow(
      canvas: canvas,
      viewportRect: viewportRect,
      destinationRect: pageRect,
      turnLeftPage: turnLeftPage,
      isFrontFace: isFrontFace,
      shadeStrength: shadeStrength,
    );

    if (isFrontFace) {
      _drawPageFace(
        canvas: canvas,
        viewportRect: viewportRect,
        pageRect: pageRect,
        turnLeftPage: turnLeftPage,
        isFrontFace: isFrontFace,
        shadeStrength: shadeStrength,
      );
    } else {
      _drawPageBack(
        canvas: canvas,
        sourceImage: targetSnapshot ?? snapshot,
        useBackTint: targetSnapshot == null,
        sampleOppositeHalf: targetSnapshot != null,
        viewportRect: viewportRect,
        pageRect: pageRect,
        turnLeftPage: turnLeftPage,
        shadeStrength: shadeStrength,
      );
    }

    _paintPageFaceShade(
      canvas: canvas,
      pageRect: pageRect,
      turnLeftPage: turnLeftPage,
      isFrontFace: isFrontFace,
      shadeStrength: shadeStrength,
    );

    _paintPageEdge(
      canvas: canvas,
      destinationRect: pageRect,
      turnLeftPage: turnLeftPage,
      isFrontFace: isFrontFace,
      shadeStrength: shadeStrength,
    );
    _paintHingeEdge(
      canvas: canvas,
      viewportRect: viewportRect,
      destinationRect: pageRect,
      turnLeftPage: turnLeftPage,
      isFrontFace: isFrontFace,
      shadeStrength: shadeStrength,
    );
    _paintSpineShadow(canvas, viewportRect, shadeStrength);
  }

  Rect _turningPageDestinationRect({
    required double spineX,
    required double projectedWidth,
    required double height,
    required bool turnLeftPage,
    required bool isFrontFace,
  }) {
    if (turnLeftPage) {
      return isFrontFace
          ? Rect.fromLTWH(spineX - projectedWidth, 0, projectedWidth, height)
          : Rect.fromLTWH(spineX, 0, projectedWidth, height);
    }

    return isFrontFace
        ? Rect.fromLTWH(spineX, 0, projectedWidth, height)
        : Rect.fromLTWH(spineX - projectedWidth, 0, projectedWidth, height);
  }

  void _drawPageFace({
    required Canvas canvas,
    required Rect viewportRect,
    required Rect pageRect,
    required bool turnLeftPage,
    required bool isFrontFace,
    required double shadeStrength,
  }) {
    _drawPageStrips(
      sourceImage: snapshot,
      sampleOppositeHalf: false,
      canvas: canvas,
      viewportRect: viewportRect,
      pageRect: pageRect,
      turnLeftPage: turnLeftPage,
      shadeStrength: shadeStrength,
      paintBuilder: (_) => Paint(),
    );
  }

  void _paintUnderPageShadow({
    required Canvas canvas,
    required Rect viewportRect,
    required Rect destinationRect,
    required bool turnLeftPage,
    required bool isFrontFace,
    required double shadeStrength,
  }) {
    if (shadeStrength <= 0.01) return;

    final shadowWidth = min(
      viewportRect.width * 0.18,
      max(18.0, destinationRect.width * 1.15),
    );
    final shadowStartsAtSpine = !isFrontFace;
    final shadowRect = turnLeftPage == shadowStartsAtSpine
        ? Rect.fromLTWH(
            viewportRect.center.dx,
            0,
            shadowWidth,
            viewportRect.height,
          )
        : Rect.fromLTWH(
            viewportRect.center.dx - shadowWidth,
            0,
            shadowWidth,
            viewportRect.height,
          );

    canvas.drawRect(
      shadowRect,
      Paint()
        ..shader = LinearGradient(
          begin: shadowRect.left < viewportRect.center.dx
              ? Alignment.centerRight
              : Alignment.centerLeft,
          end: shadowRect.left < viewportRect.center.dx
              ? Alignment.centerLeft
              : Alignment.centerRight,
          colors: [
            shadowColor.withValues(alpha: 0.30 * shadeStrength),
            shadowColor.withValues(alpha: 0.0),
          ],
        ).createShader(shadowRect),
    );
  }

  void _paintPageEdge({
    required Canvas canvas,
    required Rect destinationRect,
    required bool turnLeftPage,
    required bool isFrontFace,
    required double shadeStrength,
  }) {
    final edgeOnRight = turnLeftPage == isFrontFace;
    final edgeX = edgeOnRight ? destinationRect.left : destinationRect.right;
    canvas.drawLine(
      Offset(edgeX, destinationRect.top),
      Offset(edgeX, destinationRect.bottom),
      Paint()
        ..color = edgeColor.withValues(alpha: 0.55 + shadeStrength * 0.25)
        ..strokeWidth = 1.4,
    );
  }

  void _paintHingeEdge({
    required Canvas canvas,
    required Rect viewportRect,
    required Rect destinationRect,
    required bool turnLeftPage,
    required bool isFrontFace,
    required double shadeStrength,
  }) {
    final hingeOnRight = turnLeftPage == isFrontFace;
    final hingeX = hingeOnRight ? destinationRect.right : destinationRect.left;
    final shadowWidth = min(viewportRect.width * 0.025, 22.0);
    final hingeShadowRect = hingeOnRight
        ? Rect.fromLTWH(
            hingeX - shadowWidth,
            destinationRect.top,
            shadowWidth,
            destinationRect.height,
          )
        : Rect.fromLTWH(
            hingeX,
            destinationRect.top,
            shadowWidth,
            destinationRect.height,
          );

    canvas.drawRect(
      hingeShadowRect,
      Paint()
        ..shader = LinearGradient(
          begin: hingeOnRight ? Alignment.centerRight : Alignment.centerLeft,
          end: hingeOnRight ? Alignment.centerLeft : Alignment.centerRight,
          colors: [
            shadowColor.withValues(alpha: 0.22 + shadeStrength * 0.20),
            shadowColor.withValues(alpha: 0.0),
          ],
        ).createShader(hingeShadowRect),
    );

    canvas.drawLine(
      Offset(hingeX, destinationRect.top),
      Offset(hingeX, destinationRect.bottom),
      Paint()
        ..color = edgeColor.withValues(alpha: 0.65)
        ..strokeWidth = 1.1,
    );
  }

  void _paintSpineShadow(
    Canvas canvas,
    Rect viewportRect,
    double shadeStrength,
  ) {
    final spineRect = Rect.fromCenter(
      center: viewportRect.center,
      width: 12,
      height: viewportRect.height,
    );

    canvas.drawRect(
      spineRect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            shadowColor.withValues(alpha: 0.0),
            shadowColor.withValues(alpha: 0.14 + shadeStrength * 0.12),
            shadowColor.withValues(alpha: 0.0),
          ],
        ).createShader(spineRect),
    );
  }

  void _drawPageBack({
    required ui.Image sourceImage,
    required bool useBackTint,
    required bool sampleOppositeHalf,
    required Canvas canvas,
    required Rect viewportRect,
    required Rect pageRect,
    required bool turnLeftPage,
    required double shadeStrength,
  }) {
    canvas.drawRect(pageRect, Paint()..color = pageBackColor);

    _drawPageStrips(
      sourceImage: sourceImage,
      sampleOppositeHalf: sampleOppositeHalf,
      canvas: canvas,
      viewportRect: viewportRect,
      pageRect: pageRect,
      turnLeftPage: turnLeftPage,
      shadeStrength: shadeStrength,
      paintBuilder: (_) {
        final paint = Paint();
        if (useBackTint) {
          paint.colorFilter = ColorFilter.mode(
            pageBackColor.withValues(alpha: 0.30),
            BlendMode.srcATop,
          );
        }
        return paint;
      },
    );

    final fiberPaint = Paint()
      ..color = edgeColor.withValues(alpha: 0.08 + shadeStrength * 0.04)
      ..strokeWidth = 0.8;
    final step = max(8.0, pageRect.height / 42);
    for (var y = pageRect.top + step; y < pageRect.bottom; y += step) {
      canvas.drawLine(
        Offset(pageRect.left + 4, y),
        Offset(pageRect.right - 4, y),
        fiberPaint,
      );
    }
  }

  void _drawPageStrips({
    required ui.Image sourceImage,
    required bool sampleOppositeHalf,
    required Canvas canvas,
    required Rect viewportRect,
    required Rect pageRect,
    required bool turnLeftPage,
    required double shadeStrength,
    required Paint Function(int stripIndex) paintBuilder,
  }) {
    const stripCount = 36;
    final spineX = viewportRect.center.dx;
    final pageToLeft = pageRect.right <= spineX;
    final sign = pageToLeft ? -1.0 : 1.0;
    final projectedWidth = pageRect.width;
    final depthLift = 10.0 * shadeStrength;

    for (var i = 0; i < stripCount; i++) {
      final u0 = i / stripCount;
      final u1 = (i + 1) / stripCount;
      final x0 = spineX + sign * projectedWidth * u0;
      final x1 = spineX + sign * projectedWidth * u1;
      final left = min(x0, x1);
      final width = (x1 - x0).abs() + 0.5;
      final mid = (u0 + u1) / 2;
      final topInset = depthLift * mid;
      final bottomInset = depthLift * (1 - mid) * 0.35;

      final destinationRect = Rect.fromLTWH(
        left,
        pageRect.top + topInset,
        width,
        pageRect.height - topInset - bottomInset,
      );

      final sourceRect = _turningPageSourceStripRect(
        image: sourceImage,
        viewportRect: viewportRect,
        turnLeftPage: turnLeftPage,
        sampleOppositeHalf: sampleOppositeHalf,
        u0: u0,
        u1: u1,
      );

      canvas.drawImageRect(
        sourceImage,
        sourceRect,
        destinationRect,
        paintBuilder(i),
      );
    }
  }

  void _paintPageFaceShade({
    required Canvas canvas,
    required Rect pageRect,
    required bool turnLeftPage,
    required bool isFrontFace,
    required double shadeStrength,
  }) {
    canvas.drawRect(
      pageRect,
      Paint()
        ..shader = LinearGradient(
          begin: _gradientBegin(turnLeftPage, isFrontFace),
          end: _gradientEnd(turnLeftPage, isFrontFace),
          colors: [
            pageHighlightColor.withValues(alpha: 0.08 + shadeStrength * 0.06),
            pageBackColor.withValues(alpha: isFrontFace ? 0.03 : 0.035),
            shadowColor.withValues(
              alpha: (isFrontFace ? 0.16 : 0.07) +
                  shadeStrength * (isFrontFace ? 0.32 : 0.11),
            ),
          ],
          stops: const [0.0, 0.58, 1.0],
        ).createShader(pageRect),
    );
  }

  Rect _turningPageSourceStripRect({
    required ui.Image image,
    required Rect viewportRect,
    required bool turnLeftPage,
    required bool sampleOppositeHalf,
    required double u0,
    required double u1,
  }) {
    final pageWidth = viewportRect.width / 2;
    final effectiveTurnLeftPage =
        sampleOppositeHalf ? !turnLeftPage : turnLeftPage;
    final localRect = effectiveTurnLeftPage
        ? Rect.fromLTWH(
            pageWidth - (u1 * pageWidth),
            0,
            (u1 - u0) * pageWidth,
            viewportRect.height,
          )
        : Rect.fromLTWH(
            pageWidth + (u0 * pageWidth),
            0,
            (u1 - u0) * pageWidth,
            viewportRect.height,
          );

    return _sourceRectForLocalRect(image, localRect);
  }

  Rect _sourceRectForLocalRect(ui.Image image, Rect localRect) {
    final fullImageRect =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final pixelRatioX = image.width / viewportLogicalSize.width;
    final pixelRatioY = image.height / viewportLogicalSize.height;

    return Rect.fromLTWH(
      (snapshotViewportRect.left + localRect.left) * pixelRatioX,
      (snapshotViewportRect.top + localRect.top) * pixelRatioY,
      localRect.width * pixelRatioX,
      localRect.height * pixelRatioY,
    ).intersect(fullImageRect);
  }

  Alignment _gradientBegin(bool turnLeftPage, bool isFrontFace) {
    final spineOnRight = turnLeftPage == isFrontFace;
    return spineOnRight ? Alignment.centerRight : Alignment.centerLeft;
  }

  Alignment _gradientEnd(bool turnLeftPage, bool isFrontFace) {
    final spineOnRight = turnLeftPage == isFrontFace;
    return spineOnRight ? Alignment.centerLeft : Alignment.centerRight;
  }

  @override
  bool shouldRepaint(_BookPageTurnPainter oldDelegate) =>
      oldDelegate.snapshot != snapshot ||
      oldDelegate.targetSnapshot != targetSnapshot ||
      oldDelegate.snapshotViewportRect != snapshotViewportRect ||
      oldDelegate.viewportLogicalSize != viewportLogicalSize ||
      oldDelegate.progress != progress ||
      oldDelegate.direction != direction ||
      oldDelegate.pageBackColor != pageBackColor ||
      oldDelegate.pageHighlightColor != pageHighlightColor ||
      oldDelegate.shadowColor != shadowColor ||
      oldDelegate.edgeColor != edgeColor;
}

class _BookViewTurnButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final double size;
  final Color backgroundColor;
  final Color iconColor;
  final Color borderColor;
  final Color shadowColor;
  final VoidCallback onPressed;

  const _BookViewTurnButton({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.backgroundColor,
    required this.iconColor,
    required this.borderColor,
    required this.shadowColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final compactSize = size * 0.7;
    return Container(
      width: compactSize,
      height: compactSize,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(compactSize / 2),
          child: Center(
            child: Tooltip(
              message: tooltip,
              child: Icon(icon, color: iconColor, size: compactSize * 0.5),
            ),
          ),
        ),
      ),
    );
  }
}
