/// ייצוא "תיקון קוראים" ל-PDF.
///
/// אותם ווידג'טים של התצוגה מפורססים מחוץ למסך — הפריסה היא מקור האמת
/// למיקומים — ואז כל מילה נאספת מעץ הרינדור ונכתבת כטקסט וקטורי מעוצב
/// (ניקוד וטעמים במקומם) במקום כתמונה של הדף.
library;

import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/tools/tikkun_korim/engine/verse_range_slicer.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_pdf_writer.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_vector_ops.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_page.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;

/// שוליים בכל צד — 1 ס"מ, כמו בתוסף.
const double kTikkunExportMarginPt = 28.35;

/// מצב העימוד של הייצוא.
enum TikkunExportMode {
  /// כל טור של השיטה (42/51 שורות) מוקטן לדף PDF אחד.
  originalPages,

  /// השורות זורמות וממלאות כל דף עד סופו; מעבר דף רק בין שורות.
  flow,
}

/// אילו טורים ייכללו בייצוא.
enum TikkunExportColumns { both, stamOnly, nikudOnly }

/// היקף הייצוא.
enum TikkunExportScope {
  /// הטור המוצג כרגע.
  currentColumn,

  /// כל הטורים של הקריאה הנוכחית (פרשה / הפטרה / פרק).
  all,

  /// טווח טורים שנבחר.
  range,

  /// טווח פרקים ופסוקים.
  verseRange,

  /// העמודים השלמים של הפרשה הנוכחית — [TikkunExportOptions.parashaFromColumn]
  /// עד [TikkunExportOptions.parashaToColumn].
  parasha,
}

@immutable
class TikkunExportOptions {
  final TikkunExportScope scope;
  final TikkunExportMode mode;
  final PdfPageFormat pageFormat;
  final TikkunExportColumns columns;

  /// טווח הטורים (0-based, כולל) — רלוונטי רק ב-[TikkunExportScope.range].
  final int fromColumn;
  final int toColumn;

  /// טווח הפסוקים (כולל) — רלוונטי רק ב-[TikkunExportScope.verseRange].
  final int fromChapter;
  final int fromVerse;
  final int toChapter;
  final int toVerse;

  /// טווח העמודים של הפרשה (0-based, כולל) — רלוונטי רק ב-[TikkunExportScope.parasha].
  final int parashaFromColumn;
  final int parashaToColumn;

  const TikkunExportOptions({
    this.scope = TikkunExportScope.currentColumn,
    this.mode = TikkunExportMode.originalPages,
    this.pageFormat = PdfPageFormat.a4,
    this.columns = TikkunExportColumns.both,
    this.fromColumn = 0,
    this.toColumn = 0,
    this.fromChapter = 1,
    this.fromVerse = 1,
    this.toChapter = 1,
    this.toVerse = 1,
    this.parashaFromColumn = 0,
    this.parashaToColumn = 0,
  });

  TikkunExportOptions copyWith({
    TikkunExportScope? scope,
    TikkunExportMode? mode,
    PdfPageFormat? pageFormat,
    TikkunExportColumns? columns,
    int? fromColumn,
    int? toColumn,
    int? fromChapter,
    int? fromVerse,
    int? toChapter,
    int? toVerse,
    int? parashaFromColumn,
    int? parashaToColumn,
  }) => TikkunExportOptions(
    scope: scope ?? this.scope,
    mode: mode ?? this.mode,
    pageFormat: pageFormat ?? this.pageFormat,
    columns: columns ?? this.columns,
    fromColumn: fromColumn ?? this.fromColumn,
    toColumn: toColumn ?? this.toColumn,
    fromChapter: fromChapter ?? this.fromChapter,
    fromVerse: fromVerse ?? this.fromVerse,
    toChapter: toChapter ?? this.toChapter,
    toVerse: toVerse ?? this.toVerse,
    parashaFromColumn: parashaFromColumn ?? this.parashaFromColumn,
    parashaToColumn: parashaToColumn ?? this.parashaToColumn,
  );

  bool get hideStam => columns == TikkunExportColumns.nikudOnly;
  bool get hideNikud => columns == TikkunExportColumns.stamOnly;
}

/// בוחר מתוך [columns] את הטורים שנכללים ב-[options].
///
/// [currentColumn] הוא הטור המוצג, ומשמש רק ב-[TikkunExportScope.currentColumn].
List<List<TikkunLine>> selectTikkunExportColumns(
  List<List<TikkunLine>> columns,
  TikkunExportOptions options,
  int currentColumn,
) {
  if (columns.isEmpty) return const [];
  final last = columns.length - 1;
  return switch (options.scope) {
    TikkunExportScope.all => columns,
    TikkunExportScope.currentColumn => [columns[currentColumn.clamp(0, last)]],
    TikkunExportScope.range => _columnSpan(
      columns,
      options.fromColumn,
      options.toColumn,
    ),
    TikkunExportScope.parasha => _columnSpan(
      columns,
      options.parashaFromColumn,
      options.parashaToColumn,
    ),
    TikkunExportScope.verseRange => _sliceColumnsByVerses(columns, options),
  };
}

List<List<TikkunLine>> _columnSpan(
  List<List<TikkunLine>> columns,
  int fromColumn,
  int toColumn,
) {
  final last = columns.length - 1;
  final from = fromColumn.clamp(0, last);
  final to = toColumn.clamp(from, last);
  return columns.sublist(from, to + 1);
}

/// טווח העמודים השלמים (0-based, כולל) של [parasha]: מעמוד פתיחתה ועד העמוד
/// שלפני פתיחת הפרשה הבאה — או עמוד הפתיחה עצמו כשהיא נפתחת באמצעו.
/// `null` כשהפרשה אינה נמצאת.
({int from, int to})? tikkunParashaColumnRange(
  List<List<TikkunLine>> columns,
  String parasha,
) {
  int? from;
  for (var c = 0; c < columns.length; c++) {
    final column = columns[c];
    for (var i = 0; i < column.length; i++) {
      final name = column[i].parashaName;
      if (name == null) continue;
      if (from == null) {
        if (name == parasha) from = c;
      } else if (name != parasha) {
        return (from: from, to: i > 0 || c == from ? c : c - 1);
      }
    }
  }
  return from == null ? null : (from: from, to: columns.length - 1);
}

/// שורות [parasha] בלבד: משורת פתיחתה ועד פתיחת הפרשה הבאה; טורים ריקים נשמטים.
List<List<TikkunLine>> sliceTikkunParashaColumns(
  List<List<TikkunLine>> columns,
  String parasha,
) {
  var started = false;
  final result = <List<TikkunLine>>[];
  for (final column in columns) {
    final kept = <TikkunLine>[];
    for (final line in column) {
      final name = line.parashaName;
      if (!started && name == parasha) started = true;
      if (started && name != null && name != parasha) {
        if (kept.isNotEmpty) result.add(kept);
        return result;
      }
      if (started) kept.add(line);
    }
    if (kept.isNotEmpty) result.add(kept);
  }
  return result;
}

/// השורות שבטווח הפסוקים, לפי הפרק והפסוק הרצים; טורים שנותרו ריקים נשמטים.
List<List<TikkunLine>> _sliceColumnsByVerses(
  List<List<TikkunLine>> columns,
  TikkunExportOptions options,
) {
  var ch = 1;
  var vs = 1;
  final result = <List<TikkunLine>>[];
  for (final column in columns) {
    final kept = <TikkunLine>[];
    for (final line in column) {
      ch = line.firstChapterNum ?? ch;
      vs = line.firstVerseNum ?? vs;
      if (compareVerse(ch, vs, options.fromChapter, options.fromVerse) >= 0 &&
          compareVerse(ch, vs, options.toChapter, options.toVerse) <= 0) {
        kept.add(line);
      }
    }
    if (kept.isNotEmpty) result.add(kept);
  }
  return result;
}

/// חותך את טורי התורה לחומש אחד: מהשורה שבה מתחילה [firstParasha] ועד השורה
/// שבה מתחילה [nextBookFirstParasha] (או הסוף). טורים ריקים נשמטים; כשהפרשה
/// הראשונה אינה נמצאת מוחזרים כל הטורים.
List<List<TikkunLine>> sliceTikkunBookColumns(
  List<List<TikkunLine>> columns, {
  required String firstParasha,
  String? nextBookFirstParasha,
}) {
  var started = false;
  final result = <List<TikkunLine>>[];
  for (final column in columns) {
    final kept = <TikkunLine>[];
    for (final line in column) {
      if (!started && line.parashaName == firstParasha) started = true;
      if (started &&
          nextBookFirstParasha != null &&
          line.parashaName == nextBookFirstParasha) {
        if (kept.isNotEmpty) result.add(kept);
        return result;
      }
      if (started) kept.add(line);
    }
    if (kept.isNotEmpty) result.add(kept);
  }
  return started ? result : columns;
}

/// הפרקים שבטורים ומספר הפסוק הגבוה ביותר בכל אחד — תחום בוררי טווח הפסוקים.
SplayTreeMap<int, int> tikkunVerseDomain(List<List<TikkunLine>> columns) {
  final domain = SplayTreeMap<int, int>();
  var ch = 1;
  var vs = 1;
  for (final column in columns) {
    for (final line in column) {
      ch = line.firstChapterNum ?? ch;
      vs = line.firstVerseNum ?? vs;
      domain[ch] = math.max(domain[ch] ?? 1, vs);
    }
  }
  return domain;
}

/// נזרק כשהייצוא בוטל — מלחצן הביטול או מסגירת הטאב.
class TikkunExportCancelled implements Exception {
  const TikkunExportCancelled();
}

/// טווח שורות רציף שנכנס לדף אחד.
@immutable
class TikkunLineRange {
  final int start;
  final int end; // כולל

  const TikkunLineRange(this.start, this.end);

  int get length => end - start + 1;

  @override
  bool operator ==(Object other) =>
      other is TikkunLineRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TikkunLineRange($start..$end)';
}

/// חלוקת שורות לדפים במצב רצף — שורה לעולם אינה נחתכת באמצע.
///
/// [heights] גובה כל שורה, [maxHeight] הגובה השמיש בדף. שורה גבוהה מדף שלם
/// מקבלת דף לעצמה (בהמשך היא מוקטנת כדי להיכנס).
List<TikkunLineRange> paginateTikkunLines(
  List<double> heights,
  double maxHeight,
) {
  final ranges = <TikkunLineRange>[];
  if (heights.isEmpty || maxHeight <= 0) return ranges;
  var start = 0;
  var used = 0.0;
  for (var i = 0; i < heights.length; i++) {
    final height = heights[i];
    if (used > 0 && used + height > maxHeight) {
      ranges.add(TikkunLineRange(start, i - 1));
      start = i;
      used = 0;
    }
    used += height;
  }
  ranges.add(TikkunLineRange(start, heights.length - 1));
  return ranges;
}

/// מייצא את שורות התיקון ל-PDF.
class TikkunPdfExporter {
  final TikkunSettings settings;
  final TikkunExportOptions options;

  /// תקציב רוחב השורה שהעמודים נחתכו לפיו — חייב להיות זהה לזה שבתצוגה,
  /// אחרת היישור בייצוא יפזר רוחב שאינו קיים.
  final double lineWidthEm;

  /// הכותרת שמוצגת פעם אחת בראש הייצוא.
  final String? headerTitle;
  final String? headerSubtitle;

  /// טוען את קובצי הגופנים; ניתן להחלפה בבדיקות.
  final TikkunFontLoader loadFont;

  bool _cancelled = false;

  TikkunPdfExporter({
    required this.settings,
    required this.options,
    this.lineWidthEm = kTikkunInitialLineWidthEm,
    this.headerTitle,
    this.headerSubtitle,
    this.loadFont = loadTikkunExportFont,
  });

  /// עוצר את הייצוא בהזדמנות הבאה; [export] ייכשל ב-[TikkunExportCancelled].
  void cancel() => _cancelled = true;

  bool get isCancelled => _cancelled;

  void _throwIfCancelled() {
    if (_cancelled) throw const TikkunExportCancelled();
  }

  double get _usableWidthPt =>
      options.pageFormat.width - 2 * kTikkunExportMarginPt;

  double get _usableHeightPt =>
      options.pageFormat.height - 2 * kTikkunExportMarginPt;

  /// רוחב העמוד הלוגי — כמו בתצוגה, לפי פריסת הטורים.
  late final double _pageWidth = _pageWidthFor(1);

  double _pageWidthFor(double widthFactor) =>
      _metricsFor(widthFactor).pageWidth;

  /// נקודות PDF לכל פיקסל לוגי של התצוגה.
  double get _ptPerLogical => _usableWidthPt / _pageWidth;

  /// מייצא [columns] — כל איבר הוא טור של השיטה.
  ///
  /// [onProgress] נקרא עם (הדף הנוכחי, סך הדפים); סך אפס פירושו הכנה
  /// (מדידת השורות) שמשכה עוד לא ידוע.
  Future<Uint8List> export(
    List<List<TikkunLine>> columns, {
    void Function(int done, int total)? onProgress,
  }) async {
    final pages = await layoutPages(columns, onProgress: onProgress);
    if (pages.isEmpty) {
      throw StateError('אין תוכן לייצוא');
    }
    _throwIfCancelled();
    final writer = TikkunVectorPdfWriter(
      pageFormat: options.pageFormat,
      loadFont: loadFont,
      fallbackFamilies: [
        settings.nikudFontFamily,
        settings.stamFontFamily,
        AppFonts.defaultFont,
      ],
    );
    return writer.write(
      pages,
      unifyScale: options.mode == TikkunExportMode.originalPages,
    );
  }

  /// מפרסס את הדפים ואוסף את הפעולות הווקטוריות שלהם, בלי להרכיב את המסמך.
  Future<List<TikkunVectorPage>> layoutPages(
    List<List<TikkunLine>> columns, {
    void Function(int done, int total)? onProgress,
  }) {
    _throwIfCancelled();
    return options.mode == TikkunExportMode.originalPages
        ? _layoutOriginalPages(columns, onProgress)
        : _layoutFlow(columns, onProgress);
  }

  Future<List<TikkunVectorPage>> _layoutOriginalPages(
    List<List<TikkunLine>> columns,
    void Function(int done, int total)? onProgress,
  ) async {
    final pages = <TikkunVectorPage>[];
    for (var i = 0; i < columns.length; i++) {
      _throwIfCancelled();
      onProgress?.call(i + 1, columns.length);
      final lines = columns[i];
      if (lines.isEmpty) continue;
      final markers = computeTikkunLineMarkers(lines);
      final widthFactor = tikkunPageWidthFactor(lines);
      final pageMetrics = _metricsFor(widthFactor);
      final gaps = _gapsFor(lines, pageMetrics, _pageWidthFor(widthFactor));
      final page = await _collectPage(
        _decorate(
          verticalPadding: _pagePaddingV,
          metrics: pageMetrics,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i == 0) _header(),
              for (var j = 0; j < lines.length; j++)
                _lineWidget(lines[j], markers[j], gaps, pageMetrics),
            ],
          ),
        ),
        hasHeader: i == 0,
        widthFactor: widthFactor,
      );
      if (page != null) pages.add(page);
    }
    return pages;
  }

  Future<List<TikkunVectorPage>> _layoutFlow(
    List<List<TikkunLine>> columns,
    void Function(int done, int total)? onProgress,
  ) async {
    final lines = [for (final column in columns) ...column];
    if (lines.isEmpty) return const [];

    final markers = computeTikkunLineMarkers(lines);
    // שורת דף רחב נכנסת ברוחב הדף הרגיל בכתב מוקטן באותו יחס.
    TikkunRenderMetrics lineMetrics(double factor) =>
        factor == 1 ? metrics : metrics.withFontScale(1 / factor);
    final gaps = {
      for (final factor in {for (final l in lines) l.widthFactor})
        factor: _gapsFor(
          [
            for (final l in lines)
              if (l.widthFactor == factor) l,
          ],
          lineMetrics(factor),
          _pageWidth,
        ),
    };
    // הכותרת היא הפריט הראשון — כך העימוד מתחשב בגובהה בדף הראשון.
    final items = <Widget>[
      _header(),
      for (var i = 0; i < lines.length; i++)
        _lineWidget(
          lines[i],
          markers[i],
          gaps[lines[i].widthFactor]!,
          lineMetrics(lines[i].widthFactor),
        ),
    ];

    onProgress?.call(0, 0);
    final heights = await _measureHeights(items);
    final usableLogicalHeight =
        _usableHeightPt / _ptPerLogical - 2 * _pagePaddingV;
    final ranges = paginateTikkunLines(heights, usableLogicalHeight);

    final pages = <TikkunVectorPage>[];
    for (var i = 0; i < ranges.length; i++) {
      _throwIfCancelled();
      onProgress?.call(i + 1, ranges.length);
      final range = ranges[i];
      final page = await _collectPage(
        _decorate(
          verticalPadding: _pagePaddingV,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: items.sublist(range.start, range.end + 1),
          ),
        ),
        hasHeader: range.start == 0,
      );
      if (page != null) pages.add(page);
    }
    return pages;
  }

  /// מספר הפריטים שנמדדים בפריסה אחת — עץ של אלפי שורות בבת אחת יקר בזיכרון.
  static const int _measureChunk = 200;

  /// גובה כל פריט, נמדד בקבוצות: הפריטים מונחים בעמודה אחת וגובה כל ילד נקרא
  /// מעץ הרינדור — במקום פריסה נפרדת לכל שורה.
  Future<List<double>> _measureHeights(List<Widget> items) async {
    final heights = <double>[];
    for (var start = 0; start < items.length; start += _measureChunk) {
      _throwIfCancelled();
      final chunk = items.sublist(
        start,
        (start + _measureChunk).clamp(0, items.length),
      );
      final measured = await _layoutOffscreen(
        _decorate(Column(mainAxisSize: MainAxisSize.min, children: chunk)),
        (boundary) async => _childHeights(boundary, chunk.length),
      );
      heights.addAll(measured);
    }
    return heights;
  }

  /// גובהי ילדי ה-Column הראשון מתחת ל-[boundary].
  static List<double> _childHeights(RenderObject boundary, int expected) {
    RenderFlex? column;
    void visit(RenderObject object) {
      if (column != null) return;
      if (object is RenderFlex) {
        column = object;
        return;
      }
      object.visitChildren(visit);
    }

    visit(boundary);
    final heights = <double>[];
    var child = column?.firstChild;
    while (child != null) {
      heights.add(child.size.height);
      child = column!.childAfter(child);
    }
    assert(heights.length == expected, 'measured ${heights.length}/$expected');
    return heights;
  }

  late final TikkunRenderMetrics metrics = _metricsFor(1);

  final Map<double, TikkunRenderMetrics> _metricsByFactor = {};

  /// מידות דף ברוחב [widthFactor] מדף רגיל, כשהוא מונח ברוחבו המלא.
  TikkunRenderMetrics _metricsFor(double widthFactor) =>
      _metricsByFactor.putIfAbsent(
        widthFactor,
        // דף רחב בלי מגבלת רוחב: הוא מוקטן אל הנייר בכתיבה.
        () => TikkunRenderMetrics.forWidth(
          TikkunRenderMetrics.referenceWidthFor(settings),
          settings,
          lineWidthEm: lineWidthEm,
          pageWidthFactor: widthFactor,
          maxPageWidth: double.infinity,
        ),
      );

  /// הריפוד האנכי של העמוד — זהה לזה של רשימת השורות בתצוגה.
  late final double _pagePaddingV = metrics.em(1);

  TikkunGapAverages _gapsFor(
    List<TikkunLine> lines,
    TikkunRenderMetrics lineMetrics,
    double pageWidth,
  ) => computeTikkunGapAverages(
    lines: lines,
    metrics: lineMetrics,
    settings: settings,
    rowWidth: pageWidth - 2 * lineMetrics.em(kTikkunRowPaddingEm),
    hideNikud: options.hideNikud,
    maskDivineName: settings.hideDivineName,
  );

  Widget _lineWidget(
    TikkunLine line,
    TikkunLineMarkers markers,
    TikkunGapAverages gaps,
    TikkunRenderMetrics lineMetrics,
  ) => buildTikkunLineWidget(
    line: line,
    markers: markers,
    metrics: lineMetrics,
    settings: settings,
    hideStam: options.hideStam,
    hideNikud: options.hideNikud,
    gaps: gaps,
  );

  Widget _header() {
    if (headerTitle == null && headerSubtitle == null) {
      return const SizedBox.shrink();
    }
    // גופן מפורש: ה-PDF מטמיע את הקובץ, וגופן המערכת של המסך אינו זמין לו.
    const family = AppFonts.defaultFont;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Column(
        children: [
          if (headerTitle != null)
            Text(
              headerTitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: family,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          if (headerSubtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                headerSubtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: family,
                  fontSize: 18,
                  color: Colors.black,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// עוטף בהקשר שהשורות מצפות לו — הייצוא תמיד בהיר, גם בערכת נושא כהה.
  Widget _decorate(
    Widget child, {
    double verticalPadding = 0,
    TikkunRenderMetrics? metrics,
  }) => Directionality(
    textDirection: TextDirection.rtl,
    child: MediaQuery(
      data: const MediaQueryData(),
      child: Theme(
        data: _exportTheme,
        child: Material(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: verticalPadding,
              horizontal: (metrics ?? this.metrics).em(
                kTikkunRowPaddingEm,
              ),
            ),
            child: child,
          ),
        ),
      ),
    ),
  );

  /// חריצי הטורים של הדף, לפי אותן פונקציות שהשורה עצמה נפרסת בהן. הקווים
  /// יוצאים באמצע הרווח שבין הטור לעמודת המסמנים, ולכן אינם תלויים בהחלפת
  /// הטורים — שני הטורים תמיד באותו רוחב.
  TikkunPageColumns _columnsFor({
    required bool hasHeader,
    required double widthFactor,
  }) {
    final leading = hasHeader ? 1 : 0;
    if (settings.showsSingleCenteredColumn) {
      return TikkunPageColumns(leadingFullWidthChildren: leading);
    }
    final pageMetrics = _metricsFor(widthFactor);
    final padding = pageMetrics.em(kTikkunRowPaddingEm);
    final rowWidth = _pageWidthFor(widthFactor) - 2 * padding;
    final columnWidth = tikkunColumnWidth(rowWidth, pageMetrics, settings);
    final half = pageMetrics.columnGap / 2;
    return TikkunPageColumns(
      cuts: [
        padding + columnWidth + half,
        padding + rowWidth - columnWidth - half,
      ],
      leadingFullWidthChildren: leading,
    );
  }

  /// מפרסס דף שלם מחוץ למסך ואוסף ממנו את הטקסט והגבולות.
  Future<TikkunVectorPage?> _collectPage(
    Widget widget, {
    required bool hasHeader,
    double widthFactor = 1,
  }) => _layoutOffscreen(widget, width: _pageWidthFor(widthFactor), (
    boundary,
  ) async {
    if (boundary.size.isEmpty) return null;
    final page = collectTikkunVectorPage(
      boundary,
      columns: _columnsFor(hasHeader: hasHeader, widthFactor: widthFactor),
    );
    return page.isEmpty ? null : page;
  });

  /// בונה עץ ווידג'טים מחוץ למסך, מפרסס אותו ומריץ עליו [action].
  Future<T> _layoutOffscreen<T>(
    Widget widget,
    Future<T> Function(RenderRepaintBoundary boundary) action, {
    double? width,
  }) async {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView!;
    final boundary = RenderRepaintBoundary();
    final constraints = BoxConstraints(
      minWidth: width ?? _pageWidth,
      maxWidth: width ?? _pageWidth,
      maxHeight: _kOffscreenMaxHeight,
    );
    final renderView = RenderView(
      view: view,
      configuration: ViewConfiguration(
        logicalConstraints: constraints,
        physicalConstraints: constraints,
      ),
      child: boundary,
    );
    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();

    final buildOwner = BuildOwner(focusManager: FocusManager());
    final element = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: widget,
    ).attachToRenderTree(buildOwner);
    buildOwner
      ..buildScope(element)
      ..finalizeTree();
    pipelineOwner.flushLayout();

    try {
      return await action(boundary);
    } finally {
      // פירוק העץ — בלי זה ה-GlobalObjectKey של ה-boundary נשאר תפוס.
      RenderObjectToWidgetAdapter<RenderBox>(
        container: boundary,
      ).attachToRenderTree(buildOwner, element);
      buildOwner.finalizeTree();
      pipelineOwner.rootNode = null;
    }
  }
}

const double _kOffscreenMaxHeight = 100000;

final ThemeData _exportTheme = ThemeData(
  brightness: Brightness.light,
  useMaterial3: true,
);
