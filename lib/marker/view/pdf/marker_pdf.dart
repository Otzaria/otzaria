import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/marker/models/marker_book_uid.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_actions.dart';
import 'package:otzaria/marker/services/marker_book_cache.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/marker/view/reader/marker_reader_menu.dart';
import 'package:otzaria/marker/view/reader/marker_toolbar_action.dart';
import 'package:otzaria/marker/view/widgets/marker_dialogs.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';
import 'package:otzaria/plugins/models/plugin_reader_selection.dart';
import 'package:otzaria/plugins/services/reader_selection_service.dart';
import 'package:otzaria/theme/marker_colors.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';
import 'package:pdfrx/pdfrx.dart';

/// סימוני המרקר בספר PDF: ציור מעל העמודים, טקסט העמודים לעיגון, ופריטי
/// התפריט. מקטע הוא עמוד, והעוגן הוא בטקסט שחולץ ממנו.
class MarkerPdfController {
  MarkerPdfController({
    required this.book,
    required this.viewer,
    required this.brightness,
    this.pageRef,
    this.copyAllowed,
  }) : uid = markerBookUidOf(book) {
    _listenable = MarkerBookCache.instance.listenable(book.title)
      ..addListener(_repaint);
    MarkerSettings.instance.addListener(_repaint);
    _byViewer[viewer] = this;
  }

  static final Expando<MarkerPdfController> _byViewer = Expando();

  /// הבקר של הצופה, לחלונית ההערות שמחזיקה רק את הצופה.
  static MarkerPdfController? of(PdfViewerController viewer) =>
      _byViewer[viewer];

  final PdfBook book;
  final String uid;
  final PdfViewerController viewer;
  final Brightness Function() brightness;

  /// מראה המקום של עמוד, לסימון שנוצר או מועבר אליו.
  final String? Function(int pageNumber)? pageRef;

  /// אם המסמך מתיר העתקה. סימון שומר את הטקסט, ולכן במסמך שאוסר העתקה
  /// אין סימון חדש ואין העברה של סימון לטקסט אחר.
  final bool Function()? copyAllowed;
  late final Listenable _listenable;

  final Map<int, PdfPageText> _texts = {};
  final Set<int> _loading = {};

  /// מלבני הסימונים בכל עמוד, ביחידות העמוד. מחושבים מחדש רק כשהציור של
  /// העמוד מתחלף (המטמון מחזיר אז רשימה חדשה), ולא בכל פריים.
  final Map<int, ({List<PluginHighlight> pieces, List<List<PdfRect>> rects})>
  _pageRects = {};
  bool _disposed = false;

  /// מתחיל לטעון את הסימונים, כדי שיצוירו כבר בפתיחת הספר.
  void preload() => MarkerBookCache.instance.ensureLoaded(
    book.title,
    uid,
    pdf: true,
  );

  void dispose() {
    _disposed = true;
    if (identical(_byViewer[viewer], this)) _byViewer[viewer] = null;
    _listenable.removeListener(_repaint);
    MarkerSettings.instance.removeListener(_repaint);
  }

  void _repaint() {
    if (!_disposed && viewer.isReady) viewer.invalidate();
  }

  /// טקסט העמוד אם כבר חולץ.
  PdfPageText? textOf(int pageNumber) => _texts[pageNumber];

  List<PluginHighlight> _pieces(int pageNumber) =>
      MarkerBookCache.instance.paint(
        bookTitle: book.title,
        bookUid: uid,
        sectionIndex: pageNumber,
        brightness: brightness(),
        pdf: true,
      );

  /// `pagePaintCallbacks` של הצופה. הסימון נצבע כמו בספר טקסט: שורה רציפה
  /// עם פינות מעוגלות, גם ברווח שבין המילים, ובמיזוג שמשאיר את האותיות
  /// בצבען — כאילו הצבע מתחת לטקסט ולא מעליו.
  void paint(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    final text = _texts[page.pageNumber];
    if (text == null) {
      // גם סימון שדורש תיקון טוען את הטקסט, כדי שיעוגן מחדש וייצבע.
      if (_hasMarks(page.pageNumber)) unawaited(_loadText(page));
      return;
    }
    final pieces = _pieces(page.pageNumber);
    if (pieces.isEmpty) return;
    final fragments = _rectsOf(page.pageNumber, text, pieces);
    final dark = brightness() == Brightness.dark;
    // עמוד בהיר: הכפלה צובעת את הנייר ומשאירה את הדיו שחור. עמוד כהה (הפוך):
    // מסך צובע את הרקע השחור ומשאיר את האותיות הבהירות.
    final blend = dark ? BlendMode.screen : BlendMode.multiply;
    for (var i = 0; i < pieces.length; i++) {
      final style = pieces[i].style;
      final color = Color(MarkerColor.argbOf(style.backgroundColor));
      // השורות מאוחדות אחרי הסיבוב של העמוד, ככיוון שהן מוצגות.
      final lines = markerLineRects([
        for (final bounds in fragments[i])
          bounds.toRectInDocument(page: page, pageRect: pageRect),
      ]);
      for (final rect in lines) {
        final height = rect.height;
        if (style.underline) {
          final thickness = (height * 0.1).clamp(1.5, 4.0);
          canvas.drawRect(
            Rect.fromLTRB(
              rect.left,
              rect.bottom - thickness,
              rect.right,
              rect.bottom,
            ),
            Paint()..color = color,
          );
          continue;
        }
        final padded = Rect.fromLTRB(
          rect.left - height * 0.12,
          rect.top - height * 0.08,
          rect.right + height * 0.12,
          rect.bottom + height * 0.08,
        );
        final radius = Radius.circular(
          (style.borderRadius * height / 18).clamp(1.0, height / 3),
        );
        final shape = RRect.fromRectAndRadius(padded, radius);
        if (style.markerMode == MarkerStyleMode.box.wireName) {
          canvas.drawRRect(
            shape,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = (height * 0.06).clamp(1.0, 3.0)
              ..color = color,
          );
        } else {
          canvas.drawRRect(
            shape,
            Paint()
              ..blendMode = blend
              // המיזוג כבר משאיר את האותיות בצבען, ולכן העמעום של מצב כהה
              // (שנועד לטקסט שמצויר מעל הצבע) אינו נחוץ כאן.
              ..color = color.withValues(
                alpha: dark
                    ? (style.opacity / MarkerColors.darkFillFactor).clamp(0, 1)
                    : style.opacity,
              ),
          );
        }
      }
    }
  }

  /// מלבני השברים של כל חלק, ביחידות העמוד. מחושבים מחדש רק כשהציור של
  /// העמוד מתחלף (המטמון מחזיר אז רשימה חדשה), ולא בכל פריים.
  List<List<PdfRect>> _rectsOf(
    int pageNumber,
    PdfPageText text,
    List<PluginHighlight> pieces,
  ) {
    final cached = _pageRects[pageNumber];
    if (cached != null && identical(cached.pieces, pieces)) return cached.rects;
    final rects = [
      for (final piece in pieces) _rects(text, piece.range).toList(),
    ];
    _pageRects[pageNumber] = (pieces: pieces, rects: rects);
    return rects;
  }

  static Iterable<PdfRect> _rects(
    PdfPageText text,
    PluginTextRangeAnchor range,
  ) sync* {
    final length = text.fullText.length;
    final start = range.start.utf16.clamp(0, length);
    final end = range.end.utf16.clamp(start, length);
    if (end <= start) return;
    final pdfRange = PdfPageTextRange(pageText: text, start: start, end: end);
    for (final fragment in pdfRange.enumerateFragmentBoundingRects()) {
      yield fragment.bounds;
    }
  }

  bool _hasMarks(int pageNumber) => MarkerBookCache.instance
      .marksInSection(
        bookTitle: book.title,
        bookUid: uid,
        sectionIndex: pageNumber,
        pdf: true,
      )
      .isNotEmpty;

  Future<PdfPageText?> _loadText(PdfPage page) async {
    final number = page.pageNumber;
    final cached = _texts[number];
    if (cached != null) return cached;
    // עמוד שעוד לא נטען מחזיר טקסט ריק, ועיגון מולו היה מסמן הכול כאבוד.
    if (!page.isLoaded || !_loading.add(number)) return null;
    try {
      final text = await page.loadStructuredText();
      if (_disposed || text.fullText.isEmpty) return null;
      _texts[number] = text;
      // העוגנים נבדקים מול הטקסט כפי שחולץ עכשיו, לפני שהם מצוירים.
      MarkerBookCache.instance.reanchorSection(
        bookTitle: book.title,
        bookUid: uid,
        sectionIndex: number,
        sourceText: text.fullText,
        pdf: true,
      );
      _repaint();
      return text;
    } catch (error) {
      debugPrint('Marker: reading PDF page $number text failed: $error');
      return null;
    } finally {
      _loading.remove(number);
    }
  }

  /// טקסט העמוד, טוען אותו אם צריך; null כשהעמוד עוד לא נטען.
  Future<String?> pageText(int pageNumber) async =>
      viewer.isReady ? (await _pageText(pageNumber))?.fullText : null;

  /// אם יש עכשיו טקסט נבחר במסמך.
  bool get hasSelection =>
      viewer.isReady &&
      viewer.textSelectionDelegate.textSelectionPointRange != null;

  /// טיוטה מהבחירה הנוכחית, למשל להעברת סימון אליה; null בלי בחירה, או
  /// במסמך שאוסר העתקה.
  Future<MarkerDraft?> selectionDraft() async {
    if (!viewer.isReady || !(copyAllowed?.call() ?? true)) return null;
    final range = viewer.textSelectionDelegate.textSelectionPointRange;
    if (range == null) return null;
    return draftFromSelection(pageRef?.call(range.start.text.pageNumber));
  }

  Future<PdfPageText?> _pageText(int pageNumber) async {
    final pages = viewer.document.pages;
    if (pageNumber < 1 || pageNumber > pages.length) return null;
    return _texts[pageNumber] ?? await _loadText(pages[pageNumber - 1]);
  }

  /// הטווחים שנבחרו בכל עמוד, ביחידות UTF-16 של טקסט העמוד.
  static List<({PdfPageText text, int start, int end})> _selectedRanges(
    PdfTextSelectionRange range,
    Map<int, PdfPageText> middle,
  ) {
    final first = range.start.text.pageNumber;
    final last = range.end.text.pageNumber;
    return [
      for (var page = first; page <= last; page++)
        if (page == first || page == last || middle[page] != null)
          (
            text: page == first
                ? range.start.text
                : page == last
                ? range.end.text
                : middle[page]!,
            start: page == first ? range.start.index : 0,
            end: page == last
                ? range.end.index + 1
                : (page == first
                      ? range.start.text.fullText.length
                      : middle[page]!.fullText.length),
          ),
    ];
  }

  /// טיוטה מהבחירה הנוכחית, או null כשאין בחירה שאפשר לעגן.
  Future<MarkerDraft?> draftFromSelection(String? ref) async {
    final range = viewer.textSelectionDelegate.textSelectionPointRange;
    if (range == null) return null;
    final middle = <int, PdfPageText>{};
    for (
      var page = range.start.text.pageNumber + 1;
      page < range.end.text.pageNumber;
      page++
    ) {
      final text = await _pageText(page);
      if (text == null) return null;
      middle[page] = text;
    }
    const service = ReaderSelectionService();
    final segments = <MarkerSegment>[];
    for (final piece in _selectedRanges(range, middle)) {
      final full = piece.text.fullText;
      final graphemes = markerGraphemeRange(full, piece.start, piece.end);
      if (graphemes == null) continue;
      final anchor = service.buildRangeAnchor(
        text: full,
        startGrapheme: graphemes.start,
        endGrapheme: graphemes.end,
        layer: 'source',
        sourceTextHash: sha256.convert(utf8.encode(full)).toString(),
      );
      if (anchor == null || anchor.exactText.trim().isEmpty) continue;
      segments.add(
        MarkerSegment(sectionIndex: piece.text.pageNumber, range: anchor),
      );
    }
    if (segments.isEmpty) return null;
    return MarkerDraft(
      bookTitle: book.title,
      bookUid: uid,
      segments: segments,
      text: segments
          .map((segment) => segment.range.exactText)
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
      ref: ref,
      pdf: true,
    );
  }

  /// הסימונים הנראים מתחת לבחירה, בעמודים שהטקסט שלהם כבר ידוע.
  Set<String> _marksUnderSelection() {
    final range = viewer.textSelectionDelegate.textSelectionPointRange;
    if (range == null) return const {};
    final touched = <String>{};
    for (final piece in _selectedRanges(range, _texts)) {
      final graphemes = markerGraphemeRange(
        piece.text.fullText,
        piece.start,
        piece.end,
      );
      if (graphemes == null) continue;
      for (final paint in _pieces(piece.text.pageNumber)) {
        if (paint.range.start.grapheme < graphemes.end &&
            graphemes.start < paint.range.end.grapheme) {
          touched.add(paint.highlightId);
        }
      }
    }
    return touched;
  }

  /// הסימונים שנקודת הלחיצה [globalPosition] נופלת עליהם.
  List<MarkerHighlight> _marksAt(Offset globalPosition) {
    final local = viewer.globalToLocal(globalPosition);
    if (local == null) return const [];
    final hit = viewer.getPdfPageHitTestResult(
      local,
      useDocumentLayoutCoordinates: false,
    );
    if (hit == null) return const [];
    final number = hit.page.pageNumber;
    final text = _texts[number];
    if (text == null) return const [];
    final ids = <String>{};
    final page = hit.page;
    final pieces = _pieces(number);
    final rects = _rectsOf(number, text, pieces);
    // כמו בציור: השורות המאוחדות, בכיוון שבו העמוד מוצג.
    final point = hit.offset.toOffset(page: page);
    for (var i = 0; i < pieces.length; i++) {
      final lines = markerLineRects([
        for (final rect in rects[i]) rect.toRect(page: page),
      ]);
      if (lines.any((line) => line.inflate(1).contains(point))) {
        ids.add(pieces[i].highlightId);
      }
    }
    return [
      for (final mark in MarkerBookCache.instance.marksInSection(
        bookTitle: book.title,
        bookUid: uid,
        sectionIndex: number,
        pdf: true,
      ))
        if (ids.contains(mark.id)) mark,
    ];
  }

  /// מה שכפתור הסרגל תלוי בו.
  Listenable get toolbarListenable =>
      Listenable.merge([_listenable, MarkerSettings.instance]);

  /// כפתור המרקר בסרגל, כמו בספר טקסט.
  ActionButtonData? toolbarAction({required bool compact}) =>
      buildMarkerToolbarAction(
        bookTitle: book.title,
        bookUid: uid,
        compact: compact,
        pdf: true,
      );

  /// פריטי המרקר בתפריט ההקשר של ה-PDF. [ref] — מראה המקום של עמוד.
  List<AppContextMenuEntry> menuEntries({
    required BuildContext context,
    required Offset tapPosition,
    required bool hasSelection,
    required bool copyAllowed,
    required String? Function(int pageNumber) ref,
    VoidCallback? openNotes,
  }) {
    final settings = MarkerSettings.instance;
    if (!viewer.isReady) return const [];
    final palette = settings.palette;
    if (hasSelection) {
      // ההגדרה מסתירה רק את הסימון מהבחירה; פעולות על סימון קיים נשארות.
      // הסימון שומר את הטקסט, ולכן אינו מוצע במסמך שאוסר העתקה.
      if (!settings.showInPdfMenu || !copyAllowed) return const [];
      final range = viewer.textSelectionDelegate.textSelectionPointRange;
      if (range == null) return const [];
      final page = range.start.text.pageNumber;
      final touched = _marksUnderSelection();
      return [
        AppContextMenuEntry.colorRow([
          for (final color in palette.menuColors)
            AppContextMenuColorAction(
              id: color.id,
              color: Color(color.argb),
              label: 'סימון ב${color.label}',
              onTap: () async => MarkerActions.instance.mark(
                await draftFromSelection(ref(page)),
                color,
              ),
            ),
          if (touched.isNotEmpty)
            AppContextMenuColorAction(
              id: 'marker-erase',
              color: const Color(0x00000000),
              label: touched.length == 1
                  ? 'מחיקת הסימון'
                  : 'מחיקת ${touched.length} הסימונים',
              icon: FluentIcons.eraser_24_regular,
              onTap: () => MarkerActions.instance.remove(touched),
            ),
          ?markerNoteColorAction(
            context,
            touched,
            MarkerBookCache.instance.marksOf(book.title, uid, pdf: true) ??
                const [],
            openNotes: openNotes,
          ),
        ]),
      ];
    }
    final clicked = _marksAt(tapPosition);
    if (clicked.isEmpty) return const [];
    String? source(int page) => _texts[page]?.fullText;
    return [
      AppContextMenuEntry(
        label: clicked.length == 1 ? 'סימון' : 'סימונים',
        icon: FluentIcons.highlight_24_regular,
        childrenBuilder: () => clicked.length == 1
            ? markerActionEntries(
                context,
                clicked.single,
                palette,
                source,
                openNotes: openNotes,
              )
            : [
                for (final mark in clicked)
                  AppContextMenuEntry(
                    label: markerQuote(mark.text, 30),
                    childrenBuilder: () => markerActionEntries(
                      context,
                      mark,
                      palette,
                      source,
                      openNotes: openNotes,
                    ),
                  ),
              ],
      ),
    ];
  }
}

/// טווח ה-grapheme שמכסה את [startUtf16]–[endUtf16] (לא כולל) ב-[text]. אות
/// שנבחרה חלקית — למשל בלי הניקוד שלה — נכללת כולה.
({int start, int end})? markerGraphemeRange(
  String text,
  int startUtf16,
  int endUtf16,
) {
  if (endUtf16 <= startUtf16) return null;
  var position = 0;
  var index = 0;
  int? start;
  int? end;
  for (final char in text.characters) {
    final next = position + char.length;
    if (start == null && next > startUtf16) start = index;
    if (position < endUtf16) end = index + 1;
    position = next;
    index++;
    if (position >= endUtf16 && start != null) break;
  }
  if (start == null || end == null || end <= start) return null;
  return (start: start, end: end);
}

/// מאחד את מלבני השברים של טווח לשורות, בכיוון שבו הם מוצגים: הרווח שבין
/// המילים נצבע גם הוא, כמו בספר טקסט. שברים זה לצד זה בגובה אחד הם שורה
/// אחת; טור אחר באותו גובה (רווח גדול ביניהם) ומילה גבוהה בין שתי שורות
/// נשארים נפרדים.
@visibleForTesting
List<Rect> markerLineRects(Iterable<Rect> fragments) {
  final lines = <Rect>[];
  bool sameLine(Rect a, Rect b) {
    final low = math.min(a.height, b.height);
    final overlap = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
    if (overlap < low * 0.5) return false;
    if ((a.center.dy - b.center.dy).abs() > low * 0.5) return false;
    final gap = math.max(a.left, b.left) - math.min(a.right, b.right);
    return gap < math.max(a.height, b.height) * 3;
  }

  for (final fragment in fragments) {
    if (fragment.isEmpty) continue;
    final index = lines.indexWhere((line) => sameLine(line, fragment));
    if (index < 0) {
      lines.add(fragment);
    } else {
      lines[index] = lines[index].expandToInclude(fragment);
    }
  }
  return lines;
}
