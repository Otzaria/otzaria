import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart' as ctx;
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart' as otz_links;
import 'package:otzaria/models/pdf_headings.dart';
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
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_event.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/open_book.dart';
import 'package:otzaria/utils/ref_helper.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
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
import 'package:otzaria/settings/per_book_settings.dart';
import 'package:otzaria/widgets/commentary_pane_tooltip.dart';
import 'package:otzaria/pdf_book/pdf_scrollbar.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;

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

  // מעקב אחרי מקשים לחוצים למניעת repeat
  final Set<LogicalKeyboardKey> _pressedKeys = {};

  // גלילה רציפה
  Timer? _scrollTimer;
  LogicalKeyboardKey? _currentScrollKey;

  // Throttling לגלילה - מניעת עומס בגלילה מהירה
  Timer? _scrollThrottleTimer;
  double _pendingScrollDeltaY = 0.0;
  static const Duration _scrollThrottleDuration =
      Duration(milliseconds: 100); // המתנה של 100ms אחרי סיום גלילה

  Future<String?>? _pdfPathFuture;
  String? _tempFilePath;

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

    // טעינת PDF bytes מה-DB ושמירה לקובץ זמני
    _pdfPathFuture = _loadPdfFileFromDb();

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

    // הוספת listener ל-PDF View Focus להחזרה אוטומטית
    _pdfViewFocusNode.addListener(() {
      if (!_pdfViewFocusNode.hasFocus) {
        final currentFocus = FocusManager.instance.primaryFocus;

        // אם הפוקוס עבר ל-Root Focus Scope או null (כלומר אין פוקוס ספציפי),
        // והחלונית השמאלית סגורה, החזר את הפוקוס ל-PDF
        if ((currentFocus != _searchFieldFocusNode &&
                currentFocus != _navigationFieldFocusNode) &&
            !widget.tab.showLeftPane.value) {
          // שימוש ב-SchedulerBinding למהירות מקסימלית
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                !_pdfViewFocusNode.hasFocus &&
                !widget.tab.showLeftPane.value) {
              _pdfViewFocusNode.requestFocus();
            }
          });
        }
      }
    });

    // הוספת listeners לשדות טקסט
    _searchFieldFocusNode.addListener(() {});
    _navigationFieldFocusNode.addListener(() {});

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

    // טעינת headings וlinks
    _loadPdfHeadingsAndLinks();

    // טעינת הגדרות פר-ספר
    _loadPerBookSettings();
  }

  Future<String?> _loadPdfFileFromDb() async {
    try {
      final provider = SqliteDataProvider.instance;
      final bytes = await provider.getPdfBytesFromDb(widget.tab.book);
      
      if (bytes == null) return null;

      final tempDir = await getTemporaryDirectory();
      final fileName = 'pdf_${widget.tab.book.title.hashCode}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${tempDir.path}/$fileName');
      
      await file.writeAsBytes(bytes);
      
      _tempFilePath = file.path;
      return file.path;
    } catch (e, stackTrace) {
      debugPrint('Error loading PDF to file: $e\n$stackTrace');
      return null;
    }
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

    // widget.tab.links ממוין לפי index1, אז אפשר להפסיק מוקדם
    for (final link in widget.tab.links) {
      if (link.index1 > range.endLine) break; // חרגנו מהטווח - אפשר להפסיק
      if (link.index1 < range.startLine) continue; // עדיין לא הגענו לטווח

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
    // links כבר ממוינים מהטעינה, לא צריך למיין שוב

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
    _openCommentaryPane();
  }

  void _toggleAllCommentators(List<String> commentators) {
    final allActive = widget.tab.activeCommentators.containsAll(commentators);
    if (allActive) {
      widget.tab.activeCommentators.removeAll(commentators);
    } else {
      widget.tab.activeCommentators.addAll(commentators);
    }
    _openCommentaryPane();
  }

  ctx.ContextMenu _buildPdfContextMenu() {
    final (commentators: relevantCommentators, links: relevantLinks) =
        _getRelevantContent();

    return ctx.ContextMenu(
      entries: [
        ctx.MenuItem(
          label: _buildRtlMenuText('חיפוש'),
          icon: const Icon(FluentIcons.search_24_regular),
          onSelected: (_) => _ensureSearchTabIsActive(),
        ),
        ctx.MenuItem.submenu(
          label: _buildRtlMenuText('מפרשים'),
          icon: const Icon(FluentIcons.book_24_regular),
          enabled: relevantCommentators.isNotEmpty,
          items: [
            ctx.MenuItem(
              label: _buildRtlMenuText('הצג את כל המפרשים'),
              icon: relevantCommentators.isNotEmpty &&
                      widget.tab.activeCommentators
                          .containsAll(relevantCommentators)
                  ? const Icon(FluentIcons.checkmark_24_regular)
                  : null,
              onSelected: (_) => _toggleAllCommentators(relevantCommentators),
            ),
            if (relevantCommentators.isNotEmpty) const ctx.MenuDivider(),
            ...relevantCommentators.map(
              (commentator) => ctx.MenuItem(
                label: Text(commentator, textDirection: TextDirection.rtl),
                icon: widget.tab.activeCommentators.contains(commentator)
                    ? const Icon(FluentIcons.checkmark_24_regular)
                    : null,
                onSelected: (_) => _toggleCommentator(commentator),
              ),
            ),
          ],
        ),
        ctx.MenuItem.submenu(
          label: _buildRtlMenuText('קישורים'),
          icon: const Icon(FluentIcons.link_24_regular),
          enabled: relevantLinks.isNotEmpty,
          items: relevantLinks
              .map(
                (link) => ctx.MenuItem(
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
      viewerOverlayBuilder: (context, size, handleLinkTap) => [
        Positioned.fill(
          child: ctx.ContextMenuRegion(
            contextMenu: _buildPdfContextMenu(),
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
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
        debugPrint(
            '🎯 onViewerReady called! Document has ${document.pages.length} pages');
        // 0. יצירת textSearcher רק אחרי שה-controller מוכן
        if (!mounted) return;
        textSearcher = PdfTextSearcher(pdfController)
          ..addListener(_onTextSearcherUpdated);
        // 1. הגדרת המידע הראשוני מהמסמך
        widget.tab.documentRef.value = controller.documentRef;
        widget.tab.outline.value = await document.loadOutline();

        // 1.1. שליחת אירוע DocumentReady ל-Bloc
        // ה-Bloc יטפל גם בשחזור הזום (מהגדרות פר-ספר או מ-savedZoom)
        _bloc.add(pdf_events.DocumentReady(
          documentRef: controller.documentRef,
          outline: widget.tab.outline.value,
          totalPages: document.pages.length,
        ));

        // 1.5. קפיצה לעמוד הנכון אם צריך
        if (widget.tab.pageNumber > 1 && controller.isReady) {
          debugPrint('📖 Jumping to page ${widget.tab.pageNumber}');
          controller.goToPage(pageNumber: widget.tab.pageNumber);
        }

        // 2. עדכון הכותרת הנוכחית
        final currentPage = widget.tab.pdfViewerController.isReady
            ? (widget.tab.pdfViewerController.pageNumber ?? 1)
            : widget.tab.pageNumber;
        final title = await refFromPageNumber(
            currentPage, widget.tab.outline.value, widget.tab.book.title);
        widget.tab.currentTitle.value = title;

        // 2.5. עדכון מספר השורה בטקסט לפי הכותרת הראשונית
        if (widget.tab.pdfHeadings != null && title.isNotEmpty) {
          final lineNumber =
              widget.tab.pdfHeadings!.getLineNumberForHeading(title);
          if (lineNumber != null) {
            widget.tab.currentTextLineNumber = lineNumber;
          }
        }

        // 3. התאמת רוחב בברירת מחדל (fit to width)
        // רק אם אין זום שמור מהגדרות פר-ספר
        if (!mounted) return;
        final settingsBloc = context.read<SettingsBloc>();
        final enablePerBookSettings = settingsBloc.state.enablePerBookSettings;

        // בדיקה אם צריך להתאים לרוחב
        bool shouldFitToWidth = true;
        if (enablePerBookSettings) {
          final settings =
              await PdfBookPerBookSettings.load(widget.tab.book.title);
          shouldFitToWidth = settings?.zoom == null;
        }

        // התאמת רוחב עם מרווח קטן
        if (shouldFitToWidth) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && controller.isReady) {
              final matrix = controller.calcMatrixFitWidthForPage(
                pageNumber: currentPage,
              );
              if (matrix != null) {
                // מעבר למטריצה המתאימה לרוחב
                controller.goTo(matrix);
                // הקטנת הזום ב-2% כדי להשאיר מרווח קטן
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

        // 4. הפעלת החיפוש הראשוני (עכשיו עם מנגנון ניסיונות חוזרים)
        _runInitialSearchIfNeeded();

        // 5. הצגת חלונית הצד אם צריך
        if (mounted &&
            (widget.tab.showLeftPane.value ||
                widget.tab.searchText.isNotEmpty)) {
          widget.tab.showLeftPane.value = true;
        }

        // 6. בקשת focus ל-PDF viewer אחרי שהכל מוכן
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
    return KeyboardListener(
      focusNode: _pdfViewFocusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent) {
          // התעלמות מאירועי repeat - רק לחיצה ראשונה
          if (_pressedKeys.contains(event.logicalKey)) return;
          _pressedKeys.add(event.logicalKey);

          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _goNextPage();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _goPreviousPage();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _startContinuousScroll(LogicalKeyboardKey.arrowUp);
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _startContinuousScroll(LogicalKeyboardKey.arrowDown);
          }
        } else if (event is KeyUpEvent) {
          _pressedKeys.remove(event.logicalKey);

          if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
              event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _stopContinuousScroll();
          }
        }
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
          params: _buildPdfViewerParams(),
        ),
      ),
    );
  }

  /// טעינת הגדרות פר-ספר
  Future<void> _loadPerBookSettings() async {
    final settingsBloc = context.read<SettingsBloc>();
    if (!settingsBloc.state.enablePerBookSettings) return;

    final settings = await PdfBookPerBookSettings.load(widget.tab.book.title);
    if (settings == null || !mounted) return;

    // החלת ההגדרות
    if (settings.zoom != null && widget.tab.pdfViewerController.isReady) {
      widget.tab.pdfViewerController.setZoom(
        widget.tab.pdfViewerController.centerPosition,
        settings.zoom!,
      );
    }
  }

  @override
  void dispose() {
    _stopContinuousScroll();
    _scrollThrottleTimer?.cancel(); // ניקוי throttle timer
    textSearcher?.removeListener(_onTextSearcherUpdated);
    widget.tab.pdfViewerController.removeListener(_onPdfViewerControllerUpdate);
    // הסרת listeners למניעת דליפות זיכרון
    _leftPaneTabController?.removeListener(_leftPaneTabControllerListener);
    widget.tab.showLeftPane.removeListener(_showLeftPaneListener);
    _leftPaneTabController?.dispose();
    _searchFieldFocusNode.dispose();
    _navigationFieldFocusNode.dispose();
    _pdfViewFocusNode.dispose();
    _settingsSub.cancel();
    _bloc.close();
    
    if (_tempFilePath != null) {
      final file = File(_tempFilePath!);
      if (file.existsSync()) {
        file.delete().catchError((e) {
          debugPrint('Error deleting temp PDF: $e');
          return file;
        });
      }
    }
    
    super.dispose();
  }

  /// איפוס הגדרות פר-ספר
  Future<void> _resetPerBookSettings() async {
    _bloc.add(const pdf_events.ResetPerBookSettings());
    if (mounted) {
      UiSnack.show('ההגדרות הפר-ספריות אופסו בהצלחה');
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
          // מיון ה-links פעם אחת לפי index1 לשיפור ביצועים
          loadedLinks.sort((a, b) => a.index1.compareTo(b.index1));
          widget.tab.links = loadedLinks;

          // הצגת דוגמאות של links
          if (widget.tab.links.isNotEmpty) {
            for (final link in widget.tab.links.take(3)) {
              debugPrint(
                  '  - Line ${link.index1}: ${link.heRef} (${link.connectionType})');
            }
          }
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e, stackTrace) {
      debugPrint('Error loading PDF headings and links: $e\n$stackTrace');
    }
  }

  int _lastComputedForPage = -1;
  void _onPdfViewerControllerUpdate() async {
    if (!widget.tab.pdfViewerController.isReady) return;

    // שמירת מצב הזום לשחזור אחרי rebuild
    widget.tab.savedZoom = widget.tab.pdfViewerController.value.zoom;

    final newPage = widget.tab.pdfViewerController.pageNumber ?? 1;
    if (newPage == widget.tab.pageNumber) return;
    widget.tab.pageNumber = newPage;
    final token = _lastComputedForPage = newPage;

    // עדכון מיידי של הכותרת עם מספר העמוד
    widget.tab.currentTitle.value = 'עמוד $newPage';

    final title = await refFromPageNumber(
        newPage, widget.tab.outline.value ?? [], widget.tab.book.title);
    if (token == _lastComputedForPage) {
      widget.tab.currentTitle.value = title;

      // עדכון מספר השורה בטקסט לפי הכותרת
      if (widget.tab.pdfHeadings != null && title.isNotEmpty) {
        final lineNumber =
            widget.tab.pdfHeadings!.getLineNumberForHeading(title);

        if (lineNumber != null) {
          widget.tab.currentTextLineNumber = lineNumber;
          if (mounted) {
            setState(() {});
          }
        } else {
          debugPrint('❌ No line number found for heading: "$title"');
          debugPrint(
              'Available headings: ${widget.tab.pdfHeadings!.headingsMap.keys.take(5).join(", ")}');
        }
      } else {
        debugPrint('❌ pdfHeadings is null or title is empty');
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

  /// מאזין לשינויים ב-Bloc (לטיפול ב-side effects אם צריך)
  void _onBlocStateChanged(BuildContext context, PdfBookState state) {
    // כרגע לא צריך side effects - הכל מנוהל דרך BlocBuilder
  }

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
                            // החזרת focus ל-PDF אחרי גלילה
                            _pdfViewFocusNode.requestFocus();
                          });
                        }
                        return false;
                      },
                      child: Listener(
                        onPointerSignal: (event) {
                          if (event is PointerScrollEvent) {
                            // טיפול בגלילת עכבר עם throttling
                            _handleThrottledScroll(event.scrollDelta.dy);

                            // הסתרת חלונית צד אם לא נעולה
                            if (!(widget.tab.pinLeftPane.value ||
                                (Settings.getValue<bool>('key-pin-sidebar') ??
                                    false))) {
                              widget.tab.showLeftPane.value = false;
                              // החזרת focus ל-PDF אחרי גלילה
                              Future.microtask(() {
                                _pdfViewFocusNode.requestFocus();
                              });
                            }
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
                              FutureBuilder<String?>(
                                future: _pdfPathFuture,
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  }

                                  if (snapshot.hasError) {
                                    return Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            FluentIcons.error_circle_24_regular,
                                            size: 64,
                                            color: Colors.red,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'שגיאה בטעינת הספר: ${snapshot.error}',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              color: Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  if (!snapshot.hasData ||
                                      snapshot.data == null) {
                                    return const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            FluentIcons
                                                .document_error_24_regular,
                                            size: 64,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(height: 16),
                                          Text(
                                            'לא ניתן לטעון את הספר',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  return _buildPdfViewerFromFile(
                                      snapshot.data!);
                                },
                              ),
                              // Loading and error indicators
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
                    // טאב צף לפתיחת חלונית המפרשים - עם 3 מצבים והדרכה
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
                        // מציג את הכפתור רק כשהחלונית סגורה
                        if (state.showRightPane) {
                          return const SizedBox.shrink();
                        }

                        final isHovering = state.isRightPaneHovering;

                        return Positioned(
                          left: 0, // צמוד לקצה
                          top: MediaQuery.of(context).size.height *
                              0.10, // למעלה במסך
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
                                  // מצב 1: סגור - בליטה קטנה, מצב 2: ריחוף - נשלף יותר
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
                    // סרגל זום
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
              // Divider לחלונית ימנית
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
              // חלונית ימנית למפרשים
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
  }

  void _goPreviousPage() {
    if (!widget.tab.pdfViewerController.isReady) {
      return;
    }

    final currentPage = widget.tab.pdfViewerController.pageNumber ?? 1;
    final prevPage = max(currentPage - 1, 1);

    widget.tab.pdfViewerController.goToPage(pageNumber: prevPage);
  }

  /// טיפול בגלילה עם debouncing למניעת עומס
  /// במקום לבצע goTo על כל אירוע, ממתינים עד שהמשתמש מפסיק לגלול
  void _handleThrottledScroll(double deltaY) {
    if (!widget.tab.pdfViewerController.isReady) return;

    // צבירת הדלתא
    _pendingScrollDeltaY += deltaY;

    // ביטול timer קודם אם קיים
    _scrollThrottleTimer?.cancel();

    // יצירת timer חדש שיבוצע רק אחרי שהמשתמש מפסיק לגלול
    _scrollThrottleTimer = Timer(_scrollThrottleDuration, () {
      if (!mounted || !widget.tab.pdfViewerController.isReady) return;

      final currentMatrix = widget.tab.pdfViewerController.value;
      final currentTranslation = currentMatrix.getTranslation();

      // גלילה אנכית - deltaY חיובי = גלילה למטה
      final newY = currentTranslation.y - _pendingScrollDeltaY;

      widget.tab.pdfViewerController.goTo(
        currentMatrix.clone()
          ..setTranslationRaw(
            currentTranslation.x,
            newY,
            currentTranslation.z,
          ),
      );

      // איפוס הדלתא הצבורה
      _pendingScrollDeltaY = 0.0;
    });
  }

  /// התחלת גלילה רציפה
  void _startContinuousScroll(LogicalKeyboardKey key) {
    // אם כבר יש גלילה פעילה, לא עושים כלום
    if (_scrollTimer != null) return;

    _currentScrollKey = key;

    // גלילה ראשונה מיידית
    if (key == LogicalKeyboardKey.arrowUp) {
      _scrollUpSimple();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _scrollDownSimple();
    }

    // התחלת גלילה רציפה - כל 100ms (10 פעמים בשנייה)
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || !widget.tab.pdfViewerController.isReady) {
        _stopContinuousScroll();
        return;
      }

      if (_currentScrollKey == LogicalKeyboardKey.arrowUp) {
        _scrollUpSimple();
      } else if (_currentScrollKey == LogicalKeyboardKey.arrowDown) {
        _scrollDownSimple();
      }
    });
  }

  /// עצירת גלילה רציפה
  void _stopContinuousScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _currentScrollKey = null;
  }

  /// גלילה פשוטה למעלה - כמו בעכבר
  void _scrollUpSimple() {
    if (!widget.tab.pdfViewerController.isReady) {
      return;
    }

    final currentMatrix = widget.tab.pdfViewerController.value;
    final currentTranslation = currentMatrix.getTranslation();

    // כמות גלילה זהה לגלילת עכבר (100 פיקסלים)
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

  /// גלילה פשוטה למטה - כמו בעכבר
  void _scrollDownSimple() {
    if (!widget.tab.pdfViewerController.isReady) {
      return;
    }

    final currentMatrix = widget.tab.pdfViewerController.value;
    final currentTranslation = currentMatrix.getTranslation();

    // כמות גלילה זהה לגלילת עכבר (100 פיקסלים)
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

    // החזרת פוקוס ל-PDF אחרי סגירת הדיאלוג
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _pdfViewFocusNode.requestFocus();
        }
      });
    }

    return result ?? false;
  }

  /// בניית כפתורי ה-AppBar עבור PDF
  List<Widget> _buildPdfActions(BuildContext context, bool wideScreen) {
    final screenWidth = MediaQuery.of(context).size.width;

    // נקבע כמה כפתורים להציג בהתאם לרוחב המסך
    int maxButtons;

    if (screenWidth < 400) {
      maxButtons = 2; // 2 כפתורים + "..." במסכים קטנים מאוד
    } else if (screenWidth < 500) {
      maxButtons = 4; // 4 כפתורים + "..." במסכים קטנים
    } else if (screenWidth < 600) {
      maxButtons = 6; // 6 כפתורים + "..." במסכים בינוניים קטנים
    } else if (screenWidth < 700) {
      maxButtons = 8; // 8 כפתורים + "..." במסכים בינוניים
    } else if (screenWidth < 900) {
      maxButtons = 10; // 10 כפתורים + "..." במסכים גדולים
    } else {
      maxButtons =
          999; // כל הכפתורים החיצוניים במסכים רחבים (ההדפסה תמיד בתפריט)
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

  /// בניית רשימת כפתורים בסדר ההצגה (מימין לשמאל ב-RTL)
  List<ActionButtonData> _buildDisplayOrderPdfActions(BuildContext context) {
    return [
      // 1) Text Button
      ActionButtonData(
        widget: _buildTextButton(
            context, widget.tab.book, widget.tab.pdfViewerController),
        icon: FluentIcons.document_text_24_regular,
        tooltip: 'פתח ספר במהדורת טקסט',
        onPressed: () => _handleTextButtonPress(context),
      ),

      // 2) Zoom In Button
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

      // 3) Zoom Out Button
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

      // 4) Search Button
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

      // 5-9) Navigation Buttons - רק אם לא בתצוגה משולבת
      if (!widget.isInCombinedView) ...[
        // 5) First Page Button
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

        // 6) Previous Page Button
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

        // 7) Page Number Display - תמיד מוצג!
        ActionButtonData(
          widget: PageNumberDisplay(controller: widget.tab.pdfViewerController),
          icon: FluentIcons.text_font_24_regular,
          tooltip: 'מספר עמוד',
          onPressed: null, // לא ניתן ללחיצה
        ),

        // 8) Next Page Button
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

        // 9) Last Page Button
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

  /// כפתורים שתמיד יהיו בתפריט "..."
  List<ActionButtonData> _buildAlwaysInMenuPdfActions(BuildContext context) {
    return [
      // כפתורי ניווט - רק בתצוגה משולבת
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

      // 1) הצג הערות אישיות
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.note_24_regular),
          tooltip: 'הצג הערות אישיות',
          onPressed: () {
            setState(() {
              _rightPaneInitialTabIndex = 2; // טאב הערות אישיות
            });
            _bloc.add(const pdf_events.ToggleRightPane(show: true));
          },
        ),
        icon: FluentIcons.note_24_regular,
        tooltip: 'הצג הערות אישיות',
        onPressed: () {
          setState(() {
            _rightPaneInitialTabIndex = 2; // טאב הערות אישיות
          });
          _bloc.add(const pdf_events.ToggleRightPane(show: true));
        },
      ),

      // 2) הוספת הערה
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

      // 3) הוסף סימניה
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

      // 4) איפוס הגדרות פר-ספר - לא בתצוגה משולבת
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

      // 5) הדפסה - לא בתצוגה משולבת
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

      // תת-תפריט "פעולות נוספות" - רק בתצוגה משולבת
      if (widget.isInCombinedView)
        ActionButtonData(
          widget: const SizedBox.shrink(), // לא נראה כי זה בתפריט
          icon: FluentIcons.more_horizontal_24_regular,
          tooltip: 'פעולות נוספות',
          onPressed: null, // לא ניתן ללחיצה - זה submenu
          submenuItems: [
            // איפוס הגדרות פר-ספר (מוצג רק כשההגדרה מופעלת)
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

  /// טיפול בלחיצה על כפתור הטקסט
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

  /// טיפול בלחיצה על כפתור הסימניה
  void _handleBookmarkPress(BuildContext context) {
    if (!mounted) return;
    int index = widget.tab.pdfViewerController.isReady
        ? (widget.tab.pdfViewerController.pageNumber ?? 1)
        : 1;

    // נסה למצוא כותרת מה-outline
    String ref;
    final outline = widget.tab.outline.value;
    debugPrint(
        'DEBUG Bookmark: outline is ${outline == null ? "null" : "not null"}, isEmpty: ${outline?.isEmpty}, page: $index');
    if (outline != null && outline.isNotEmpty) {
      final heading = _findHeadingForPage(outline, index);
      debugPrint('DEBUG Bookmark: heading found: $heading');
      if (heading != null) {
        ref = '${widget.tab.title} $heading'; // שם הספר + הכותרת
      } else {
        ref =
            '${widget.tab.title} עמוד $index'; // אם אין כותרת, הצג עם מספר עמוד
      }
    } else {
      ref =
          '${widget.tab.title} עמוד $index'; // אם אין outline, הצג עם מספר עמוד
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

    // החזרת פוקוס ל-PDF אחרי הוספת סימניה
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _pdfViewFocusNode.requestFocus();
        }
      });
    }
  }

  /// מוצא את הכותרת המתאימה לעמוד מסוים ב-outline
  String? _findHeadingForPage(List<PdfOutlineNode> outline, int page) {
    PdfOutlineNode? bestMatch;

    void searchNodes(List<PdfOutlineNode> nodes) {
      for (final node in nodes) {
        final nodePage = node.dest?.pageNumber;
        debugPrint(
            'DEBUG: checking node "${node.title}" with page $nodePage against target page $page');
        if (nodePage != null && nodePage <= page) {
          // אם זה העמוד המדויק או קרוב יותר מהמצא הקודם
          if (bestMatch == null ||
              nodePage > (bestMatch!.dest?.pageNumber ?? 0)) {
            bestMatch = node;
            debugPrint(
                'DEBUG: new bestMatch: "${node.title}" at page $nodePage');
          }
          // חפש גם בילדים
          if (node.children.isNotEmpty) {
            searchNodes(node.children);
          }
        }
      }
    }

    searchNodes(outline);
    return bestMatch?.title;
  }

  /// טיפול בלחיצה על כפתור הוספת הערה
  Future<void> _handleAddNotePress(BuildContext context) async {
    final currentPage = widget.tab.pdfViewerController.isReady
        ? (widget.tab.pdfViewerController.pageNumber ?? 1)
        : 1;

    // שמירת הערכים מה-context לפני ה-async gap
    final notesBloc = context.read<PersonalNotesBloc>();
    final dialogContext = context;

    // קבלת טווח השורות של העמוד הנוכחי
    final library = await DataRepository.instance.library;
    final textBook = library.findBookByTitle(widget.tab.book.title, TextBook);

    String dialogTitle = 'הוסף הערה לעמוד $currentPage';
    if (textBook != null && widget.tab.pdfHeadings != null) {
      // מציאת טווח השורות של העמוד
      final currentTitle = widget.tab.currentTitle.value;
      final currentLineNumber =
          widget.tab.pdfHeadings!.getLineNumberForHeading(currentTitle);

      if (currentLineNumber != null) {
        // מציאת הכותרת הבאה כדי לדעת את טווח השורות
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

    // החזרת פוקוס ל-PDF אחרי סגירת הדיאלוג
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _pdfViewFocusNode.requestFocus();
        }
      });
    }

    if (!mounted) return;

    if (noteContent == null) {
      debugPrint('Note dialog cancelled');
      return;
    }

    final trimmed = noteContent.contentPlain.trim();
    if (trimmed.isEmpty) {
      UiSnack.show('ההערה ריקה, לא נשמרה');
      return;
    }

    if (!mounted) return;

    try {
      // תמיד נשתמש בשם הספר המקורי כדי שההערות יהיו משותפות
      final bookId = widget.tab.book.title;

      debugPrint('Adding note to bookId: $bookId, page: $currentPage');
      debugPrint('Note content: $trimmed');

      notesBloc.add(AddPersonalNote(
        bookId: bookId,
        lineNumber: currentPage,
        content: noteContent.content,
        contentPlain: noteContent.contentPlain,
        contentFormat: noteContent.contentFormat,
      ));

      // פתיחת חלונית המפרשים בטאב ההערות
      setState(() {
        _rightPaneInitialTabIndex = 2; // טאב הערות אישיות
      });
      _bloc.add(const pdf_events.ToggleRightPane(show: true));

      // המתנה קצרה לעדכון ה-bloc
      await Future.delayed(const Duration(milliseconds: 100));

      debugPrint('Note added successfully');

      if (textBook != null) {
        UiSnack.show('ההערה נשמרה ותוצג בכל שורות העמוד בתצוגת הטקסט');
      } else {
        UiSnack.show('ההערה נשמרה בהצלחה');
      }
    } catch (e, stackTrace) {
      debugPrint('Error adding note: $e');
      debugPrint('Stack trace: $stackTrace');
      UiSnack.showError('שמירת ההערה נכשלה: $e');
    }
  }

  /// טיפול בלחיצה על כפתור ההדפסה
  Future<void> _handlePrintPress(BuildContext context) async {
    final file = File(widget.tab.book.path);
    final fileName = file.uri.pathSegments.last;
    await Printing.sharePdf(
      bytes: await file.readAsBytes(),
      filename: fileName,
    );

    // החזרת פוקוס ל-PDF אחרי סגירת דיאלוג ההדפסה
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

  /// בניית חלונית ימנית למפרשים וקישורים
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