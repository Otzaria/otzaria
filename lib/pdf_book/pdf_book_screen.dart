import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/app_menu.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart' as otz_links;
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart' as pdf_events;
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/pdf_page_number_dispaly.dart';
import 'package:otzaria/pdf_book/pdf_commentary_panel.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_event.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor.dart';
import 'package:otzaria/personal_notes/services/personal_note_draft_service.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/open_book.dart';
import 'package:otzaria/utils/ref_helper.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'pdf_search_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'pdf_outlines_screen.dart';
import 'package:otzaria/widgets/password_dialog.dart';
import 'pdf_thumbnails_screen.dart';
import 'package:printing/printing.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/utils/page_converter.dart';
import 'package:otzaria/utils/reading_left_pane_policy.dart';
import 'package:flutter/gestures.dart';
import 'package:otzaria/widgets/dual_adaptive_reader_pane.dart';
import 'package:otzaria/widgets/responsive_action_bar.dart';
import 'pdf_zoom_bar.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/widgets/commentary_pane_tooltip.dart';
import 'package:otzaria/pdf_book/pdf_scrollbar.dart';
import 'package:otzaria/widgets/resume_reading_chip.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';

class PdfBookScreen extends StatefulWidget {
  final PdfBookTab tab;
  final bool isInCombinedView;

  const PdfBookScreen({
    super.key,
    required this.tab,
    this.isInCombinedView = false,
  });

  @override
  State<PdfBookScreen> createState() => _PdfBookScreenState();
}

class _PdfBookScreenState extends State<PdfBookScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  static const int _defaultPdfLineRange = 50;
  static const double _bookViewGap = 3.0;
  static const double _bookViewScale = 0.5;
  static const String _connectionTypeCommentary = 'COMMENTARY';
  static const String _connectionTypeTargum = 'TARGUM';

  @override
  bool get wantKeepAlive => true;

  late final PdfViewerController pdfController;
  late final PdfBookBloc _bloc;
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
  LogicalKeyboardKey? _currentScrollKey;
  int? _scrollAnchorPage;
  int? _lockedSpreadStartPage;
  ui.Image? _pageTurnSnapshot;
  _BookPageTurnTransition? _pageTurnTransition;
  bool _isPageTurnInProgress = false;
  _PendingBookPageTurn? _pendingPageTurn;
  bool _resumePromptDismissed = false;

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
      duration: const Duration(milliseconds: 520),
    );
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
        typoToleranceEnabled: widget.tab.typoToleranceEnabled,
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
    if (currentLine == null) return null;

    final int startLine = currentLine;
    int endLine = startLine + _defaultPdfLineRange;

    if (widget.tab.pdfHeadings != null) {
      final sortedHeadings = widget.tab.pdfHeadings!.getSortedHeadings();
      final currentIndex =
          sortedHeadings.indexWhere((e) => e.value == currentLine);

      if (currentIndex != -1 && currentIndex < sortedHeadings.length - 1) {
        endLine = sortedHeadings[currentIndex + 1].value - 1;
      }
    }

    return (startLine: startLine, endLine: endLine);
  }

  Future<int> _resolveTextLineNumberForPage(
    int pageNumber, {
    String? resolvedTitle,
  }) async {
    final outline = widget.tab.outline.value ?? const <PdfOutlineNode>[];
    if (outline.isNotEmpty) {
      final textIndex =
          await pdfToTextPage(widget.tab.book, outline, pageNumber, context);
      if (textIndex != null) {
        return textIndex + 1;
      }
    }

    final title = resolvedTitle ??
        await refFromPageNumber(pageNumber, outline, widget.tab.book.title);
    if (widget.tab.pdfHeadings != null && title.isNotEmpty) {
      final lineNumber = widget.tab.pdfHeadings!.getLineNumberForHeading(title);
      if (lineNumber != null) {
        return lineNumber;
      }
    }

    return pageNumber;
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

  void _openCommentaryPane() {
    setState(() {
      _rightPaneInitialTabIndex = 0;
    });
    _bloc.add(const pdf_events.ToggleRightPane(show: true));
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
      BuildContext menuContext) {
    final (commentators: relevantCommentators, links: relevantLinks) =
        _getRelevantContent();

    final allActive = relevantCommentators.isNotEmpty &&
        widget.tab.activeCommentators.containsAll(relevantCommentators);

    final commentatorChildren = <AppContextMenuEntry>[
      AppContextMenuEntry(
        label: 'הצג את כל המפרשים',
        icon: allActive ? FluentIcons.checkmark_24_regular : null,
        onTap: () => _toggleAllCommentators(relevantCommentators),
      ),
      if (relevantCommentators.isNotEmpty) const AppContextMenuEntry.divider(),
      ..._buildGroupedCommentatorEntries(relevantCommentators),
    ];

    final linkChildren = relevantLinks
        .map((link) => AppContextMenuEntry(
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
            ))
        .toList();

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
      horizontalCacheExtent: 0, // רק דפים נראים
      verticalCacheExtent: 1, // רק דף אחד למעלה/למטה
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
        PdfScrollbar(
          controller: widget.tab.pdfViewerController,
          orientation: ScrollbarOrientation.right,
          trackThickness: 16.0,
          thumbMinSize: 50.0,
          scrollBoundsBuilder: _currentVerticalScrollbarBounds,
        ),
        _buildResumeReadingPrompt(size),
        PdfHorizontalScrollbar(
          controller: widget.tab.pdfViewerController,
          trackThickness: 10.0,
        ),
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

        _bloc.add(pdf_events.DocumentReady(
          documentRef: controller.documentRef,
          outline: widget.tab.outline.value,
          totalPages: document.pages.length,
        ));

        // טעינת headings וlinks
        await _loadPdfHeadingsAndLinks();

        // קפיצה לעמוד הנכון - עם המתנה קצרה כדי לוודא שה-controller מוכן
        if (widget.tab.pageNumber > 1) {
          _isJumping = true; // מסמן שאנחנו בתהליך קפיצה
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            // המתנה קצרה נוספת לוודא שהכל מוכן
            await Future.delayed(const Duration(milliseconds: 100));
            if (mounted && controller.isReady) {
              await controller.goToPage(pageNumber: widget.tab.pageNumber);
              // המתנה נוספת לוודא שהקפיצה הסתיימה
              await Future.delayed(const Duration(milliseconds: 200));

              // עדכון currentTextLineNumber אחרי הקפיצה
              if (mounted) {
                final jumpedPage = widget.tab.pdfViewerController.pageNumber ??
                    widget.tab.pageNumber;
                final jumpedTitle = await refFromPageNumber(jumpedPage,
                    widget.tab.outline.value ?? [], widget.tab.book.title);
                widget.tab.currentTextLineNumber =
                    await _resolveTextLineNumberForPage(
                  jumpedPage,
                  resolvedTitle: jumpedTitle,
                );
                setState(() {});
              }

              _isJumping = false; // מאפס את ה-flag
              _initialPageNumber = null; // מאפס גם את זה
            } else {
              _isJumping = false;
            }
          });
        } else {
          // אם לא קופצים, עדכן את currentTextLineNumber מיד
          final currentPage = widget.tab.pdfViewerController.isReady
              ? (widget.tab.pdfViewerController.pageNumber ?? 1)
              : widget.tab.pageNumber;
          final title = await refFromPageNumber(
              currentPage, widget.tab.outline.value, widget.tab.book.title);
          widget.tab.currentTitle.value = title;
          widget.tab.currentTextLineNumber =
              await _resolveTextLineNumberForPage(
            currentPage,
            resolvedTitle: title,
          );
        }

        if (!mounted) return;
        final settingsBloc = context.read<SettingsBloc>();
        final enablePerBookSettings = settingsBloc.state.enablePerBookSettings;

        // קבע את currentPage לשימוש בקוד שלאחר
        final currentPage = widget.tab.pdfViewerController.isReady
            ? (widget.tab.pdfViewerController.pageNumber ?? 1)
            : widget.tab.pageNumber;

        bool shouldFitToWidth = true;
        if (enablePerBookSettings) {
          final settings =
              await PdfBookPerBookSettings.load(widget.tab.book.title);
          shouldFitToWidth = settings?.zoom == null;

          // טעינת המפרשים הפעילים
          if (settings?.activeCommentators != null) {
            widget.tab.activeCommentators.clear();
            widget.tab.activeCommentators.addAll(settings!.activeCommentators!);
          }
        }

        if (shouldFitToWidth) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && controller.isReady) {
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
          if (state is PdfBookLoaded) return state.layoutMode;
          return null;
        }

        return layoutModeFor(prev) != layoutModeFor(curr);
      },
      builder: (context, state) {
        final layoutMode = switch (state) {
          PdfBookInitial initial => initial.layoutMode,
          PdfBookLoaded loaded => loaded.layoutMode,
          _ => PdfLayoutMode.regularView,
        };

        return Focus(
          focusNode: _pdfViewFocusNode,
          autofocus: false,
          onKeyEvent: (FocusNode node, KeyEvent event) {
            if (event is KeyDownEvent) {
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
            } else if (event is KeyUpEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                  event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _stopContinuousScroll();
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _pdfViewFocusNode.requestFocus();
            },
            child: PdfViewer.file(
              filePath,
              controller: widget.tab.pdfViewerController,
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
    final layout = controller.layout;
    final pageLayouts = layout.pageLayouts;
    if (pageLayouts.isEmpty) return null;
    return Rect.fromLTRB(
      0,
      pageLayouts.first.top,
      layout.documentSize.width,
      pageLayouts.last.bottom,
    );
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

  Widget _buildResumeReadingPrompt(Size viewportSize) {
    final resumePage = widget.tab.resumePageNumber;
    final controller = widget.tab.pdfViewerController;
    if (_resumePromptDismissed ||
        resumePage == null ||
        resumePage <= 1 ||
        !controller.isReady ||
        controller.pageCount <= 0 ||
        controller.pageNumber == resumePage) {
      return const SizedBox.shrink();
    }

    final targetPage = resumePage.clamp(1, controller.pageCount);
    if (viewportSize.height <= 88) return const SizedBox.shrink();
    final progress = controller.pageCount <= 1
        ? 0.0
        : (targetPage - 1) / (controller.pageCount - 1);
    final markerTop = (viewportSize.height - 64) * progress;
    final colorScheme = Theme.of(context).colorScheme;
    final ref = widget.tab.resumeRef?.trim();
    final subtitle = ref == null || ref.isEmpty ? 'עמוד $targetPage' : ref;

    return PositionedDirectional(
      end: 26,
      top: markerTop.clamp(12.0, viewportSize.height - 76).toDouble(),
      child: ResumeReadingChip(
        subtitle: subtitle,
        onTap: () {
          setState(() {
            _resumePromptDismissed = true;
          });
          _goToPageWithSpreadLock(targetPage);
        },
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        borderColor: colorScheme.primary.withValues(alpha: 0.25),
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
                final progress = Curves.easeInOutCubic.transform(
                  _pageTurnController.value,
                );
                return CustomPaint(
                  painter: _BookPageTurnBackgroundPainter(
                    snapshot: snapshot,
                    spreadRect: transition.viewportRect,
                    progress: progress,
                    direction: transition.direction,
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
                final progress = Curves.easeInOutCubic.transform(
                  _pageTurnController.value,
                );

                return CustomPaint(
                  size: transition.viewportRect.size,
                  painter: _BookPageTurnPainter(
                    snapshot: snapshot,
                    snapshotViewportRect: transition.viewportRect,
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
    if (!widget.tab.pdfViewerController.isReady) return;
    final totalPages = widget.tab.pdfViewerController.pageCount;
    final safePage = pageNumber.clamp(1, totalPages);

    if (_isBookViewModeActive()) {
      _lockedSpreadStartPage = _spreadStartPageFor(safePage);
    }

    // During progressive PDF loading, pdfrx may wait indefinitely for the
    // viewport to settle while new tiles keep arriving. Time out the await so
    // page-turn state cannot deadlock the navigation flow.
    await widget.tab.pdfViewerController
        .goToPage(pageNumber: safePage)
        .timeout(const Duration(seconds: 3), onTimeout: () {});

    if (!_pdfViewFocusNode.hasFocus) {
      _pdfViewFocusNode.requestFocus();
    }
  }

  Future<ui.Image?> _capturePdfViewportSnapshot() async {
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
      return await renderObject.toImage(pixelRatio: pixelRatio);
    } catch (error, stackTrace) {
      debugPrint('Failed to capture PDF snapshot: $error\n$stackTrace');
      return null;
    }
  }

  void _disposePageTurnSnapshot() {
    _pageTurnSnapshot?.dispose();
    _pageTurnSnapshot = null;
  }

  void _clearPageTurnOverlay() {
    _disposePageTurnSnapshot();
    _pageTurnTransition = null;
  }

  Future<void> _processPendingPageTurnIfNeeded() async {
    final pendingPageTurn = _pendingPageTurn;
    _pendingPageTurn = null;

    if (pendingPageTurn == null || !mounted) {
      return;
    }

    await _animateBookPageTurn(
      targetPage: pendingPageTurn.targetPage,
      direction: pendingPageTurn.direction,
    );
  }

  bool _hasNewerPendingPageTurn({
    required int targetPage,
    required _BookPageTurnDirection direction,
  }) {
    final pendingPageTurn = _pendingPageTurn;
    if (pendingPageTurn == null) {
      return false;
    }

    return pendingPageTurn.targetPage != targetPage ||
        pendingPageTurn.direction != direction;
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
      _pendingPageTurn = _PendingBookPageTurn(
        targetPage: targetPage,
        direction: direction,
      );
      return;
    }

    // Set the flag BEFORE any goToPage call so that the normalizeMatrix
    // callback is disabled for the entire duration. Without this, when
    // currentSpreadViewportRect is null (layout not ready during progressive
    // loading), goToPage hangs because normalization keeps fighting it.
    _isPageTurnInProgress = true;

    try {
      final currentSpreadViewportRect = _currentSpreadViewportRect(
        widget.tab.pdfViewerController,
        widget.tab.pdfViewerController.viewSize,
      );

      if (currentSpreadViewportRect == null) {
        await _goToPageWithSpreadLock(targetPage);
        return;
      }

      final snapshot = await _capturePdfViewportSnapshot();

      if (!mounted || snapshot == null) {
        snapshot?.dispose();
        await _goToPageWithSpreadLock(targetPage);
        return;
      }

      if (_hasNewerPendingPageTurn(
          targetPage: targetPage, direction: direction)) {
        snapshot.dispose();
        return;
      }

      // Reset to 0 before setState so that when the AnimatedBuilder first
      // paints the overlay it uses progress=0 (full snapshot, no hole).
      // Without this, a previous completed animation leaves the controller
      // at 1.0, punching a full-spread hole in the snapshot and exposing
      // the loading tiles underneath before the animation even starts.
      _pageTurnController.reset();
      setState(() {
        _disposePageTurnSnapshot();
        _pageTurnSnapshot = snapshot;
        _pageTurnTransition = _BookPageTurnTransition(
          direction: direction,
          viewportRect: currentSpreadViewportRect,
        );
      });

      // Wait for the overlay frame to actually paint before jumping to the
      // new page. Without this, goToPage fires while the snapshot is still
      // scheduled (not yet on screen) and the new PDF tiles appear
      // underneath a blank overlay.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      if (_hasNewerPendingPageTurn(
          targetPage: targetPage, direction: direction)) {
        return;
      }

      await _goToPageWithSpreadLock(targetPage);

      if (!mounted) return;

      // Allow the PDF to begin rendering the new page tiles before the
      // animation starts, so the revealed area isn't blank.
      await Future<void>.delayed(const Duration(milliseconds: 16));

      if (!mounted) return;

      await _pageTurnController.forward(from: 0);
    } finally {
      _isPageTurnInProgress = false;
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
    try {
      // טעינת headings מה-DB
      final headings = await PdfHeadings.loadFromDatabase(
        widget.tab.book.title,
        categoryId: widget.tab.book.categoryId,
        filePath: widget.tab.book.filePath,
      );
      if (headings != null) {
        widget.tab.pdfHeadings = headings;
      }

      // טעינת links
      final library = await DataRepository.instance.library;

      final textBook = library.findBookByTitle(widget.tab.book.title, TextBook);

      if (textBook != null) {
        if (textBook is TextBook) {
          final loadedLinks = await textBook.links
            ..sort((a, b) => a.index1.compareTo(b.index1));
          widget.tab.links = loadedLinks;
          await _loadCommentatorGroups();
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e, stackTrace) {
      debugPrint('Error loading PDF headings and links: $e\n$stackTrace');
    }
  }

  @override
  void dispose() {
    _stopContinuousScroll();
    _disposePageTurnSnapshot();
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

  void _onPdfViewerControllerUpdate() async {
    if (!widget.tab.pdfViewerController.isReady) return;

    widget.tab.savedZoom = widget.tab.pdfViewerController.value.zoom;

    final newPage = widget.tab.pdfViewerController.pageNumber ?? 1;

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
    if (token == _lastComputedForPage) {
      widget.tab.currentTitle.value = title;

      widget.tab.currentTextLineNumber = await _resolveTextLineNumberForPage(
        newPage,
        resolvedTitle: title,
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
    return LayoutBuilder(builder: (context, constrains) {
      final wideScreen = (MediaQuery.of(context).size.width >= 600);
      return CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
              _ensureSearchTabIsActive,
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.equal):
              _zoomIn,
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.add):
              _zoomIn,
          LogicalKeySet(
                  LogicalKeyboardKey.control, LogicalKeyboardKey.numpadAdd):
              _zoomIn,
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.minus):
              _zoomOut,
          LogicalKeySet(LogicalKeyboardKey.control,
              LogicalKeyboardKey.numpadSubtract): _zoomOut,
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
                if (value.isNotEmpty &&
                    !value.contains(widget.tab.book.title)) {
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
                minMainContentWidth: 640,
              );
            },
          ),
        ),
      );
    });
  }

  Widget _buildReaderMainContent() {
    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (!(widget.tab.pinLeftPane.value ||
                (Settings.getValue<bool>('key-pin-sidebar') ?? false))) {
              Future.microtask(() {
                _setLeftPaneVisibility(false);
                _pdfViewFocusNode.requestFocus();
              });
            }
            return false;
          },
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                if (HardwareKeyboard.instance.isControlPressed) {
                  return;
                }

                _captureScrollAnchor();
                _applyPointerScroll(event);

                if (!(widget.tab.pinLeftPane.value ||
                    (Settings.getValue<bool>('key-pin-sidebar') ?? false))) {
                  _setLeftPaneVisibility(false);
                  Future.microtask(() {
                    _pdfViewFocusNode.requestFocus();
                  });
                }
              }
            },
            child: Stack(
              children: [
                RepaintBoundary(
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
                _buildPageTurnOverlay(context),
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
              child: CommentaryPaneTooltip(
                child: MouseRegion(
                  onEnter: (_) =>
                      _bloc.add(const pdf_events.SetRightPaneHovering(true)),
                  onExit: (_) =>
                      _bloc.add(const pdf_events.SetRightPaneHovering(false)),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _rightPaneInitialTabIndex = 0;
                      });
                      _bloc.add(const pdf_events.ToggleRightPane(show: true));
                    },
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
                    Tab(text: 'ניווט'),
                    Tab(text: 'חיפוש'),
                    Tab(text: 'דפים'),
                  ],
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  dividerColor: Colors.transparent,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
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
                        initialTypoToleranceEnabled:
                            widget.tab.typoToleranceEnabled,
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

  void _goNextPage() {
    if (!widget.tab.pdfViewerController.isReady) return;

    final isBookViewMode = _isBookViewModeActive();
    final currentPage = widget.tab.pdfViewerController.pageNumber ?? 1;
    final totalPages = widget.tab.pdfViewerController.pageCount;
    final pageStep = isBookViewMode ? 2 : 1;
    final nextPage = min(currentPage + pageStep, totalPages);

    if (nextPage == currentPage) {
      return;
    }

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
    final currentPage = widget.tab.pdfViewerController.pageNumber ?? 1;
    final pageStep = isBookViewMode ? 2 : 1;
    final prevPage = max(currentPage - pageStep, 1);

    if (prevPage == currentPage) {
      return;
    }

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

  void _applyPointerScroll(PointerScrollEvent event) {
    if (!widget.tab.pdfViewerController.isReady) return;

    final currentMatrix = widget.tab.pdfViewerController.value;
    final zoom = currentMatrix.zoom;
    final candidateMatrix = currentMatrix.clone()
      ..translateByDouble(
        -event.scrollDelta.dx / zoom,
        -event.scrollDelta.dy / zoom,
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
        key: ValueKey('pdf_actions_$screenWidth'),
        overflowMenuOffset: const Offset(0, 8),
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
    final dialogContext = context;

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

    if (!mounted) return;

    final noteContent = await showDialog<PersonalNoteEditorResult>(
      // ignore: use_build_context_synchronously
      context: dialogContext,
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
    final file = File(widget.tab.book.path);
    final fileName = file.uri.pathSegments.last;
    await Printing.sharePdf(
      bytes: await file.readAsBytes(),
      filename: fileName,
    );

    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _pdfViewFocusNode.requestFocus();
        }
      });
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

  const _BookPageTurnTransition({
    required this.direction,
    required this.viewportRect,
  });
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

  /// Position of the spread (book pages) inside the full viewer, in logical
  /// pixels of the viewer's coordinate space.
  final Rect spreadRect;
  final double progress;
  final _BookPageTurnDirection direction;

  const _BookPageTurnBackgroundPainter({
    required this.snapshot,
    required this.spreadRect,
    required this.progress,
    required this.direction,
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

    final revealedRect = _computeRevealedRect();

    if (revealedRect == null) {
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
      ..addRect(revealedRect);
    canvas.clipPath(clipPath);
    canvas.drawImageRect(snapshot, sourceRect, destRect, Paint());
    canvas.restore();
  }

  /// Returns the portion of the spread rect that the animation has already
  /// swept past (where the new page should be visible).
  Rect? _computeRevealedRect() {
    final revealW = spreadRect.width * progress;
    if (revealW <= 0) return null;

    if (direction == _BookPageTurnDirection.next) {
      // Curl sweeps left → right; left side is revealed first.
      return Rect.fromLTWH(
        spreadRect.left,
        spreadRect.top,
        revealW,
        spreadRect.height,
      );
    } else {
      // Curl sweeps right → left; right side is revealed first.
      return Rect.fromLTWH(
        spreadRect.right - revealW,
        spreadRect.top,
        revealW,
        spreadRect.height,
      );
    }
  }

  @override
  bool shouldRepaint(_BookPageTurnBackgroundPainter old) =>
      old.progress != progress ||
      old.snapshot != snapshot ||
      old.spreadRect != spreadRect ||
      old.direction != direction;
}

class _BookPageTurnPainter extends CustomPainter {
  final ui.Image snapshot;
  final Rect snapshotViewportRect;
  final double progress;
  final _BookPageTurnDirection direction;
  final Color pageBackColor;
  final Color pageHighlightColor;
  final Color shadowColor;
  final Color edgeColor;

  const _BookPageTurnPainter({
    required this.snapshot,
    required this.snapshotViewportRect,
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

    final viewportRect = Offset.zero & size;
    final curlWidth = max(
      size.width * 0.12,
      size.width * (0.08 + (sin(pi * progress) * 0.10)),
    );

    if (direction == _BookPageTurnDirection.next) {
      _paintNextTurn(
        canvas: canvas,
        viewportRect: viewportRect,
        curlWidth: curlWidth,
      );
      return;
    }

    _paintPreviousTurn(
      canvas: canvas,
      viewportRect: viewportRect,
      curlWidth: curlWidth,
    );
  }

  void _paintNextTurn({
    required Canvas canvas,
    required Rect viewportRect,
    required double curlWidth,
  }) {
    final revealX = viewportRect.width * progress;
    final curlEndX = min(viewportRect.width, revealX + curlWidth);

    if (curlEndX < viewportRect.width) {
      _drawSnapshotSegment(
        canvas: canvas,
        viewportRect: viewportRect,
        destinationRect: Rect.fromLTWH(
          curlEndX,
          0,
          viewportRect.width - curlEndX,
          viewportRect.height,
        ),
      );
    }

    if (curlEndX <= revealX) {
      return;
    }

    _paintCurl(
      canvas: canvas,
      viewportRect: viewportRect,
      curlRect: Rect.fromLTWH(
        revealX,
        0,
        curlEndX - revealX,
        viewportRect.height,
      ),
      revealLeadingEdge: revealX,
      movingForward: true,
    );
  }

  void _paintPreviousTurn({
    required Canvas canvas,
    required Rect viewportRect,
    required double curlWidth,
  }) {
    final revealX = viewportRect.width * (1 - progress);
    final curlStartX = max(0.0, revealX - curlWidth);

    if (curlStartX > 0) {
      _drawSnapshotSegment(
        canvas: canvas,
        viewportRect: viewportRect,
        destinationRect: Rect.fromLTWH(
          0,
          0,
          curlStartX,
          viewportRect.height,
        ),
      );
    }

    if (revealX <= curlStartX) {
      return;
    }

    _paintCurl(
      canvas: canvas,
      viewportRect: viewportRect,
      curlRect: Rect.fromLTWH(
        curlStartX,
        0,
        revealX - curlStartX,
        viewportRect.height,
      ),
      revealLeadingEdge: revealX,
      movingForward: false,
    );
  }

  void _paintCurl({
    required Canvas canvas,
    required Rect viewportRect,
    required Rect curlRect,
    required double revealLeadingEdge,
    required bool movingForward,
  }) {
    final bendsLeft = !movingForward;
    final curvature = curlRect.width * (0.14 + (0.10 * sin(pi * progress)));
    final bendPath = Path()
      ..moveTo(curlRect.left, curlRect.top)
      ..quadraticBezierTo(
        curlRect.left + (bendsLeft ? curvature : -curvature),
        curlRect.center.dy,
        curlRect.left,
        curlRect.bottom,
      )
      ..lineTo(curlRect.right, curlRect.bottom)
      ..quadraticBezierTo(
        curlRect.right + (bendsLeft ? curvature * 0.4 : -curvature * 0.4),
        curlRect.center.dy,
        curlRect.right,
        curlRect.top,
      )
      ..close();

    canvas.save();
    canvas.clipPath(bendPath);

    final sourceRect = _sourceRectForDestination(
      viewportRect: viewportRect,
      destinationRect: curlRect,
    );

    if (bendsLeft) {
      canvas.save();
      canvas.translate(curlRect.right, 0);
      canvas.scale(-1, 1);
      canvas.drawImageRect(
        snapshot,
        sourceRect,
        Rect.fromLTWH(0, 0, curlRect.width, curlRect.height),
        Paint(),
      );
      canvas.restore();
    } else {
      canvas.save();
      canvas.translate(curlRect.left + curlRect.width, 0);
      canvas.scale(-1, 1);
      canvas.drawImageRect(
        snapshot,
        sourceRect,
        Rect.fromLTWH(0, 0, curlRect.width, curlRect.height),
        Paint(),
      );
      canvas.restore();
    }

    canvas.drawRect(
      curlRect,
      Paint()
        ..shader = LinearGradient(
          begin: bendsLeft ? Alignment.centerRight : Alignment.centerLeft,
          end: bendsLeft ? Alignment.centerLeft : Alignment.centerRight,
          colors: [
            pageHighlightColor.withValues(alpha: 0.10),
            pageBackColor.withValues(alpha: 0.28),
            shadowColor.withValues(alpha: 0.18),
          ],
          stops: const [0.0, 0.58, 1.0],
        ).createShader(curlRect),
    );

    canvas.restore();

    final underShadowWidth =
        min(curlRect.width * 0.8, viewportRect.width * 0.10);
    final underShadowRect = movingForward
        ? Rect.fromLTWH(
            max(0.0, revealLeadingEdge - underShadowWidth),
            0,
            underShadowWidth,
            viewportRect.height,
          )
        : Rect.fromLTWH(
            revealLeadingEdge,
            0,
            underShadowWidth,
            viewportRect.height,
          );

    canvas.drawRect(
      underShadowRect,
      Paint()
        ..shader = LinearGradient(
          begin: movingForward ? Alignment.centerRight : Alignment.centerLeft,
          end: movingForward ? Alignment.centerLeft : Alignment.centerRight,
          colors: [
            shadowColor.withValues(alpha: 0.22),
            shadowColor.withValues(alpha: 0.0),
          ],
        ).createShader(underShadowRect),
    );

    final edgeX = movingForward ? curlRect.right : curlRect.left;
    canvas.drawLine(
      Offset(edgeX, curlRect.top),
      Offset(edgeX, curlRect.bottom),
      Paint()
        ..color = edgeColor.withValues(alpha: 0.42)
        ..strokeWidth = 1.2,
    );
  }

  void _drawSnapshotSegment({
    required Canvas canvas,
    required Rect viewportRect,
    required Rect destinationRect,
  }) {
    if (destinationRect.width <= 0 || destinationRect.height <= 0) {
      return;
    }

    final sourceRect = _sourceRectForDestination(
      viewportRect: viewportRect,
      destinationRect: destinationRect,
    );

    canvas.drawImageRect(snapshot, sourceRect, destinationRect, Paint());
  }

  Rect _sourceRectForDestination({
    required Rect viewportRect,
    required Rect destinationRect,
  }) {
    final fullImageRect = Rect.fromLTWH(
      0,
      0,
      snapshot.width.toDouble(),
      snapshot.height.toDouble(),
    );
    final normalizedLeft = destinationRect.left / viewportRect.width;
    final normalizedTop = destinationRect.top / viewportRect.height;
    final normalizedWidth = destinationRect.width / viewportRect.width;
    final normalizedHeight = destinationRect.height / viewportRect.height;

    return Rect.fromLTWH(
      snapshotViewportRect.left + (snapshotViewportRect.width * normalizedLeft),
      snapshotViewportRect.top + (snapshotViewportRect.height * normalizedTop),
      snapshotViewportRect.width * normalizedWidth,
      snapshotViewportRect.height * normalizedHeight,
    ).intersect(fullImageRect);
  }

  @override
  bool shouldRepaint(_BookPageTurnPainter oldDelegate) =>
      oldDelegate.snapshot != snapshot ||
      oldDelegate.snapshotViewportRect != snapshotViewportRect ||
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
