import 'dart:io';
import 'package:otzaria/theme/app_tokens.dart';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/settings/settings_exports.dart' hide UpdateFontSize;
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/widgets/dialogs/password_dialog.dart';
import 'package:otzaria/pdf_book/view/pdf_scrollbar.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// פאנל תצוגה מקדימה של ספר בספרייה
/// מציג את תוכן הספר בלי כרטיסיות, בדומה לחלון העיון
class BookPreviewPanel extends StatefulWidget {
  final Book? book;
  final Function(int index)? onOpenInReader; // מקבל את המיקום הנוכחי

  const BookPreviewPanel({
    super.key,
    this.book,
    this.onOpenInReader,
  });

  @override
  State<BookPreviewPanel> createState() => _BookPreviewPanelState();
}

class _BookPreviewPanelState extends State<BookPreviewPanel> {
  TextBookTab? _currentTextTab;
  PdfViewerController? _pdfController;
  bool _isPdfViewerReady = false;
  bool _pdfFileExists = true;
  double _fontSize = 18.0; // ברירת מחדל לגודל פונט
  DateTime? _lastPdfPrimaryClickAt;
  Offset? _lastPdfPrimaryClickPosition;
  final GlobalKey _pdfPreviewToolbarKey = GlobalKey();
  final GlobalKey _pdfVerticalScrollbarKey = GlobalKey();
  final GlobalKey _pdfHorizontalScrollbarKey = GlobalKey();

  @override
  void didUpdateWidget(BookPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // אם הספר השתנה, נצור tab חדש
    if (widget.book != oldWidget.book) {
      _disposeCurrentTab();
      if (widget.book != null) {
        _createNewTab();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // קבלת גודל הפונט מההגדרות
    _fontSize = Settings.getValue<double>('key-font-size', defaultValue: 18.0)!;
    if (widget.book != null) {
      _createNewTab();
    }
  }

  @override
  void dispose() {
    _disposeCurrentTab();
    super.dispose();
  }

  void _disposeCurrentTab() {
    _currentTextTab?.dispose();
    _currentTextTab = null;
    _pdfController = null;
    _isPdfViewerReady = false;
  }

  void _createNewTab() {
    if (widget.book == null) return;

    // DocxBook/EpubBook יורשים מ-FileBook ולא מ-TextBook — העטיפה דרך
    // toTextBook משמרת id/categoryId/externalLibraryId שדרושים
    // ל-LibraryProviderManager (בלעדיהם getBookContent יחזיר תוכן ריק).
    final book = widget.book;
    final TextBook? textBook = book is TextBook
        ? book
        : book is DocxBook
        ? book.toTextBook()
        : book is EpubBook
        ? book.toTextBook()
        : null;

    if (textBook != null) {
      setState(() {
        _isPdfViewerReady = false;
        _currentTextTab = TextBookTab(
          book: textBook,
          index: 0,
          searchText: '',
          openLeftPane: false,
          splitedView: Settings.getValue<bool>('key-splited-view') ?? true,
        );
      });
    } else if (book is PdfBook) {
      final fileExists = File(book.path).existsSync();
      setState(() {
        _isPdfViewerReady = false;
        _pdfFileExists = fileExists;
        _pdfController = PdfViewerController();
      });
    }
  }

  void _openCurrentPreviewInReader() {
    if (widget.book is PdfBook) {
      final currentPage = (_pdfController != null && _pdfController!.isReady)
          ? (_pdfController!.pageNumber ?? 1)
          : 1;
      widget.onOpenInReader?.call(currentPage);
      return;
    }

    // DOCX עובר ל-TextBookTab דרך _createNewTab, ולכן _currentTextTab קיים
    // גם עבור DocxBook. בלי הבדיקה הזו לחיצה כפולה על preview של DOCX היתה
    // נופלת ל-fallback של 0 ומאבדת את מיקום הגלילה הנוכחי.
    if (_currentTextTab != null) {
      widget.onOpenInReader?.call(_currentTextTab!.index);
      return;
    }

    widget.onOpenInReader?.call(0);
  }

  bool _isPointerInsideWidget(GlobalKey key, Offset globalPosition) {
    final context = key.currentContext;
    if (context == null) return false;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }

    final widgetOrigin = renderObject.localToGlobal(Offset.zero);
    final widgetRect = widgetOrigin & renderObject.size;
    return widgetRect.contains(globalPosition);
  }

  bool _isPdfPreviewDoubleTapCandidate(PointerDownEvent event) {
    return event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton;
  }

  bool _isPointerInsidePdfChrome(Offset globalPosition) {
    return _isPointerInsideWidget(_pdfPreviewToolbarKey, globalPosition) ||
        _isPointerInsideWidget(_pdfVerticalScrollbarKey, globalPosition) ||
        _isPointerInsideWidget(_pdfHorizontalScrollbarKey, globalPosition);
  }

  void _handlePdfPreviewPointerDown(PointerDownEvent event) {
    if (!_isPdfPreviewDoubleTapCandidate(event)) {
      return;
    }

    if (_isPointerInsidePdfChrome(event.position)) {
      _lastPdfPrimaryClickAt = null;
      _lastPdfPrimaryClickPosition = null;
      return;
    }

    final now = DateTime.now();
    if (_lastPdfPrimaryClickAt != null &&
        _lastPdfPrimaryClickPosition != null &&
        now.difference(_lastPdfPrimaryClickAt!) <= kDoubleTapTimeout &&
        (event.position - _lastPdfPrimaryClickPosition!).distance <=
            kDoubleTapSlop) {
      _lastPdfPrimaryClickAt = null;
      _lastPdfPrimaryClickPosition = null;
      _openCurrentPreviewInReader();
      return;
    }

    _lastPdfPrimaryClickAt = now;
    _lastPdfPrimaryClickPosition = event.position;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.book == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              OtzariaIcons.otzaria_icon_2_page_line_24_regular,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.secondary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'בחר ספר לתצוגה מקדימה',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // אם זה ספר חיצוני
    if (widget.book is ExternalLibraryBook) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.link_24_regular,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.secondary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              widget.book!.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'ספר חיצוני - לחץ פעמיים לפתיחה',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ActionButton.recommended(
              text: 'פתח בעיון',
              icon: FluentIcons.open_24_regular,
              onPressed: () => widget.onOpenInReader?.call(0),
            ),
          ],
        ),
      );
    }

    // תצוגת ספר PDF
    if (widget.book is PdfBook && _pdfController != null) {
      return BlocBuilder<SettingsBloc, SettingsState>(
        buildWhen: (p, c) => p.compactMenuMode != c.compactMenuMode,
        builder: (context, settingsState) {
          final compact = settingsState.compactMenuMode;
          return Stack(
            children: [
              _buildPdfViewer((widget.book as PdfBook).path),
              Positioned(
                top: compact ? 6 : 8,
                left: compact ? 20 : 24,
                child: _PreviewToolbar(
                  key: _pdfPreviewToolbarKey,
                  compact: compact,
                  onZoomIn: () => _pdfController?.zoomUp(),
                  onZoomOut: () => _pdfController?.zoomDown(),
                  onOpen: _openCurrentPreviewInReader,
                ),
              ),
            ],
          );
        },
      );
    }

    // תצוגת ספר טקסט
    if (_currentTextTab == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, c) =>
          p.compactMenuMode != c.compactMenuMode ||
          p.defaultRemoveNikud != c.defaultRemoveNikud,
      builder: (context, settingsState) {
        final compact = settingsState.compactMenuMode;
        return Stack(
          children: [
            GestureDetector(
              onDoubleTap: _openCurrentPreviewInReader,
              child: BlocProvider.value(
                value: _currentTextTab!.bloc,
                child: BlocBuilder(
                  bloc: _currentTextTab!.bloc,
                  builder: (context, state) {
                    if (state is TextBookInitial) {
                      _currentTextTab!.bloc.add(
                        LoadContent(
                          fontSize: _fontSize,
                          showSplitView: false,
                          removeNikud: settingsState.defaultRemoveNikud,
                          loadCommentators: false,
                        ),
                      );
                      return _buildSkeletonLoading();
                    }
                    if (state is TextBookLoading) {
                      return _buildSkeletonLoading();
                    }
                    if (state is TextBookError) {
                      return Center(
                        child: Text(
                          'שגיאה: ${state.message}',
                        ),
                      );
                    }
                    if (state is TextBookLoaded) {
                      return CombinedView(
                        data: state.content,
                        textSize: _fontSize,
                        openBookCallback: (tab) {},
                        openLeftPaneTab: (index, {String? searchText}) {},
                        showCommentaryAsExpansionTiles: false,
                        tab: _currentTextTab!,
                        isPreviewMode: true,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
            Positioned(
              top: compact ? 10 : 14,
              left: compact ? 16 : 20,
              child: _PreviewToolbar(
                compact: compact,
                onZoomIn: () {
                  setState(() {
                    _fontSize = (_fontSize + 2).clamp(10.0, 50.0);
                  });
                  _currentTextTab!.bloc.add(UpdateFontSize(_fontSize));
                },
                onZoomOut: () {
                  setState(() {
                    _fontSize = (_fontSize - 2).clamp(10.0, 50.0);
                  });
                  _currentTextTab!.bloc.add(UpdateFontSize(_fontSize));
                },
                onOpen: () =>
                    widget.onOpenInReader?.call(_currentTextTab?.index ?? 0),
              ),
            ),
          ],
        );
      },
    );
  }

  /// בניית PDF viewer דרך נתיב הקובץ
  Widget _buildPdfViewer(String filePath) {
    if (!_pdfFileExists) {
      return const Center(
        child: Text('הספר איננו קיים'),
      );
    }
    return Stack(
      children: [
        PdfViewer.file(
          filePath,
          key: ValueKey('pdf_${widget.book!.title}'),
          initialPageNumber: 1,
          passwordProvider: () => passwordDialog(context),
          controller: _pdfController!,
          params: PdfViewerParams(
            backgroundColor: Theme.of(context).colorScheme.surface,
            zoomStepsDelegateProvider:
                const PdfViewerZoomStepsDelegateProviderSmart(),
            sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(
              maxScale: 10,
            ),
            horizontalCacheExtent: 0,
            verticalCacheExtent: 1,
            pageAnchor: PdfPageAnchor.top,
            margin: 4,
            onDocumentChanged: (document) {
              if (document != null || !_isPdfViewerReady || !mounted) return;
              setState(() => _isPdfViewerReady = false);
            },
            onViewerReady: (document, controller) {
              if (_isPdfViewerReady || !mounted) return;
              setState(() => _isPdfViewerReady = true);
            },
            viewerOverlayBuilder: (context, size, handleLinkTap) => [
              if (_isPdfViewerReady)
                KeyedSubtree(
                  key: _pdfVerticalScrollbarKey,
                  child: PdfScrollbar(
                    controller: _pdfController!,
                    orientation: ScrollbarOrientation.right,
                    trackThickness: 16.0,
                    thumbMinSize: 50.0,
                  ),
                ),
              if (_isPdfViewerReady)
                KeyedSubtree(
                  key: _pdfHorizontalScrollbarKey,
                  child: PdfHorizontalScrollbar(
                    controller: _pdfController!,
                    trackThickness: 10.0,
                  ),
                ),
            ],
          ),
        ),
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handlePdfPreviewPointerDown,
          ),
        ),
      ],
    );
  }

  Widget _buildSkeletonLoading() {
    final baseColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: _SkeletonLine(width: 0.25, height: 36, color: baseColor),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: _SkeletonLine(width: 0.2, height: 28, color: baseColor),
              ),
            ),
            ..._buildParagraph([0.95, 0.92, 0.88, 0.94, 0.85], baseColor),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: _SkeletonLine(width: 0.18, height: 28, color: baseColor),
              ),
            ),
            ..._buildParagraph([0.93, 0.89, 0.96, 0.87, 0.91, 0.82], baseColor),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: _SkeletonLine(width: 0.22, height: 28, color: baseColor),
              ),
            ),
            ..._buildParagraph([0.94, 0.88, 0.92, 0.86], baseColor),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildParagraph(List<double> widths, Color color) {
    return widths
        .map(
          (width) => Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: _SkeletonLine(width: width, height: 18, color: color),
            ),
          ),
        )
        .toList();
  }
}

class _SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _SkeletonLine({
    required this.width,
    required this.color,
    this.height = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: MediaQuery.of(context).size.width * width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppTokens.borderRadiusAll,
      ),
    );
  }
}

class _PreviewToolbar extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onOpen;
  final bool compact;

  const _PreviewToolbar({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onOpen,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      shape: AppTokens.roundedShape,
      elevation: 2,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BarButton.icon(
            compact: compact,
            tooltip: 'הגדל טקסט',
            icon: FluentIcons.zoom_in_24_regular,
            onPressed: onZoomIn,
          ),
          BarButton.icon(
            compact: compact,
            tooltip: 'הקטן טקסט',
            icon: FluentIcons.zoom_out_24_regular,
            onPressed: onZoomOut,
          ),
          BarButton.icon(
            compact: compact,
            tooltip: 'פתח בעיון (או לחץ פעמיים על הספר)',
            icon: FluentIcons.open_24_regular,
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}
