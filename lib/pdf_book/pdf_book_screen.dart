import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/pdf_page_number_dispaly.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_event.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/utils/open_book.dart';
import 'package:otzaria/utils/ref_helper.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:provider/provider.dart';
import 'pdf_search_screen.dart';
import 'pdf_thumbnails_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'pdf_outlines_screen.dart';
import 'package:otzaria/widgets/password_dialog.dart';
import 'package:printing/printing.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/utils/page_converter.dart';
import 'package:flutter/gestures.dart';
import 'package:otzaria/widgets/responsive_action_bar.dart';

class PdfBookScreen extends StatefulWidget {
  final PdfBookTab tab;

  const PdfBookScreen({
    super.key,
    required this.tab,
  });

  @override
  State<PdfBookScreen> createState() => _PdfBookScreenState();
}

class _PdfBookScreenState extends State<PdfBookScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  late final PdfViewerController pdfController;
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  PdfTextSearchResult? _searchResult;
  TabController? _leftPaneTabController;
  int _currentLeftPaneTabIndex = 0;
  final FocusNode _searchFieldFocusNode = FocusNode();
  final FocusNode _navigationFieldFocusNode = FocusNode();
  late final ValueNotifier<double> _sidebarWidth;
  late final StreamSubscription<SettingsState> _settingsSub;

  Future<void> _runInitialSearchIfNeeded() async {
    final controller = widget.tab.searchController;
    final String query = controller.text.trim();
    if (query.isEmpty) return;

    debugPrint('DEBUG: Running initial search for "$query"');

    // Syncfusion: Use controller.searchText() instead of PdfTextSearcher
    if (widget.tab.isDocumentLoaded) {
      _searchResult = pdfController.searchText(query);
      if (_searchResult != null && _searchResult!.hasResult) {
        widget.tab.pdfSearchResult = _searchResult;
        widget.tab.searchText = query;
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  void _ensureSearchTabIsActive() {
    widget.tab.showLeftPane.value = true;
    if (_leftPaneTabController != null && _leftPaneTabController!.index != 1) {
      _leftPaneTabController!.animateTo(1);
    }
    _searchFieldFocusNode.requestFocus();
  }

  @override
  void initState() {
    super.initState();

    pdfController = PdfViewerController();

    // Syncfusion doesn't use PdfTextSearcher - search is done via controller.searchText()
    // Search result will be stored in _searchResult

    widget.tab.pdfViewerController = pdfController;

    debugPrint('DEBUG: אתחול PDF טאב - דף התחלתי: ${widget.tab.pageNumber}');

    _sidebarWidth = ValueNotifier<double>(
        Settings.getValue<double>('key-sidebar-width', defaultValue: 300)!);

    _settingsSub = context.read<SettingsBloc>().stream.listen((state) {
      _sidebarWidth.value = state.sidebarWidth;
    });

    pdfController.addListener(_onPdfViewerControllerUpdate);
    if (widget.tab.searchText.isNotEmpty) {
      _currentLeftPaneTabIndex = 1;
    } else {
      _currentLeftPaneTabIndex = 0;
    }

    _leftPaneTabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: _currentLeftPaneTabIndex,
    );
    if (_currentLeftPaneTabIndex == 1) {
      _searchFieldFocusNode.requestFocus();
    } else {
      _navigationFieldFocusNode.requestFocus();
    }
    _leftPaneTabController!.addListener(() {
      if (_currentLeftPaneTabIndex != _leftPaneTabController!.index) {
        setState(() {
          _currentLeftPaneTabIndex = _leftPaneTabController!.index;
        });
        if (_leftPaneTabController!.index == 1) {
          _searchFieldFocusNode.requestFocus();
        } else if (_leftPaneTabController!.index == 0) {
          _navigationFieldFocusNode.requestFocus();
        }
      }
    });
    widget.tab.showLeftPane.addListener(() {
      if (widget.tab.showLeftPane.value) {
        if (_leftPaneTabController!.index == 1) {
          _searchFieldFocusNode.requestFocus();
        } else if (_leftPaneTabController!.index == 0) {
          _navigationFieldFocusNode.requestFocus();
        }
      }
    });
  }

  int _lastComputedForPage = -1;
  void _onPdfViewerControllerUpdate() async {
    // Syncfusion: Check isDocumentLoaded instead of isReady
    if (!widget.tab.isDocumentLoaded) return;
    final newPage = widget.tab.pdfViewerController.pageNumber;
    if (newPage == widget.tab.pageNumber) return;
    widget.tab.pageNumber = newPage;
    final token = _lastComputedForPage = newPage;
    final title = await refFromPageNumber(
        newPage,
        widget.tab.outline.value ?? [],
        widget.tab.book.title,
        widget.tab.document.value);
    if (token == _lastComputedForPage) {
      widget.tab.currentTitle.value = title;
    }
  }

  @override
  void dispose() {
    // Syncfusion search doesn't need listener removal
    widget.tab.pdfViewerController.removeListener(_onPdfViewerControllerUpdate);
    _leftPaneTabController?.dispose();
    _searchFieldFocusNode.dispose();
    _navigationFieldFocusNode.dispose();
    _sidebarWidth.dispose();
    _settingsSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(builder: (context, constrains) {
      final wideScreen = (MediaQuery.of(context).size.width >= 600);
      return CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
              _ensureSearchTabIsActive,
          LogicalKeySet(LogicalKeyboardKey.arrowRight): _goNextPage,
          LogicalKeySet(LogicalKeyboardKey.arrowLeft): _goPreviousPage,
          LogicalKeySet(LogicalKeyboardKey.arrowDown): _goNextPage,
          LogicalKeySet(LogicalKeyboardKey.arrowUp): _goPreviousPage,
          LogicalKeySet(LogicalKeyboardKey.pageDown): _goNextPage,
          LogicalKeySet(LogicalKeyboardKey.pageUp): _goPreviousPage,
        },
        child: Focus(
          focusNode: FocusNode(),
          autofocus: !Platform.isAndroid,
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
                icon: const Icon(Icons.menu),
                tooltip: 'חיפוש וניווט',
                onPressed: () {
                  widget.tab.showLeftPane.value =
                      !widget.tab.showLeftPane.value;
                },
              ),
              actions: _buildPdfActions(context, wideScreen),
            ),
            body: Row(
              children: [
                _buildLeftPane(),
                ValueListenableBuilder(
                  valueListenable: widget.tab.showLeftPane,
                  builder: (context, show, child) => show
                      ? MouseRegion(
                          cursor: SystemMouseCursors.resizeColumn,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onHorizontalDragUpdate: (details) {
                              final newWidth =
                                  (_sidebarWidth.value - details.delta.dx)
                                      .clamp(200.0, 600.0);
                              _sidebarWidth.value = newWidth;
                            },
                            onHorizontalDragEnd: (_) {
                              context
                                  .read<SettingsBloc>()
                                  .add(UpdateSidebarWidth(_sidebarWidth.value));
                            },
                            child: const VerticalDivider(width: 4),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Expanded(
                  child: NotificationListener<UserScrollNotification>(
                    onNotification: (notification) {
                      if (!(widget.tab.pinLeftPane.value ||
                          (Settings.getValue<bool>('key-pin-sidebar') ??
                              false))) {
                        Future.microtask(() {
                          widget.tab.showLeftPane.value = false;
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
                        }
                      },
                      child: Selector<SettingsBloc, bool>(
                        selector: (context, bloc) => bloc.state.isDarkMode,
                        builder: (context, isDarkMode, child) => ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            Colors.white,
                            isDarkMode ? BlendMode.difference : BlendMode.dst,
                          ),
                          child: child!,
                        ),
                        child: SfPdfViewer.file(
                          File(widget.tab.book.path),
                          key: _pdfViewerKey,
                          controller: widget.tab.pdfViewerController,
                          initialPageNumber: widget.tab.pageNumber,
                          canShowScrollHead: true,
                          canShowScrollStatus: true,
                          pageLayoutMode: PdfPageLayoutMode.continuous,
                          scrollDirection: PdfScrollDirection.vertical,
                          interactionMode: PdfInteractionMode.selection,
                          onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                            // 1. הגדרת המידע הראשוני מהמסמך
                            widget.tab.document.value = details.document;
                            // Convert PdfBookmarkBase to List<PdfBookmark>
                            final bookmarks = details.document.bookmarks;
                            widget.tab.outline.value = bookmarks.count > 0
                                ? List<PdfBookmark>.generate(
                                    bookmarks.count,
                                    (index) => bookmarks[index],
                                  )
                                : [];
                            widget.tab.isDocumentLoaded = true;

                            // 2. עדכון הכותרת הנוכחית
                            refFromPageNumber(
                              widget.tab.pdfViewerController.pageNumber,
                              widget.tab.outline.value,
                              widget.tab.book.title,
                              widget.tab.document.value,
                            ).then((title) {
                              widget.tab.currentTitle.value = title;
                            });

                            // 3. הפעלת החיפוש הראשוני
                            _runInitialSearchIfNeeded();

                            // 4. הצגת חלונית הצד אם צריך
                            if (mounted &&
                                (widget.tab.showLeftPane.value ||
                                    widget.tab.searchText.isNotEmpty)) {
                              widget.tab.showLeftPane.value = true;
                            }
                          },
                          onDocumentLoadFailed:
                              (PdfDocumentLoadFailedDetails details) {
                            // טיפול בשגיאות טעינה, כולל סיסמה
                            if (details.error
                                .toLowerCase()
                                .contains('password')) {
                              passwordDialog(context).then((password) {
                                if (password != null && password.isNotEmpty) {
                                  // TODO: Reload document with password
                                  // Syncfusion doesn't have direct password support in viewer
                                  // Need to decrypt PDF first or use SfPdfViewer.memory with decrypted bytes
                                }
                              });
                            }
                          },
                          onPageChanged: (PdfPageChangedDetails details) {
                            widget.tab.pageNumber = details.newPageNumber;
                            // עדכון כותרת נוכחית
                            refFromPageNumber(
                              details.newPageNumber,
                              widget.tab.outline.value ?? [],
                              widget.tab.book.title,
                              widget.tab.document.value,
                            ).then((title) {
                              widget.tab.currentTitle.value = title;
                            });
                          },
                          onTextSelectionChanged:
                              (PdfTextSelectionChangedDetails details) {
                            // טיפול בבחירת טקסט - יכול להיות שימושי בעתיד
                            // כרגע לא נדרש
                          },
                        ),
                      ), // SfPdfViewer (Selector child)
                    ), // Selector
                  ), // Listener
                ), // NotificationListener
              ],
            ),
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
            ValueListenableBuilder<double>(
          valueListenable: _sidebarWidth,
          builder: (context, width, child2) => SizedBox(
            width: showLeftPane ? width : 0,
            child: child2!,
          ),
          child: child,
        ),
        child: Container(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: ClipRect(
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(child: _buildCustomTab('ניווט', 0)),
                                  Container(
                                      height: 24,
                                      width: 1,
                                      color: Colors.grey.shade400,
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 2)),
                                  Expanded(child: _buildCustomTab('חיפוש', 1)),
                                  Container(
                                      height: 24,
                                      width: 1,
                                      color: Colors.grey.shade400,
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 2)),
                                  Expanded(child: _buildCustomTab('דפים', 2)),
                                ],
                              ),
                              Container(
                                height: 1,
                                color: Theme.of(context).dividerColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: widget.tab.pinLeftPane,
                      builder: (context, pinLeftPanel, child) =>
                          MediaQuery.of(context).size.width < 600
                              ? const SizedBox.shrink()
                              : IconButton(
                                  onPressed: (Settings.getValue<bool>(
                                              'key-pin-sidebar') ??
                                          false)
                                      ? null
                                      : () {
                                          widget.tab.pinLeftPane.value =
                                              !widget.tab.pinLeftPane.value;
                                        },
                                  icon: const Icon(Icons.push_pin),
                                  isSelected: pinLeftPanel ||
                                      (Settings.getValue<bool>(
                                              'key-pin-sidebar') ??
                                          false),
                                ),
                    ),
                  ],
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
                          document: widget.tab.document.value,
                        ),
                      ),
                      PdfBookSearchView(
                        pdfController: widget.tab.pdfViewerController,
                        searchController: widget.tab.searchController,
                        focusNode: _searchFieldFocusNode,
                        outline: widget.tab.outline.value,
                        bookTitle: widget.tab.book.title,
                        initialSearchText: widget.tab.searchText,
                        onSearchResultNavigated: _ensureSearchTabIsActive,
                      ),
                      // Thumbnails tab
                      ValueListenableBuilder(
                        valueListenable: widget.tab.document,
                        builder: (context, document, child) => ThumbnailsView(
                          document: document,
                          controller: widget.tab.pdfViewerController,
                          filePath: widget.tab.book.path,
                        ),
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

  void _goNextPage() {
    if (widget.tab.isDocumentLoaded) {
      final nextPage = min(widget.tab.pdfViewerController.pageNumber + 1,
          widget.tab.pdfViewerController.pageCount);
      widget.tab.pdfViewerController.jumpToPage(nextPage);
    }
  }

  void _goPreviousPage() {
    if (widget.tab.isDocumentLoaded) {
      final prevPage = max(widget.tab.pdfViewerController.pageNumber - 1, 1);
      widget.tab.pdfViewerController.jumpToPage(prevPage);
    }
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
    return result ?? false;
  }

  Widget _buildCustomTab(String text, int index) {
    final controller = _leftPaneTabController;
    if (controller == null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
        ),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final isSelected = controller.index == index;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              controller.animateTo(index);
            },
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  controller.animateTo(index);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    border: isSelected
                        ? Border(
                            bottom: BorderSide(
                                color: Theme.of(context).primaryColor,
                                width: 2))
                        : null,
                  ),
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected ? Theme.of(context).primaryColor : null,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
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
        icon: Icons.article,
        tooltip: 'פתח ספר במהדורת טקסט',
        onPressed: () => _handleTextButtonPress(context),
      ),

      // 2) Zoom In Button
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(Icons.zoom_in),
          tooltip: 'הגדל',
          onPressed: () {
            widget.tab.pdfViewerController.zoomLevel =
                widget.tab.pdfViewerController.zoomLevel * 1.25;
          },
        ),
        icon: Icons.zoom_in,
        tooltip: 'הגדל',
        onPressed: () {
          widget.tab.pdfViewerController.zoomLevel =
              widget.tab.pdfViewerController.zoomLevel * 1.25;
        },
      ),

      // 3) Zoom Out Button
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(Icons.zoom_out),
          tooltip: 'הקטן',
          onPressed: () {
            widget.tab.pdfViewerController.zoomLevel =
                widget.tab.pdfViewerController.zoomLevel * 0.8;
          },
        ),
        icon: Icons.zoom_out,
        tooltip: 'הקטן',
        onPressed: () {
          widget.tab.pdfViewerController.zoomLevel =
              widget.tab.pdfViewerController.zoomLevel * 0.8;
        },
      ),

      // 4) Search Button
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'חיפוש',
          onPressed: _ensureSearchTabIsActive,
        ),
        icon: Icons.search,
        tooltip: 'חיפוש',
        onPressed: _ensureSearchTabIsActive,
      ),

      // 5) First Page Button
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(Icons.first_page),
          tooltip: 'תחילת הספר',
          onPressed: () => widget.tab.pdfViewerController.jumpToPage(1),
        ),
        icon: Icons.first_page,
        tooltip: 'תחילת הספר',
        onPressed: () => widget.tab.pdfViewerController.jumpToPage(1),
      ),

      // 6) Previous Page Button
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'הקודם',
          onPressed: () => widget.tab.isDocumentLoaded
              ? widget.tab.pdfViewerController.jumpToPage(
                  max(widget.tab.pdfViewerController.pageNumber - 1, 1))
              : null,
        ),
        icon: Icons.chevron_left,
        tooltip: 'הקודם',
        onPressed: () => widget.tab.isDocumentLoaded
            ? widget.tab.pdfViewerController.jumpToPage(
                max(widget.tab.pdfViewerController.pageNumber - 1, 1))
            : null,
      ),

      // 7) Page Number Display - תמיד מוצג!
      ActionButtonData(
        widget: PageNumberDisplay(controller: widget.tab.pdfViewerController),
        icon: Icons.text_fields,
        tooltip: 'מספר עמוד',
        onPressed: null, // לא ניתן ללחיצה
      ),

      // 8) Next Page Button
      ActionButtonData(
        widget: IconButton(
          onPressed: () => widget.tab.isDocumentLoaded
              ? widget.tab.pdfViewerController.jumpToPage(min(
                  widget.tab.pdfViewerController.pageNumber + 1,
                  widget.tab.pdfViewerController.pageCount))
              : null,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'הבא',
        ),
        icon: Icons.chevron_right,
        tooltip: 'הבא',
        onPressed: () => widget.tab.isDocumentLoaded
            ? widget.tab.pdfViewerController.jumpToPage(min(
                widget.tab.pdfViewerController.pageNumber + 1,
                widget.tab.pdfViewerController.pageCount))
            : null,
      ),

      // 9) Last Page Button
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(Icons.last_page),
          tooltip: 'סוף הספר',
          onPressed: () => widget.tab.pdfViewerController
              .jumpToPage(widget.tab.pdfViewerController.pageCount),
        ),
        icon: Icons.last_page,
        tooltip: 'סוף הספר',
        onPressed: () => widget.tab.pdfViewerController
            .jumpToPage(widget.tab.pdfViewerController.pageCount),
      ),
    ];
  }

  /// כפתורים שתמיד יהיו בתפריט "..."
  List<ActionButtonData> _buildAlwaysInMenuPdfActions(BuildContext context) {
    return [
      // 1) הוספת סימניה
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(Icons.bookmark_add),
          tooltip: 'הוספת סימניה',
          onPressed: () => _handleBookmarkPress(context),
        ),
        icon: Icons.bookmark_add,
        tooltip: 'הוספת סימניה',
        onPressed: () => _handleBookmarkPress(context),
      ),

      // 2) הדפסה
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(Icons.print),
          tooltip: 'הדפס',
          onPressed: () => _handlePrintPress(context),
        ),
        icon: Icons.print,
        tooltip: 'הדפס',
        onPressed: () => _handlePrintPress(context),
      ),
    ];
  }

  /// טיפול בלחיצה על כפתור הטקסט
  Future<void> _handleTextButtonPress(BuildContext context) async {
    final currentPage = widget.tab.isDocumentLoaded
        ? widget.tab.pdfViewerController.pageNumber
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
    int index = widget.tab.isDocumentLoaded
        ? widget.tab.pdfViewerController.pageNumber
        : 1;
    bool bookmarkAdded = Provider.of<BookmarkBloc>(context, listen: false)
        .addBookmark(
            ref: '${widget.tab.title} עמוד $index',
            book: widget.tab.book,
            index: index);
    if (mounted) {
      UiSnack.show(
          bookmarkAdded ? 'הסימניה נוספה בהצלחה' : 'הסימניה כבר קיימת');
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
  }

  Widget _buildTextButton(
      BuildContext context, PdfBook book, PdfViewerController controller) {
    return FutureBuilder(
      future: DataRepository.instance.library
          .then((library) => library.findBookByTitle(book.title, TextBook)),
      builder: (context, snapshot) => snapshot.hasData
          ? IconButton(
              icon: const Icon(Icons.article),
              tooltip: 'פתח ספר במהדורת טקסט',
              onPressed: () async {
                final currentPage = widget.tab.isDocumentLoaded
                    ? controller.pageNumber
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
}
