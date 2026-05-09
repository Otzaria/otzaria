import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/pdf_book/view/pdf_page_number_display.dart';
import 'package:otzaria/pdf_book/view/pdf_thumbnails_screen.dart';
import 'package:otzaria/pdf_book/view/pdf_scrollbar.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/printing/printing_helpers.dart';
import 'package:otzaria/printing/pdf_text_rasterizer.dart';
import 'package:otzaria/printing/word_export_service.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';

enum _PrintRangeMode { headers, altHeaders, lines }

class PrintingScreen extends StatefulWidget {
  final Future<String> data;
  final Future<Uint8List> Function(PdfPageFormat format)? createPdfOverride;
  final String bookId;
  final TextBook? book;
  final List<Link> links;
  final List<String> activeCommentators;
  final bool removeNikud;
  final bool removeTaamim;
  final int startLine;
  final List<TocEntry> tableOfContents;
  final int? initialPage;
  final bool isBookView;
  final List<PdfOutlineNode> pdfOutline;
  const PrintingScreen({
    super.key,
    required this.data,
    this.createPdfOverride,
    required this.bookId,
    this.book,
    this.links = const [],
    this.activeCommentators = const [],
    this.startLine = 0,
    this.removeNikud = false,
    this.removeTaamim = false,
    this.tableOfContents = const [],
    this.initialPage,
    this.isBookView = false,
    this.pdfOutline = const [],
  });
  @override
  State<PrintingScreen> createState() => _PrintingScreenState();
}

class _PrintingScreenState extends State<PrintingScreen> {
  double fontSize = 15.0;
  String fontName =
      AppFonts.fontPaths.keys.first; // ברירת מחדל - הגופן הראשון ברשימה
  late int startLine;
  late int endLine;
  late Future<(Uint8List, String)> _previewPdf;
  late Future<String> _dataFuture;
  pw.PageOrientation orientation = pw.PageOrientation.portrait;
  PdfPageFormat format = PdfPageFormat.a4;
  double pageMargin = 20.0;

  final PdfViewerController _pdfViewerController = PdfViewerController();
  final ValueNotifier<PdfDocumentRef?> _documentRef =
      ValueNotifier<PdfDocumentRef?>(null);

  bool _showThumbnails = false;
  int _pagesPerSheet = 1;

  // טווח עמודים ב-PDF
  int _totalPdfPages = 0;
  int _pdfStartPage = 1;
  int _pdfEndPage = 0; // 0 = כל העמודים
  int _renderGeneration = 0; // מונה שביטול renders ישנים
  // נעילה סדרתית של פעולות pdfrx: שני openData במקביל תוקעים את הספרייה.
  Future<void> _rasterLock = Future.value();
  Map<int, String> _pageLabels = {};

  String _labelForPage(int pageNumber) =>
      labelForPdfPage(_pageLabels, pageNumber);

  bool _includeCommentaries = false;
  bool _includePersonalNotes = false;

  final Map<String, String> _commentaryContentCache = {};
  List<PersonalNote>? _personalNotesCache;
  bool _isLoadingNotes = false;
  Timer? _previewRefreshTimer;

  // מצב בחירה: שורות, כותרות, או כותרות משנה
  _PrintRangeMode _rangeMode = _PrintRangeMode.headers;
  int? _startHeaderIndex;
  int? _endHeaderIndex;
  List<TocEntry> _flatHeaders = [];
  int? _startAltHeaderIndex;
  int? _endAltHeaderIndex;
  List<TocEntry> _flatAltHeaders = [];

  // הגדרות ניקוד וטעמים - ברירת מחדל לפי תצוגת הספר
  late bool _removeNikud;
  late bool _removeTaamim;
  static const _defaultWordExtension = 'docx';
  static const _pdfExtension = 'pdf';

  @override
  void initState() {
    super.initState();
    _dataFuture = widget.data;
    startLine = widget.startLine;
    endLine = startLine;

    // אתחול הגדרות ניקוד וטעמים לפי תצוגת הספר
    _removeNikud = widget.removeNikud;
    _removeTaamim = widget.removeTaamim;

    // במצב PDF חיצוני (כמו "צורת הדף") אין טווח שורות/כותרות.
    if (widget.createPdfOverride != null) {
      _rangeMode = _PrintRangeMode.lines;
      _flatHeaders = const [];
      _pageLabels = buildPdfPageLabels(widget.pdfOutline);
      if (widget.initialPage != null) {
        _pdfStartPage = widget.initialPage!;
        _pdfEndPage =
            widget.isBookView ? widget.initialPage! + 1 : widget.initialPage!;
      }
      _previewPdf = _createPreviewPdf(format);
      return;
    }

    // יצירת רשימה שטוחה של כל הכותרות
    _flatHeaders = _flattenHeaders(widget.tableOfContents);

    // אם יש כותרות, אתחל את מצב הכותרות
    if (_flatHeaders.isNotEmpty) {
      _startHeaderIndex = 0;
      _endHeaderIndex = min(2, _flatHeaders.length - 1);
    } else {
      // אם אין כותרות, עבור למצב שורות
      _rangeMode = _PrintRangeMode.lines;
    }

    _previewPdf = _createInitialPreviewPdf();
    _loadAltHeaders();
  }

  @override
  void didUpdateWidget(covariant PrintingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _dataFuture = widget.data;
      _previewPdf = _createInitialPreviewPdf();
    }
  }

  Future<(Uint8List, String)> _createInitialPreviewPdf() async {
    await _applyCurrentRange();
    if (mounted) {
      setState(() {});
    }
    return _createPreviewPdf(format);
  }

  Future<int> _totalLineCount() async => (await _dataFuture).split('\n').length;

  Future<void> _applyCurrentRange() async {
    if (_rangeMode == _PrintRangeMode.headers) {
      await _applyHeaderRange();
      return;
    }
    if (_rangeMode == _PrintRangeMode.altHeaders) {
      await _applyAltHeaderRange();
      return;
    }
    final totalLines = await _totalLineCount();
    if (endLine <= startLine) {
      endLine = min(startLine + 3, totalLines);
    } else {
      startLine = startLine.clamp(0, totalLines);
      endLine = endLine.clamp(startLine, totalLines);
    }
  }

  Future<void> _applyAltHeaderRange() async {
    if (_startAltHeaderIndex == null || _endAltHeaderIndex == null) return;
    if (_flatAltHeaders.isEmpty) return;

    final startEntry = _flatAltHeaders[_startAltHeaderIndex!];
    final totalLines = await _totalLineCount();
    if (!mounted) return;

    startLine = startEntry.index;
    if (_endAltHeaderIndex! < _flatAltHeaders.length - 1) {
      endLine = _flatAltHeaders[_endAltHeaderIndex! + 1].index;
    } else {
      endLine = totalLines;
    }
  }

  Future<void> _applyHeaderRange() async {
    if (_startHeaderIndex == null || _endHeaderIndex == null) return;
    if (_flatHeaders.isEmpty) return;

    final startHeader = _flatHeaders[_startHeaderIndex!];
    final totalLines = await _totalLineCount();
    if (!mounted) return;

    startLine = startHeader.index;
    if (_endHeaderIndex! < _flatHeaders.length - 1) {
      endLine = _flatHeaders[_endHeaderIndex! + 1].index;
    } else {
      endLine = totalLines;
    }
  }

  Future<void> _loadAltHeaders() async {
    if (widget.createPdfOverride != null) return;
    try {
      final structures = await DatabaseLibraryProvider.instance
          .getAlternativeStructuresForBook(widget.bookId);
      if (structures.isEmpty || !mounted) return;

      // שימוש ב-structure הראשון בלבד - ריבוי structures מערבב ערכים
      final rows = await DatabaseLibraryProvider.instance
          .getAltTocLineIndices(structures.first.id);
      if (!mounted || rows.isEmpty) return;

      final altEntries =
          rows.map((r) => TocEntry(text: r.text, index: r.lineIndex)).toList();

      setState(() {
        _flatAltHeaders = altEntries;
        _startAltHeaderIndex = 0;
        _endAltHeaderIndex = min(2, altEntries.length - 1);
        // אם אין ניווט רגיל, עבור אוטומטית למצב כותרות משנה
        if (_flatHeaders.isEmpty) {
          _rangeMode = _PrintRangeMode.altHeaders;
          _updateRangeByAltHeaders();
        }
      });
    } catch (e) {
      debugPrint('Error loading alt headers for printing: $e');
    }
  }

  void _updateRangeByAltHeaders() async {
    if (_startAltHeaderIndex != null && _endAltHeaderIndex != null) {
      await _applyAltHeaderRange();
      if (!mounted) return;
      _refreshPreviewPdf(immediate: true);
      setState(() {});
    }
  }

  @override
  void dispose() {
    _previewRefreshTimer?.cancel();
    _documentRef.dispose();
    super.dispose();
  }

  // פונקציה ליצירת רשימה שטוחה של כל הכותרות
  List<TocEntry> _flattenHeaders(List<TocEntry> headers) {
    // דילוג על רמה 1 רק כאשר יש entry יחיד ברמה 1 עם ילדים
    // (מצב זה מסמל שם ספר-עטיפה). כאשר יש מספר entries ברמה 1,
    // הם כותרות תוכן אמיתיות ויש לכלול אותן.
    final level1Roots = headers.where((h) => h.level == 1).toList();
    final skipLevel1 =
        level1Roots.length == 1 && level1Roots.first.children.isNotEmpty;

    List<TocEntry> result = [];
    for (var header in headers) {
      if (!skipLevel1 || header.level > 1) {
        result.add(header);
      }
      if (header.children.isNotEmpty) {
        result.addAll(_flattenHeaders(header.children));
      }
    }
    return result;
  }

  // עדכון טווח השורות לפי כותרות נבחרות
  void _updateRangeByHeaders() async {
    if (_startHeaderIndex != null && _endHeaderIndex != null) {
      await _applyHeaderRange();
      if (!mounted) return;
      _refreshPreviewPdf(immediate: true);
      setState(() {});
    }
  }

  void _toggleThumbnails(bool value) {
    final currentPage =
        _pdfViewerController.isReady ? _pdfViewerController.pageNumber : null;
    setState(() {
      _showThumbnails = value;
    });
    if (currentPage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pdfViewerController.isReady) {
          _pdfViewerController.goToPage(
            pageNumber: currentPage,
            anchor: PdfPageAnchor.top,
          );
        }
      });
    }
  }

  void _refreshPreviewPdf({bool immediate = false}) {
    _renderGeneration++;
    _previewRefreshTimer?.cancel();
    if (immediate) {
      _previewPdf = _createPreviewPdf(format);
      return;
    }
    _previewRefreshTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _previewPdf = _createPreviewPdf(format);
      });
    });
  }

  Future<(Uint8List, String)> _createPreviewPdf(PdfPageFormat format) async {
    final name = 'printing_${DateTime.now().millisecondsSinceEpoch}';
    final bytes = await _createOutputPdf(format);
    return (bytes, name);
  }

  Future<Uint8List> _createOutputPdf(PdfPageFormat format) async {
    final base = await _createBasePdf(format);

    final isPdfMode = widget.createPdfOverride != null;
    final startPage = isPdfMode ? _pdfStartPage : 1;
    final endPage = computePdfPrintEndPage(
      isPdfMode: isPdfMode,
      pdfEndPage: _pdfEndPage,
      totalPdfPages: _totalPdfPages,
    );
    final hasPageRange =
        hasPdfPageRange(startPage: startPage, endPage: endPage);

    if (_pagesPerSheet <= 1 && !hasPageRange) return base;

    try {
      return await _createNUpPdfFromRaster(
        base,
        sheetFormat: _effectivePageFormat(format),
        pagesPerSheet: _pagesPerSheet,
        startPage: startPage,
        endPage: endPage,
      );
    } catch (e, st) {
      debugPrint('[PRINT] raster failed: $e\n$st');
      if (mounted) {
        UiSnack.showError(hasPageRange
            ? 'עיבוד טווח העמודים שנבחר נכשל'
            : 'עיבוד עמודים מרובים בגיליון נכשל');
      }
      rethrow;
    }
  }

  PdfPageFormat _effectivePageFormat(PdfPageFormat format) {
    return orientation == pw.PageOrientation.landscape
        ? format.landscape
        : format;
  }

  Future<Uint8List> _createBasePdf(PdfPageFormat format) async {
    final override = widget.createPdfOverride;
    if (override != null) {
      final effectiveFormat = orientation == pw.PageOrientation.landscape
          ? format.landscape
          : format;
      return override(effectiveFormat);
    }
    return createPdf(format);
  }

  Future<Uint8List> _createNUpPdfFromRaster(
    Uint8List sourcePdf, {
    required PdfPageFormat sheetFormat,
    required int pagesPerSheet,
    int startPage = 1,
    int? endPage,
  }) async {
    // הסדרה של עבודת pdfrx: רק render אחד בכל רגע נתון.
    // בלי זה, פתיחת שני PdfDocument במקביל תוקעת את הספרייה.
    final completer = Completer<Uint8List>();
    final previousLock = _rasterLock;
    _rasterLock = completer.future.then((_) => null).catchError((_) => null);
    await previousLock;

    try {
      final result = await _rasterizeNUp(
        sourcePdf,
        sheetFormat: sheetFormat,
        pagesPerSheet: pagesPerSheet,
        startPage: startPage,
        endPage: endPage,
      );
      completer.complete(result);
      return result;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    }
  }

  Future<Uint8List> _rasterizeNUp(
    Uint8List sourcePdf, {
    required PdfPageFormat sheetFormat,
    required int pagesPerSheet,
    int startPage = 1,
    int? endPage,
  }) async {
    final (rows, cols) = switch (pagesPerSheet) {
      2 => (1, 2),
      4 => (2, 2),
      _ => (1, 1),
    };
    final hasRange = startPage > 1 || endPage != null;
    if (rows == 1 && cols == 1 && !hasRange) return sourcePdf;

    final dpi = switch (pagesPerSheet) {
      4 => 72.0,
      2 => 96.0,
      _ => 120.0,
    };
    final rasterPages = <Uint8List>[];
    final generation = _renderGeneration;

    // Wait for Flutter to rebuild and unmount the previous PdfViewer before using pdfrx
    await Future.delayed(const Duration(milliseconds: 150));

    // If a newer render was requested while waiting, abort to avoid concurrent pdfrx documents
    if (generation != _renderGeneration || !mounted) return sourcePdf;

    final doc = await PdfDocument.openData(sourcePdf,
        sourceName: 'nup_${DateTime.now().millisecondsSinceEpoch}');

    // Update total page count on first open and clamp page range
    if (_totalPdfPages == 0 && widget.createPdfOverride != null && mounted) {
      final count = doc.pages.length;
      setState(() {
        _totalPdfPages = count;
        _pdfStartPage = _pdfStartPage.clamp(1, count);
        _pdfEndPage = _pdfEndPage == 0 ? count : _pdfEndPage.clamp(1, count);
      });
    }

    try {
      final scale = dpi / 72.0;
      final firstIdx = max(0, min(startPage - 1, doc.pages.length - 1));
      final lastIdx = max(firstIdx,
          min((endPage ?? doc.pages.length) - 1, doc.pages.length - 1));
      for (var i = firstIdx; i <= lastIdx; i++) {
        // אם המשתמש שינה פרמטר באמצע ה-render, זרוק את המסמך מוקדם.
        // בלי זה שני PdfDocument פעילים בו-זמנית - ופדרקס תקוע.
        if (generation != _renderGeneration || !mounted) {
          return sourcePdf;
        }
        final page = doc.pages[i];
        final pdfImage = await page.render(
          fullWidth: page.width * scale,
          fullHeight: page.height * scale,
          backgroundColor: 0xFFFFFFFF,
        );
        if (pdfImage == null) continue;
        final uiImage = await pdfImage.createImage();
        pdfImage.dispose();
        final byteData =
            await uiImage.toByteData(format: ui.ImageByteFormat.png);
        uiImage.dispose();
        if (byteData == null) continue;
        rasterPages.add(byteData.buffer.asUint8List());
      }
    } finally {
      doc.dispose();
    }

    if (rasterPages.isEmpty) return sourcePdf;

    final output = pw.Document(compress: false);
    final cells = rows * cols;
    final cellHeight = sheetFormat.height / rows;

    for (var i = 0; i < rasterPages.length; i += cells) {
      final chunk = rasterPages.sublist(
        i,
        min(i + cells, rasterPages.length),
      );

      output.addPage(
        pw.Page(
          pageFormat: sheetFormat,
          margin: pw.EdgeInsets.zero,
          build: (context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                children: List.generate(rows, (row) {
                  return pw.SizedBox(
                    height: cellHeight,
                    child: pw.Row(
                      children: List.generate(cols, (col) {
                        final indexInChunk = row * cols + col;
                        if (indexInChunk >= chunk.length) {
                          return pw.Expanded(child: pw.SizedBox());
                        }
                        final image = pw.MemoryImage(chunk[indexInChunk]);
                        return pw.Expanded(
                          child: pw.Align(
                            alignment: pw.Alignment.centerRight,
                            child: pw.Image(
                              image,
                              fit: pw.BoxFit.contain,
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),
            );
          },
        ),
      );
    }

    return output.save();
  }

  Future<Uint8List> createPdf(PdfPageFormat format) async {
    // אם הגופן לא מוטמע, השתמש בגופן ברירת מחדל
    final fontPath = fonts[fontName] ?? fonts.values.first;
    final font = pw.Font.ttf(await rootBundle.load(fontPath));
    final fullBackFont = pw.Font.ttf(await rootBundle
        .load('fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf'));
    String dataString = await _dataFuture;
    if (orientation == pw.PageOrientation.landscape) {
      format = format.landscape;
    }

    // הסרת ניקוד וטעמים לפי הגדרות המשתמש
    // טעמים: U+0591-U+05AF
    // ניקוד: U+05B0-U+05C7
    if (_removeNikud && _removeTaamim) {
      // הסרת ניקוד וטעמים (U+0591-U+05C7)
      dataString = removeVolwels(dataString);
    } else if (_removeNikud && !_removeTaamim) {
      // הסרת ניקוד בלבד, שמירת טעמים (U+05B0-U+05C7)
      dataString = dataString
          .replaceAll('־', ' ')
          .replaceAll('׀', ' ')
          .replaceAll('|', ' ')
          .replaceAll(RegExp(r'[\u05B0-\u05C7]'), '');
    } else if (!_removeNikud && _removeTaamim) {
      // הסרת טעמים בלבד, שמירת ניקוד
      dataString = removeTeamim(dataString);
    }
    // אם שניהם false - לא מסירים כלום

    final shouldReplaceHolyNames =
        Settings.getValue<bool>('key-replace-holy-names') ?? true;
    if (shouldReplaceHolyNames) {
      dataString = replaceHolyNames(dataString);
    }

    List<String> data = stripHtmlIfNeeded(dataString).split('\n').toList();
    final pageMargin = this.pageMargin;
    final fontSize = this.fontSize;

    String bookName = data[0];
    if (shouldReplaceHolyNames) {
      bookName = replaceHolyNames(bookName);
    }
    final allLines = data;
    final selectedStart = startLine.clamp(0, allLines.length);
    final selectedEnd = endLine.clamp(selectedStart, allLines.length);

    final personalNotes = _includePersonalNotes
        ? await _getPersonalNotesForBook(widget.bookId)
        : const <PersonalNote>[];

    final blocks = await _buildPrintBlocks(
      allLines: allLines,
      selectedStart: selectedStart,
      selectedEnd: selectedEnd,
      shouldReplaceHolyNames: shouldReplaceHolyNames,
      personalNotes: personalNotes,
    );
    final contentWidth = max(1.0, format.width - pageMargin * 2);
    final rasterizedNikudBlocks = await _rasterizeNikudBlocks(
      blocks: blocks,
      fontName: fontName,
      fontSize: fontSize,
      contentWidth: contentWidth,
    );

    final result = await Isolate.run(() async {
      final pdfData =
          pw.Document(compress: false, pageMode: PdfPageMode.outlines);
      pdfData.addPage(pw.MultiPage(
          theme:
              pw.ThemeData.withFont(base: font, fontFallback: [fullBackFont]),
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          textDirection: pw.TextDirection.rtl,
          maxPages: 1000000,
          margin: pw.EdgeInsets.all(pageMargin),
          pageFormat: format,
          header: (pw.Context context) {
            return pw.Container(
                alignment: pw.Alignment.topCenter,
                margin: const pw.EdgeInsets.only(top: 1.0 * PdfPageFormat.cm),
                child: pw.Text(bookName,
                    style: pw.Theme.of(context)
                        .defaultTextStyle
                        .copyWith(color: PdfColors.grey)));
          },
          footer: (pw.Context context) {
            return pw.Container(
                alignment: pw.Alignment.bottomCenter,
                margin: const pw.EdgeInsets.only(top: 1.0 * PdfPageFormat.cm),
                child: pw.Text(
                    'עמוד ${context.pageNumber} מתוך ${context.pagesCount} - הודפס מתוכנת אוצריא',
                    style: pw.Theme.of(context)
                        .defaultTextStyle
                        .copyWith(color: PdfColors.grey)));
          },
          build: (pw.Context context) {
            return blocks.asMap().entries.expand((entry) {
              final blockIndex = entry.key;
              final b = entry.value;
              final kind = b['kind'];
              final title = b['title'];
              final text = (b['text'] ?? '').replaceAll('\n', '');

              if (kind == 'commentaryTitle') {
                return [
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(
                      top: 6,
                      right: 8,
                      left: 8,
                    ),
                    child: pw.Text(
                      title ?? 'מפרשים',
                      style: pw.TextStyle(
                        fontSize: max(10.0, fontSize * 0.9),
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey800,
                      ),
                    ),
                  )
                ];
              }

              if (kind == 'commentaryGroupTitle') {
                return [
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(
                      top: 4,
                      right: 12,
                      left: 8,
                    ),
                    child: pw.Text(
                      title ?? '',
                      style: pw.TextStyle(
                        fontSize: max(10.0, fontSize * 0.9),
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey900,
                      ),
                    ),
                  )
                ];
              }

              if (kind == 'noteTitle') {
                return [
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(
                      top: 6,
                      right: 8,
                      left: 8,
                    ),
                    child: pw.Text(
                      title ?? 'הערות אישיות',
                      style: pw.TextStyle(
                        fontSize: max(10.0, fontSize * 0.9),
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey800,
                      ),
                    ),
                  )
                ];
              }

              final effectiveFontSize = switch (kind) {
                'commentary' || 'note' => max(10.0, fontSize * 0.9),
                _ => fontSize,
              };

              final padding = switch (kind) {
                'commentary' || 'note' => const pw.EdgeInsets.only(
                    top: 2,
                    bottom: 2,
                    right: 18,
                    left: 8,
                  ),
                'commentaryGroupTitle' => const pw.EdgeInsets.only(
                    top: 4,
                    bottom: 2,
                    right: 12,
                    left: 8,
                  ),
                _ => const pw.EdgeInsets.all(8.0),
              };
              final rasterizedLines = rasterizedNikudBlocks[blockIndex];
              if (rasterizedLines != null && rasterizedLines.isNotEmpty) {
                final lineWidth = max(
                  1.0,
                  contentWidth - padding.left - padding.right,
                );
                return rasterizedLines.asMap().entries.map((lineEntry) {
                  final isFirst = lineEntry.key == 0;
                  final isLast = lineEntry.key == rasterizedLines.length - 1;
                  return pw.Padding(
                    padding: pw.EdgeInsets.only(
                      top: isFirst ? padding.top : 0,
                      bottom: isLast ? padding.bottom : 0,
                      right: padding.right,
                      left: padding.left,
                    ),
                    child: pw.Image(
                      pw.MemoryImage(lineEntry.value),
                      width: lineWidth,
                    ),
                  );
                });
              }

              return [
                pw.Padding(
                  padding: padding,
                  child: pw.Paragraph(
                    text: text,
                    textAlign: pw.TextAlign.justify,
                    style: pw.TextStyle(
                      fontSize: effectiveFontSize,
                      font: font,
                    ),
                  ),
                )
              ];
            }).toList();
          }));

      return await pdfData.save();
    });

    return result;
  }

  Future<Map<int, List<Uint8List>>> _rasterizeNikudBlocks({
    required List<Map<String, String>> blocks,
    required String fontName,
    required double fontSize,
    required double contentWidth,
  }) async {
    if (_removeNikud) return const {};

    final images = <int, List<Uint8List>>{};
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final kind = block['kind'];
      if (kind == 'commentaryTitle' ||
          kind == 'commentaryGroupTitle' ||
          kind == 'noteTitle') {
        continue;
      }

      final text = (block['text'] ?? '').replaceAll('\n', '');
      if (!PdfTextRasterizer.containsHebrewMarks(text)) continue;

      final effectiveFontSize = switch (kind) {
        'commentary' || 'note' => max(10.0, fontSize * 0.9),
        _ => fontSize,
      };

      final paddingHorizontal = switch (kind) {
        'commentary' || 'note' => 26.0,
        'commentaryGroupTitle' => 20.0,
        _ => 16.0,
      };

      final lines = await PdfTextRasterizer.renderRtlTextLines(
        text: text,
        maxWidth: max(1.0, contentWidth - paddingHorizontal),
        style: TextStyle(
          color: Colors.black,
          fontFamily: fontName,
          fontSize: effectiveFontSize,
          height: 1.35,
        ),
      );
      if (lines.isNotEmpty) {
        images[i] = lines;
      }
    }
    return images;
  }

  Future<List<Link>> _loadLinksForPrintRange(
      int selectedStart, int selectedEnd) async {
    final book = widget.book;
    if (book == null) return widget.links;

    final categoryId = book.categoryId;
    final fileType = book.fileType ?? 'txt';

    final provider = LibraryProviderManager.instance.getProviderForBook(
      book.title,
      categoryId: categoryId,
      fileType: fileType,
    );

    if (provider is DatabaseLibraryProvider && categoryId != null) {
      try {
        return await provider.getLinksForBookRange(
          book.title,
          categoryId,
          fileType,
          startLineIndex: selectedStart,
          endLineIndex: selectedEnd,
          targetBookTitles: widget.activeCommentators,
        );
      } catch (_) {}
    }

    // ספרים מבוססי-קבצים: טעינת כל הקישורים וסינון לפי טווח
    try {
      final allLinks = await book.links;
      if (allLinks.isNotEmpty) {
        final rangeStart = selectedStart + 1;
        final rangeEnd = selectedEnd + 1;
        return allLinks
            .where((l) => l.index1 >= rangeStart && l.index1 <= rangeEnd)
            .toList();
      }
    } catch (_) {}

    return widget.links;
  }

  Future<List<Map<String, String>>> _buildPrintBlocks({
    required List<String> allLines,
    required int selectedStart,
    required int selectedEnd,
    required bool shouldReplaceHolyNames,
    required List<PersonalNote> personalNotes,
  }) async {
    final blocks = <Map<String, String>>[];

    Map<int, List<PersonalNote>> notesByLine = const {};
    if (_includePersonalNotes && personalNotes.isNotEmpty) {
      final map = <int, List<PersonalNote>>{};
      for (final note in personalNotes) {
        final ln = note.lineNumber;
        if (ln == null) continue;
        (map[ln] ??= []).add(note);
      }
      notesByLine = map;
    }

    final rangeLinks = _includeCommentaries
        ? await _loadLinksForPrintRange(selectedStart, selectedEnd)
        : <Link>[];

    for (var i = selectedStart; i < selectedEnd; i++) {
      var lineText = allLines[i];
      if (shouldReplaceHolyNames) {
        lineText = replaceHolyNames(lineText);
      }
      blocks.add({'kind': 'text', 'text': lineText});

      final lineNumber1Based = i + 1;

      if (_includeCommentaries) {
        final linksForLine = await getLinksforIndexs(
          indexes: [i],
          links: rangeLinks,
          commentatorsToShow: widget.activeCommentators,
        );

        if (linksForLine.isNotEmpty) {
          blocks.add({'kind': 'commentaryTitle', 'title': 'מפרשים'});

          // קיבוץ לפי מפרש (כמו בתצוגת PDF): כותרת לכל מפרש, ומתחתיה כל הקטעים שלו
          String? currentGroupTitle;
          for (final link in linksForLine) {
            final commentatorTitle = getTitleFromPath(link.path2);
            if (currentGroupTitle != commentatorTitle) {
              currentGroupTitle = commentatorTitle;
              blocks.add({
                'kind': 'commentaryGroupTitle',
                'title': commentatorTitle,
              });
            }

            final content = await _getCommentaryContent(
              link,
              shouldReplaceHolyNames: shouldReplaceHolyNames,
            );
            if (content.trim().isEmpty) continue;
            blocks.add({
              'kind': 'commentary',
              'text': content,
            });
          }
        }
      }

      if (_includePersonalNotes) {
        final notes = notesByLine[lineNumber1Based] ?? const <PersonalNote>[];
        if (notes.isNotEmpty) {
          blocks.add({'kind': 'noteTitle', 'title': 'הערות אישיות'});
          for (final note in notes) {
            var noteText = note.contentPlain.trim().isNotEmpty
                ? note.contentPlain
                : _normalizeLegacyNoteText(note.content);
            if (shouldReplaceHolyNames) {
              noteText = replaceHolyNames(noteText);
            }
            blocks.add({'kind': 'note', 'text': noteText});
          }
        }
      }
    }

    return blocks;
  }

  Future<PreparedPrintDocument> _prepareWordDocument() async {
    String dataString = await _dataFuture;

    if (_removeNikud && _removeTaamim) {
      dataString = removeVolwels(dataString);
    } else if (_removeNikud && !_removeTaamim) {
      dataString = dataString
          .replaceAll('ײ¾', ' ')
          .replaceAll('׳€', ' ')
          .replaceAll('|', ' ')
          .replaceAll(RegExp(r'[\u05B0-\u05C7]'), '');
    } else if (!_removeNikud && _removeTaamim) {
      dataString = removeTeamim(dataString);
    }

    final shouldReplaceHolyNames =
        Settings.getValue<bool>('key-replace-holy-names') ?? true;
    if (shouldReplaceHolyNames) {
      dataString = replaceHolyNames(dataString);
    }

    final allLines = stripHtmlIfNeeded(dataString).split('\n').toList();
    var bookName = allLines.isNotEmpty ? allLines.first : widget.bookId;
    if (bookName.trim().isEmpty) {
      bookName = widget.bookId;
    }

    final selectedStart = startLine.clamp(0, allLines.length);
    final selectedEnd = endLine.clamp(selectedStart, allLines.length);
    final personalNotes = _includePersonalNotes
        ? await _getPersonalNotesForBook(widget.bookId)
        : const <PersonalNote>[];

    final legacyBlocks = _foldPersonalNoteBlocks(
      await _buildPrintBlocks(
        allLines: allLines,
        selectedStart: selectedStart,
        selectedEnd: selectedEnd,
        shouldReplaceHolyNames: shouldReplaceHolyNames,
        personalNotes: personalNotes,
      ),
    );

    return PreparedPrintDocument(
      bookName: bookName,
      blocks: legacyBlocks.map(_mapPrintBlock).toList(growable: false),
    );
  }

  PrintBlock _mapPrintBlock(Map<String, String> block) {
    final kindName = block['kind'] ?? 'text';
    final kind = switch (kindName) {
      'commentaryTitle' => PrintBlockKind.commentaryTitle,
      'commentaryGroupTitle' => PrintBlockKind.commentaryGroupTitle,
      'commentary' => PrintBlockKind.commentary,
      'heading' => PrintBlockKind.heading,
      _ => PrintBlockKind.text,
    };

    return PrintBlock(
      kind: kind,
      text: block['text'] ?? block['title'] ?? '',
      headingLevel: int.tryParse(block['headingLevel'] ?? ''),
      footnotes: (block['footnotes'] ?? '')
          .split('\u241E')
          .where((item) => item.isNotEmpty)
          .map((item) => PrintFootnote(text: item))
          .toList(growable: false),
    );
  }

  List<Map<String, String>> _foldPersonalNoteBlocks(
    List<Map<String, String>> blocks,
  ) {
    final folded = <Map<String, String>>[];
    Map<String, String>? currentTarget;

    for (final block in blocks) {
      final kind = block['kind'];
      if (kind == 'text' || kind == 'heading') {
        final copy = Map<String, String>.from(block);
        folded.add(copy);
        currentTarget = copy;
        continue;
      }

      if (kind == 'noteTitle') {
        continue;
      }

      if (kind == 'note' && currentTarget != null) {
        final normalized = _normalizeLegacyNoteText(block['text'] ?? '');
        if (normalized.isNotEmpty) {
          final existing = currentTarget['footnotes'];
          final combined = <String>[
            if (existing != null && existing.isNotEmpty)
              ...existing.split('\u241E').where((item) => item.isNotEmpty),
            normalized,
          ];
          currentTarget['footnotes'] = combined.join('\u241E');
        }
        continue;
      }

      folded.add(Map<String, String>.from(block));
    }

    return folded;
  }

  String _normalizeLegacyNoteText(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return '';

    if (!trimmed.startsWith('[')) {
      return trimmed;
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        final buffer = StringBuffer();
        for (final item in decoded) {
          if (item is Map && item['insert'] is String) {
            buffer.write(item['insert'] as String);
          }
        }
        final normalized = buffer.toString().trim();
        if (normalized.isNotEmpty) {
          return normalized;
        }
      }
    } catch (_) {
      // Leave raw text when old note payload is not valid Delta JSON.
    }

    return trimmed;
  }

  Future<void> _exportDocument() async {
    try {
      final supportsWord = widget.createPdfOverride == null;
      final selectedFormat =
          await _pickExportFormat(supportsWord: supportsWord);
      if (selectedFormat == null) return;

      final selectedExtension = selectedFormat.extension;
      final path = await FilePicker.saveFile(
        dialogTitle: 'ייצוא קובץ',
        fileName: '${_sanitizeFileName(widget.bookId)}.$selectedExtension',
        type: FileType.custom,
        allowedExtensions: [selectedExtension],
      );
      if (path == null) return;

      final resolvedPath = _normalizeExportPath(
        path,
        defaultExtension: selectedExtension,
      );
      final file = File(resolvedPath);

      if (selectedFormat == _ExportFormat.word) {
        final prepared = await _prepareWordDocument();
        final bytes = WordExportService.createWordDocument(
          title: prepared.bookName,
          blocks: prepared.blocks,
          format: format,
          isLandscape: orientation == pw.PageOrientation.landscape,
          pageMargin: pageMargin,
        );
        await file.writeAsBytes(bytes);
        UiSnack.showSuccess('קובץ Word נשמר בהצלחה');
        return;
      }

      await file.writeAsBytes(await _createOutputPdf(format));
      UiSnack.showSuccess('קובץ PDF נשמר בהצלחה');
    } on FileSystemException catch (e) {
      if (_isLockedFileException(e)) {
        UiSnack.showError(
            'לא ניתן לשמור את הקובץ כי הוא פתוח בתוכנה אחרת. יש לסגור אותו ולנסות שוב.');
        return;
      }
      UiSnack.showError('ייצוא הקובץ נכשל: ${e.message}');
    } catch (e) {
      UiSnack.showError('ייצוא הקובץ נכשל: $e');
    }
  }

  Future<_ExportFormat?> _pickExportFormat({
    required bool supportsWord,
  }) async {
    if (!supportsWord) {
      return _ExportFormat.pdf;
    }
    final result = await showTwoActionsDialog(
      context: context,
      title: 'בחירת סוג קובץ',
      content: 'בחר פורמט לייצוא',
      cancelText: 'PDF',
      confirmText: 'Word',
      barrierDismissible: true,
    );

    if (result == null) return null;
    return result ? _ExportFormat.word : _ExportFormat.pdf;
  }

  String _sanitizeFileName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return sanitized.isEmpty ? 'output' : sanitized;
  }

  String _normalizeExportPath(
    String path, {
    required String defaultExtension,
  }) {
    final extension = _extensionOf(path);
    if (extension == _defaultWordExtension || extension == _pdfExtension) {
      return path;
    }
    return '$path.$defaultExtension';
  }

  String _extensionOf(String path) {
    final parts = path.split('.');
    if (parts.length < 2) return '';
    return parts.last.toLowerCase();
  }

  bool _isLockedFileException(FileSystemException error) {
    final message =
        '${error.message} ${error.osError?.message ?? ''}'.toLowerCase();
    return message.contains('used by another process') ||
        message.contains('being used by another process') ||
        message.contains('access is denied') ||
        message.contains('permission denied');
  }

  Future<String> _getCommentaryContent(
    Link link, {
    required bool shouldReplaceHolyNames,
  }) async {
    final key = '${link.path2}::${link.index2}::${link.heRef}';
    final cached = _commentaryContentCache[key];
    if (cached != null) return cached;

    var text = await link.content;
    text = stripHtmlIfNeeded(text);
    if (_removeNikud && _removeTaamim) {
      text = removeVolwels(text);
    } else if (_removeNikud && !_removeTaamim) {
      text = text
          .replaceAll('־', ' ')
          .replaceAll('׀', ' ')
          .replaceAll('|', ' ')
          .replaceAll(RegExp(r'[\u05B0-\u05C7]'), '');
    } else if (!_removeNikud && _removeTaamim) {
      text = removeTeamim(text);
    }
    if (shouldReplaceHolyNames) {
      text = replaceHolyNames(text);
    }

    _commentaryContentCache[key] = text;
    return text;
  }

  Future<List<PersonalNote>> _getPersonalNotesForBook(String bookId) async {
    if (_personalNotesCache != null) return _personalNotesCache!;
    if (_isLoadingNotes) return const <PersonalNote>[];
    _isLoadingNotes = true;

    try {
      final repo = PersonalNotesRepository();
      final all =
          await repo.loadNotes(bookId, categoryId: widget.book?.categoryId);
      final located = all.where((n) => n.hasLocation).toList();
      _personalNotesCache = located;
      return located;
    } catch (_) {
      _personalNotesCache = const <PersonalNote>[];
      return const <PersonalNote>[];
    } finally {
      _isLoadingNotes = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCustomPdfMode = widget.createPdfOverride != null;

    return Dialog(
      insetPadding: const EdgeInsets.fromLTRB(12, 40, 12, 12),
      clipBehavior: Clip.antiAlias,
      child: Scaffold(
        backgroundColor: AppSurfaces.solidPanelBackground(context),
        body: Column(
          children: [
            _PrintingAppBar(
              title: 'הדפסה — ${widget.book?.title ?? widget.bookId}',
              onClose: () => Navigator.of(context).pop(),
              onExport: _exportDocument,
              onPrint: () async {
                final printed = await Printing.layoutPdf(
                  usePrinterSettings: true,
                  onLayout: _createOutputPdf,
                  format: format,
                );
                if (printed && context.mounted) {
                  Navigator.of(context).pop(true);
                }
              },
            ),
            Expanded(
              child: FutureBuilder(
                future: _dataFuture,
                builder: (context, snapshot) {
                  if (isCustomPdfMode) {
                    return Row(
                      children: [
                        // פאנל הגדרות בצד
                        SizedBox(
                          width: 320,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildSectionCard(
                                  context: context,
                                  title: 'תצוגה מקדימה',
                                  icon: FluentIcons.eye_24_regular,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildDropdownRow(
                                        context: context,
                                        label: 'מעבר לדף',
                                        child: SizedBox(
                                          height: 40,
                                          child: PageNumberDisplay(
                                              controller: _pdfViewerController),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SwitchListTile(
                                        title: const Text(
                                            'תצוגה מוקטנת של כל הדפים'),
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        value: _showThumbnails,
                                        onChanged: _toggleThumbnails,
                                      ),
                                    ],
                                  ),
                                ),
                                if (_totalPdfPages > 0) ...[
                                  const SizedBox(height: 12),
                                  _buildSectionCard(
                                    context: context,
                                    title: 'טווח עמודים',
                                    icon: FluentIcons
                                        .document_page_number_24_regular,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _buildDropdownRow(
                                          context: context,
                                          label: 'מעמוד',
                                          child: AppDropdownField<int>(
                                            value: _pdfStartPage,
                                            enableSearch: true,
                                            entries: List.generate(
                                              _pdfEndPage,
                                              (i) => AppMenuEntry(
                                                value: i + 1,
                                                label: _labelForPage(i + 1),
                                              ),
                                            ),
                                            onSelected: (int? value) {
                                              if (value == null) return;
                                              setState(() {
                                                _pdfStartPage = value;
                                                if (_pdfEndPage <
                                                    _pdfStartPage) {
                                                  _pdfEndPage = _pdfStartPage;
                                                }
                                                _refreshPreviewPdf();
                                              });
                                            },
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        _buildDropdownRow(
                                          context: context,
                                          label: 'עד עמוד',
                                          child: AppDropdownField<int>(
                                            value: _pdfEndPage,
                                            enableSearch: true,
                                            entries: List.generate(
                                              _totalPdfPages -
                                                  _pdfStartPage +
                                                  1,
                                              (i) => AppMenuEntry(
                                                value: _pdfStartPage + i,
                                                label: _labelForPage(
                                                    _pdfStartPage + i),
                                              ),
                                            ),
                                            onSelected: (int? value) {
                                              if (value == null) return;
                                              setState(() {
                                                _pdfEndPage = value;
                                                _refreshPreviewPdf();
                                              });
                                            },
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_pdfEndPage - _pdfStartPage + 1} עמודים מתוך $_totalPdfPages',
                                          style: TextStyle(
                                            color: colorScheme.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                _buildSectionCard(
                                  context: context,
                                  title: 'הגדרות דף',
                                  icon: FluentIcons.options_24_regular,
                                  child: Column(
                                    children: [
                                      _buildDropdownRow(
                                        context: context,
                                        label: 'גודל דף',
                                        child: AppDropdownField<PdfPageFormat>(
                                          value: format,
                                          entries: const {
                                            'A4': PdfPageFormat.a4,
                                            'Letter': PdfPageFormat.letter,
                                          }.entries.map((entry) {
                                            return AppMenuEntry(
                                              value: entry.value,
                                              label: entry.key,
                                            );
                                          }).toList(),
                                          onSelected: (PdfPageFormat? value) {
                                            if (value == null) return;
                                            setState(() {
                                              format = value;
                                              _refreshPreviewPdf();
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _buildDropdownRow(
                                        context: context,
                                        label: 'כיוון',
                                        child: AppDropdownField<
                                            pw.PageOrientation>(
                                          value: orientation,
                                          entries: const [
                                            AppMenuEntry(
                                              value:
                                                  pw.PageOrientation.portrait,
                                              label: 'לאורך',
                                            ),
                                            AppMenuEntry(
                                              value:
                                                  pw.PageOrientation.landscape,
                                              label: 'לרוחב',
                                            ),
                                          ],
                                          onSelected:
                                              (pw.PageOrientation? value) {
                                            if (value == null) return;
                                            orientation = value;
                                            setState(_refreshPreviewPdf);
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _buildDropdownRow(
                                        context: context,
                                        label: 'עמודים בגליון',
                                        child: AppDropdownField<int>(
                                          value: _pagesPerSheet,
                                          entries: const [
                                            AppMenuEntry(
                                              value: 1,
                                              label: '1 (רגיל)',
                                            ),
                                            AppMenuEntry(
                                              value: 2,
                                              label: '2 (יישור לימין)',
                                            ),
                                            AppMenuEntry(
                                              value: 4,
                                              label: '4 (יישור לימין)',
                                            ),
                                          ],
                                          onSelected: (int? value) {
                                            if (value == null) return;
                                            setState(() {
                                              _pagesPerSheet = value;
                                              _refreshPreviewPdf();
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // תצוגה מקדימה של ה-PDF
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(12),
                              topLeft: Radius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: FutureBuilder(
                                    future: _previewPdf,
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                              ConnectionState.done &&
                                          snapshot.hasData) {
                                        final (pdfBytes, pdfSourceName) =
                                            snapshot.data!;
                                        return PdfViewer.data(
                                          pdfBytes,
                                          sourceName: pdfSourceName,
                                          controller: _pdfViewerController,
                                          params: PdfViewerParams(
                                            viewerOverlayBuilder: (context,
                                                    size, handleLinkTap) =>
                                                [
                                              PdfScrollbar(
                                                controller:
                                                    _pdfViewerController,
                                                orientation:
                                                    ScrollbarOrientation.right,
                                                trackThickness: 16.0,
                                                thumbMinSize: 50.0,
                                              ),
                                              PdfHorizontalScrollbar(
                                                controller:
                                                    _pdfViewerController,
                                                trackThickness: 10.0,
                                              ),
                                            ],
                                            onDocumentChanged: (document) {
                                              if (document == null) {
                                                _documentRef.value = null;
                                              }
                                            },
                                            onViewerReady:
                                                (document, controller) {
                                              _documentRef.value =
                                                  controller.documentRef;
                                              if (_totalPdfPages == 0 &&
                                                  mounted) {
                                                setState(() {
                                                  final total =
                                                      document.pages.length;
                                                  _totalPdfPages = total;
                                                  if (_pdfEndPage == 0) {
                                                    _pdfEndPage = total;
                                                  }
                                                });
                                              }
                                            },
                                          ),
                                        );
                                      }
                                      if (snapshot.hasError) {
                                        return Center(
                                          child: Icon(
                                            FluentIcons.error_circle_24_regular,
                                            color: colorScheme.error,
                                            size: 48,
                                          ),
                                        );
                                      }
                                      return Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircularProgressIndicator(
                                              color: colorScheme.primary,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'מכין תצוגה מקדימה...',
                                              style: TextStyle(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                if (_showThumbnails) ...[
                                  VerticalDivider(
                                    width: 1,
                                    color: colorScheme.outlineVariant,
                                  ),
                                  SizedBox(
                                    width: 260,
                                    child:
                                        ValueListenableBuilder<PdfDocumentRef?>(
                                      valueListenable: _documentRef,
                                      builder: (context, documentRef, _) {
                                        return ThumbnailsView(
                                          documentRef: documentRef,
                                          controller: _pdfViewerController,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.done) {
                    final totalLines = snapshot.data!.split('\n').length;
                    return Row(
                      children: [
                        // פאנל הגדרות בצד
                        SizedBox(
                          width: 320,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // ניווט ותצוגה מקדימה
                                _buildSectionCard(
                                  context: context,
                                  title: 'תצוגה מקדימה',
                                  icon: FluentIcons.eye_24_regular,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildDropdownRow(
                                        context: context,
                                        label: 'מעבר לדף',
                                        child: SizedBox(
                                          height: 40,
                                          child: PageNumberDisplay(
                                              controller: _pdfViewerController),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SwitchListTile(
                                        title: const Text(
                                            'תצוגה מוקטנת של כל הדפים'),
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        value: _showThumbnails,
                                        onChanged: _toggleThumbnails,
                                      ),
                                      const SizedBox(height: 8),
                                      if (!isCustomPdfMode) ...[
                                        SwitchListTile(
                                          title: const Text('כלול מפרשים'),
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          value: _includeCommentaries,
                                          onChanged: (value) {
                                            setState(() {
                                              _includeCommentaries = value;
                                              _refreshPreviewPdf();
                                            });
                                          },
                                        ),
                                        SwitchListTile(
                                          title:
                                              const Text('כלול הערות אישיות'),
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          value: _includePersonalNotes,
                                          onChanged: (value) {
                                            setState(() {
                                              _includePersonalNotes = value;
                                              if (!value) {
                                                _personalNotesCache = null;
                                              }
                                              _refreshPreviewPdf();
                                            });
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // כותרת טווח הדפסה
                                _buildSectionCard(
                                  context: context,
                                  title: 'טווח הדפסה',
                                  icon: FluentIcons
                                      .document_page_number_24_regular,
                                  child: Column(
                                    children: [
                                      // תפריט בחירה: שורות/כותרות/כותרות משנה
                                      if (_flatHeaders.isNotEmpty ||
                                          _flatAltHeaders.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 16),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: SegmentedButton<
                                                    _PrintRangeMode>(
                                                  showSelectedIcon: false,
                                                  segments: [
                                                    if (_flatHeaders.isNotEmpty)
                                                      const ButtonSegment<
                                                          _PrintRangeMode>(
                                                        value: _PrintRangeMode
                                                            .headers,
                                                        label: Text('כותרות'),
                                                      ),
                                                    if (_flatAltHeaders
                                                        .isNotEmpty)
                                                      ButtonSegment<
                                                          _PrintRangeMode>(
                                                        value: _PrintRangeMode
                                                            .altHeaders,
                                                        label: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: const [
                                                            Text('כותרות',
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        11)),
                                                            Text('משנה',
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        11)),
                                                          ],
                                                        ),
                                                      ),
                                                    const ButtonSegment<
                                                        _PrintRangeMode>(
                                                      value:
                                                          _PrintRangeMode.lines,
                                                      label: Text('שורות'),
                                                    ),
                                                  ],
                                                  selected: {_rangeMode},
                                                  onSelectionChanged:
                                                      (Set<_PrintRangeMode>
                                                          newSelection) {
                                                    setState(() {
                                                      _rangeMode =
                                                          newSelection.first;
                                                      if (_rangeMode ==
                                                              _PrintRangeMode
                                                                  .headers &&
                                                          _flatHeaders
                                                              .isNotEmpty) {
                                                        _startHeaderIndex = 0;
                                                        _endHeaderIndex = min(
                                                            2,
                                                            _flatHeaders
                                                                    .length -
                                                                1);
                                                        _updateRangeByHeaders();
                                                      } else if (_rangeMode ==
                                                              _PrintRangeMode
                                                                  .altHeaders &&
                                                          _flatAltHeaders
                                                              .isNotEmpty) {
                                                        _startAltHeaderIndex =
                                                            0;
                                                        _endAltHeaderIndex = min(
                                                            2,
                                                            _flatAltHeaders
                                                                    .length -
                                                                1);
                                                        _updateRangeByAltHeaders();
                                                      } else {
                                                        _refreshPreviewPdf();
                                                      }
                                                    });
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                      // בחירת טווח לפי שורות
                                      if (_rangeMode ==
                                          _PrintRangeMode.lines) ...[
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'שורה ${startLine + 1}',
                                              style: TextStyle(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                            ),
                                            Text(
                                              'שורה ${endLine + 1}',
                                              style: TextStyle(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        RangeSlider(
                                          min: 0.0,
                                          max: totalLines.toDouble(),
                                          values: RangeValues(
                                              startLine.toDouble(),
                                              endLine.toDouble()),
                                          onChanged: (value) {
                                            setState(() {
                                              startLine = value.start.toInt();
                                              endLine = value.end.toInt();
                                            });
                                          },
                                          onChangeEnd: (value) {
                                            startLine = value.start.toInt();
                                            endLine = value.end.toInt();
                                            setState(_refreshPreviewPdf);
                                          },
                                        ),
                                        Text(
                                          '${endLine - startLine} שורות נבחרו מתוך $totalLines',
                                          style: TextStyle(
                                            color: colorScheme.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],

                                      // בחירת טווח לפי כותרות
                                      if (_rangeMode ==
                                              _PrintRangeMode.headers &&
                                          _flatHeaders.isNotEmpty) ...[
                                        _buildDropdownRow(
                                          context: context,
                                          label: 'מ-',
                                          child: AppDropdownField<int>(
                                            value: _startHeaderIndex,
                                            enableSearch: true,
                                            entries: _flatHeaders
                                                .asMap()
                                                .entries
                                                .where((entry) =>
                                                    _endHeaderIndex == null ||
                                                    entry.key <=
                                                        _endHeaderIndex!)
                                                .map(
                                                  (entry) => AppMenuEntry(
                                                    value: entry.key,
                                                    label: entry.value.fullText,
                                                  ),
                                                )
                                                .toList(),
                                            onSelected: (int? value) {
                                              setState(() {
                                                _startHeaderIndex = value;
                                                if (_endHeaderIndex != null &&
                                                    value != null &&
                                                    value > _endHeaderIndex!) {
                                                  _endHeaderIndex = value;
                                                }
                                                _updateRangeByHeaders();
                                              });
                                            },
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        _buildDropdownRow(
                                          context: context,
                                          label: 'עד-',
                                          child: AppDropdownField<int>(
                                            value: _endHeaderIndex,
                                            enableSearch: true,
                                            entries: _flatHeaders
                                                .asMap()
                                                .entries
                                                .where((entry) =>
                                                    _startHeaderIndex == null ||
                                                    entry.key >=
                                                        _startHeaderIndex!)
                                                .map(
                                                  (entry) => AppMenuEntry(
                                                    value: entry.key,
                                                    label: entry.value.fullText,
                                                  ),
                                                )
                                                .toList(),
                                            onSelected: (int? value) {
                                              setState(() {
                                                _endHeaderIndex = value;
                                                if (_startHeaderIndex != null &&
                                                    value != null &&
                                                    value <
                                                        _startHeaderIndex!) {
                                                  _startHeaderIndex = value;
                                                }
                                                _updateRangeByHeaders();
                                              });
                                            },
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${(_endHeaderIndex ?? 0) - (_startHeaderIndex ?? 0) + 1} כותרות נבחרו',
                                          style: TextStyle(
                                            color: colorScheme.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],

                                      // בחירת טווח לפי כותרות משנה
                                      if (_rangeMode ==
                                              _PrintRangeMode.altHeaders &&
                                          _flatAltHeaders.isNotEmpty) ...[
                                        _buildDropdownRow(
                                          context: context,
                                          label: 'מ-',
                                          child: AppDropdownField<int>(
                                            value: _startAltHeaderIndex,
                                            enableSearch: true,
                                            entries: _flatAltHeaders
                                                .asMap()
                                                .entries
                                                .where((entry) =>
                                                    _endAltHeaderIndex ==
                                                        null ||
                                                    entry.key <=
                                                        _endAltHeaderIndex!)
                                                .map(
                                                  (entry) => AppMenuEntry(
                                                    value: entry.key,
                                                    label: entry.value.fullText,
                                                  ),
                                                )
                                                .toList(),
                                            onSelected: (int? value) {
                                              setState(() {
                                                _startAltHeaderIndex = value;
                                                if (_endAltHeaderIndex !=
                                                        null &&
                                                    value != null &&
                                                    value >
                                                        _endAltHeaderIndex!) {
                                                  _endAltHeaderIndex = value;
                                                }
                                                _updateRangeByAltHeaders();
                                              });
                                            },
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        _buildDropdownRow(
                                          context: context,
                                          label: 'עד-',
                                          child: AppDropdownField<int>(
                                            value: _endAltHeaderIndex,
                                            enableSearch: true,
                                            entries: _flatAltHeaders
                                                .asMap()
                                                .entries
                                                .where((entry) =>
                                                    _startAltHeaderIndex ==
                                                        null ||
                                                    entry.key >=
                                                        _startAltHeaderIndex!)
                                                .map(
                                                  (entry) => AppMenuEntry(
                                                    value: entry.key,
                                                    label: entry.value.fullText,
                                                  ),
                                                )
                                                .toList(),
                                            onSelected: (int? value) {
                                              setState(() {
                                                _endAltHeaderIndex = value;
                                                if (_startAltHeaderIndex !=
                                                        null &&
                                                    value != null &&
                                                    value <
                                                        _startAltHeaderIndex!) {
                                                  _startAltHeaderIndex = value;
                                                }
                                                _updateRangeByAltHeaders();
                                              });
                                            },
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${(_endAltHeaderIndex ?? 0) - (_startAltHeaderIndex ?? 0) + 1} כותרות משנה נבחרו',
                                          style: TextStyle(
                                            color: colorScheme.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // הגדרות טקסט
                                _buildSectionCard(
                                  context: context,
                                  title: 'הגדרות טקסט',
                                  icon: FluentIcons.text_font_24_regular,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildSliderRow(
                                        context: context,
                                        label: 'גודל גופן',
                                        value: fontSize,
                                        min: 10,
                                        max: 50,
                                        displayValue:
                                            fontSize.toInt().toString(),
                                        onChanged: (value) {
                                          setState(() {
                                            fontSize = value;
                                          });
                                        },
                                        onChangeEnd: (value) {
                                          fontSize = value;
                                          setState(_refreshPreviewPdf);
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: 80,
                                            child: Text(
                                              'גופן',
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: AppDropdownField<String>(
                                              value: fontName,
                                              enableSearch: true,
                                              decoration: const InputDecoration(
                                                hintText: 'חיפוש גופן',
                                              ),
                                              entries: fontNames.entries
                                                  .map(
                                                    (entry) => AppMenuEntry(
                                                      value: entry.key,
                                                      label: entry.value,
                                                    ),
                                                  )
                                                  .toList(),
                                              onSelected: (value) {
                                                if (value == null) return;
                                                setState(() {
                                                  fontName = value;
                                                  _refreshPreviewPdf();
                                                });
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      // הגדרות ניקוד וטעמים
                                      SwitchListTile(
                                        title: const Text('הדפסה עם ניקוד'),
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        value: !_removeNikud,
                                        onChanged: (value) {
                                          setState(() {
                                            _removeNikud = !value;
                                            _refreshPreviewPdf();
                                          });
                                        },
                                      ),
                                      SwitchListTile(
                                        title: const Text('הדפסה עם טעמים'),
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        value: !_removeTaamim,
                                        onChanged: (value) {
                                          setState(() {
                                            _removeTaamim = !value;
                                            _refreshPreviewPdf();
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // הגדרות עמוד
                                _buildSectionCard(
                                  context: context,
                                  title: 'הגדרות עמוד',
                                  icon: FluentIcons.document_24_regular,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _buildSliderRow(
                                        context: context,
                                        label: 'שוליים',
                                        value: pageMargin,
                                        min: 10,
                                        max: 100,
                                        displayValue:
                                            '${pageMargin.toInt()} px',
                                        onChanged: (value) {
                                          setState(() {
                                            pageMargin = value;
                                          });
                                        },
                                        onChangeEnd: (value) {
                                          pageMargin = value;
                                          setState(_refreshPreviewPdf);
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      _buildDropdownRow(
                                        context: context,
                                        label: 'גודל עמוד',
                                        child: AppDropdownField<PdfPageFormat>(
                                          value: format,
                                          entries: formats.entries
                                              .map(
                                                (entry) => AppMenuEntry(
                                                  value: entry.key,
                                                  label: entry.value,
                                                ),
                                              )
                                              .toList(),
                                          onSelected: (PdfPageFormat? value) {
                                            if (value == null) return;
                                            setState(() {
                                              format = value;
                                              _refreshPreviewPdf();
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _buildDropdownRow(
                                        context: context,
                                        label: 'כיוון',
                                        child: AppDropdownField<
                                            pw.PageOrientation>(
                                          value: orientation,
                                          entries: const [
                                            AppMenuEntry(
                                              value:
                                                  pw.PageOrientation.portrait,
                                              label: 'לאורך',
                                            ),
                                            AppMenuEntry(
                                              value:
                                                  pw.PageOrientation.landscape,
                                              label: 'לרוחב',
                                            ),
                                          ],
                                          onSelected:
                                              (pw.PageOrientation? value) {
                                            if (value == null) return;
                                            setState(() {
                                              orientation = value;
                                              _refreshPreviewPdf();
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _buildDropdownRow(
                                        context: context,
                                        label: 'עמודים בגליון',
                                        child: AppDropdownField<int>(
                                          value: _pagesPerSheet,
                                          entries: const [
                                            AppMenuEntry(
                                              value: 1,
                                              label: '1 (רגיל)',
                                            ),
                                            AppMenuEntry(
                                              value: 2,
                                              label: '2 (יישור לימין)',
                                            ),
                                            AppMenuEntry(
                                              value: 4,
                                              label: '4 (יישור לימין)',
                                            ),
                                          ],
                                          onSelected: (int? value) {
                                            if (value == null) return;
                                            setState(() {
                                              _pagesPerSheet = value;
                                              _refreshPreviewPdf();
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // תצוגה מקדימה של ה-PDF
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(12),
                              topLeft: Radius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: FutureBuilder(
                                    future: _previewPdf,
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState ==
                                              ConnectionState.done &&
                                          snapshot.hasData) {
                                        final (pdfBytes, pdfSourceName) =
                                            snapshot.data!;
                                        return PdfViewer.data(
                                          pdfBytes,
                                          sourceName: pdfSourceName,
                                          controller: _pdfViewerController,
                                          params: PdfViewerParams(
                                            viewerOverlayBuilder: (context,
                                                    size, handleLinkTap) =>
                                                [
                                              PdfScrollbar(
                                                controller:
                                                    _pdfViewerController,
                                                orientation:
                                                    ScrollbarOrientation.right,
                                                trackThickness: 16.0,
                                                thumbMinSize: 50.0,
                                              ),
                                              PdfHorizontalScrollbar(
                                                controller:
                                                    _pdfViewerController,
                                                trackThickness: 10.0,
                                              ),
                                            ],
                                            onDocumentChanged: (document) {
                                              if (document == null) {
                                                _documentRef.value = null;
                                              }
                                            },
                                            onViewerReady:
                                                (document, controller) {
                                              _documentRef.value =
                                                  controller.documentRef;
                                            },
                                          ),
                                        );
                                      }
                                      if (snapshot.hasError) {
                                        return Center(
                                          child: Icon(
                                            FluentIcons.error_circle_24_regular,
                                            color: colorScheme.error,
                                            size: 48,
                                          ),
                                        );
                                      }
                                      return Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircularProgressIndicator(
                                              color: colorScheme.primary,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'מכין תצוגה מקדימה...',
                                              style: TextStyle(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                if (_showThumbnails) ...[
                                  VerticalDivider(
                                    width: 1,
                                    color: colorScheme.outlineVariant,
                                  ),
                                  SizedBox(
                                    width: 260,
                                    child:
                                        ValueListenableBuilder<PdfDocumentRef?>(
                                      valueListenable: _documentRef,
                                      builder: (context, documentRef, _) {
                                        return ThumbnailsView(
                                          documentRef: documentRef,
                                          controller: _pdfViewerController,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          'טוען נתונים...',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: AppSurfaces.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required BuildContext context,
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                displayValue,
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownRow({
    required BuildContext context,
    required String label,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: child,
          ),
        ),
      ],
    );
  }

  // שימוש בקבועים מ-AppFonts
  Map<String, String> get fonts => AppFonts.fontPaths;
  Map<String, String> get fontNames {
    // כולל את כל הגופנים הזמינים (גם מהמערכת), אבל רק גופנים מוטמעים יכולים להיות מודפסים
    final Map<String, String> allFonts = {};
    for (final font in AppFonts.availableFonts) {
      allFonts[font.value] = font.label;
    }
    return allFonts;
  }

  final Map<PdfPageFormat, String> formats = {
    PdfPageFormat.a4: 'A4',
    PdfPageFormat.letter: 'Letter',
    PdfPageFormat.legal: 'Legal',
    PdfPageFormat.a5: 'A5',
    PdfPageFormat.a3: 'A3',
  };
}

enum _ExportFormat {
  word('docx'),
  pdf('pdf');

  final String extension;
  const _ExportFormat(this.extension);
}

// סף רוחב: מתחתיו הכותרת יורדת לשורה שנייה וכפתור ביטול הופך לX
const double _kPrintingAppBarWideThreshold = 435.0;

class _PrintingAppBar extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final VoidCallback onExport;
  final VoidCallback onPrint;

  const _PrintingAppBar({
    required this.title,
    required this.onClose,
    required this.onExport,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _kPrintingAppBarWideThreshold;

        final printExportButtons = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeutralActionButton(
              text: 'ייצא',
              icon: FluentIcons.arrow_export_ltr_24_regular,
              onPressed: onExport,
            ),
            const SizedBox(width: 8),
            RecommendedActionButton(
              text: 'הדפסה',
              icon: FluentIcons.print_24_regular,
              onPressed: onPrint,
            ),
          ],
        );

        final titleWidget = Text(
          title,
          textDirection: TextDirection.rtl,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        );

        if (isWide) {
          // Stack: כותרת במרכז אמיתי, כפתורים מימין, ביטול משמאל
          // ב-RTL: centerStart=ימין, centerEnd=שמאל
          return SizedBox(
            height: kToolbarHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(child: titleWidget),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: printExportButtons,
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: NeutralActionButton(
                      text: 'ביטול',
                      onPressed: onClose,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  printExportButtons,
                  const Spacer(),
                  IconButton(
                    icon: const Icon(FluentIcons.dismiss_24_regular),
                    tooltip: 'סגירה',
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8, bottom: 6),
              child: Center(child: titleWidget),
            ),
          ],
        );
      },
    );
  }
}
