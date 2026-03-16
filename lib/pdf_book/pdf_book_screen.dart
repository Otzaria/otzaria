import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart' as ctx;
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
import 'package:flutter/gestures.dart';
import 'package:otzaria/widgets/responsive_action_bar.dart';
import 'package:otzaria/widgets/resizable_drag_handle.dart';
import 'pdf_zoom_bar.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/widgets/commentary_pane_tooltip.dart';
import 'package:otzaria/pdf_book/pdf_scrollbar.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/models/pdf_headings.dart';

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
  late final StreamSubscription<SettingsState> _settingsSub;

  // גלילה רציפה
  Timer? _scrollTimer;
  LogicalKeyboardKey? _currentScrollKey;

  // Local UI state that syncs with Bloc
  int _rightPaneInitialTabIndex = 0;

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
    widget.tab.showLeftPane.value = true;
    if (_leftPaneTabController != null && _leftPaneTabController!.index != 1) {
      _leftPaneTabController!.animateTo(1);
    }
    _searchFieldFocusNode.requestFocus();
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
    _initialPageNumber = widget.tab.pageNumber; // שמירת מספר העמוד ההתחלתי
    pdfController = PdfViewerController();
    widget.tab.pdfViewerController = pdfController;

    // יצירת ה-Bloc עם המצב ההתחלתי
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
      ),
    );

    // PDF is always a file on the file system — use book.path directly

    // הגדרת ערכים התחלתיים מ-Settings
    final settingsBloc = context.read<SettingsBloc>();
    _settingsSub = settingsBloc.stream.listen((state) {
      _bloc.add(pdf_events.UpdateSidebarWidth(state.sidebarWidth));
      _bloc.add(pdf_events.UpdateRightPaneWidth(state.commentaryPaneWidth));
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

  Text _buildRtlMenuText(String text) =>
      Text(text, textDirection: TextDirection.rtl);

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

  ctx.ContextMenu<Object> _buildPdfContextMenu() {
    final (commentators: relevantCommentators, links: relevantLinks) =
        _getRelevantContent();

    return ctx.ContextMenu(
      entries: <ctx.ContextMenuEntry<Object>>[
        ctx.MenuItem<Object>(
          label: _buildRtlMenuText('חיפוש'),
          icon: const Icon(FluentIcons.search_24_regular),
          onSelected: (_) => _ensureSearchTabIsActive(),
        ),
        ctx.MenuItem<Object>.submenu(
          label: _buildRtlMenuText('מפרשים'),
          icon: const Icon(FluentIcons.book_24_regular),
          enabled: relevantCommentators.isNotEmpty,
          items: <ctx.ContextMenuEntry<Object>>[
            ctx.MenuItem<Object>(
              label: _buildRtlMenuText('הצג את כל המפרשים'),
              icon: relevantCommentators.isNotEmpty &&
                      widget.tab.activeCommentators
                          .containsAll(relevantCommentators)
                  ? const Icon(FluentIcons.checkmark_24_regular)
                  : null,
              onSelected: (_) => _toggleAllCommentators(relevantCommentators),
            ),
            if (relevantCommentators.isNotEmpty) const ctx.MenuDivider(),
            ...relevantCommentators.map<ctx.ContextMenuEntry<Object>>(
              (commentator) => ctx.MenuItem<Object>(
                label: Text(commentator, textDirection: TextDirection.rtl),
                icon: widget.tab.activeCommentators.contains(commentator)
                    ? const Icon(FluentIcons.checkmark_24_regular)
                    : null,
                onSelected: (_) => _toggleCommentator(commentator),
              ),
            ),
          ],
        ),
        ctx.MenuItem<Object>.submenu(
          label: _buildRtlMenuText('קישורים'),
          icon: const Icon(FluentIcons.link_24_regular),
          enabled: relevantLinks.isNotEmpty,
          items: relevantLinks
              .map<ctx.ContextMenuEntry<Object>>(
                (link) => ctx.MenuItem<Object>(
                  label: Text(link.heRef, textDirection: TextDirection.rtl),
                  onSelected: (_) {
                    openBook(
                      context,
                      TextBook(title: utils.getTitleFromPath(link.path2)),
                      link.index2 - 1,
                      '',
                      ignoreHistory: false,
                    );
                  },
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  PdfViewerParams _buildPdfViewerParams() {
    return PdfViewerParams(
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
          widget.tab.showLeftPane.value = false;
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
        // פס גלילה אנכי עם track מלא
        PdfScrollbar(
          controller: widget.tab.pdfViewerController,
          orientation: ScrollbarOrientation.right,
          trackThickness: 16.0,
          thumbMinSize: 50.0,
        ),
        // פס גלילה אופקי דינמי
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

                if (widget.tab.pdfHeadings != null && jumpedTitle.isNotEmpty) {
                  final lineNumber = widget.tab.pdfHeadings!
                      .getLineNumberForHeading(jumpedTitle);
                  if (lineNumber != null) {
                    widget.tab.currentTextLineNumber = lineNumber;
                  } else {
                    widget.tab.currentTextLineNumber = jumpedPage;
                  }
                } else {
                  widget.tab.currentTextLineNumber = jumpedPage;
                }
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

          if (widget.tab.pdfHeadings != null && title.isNotEmpty) {
            final lineNumber =
                widget.tab.pdfHeadings!.getLineNumberForHeading(title);
            if (lineNumber != null) {
              widget.tab.currentTextLineNumber = lineNumber;
            } else {
              widget.tab.currentTextLineNumber = currentPage;
            }
          } else {
            widget.tab.currentTextLineNumber = currentPage;
          }
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

        if (mounted &&
            (widget.tab.showLeftPane.value ||
                widget.tab.searchText.isNotEmpty)) {
          widget.tab.showLeftPane.value = true;
        }

        if (mounted && !widget.tab.showLeftPane.value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _pdfViewFocusNode.requestFocus();
            }
          });
        }
      },
    );
  }

  Widget _buildPdfViewerFromFile(String filePath) {
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
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
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
        child: ctx.ContextMenuRegion(
          contextMenu: _buildPdfContextMenu(),
          child: PdfViewer.file(
            filePath,
            controller: widget.tab.pdfViewerController,
            passwordProvider: () => passwordDialog(context),
            params: _buildPdfViewerParams(),
          ),
        ),
      ),
    );
  }

  Future<void> _saveActiveCommentators() async {
    final settingsBloc = context.read<SettingsBloc>();
    if (!settingsBloc.state.enablePerBookSettings) return;

    final existingSettings =
        await PdfBookPerBookSettings.load(widget.tab.book.title);
    final settings = PdfBookPerBookSettings(
      zoom: existingSettings?.zoom,
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

  Future<void> _loadPdfHeadingsAndLinks() async {
    try {
      // טעינת headings מה-DB
      final headings =
          await PdfHeadings.loadFromDatabase(widget.tab.book.title);
      if (headings != null) {
        widget.tab.pdfHeadings = headings;
      }

      // טעינת links
      final library = await DataRepository.instance.library;

      final textBook = library.findBookByTitle(widget.tab.book.title, TextBook);

      if (textBook != null) {
        if (textBook is TextBook) {
          final loadedLinks = await textBook.links;
          widget.tab.links = loadedLinks;
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

      if (widget.tab.pdfHeadings != null && title.isNotEmpty) {
        final lineNumber =
            widget.tab.pdfHeadings!.getLineNumberForHeading(title);

        if (lineNumber != null) {
          widget.tab.currentTextLineNumber = lineNumber;
          if (mounted) {
            setState(() {});
          }
        } else {
          widget.tab.currentTextLineNumber = newPage;
          if (mounted) {
            setState(() {});
          }
        }
      } else {
        widget.tab.currentTextLineNumber = newPage;
        if (mounted) {
          setState(() {});
        }
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
                widget.tab.showLeftPane.value = !widget.tab.showLeftPane.value;
              },
            ),
            actions: _buildPdfActions(context, wideScreen),
          ),
          body: Row(
            children: [
              _buildLeftPane(),
              BlocBuilder<PdfBookBloc, PdfBookState>(
                buildWhen: (prev, curr) {
                  if (prev is PdfBookLoaded && curr is PdfBookLoaded) {
                    return prev.sidebarWidth != curr.sidebarWidth ||
                        prev.showLeftPane != curr.showLeftPane;
                  }
                  return true;
                },
                builder: (context, state) {
                  if (state is! PdfBookLoaded) return const SizedBox.shrink();
                  if (!state.showLeftPane) {
                    return const SizedBox.shrink();
                  }
                  return ResizableDragHandle(
                    isVertical: true,
                    hitSize: 4,
                    onDragDelta: (delta) {
                      final newWidth =
                          (state.sidebarWidth - delta).clamp(200.0, 600.0);
                      _bloc.add(pdf_events.UpdateSidebarWidth(newWidth));
                    },
                    onDragEnd: () {
                      final current = _bloc.state;
                      if (current is PdfBookLoaded) {
                        context
                            .read<SettingsBloc>()
                            .add(UpdateSidebarWidth(current.sidebarWidth));
                      }
                    },
                  );
                },
              ),
              Expanded(
                child: Stack(
                  children: [
                    NotificationListener<UserScrollNotification>(
                      onNotification: (notification) {
                        if (!(widget.tab.pinLeftPane.value ||
                            (Settings.getValue<bool>('key-pin-sidebar') ??
                                false))) {
                          Future.microtask(() {
                            widget.tab.showLeftPane.value = false;
                            _pdfViewFocusNode.requestFocus();
                          });
                        }
                        return false;
                      },
                      child: Listener(
                        onPointerSignal: (event) {
                          if (event is PointerScrollEvent &&
                              !(widget.tab.pinLeftPane.value ||
                                  (Settings.getValue<bool>('key-pin-sidebar') ??
                                      false))) {
                            widget.tab.showLeftPane.value = false;
                            Future.microtask(() {
                              _pdfViewFocusNode.requestFocus();
                            });
                          }
                        },
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
                                        prev.loadSucceeded !=
                                            curr.loadSucceeded;
                                  }
                                  return true;
                                },
                                builder: (context, state) {
                                  if (state is! PdfBookLoaded) {
                                    return const Positioned.fill(
                                      child: ColoredBox(
                                        color: Color(0xFFFFFFFF),
                                        child: Center(
                                            child: CircularProgressIndicator()),
                                      ),
                                    );
                                  }
                                  if (state.isLoading) {
                                    return const Positioned.fill(
                                      child: ColoredBox(
                                        color: Color(0xFFFFFFFF),
                                        child: Center(
                                            child: CircularProgressIndicator()),
                                      ),
                                    );
                                  }
                                  if (!state.loadSucceeded) {
                                    return const Positioned.fill(
                                      child: Center(
                                          child: Text('Failed to load PDF')),
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
                    BlocBuilder<PdfBookBloc, PdfBookState>(
                      buildWhen: (prev, curr) {
                        if (prev is PdfBookLoaded && curr is PdfBookLoaded) {
                          return prev.showRightPane != curr.showRightPane ||
                              prev.isRightPaneHovering !=
                                  curr.isRightPaneHovering;
                        }
                        return true;
                      },
                      builder: (context, state) {
                        if (state is! PdfBookLoaded) {
                          return const SizedBox.shrink();
                        }
                        if (state.showRightPane) {
                          return const SizedBox.shrink();
                        }

                        final isHovering = state.isRightPaneHovering;

                        return Positioned(
                          left: 0,
                          top: MediaQuery.of(context).size.height * 0.10,
                          child: CommentaryPaneTooltip(
                            child: MouseRegion(
                              onEnter: (_) => _bloc.add(
                                  const pdf_events.SetRightPaneHovering(true)),
                              onExit: (_) => _bloc.add(
                                  const pdf_events.SetRightPaneHovering(false)),
                              child: GestureDetector(
                                onTap: () {
                                  _bloc.add(const pdf_events.ToggleRightPane(
                                      show: true));
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
                                        .withValues(
                                            alpha: isHovering ? 0.95 : 0.8),
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(40),
                                      bottomRight: Radius.circular(40),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.15),
                                        blurRadius: isHovering ? 8 : 4,
                                        offset: const Offset(2, 0),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: AnimatedOpacity(
                                      duration:
                                          const Duration(milliseconds: 150),
                                      opacity: isHovering ? 1.0 : 0.6,
                                      child: Icon(
                                        FluentIcons.chevron_right_24_regular,
                                        size: isHovering ? 24 : 18,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
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
                        final showZoomBar =
                            state is PdfBookLoaded && state.showZoomBar;
                        if (!showZoomBar ||
                            !widget.tab.pdfViewerController.isReady) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          top: 16,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: PdfZoomBar(
                              currentZoom:
                                  widget.tab.pdfViewerController.value.zoom,
                              onZoomIn: _zoomIn,
                              onZoomOut: _zoomOut,
                              onResetZoom: _resetZoom,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              BlocBuilder<PdfBookBloc, PdfBookState>(
                buildWhen: (prev, curr) {
                  if (prev is PdfBookLoaded && curr is PdfBookLoaded) {
                    return prev.showRightPane != curr.showRightPane ||
                        prev.rightPaneWidth != curr.rightPaneWidth;
                  }
                  return true;
                },
                builder: (context, state) {
                  if (state is! PdfBookLoaded) return const SizedBox.shrink();
                  if (!state.showRightPane) return const SizedBox.shrink();
                  return ResizableDragHandle(
                    isVertical: true,
                    hitSize: 4,
                    onDragDelta: (delta) {
                      final newWidth =
                          (state.rightPaneWidth + delta).clamp(250.0, 600.0);
                      _bloc.add(pdf_events.UpdateRightPaneWidth(newWidth));
                    },
                    onDragEnd: () {
                      final current = _bloc.state;
                      if (current is PdfBookLoaded) {
                        context.read<SettingsBloc>().add(
                            UpdateCommentaryPaneWidth(current.rightPaneWidth));
                      }
                    },
                  );
                },
              ),
              _buildRightPane(),
            ],
          ),
        ),
      );
    });
  }

  AnimatedSize _buildLeftPane() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      child: ValueListenableBuilder(
        valueListenable: widget.tab.showLeftPane,
        builder: (context, showLeftPane, child) =>
            BlocBuilder<PdfBookBloc, PdfBookState>(
          buildWhen: (prev, curr) {
            if (prev is PdfBookLoaded && curr is PdfBookLoaded) {
              return prev.sidebarWidth != curr.sidebarWidth;
            }
            return true;
          },
          builder: (context, state) {
            final width = state is PdfBookLoaded ? state.sidebarWidth : 300.0;
            return SizedBox(
              width: showLeftPane ? width : 0,
              child: child,
            );
          },
        ),
        child: Container(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
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
                          overlayColor:
                              WidgetStateProperty.all(Colors.transparent),
                        ),
                      ),
                      if (MediaQuery.of(context).size.width >= 600)
                        ValueListenableBuilder(
                          valueListenable: widget.tab.pinLeftPane,
                          builder: (context, pinLeftPanel, child) => IconButton(
                            onPressed:
                                (Settings.getValue<bool>('key-pin-sidebar') ??
                                        false)
                                    ? null
                                    : () {
                                        widget.tab.pinLeftPane.value =
                                            !widget.tab.pinLeftPane.value;
                                      },
                            icon: AnimatedRotation(
                              turns: (pinLeftPanel ||
                                      (Settings.getValue<bool>(
                                              'key-pin-sidebar') ??
                                          false))
                                  ? -0.125
                                  : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                (pinLeftPanel ||
                                        (Settings.getValue<bool>(
                                                'key-pin-sidebar') ??
                                            false))
                                    ? FluentIcons.pin_24_filled
                                    : FluentIcons.pin_24_regular,
                              ),
                            ),
                            color: (pinLeftPanel ||
                                    (Settings.getValue<bool>(
                                            'key-pin-sidebar') ??
                                        false))
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            isSelected: pinLeftPanel ||
                                (Settings.getValue<bool>('key-pin-sidebar') ??
                                    false),
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
                                pdfFilePath: widget.tab.book.path,
                                initialSearchText: widget.tab.searchText,
                                initialSearchOptions: widget.tab.searchOptions,
                                initialAlternativeWords:
                                    widget.tab.alternativeWords,
                                initialSpacingValues: widget.tab.spacingValues,
                                initialSearchMode: widget.tab.searchMode,
                                onSearchResultNavigated:
                                    _ensureSearchTabIsActive,
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
            ),
          ),
        ),
      ),
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
    if (!widget.tab.pdfViewerController.isReady) {
      return;
    }

    final currentPage = widget.tab.pdfViewerController.pageNumber ?? 1;
    final totalPages = widget.tab.pdfViewerController.pageCount;
    final nextPage = min(currentPage + 1, totalPages);

    widget.tab.pdfViewerController.goToPage(pageNumber: nextPage);

    // משיכת פוקוס חזרה לאחר שינוי עמוד
    if (!_pdfViewFocusNode.hasFocus) {
      _pdfViewFocusNode.requestFocus();
    }
  }

  void _goPreviousPage() {
    if (!widget.tab.pdfViewerController.isReady) {
      return;
    }

    final currentPage = widget.tab.pdfViewerController.pageNumber ?? 1;
    final prevPage = max(currentPage - 1, 1);

    widget.tab.pdfViewerController.goToPage(pageNumber: prevPage);

    // משיכת פוקוס חזרה לאחר שינוי עמוד
    if (!_pdfViewFocusNode.hasFocus) {
      _pdfViewFocusNode.requestFocus();
    }
  }

  void _startContinuousScroll(LogicalKeyboardKey key) {
    if (_scrollTimer != null) return;

    _currentScrollKey = key;

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

      // שמירה אקטיבית על הפוקוס - מונע את ה"בריחה" של המקלדת
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

    // למקרה שהפוקוס אבד בדיוק ברגע העצירה
    if (mounted && !_pdfViewFocusNode.hasFocus) {
      _pdfViewFocusNode.requestFocus();
    }
  }

  void _scrollUpSimple() {
    if (!widget.tab.pdfViewerController.isReady) {
      return;
    }

    final currentMatrix = widget.tab.pdfViewerController.value;
    final currentTranslation = currentMatrix.getTranslation();

    const double scrollAmount = 100.0;
    final newY = currentTranslation.y + scrollAmount;

    widget.tab.pdfViewerController.goTo(
      currentMatrix.clone()
        ..setTranslationRaw(
          currentTranslation.x,
          newY,
          currentTranslation.z,
        ),
    );
  }

  void _scrollDownSimple() {
    if (!widget.tab.pdfViewerController.isReady) {
      return;
    }

    final currentMatrix = widget.tab.pdfViewerController.value;
    final currentTranslation = currentMatrix.getTranslation();

    const double scrollAmount = 100.0;
    final newY = currentTranslation.y - scrollAmount;

    widget.tab.pdfViewerController.goTo(
      currentMatrix.clone()
        ..setTranslationRaw(
          currentTranslation.x,
          newY,
          currentTranslation.z,
        ),
    );
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
            onPressed: () =>
                widget.tab.pdfViewerController.goToPage(pageNumber: 1),
          ),
          icon: FluentIcons.arrow_previous_24_filled,
          tooltip: 'תחילת הספר (CTRL + HOME)',
          onPressed: () =>
              widget.tab.pdfViewerController.goToPage(pageNumber: 1),
        ),
        ActionButtonData(
          widget: IconButton(
            icon: const Icon(FluentIcons.chevron_left_24_regular),
            tooltip: 'הקודם',
            onPressed: () {
              if (widget.tab.pdfViewerController.isReady) {
                final currentPage =
                    widget.tab.pdfViewerController.pageNumber ?? 1;
                widget.tab.pdfViewerController.goToPage(
                  pageNumber: max(currentPage - 1, 1),
                );
              }
            },
          ),
          icon: FluentIcons.chevron_left_24_regular,
          tooltip: 'הקודם',
          onPressed: () {
            if (widget.tab.pdfViewerController.isReady) {
              final currentPage =
                  widget.tab.pdfViewerController.pageNumber ?? 1;
              widget.tab.pdfViewerController.goToPage(
                pageNumber: max(currentPage - 1, 1),
              );
            }
          },
        ),
        ActionButtonData(
          widget: PageNumberDisplay(controller: widget.tab.pdfViewerController),
          icon: FluentIcons.text_font_24_regular,
          tooltip: 'מספר עמוד',
          onPressed: null,
        ),
        ActionButtonData(
          widget: IconButton(
            onPressed: () {
              if (widget.tab.pdfViewerController.isReady) {
                final currentPage =
                    widget.tab.pdfViewerController.pageNumber ?? 1;
                widget.tab.pdfViewerController.goToPage(
                  pageNumber: min(currentPage + 1,
                      widget.tab.pdfViewerController.pageCount),
                );
              }
            },
            icon: const Icon(FluentIcons.chevron_right_24_regular),
            tooltip: 'הבא',
          ),
          icon: FluentIcons.chevron_right_24_regular,
          tooltip: 'הבא',
          onPressed: () {
            if (widget.tab.pdfViewerController.isReady) {
              final currentPage =
                  widget.tab.pdfViewerController.pageNumber ?? 1;
              widget.tab.pdfViewerController.goToPage(
                pageNumber: min(
                    currentPage + 1, widget.tab.pdfViewerController.pageCount),
              );
            }
          },
        ),
        ActionButtonData(
          widget: IconButton(
            icon: const Icon(FluentIcons.arrow_next_24_filled),
            tooltip: 'סוף הספר (CTRL + END)',
            onPressed: () => widget.tab.pdfViewerController
                .goToPage(pageNumber: widget.tab.pdfViewerController.pageCount),
          ),
          icon: FluentIcons.arrow_next_24_filled,
          tooltip: 'סוף הספר (CTRL + END)',
          onPressed: () => widget.tab.pdfViewerController
              .goToPage(pageNumber: widget.tab.pdfViewerController.pageCount),
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
            onPressed: () =>
                widget.tab.pdfViewerController.goToPage(pageNumber: 1),
          ),
          icon: FluentIcons.arrow_previous_24_filled,
          tooltip: 'תחילת הספר (CTRL + HOME)',
          onPressed: () =>
              widget.tab.pdfViewerController.goToPage(pageNumber: 1),
        ),
        ActionButtonData(
          widget: IconButton(
            icon: const Icon(FluentIcons.chevron_left_24_regular),
            tooltip: 'הקודם',
            onPressed: () {
              if (widget.tab.pdfViewerController.isReady) {
                final currentPage =
                    widget.tab.pdfViewerController.pageNumber ?? 1;
                widget.tab.pdfViewerController.goToPage(
                  pageNumber: max(currentPage - 1, 1),
                );
              }
            },
          ),
          icon: FluentIcons.chevron_left_24_regular,
          tooltip: 'הקודם',
          onPressed: () {
            if (widget.tab.pdfViewerController.isReady) {
              final currentPage =
                  widget.tab.pdfViewerController.pageNumber ?? 1;
              widget.tab.pdfViewerController.goToPage(
                pageNumber: max(currentPage - 1, 1),
              );
            }
          },
        ),
        ActionButtonData(
          widget: IconButton(
            onPressed: () {
              if (widget.tab.pdfViewerController.isReady) {
                final currentPage =
                    widget.tab.pdfViewerController.pageNumber ?? 1;
                widget.tab.pdfViewerController.goToPage(
                  pageNumber: min(currentPage + 1,
                      widget.tab.pdfViewerController.pageCount),
                );
              }
            },
            icon: const Icon(FluentIcons.chevron_right_24_regular),
            tooltip: 'הבא',
          ),
          icon: FluentIcons.chevron_right_24_regular,
          tooltip: 'הבא',
          onPressed: () {
            if (widget.tab.pdfViewerController.isReady) {
              final currentPage =
                  widget.tab.pdfViewerController.pageNumber ?? 1;
              widget.tab.pdfViewerController.goToPage(
                pageNumber: min(
                    currentPage + 1, widget.tab.pdfViewerController.pageCount),
              );
            }
          },
        ),
        ActionButtonData(
          widget: IconButton(
            icon: const Icon(FluentIcons.arrow_next_24_filled),
            tooltip: 'סוף הספר (CTRL + END)',
            onPressed: () => widget.tab.pdfViewerController
                .goToPage(pageNumber: widget.tab.pdfViewerController.pageCount),
          ),
          icon: FluentIcons.arrow_next_24_filled,
          tooltip: 'סוף הספר (CTRL + END)',
          onPressed: () => widget.tab.pdfViewerController
              .goToPage(pageNumber: widget.tab.pdfViewerController.pageCount),
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

  Widget _buildRightPane() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      child: BlocBuilder<PdfBookBloc, PdfBookState>(
        buildWhen: (prev, curr) {
          if (prev is PdfBookLoaded && curr is PdfBookLoaded) {
            return prev.showRightPane != curr.showRightPane ||
                prev.rightPaneWidth != curr.rightPaneWidth;
          }
          return true;
        },
        builder: (context, state) {
          final showRightPane = state is PdfBookLoaded && state.showRightPane;
          final width = state is PdfBookLoaded ? state.rightPaneWidth : 300.0;
          return ClipRect(
            child: SizedBox(
              width: showRightPane ? width : 0,
              child: showRightPane
                  ? Container(
                      color: Theme.of(context).colorScheme.surface,
                      child: PdfCommentaryPanel(
                        tab: widget.tab,
                        openBookCallback: (tab) {
                          if (tab is TextBookTab) {
                            openBook(context, tab.book, tab.index, '',
                                ignoreHistory: false);
                          }
                        },
                        fontSize: 16.0,
                        onClose: () {
                          _bloc.add(
                              const pdf_events.ToggleRightPane(show: false));
                        },
                        initialTabIndex: _rightPaneInitialTabIndex,
                      ),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}
