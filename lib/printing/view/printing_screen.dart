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
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/printing/serial_latest_runner.dart';
import 'package:otzaria/printing/printing_helpers.dart';
import 'package:otzaria/printing/pdf_text_rasterizer.dart';
import 'package:otzaria/printing/word_export_service.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/printing/view/widgets/printing_widgets.dart';

enum _AnchorKind { header, altHeader, line }

/// נקודת קצה לטווח ההדפסה — כותרת, כותרת משנה, או מספר שורה.
/// שתי נקודות הקצה (התחלה/עד) עצמאיות בסוגן, כך שניתן להתחיל בכותרת ולסיים בשורה.
@immutable
class _RangeAnchor {
  final _AnchorKind kind;
  final int index;
  const _RangeAnchor(this.kind, this.index);

  @override
  bool operator ==(Object other) =>
      other is _RangeAnchor && other.kind == kind && other.index == index;

  @override
  int get hashCode => Object.hash(kind, index);
}

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

  /// בלוקים מוכנים מראש להדפסה (למשל מכרטיסיית המפרשים). כשמסופק — מסך ההדפסה
  /// מדפיס אותם ישירות, ללא בחירת טווח שורות/כותרות והכללת מפרשים.
  final List<PrintBlock>? prebuiltBlocks;

  /// כותרת המסמך (שם הספר) כשמשתמשים ב-[prebuiltBlocks].
  final String? documentTitle;
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
    this.prebuiltBlocks,
    this.documentTitle,
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
  // התצוגה המקדימה מוצגת כתמונות מרוסטרות (ולא דרך PdfViewer), כי pdfrx מנהל
  // worker יחיד שלא יכול לרסטר תוך כדי שה-PdfViewer פעיל — שני openData בו-זמנית
  // תוקעים אותו. רסטור לתמונות עובר כולו דרך ה-runner הסדרתי ולכן בטוח.
  //
  // הרסטור מדורג: כל עמוד מתווסף ל-notifier מיד עם רסטורו, כך שהעמוד הראשון
  // מוצג בלי להמתין לכל הטווח. הטווח מוגבל ל-[_maxPreviewPages] כדי למנוע
  // צריכת זיכרון מופרזת/תקיעה במסמכים ארוכים מאוד.
  final ValueNotifier<
    ({
      List<Uint8List> pages,
      bool busy,
      bool failed,
      bool truncated,
    })
  >
  _preview = ValueNotifier((
    pages: const [],
    busy: true,
    failed: false,
    truncated: false,
  ));

  /// מספר העמודים המרבי שמרוסטרים לתצוגה המקדימה (ההדפסה/הייצוא כוללים הכול).
  static const int _maxPreviewPages = 60;

  /// controller ל-ScrollablePositionedList של התצוגה — מאפשר גם scrollbar
  /// (דרך [ScrollablePositionedListScrollbar]) וגם קפיצה לעמוד לפי אינדקס.
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  /// תצוגת תמונות מוקטנות של כל הדפים (לחיצה מנווטת לעמוד).
  bool _showThumbnails = false;

  /// האינדקס (0-based) של הדף הראשון הנראה כעת — לעדכון בורר "מעבר לדף".
  int _currentPreviewItem = 0;
  late Future<String> _dataFuture;
  pw.PageOrientation orientation = pw.PageOrientation.portrait;
  PdfPageFormat format = PdfPageFormat.a4;
  double pageMargin = 20.0;

  int _pagesPerSheet = 1;

  // טווח עמודים ב-PDF
  int _totalPdfPages = 0;
  int _pdfStartPage = 1;
  int _pdfEndPage = 0; // 0 = כל העמודים
  int _renderGeneration = 0; // מונה שביטול renders ישנים
  // נעילה סדרתית של פעולות pdfrx: שני openData במקביל תוקעים את הספרייה.
  Future<void> _rasterLock = Future.value();
  // הסדרת התצוגות המקדימות: render כבד אחד בכל רגע, ודילוג על render שהתיישן
  // בזמן ההמתנה בתור, כדי ששינויי פרמטרים עוקבים לא יריצו במקביל מספר יצירות
  // base PDF / רסטור ניקוד / isolate שמציפים את המעבד.
  final SerialLatestRunner<List<Uint8List>> _previewRunner =
      SerialLatestRunner<List<Uint8List>>();
  Map<int, String> _pageLabels = {};

  String _labelForPage(int pageNumber) =>
      labelForPdfPage(_pageLabels, pageNumber);

  bool _includeCommentaries = false;
  bool _includePersonalNotes = false;

  final Map<String, String> _commentaryContentCache = {};
  List<PersonalNote>? _personalNotesCache;
  bool _isLoadingNotes = false;
  Timer? _previewRefreshTimer;

  // נקודות הקצה של טווח ההדפסה — כל אחת עצמאית בסוגה (כותרת/כותרת משנה/שורה).
  _RangeAnchor? _startAnchor;
  _RangeAnchor? _endAnchor;
  List<TocEntry> _flatHeaders = [];
  List<TocEntry> _flatAltHeaders = [];

  // מטמון פריטי התפריט (כותרות + כותרות משנה + שורות) — נבנה פעם אחת כדי
  // לא לבנות אלפי פריטי שורה בכל build.
  List<AppMenuEntry<_RangeAnchor>>? _anchorEntries;

  // הגדרות ניקוד וטעמים - ברירת מחדל לפי תצוגת הספר
  late bool _removeNikud;
  late bool _removeTaamim;

  // יעד ההדפסה הנבחר (הדפסה/PDF/Word) — נשמר כעדיפות לפעמים הבאות.
  static const _destinationKey = 'key-print-destination';
  late _PrintDestination _destination;

  bool get _supportsWord => widget.createPdfOverride == null;

  void _setDestination(_PrintDestination value) {
    setState(() => _destination = value);
    Settings.setValue<int>(_destinationKey, value.index);
  }

  @override
  void initState() {
    super.initState();
    _dataFuture = widget.data;
    startLine = widget.startLine;
    endLine = startLine;
    _itemPositionsListener.itemPositions.addListener(_onPreviewScroll);

    // יעד ההדפסה השמור — נופל ל-Word ל-PDF כשלא נתמך במצב הנוכחי.
    final savedDestination = Settings.getValue<int>(_destinationKey);
    _destination =
        _PrintDestination.values[(savedDestination ??
                _PrintDestination.printer.index)
            .clamp(0, _PrintDestination.values.length - 1)];
    if (_destination == _PrintDestination.word && !_supportsWord) {
      _destination = _PrintDestination.pdf;
    }

    // אתחול הגדרות ניקוד וטעמים לפי תצוגת הספר
    _removeNikud = widget.removeNikud;
    _removeTaamim = widget.removeTaamim;

    // במצב PDF חיצוני (כמו "צורת הדף") אין טווח שורות/כותרות.
    if (widget.createPdfOverride != null) {
      _flatHeaders = const [];
      _pageLabels = buildPdfPageLabels(widget.pdfOutline);
      if (widget.initialPage != null) {
        _pdfStartPage = widget.initialPage!;
        _pdfEndPage = widget.isBookView
            ? widget.initialPage! + 1
            : widget.initialPage!;
      }
      _renderPreview();
      return;
    }

    // מצב בלוקים מוכנים (כרטיסיית מפרשים): אין טווח שורות/כותרות.
    if (widget.prebuiltBlocks != null) {
      _flatHeaders = const [];
      _renderPreview();
      return;
    }

    // יצירת רשימה שטוחה של כל הכותרות
    _flatHeaders = _flattenHeaders(widget.tableOfContents);

    // ברירת המחדל היא הכותרת האחרונה שלפני השורה הנראית (ועד סוף אותה כותרת);
    // בלי כותרות — טווח שורות מסביב לשורה הראשונה הנראית.
    if (_flatHeaders.isNotEmpty) {
      final lastHeader = findLastHeaderIndexAtOrBefore(
        _flatHeaders,
        widget.startLine,
      );
      _startAnchor = _RangeAnchor(_AnchorKind.header, lastHeader);
      _endAnchor = _RangeAnchor(_AnchorKind.header, lastHeader);
    } else {
      _startAnchor = _RangeAnchor(_AnchorKind.line, widget.startLine);
      _endAnchor = _RangeAnchor(_AnchorKind.line, widget.startLine + 2);
    }

    _initPreviewRange();
    _loadAltHeaders();
  }

  @override
  void didUpdateWidget(covariant PrintingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _dataFuture = widget.data;
      _cachedBasePdf = null;
      _cachedBaseKey = null;
      _anchorEntries = null; // מספר השורות עשוי להשתנות — נבנה מחדש
      _initPreviewRange();
    }
  }

  Future<void> _initPreviewRange() async {
    await _applyCurrentRange();
    if (mounted) {
      setState(() {});
    }
    _renderPreview();
  }

  Future<int> _totalLineCount() async => (await _dataFuture).split('\n').length;

  Future<void> _applyCurrentRange() async {
    final totalLines = await _totalLineCount();
    if (!mounted) return;

    final s = _anchorStartLine(_startAnchor, totalLines);
    final e = _anchorEndLine(_endAnchor, totalLines);
    // מצב PDF/בלוקים — אין עוגנים, משאירים את הטווח כפי שהוא (מוגבל לגבולות).
    if (s == null || e == null) {
      startLine = startLine.clamp(0, totalLines);
      endLine = endLine.clamp(startLine, totalLines);
      return;
    }
    startLine = s.clamp(0, totalLines);
    endLine = e.clamp(startLine, totalLines);
  }

  /// שורת ההתחלה של עוגן: כותרת/כותרת משנה → שורת הכותרת; שורה → השורה עצמה.
  int? _anchorStartLine(_RangeAnchor? anchor, int totalLines) {
    if (anchor == null) return null;
    switch (anchor.kind) {
      case _AnchorKind.header:
        if (_flatHeaders.isEmpty) return null;
        return _flatHeaders[anchor.index.clamp(0, _flatHeaders.length - 1)]
            .index;
      case _AnchorKind.altHeader:
        if (_flatAltHeaders.isEmpty) return null;
        return _flatAltHeaders[anchor.index.clamp(
              0,
              _flatAltHeaders.length - 1,
            )]
            .index;
      case _AnchorKind.line:
        return anchor.index;
    }
  }

  /// שורת הסיום (בלעדית) של עוגן: כותרת → תחילת הכותרת הבאה (או סוף הספר);
  /// שורה → השורה שאחריה, כך שהשורה הנבחרת נכללת.
  int? _anchorEndLine(_RangeAnchor? anchor, int totalLines) {
    if (anchor == null) return null;
    switch (anchor.kind) {
      case _AnchorKind.header:
        if (_flatHeaders.isEmpty) return null;
        final i = anchor.index.clamp(0, _flatHeaders.length - 1);
        return i < _flatHeaders.length - 1
            ? _flatHeaders[i + 1].index
            : totalLines;
      case _AnchorKind.altHeader:
        if (_flatAltHeaders.isEmpty) return null;
        final i = anchor.index.clamp(0, _flatAltHeaders.length - 1);
        return i < _flatAltHeaders.length - 1
            ? _flatAltHeaders[i + 1].index
            : totalLines;
      case _AnchorKind.line:
        return anchor.index + 1;
    }
  }

  Future<void> _loadAltHeaders() async {
    if (widget.createPdfOverride != null) return;
    try {
      final structures = await DatabaseLibraryProvider.instance
          .getAlternativeStructuresForBook(widget.bookId);
      if (structures.isEmpty || !mounted) return;

      // שימוש ב-structure הראשון בלבד - ריבוי structures מערבב ערכים
      final rows = await DatabaseLibraryProvider.instance.getAltTocLineIndices(
        structures.first.id,
      );
      if (!mounted || rows.isEmpty) return;

      final altEntries = rows
          .map((r) => TocEntry(text: r.text, index: r.lineIndex))
          .toList();

      final lastAlt = findLastHeaderIndexAtOrBefore(
        altEntries,
        widget.startLine,
      );
      setState(() {
        _flatAltHeaders = altEntries;
        _anchorEntries = null; // נבנה מחדש עם כותרות המשנה
        // בלי ניווט רגיל — ברירת המחדל היא כותרות המשנה.
        if (_flatHeaders.isEmpty) {
          _startAnchor = _RangeAnchor(_AnchorKind.altHeader, lastAlt);
          _endAnchor = _RangeAnchor(_AnchorKind.altHeader, lastAlt);
          _updateRangeFromAnchors();
        }
      });
    } catch (e) {
      debugPrint('Error loading alt headers for printing: $e');
    }
  }

  /// מעדכן את טווח השורות מהעוגנים ומרענן את התצוגה המקדימה.
  void _updateRangeFromAnchors() async {
    await _applyCurrentRange();
    if (!mounted) return;
    _refreshPreview(immediate: true);
    setState(() {});
  }

  @override
  void dispose() {
    _previewRefreshTimer?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_onPreviewScroll);
    _preview.dispose();
    super.dispose();
  }

  /// עדכון הדף הנוכחי (הראשון הנראה) לבורר "מעבר לדף" — מתעדכן גם בגלילה ידנית.
  void _onPreviewScroll() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty || !mounted) return;
    final minIndex = positions
        .map((p) => p.index)
        .reduce((a, b) => a < b ? a : b);
    if (minIndex != _currentPreviewItem) {
      setState(() => _currentPreviewItem = minIndex);
    }
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

  void _refreshPreview({bool immediate = false}) {
    _renderGeneration++;
    _previewRefreshTimer?.cancel();
    if (immediate) {
      _renderPreview();
      return;
    }
    _previewRefreshTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _renderPreview();
    });
  }

  /// מרנדר את התצוגה המקדימה בהדרגה: כל עמוד מתווסף ל-[_preview] מיד עם רסטורו,
  /// כך שהעמוד הראשון מוצג בלי להמתין לכל הטווח. כל העבודה עוברת דרך ה-runner
  /// הסדרתי (render כבד אחד בכל רגע, דילוג על renders מיושנים), כך שלא ירוצו
  /// שני openData של pdfrx במקביל.
  void _renderPreview() {
    final generation = _renderGeneration;
    // מנקים את התמונות הקודמות ומציגים אינדיקטור טעינה — אחרת טווח קודם
    // (למשל גדול יותר) ממשיך להופיע עד שהטווח החדש מסיים להיטען.
    _preview.value = (
      pages: const [],
      busy: true,
      failed: false,
      truncated: false,
    );
    _previewRunner.run(
      isStale: () => generation != _renderGeneration,
      task: () => _renderPreviewTask(generation),
    );
  }

  Future<List<Uint8List>> _renderPreviewTask(int generation) async {
    try {
      // רסטור ה-base PDF בלבד (openData אחד). פריסת ה-N-up נבנית מהתמונות
      // ב-Flutter — לא יוצרים PDF ביניים ולא פותחים אותו שוב.
      final base = await _createBasePdf(format);
      if (generation != _renderGeneration || !mounted) return const [];
      final isPdfMode = widget.createPdfOverride != null;
      final startPage = isPdfMode ? _pdfStartPage : 1;
      final endPage = computePdfPrintEndPage(
        isPdfMode: isPdfMode,
        pdfEndPage: _pdfEndPage,
        totalPdfPages: _totalPdfPages,
      );
      final pages = <Uint8List>[];
      final truncated = await _rasterizePdfToImages(
        base,
        generation,
        startPage: startPage,
        endPage: endPage,
        onPage: (img) {
          pages.add(img);
          if (generation != _renderGeneration || !mounted) return;
          _preview.value = (
            pages: List<Uint8List>.unmodifiable(pages),
            busy: true,
            failed: false,
            truncated: false,
          );
        },
      );
      if (generation == _renderGeneration && mounted) {
        _preview.value = (
          pages: List<Uint8List>.unmodifiable(pages),
          busy: false,
          failed: false,
          truncated: truncated,
        );
      }
      return pages;
    } catch (e, st) {
      debugPrint('[PRINT] preview render failed: $e\n$st');
      if (generation == _renderGeneration && mounted) {
        _preview.value = (
          pages: const [],
          busy: false,
          failed: true,
          truncated: false,
        );
      }
      return const [];
    }
  }

  /// פותח PDF מ-bytes שכבר בזיכרון, בטעינה ישירה (FPDF_LoadMemDocument).
  ///
  /// ה-openData הרגיל עובר ל-on-demand (FPDF_LoadCustomDocument עם read
  /// callbacks) לכל PDF מעל 1MB — וה-callbacks נתקעים אחרי close של מסמך קודם.
  /// כאן מאלצים caching בזיכרון, כך שאין callbacks ואין תקיעה.
  Future<PdfDocument> _openPdfInMemory(Uint8List bytes, String tag) {
    return PdfDocument.openCustom(
      read: (buffer, position, size) {
        final end = min(position + size, bytes.length);
        final count = end - position;
        if (count <= 0) return 0;
        buffer.setRange(0, count, bytes, position);
        return count;
      },
      fileSize: bytes.length,
      sourceName: '${tag}_${DateTime.now().millisecondsSinceEpoch}',
      maxSizeToCacheOnMemory: 1024 * 1024 * 1024,
    );
  }

  /// מרסטר את עמודי ה-PDF (בטווח הנתון, עד [_maxPreviewPages]) לתמונות PNG,
  /// וקורא [onPage] לכל עמוד מיד עם רסטורו (תצוגה מדורגת). מחזיר `true` אם
  /// הטווח נחתך בגלל המגבלה.
  ///
  /// נקרא רק מתוך ה-runner הסדרתי וללא PdfViewer פעיל, כך שאין openData מקביל.
  Future<bool> _rasterizePdfToImages(
    Uint8List pdfBytes,
    int generation, {
    int startPage = 1,
    int? endPage,
    required void Function(Uint8List) onPage,
  }) => _withRasterLock(
    () => _rasterizePdfToImagesLocked(
      pdfBytes,
      generation,
      startPage: startPage,
      endPage: endPage,
      onPage: onPage,
    ),
    'images',
  );

  Future<bool> _rasterizePdfToImagesLocked(
    Uint8List pdfBytes,
    int generation, {
    int startPage = 1,
    int? endPage,
    required void Function(Uint8List) onPage,
  }) async {
    if (generation != _renderGeneration || !mounted) return false;
    final doc = await _openPdfInMemory(pdfBytes, 'preview');
    try {
      final pageCount = doc.pages.length;
      // במצב PDF חיצוני, ספירת העמודים נחוצה לבחירת טווח עמודים ב-UI.
      if (_totalPdfPages == 0 && widget.createPdfOverride != null && mounted) {
        setState(() {
          _totalPdfPages = pageCount;
          _pdfStartPage = _pdfStartPage.clamp(1, pageCount);
          _pdfEndPage = _pdfEndPage == 0
              ? pageCount
              : _pdfEndPage.clamp(1, pageCount);
        });
      }

      final firstIdx = max(0, min(startPage - 1, pageCount - 1));
      final lastIdx = max(
        firstIdx,
        min((endPage ?? pageCount) - 1, pageCount - 1),
      );
      // גג בטיחותי: לא מרסטרים יותר מ-[_maxPreviewPages] לתצוגה (ההדפסה
      // וההייצוא כוללים את כל הטווח דרך _createOutputPdf).
      final limitIdx = min(lastIdx, firstIdx + _maxPreviewPages - 1);

      // רזולוציית התצוגה המקדימה בלבד — הפלט המודפס הוא ה-PDF הווקטורי,
      // כך שאין השפעה על איכות ההדפסה. 2x הכפיל את זיכרון ה-preview לחינם.
      const previewScale = 1.5;
      for (var i = firstIdx; i <= limitIdx; i++) {
        if (generation != _renderGeneration || !mounted) break;
        final page = doc.pages[i];
        final pdfImage = await page.render(
          fullWidth: page.width * previewScale,
          fullHeight: page.height * previewScale,
          backgroundColor: AppColors.pageWhite.toARGB32(),
        );
        if (pdfImage == null) continue;
        final uiImage = await pdfImage.createImage();
        pdfImage.dispose();
        final byteData = await uiImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        uiImage.dispose();
        if (byteData == null) continue;
        onPage(byteData.buffer.asUint8List());
      }
      return lastIdx > limitIdx;
    } finally {
      // חובה await: dispose שולח FPDF_CloseDocument ל-worker. בלי המתנה,
      // ה-close רץ בו-זמנית עם ה-openData של ה-render הבא ותוקע את pdfrx.
      await doc.dispose();
    }
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
    final hasPageRange = hasPdfPageRange(
      startPage: startPage,
      endPage: endPage,
    );

    if (_pagesPerSheet <= 1 && !hasPageRange) {
      return base;
    }

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
        UiSnack.showError(
          hasPageRange
              ? PdfMessages.pageRangeRenderFailed
              : PdfMessages.multiPageSheetRenderFailed,
        );
      }
      rethrow;
    }
  }

  PdfPageFormat _effectivePageFormat(PdfPageFormat format) {
    return orientation == pw.PageOrientation.landscape
        ? format.landscape
        : format;
  }

  // מטמון ה-base PDF: שינוי שמשפיע רק על שלב הרסטור (מספר עמודים בגיליון,
  // טווח עמודים ב-PDF חיצוני) לא בונה מחדש את המסמך — רק מרסטר אותו שוב.
  Uint8List? _cachedBasePdf;
  String? _cachedBaseKey;

  /// חתימת כל הפרמטרים שמשפיעים על תוכן ה-base PDF. שדות שמשפיעים רק על
  /// הרסטור (‎_pagesPerSheet, טווח עמודים ב-PDF חיצוני) בכוונה אינם נכללים.
  String _baseCacheKey(PdfPageFormat format) {
    if (widget.createPdfOverride != null) {
      return 'override|${orientation.name}|${format.width}x${format.height}';
    }
    final holyNames = Settings.getValue<bool>('key-replace-holy-names') ?? true;
    return [
      orientation.name,
      format.width,
      format.height,
      pageMargin,
      fontSize,
      fontName,
      _removeNikud,
      _removeTaamim,
      holyNames,
      startLine,
      endLine,
      _includeCommentaries,
      _includePersonalNotes,
    ].join('|');
  }

  Future<Uint8List> _createBasePdf(PdfPageFormat format) async {
    final key = _baseCacheKey(format);
    final cached = _cachedBasePdf;
    if (cached != null && _cachedBaseKey == key) {
      return cached;
    }
    final override = widget.createPdfOverride;
    final Uint8List bytes;
    if (override != null) {
      final effectiveFormat = orientation == pw.PageOrientation.landscape
          ? format.landscape
          : format;
      bytes = await override(effectiveFormat);
    } else {
      bytes = await createPdf(format);
    }
    _cachedBasePdf = bytes;
    _cachedBaseKey = key;
    return bytes;
  }

  Future<Uint8List> _createNUpPdfFromRaster(
    Uint8List sourcePdf, {
    required PdfPageFormat sheetFormat,
    required int pagesPerSheet,
    int startPage = 1,
    int? endPage,
  }) async {
    // הסדרה של כל פעולות ה-pdfrx: שני openData במקביל תוקעים את ה-worker היחיד.
    return _withRasterLock(
      () => _rasterizeNUp(
        sourcePdf,
        sheetFormat: sheetFormat,
        pagesPerSheet: pagesPerSheet,
        startPage: startPage,
        endPage: endPage,
      ),
      'nup',
    );
  }

  /// מריץ [action] בהסדרה מול כל שאר פעולות ה-pdfrx (openData/render),
  /// כדי שלעולם לא ירוצו שתיים במקביל ויתקעו את ה-worker היחיד של pdfrx.
  Future<T> _withRasterLock<T>(
    Future<T> Function() action, [
    String label = '',
  ]) async {
    final completer = Completer<void>();
    final previousLock = _rasterLock;
    _rasterLock = completer.future;
    try {
      await previousLock;
      return await action();
    } finally {
      completer.complete();
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

    // אם נרשם render חדש יותר, דלג כדי לא לבזבז עבודה מיושנת.
    if (generation != _renderGeneration || !mounted) return sourcePdf;

    final doc = await _openPdfInMemory(sourcePdf, 'nup');

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
      final lastIdx = max(
        firstIdx,
        min((endPage ?? doc.pages.length) - 1, doc.pages.length - 1),
      );
      for (var i = firstIdx; i <= lastIdx; i++) {
        // אם המשתמש שינה פרמטר באמצע ה-render, זרוק את המסמך מוקדם.
        if (generation != _renderGeneration || !mounted) {
          return sourcePdf;
        }
        final page = doc.pages[i];
        final pdfImage = await page.render(
          fullWidth: page.width * scale,
          fullHeight: page.height * scale,
          backgroundColor: AppColors.pageWhite.toARGB32(),
        );
        if (pdfImage == null) continue;
        final uiImage = await pdfImage.createImage();
        pdfImage.dispose();
        final byteData = await uiImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        uiImage.dispose();
        if (byteData == null) continue;
        rasterPages.add(byteData.buffer.asUint8List());
      }
    } finally {
      // חובה await — ראה ההסבר ב-_rasterizePdfToImagesLocked.
      await doc.dispose();
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
          textDirection: pw.TextDirection.rtl,
          build: (context) {
            return pw.Column(
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
            );
          },
        ),
      );
    }

    return output.save();
  }

  Future<Uint8List> createPdf(PdfPageFormat format) async {
    if (widget.prebuiltBlocks != null) {
      return _createPrebuiltPdf(format);
    }
    String dataString = await _dataFuture;
    if (orientation == pw.PageOrientation.landscape) {
      format = format.landscape;
    }

    final shouldReplaceHolyNames =
        Settings.getValue<bool>('key-replace-holy-names') ?? true;

    // חלוקה גולמית לשורות בלבד. הטרנספורמציות היקרות (הסרת ניקוד/טעמים/HTML
    // והחלפת שמות קודש) מוחלות פר-שורה על הטווח הנבחר ב-_buildPrintBlocks —
    // לא על כל הספר. חוסך עבודה כשמדפיסים קטע קצר מתוך ספר ארוך.
    final allLines = dataString.split('\n');
    final pageMargin = this.pageMargin;
    final fontSize = this.fontSize;

    String bookName = allLines.isNotEmpty ? stripHtmlIfNeeded(allLines[0]) : '';
    bookName = _applyTextTransforms(bookName, shouldReplaceHolyNames);
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
    return _renderBlocksToPdf(
      blocks: blocks,
      format: format,
      bookName: bookName,
      pageMargin: pageMargin,
      fontSize: fontSize,
    );
  }

  /// יוצר PDF מבלוקים מוכנים מראש (כרטיסיית מפרשים).
  Future<Uint8List> _createPrebuiltPdf(PdfPageFormat format) async {
    if (orientation == pw.PageOrientation.landscape) {
      format = format.landscape;
    }
    final bookName = widget.documentTitle ?? widget.bookId;
    final blocks = _mapPrebuiltBlocks(widget.prebuiltBlocks ?? const []);
    return _renderBlocksToPdf(
      blocks: blocks,
      format: format,
      bookName: bookName,
      pageMargin: pageMargin,
      fontSize: fontSize,
    );
  }

  /// מסיר ניקוד/טעמים ומחליף שמות קודש לפי בחירת המשתמש.
  String _applyTextTransforms(String input, bool shouldReplaceHolyNames) {
    var text = input;
    if (_removeNikud && _removeTaamim) {
      text = removeVolwels(text);
    } else if (_removeNikud && !_removeTaamim) {
      text = text
          .replaceAll('־', ' ')
          .replaceAll('׀', ' ')
          .replaceAll('|', ' ')
          .replaceAll(RegExp(r'[ְ-ׇ]'), '');
    } else if (!_removeNikud && _removeTaamim) {
      text = removeTeamim(text);
    }
    if (shouldReplaceHolyNames) {
      text = replaceHolyNames(text);
    }
    return text;
  }

  /// ממיר בלוקים מוכנים לייצוג הפנימי, תוך החלת הסרת ניקוד/טעמים ושמות קודש.
  List<Map<String, String>> _mapPrebuiltBlocks(List<PrintBlock> source) {
    final shouldReplaceHolyNames =
        Settings.getValue<bool>('key-replace-holy-names') ?? true;
    final result = <Map<String, String>>[];
    for (final block in source) {
      switch (block.kind) {
        case PrintBlockKind.commentaryTitle:
          result.add({'kind': 'commentaryTitle', 'title': block.text});
        case PrintBlockKind.commentaryGroupTitle:
          result.add({'kind': 'commentaryGroupTitle', 'title': block.text});
        case PrintBlockKind.commentary:
          result.add({
            'kind': 'commentary',
            'text': _applyTextTransforms(block.text, shouldReplaceHolyNames),
          });
        case PrintBlockKind.heading:
        case PrintBlockKind.text:
          result.add({
            'kind': 'text',
            'text': _applyTextTransforms(block.text, shouldReplaceHolyNames),
          });
      }
    }
    return result;
  }

  /// מרנדר רשימת בלוקים (ייצוג פנימי) ל-PDF — משותף למצב הרגיל ולמצב הבלוקים
  /// המוכנים מראש.
  Future<Uint8List> _renderBlocksToPdf({
    required List<Map<String, String>> blocks,
    required PdfPageFormat format,
    required String bookName,
    required double pageMargin,
    required double fontSize,
  }) async {
    // אם הגופן לא מוטמע, השתמש בגופן ברירת מחדל
    final fontPath = fonts[fontName] ?? fonts.values.first;
    final font = pw.Font.ttf(await rootBundle.load(fontPath));
    final fullBackFont = pw.Font.ttf(
      await rootBundle.load('fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf'),
    );
    final contentWidth = max(1.0, format.width - pageMargin * 2);
    final rasterizedNikudBlocks = await _rasterizeNikudBlocks(
      blocks: blocks,
      fontName: fontName,
      fontSize: fontSize,
      contentWidth: contentWidth,
    );

    final result = await Isolate.run(() async {
      final pdfData = pw.Document(
        compress: false,
        pageMode: PdfPageMode.outlines,
      );
      pdfData.addPage(
        pw.MultiPage(
          theme: pw.ThemeData.withFont(
            base: font,
            fontFallback: [fullBackFont],
          ),
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          textDirection: pw.TextDirection.rtl,
          maxPages: 1000000,
          margin: pw.EdgeInsets.all(pageMargin),
          pageFormat: format,
          header: (pw.Context context) {
            return pw.Container(
              alignment: pw.Alignment.topCenter,
              margin: const pw.EdgeInsets.only(top: 1.0 * PdfPageFormat.cm),
              child: pw.Text(
                bookName,
                style: pw.Theme.of(
                  context,
                ).defaultTextStyle.copyWith(color: PdfColors.grey),
              ),
            );
          },
          footer: (pw.Context context) {
            return pw.Container(
              alignment: pw.Alignment.bottomCenter,
              margin: const pw.EdgeInsets.only(top: 1.0 * PdfPageFormat.cm),
              child: pw.Text(
                'עמוד ${context.pageNumber} מתוך ${context.pagesCount} - הודפס מתוכנת אוצריא',
                style: pw.Theme.of(
                  context,
                ).defaultTextStyle.copyWith(color: PdfColors.grey),
              ),
            );
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
                  ),
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
                  ),
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
                  ),
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
                ),
              ];
            }).toList();
          },
        ),
      );

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
    int selectedStart,
    int selectedEnd,
  ) async {
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
      } catch (e) {
        // נופלים לנתיב הקבצים — הלוג נדרש כי המפרשים עלולים לצאת שונים
        debugPrint(
          '[Print] getLinksForBookRange failed for '
          '"${book.title}": $e',
        );
      }
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
    } catch (e) {
      // widget.links אינו מסונן לטווח שנבחר — הכשל חייב להיות גלוי בלוג
      debugPrint('[Print] file links load failed for "${book.title}": $e');
    }

    return widget.links;
  }

  Future<List<Map<String, String>>> _buildPrintBlocks({
    required List<String> allLines,
    required int selectedStart,
    required int selectedEnd,
    required bool shouldReplaceHolyNames,
    required List<PersonalNote> personalNotes,
    bool keepHtml = false,
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
      // הסרת HTML + ניקוד/טעמים + שמות קודש מוחלת כאן, על שורות הטווח הנבחר
      // בלבד (הועברה לכאן מהטרנספורמציה על כל הספר ב-createPdf).
      final lineText = _applyTextTransforms(
        stripHtmlIfNeeded(allLines[i]),
        shouldReplaceHolyNames,
      );
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
              keepHtml: keepHtml,
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
    if (widget.prebuiltBlocks != null) {
      final shouldReplaceHolyNames =
          Settings.getValue<bool>('key-replace-holy-names') ?? true;
      final blocks = widget.prebuiltBlocks!
          .map((block) {
            switch (block.kind) {
              case PrintBlockKind.heading:
              case PrintBlockKind.text:
              case PrintBlockKind.commentary:
                return PrintBlock(
                  kind: block.kind,
                  text: _applyTextTransforms(
                    block.text,
                    shouldReplaceHolyNames,
                  ),
                  headingLevel: block.headingLevel,
                  footnotes: block.footnotes,
                );
              case PrintBlockKind.commentaryTitle:
              case PrintBlockKind.commentaryGroupTitle:
                return block;
            }
          })
          .toList(growable: false);
      return PreparedPrintDocument(
        bookName: widget.documentTitle ?? widget.bookId,
        blocks: blocks,
      );
    }
    String dataString = await _dataFuture;

    final shouldReplaceHolyNames =
        Settings.getValue<bool>('key-replace-holy-names') ?? true;
    dataString = _applyTextTransforms(dataString, shouldReplaceHolyNames);

    // שומרים את תגיות ה-HTML — WordExportService ממיר אותן לעיצוב במסמך
    final allLines = dataString.split('\n').toList();
    var bookName = allLines.isNotEmpty
        ? stripHtmlIfNeeded(allLines.first)
        : widget.bookId;
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
        keepHtml: true,
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

  /// מבצע את הפעולה לפי היעד הנבחר: הדפסה למדפסת, או שמירה ל-PDF/Word.
  Future<void> _performDestinationAction(BuildContext context) async {
    switch (_destination) {
      case _PrintDestination.printer:
        final printed = await Printing.layoutPdf(
          usePrinterSettings: true,
          onLayout: _createOutputPdf,
          format: format,
        );
        if (printed && context.mounted) {
          Navigator.of(context).pop(true);
        }
      case _PrintDestination.pdf:
        await _saveToFile(_ExportFormat.pdf);
      case _PrintDestination.word:
        await _saveToFile(_ExportFormat.word);
    }
  }

  Future<void> _saveToFile(_ExportFormat selectedFormat) async {
    if (!await verifySaferModePassword(context)) return;
    if (!mounted) return;
    try {
      final selectedExtension = selectedFormat.extension;
      final Uint8List bytes;
      final String successMessage;
      if (selectedFormat == _ExportFormat.word) {
        final prepared = await _prepareWordDocument();
        bytes = WordExportService.createWordDocument(
          title: prepared.bookName,
          blocks: prepared.blocks,
          format: format,
          isLandscape: orientation == pw.PageOrientation.landscape,
          pageMargin: pageMargin,
          fontFamily: fontName,
          fontSize: fontSize,
        );
        successMessage = PdfMessages.wordFileSaved;
      } else {
        bytes = await _createOutputPdf(format);
        successMessage = PdfMessages.pdfFileSaved;
      }
      final path = await FilePicker.saveFile(
        dialogTitle: 'ייצוא קובץ',
        fileName: '${_sanitizeFileName(widget.bookId)}.$selectedExtension',
        type: FileType.custom,
        allowedExtensions: [selectedExtension],
        bytes: bytes,
        lockParentWindow: true,
      );
      if (path == null) return;
      UiSnack.showSuccess(successMessage);
    } on FileSystemException catch (e) {
      if (_isLockedFileException(e)) {
        UiSnack.showError(PdfMessages.fileLockedByAnotherApp);
        return;
      }
      UiSnack.showError(PdfMessages.fileExportFailed(e.message));
    } catch (e) {
      UiSnack.showError(PdfMessages.fileExportFailed(e));
    }
  }

  String _sanitizeFileName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return sanitized.isEmpty ? 'output' : sanitized;
  }

  bool _isLockedFileException(FileSystemException error) {
    final message = '${error.message} ${error.osError?.message ?? ''}'
        .toLowerCase();
    return message.contains('used by another process') ||
        message.contains('being used by another process') ||
        message.contains('access is denied') ||
        message.contains('permission denied');
  }

  Future<String> _getCommentaryContent(
    Link link, {
    required bool shouldReplaceHolyNames,
    bool keepHtml = false,
  }) async {
    // המפתח כולל את דגלי הניקוד/טעמים/שמות-קודש: אחרת החלפת "הדפסה עם ניקוד"
    // הייתה מחזירה תוכן מפרש מוטרנספרם קודם (באג: הניקוד לא התעדכן).
    final key =
        '$_removeNikud|$_removeTaamim|$shouldReplaceHolyNames'
        '::${link.path2}::${link.index2}::${link.heRef}::$keepHtml';
    final cached = _commentaryContentCache[key];
    if (cached != null) return cached;

    var text = await link.content;
    if (!keepHtml) {
      text = stripHtmlIfNeeded(text);
    }
    text = _applyTextTransforms(text, shouldReplaceHolyNames);

    _commentaryContentCache[key] = text;
    return text;
  }

  Future<List<PersonalNote>> _getPersonalNotesForBook(String bookId) async {
    if (_personalNotesCache != null) return _personalNotesCache!;
    if (_isLoadingNotes) return const <PersonalNote>[];
    _isLoadingNotes = true;

    try {
      final repo = PersonalNotesRepository();
      final all = await repo.loadNotes(
        bookId,
        categoryId: widget.book?.categoryId,
      );
      final located = all.where((n) => n.hasLocation).toList();
      _personalNotesCache = located;
      return located;
    } catch (e) {
      // לא שומרים בקאש — כשל חולף לא ישמיט את ההערות מכל ההדפסות בדיאלוג
      debugPrint('[Print] personal notes load failed for "$bookId": $e');
      return const <PersonalNote>[];
    } finally {
      _isLoadingNotes = false;
    }
  }

  /// שם הצ'יפ (סוג העוגן) — לתוויות הסינון בתפריט ולבחירת הצ'יפ הפעיל בפתיחתו.
  String _kindChipLabel(_AnchorKind kind) => switch (kind) {
    _AnchorKind.header => 'כותרות',
    _AnchorKind.altHeader => 'כותרות משנה',
    _AnchorKind.line => 'שורות',
  };

  /// התווית המוצגת בשדה הסגור עבור עוגן (חישוב O(1), בלי סריקת כל הפריטים).
  String _anchorLabel(_RangeAnchor? anchor) {
    if (anchor == null) return '';
    switch (anchor.kind) {
      case _AnchorKind.header:
        return anchor.index < _flatHeaders.length
            ? _flatHeaders[anchor.index].fullText
            : '';
      case _AnchorKind.altHeader:
        return anchor.index < _flatAltHeaders.length
            ? _flatAltHeaders[anchor.index].fullText
            : '';
      case _AnchorKind.line:
        return 'שורה ${anchor.index + 1}';
    }
  }

  /// בונה (ושומר במטמון) את פריטי התפריט: כל הכותרות, כותרות המשנה והשורות.
  List<AppMenuEntry<_RangeAnchor>> _anchorMenuEntries(int totalLines) {
    final cached = _anchorEntries;
    if (cached != null) return cached;

    final entries = <AppMenuEntry<_RangeAnchor>>[];
    for (var i = 0; i < _flatHeaders.length; i++) {
      entries.add(
        AppMenuEntry(
          value: _RangeAnchor(_AnchorKind.header, i),
          label: _flatHeaders[i].fullText,
        ),
      );
    }
    for (var i = 0; i < _flatAltHeaders.length; i++) {
      entries.add(
        AppMenuEntry(
          value: _RangeAnchor(_AnchorKind.altHeader, i),
          label: _flatAltHeaders[i].fullText,
        ),
      );
    }
    for (var i = 0; i < totalLines; i++) {
      entries.add(
        AppMenuEntry(
          value: _RangeAnchor(_AnchorKind.line, i),
          label: 'שורה ${i + 1}',
        ),
      );
    }
    _anchorEntries = entries;
    return entries;
  }

  /// תוויות הסינון (הצ'יפים) והפרדיקטים שלהן — רק לסוגים שקיימים בספר.
  (List<String>, List<bool Function(AppMenuEntry<_RangeAnchor>)?>)
  _anchorFilters() {
    final labels = <String>[];
    final predicates = <bool Function(AppMenuEntry<_RangeAnchor>)?>[];
    if (_flatHeaders.isNotEmpty) {
      labels.add(_kindChipLabel(_AnchorKind.header));
      predicates.add((e) => e.value.kind == _AnchorKind.header);
    }
    if (_flatAltHeaders.isNotEmpty) {
      labels.add(_kindChipLabel(_AnchorKind.altHeader));
      predicates.add((e) => e.value.kind == _AnchorKind.altHeader);
    }
    labels.add(_kindChipLabel(_AnchorKind.line));
    predicates.add((e) => e.value.kind == _AnchorKind.line);
    return (labels, predicates);
  }

  /// שורת בורר עבור נקודת קצה אחת (התחלה/עד). התפריט מאחד כותרות/כותרות
  /// משנה/שורות עם צ'יפים לסינון, ונפתח על הצ'יפ שמתאים לסוג הבחירה הנוכחית.
  Widget _buildAnchorDropdownRow({
    required String label,
    required _RangeAnchor? anchor,
    required bool isStart,
    required int totalLines,
  }) {
    final (labels, predicates) = _anchorFilters();
    final initialFilter = anchor == null
        ? 0
        : max(0, labels.indexOf(_kindChipLabel(anchor.kind)));

    return PrintingDropdownRow(
      label: label,
      child: AppDropdownField<_RangeAnchor>(
        value: anchor,
        enableSearch: true,
        entries: _anchorMenuEntries(totalLines),
        filterLabels: labels,
        filterPredicates: predicates,
        initialFilter: initialFilter,
        selectedBuilder: (context, value) => Text(
          _anchorLabel(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onSelected: (value) {
          if (value == null) return;
          _onAnchorSelected(
            isStart: isStart,
            anchor: value,
            totalLines: totalLines,
          );
        },
      ),
    );
  }

  /// מעדכן את נקודת הקצה שנבחרה, ומיישר את הקצה השני אם הטווח התהפך.
  void _onAnchorSelected({
    required bool isStart,
    required _RangeAnchor anchor,
    required int totalLines,
  }) {
    if (isStart) {
      _startAnchor = anchor;
      final s = _anchorStartLine(anchor, totalLines);
      final e = _anchorEndLine(_endAnchor, totalLines);
      if (s != null && e != null && s > e) _endAnchor = anchor;
    } else {
      _endAnchor = anchor;
      final s = _anchorStartLine(_startAnchor, totalLines);
      final e = _anchorEndLine(anchor, totalLines);
      if (s != null && e != null && e < s) _startAnchor = anchor;
    }
    _updateRangeFromAnchors();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCustomPdfMode = widget.createPdfOverride != null;
    final isPrebuiltMode = widget.prebuiltBlocks != null;

    return Dialog(
      insetPadding: const EdgeInsets.fromLTRB(12, 40, 12, 12),
      clipBehavior: Clip.antiAlias,
      child: Scaffold(
        backgroundColor: AppSurfaces.solidPanelBackground(context),
        body: Column(
          children: [
            PrintingAppBar(
              title: 'הדפסה — ${widget.book?.title ?? widget.bookId}',
              leading: _buildTopBarNav(),
            ),
            Expanded(
              child: FutureBuilder(
                future: _dataFuture,
                builder: (context, snapshot) {
                  if (isCustomPdfMode) {
                    return Row(
                      children: [
                        // תצוגה מקדימה (תמונות מרוסטרות)
                        Expanded(child: _buildImagePreview(colorScheme)),
                        // פאנל הגדרות בצד
                        SizedBox(
                          width: 320,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildDestinationCard(context),
                                      if (_totalPdfPages > 0) ...[
                                        PrintingSectionCard(
                                          title: 'טווח עמודים',
                                          icon: FluentIcons
                                              .document_page_number_24_regular,
                                          children: [
                                            PrintingDropdownRow(
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
                                                      _pdfEndPage =
                                                          _pdfStartPage;
                                                    }
                                                    _refreshPreview();
                                                  });
                                                },
                                              ),
                                            ),
                                            PrintingDropdownRow(
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
                                                      _pdfStartPage + i,
                                                    ),
                                                  ),
                                                ),
                                                onSelected: (int? value) {
                                                  if (value == null) return;
                                                  setState(() {
                                                    _pdfEndPage = value;
                                                    _refreshPreview();
                                                  });
                                                },
                                              ),
                                            ),
                                            Padding(
                                              padding: kPrintingRowPadding,
                                              child: Text(
                                                '${_pdfEndPage - _pdfStartPage + 1} עמודים מתוך $_totalPdfPages',
                                                style: TextStyle(
                                                  color: colorScheme.primary,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      PrintingSectionCard(
                                        title: 'הגדרות דף',
                                        icon: FluentIcons.options_24_regular,
                                        children: [
                                          PrintingDropdownRow(
                                            label: 'גודל דף',
                                            child:
                                                AppDropdownField<PdfPageFormat>(
                                                  value: format,
                                                  entries:
                                                      const {
                                                        'A4': PdfPageFormat.a4,
                                                        'Letter': PdfPageFormat
                                                            .letter,
                                                      }.entries.map((entry) {
                                                        return AppMenuEntry(
                                                          value: entry.value,
                                                          label: entry.key,
                                                        );
                                                      }).toList(),
                                                  onSelected:
                                                      (PdfPageFormat? value) {
                                                        if (value == null) {
                                                          return;
                                                        }
                                                        setState(() {
                                                          format = value;
                                                          _refreshPreview();
                                                        });
                                                      },
                                                ),
                                          ),
                                          PrintingOrientationDropdownRow(
                                            value: orientation,
                                            onChanged: (value) {
                                              orientation = value;
                                              setState(_refreshPreview);
                                            },
                                          ),
                                          PrintingPagesPerSheetDropdownRow(
                                            value: _pagesPerSheet,
                                            onChanged: (value) {
                                              setState(() {
                                                _pagesPerSheet = value;
                                                _refreshPreview();
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              _buildPrintExportFooter(context),
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.done) {
                    final totalLines = snapshot.data!.split('\n').length;
                    return Row(
                      children: [
                        // תצוגה מקדימה (תמונות מרוסטרות)
                        Expanded(child: _buildImagePreview(colorScheme)),
                        // פאנל הגדרות בצד
                        SizedBox(
                          width: 320,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildDestinationCard(context),

                                      // כותרת טווח הדפסה — מוסתר במצב בלוקים מוכנים (מפרשים)
                                      if (!isPrebuiltMode) ...[
                                        PrintingSectionCard(
                                          title: 'טווח הדפסה',
                                          icon: FluentIcons
                                              .document_page_number_24_regular,
                                          children: [
                                            Padding(
                                              padding: kPrintingRowPadding,
                                              child: Align(
                                                alignment: AlignmentDirectional
                                                    .centerStart,
                                                child: Text(
                                                  '${(endLine - startLine).clamp(0, totalLines)} שורות נבחרו מתוך $totalLines',
                                                  style: TextStyle(
                                                    color: colorScheme.primary,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            _buildAnchorDropdownRow(
                                              label: 'התחלה',
                                              anchor: _startAnchor,
                                              isStart: true,
                                              totalLines: totalLines,
                                            ),
                                            _buildAnchorDropdownRow(
                                              label: 'עד',
                                              anchor: _endAnchor,
                                              isStart: false,
                                              totalLines: totalLines,
                                            ),
                                            PrintingSwitchRow(
                                              label: 'כלול מפרשים',
                                              value: _includeCommentaries,
                                              onChanged: (value) {
                                                setState(() {
                                                  _includeCommentaries = value;
                                                  _refreshPreview();
                                                });
                                              },
                                            ),
                                            PrintingSwitchRow(
                                              label: 'כלול הערות אישיות',
                                              value: _includePersonalNotes,
                                              onChanged: (value) {
                                                setState(() {
                                                  _includePersonalNotes = value;
                                                  if (!value) {
                                                    _personalNotesCache = null;
                                                  }
                                                  _refreshPreview();
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ],

                                      // הגדרות טקסט
                                      PrintingSectionCard(
                                        title: 'הגדרות טקסט',
                                        icon: FluentIcons.text_font_24_regular,
                                        children: [
                                          // גופן/גודל גופן לא משפיעים על ייצוא
                                          // Word — מוסתרים כשהיעד Word.
                                          if (_destination !=
                                              _PrintDestination.word) ...[
                                            PrintingSliderRow(
                                              label: 'גודל גופן',
                                              value: fontSize,
                                              min: 10,
                                              max: 50,
                                              displayValue: fontSize
                                                  .toInt()
                                                  .toString(),
                                              onChanged: (value) {
                                                setState(() {
                                                  fontSize = value;
                                                });
                                              },
                                              onChangeEnd: (value) {
                                                fontSize = value;
                                                setState(_refreshPreview);
                                              },
                                            ),
                                            PrintingDropdownRow(
                                              label: 'גופן',
                                              child: AppDropdownField<String>(
                                                value: fontName,
                                                enableSearch: true,
                                                decoration:
                                                    const InputDecoration(
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
                                                    _refreshPreview();
                                                  });
                                                },
                                              ),
                                            ),
                                          ],
                                          PrintingSwitchRow(
                                            label: 'הדפסה עם ניקוד',
                                            value: !_removeNikud,
                                            onChanged: (value) {
                                              setState(() {
                                                _removeNikud = !value;
                                                _refreshPreview();
                                              });
                                            },
                                          ),
                                          PrintingSwitchRow(
                                            label: 'הדפסה עם טעמים',
                                            value: !_removeTaamim,
                                            onChanged: (value) {
                                              setState(() {
                                                _removeTaamim = !value;
                                                _refreshPreview();
                                              });
                                            },
                                          ),
                                        ],
                                      ),

                                      // הגדרות עמוד
                                      PrintingSectionCard(
                                        title: 'הגדרות עמוד',
                                        icon: FluentIcons.document_24_regular,
                                        children: [
                                          PrintingSliderRow(
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
                                              setState(_refreshPreview);
                                            },
                                          ),
                                          PrintingDropdownRow(
                                            label: 'גודל עמוד',
                                            child:
                                                AppDropdownField<PdfPageFormat>(
                                                  value: format,
                                                  entries: formats.entries
                                                      .map(
                                                        (entry) => AppMenuEntry(
                                                          value: entry.key,
                                                          label: entry.value,
                                                        ),
                                                      )
                                                      .toList(),
                                                  onSelected:
                                                      (PdfPageFormat? value) {
                                                        if (value == null) {
                                                          return;
                                                        }
                                                        setState(() {
                                                          format = value;
                                                          _refreshPreview();
                                                        });
                                                      },
                                                ),
                                          ),
                                          PrintingOrientationDropdownRow(
                                            value: orientation,
                                            onChanged: (value) {
                                              setState(() {
                                                orientation = value;
                                                _refreshPreview();
                                              });
                                            },
                                          ),
                                          // N-up לא רלוונטי לייצוא Word.
                                          if (_destination !=
                                              _PrintDestination.word)
                                            PrintingPagesPerSheetDropdownRow(
                                              value: _pagesPerSheet,
                                              onChanged: (value) {
                                                setState(() {
                                                  _pagesPerSheet = value;
                                                  _refreshPreview();
                                                });
                                              },
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              _buildPrintExportFooter(context),
                            ],
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

  /// שורת הפעולות (ייצא/הדפסה) בתחתית פאנל ההגדרות — קבועה מחוץ לאזור הגלילה.
  Widget _buildPrintExportFooter(BuildContext context) {
    final isPrint = _destination == _PrintDestination.printer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: ActionButton.neutral(
              text: 'ביטול',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ActionButton.recommended(
              text: isPrint ? 'הדפסה' : 'שמירה',
              icon: isPrint
                  ? FluentIcons.print_24_regular
                  : FluentIcons.save_24_regular,
              onPressed: () => _performDestinationAction(context),
            ),
          ),
        ],
      ),
    );
  }

  /// כרטיס בחירת יעד ההדפסה — בראש הפאנל. הכפתור התחתון והפאנל מתעדכנים לפיו.
  Widget _buildDestinationCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrintingSectionCard(
          title: 'שמור לקובץ או הדפס',
          icon: FluentIcons.print_24_regular,
          children: [
            Padding(
              padding: kPrintingRowPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'בחר יעד הדפסה',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AppDropdownField<_PrintDestination>(
                    value: _destination,
                    entries: [
                      const AppMenuEntry(
                        value: _PrintDestination.printer,
                        label: 'הדפס',
                      ),
                      const AppMenuEntry(
                        value: _PrintDestination.pdf,
                        label: 'שמור ל-PDF',
                      ),
                      if (_supportsWord)
                        const AppMenuEntry(
                          value: _PrintDestination.word,
                          label: 'שמור ל-Word',
                        ),
                    ],
                    onSelected: (value) {
                      if (value != null) _setDestination(value);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// תצוגה מקדימה של עמודי ההדפסה כתמונות מרוסטרות. נמנעת משימוש ב-PdfViewer
  /// כדי שלא להעסיק את ה-worker היחיד של pdfrx בזמן רסטור.
  Widget _buildImagePreview(ColorScheme colorScheme) {
    // פריסת ה-N-up: מספר עמודי-מקור בכל גיליון.
    final (rows, cols) = switch (_pagesPerSheet) {
      2 => (1, 2),
      4 => (2, 2),
      _ => (1, 1),
    };
    final cells = rows * cols;

    return ClipRRect(
      borderRadius: AppTokens.borderRadiusAll,
      child:
          ValueListenableBuilder<
            ({
              List<Uint8List> pages,
              bool busy,
              bool failed,
              bool truncated,
            })
          >(
            valueListenable: _preview,
            builder: (context, state, _) {
              if (state.failed) {
                return Center(
                  child: Icon(
                    FluentIcons.error_circle_24_regular,
                    color: colorScheme.error,
                    size: 48,
                  ),
                );
              }

              final images = state.pages;

              // אין עדיין תמונות — מציגים אינדיקטור טעינה (גם בזמן busy וגם בריק).
              if (images.isEmpty) {
                if (state.busy) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          'מכין תצוגה מקדימה...',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }
                return Center(
                  child: Text(
                    'אין תצוגה מקדימה',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                );
              }

              final sheetCount = cells <= 1
                  ? images.length
                  : (images.length + cells - 1) ~/ cells;
              // פריט אחרון נוסף לבאנר "טווח חלקי" / אינדיקטור טעינה מתמשך.
              final footerCount = (state.busy || state.truncated) ? 1 : 0;
              final itemCount = sheetCount + footerCount;

              final list = ScrollablePositionedListScrollbar(
                scrollController: _itemScrollController,
                itemPositionsListener: _itemPositionsListener,
                itemCount: itemCount,
                child: ScrollablePositionedList.separated(
                  itemScrollController: _itemScrollController,
                  itemPositionsListener: _itemPositionsListener,
                  padding: const EdgeInsets.all(16),
                  itemCount: itemCount,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    if (index >= sheetCount) {
                      return _previewFooter(
                        state.busy,
                        state.truncated,
                        images.length,
                        colorScheme,
                      );
                    }
                    return Center(
                      child: _buildSheet(
                        index,
                        images,
                        rows,
                        cols,
                        colorScheme,
                      ),
                    );
                  },
                ),
              );

              return Row(
                children: [
                  // חלונית הניווט נפתחת/נסגרת ברוחב מונפש.
                  AnimatedSize(
                    duration: AppTokens.animNormal,
                    curve: Curves.easeInOut,
                    child: _showThumbnails
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildThumbnailsPane(
                                images,
                                rows,
                                cols,
                                colorScheme,
                              ),
                              VerticalDivider(
                                width: 1,
                                color: colorScheme.outlineVariant,
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  Expanded(child: list),
                ],
              );
            },
          ),
    );
  }

  /// פקדי ניווט בסרגל העליון: כפתור "ניווט" (מחליף תצוגה מוקטנת) ובורר "עמוד".
  /// reactive ל-[_preview] — מוצג רק כשיש יותר מגיליון אחד והטעינה הסתיימה.
  Widget _buildTopBarNav() {
    return ValueListenableBuilder<
      ({
        List<Uint8List> pages,
        bool busy,
        bool failed,
        bool truncated,
      })
    >(
      valueListenable: _preview,
      builder: (context, state, _) {
        final cells = switch (_pagesPerSheet) {
          2 => 2,
          4 => 4,
          _ => 1,
        };
        final pageCount = state.pages.length;
        final sheetCount = cells <= 1
            ? pageCount
            : (pageCount + cells - 1) ~/ cells;
        final hasNav = !state.busy && sheetCount > 1;
        if (!hasNav) return const SizedBox.shrink();
        final currentSheet = _currentPreviewItem.clamp(
          0,
          sheetCount > 0 ? sheetCount - 1 : 0,
        );
        final colorScheme = Theme.of(context).colorScheme;

        void toggleThumbnails() =>
            setState(() => _showThumbnails = !_showThumbnails);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _showThumbnails
                ? ActionButton.recommended(
                    text: 'ניווט',
                    icon: FluentIcons.navigation_24_regular,
                    onPressed: toggleThumbnails,
                  )
                : ActionButton.neutral(
                    text: 'ניווט',
                    icon: FluentIcons.navigation_24_regular,
                    onPressed: toggleThumbnails,
                  ),
            const SizedBox(width: 12),
            Text(
              'עמוד',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 96,
              child: AppDropdownField<int>(
                value: currentSheet + 1,
                enableSearch: true,
                entries: List.generate(
                  sheetCount,
                  (i) => AppMenuEntry(value: i + 1, label: '${i + 1}'),
                ),
                onSelected: (value) {
                  if (value == null || !_itemScrollController.isAttached) {
                    return;
                  }
                  _itemScrollController.scrollTo(
                    index: value - 1,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// חלונית תצוגות מוקטנות של הגיליונות כפי שיודפסו (כולל פריסת N-up); לחיצה
  /// מנווטת לגיליון.
  Widget _buildThumbnailsPane(
    List<Uint8List> images,
    int rows,
    int cols,
    ColorScheme colorScheme,
  ) {
    final cells = rows * cols;
    final sheetCount = cells <= 1
        ? images.length
        : (images.length + cells - 1) ~/ cells;
    return SizedBox(
      width: 132,
      child: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: sheetCount,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final selected = i == _currentPreviewItem;
          return GestureDetector(
            onTap: () {
              if (!_itemScrollController.isAttached) return;
              _itemScrollController.scrollTo(
                index: i,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: _buildSheet(i, images, rows, cols, colorScheme),
                ),
                Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// שורת תחתית בתצוגה: אינדיקטור טעינה מתמשך, או הודעה שהטווח נחתך.
  Widget _previewFooter(
    bool busy,
    bool truncated,
    int shown,
    ColorScheme colorScheme,
  ) {
    if (busy) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        'התצוגה המקדימה מוגבלת ל-$shown עמודים. ההדפסה/הייצוא יכללו את כל הטווח.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  /// עוטף תוכן גיליון ברקע לבן + צל.
  Widget _decoratedSheet(Widget child, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.2),
            blurRadius: 8,
          ),
        ],
      ),
      child: child,
    );
  }

  /// בונה את הגיליון מספר [sheetIndex] כפי שיודפס בפועל — עמוד יחיד, או פריסת
  /// [rows]x[cols] של N-up ביישור לימין (RTL), תואם ל-_rasterizeNUp.
  /// משותף לתצוגה הראשית ולחלונית התצוגות המוקטנות.
  Widget _buildSheet(
    int sheetIndex,
    List<Uint8List> images,
    int rows,
    int cols,
    ColorScheme colorScheme,
  ) {
    final cells = rows * cols;
    if (cells <= 1) {
      return _decoratedSheet(
        Image.memory(
          images[sheetIndex],
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
        colorScheme,
      );
    }
    final start = sheetIndex * cells;
    final chunk = images.sublist(start, min(start + cells, images.length));
    final sheetFormat = _effectivePageFormat(format);
    return _decoratedSheet(
      AspectRatio(
        aspectRatio: sheetFormat.width / sheetFormat.height,
        child: Column(
          children: List.generate(rows, (row) {
            return Expanded(
              child: Row(
                children: List.generate(cols, (col) {
                  final idx = row * cols + col;
                  if (idx >= chunk.length) {
                    return const Expanded(child: SizedBox());
                  }
                  return Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Image.memory(
                        chunk[idx],
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ),
      ),
      colorScheme,
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

/// יעד הפעולה מהפאנל: הדפסה למדפסת, שמירה ל-PDF או שמירה ל-Word.
/// הסדר קבוע — האינדקס נשמר ב-Settings.
enum _PrintDestination { pdf, word, printer }
