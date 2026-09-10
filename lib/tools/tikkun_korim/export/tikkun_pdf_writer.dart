/// כתיבת עמודי התיקון שנאספו כטקסט וקטורי ב-PDF.
///
/// כל מילה מעוצבת דרך `opentype_shaper` (GSUB/GPOS) ונפלטת עם הגליפים שלה
/// דרך [PdfShapedFont], כך שהניקוד והטעמים יושבים במקומם והטקסט נשאר
/// ניתן לסימון ולחיפוש.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart' show Matrix4;
import 'package:flutter/services.dart' show rootBundle;
import 'package:opentype_shaper/opentype_shaper.dart';
import 'package:otzaria/printing/shaped_text/pdf_shaped_font.dart';
import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_pdf_exporter.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_vector_ops.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_stam_fonts.dart';
import 'package:pdf/pdf.dart';

/// מחזיר את קובץ הגופן של [family] במשקל המבוקש, או null כשאין כזה.
typedef TikkunFontLoader =
    Future<Uint8List?> Function(String family, {required bool bold});

/// טוען גופן מוטמע (נכס) או גופן מערכת שהסריקה מכירה. בולד מוחזר רק כשקיים
/// לו face אמיתי — אחרת הכותב מסנתז אותו ממשיחה.
Future<Uint8List?> loadTikkunExportFont(
  String family, {
  required bool bold,
}) async {
  final asset = bold
      ? AppFonts.boldFontPaths[family]
      : (kTikkunBundledFontAssets[family] ?? AppFonts.fontPaths[family]);
  if (asset != null) {
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
  if (bold && AppFonts.fontPaths.containsKey(family)) return null;

  final faces = AppFonts.systemFamilyFaces(family);
  final path = bold ? faces?.boldPath : faces?.regularPath;
  if (path == null) return null;
  try {
    return await File(path).readAsBytes();
  } on FileSystemException {
    return null;
  }
}

/// שיפוע ההטיה המסונתזת — כמו ההטיה שהמנוע מייצר לגופן בלי face נטוי.
const double _kItalicSkew = 0.21;

/// עובי המשיחה שמסנתזת בולד, ביחס לגודל הגופן.
const double _kSyntheticBoldStroke = 0.03;

/// סובלנות קו הבסיס לזיהוי שתי מילים כשכנות באותה שורה, בפיקסלים לוגיים.
const double _kSameLineTolerance = 0.5;

/// הרווח המזערי שמצדיק גליף רווח, ביחס לגודל הגופן. מתחתיו אין גבול מילה
/// אלא פיצול כיוון בתוך מילה אחת (ספרות בתוך טקסט עברי).
const double _kMinWordGapEm = 0.1;

class _ExportFont {
  final ShaperFont shaper;
  final PdfShapedFont pdfFont;

  _ExportFont(this.shaper, this.pdfFont);

  /// ריצת הרווח של הגופן, או null כשאין בו גליף רווח.
  late final ShapedRun? spaceRun = _shapeSpace();

  ShapedRun? _shapeSpace() {
    final run = shaper.shape(' ', rtl: true, script: 'hebr');
    if (run.isEmpty || run.glyphId(0) == 0 || run.advance <= 0) return null;
    return run;
  }
}

/// מרכיב מסמך PDF מעמודים שנאספו ב-[collectTikkunVectorPage].
class TikkunVectorPdfWriter {
  final TikkunExportPageSize pageSize;
  final TikkunFontLoader loadFont;

  /// משפחות שמנסים כשגופן המילה חסר גליף — קודם גופן הטור השני, ואז גופן
  /// ברירת המחדל של התוכנה שמכסה ספרות ואותיות לטיניות.
  final List<String> fallbackFamilies;

  final PdfDocument _document = PdfDocument();
  final Map<String, _ExportFont?> _fonts = {};

  TikkunVectorPdfWriter({
    required this.pageSize,
    this.loadFont = loadTikkunExportFont,
    this.fallbackFamilies = const [AppFonts.defaultFont],
  });

  double get _usableWidth => pageSize.widthPt - 2 * kTikkunExportMarginPt;

  double get _usableHeight => pageSize.heightPt - 2 * kTikkunExportMarginPt;

  /// קנה המידה (נקודות לפיקסל לוגי) שבו העמוד נכנס בשטח השמיש.
  double scaleFor(TikkunVectorPage page) => math.min(
    _usableWidth / page.width,
    _usableHeight / page.height,
  );

  /// כותב את [pages] ומחזיר את בייטי המסמך. עם [unifyScale] כל העמודים
  /// מוקטנים לקנה המידה של הצפוף ביותר, כדי שעמוד קצר לא ייצא רחב מהאחרים.
  Future<Uint8List> write(
    List<TikkunVectorPage> pages, {
    required bool unifyScale,
  }) async {
    final scales = pages.map(scaleFor).toList();
    if (unifyScale && scales.isNotEmpty) {
      final shared = scales.reduce(math.min);
      scales.fillRange(0, scales.length, shared);
    }
    try {
      for (var i = 0; i < pages.length; i++) {
        await _writePage(pages[i], scales[i]);
      }
      return await _document.save();
    } finally {
      for (final font in _fonts.values) {
        font?.shaper.dispose();
      }
      _fonts.clear();
    }
  }

  Future<void> _writePage(TikkunVectorPage page, double scale) async {
    final pdfPage = PdfPage(
      _document,
      pageFormat: PdfPageFormat(pageSize.widthPt, pageSize.heightPt),
    );
    final g = pdfPage.getGraphics();
    // התוכן ממורכז לרוחב וצמוד לשוליים העליונים.
    final originX = (pageSize.widthPt - page.width * scale) / 2;
    final top = pageSize.heightPt - kTikkunExportMarginPt;

    for (final rect in page.rects) {
      g.setFillColor(PdfColor.fromInt(rect.color.toARGB32()));
      g.drawRect(
        originX + rect.rect.left * scale,
        top - rect.rect.bottom * scale,
        rect.rect.width * scale,
        rect.rect.height * scale,
      );
      g.fillPath();
    }

    TikkunTextOp? previous;
    for (final op in page.texts) {
      final resolved = await _resolve(op);
      if (resolved == null) {
        previous = null;
        continue;
      }
      final (font, run, syntheticBold) = resolved;
      _writeWordSpace(
        g,
        font,
        previous,
        op,
        originX: originX,
        top: top,
        scale: scale,
      );
      previous = op;
      final fontSize = op.fontSize * scale;
      final x = originX + op.left * scale;
      final y = top - op.baseline * scale;

      g.saveContext();
      final mirror = op.mirrorCenter;
      if (mirror != null) {
        final cx = originX + mirror * scale;
        g.setTransform(
          Matrix4(-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 2 * cx, 0, 0, 1),
        );
      }
      if (op.italic) {
        g.setTransform(
          Matrix4(
            1,
            0,
            0,
            0, //
            _kItalicSkew,
            1,
            0,
            0, //
            0,
            0,
            1,
            0, //
            -_kItalicSkew * y,
            0,
            0,
            1,
          ),
        );
      }
      final color = PdfColor.fromInt(op.color.toARGB32());
      g.setFillColor(color);
      var mode = PdfTextRenderingMode.fill;
      if (syntheticBold) {
        g.setStrokeColor(color);
        g.setLineWidth(fontSize * _kSyntheticBoldStroke);
        mode = PdfTextRenderingMode.fillAndStroke;
      }
      font.pdfFont.drawShapedRun(
        g,
        run,
        x: x,
        y: y,
        fontSize: fontSize,
        mode: mode,
      );
      if (op.underline) {
        g.drawRect(
          x,
          y - fontSize * 0.15,
          run.advanceAt(fontSize),
          fontSize * 0.05,
        );
        g.fillPath();
      }
      g.restoreContext();
    }
  }

  /// כותב גליף רווח בין [op] לשכנתה בשורה.
  ///
  /// כל מילה היא פעולת ציור לעצמה, והיישור נעשה במיקומים ולא ברווחים; בלי
  /// הגליף הזה בזרם התוכן אין גבול מילה, וההעתקה מה-PDF תלויה בהיוריסטיקת
  /// הרווחים של הקורא. הרווח נכתב לפני המילה כדי שסדר החילוץ יישאר סדר
  /// הקריאה, ומונח בחלל שבין שתי התיבות.
  void _writeWordSpace(
    PdfGraphics g,
    _ExportFont font,
    TikkunTextOp? previous,
    TikkunTextOp op, {
    required double originX,
    required double top,
    required double scale,
  }) {
    if (previous == null) return;
    if ((op.baseline - previous.baseline).abs() > _kSameLineTolerance) return;
    final space = font.spaceRun;
    if (space == null) return;

    final leftBox = op.left < previous.left ? op : previous;
    final rightBox = op.left < previous.left ? previous : op;
    if (rightBox.left - leftBox.right < op.fontSize * _kMinWordGapEm) return;

    font.pdfFont.drawShapedRun(
      g,
      space,
      x: originX + leftBox.right * scale,
      y: top - op.baseline * scale,
      fontSize: op.fontSize * scale,
    );
  }

  /// הגופן והריצה המעוצבת של [op]: המשפחה המבוקשת, ואם חסר בה גליף —
  /// החלופות לפי הסדר. הערך השלישי מסמן בולד שיש לסנתז.
  Future<(_ExportFont, ShapedRun, bool)?> _resolve(TikkunTextOp op) async {
    (_ExportFont, ShapedRun, bool)? lastResort;
    final families = <String>{
      if (op.style.fontFamily != null) op.style.fontFamily!,
      ...fallbackFamilies,
    };
    for (final family in families) {
      for (final bold in [if (op.bold) true, false]) {
        final font = await _font(family, bold: bold);
        if (font == null) continue;
        final run = font.shaper.shape(
          op.text,
          rtl: op.rtl,
          script: op.rtl ? 'hebr' : 'latn',
        );
        final candidate = (font, run, op.bold && !bold);
        if (_covers(run)) return candidate;
        lastResort ??= candidate;
      }
    }
    return lastResort;
  }

  Future<_ExportFont?> _font(String family, {required bool bold}) async {
    final key = '$family|$bold';
    if (_fonts.containsKey(key)) return _fonts[key];
    _ExportFont? font;
    final bytes = await loadFont(family, bold: bold);
    if (bytes != null) {
      final shaper = ShaperFont.register(bytes);
      font = _ExportFont(
        shaper,
        PdfShapedFont(_document, shaper: shaper, fontBytes: bytes),
      );
    }
    return _fonts[key] = font;
  }

  static bool _covers(ShapedRun run) {
    for (var i = 0; i < run.glyphCount; i++) {
      if (run.glyphId(i) == 0) return false;
    }
    return run.isNotEmpty;
  }
}
