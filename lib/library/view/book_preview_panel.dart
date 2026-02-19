import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart'; // הוספת הייבוא של UUID
import 'package:otzaria/widgets/password_dialog.dart';
import 'package:otzaria/pdf_book/pdf_scrollbar.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';

/// פאנל תצוגה מקדימה של ספר בספרייה
/// מציג את תוכן הספר בלי כרטיסיות, בדומה לחלון העיון
class BookPreviewPanel extends StatefulWidget {
  final Book? book;
  final Function(int index)? onOpenInReader; // מקבל את המיקום הנוכחי
  final VoidCallback? onClose;

  const BookPreviewPanel({
    super.key,
    this.book,
    this.onOpenInReader,
    this.onClose,
  });

  @override
  State<BookPreviewPanel> createState() => _BookPreviewPanelState();
}

class _BookPreviewPanelState extends State<BookPreviewPanel> {
  TextBookTab? _currentTextTab;
  PdfViewerController? _pdfController;
  double _fontSize = 18.0; // ברירת מחדל לגודל פונט
  Future<String?>? _pdfPathFuture;
  String? _cachedPdfPath; // שמירת נתיב הקובץ כדי למנוע טעינה מחדש

  @override
  void didUpdateWidget(BookPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // אם הספר השתנה, נצור tab חדש
    if (widget.book != oldWidget.book && widget.book != null) {
      _disposeCurrentTab();
      _createNewTab();
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

    // ניקוי הקובץ הזמני בשיטת שגר-ושכח אסינכרונית לחלוטין
    if (_cachedPdfPath != null) {
      final String pathToDelete = _cachedPdfPath!;
      () async {
        try {
          final file = File(pathToDelete);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          debugPrint('Error deleting preview PDF: $e');
        }
      }();
    }
    _cachedPdfPath = null;
  }

  Future<String?> _loadPreviewPdfFile(PdfBook book) async {
    final bytes = await SqliteDataProvider.instance.getPdfBytesFromDb(book);
    if (bytes == null) return null;

    final tempDir = await getTemporaryDirectory();
    // שימוש ב-UUID ליצירת שם קובץ מובטח וייחודי
    final fileName = 'preview_${book.title.hashCode}_${const Uuid().v4()}.pdf';
    final file = File('${tempDir.path}/$fileName');

    await file.writeAsBytes(bytes);
    return file.path;
  }

  void _createNewTab() {
    if (widget.book == null) return;

    if (widget.book is TextBook) {
      debugPrint('📖 Preview: Creating TextBook tab for ${widget.book!.title}');
      setState(() {
        _currentTextTab = TextBookTab(
          book: widget.book as TextBook,
          index: 0,
          searchText: '',
          openLeftPane: false,
          splitedView: Settings.getValue<bool>('key-splited-view') ?? false,
        );
      });
    } else if (widget.book is PdfBook) {
      debugPrint('📄 Preview: Creating PdfBook tab for ${widget.book!.title}');
      setState(() {
        _pdfController = PdfViewerController();
        _cachedPdfPath = null;
        _pdfPathFuture = _loadPreviewPdfFile(widget.book as PdfBook);
      });
      debugPrint('📄 Preview: Started loading PDF bytes from DB');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.book == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.book_24_regular,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .secondary
                  .withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'בחר ספר לתצוגה מקדימה',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
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
              color: Theme.of(context)
                  .colorScheme
                  .secondary
                  .withValues(alpha: 0.3),
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
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => widget.onOpenInReader?.call(0),
              icon: const Icon(FluentIcons.open_24_regular),
              label: const Text('פתח בעיון'),
            ),
          ],
        ),
      );
    }

    // תצוגת ספר PDF
    if (widget.book is PdfBook) {
      debugPrint('📄 Preview: Building PDF view for ${widget.book!.title}');

      // אם יש נתיב שמור, השתמש בו ישירות
      if (_cachedPdfPath != null && _pdfController != null) {
        debugPrint('✅ Preview: Using cached PDF file path');
        return _buildPdfViewer(_cachedPdfPath!);
      }

      // אחרת, טען מה-Future
      if (_pdfController == null || _pdfPathFuture == null) {
        debugPrint('⏳ Preview: Waiting for PDF controller or future');
        return const Center(child: CircularProgressIndicator());
      }

      debugPrint('🔄 Preview: Building FutureBuilder for PDF');
      return FutureBuilder<String?>(
        future: _pdfPathFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            debugPrint('⏳ Preview: Still waiting for PDF file');
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            debugPrint('❌ Preview: Error loading PDF: ${snapshot.error}');
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    FluentIcons.error_circle_24_regular,
                    size: 64,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'שגיאה בטעינת הספר',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data == null) {
            debugPrint('❌ Preview: No PDF file received');
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    FluentIcons.document_error_24_regular,
                    size: 64,
                    color: Theme.of(context)
                        .colorScheme
                        .secondary
                        .withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'לא ניתן לטעון את הספר',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            );
          }

          // שמירת הנתיב ב-cache
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _cachedPdfPath == null) {
              setState(() {
                _cachedPdfPath = snapshot.data;
              });
            }
          });

          return _buildPdfViewer(snapshot.data!);
        },
      );
    }

    // תצוגת ספר טקסט
    if (_currentTextTab == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        // תוכן הספר (מלא את כל השטח)
        BlocProvider.value(
          value: _currentTextTab!.bloc,
          child: BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) {
              return BlocBuilder(
                bloc: _currentTextTab!.bloc,
                builder: (context, state) {
                  if (state is TextBookInitial) {
                    _currentTextTab!.bloc.add(
                      LoadContent(
                        fontSize: _fontSize,
                        showSplitView: false,
                        removeNikud: settingsState.defaultRemoveNikud,
                        loadCommentators: false, // אל תטען מפרשים בתצוגה מקדימה
                      ),
                    );
                    return _buildSkeletonLoading();
                  }

                  if (state is TextBookLoading) {
                    return _buildSkeletonLoading();
                  }

                  if (state is TextBookError) {
                    return Center(
                      child: Text('שגיאה: ${state.message}'),
                    );
                  }

                  if (state is TextBookLoaded) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 12.0, right: 0.0),
                      child: CombinedView(
                        data: state.content,
                        textSize: _fontSize,
                        openBookCallback: (tab) {},
                        openLeftPaneTab: (index, {String? searchText}) {},
                        showCommentaryAsExpansionTiles: false,
                        tab: _currentTextTab!,
                        isPreviewMode: true,
                      ),
                    );
                  }

                  return const SizedBox.shrink();
                },
              );
            },
          ),
        ),
        // כפתורים צפים בפינה השמאלית העליונה
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(FluentIcons.zoom_in_24_regular, size: 20),
                  tooltip: 'הגדל טקסט',
                  onPressed: () {
                    setState(() {
                      _fontSize = (_fontSize + 2).clamp(10.0, 50.0);
                    });
                    _currentTextTab!.bloc.add(
                      UpdateFontSize(_fontSize),
                    );
                  },
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                IconButton(
                  icon: const Icon(FluentIcons.zoom_out_24_regular, size: 20),
                  tooltip: 'הקטן את גודל הטקסט',
                  onPressed: () {
                    setState(() {
                      _fontSize = (_fontSize - 2).clamp(10.0, 50.0);
                    });
                    _currentTextTab!.bloc.add(
                      UpdateFontSize(_fontSize),
                    );
                  },
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                Container(
                  width: 1,
                  height: 24,
                  color: Theme.of(context).dividerColor,
                ),
                IconButton(
                  icon: const Icon(FluentIcons.open_24_regular, size: 20),
                  tooltip: 'פתח בעיון (או לחץ פעמיים על הספר)',
                  onPressed: () {
                    widget.onOpenInReader?.call(_currentTextTab?.index ?? 0);
                  },
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                if (widget.onClose != null)
                  Container(
                    width: 1,
                    height: 24,
                    color: Theme.of(context).dividerColor,
                  ),
                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(FluentIcons.dismiss_24_regular, size: 20),
                    tooltip: 'הסתר תצוגה מקדימה',
                    onPressed: widget.onClose,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// בניית PDF viewer דרך נתיב הקובץ
  Widget _buildPdfViewer(String filePath) {
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
            maxScale: 10,
            horizontalCacheExtent: 0,
            verticalCacheExtent: 1,
            pageAnchor: PdfPageAnchor.top,
            margin: 4,
            onViewerReady: (document, controller) {
              debugPrint('✅ Preview: PDF viewer ready');
            },
            viewerOverlayBuilder: (context, size, handleLinkTap) => [
              PdfScrollbar(
                controller: _pdfController!,
                orientation: ScrollbarOrientation.right,
                trackThickness: 16.0,
                thumbMinSize: 50.0,
              ),
              PdfHorizontalScrollbar(
                controller: _pdfController!,
                trackThickness: 10.0,
              ),
            ],
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(FluentIcons.zoom_in_24_regular, size: 20),
                  tooltip: 'הגדל את גודל הטקסט',
                  onPressed: () => _pdfController?.zoomUp(),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                IconButton(
                  icon: const Icon(FluentIcons.zoom_out_24_regular, size: 20),
                  tooltip: 'הקטן את גודל הטקסט',
                  onPressed: () => _pdfController?.zoomDown(),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                Container(
                  width: 1,
                  height: 24,
                  color: Theme.of(context).dividerColor,
                ),
                IconButton(
                  icon: const Icon(FluentIcons.open_24_regular, size: 20),
                  tooltip: 'פתח בעיון (או לחץ פעמיים על הספר)',
                  onPressed: () {
                    int currentPage = 1;
                    if (_pdfController != null && _pdfController!.isReady) {
                      currentPage = _pdfController!.pageNumber ?? 1;
                    }
                    widget.onOpenInReader?.call(currentPage);
                  },
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                if (widget.onClose != null)
                  Container(
                    width: 1,
                    height: 24,
                    color: Theme.of(context).dividerColor,
                  ),
                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(FluentIcons.dismiss_24_regular, size: 20),
                    tooltip: 'הסתר תצוגה מקדימה',
                    onPressed: widget.onClose,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
              ],
            ),
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
        .map((width) => Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: _SkeletonLine(width: width, height: 18, color: color),
              ),
            ))
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
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
