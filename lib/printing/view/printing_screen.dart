import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals, visibleForTesting;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/printing/commentary_print_builder.dart';
import 'package:otzaria/divine_names/utils/divine_name_markers.dart';
import 'package:otzaria/printing/serial_latest_runner.dart';
import 'package:otzaria/printing/printing_helpers.dart';
import 'package:otzaria/printing/pdf_sheet_composer.dart';
import 'package:otzaria/printing/print_pdf_source.dart';
import 'package:otzaria/printing/print_preview_controller.dart';
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:otzaria/printing/shaped_text/pdf_shaped_font.dart';
import 'package:otzaria/printing/shaped_text/shaper_font_scope.dart';
import 'package:otzaria/printing/shaped_text/shaped_text_layout.dart';
import 'package:otzaria/printing/shaped_text/shaped_text_widget.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/divine_names/repository/divine_names_repository.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/printing/commentary_print_limit.dart';
import 'package:otzaria/printing/safer_print_service.dart';
import 'package:otzaria/printing/view/slow_preview_hint.dart';
import 'package:otzaria/printing/word_export_service.dart';
import 'package:otzaria/utils/file/save_file_with_extension.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/lists/filter_chips_widget.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:positioned_sliver_list/positioned_list.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/printing/view/widgets/printing_widgets.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';

enum _AnchorKind { header, altHeader, line }

/// פריסת מסך ההדפסה: התצוגה המקדימה, ולצידה חלונית ההגדרות ברוחב קבוע עם
/// שורת הפעולות. במסך צר החלונית היא החצי התחתון, כדי שהתצוגה לא תתכווץ.
class _PrintLayout extends StatelessWidget {
  const _PrintLayout({
    required this.narrow,
    required this.preview,
    required this.settings,
    required this.footer,
  });

  final bool narrow;
  final Widget preview;
  final List<Widget> settings;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final pane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: settings,
            ),
          ),
        ),
        footer,
      ],
    );
    return Flex(
      direction: narrow ? Axis.vertical : Axis.horizontal,
      children: [
        Expanded(flex: narrow ? 5 : 1, child: preview),
        narrow
            ? Expanded(flex: 6, child: pane)
            : SizedBox(width: 320, child: pane),
      ],
    );
  }
}

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

  /// קובץ קיים נפתח ישירות; בתים מלאים נקראים רק כשיעד הפלט דורש אותם.
  final String? pdfFilePath;
  final String bookId;
  final TextBook? book;
  final List<Link> links;
  final List<String> activeCommentators;

  /// כשמסופק, מאפשר בחירת מפרשים במסך בלי לשנות את בחירת הקורא.
  final List<String>? availableCommentators;

  /// כולל את המפרשים מיד כשמסלול צילום מוגבל עובר להדפסת שורות מקור.
  final bool initialIncludeCommentaries;
  final bool removeNikud;
  final bool removeTaamim;

  /// פרופיל גוף הספר בערוץ הייצוא. מתגי הניקוד והטעמים במסך גוברים עליו.
  final TextDisplayProfile? displayProfile;

  /// פרופיל המפרשים בערוץ הייצוא, כולל עקיפות הספר והכרטיסייה.
  final TextDisplayProfile? commentaryDisplayProfile;
  final int startLine;

  /// סוף טווח ההדפסה ההתחלתי (בלעדי). כשמסופק — הטווח [startLine]..[endLine]
  /// מסומן מראש (למשל מ-`reader.printRange` של תוסף), במקום הכותרת שסביב
  /// השורה הנראית.
  final int? endLine;
  final List<TocEntry> tableOfContents;
  final int? initialPage;
  final bool isBookView;
  final List<PdfOutlineNode> pdfOutline;

  /// בלוקים מוכנים מראש להדפסה (למשל מכרטיסיית המפרשים). כשמסופק — מסך ההדפסה
  /// מדפיס אותם ישירות, ללא בחירת טווח שורות/כותרות והכללת מפרשים.
  final List<PrintBlock>? prebuiltBlocks;

  /// כותרת המסמך (שם הספר) כשמשתמשים ב-[prebuiltBlocks].
  final String? documentTitle;

  /// הגבלת המו"ל על התוכן. null — נקבעת לפי [book], אם סופק.
  final BookProtection? protection;
  const PrintingScreen({
    super.key,
    required this.data,
    this.createPdfOverride,
    this.pdfFilePath,
    required this.bookId,
    this.book,
    this.links = const [],
    this.activeCommentators = const [],
    this.availableCommentators,
    this.initialIncludeCommentaries = false,
    this.startLine = 0,
    this.endLine,
    this.removeNikud = false,
    this.removeTaamim = false,
    this.displayProfile,
    this.commentaryDisplayProfile,
    this.tableOfContents = const [],
    this.initialPage,
    this.isBookView = false,
    this.pdfOutline = const [],
    this.prebuiltBlocks,
    this.documentTitle,
    this.protection,
  }) : assert(createPdfOverride == null || pdfFilePath == null);

  /// בבדיקות: מקבל את בלוקי הטקסט שנבנו לטווח ההדפסה.
  @visibleForTesting
  static void Function(List<Map<String, String>> blocks)? debugOnPrintBlocks;

  /// Completes after currently queued native printing work, including disposal.
  /// Widget tests must unmount their screens before awaiting this barrier.
  @visibleForTesting
  static Future<void> get debugRasterIdle =>
      _PrintingScreenState._rasterLock ?? Future<void>.value();

  @override
  State<PrintingScreen> createState() => _PrintingScreenState();
}

class _PrintingScreenState extends State<PrintingScreen> {
  bool get _isPdfSource =>
      widget.pdfFilePath != null || widget.createPdfOverride != null;

  /// מתחת לרוחב הזה פאנל ההגדרות עובר מתחת לתצוגה המקדימה.
  bool _isNarrowLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width < _narrowLayoutBelow;

  static const double _narrowLayoutBelow = 760;

  double fontSize = 15.0;
  String fontName =
      AppFonts.fontPaths.keys.first; // ברירת מחדל - הגופן הראשון ברשימה
  late int startLine;
  late int endLine;
  late final _preview = PrintPreviewController(
    serialize: (action) => _withRasterLock(action),
  );

  /// controller ל-ScrollablePositionedList של התצוגה — מאפשר גם scrollbar
  /// (דרך [ScrollablePositionedListScrollbar]) וגם קפיצה לעמוד לפי אינדקס.
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final ItemPositionsListener _thumbnailPositionsListener =
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
  static Future<void>? _rasterLock;
  // הסדרת התצוגות המקדימות: render כבד אחד בכל רגע, ודילוג על render שהתיישן
  // בזמן ההמתנה בתור, כדי ששינויי פרמטרים עוקבים לא יריצו במקביל מספר יצירות
  // base PDF / רסטור ניקוד / isolate שמציפים את המעבד.
  final SerialLatestRunner<bool> _previewRunner = SerialLatestRunner<bool>();
  Map<int, String> _pageLabels = {};

  String _labelForPage(int pageNumber) =>
      labelForPdfPage(_pageLabels, pageNumber);

  bool _includeCommentaries = false;
  late List<String> _selectedCommentators;
  bool _includePersonalNotes = false;

  final Map<String, String> _commentaryContentCache = {};
  List<PersonalNote>? _personalNotesCache;
  bool _isLoadingNotes = false;

  /// עבודת הדפסה בתהליך: ציור והעברה למדפסת יכולים לקחת דקות.
  String? _printProgress;
  bool get _isPrinting => _printProgress != null;
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

  // שמות הקודש להדפסה הזו בלבד — ברירת המחדל מפרופיל ערוץ הייצוא.
  late HolyNameDisplay _holyName;
  late DivineNamesDisplay _divineNamesDisplay;
  DivineNameSpans _divineNames = DivineNameSpans.empty;
  BookNotes _bookNotes = BookNotes.empty;

  // הפלט נבנה רק אחרי הטעינה — אחרת הדפסה מהירה יוצאת בלי ההחלפה וההערות.
  late final Future<void> _divineNamesReady;

  // יעד ההדפסה הנבחר (הדפסה/PDF/Word) — נשמר כעדיפות לפעמים הבאות.
  static const _destinationKey = 'key-print-destination';
  late _PrintDestination _destination;

  bool get _supportsWord =>
      !_isPdfSource && _exportProtection.allowsEditableExport;

  bool get _supportsPdf => _exportProtection.allowsPdfExport;

  BookProtection _mainProtection = BookProtection.none;
  Map<String, BookProtection> _commentatorProtection = const {};
  late final Future<void> _protectionReady;

  /// ההגבלה המחמירה מבין הספר והמפרשים שנכללים בפלט — קובעת את יעדי השמירה.
  BookProtection get _exportProtection {
    var result = _mainProtection;
    if (widget.prebuiltBlocks == null && _includeCommentaries) {
      for (final title in _selectedCommentators) {
        result = result.strictest(
          _commentatorProtection[title] ?? BookProtection.none,
        );
      }
    }
    return result;
  }

  /// סוף הטווח (בלעדי) אחרי מגבלת ההדפסה של הספר עצמו; מפרש מוגבל נחתך
  /// בנפרד, בקטעים שלו.
  int _limitPrintEnd(int start, int end) =>
      _mainProtection.limitPrintEnd(start, end);

  /// מגבלת ההדפסה של מפרש שנכלל, ב-[_buildPrintBlocks].
  int? _commentatorPrintLimit(String title) =>
      _commentatorProtection[title]?.maxPrintSegments;

  bool get _anyIncludedCommentatorLimited =>
      widget.prebuiltBlocks == null &&
      _includeCommentaries &&
      _selectedCommentators.any((t) => _commentatorPrintLimit(t) != null);

  Future<void> _loadProtection() async {
    final repository = BookProtectionRepository.instance;
    final book = widget.book;
    final main =
        widget.protection ??
        (book == null ? BookProtection.none : await repository.forBook(book));
    final commentators = <String, BookProtection>{};
    if (widget.prebuiltBlocks == null) {
      final seen = <String>{};
      for (final link in widget.links) {
        if (!seen.add(link.targetIdentityKey)) continue;
        final title = getTitleFromPath(link.path2);
        commentators[title] = (commentators[title] ?? BookProtection.none)
            .strictest(await repository.forLink(link));
      }
    }
    if (!mounted) return;
    setState(() {
      _mainProtection = main;
      _commentatorProtection = commentators;
      _syncDestinationWithProtection();
    });
    if (!_isPdfSource && widget.prebuiltBlocks == null) {
      await _applyCurrentRange();
      if (mounted) _refreshPreview();
    }
  }

  /// מחזיר את היעד ליעד מותר כשיעד נחסם (למשל בהכללת מפרש מוגבל).
  void _syncDestinationWithProtection() {
    if (_destination == _PrintDestination.word && !_supportsWord) {
      _destination = _supportsPdf
          ? _PrintDestination.pdf
          : _PrintDestination.printer;
    }
    if (_destination == _PrintDestination.pdf && !_supportsPdf) {
      _destination = _PrintDestination.printer;
    }
  }

  void _setDestination(_PrintDestination value) {
    setState(() => _destination = value);
    Settings.setValue<int>(_destinationKey, value.index);
  }

  @override
  void initState() {
    super.initState();
    _selectedCommentators = List.of(widget.activeCommentators);
    _includeCommentaries = widget.initialIncludeCommentaries;
    _dataFuture = widget.data;
    startLine = widget.startLine;
    endLine = startLine;
    _itemPositionsListener.itemPositions.addListener(_onPreviewScroll);
    _thumbnailPositionsListener.itemPositions.addListener(_onThumbnailScroll);

    // יעד ההדפסה השמור — נופל ל-Word ל-PDF כשלא נתמך במצב הנוכחי.
    final savedDestination = Settings.getValue<int>(_destinationKey);
    _destination =
        _PrintDestination.values[(savedDestination ??
                _PrintDestination.printer.index)
            .clamp(0, _PrintDestination.values.length - 1)];
    if (_destination == _PrintDestination.word && !_supportsWord) {
      _destination = _PrintDestination.pdf;
    }
    _protectionReady = _loadProtection();

    // אתחול הגדרות ניקוד וטעמים לפי תצוגת הספר
    final profile =
        widget.displayProfile ??
        (widget.prebuiltBlocks != null
            ? widget.commentaryDisplayProfile
            : null);
    _removeNikud = profile?.removeNikud ?? widget.removeNikud;
    _removeTaamim = profile?.removeTeamim ?? widget.removeTaamim;
    final exportProfile = _exportProfile;
    _holyName = exportProfile.holyName;
    _divineNamesDisplay = exportProfile.divineNames;
    _divineNamesReady = Future.wait([_loadDivineNames(), _loadBookNotes()]);
    // כשל (למשל בהערות) מכשיל את יצירת המסמך שממתינה לו, לא כשגיאה לא-מטופלת.
    _divineNamesReady.then<void>((_) {}, onError: (Object _) {});

    // במצב PDF חיצוני (כמו "צורת הדף") אין טווח שורות/כותרות.
    if (_isPdfSource) {
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
    if (widget.endLine != null) {
      // טווח מפורש: עוגני שורות עד שידוע אורך הספר, ואז כותרות כשהן תואמות
      // בדיוק (_resolveRequestedRange).
      _startAnchor = _RangeAnchor(_AnchorKind.line, widget.startLine);
      _endAnchor = _RangeAnchor(
        _AnchorKind.line,
        max(widget.startLine, widget.endLine! - 1),
      );
    } else if (_flatHeaders.isNotEmpty) {
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
    if (oldWidget.activeCommentators != widget.activeCommentators) {
      _selectedCommentators = List.of(widget.activeCommentators);
    }
    if (oldWidget.pdfFilePath != widget.pdfFilePath ||
        oldWidget.createPdfOverride != widget.createPdfOverride ||
        (!_isPdfSource && oldWidget.data != widget.data) ||
        oldWidget.prebuiltBlocks != widget.prebuiltBlocks) {
      _dataFuture = widget.data;
      _cachedBasePdf = null;
      _cachedBaseKey = null;
      _anchorEntries = null;
      _totalPdfPages = 0;
      if (_isPdfSource) {
        _pdfStartPage = widget.initialPage ?? 1;
        _pdfEndPage = widget.initialPage == null
            ? 0
            : widget.initialPage! + (widget.isBookView ? 1 : 0);
        _refreshPreview(immediate: true);
      } else {
        _renderGeneration++;
        _preview.reset(pagesPerSheet: _pagesPerSheet);
        _initPreviewRange();
      }
    }
  }

  /// ממיר את הטווח המפורש ([PrintingScreen.endLine]) לעוגני כותרות כשהוא
  /// מתחיל ומסתיים בדיוק בגבולות כותרות — כך שבחירת הטווח במסך נראית כמו
  /// בחירה ידנית. אחרת נשארים עוגני השורות.
  bool _requestedRangeResolved = false;

  Future<void> _resolveRequestedRange() async {
    final endLine = widget.endLine;
    if (endLine == null || _requestedRangeResolved || _flatHeaders.isEmpty) {
      return;
    }
    _requestedRangeResolved = true;
    final totalLines = await _totalLineCount();
    final match = matchHeaderRange(
      _flatHeaders,
      widget.startLine,
      endLine,
      totalLines,
    );
    if (match.start != null) {
      _startAnchor = _RangeAnchor(_AnchorKind.header, match.start!);
    }
    if (match.end != null) {
      _endAnchor = _RangeAnchor(_AnchorKind.header, match.end!);
    }
  }

  Future<void> _initPreviewRange() async {
    await _resolveRequestedRange();
    await _applyCurrentRange();
    if (mounted) {
      setState(() {});
    }
    _renderPreview();
  }

  final _lineCounts = LineCountCache();

  Future<int> _totalLineCount() async => _lineCounts.of(await _dataFuture);

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
    endLine = _limitPrintEnd(startLine, e.clamp(startLine, totalLines));
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

  /// שורת הסיום (בלעדית) של עוגן: כותרת → סוף הסעיף שלה, כולל תתי-הכותרות;
  /// שורה → השורה שאחריה, כך שהשורה הנבחרת נכללת.
  int? _anchorEndLine(_RangeAnchor? anchor, int totalLines) {
    if (anchor == null) return null;
    switch (anchor.kind) {
      case _AnchorKind.header:
        if (_flatHeaders.isEmpty) return null;
        final i = anchor.index.clamp(0, _flatHeaders.length - 1);
        return headerSectionEndLine(_flatHeaders, i, totalLines);
      case _AnchorKind.altHeader:
        if (_flatAltHeaders.isEmpty) return null;
        final i = anchor.index.clamp(0, _flatAltHeaders.length - 1);
        return headerSectionEndLine(_flatAltHeaders, i, totalLines);
      case _AnchorKind.line:
        return anchor.index + 1;
    }
  }

  Future<void> _loadAltHeaders() async {
    final book = widget.book;
    if (_isPdfSource || book == null) return;
    try {
      final structures = await DatabaseLibraryProvider.instance
          .getAlternativeStructuresForBook(book);
      if (structures.isEmpty || !mounted) return;

      // שימוש ב-structure הראשון בלבד - ריבוי structures מערבב ערכים
      final rows = await DatabaseLibraryProvider.instance
          .getAltTocEntriesWithLineIndex(
            structures.first.id,
            source: structures.first.source,
          );
      if (!mounted) return;

      final altEntries = buildAltHeaderEntries(rows);
      if (altEntries.isEmpty) return;

      final lastAlt = findLastHeaderIndexAtOrBefore(
        altEntries,
        widget.startLine,
      );
      setState(() {
        _flatAltHeaders = altEntries;
        _anchorEntries = null; // נבנה מחדש עם כותרות המשנה
        // בלי ניווט רגיל — ברירת המחדל היא כותרות המשנה.
        if (_flatHeaders.isEmpty && widget.endLine == null) {
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
    _renderGeneration++;
    _previewRefreshTimer?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_onPreviewScroll);
    _thumbnailPositionsListener.itemPositions.removeListener(
      _onThumbnailScroll,
    );
    _preview.dispose();
    _cachedBasePdf = null;
    super.dispose();
  }

  Set<int> _visibleSheets(ItemPositionsListener listener) => listener
      .itemPositions
      .value
      .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
      .map((p) => p.index)
      .toSet();

  void _onPreviewScroll() {
    if (!mounted) return;
    final visible = _visibleSheets(_itemPositionsListener);
    if (visible.isEmpty) return;
    _preview.showSheets(visible);
    final minIndex = visible.reduce(min);
    if (minIndex != _currentPreviewItem) {
      setState(() => _currentPreviewItem = minIndex);
    }
  }

  void _onThumbnailScroll() {
    if (!mounted || !_showThumbnails) return;
    _preview.showSheets(
      _visibleSheets(_thumbnailPositionsListener),
      thumbnails: true,
    );
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
    if (!mounted || _preview.isStopped) return;
    _renderGeneration++;
    _preview.reset(pagesPerSheet: _pagesPerSheet);
    _previewRefreshTimer?.cancel();
    if (immediate) {
      _renderPreview();
      return;
    }
    _previewRefreshTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) _renderPreview();
    });
  }

  void _renderPreview() {
    if (!mounted || _preview.isStopped) return;
    final generation = ++_renderGeneration;
    _currentPreviewItem = 0;
    _preview.reset(pagesPerSheet: _pagesPerSheet);
    _previewRunner.run(
      isStale: () => !mounted || generation != _renderGeneration,
      task: () => _renderPreviewTask(generation),
    );
  }

  Future<bool> _renderPreviewTask(int generation) async {
    bool stale() =>
        !mounted || _preview.isStopped || generation != _renderGeneration;
    if (stale()) return false;
    try {
      final base = await _createBasePdf(format);
      if (stale()) return false;
      await _preview.load(
        base,
        startPage: _isPdfSource ? _pdfStartPage : 1,
        endPage: computePdfPrintEndPage(
          isPdfMode: _isPdfSource,
          pdfEndPage: _pdfEndPage,
          totalPdfPages: _totalPdfPages,
        ),
        isStale: stale,
        onPageCount: _updatePdfPageCount,
      );
      return !stale();
    } catch (e, st) {
      debugPrint('[PRINT] preview creation failed: $e\n$st');
      if (!stale()) _preview.reportError(e, st);
      return false;
    }
  }

  void _updatePdfPageCount(int count) {
    if (_totalPdfPages != 0 || !_isPdfSource || !mounted || count == 0) return;
    setState(() {
      _totalPdfPages = count;
      _pdfStartPage = _pdfStartPage.clamp(1, count);
      _pdfEndPage = _pdfEndPage == 0 ? count : _pdfEndPage.clamp(1, count);
    });
  }

  void _setPagesPerSheet(int value) {
    setState(() => _pagesPerSheet = value);
    _preview.setPagesPerSheet(value);
  }

  Future<Uint8List> _createOutputPdf(PdfPageFormat format) async {
    final pagesPerSheet = _pagesPerSheet;
    final sheetFormat = _effectivePageFormat(format);
    final isPdfMode = _isPdfSource;
    final startPage = isPdfMode ? _pdfStartPage : 1;
    final endPage = computePdfPrintEndPage(
      isPdfMode: isPdfMode,
      pdfEndPage: _pdfEndPage,
      totalPdfPages: _totalPdfPages,
    );
    final hasPageRange = hasPdfPageRange(
      startPage: startPage,
      endPage: endPage,
      totalPages: _totalPdfPages,
    );

    final base = await _createBasePdf(format);
    if (pagesPerSheet <= 1 && !hasPageRange) {
      return base.readBytes();
    }

    try {
      return await _createNUpPdf(
        base,
        sheetFormat: sheetFormat,
        pagesPerSheet: pagesPerSheet,
        startPage: startPage,
        endPage: endPage,
      );
    } catch (e, st) {
      debugPrint('[PRINT] N-up failed: $e\n$st');
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
  /// הרסטור (_pagesPerSheet, טווח עמודים ב-PDF חיצוני) בכוונה אינם נכללים.
  String _baseCacheKey(PdfPageFormat format) {
    if (_isPdfSource) {
      return 'override|${identityHashCode(widget.createPdfOverride)}|${orientation.name}|${format.width}x${format.height}';
    }
    final holyNames = _shouldReplaceHolyNames;
    return [
      identityHashCode(_dataFuture),
      identityHashCode(widget.prebuiltBlocks),
      orientation.name,
      format.width,
      format.height,
      pageMargin,
      fontSize,
      fontName,
      _removeNikud,
      _removeTaamim,
      holyNames,
      _holyNameStyle.storageKey,
      _divineNamesDisplay.name,
      identityHashCode(_divineNames),
      identityHashCode(_bookNotes),
      startLine,
      endLine,
      _includeCommentaries,
      (List.of(_selectedCommentators)..sort()).join("\u0000"),
      _includePersonalNotes,
      _mainProtection.effectiveLevel,
      identityHashCode(_commentatorProtection),
    ].join('|');
  }

  Future<PrintPdfSource> _createBasePdf(PdfPageFormat format) async {
    final path = widget.pdfFilePath;
    if (path != null) return PrintPdfSource.file(path);
    await _divineNamesReady;
    final key = _baseCacheKey(format);
    final cached = _cachedBasePdf;
    if (cached != null && _cachedBaseKey == key) {
      return PrintPdfSource.data(cached);
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
    if (mounted && !_preview.isStopped && _baseCacheKey(format) == key) {
      _cachedBasePdf = bytes;
      _cachedBaseKey = key;
    }
    return PrintPdfSource.data(bytes);
  }

  Future<Uint8List> _createNUpPdf(
    PrintPdfSource sourcePdf, {
    required PdfPageFormat sheetFormat,
    required int pagesPerSheet,
    int startPage = 1,
    int? endPage,
  }) async {
    // הסדרה של כל פעולות ה-pdfrx: שני openData במקביל תוקעים את ה-worker היחיד.
    return _withRasterLock(
      () => _composeNUp(
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
      if (previousLock != null) {
        await previousLock;
      }
      return await action();
    } finally {
      // A drained queue must not retain the completed future or its old Zone.
      // A newer tail still owns the queue when another operation is waiting.
      if (identical(_rasterLock, completer.future)) {
        _rasterLock = null;
      }
      completer.complete();
    }
  }

  Future<Uint8List> _composeNUp(
    PrintPdfSource sourcePdf, {
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
    if (rows == 1 && cols == 1 && !hasRange) return sourcePdf.readBytes();

    final doc = await sourcePdf.open();
    try {
      final pageCount = doc.pages.length;
      if (_totalPdfPages == 0 && _isPdfSource && mounted) {
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
      return await composePdfSheets(
        doc,
        firstIndex: firstIdx,
        lastIndex: lastIdx,
        rows: rows,
        cols: cols,
        sheetWidth: sheetFormat.width,
        sheetHeight: sheetFormat.height,
      );
    } finally {
      // Native cleanup must finish before the next serialized operation opens.
      await doc.dispose();
    }
  }

  Future<Uint8List> createPdf(PdfPageFormat format) async {
    if (widget.prebuiltBlocks != null) {
      return _createPrebuiltPdf(format);
    }
    String dataString = await _dataFuture;
    if (orientation == pw.PageOrientation.landscape) {
      format = format.landscape;
    }

    final shouldReplaceHolyNames = _shouldReplaceHolyNames;

    // הטרנספורמציות היקרות מוחלות פר-שורה רק על הטווח הנבחר ב-_buildPrintBlocks.
    final totalLines = _lineCounts.of(dataString);
    final pageMargin = this.pageMargin;
    final fontSize = this.fontSize;

    final bookName = stripHtmlIfNeeded(
      _applyTextTransforms(
        _withStoredLineData(linesInRange(dataString, 0, 1).first, 0),
      ),
    );
    final selectedStart = startLine.clamp(0, totalLines);
    final selectedEnd = _limitPrintEnd(
      selectedStart,
      endLine.clamp(selectedStart, totalLines),
    );

    final personalNotes = _includePersonalNotes
        ? await _getPersonalNotesForBook(widget.bookId)
        : const <PersonalNote>[];

    final blocks = await _buildPrintBlocks(
      rangeLines: linesInRange(dataString, selectedStart, selectedEnd),
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

  late final TextDisplayProfile _exportProfile =
      widget.displayProfile ??
      SettingsRepository().loadTextDisplayPolicy().resolve(
        const TextDisplaySlot(
          target: TextTarget.body,
          view: TextView.regular,
          channel: TextChannel.export,
        ),
      );

  late final TextDisplayProfile _commentaryExportProfile =
      widget.commentaryDisplayProfile ??
      SettingsRepository().loadTextDisplayPolicy().resolve(
        TextDisplaySlot.commentaryDisplay.copyWith(channel: TextChannel.export),
      );

  HolyNameStyle get _holyNameStyle => _holyName.style ?? HolyNameStyle.kufKuf;

  bool get _shouldReplaceHolyNames => _holyName != HolyNameDisplay.asIs;

  bool get _substituteDivineNames =>
      _divineNamesDisplay == DivineNamesDisplay.substitute;

  /// מופעי השמות של הספר (מהמסד), לבורר "שאר שמות הקודש".
  Future<void> _loadDivineNames() async {
    final book = widget.book;
    if (book == null || _isPdfSource) return;
    final spans = await DivineNamesRepository.instance.spansFor(
      book.title,
      categoryId: book.categoryId,
      source: book.source,
      fileType: book.fileType,
      versionTitle: book.versionTitle,
    );
    if (!mounted || spans.isEmpty) return;
    setState(() => _divineNames = spans);
  }

  /// הערות השוליים של הספר מהמסד, שמוחזרות לשורה בהדפסה.
  Future<void> _loadBookNotes() async {
    final book = widget.book;
    if (book == null || _isPdfSource) return;
    final notes = await BookNotesRepository.instance.notesFor(
      book.title,
      categoryId: book.categoryId,
      source: book.source,
      fileType: book.fileType,
      versionTitle: book.versionTitle,
    );
    if (!mounted || notes.isEmpty) return;
    setState(() => _bookNotes = notes);
  }

  /// שורה [lineIndex] הגולמית של הספר עם מופעי השמות ועם הערות המסד — לפני
  /// כל טרנספורמציה, כי אופסטי השמות נמדדו על השורה כפי שנשמרה.
  String _withStoredLineData(String rawLine, int lineIndex) =>
      applyStoredLineData(
        rawLine,
        lineIndex,
        names: _divineNames,
        notes: _bookNotes,
        substituteOtherNames: _substituteDivineNames,
        holyNameStyle: _shouldReplaceHolyNames ? _holyNameStyle : null,
      );

  /// מחיל את פרופיל הייצוא; מתגי הניקוד, הטעמים ושם הוי"ה שבמסך גוברים עליו.
  String _applyTextTransforms(String input, {bool commentary = false}) {
    final profile = _screenProfile(commentary: commentary);
    return applyTextDisplayProfile(
      resolveDivineNameMarkers(
        input,
        substituteOtherNames: _substituteDivineNames,
        holyNameStyle: profile.replaceHolyNames ? profile.holyNameStyle : null,
      ),
      profile,
    );
  }

  // שם הוי"ה במפרשים נשאר לפי פרופיל המפרשים כל עוד לא שונה במסך.
  TextDisplayProfile _screenProfile({bool commentary = false}) {
    final base = commentary ? _commentaryExportProfile : _exportProfile;
    final holyNameChanged = _holyName != _exportProfile.holyName;
    return base.copyWith(
      nikud: _removeNikud ? MarkVisibility.hide : MarkVisibility.show,
      teamim: _removeTaamim ? TeamimVisibility.hide : TeamimVisibility.show,
      holyName: commentary && !holyNameChanged ? null : _holyName,
    );
  }

  /// ממיר בלוקים מוכנים לייצוג הפנימי, תוך החלת הסרת ניקוד/טעמים ושמות קודש.
  List<Map<String, String>> _mapPrebuiltBlocks(List<PrintBlock> source) {
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
            'text': stripHtmlIfNeeded(
              _applyTextTransforms(block.text, commentary: true),
            ),
          });
        case PrintBlockKind.heading:
        case PrintBlockKind.text:
          result.add({
            'kind': 'text',
            'text': stripHtmlIfNeeded(_applyTextTransforms(block.text)),
          });
      }
    }
    return result;
  }

  /// קובץ הגופן [family]: נכס מובנה, או קובץ גופן המחשב שאותר בסריקה.
  /// גופן מחשב שלא נמצא או לא נקרא — נופלים לגופן המובנה הראשון.
  Future<Uint8List> _loadPrintFont(String family) async {
    if (!fonts.containsKey(family)) {
      final path = AppFonts.systemFamilyFaces(family)?.regularPath;
      try {
        if (path != null) return await File(path).readAsBytes();
        debugPrint('[PRINT] system font not found: $family');
      } on FileSystemException catch (e) {
        debugPrint('[PRINT] system font unreadable: $family: $e');
      }
    }
    final asset = await rootBundle.load(fonts[family] ?? fonts.values.first);
    return asset.buffer.asUint8List();
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
    final primaryBytes = await _loadPrintFont(fontName);
    final fallbackBytes = (await rootBundle.load(
      'fonts/NotoSerifHebrew-VariableFont_wdth,wght.ttf',
    )).buffer.asUint8List();
    // pw.Font קורא רק קווי מתאר TrueType: בגופן CFF הכותרות ושולי העמוד נשארים
    // בגופן המובנה, וגוף הטקסט המעוצב — בגופן שנבחר.
    final isTrueType =
        primaryBytes.length >= 4 &&
        ByteData.sublistView(primaryBytes).getUint32(0) == 0x10000;
    final font = pw.Font.ttf(
      (isTrueType ? primaryBytes : await _loadPrintFont(fonts.keys.first))
          .buffer
          .asByteData(),
    );
    final fullBackFont = pw.Font.ttf(fallbackBytes.buffer.asByteData());

    // הגופנים נרשמים ומשתחררים ב-worker; אותם בתים משמשים גם להטמעה ב-PDF.
    return Isolate.run(
      () => withShaperFontPair(
        createPrimary: () => ShaperFont.register(primaryBytes),
        createFallback: () => ShaperFont.register(fallbackBytes),
        action: (primary, fallback) async {
          final pdfData = pw.Document(pageMode: PdfPageMode.outlines);
          final shapedFonts = [
            PdfShapedFont(
              pdfData.document,
              shaper: primary,
              fontBytes: primaryBytes,
            ),
            PdfShapedFont(
              pdfData.document,
              shaper: fallback,
              fontBytes: fallbackBytes,
            ),
          ];
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
                  margin: const pw.EdgeInsets.only(
                    top: 1.0 * PdfPageFormat.cm,
                  ),
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
                  margin: const pw.EdgeInsets.only(
                    top: 1.0 * PdfPageFormat.cm,
                  ),
                  child: pw.Text(
                    'עמוד ${context.pageNumber} מתוך ${context.pagesCount} - הודפס מתוכנת אוצריא',
                    style: pw.Theme.of(
                      context,
                    ).defaultTextStyle.copyWith(color: PdfColors.grey),
                  ),
                );
              },
              build: (pw.Context context) {
                return blocks.expand((b) {
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
                  return [
                    pw.Padding(
                      padding: padding,
                      child: ShapedText(
                        text,
                        fonts: shapedFonts,
                        fontSize: effectiveFontSize,
                        align: ShapedTextAlign.justify,
                        heightFactor: 1.35,
                      ),
                    ),
                  ];
                }).toList();
              },
            ),
          );

          return await pdfData.save();
        },
      ),
    );
  }

  Future<List<Link>> _loadLinksForPrintRange(
    int selectedStart,
    int selectedEnd,
  ) async {
    final book = widget.book;
    if (book == null) return widget.links;
    return loadPrintRangeLinks(
      book,
      startIndex: selectedStart,
      endIndex: selectedEnd,
      targetBookTitles: _selectedCommentators,
      fallback: widget.links,
    );
  }

  Future<void> _loadCommentaryProtection(Iterable<Link> links) async {
    final protections = Map<String, BookProtection>.of(_commentatorProtection);
    final seen = <String>{};
    for (final link in links) {
      if (!seen.add(link.targetIdentityKey)) continue;
      final title = getTitleFromPath(link.path2);
      protections[title] = (protections[title] ?? BookProtection.none)
          .strictest(
            await BookProtectionRepository.instance.forLink(link),
          );
    }
    if (!mounted || mapEquals(protections, _commentatorProtection)) return;
    setState(() {
      _commentatorProtection = protections;
      _syncDestinationWithProtection();
    });
  }

  Future<List<Map<String, String>>> _buildPrintBlocks({
    required List<String> rangeLines,
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
    await _loadCommentaryProtection(rangeLinks);
    final linksByLine = groupLinksBySourceLine(
      rangeLinks,
      selectedStart + 1,
      selectedEnd,
    );
    final limit = CommentaryPrintLimit();

    for (var i = selectedStart; i < selectedEnd; i++) {
      // הטרנספורמציות מוחלות רק על שורות הטווח; ב-Word ה-HTML נשמר לעיצוב.
      final rawLine = rangeLines[i - selectedStart];
      final lineText = _applyTextTransforms(_withStoredLineData(rawLine, i));
      blocks.add({
        'kind': 'text',
        'text': keepHtml ? lineText : stripHtmlIfNeeded(lineText),
      });

      final lineNumber1Based = i + 1;

      if (_includeCommentaries) {
        final linksForLine = await getLinksforIndexs(
          indexes: [i],
          links: linksByLine[lineNumber1Based] ?? const [],
          commentatorsToShow: _selectedCommentators,
        );

        // מפרש עם מגבלת הדפסה נחתך לפי הקטעים שלו לאורך כל העבודה.
        final printable = <Link>[];
        for (final link in linksForLine) {
          final selected = await limit.take(link);
          if (selected != null) printable.add(selected);
        }

        if (printable.isNotEmpty) {
          blocks.add({'kind': 'commentaryTitle', 'title': 'מפרשים'});

          // קיבוץ לפי מפרש (כמו בתצוגת PDF): כותרת לכל מפרש, ומתחתיה כל הקטעים שלו
          String? currentGroupTitle;
          for (final link in printable) {
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
              noteText = replaceHolyNames(noteText, style: _holyNameStyle);
            }
            blocks.add({'kind': 'note', 'text': noteText});
          }
        }
      }
    }

    PrintingScreen.debugOnPrintBlocks?.call(blocks);
    return blocks;
  }

  Future<PreparedPrintDocument> _prepareWordDocument() async {
    await _divineNamesReady;
    if (widget.prebuiltBlocks != null) {
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
                    commentary: block.kind == PrintBlockKind.commentary,
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
    final dataString = await _dataFuture;

    final shouldReplaceHolyNames = _shouldReplaceHolyNames;

    // שומרים את תגיות ה-HTML — WordExportService ממיר אותן לעיצוב במסמך
    final totalLines = _lineCounts.of(dataString);
    var bookName = stripHtmlIfNeeded(
      _applyTextTransforms(
        _withStoredLineData(linesInRange(dataString, 0, 1).first, 0),
      ),
    );
    if (bookName.trim().isEmpty) {
      bookName = widget.bookId;
    }

    final selectedStart = startLine.clamp(0, totalLines);
    final selectedEnd = _limitPrintEnd(
      selectedStart,
      endLine.clamp(selectedStart, totalLines),
    );
    final personalNotes = _includePersonalNotes
        ? await _getPersonalNotesForBook(widget.bookId)
        : const <PersonalNote>[];

    final legacyBlocks = _foldPersonalNoteBlocks(
      await _buildPrintBlocks(
        rangeLines: linesInRange(dataString, selectedStart, selectedEnd),
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

  /// הערה קבועה מתחת לבחירת הטווח כשהמו"ל הגביל את ההדפסה.
  Widget? _buildPrintLimitHint(ColorScheme colorScheme) {
    final mainLimit = _mainProtection.maxPrintSegments;
    final text = mainLimit != null
        ? PdfMessages.printLimitedByPublisher(mainLimit)
        : _anyIncludedCommentatorLimited
        ? PdfMessages.commentaryPrintLimitedByPublisher(
            BookProtection.printSegmentLimit,
          )
        : null;
    if (text == null) return null;
    return Padding(
      padding: kPrintingRowPadding,
      child: Text(
        text,
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
      ),
    );
  }

  /// מבצע את הפעולה לפי היעד הנבחר: הדפסה למדפסת, או שמירה ל-PDF/Word.
  Future<void> _performDestinationAction(BuildContext context) async {
    try {
      await _protectionReady;
    } catch (error) {
      debugPrint('Print protection lookup failed: $error');
    }
    if (!mounted || !context.mounted) return;
    final requested = _destination;
    if (_includeCommentaries && widget.prebuiltBlocks == null) {
      await _loadCommentaryProtection(
        await _loadLinksForPrintRange(startLine, endLine),
      );
    }
    if (!mounted || !context.mounted) return;
    setState(_syncDestinationWithProtection);
    // יעד שנחסם אחרי הבחירה — הרשימה התעדכנה, והמשתמש יבחר שוב.
    if (_destination != requested) {
      UiSnack.show(PdfMessages.exportFormatRestrictedByPublisher);
      return;
    }
    switch (_destination) {
      case _PrintDestination.printer:
        if (_isPrinting) return;
        setState(() => _printProgress = PdfMessages.printPreparing);
        var layoutFailed = false;
        final bool printed;
        try {
          printed = await printPdfWithSaferMode(
            context: context,
            name: widget.bookId,
            usePrinterSettings: true,
            onLayout: (format) async {
              try {
                return await _createOutputPdf(format);
              } catch (_) {
                layoutFailed = true;
                rethrow;
              }
            },
            format: format,
            onSpooling: (_) {
              if (mounted) {
                setState(() => _printProgress = PdfMessages.printSending);
              }
            },
          );
        } catch (e, stack) {
          if (mounted) setState(() => _printProgress = null);
          UiSnack.showError(PdfMessages.printError);
          // כשל ב-onLayout כבר דווח על ידי printing, עם החריגה המקורית.
          if (!layoutFailed) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: e,
                stack: stack,
                library: 'printing',
              ),
            );
          }
          return;
        }
        if (mounted) setState(() => _printProgress = null);
        if (printed) UiSnack.show(PdfMessages.printSent);
        if (printed && context.mounted) {
          Navigator.of(context).pop(true);
        }
      case _PrintDestination.pdf:
        if (await _saveToFile(_ExportFormat.pdf) && context.mounted) {
          Navigator.of(context).pop(true);
        }
      case _PrintDestination.word:
        if (!_supportsWord) {
          UiSnack.showError(PdfMessages.editableExportRestricted);
          return;
        }
        if (await _saveToFile(_ExportFormat.word) && context.mounted) {
          Navigator.of(context).pop(true);
        }
    }
  }

  Future<bool> _saveToFile(_ExportFormat selectedFormat) async {
    if (!await verifySaferModePassword(context)) return false;
    if (!mounted) return false;
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
      if (!mounted) return false;
      final path = await saveFileWithExtension(
        context: context,
        dialogTitle: 'ייצוא קובץ',
        fileName: '${_sanitizeFileName(widget.bookId)}.$selectedExtension',
        extension: selectedExtension,
        bytes: bytes,
      );
      if (path == null) return false;
      UiSnack.showSuccess(successMessage);
      return true;
    } on FileSystemException catch (e) {
      if (_isLockedFileException(e)) {
        UiSnack.showError(PdfMessages.fileLockedByAnotherApp);
        return false;
      }
      UiSnack.showError(PdfMessages.fileExportFailed(e.message));
      return false;
    } catch (e) {
      UiSnack.showError(PdfMessages.fileExportFailed(e));
      return false;
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
    bool keepHtml = false,
  }) async {
    // המפתח כולל את דגלי הניקוד/טעמים/שמות-קודש: אחרת החלפת "הדפסה עם ניקוד"
    // הייתה מחזירה תוכן מפרש מוטרנספרם קודם (באג: הניקוד לא התעדכן).
    final commentaryProfile = _screenProfile(commentary: true);
    final key = printCommentaryContentCacheKey(
      link,
      removeNikud: _removeNikud,
      removeTaamim: _removeTaamim,
      replaceHolyNames: commentaryProfile.replaceHolyNames,
      keepHtml: keepHtml,
      holyNameStyle: commentaryProfile.holyNameStyle,
      substituteDivineNames: _substituteDivineNames,
    );
    final cached = _commentaryContentCache[key];
    if (cached != null) return cached;

    var text = _applyTextTransforms(
      await contentWithBookNotes(link),
      commentary: true,
    );
    if (!keepHtml) {
      text = stripHtmlIfNeeded(text);
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
      final book = widget.book;
      final all = await repo.loadNotes(
        book != null ? personalNotesBookKey(book) : bookId,
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

  /// מעדכן את נקודת הקצה שנבחרה, ומיישר את הקצה השני אם הטווח התהפך או התרוקן.
  void _onAnchorSelected({
    required bool isStart,
    required _RangeAnchor anchor,
    required int totalLines,
  }) {
    if (isStart) {
      _startAnchor = anchor;
      final s = _anchorStartLine(anchor, totalLines);
      final e = _anchorEndLine(_endAnchor, totalLines);
      if (s != null && e != null && isEmptyLineRange(s, e)) {
        _endAnchor = anchor;
      }
    } else {
      _endAnchor = anchor;
      final s = _anchorStartLine(_startAnchor, totalLines);
      final e = _anchorEndLine(anchor, totalLines);
      if (s != null && e != null && isEmptyLineRange(s, e)) {
        _startAnchor = anchor;
      }
    }
    _updateRangeFromAnchors();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCustomPdfMode = _isPdfSource;
    final isPrebuiltMode = widget.prebuiltBlocks != null;

    // הקוראים פותחים עם barrierDismissible: false — לחיצה בחוץ לא סוגרת, ESC כן.
    // ה-Focus מחזיק פוקוס בדיאלוג כדי שה-DismissIntent יגיע למסגרת.
    final dialog = AnimatedBuilder(
      animation: _preview,
      builder: (context, body) {
        final sheetCount = _navigableSheetCount();
        return AppDialogFrame(
          icon: FluentIcons.print_24_regular,
          title: 'הדפסה — ${widget.book?.title ?? widget.bookId}',
          fitTitle: true,
          leading: sheetCount == null ? null : _buildTopBarNav(sheetCount),
          size: AppDialogSize.full,
          padding: EdgeInsets.zero,
          backgroundColor: AppSurfaces.panelBackground(context),
          closeEnabled: !_isPrinting,
          child: body!,
        );
      },
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder(
                future: _dataFuture,
                builder: (context, snapshot) {
                  if (isCustomPdfMode) {
                    return _PrintLayout(
                      narrow: _isNarrowLayout(context),
                      preview: _buildImagePreview(colorScheme),
                      settings: _buildCustomPdfSettings(colorScheme),
                      footer: _buildPrintExportFooter(context),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.done) {
                    final totalLines = _lineCounts.of(snapshot.data!);
                    return _PrintLayout(
                      narrow: _isNarrowLayout(context),
                      preview: _buildImagePreview(colorScheme),
                      settings: _buildTextSettings(
                        colorScheme,
                        totalLines: totalLines,
                        isPrebuiltMode: isPrebuiltMode,
                      ),
                      footer: _buildPrintExportFooter(context),
                    );
                  }

                  return const LoadingIndicator(message: 'טוען נתונים...');
                },
              ),
            ),
          ],
        ),
      ),
    );
    // המסגרת שומרת על הרשאת הסגירה; עוצרים את הרינדור מיד כשהנתיב נסגר,
    // לפני dispose שמגיע רק בסוף אנימציית הסגירה.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        _renderGeneration++;
        _previewRefreshTimer?.cancel();
        _preview.stop();
      },
      child: dialog,
    );
  }

  /// הגדרות ההדפסה של PDF מוכן: טווח עמודים והגדרות דף.
  List<Widget> _buildCustomPdfSettings(ColorScheme colorScheme) => [
    _buildDestinationCard(context),
    if (_totalPdfPages > 0) ...[
      PrintingSectionCard(
        title: 'טווח עמודים',
        icon: FluentIcons.document_page_number_24_regular,
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
                  if (_pdfEndPage < _pdfStartPage) {
                    _pdfEndPage = _pdfStartPage;
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
                _totalPdfPages - _pdfStartPage + 1,
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
              pdfPageRangeSummary(
                startPage: _pdfStartPage,
                endPage: _pdfEndPage,
                totalPages: _totalPdfPages,
                pagesPerSheet: _pagesPerSheet,
              ),
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
          child: AppDropdownField<PdfPageFormat>(
            value: format,
            entries: formats.entries
                .map(
                  (entry) => AppMenuEntry(value: entry.key, label: entry.value),
                )
                .toList(),
            onSelected: (PdfPageFormat? value) {
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
          onChanged: _setPagesPerSheet,
        ),
      ],
    ),
  ];

  /// הגדרות ההדפסה של טקסט: טווח, טקסט ועמוד.
  List<Widget> _buildTextSettings(
    ColorScheme colorScheme, {
    required int totalLines,
    required bool isPrebuiltMode,
  }) => [
    _buildDestinationCard(context),

    // כותרת טווח הדפסה — מוסתר במצב בלוקים מוכנים (מפרשים)
    if (!isPrebuiltMode) ...[
      PrintingSectionCard(
        title: 'טווח הדפסה',
        icon: FluentIcons.document_page_number_24_regular,
        children: [
          Padding(
            padding: kPrintingRowPadding,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '${(_limitPrintEnd(startLine, endLine) - startLine).clamp(0, totalLines)} שורות נבחרו מתוך $totalLines',
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
          ?_buildPrintLimitHint(colorScheme),
          PrintingSwitchRow(
            label: 'כלול מפרשים',
            value: _includeCommentaries,
            onChanged: (value) {
              setState(() {
                _includeCommentaries = value;
                _syncDestinationWithProtection();
                _refreshPreview();
              });
            },
          ),
          if (_includeCommentaries &&
              widget.availableCommentators?.isNotEmpty == true)
            FilterChipsSelector<String>(
              items: widget.availableCommentators!,
              selectedItems: _selectedCommentators,
              labelBuilder: (name) => name,
              onSelectionChanged: (selected) => setState(() {
                _selectedCommentators = List.of(selected);
                _syncDestinationWithProtection();
                _refreshPreview();
              }),
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
        if (_destination != _PrintDestination.word) ...[
          PrintingSliderRow(
            label: 'גודל גופן',
            value: fontSize,
            min: 10,
            max: 50,
            displayValue: fontSize.toInt().toString(),
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
        PrintingDropdownRow(
          label: 'שם הוי"ה',
          child: AppDropdownField<HolyNameDisplay>(
            value: _holyName,
            entries: [
              AppMenuEntry(
                value: HolyNameDisplay.asIs,
                label: 'ככתבו',
              ),
              AppMenuEntry(
                value: HolyNameDisplay.kufKuf,
                label: 'יקוק',
              ),
              AppMenuEntry(
                value: HolyNameDisplay.daletDalet,
                label: 'ידוד',
              ),
              AppMenuEntry(
                value: HolyNameDisplay.hehApostrophe,
                label: "ה'",
              ),
              AppMenuEntry(
                value: HolyNameDisplay.doubleYod,
                label: 'יי',
              ),
            ],
            onSelected: (value) {
              if (value == null) return;
              setState(() {
                _holyName = value;
                _refreshPreview();
              });
            },
          ),
        ),
        if (!_divineNames.isEmpty)
          PrintingSwitchRow(
            label: 'שאר שמות הקודש בכינוי',
            value: _substituteDivineNames,
            onChanged: (value) {
              setState(() {
                _divineNamesDisplay = value
                    ? DivineNamesDisplay.substitute
                    : DivineNamesDisplay.asIs;
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
          displayValue: '${pageMargin.toInt()} px',
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
        if (_destination != _PrintDestination.word)
          PrintingPagesPerSheetDropdownRow(
            value: _pagesPerSheet,
            onChanged: _setPagesPerSheet,
          ),
      ],
    ),
  ];

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
              onPressed: _isPrinting ? null : () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _isPrinting
                ? ActionButton.recommended(
                    text: _printProgress!,
                    iconWidget: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    onPressed: null,
                  )
                : ActionButton.recommended(
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
                      if (_supportsPdf)
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
      child: AnimatedBuilder(
        animation: _preview,
        builder: (context, _) {
          if (_preview.failed) {
            return Center(
              child: Icon(
                FluentIcons.error_circle_24_regular,
                color: colorScheme.error,
                size: 48,
              ),
            );
          }

          final pageCount = _preview.pageCount;

          // אין עדיין תמונות — מציגים אינדיקטור טעינה (גם בזמן busy וגם בריק).
          if (pageCount == 0) {
            if (_preview.busy) {
              // נגלל: בפריסה צרה אזור התצוגה נמוך מהאינדיקטור וההסבר.
              return Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        'מכין תצוגה מקדימה...',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SlowPreviewHint(),
                    ],
                  ),
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
              ? pageCount
              : (pageCount + cells - 1) ~/ cells;
          final list = ScrollablePositionedListScrollbar(
            scrollController: _itemScrollController,
            itemCount: sheetCount,
            child: ScrollablePositionedList.separated(
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              padding: const EdgeInsets.all(16),
              itemCount: sheetCount,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                return Center(
                  child: _buildSheet(
                    index,
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
                duration: AppMotion.duration(context, AppTokens.animNormal),
                curve: Curves.easeInOut,
                child: _showThumbnails
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildThumbnailsPane(
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

  /// מספר הגיליונות בתצוגה המקדימה, או null כשאין בין מה לנווט.
  /// הניווט זמין ברגע שמספר הגיליונות ידוע, גם לפני רינדורם.
  int? _navigableSheetCount() {
    final cells = switch (_pagesPerSheet) {
      2 => 2,
      4 => 4,
      _ => 1,
    };
    final pageCount = _preview.pageCount;
    final sheetCount = cells <= 1
        ? pageCount
        : (pageCount + cells - 1) ~/ cells;
    return sheetCount > 1 ? sheetCount : null;
  }

  /// פקדי ניווט בסרגל העליון: כפתור "ניווט" (מחליף תצוגה מוקטנת) ובורר "עמוד".
  Widget _buildTopBarNav(int sheetCount) {
    final currentSheet = _currentPreviewItem.clamp(
      0,
      sheetCount > 0 ? sheetCount - 1 : 0,
    );
    final colorScheme = Theme.of(context).colorScheme;

    void toggleThumbnails() {
      setState(() => _showThumbnails = !_showThumbnails);
      if (!_showThumbnails) _preview.showSheets({}, thumbnails: true);
    }

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
            fontSize: AppTokens.fontMD,
          ),
        ),
        const SizedBox(width: AppTokens.spaceSM),
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
              AppMotion.scroll(
                context,
                AppTokens.animPanelSlide,
                animate: (duration) => _itemScrollController.scrollTo(
                  index: value - 1,
                  duration: duration,
                  curve: Curves.easeInOut,
                ),
                jump: () => _itemScrollController.jumpTo(index: value - 1),
              );
            },
          ),
        ),
      ],
    );
  }

  /// חלונית תצוגות מוקטנות של הגיליונות כפי שיודפסו (כולל פריסת N-up); לחיצה
  /// מנווטת לגיליון.
  Widget _buildThumbnailsPane(
    int rows,
    int cols,
    ColorScheme colorScheme,
  ) {
    final cells = rows * cols;
    final sheetCount = cells <= 1
        ? _preview.pageCount
        : (_preview.pageCount + cells - 1) ~/ cells;
    // רקע מובחן מהתצוגה, כדי שהרצועה תיקרא כסרגל צד ולא כחלק מהדף.
    return ColoredBox(
      color: colorScheme.surfaceContainer,
      child: SizedBox(
        width: 132,
        child: ScrollablePositionedList.separated(
          itemPositionsListener: _thumbnailPositionsListener,
          padding: const EdgeInsets.all(8),
          itemCount: sheetCount,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final selected = i == _currentPreviewItem;
            return GestureDetector(
              onTap: () {
                if (!_itemScrollController.isAttached) return;
                AppMotion.scroll(
                  context,
                  AppTokens.animPanelSlide,
                  animate: (duration) => _itemScrollController.scrollTo(
                    index: i,
                    duration: duration,
                    curve: Curves.easeInOut,
                  ),
                  jump: () => _itemScrollController.jumpTo(index: i),
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
                    child: _buildSheet(
                      i,
                      rows,
                      cols,
                      colorScheme,
                      thumbnail: true,
                    ),
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
  /// [rows]x[cols] של N-up (הראשון מימין, כל עמוד ממורכז בתאו), תואם ל-_composeNUp.
  /// משותף לתצוגה הראשית ולחלונית התצוגות המוקטנות.
  Widget _buildSheet(
    int sheetIndex,
    int rows,
    int cols,
    ColorScheme colorScheme, {
    bool thumbnail = false,
  }) {
    final cells = rows * cols;
    if (cells <= 1) {
      return _decoratedSheet(
        _buildPreviewPage(sheetIndex, thumbnail: thumbnail),
        colorScheme,
      );
    }
    final start = sheetIndex * cells;
    final sheetFormat = _effectivePageFormat(format);
    return _decoratedSheet(
      AspectRatio(
        aspectRatio: sheetFormat.width / sheetFormat.height,
        child: Column(
          children: List.generate(rows, (row) {
            return Expanded(
              child: Row(
                children: List.generate(cols, (col) {
                  final index = start + row * cols + col;
                  if (index >= _preview.pageCount) {
                    return const Expanded(child: SizedBox());
                  }
                  return Expanded(
                    child: Center(
                      child: _buildPreviewPage(index, thumbnail: thumbnail),
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

  Widget _buildPreviewPage(int index, {required bool thumbnail}) {
    final size = _preview.pageSize(index);
    final image = _preview.image(index, thumbnail: thumbnail);
    return AspectRatio(
      aspectRatio: size.width / size.height,
      child: image == null
          ? const Center(
              child: LoadingIndicator(size: AppTokens.iconMD, strokeWidth: 2),
            )
          : RawImage(
              image: image,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
    );
  }

  // שימוש בקבועים מ-AppFonts
  Map<String, String> get fonts => AppFonts.fontPaths;
  Map<String, String> get fontNames {
    // כולל את כל הגופנים הזמינים, גם מהמערכת.
    final Map<String, String> allFonts = {};
    for (final font in AppFonts.availableFonts) {
      allFonts[font.value] = font.label;
    }
    return allFonts;
  }

  /// גדלי הדף, אותם בהדפסת PDF מוכן ובהדפסת טקסט.
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

/// קישורי [links] לפי שורת מקור (1-based) בטווח [first, last], בסדרם המקורי:
/// כל שורה בהדפסה מסננת רק את קישוריה ולא את כל קישורי הטווח.
@visibleForTesting
Map<int, List<Link>> groupLinksBySourceLine(
  List<Link> links,
  int first,
  int last,
) {
  final byLine = <int, List<Link>>{};
  for (final link in links) {
    final start = link.index1;
    if (start >= first && start <= last) (byLine[start] ??= []).add(link);
    final end = min(link.index1End ?? start, last);
    for (var line = max(start + 1, first); line <= end; line++) {
      (byLine[line] ??= []).add(link);
    }
  }
  return byLine;
}

/// קישורי הטווח להדפסה — אותו מקור של חלונית המפרשים: קישורי הספר לפי מקורו,
/// קישורי המשתמש וקישורים חוצי-מסדים.
@visibleForTesting
Future<List<Link>> loadPrintRangeLinks(
  TextBook book, {
  required int startIndex,
  required int endIndex,
  required List<String> targetBookTitles,
  required List<Link> fallback,
  TextBookRepository? repository,
}) async {
  try {
    return await (repository ??
            TextBookRepository(fileSystem: FileSystemData.instance))
        .getBookLinksInRange(
          book,
          startIndex: startIndex,
          endIndex: endIndex,
          targetBookTitles: targetBookTitles,
        );
  } catch (e) {
    // fallback אינו מסונן לטווח שנבחר — הכשל חייב להיות גלוי בלוג.
    debugPrint('[Print] range links load failed for "${book.title}": $e');
    return fallback;
  }
}
