/// איסוף פעולות ציור וקטוריות מעץ רינדור של Flutter שכבר פורסס.
///
/// הפריסה של התיקון נשארת מקור האמת למיקומים: העץ נבנה מחוץ למסך כמו לתצוגה,
/// וכאן כל פסקת טקסט וכל גבול מתורגמים לפעולות במערכת הקואורדינטות הלוגית של
/// העמוד, כדי שכותב ה-PDF יצייר אותם כטקסט אמיתי ולא כתמונה.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/rendering.dart';

/// קטע טקסט בגופן אחד, כפי שהונח על העמוד.
@immutable
class TikkunTextOp {
  final String text;

  /// הסגנון האפקטיבי — משפחה, גודל, משקל, הטיה, צבע וקישוט.
  final TextStyle style;

  /// הקצה השמאלי (החזותי) של תיבת הקטע, בפיקסלים לוגיים.
  final double left;

  /// רוחב תיבת הקטע — ממנו נגזר הטור שהקטע יושב בו והרווח עד שכנו בשורה.
  final double width;

  /// קו הבסיס של השורה שבה הקטע יושב.
  final double baseline;

  /// כיוון הקטע — עברית מימין לשמאל, ספרות ולטינית משמאל לימין.
  final bool rtl;

  /// כשהקטע מצויר בהיפוך אופקי (נו"ן מנוזרת): ה-x שסביבו הוא משתקף.
  final double? mirrorCenter;

  const TikkunTextOp({
    required this.text,
    required this.style,
    required this.left,
    required this.width,
    required this.baseline,
    required this.rtl,
    this.mirrorCenter,
  });

  /// הקצה הימני (החזותי) של תיבת הקטע.
  double get right => left + width;

  double get fontSize => style.fontSize ?? 14;

  bool get bold =>
      (style.fontWeight ?? FontWeight.normal).value >= FontWeight.w600.value;

  bool get italic => style.fontStyle == FontStyle.italic;

  bool get underline =>
      style.decoration?.contains(TextDecoration.underline) ?? false;

  ui.Color get color => style.color ?? const ui.Color(0xFF000000);

  @override
  String toString() =>
      'TikkunTextOp("$text" ${style.fontFamily} ${fontSize.toStringAsFixed(1)} '
      'left=${left.toStringAsFixed(1)} baseline=${baseline.toStringAsFixed(1)})';
}

/// חריצי הטורים של העמוד, בקואורדינטות הלוגיות שלו.
///
/// הפעולות נכתבות ל-PDF טור אחרי טור ולא שורה אחרי שורה, כי סדר זרם התוכן
/// הוא מה שקורא ה-PDF מסמן ומעתיק לפיו: בסדר עץ הרינדור כל שורה מחזיקה את
/// שני הטורים, וגרירה על טור אחד הייתה מסמנת גם את חברו.
@immutable
class TikkunPageColumns {
  /// קווי החיתוך ב-x, בסדר עולה. רשימה ריקה = טור אחד לכל רוחב העמוד.
  final List<double> cuts;

  /// כשאמת, הטור הימני נכתב ראשון — סדר הקריאה של עמוד עברי.
  final bool rightToLeft;

  /// כמה מילדיה הראשונים של עמודת העמוד אינם שורה (הכותרת). הפעולות שלהם
  /// נכתבות ראשונות ובסדר המסמך, בלי לשייך אותן לטור.
  final int leadingFullWidthChildren;

  const TikkunPageColumns({
    this.cuts = const [],
    this.rightToLeft = true,
    this.leadingFullWidthChildren = 0,
  });

  /// עמוד בלי חלוקה לטורים — הסדר שנאסף נשמר כמו שהוא.
  static const TikkunPageColumns none = TikkunPageColumns();

  /// מספר החריץ של [center] בסדר הקריאה; אפס הוא הראשון שנכתב.
  int slotOf(double center) {
    var below = 0;
    for (final cut in cuts) {
      if (center > cut) below++;
    }
    return rightToLeft ? cuts.length - below : below;
  }
}

/// מלבן מלא בצבע אחיד — קווי ההפרדה של השורות והטורים.
@immutable
class TikkunRectOp {
  final Rect rect;
  final ui.Color color;

  const TikkunRectOp(this.rect, this.color);
}

/// עמוד שנאסף: הפעולות ומידות העץ שממנו נאספו, בפיקסלים לוגיים.
@immutable
class TikkunVectorPage {
  final List<TikkunTextOp> texts;
  final List<TikkunRectOp> rects;
  final double width;
  final double height;

  const TikkunVectorPage({
    required this.texts,
    required this.rects,
    required this.width,
    required this.height,
  });

  bool get isEmpty => texts.isEmpty && rects.isEmpty;
}

/// אוסף את הטקסט והגבולות מתחת ל-[root], שכבר עבר פריסה.
///
/// תת-עצים שקופים לחלוטין (טור מוסתר ששומר את מקומו) נשמטים, וכך גם פסקת
/// המשיחה שמעבה את הגופן בתצוגה — ב-PDF הגליפים חדים בלי עיבוי.
///
/// [columns] מסדר את הפעולות בסדר הקריאה: כל טור בשלמותו, שורה אחר שורה.
TikkunVectorPage collectTikkunVectorPage(
  RenderBox root, {
  TikkunPageColumns columns = TikkunPageColumns.none,
}) {
  final rects = <TikkunRectOp>[];

  // הכותרת שלפני השורות נכתבת ראשונה ובסדר המסמך; השאר מסודר לפי טורים.
  final leading = <TikkunTextOp>[];
  final body = <TikkunTextOp>[];
  var out = columns.leadingFullWidthChildren > 0 ? leading : body;
  var splitDone = columns.leadingFullWidthChildren == 0;

  void visit(RenderObject node) {
    if (node is RenderOpacity && node.opacity == 0) return;
    if (node is RenderAnimatedOpacity && node.opacity.value == 0) return;
    if (node is RenderParagraph) {
      _collectParagraph(node, root, out);
      return;
    }
    if (node is RenderDecoratedBox) _collectBorders(node, root, rects);
    // עמודת העמוד היא ה-Flex הראשון שנפגש; ילדיה הראשונים הם הכותרת.
    if (!splitDone && node is RenderFlex) {
      splitDone = true;
      var index = 0;
      var child = node.firstChild;
      while (child != null) {
        out = index < columns.leadingFullWidthChildren ? leading : body;
        visit(child);
        child = node.childAfter(child);
        index++;
      }
      out = body;
      return;
    }
    node.visitChildren(visit);
  }

  visit(root);
  return TikkunVectorPage(
    texts: [...leading, ..._inReadingOrder(body, columns)],
    rects: rects,
    width: root.size.width,
    height: root.size.height,
  );
}

/// מסדר את [ops] טור אחר טור, ובכל טור שורה אחר שורה.
///
/// קו הבסיס מעוגל לחצי פיקסל כדי ששתי מילים באותה שורה יקבלו אותו מפתח גם
/// כשהמדידה זזה בשבריר. בתוך שורה הסדר הוא חזותי משמאל לימין — הגליפים של
/// כל מילה כבר יוצאים כך מהמעצב, וקורא ה-PDF מריץ ניתוח דו-כיווני על הרצף
/// שהוא מחלץ; שורה בסדר הקריאה הייתה יוצאת ממנו כשורה הפוכה.
List<TikkunTextOp> _inReadingOrder(
  List<TikkunTextOp> ops,
  TikkunPageColumns columns,
) {
  if (columns.cuts.isEmpty || ops.length < 2) return ops;
  final keyed =
      [
        for (var index = 0; index < ops.length; index++)
          (
            slot: columns.slotOf(ops[index].left + ops[index].width / 2),
            row: (ops[index].baseline * 2).round(),
            order: index,
            op: ops[index],
          ),
      ]..sort((a, b) {
        if (a.slot != b.slot) return a.slot - b.slot;
        if (a.row != b.row) return a.row - b.row;
        final left = a.op.left.compareTo(b.op.left);
        return left != 0 ? left : a.order - b.order;
      });
  return [for (final entry in keyed) entry.op];
}

/// אותיות לטיניות וספרות — הקטעים שכיוונם הפוך לכיוון השורה העברית.
final RegExp _ltrSegment = RegExp('[A-Za-z0-9]+');

void _collectParagraph(
  RenderParagraph paragraph,
  RenderBox root,
  List<TikkunTextOp> out,
) {
  final rootSpan = paragraph.text;
  if (rootSpan.style?.foreground?.style == PaintingStyle.stroke) return;

  final runs = _flattenRuns(rootSpan);
  if (runs.isEmpty) return;

  // מדידה מחדש באותם פרמטרים של הפסקה: המנוע זהה ולכן המיקומים זהים, וכל
  // ה-API של TextPainter פתוח לקריאה גם אחרי הפריסה.
  final constraints = paragraph.constraints;
  final wraps =
      paragraph.softWrap || paragraph.overflow == TextOverflow.ellipsis;
  final painter =
      TextPainter(
        text: rootSpan,
        textAlign: paragraph.textAlign,
        textDirection: paragraph.textDirection,
        textScaler: paragraph.textScaler,
        maxLines: paragraph.maxLines,
        ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '…' : null,
        locale: paragraph.locale,
        strutStyle: paragraph.strutStyle,
        textWidthBasis: paragraph.textWidthBasis,
        textHeightBehavior: paragraph.textHeightBehavior,
      )..layout(
        minWidth: constraints.minWidth,
        maxWidth: wraps ? constraints.maxWidth : double.infinity,
      );

  try {
    final plainLength = rootSpan.toPlainText().length;
    final allBoxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: plainLength),
      boxHeightStyle: ui.BoxHeightStyle.max,
    );
    if (allBoxes.isEmpty) return;
    final firstLineTop = allBoxes
        .map((b) => b.top)
        .reduce(
          (a, b) => a < b ? a : b,
        );
    final firstBaseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );

    final transform = paragraph.getTransformTo(root);
    final mirrored = transform.storage[0] < 0;
    final baseRtl = paragraph.textDirection == TextDirection.rtl;

    for (final run in runs) {
      for (final segment in _splitDirection(run, baseRtl)) {
        final boxes = painter.getBoxesForSelection(
          TextSelection(
            baseOffset: segment.start,
            extentOffset: segment.end,
          ),
          boxHeightStyle: ui.BoxHeightStyle.max,
        );
        for (final box in boxes) {
          final range = boxes.length == 1
              ? (segment.start, segment.end)
              : _rangeInBox(painter, box, segment.start, segment.end);
          if (range.$2 <= range.$1) continue;
          final text = run.text.substring(
            range.$1 - run.start,
            range.$2 - run.start,
          );
          if (text.trim().isEmpty) continue;

          final lineBaseline = firstBaseline + box.top - firstLineTop;
          final globalRect = MatrixUtils.transformRect(
            transform,
            box.toRect(),
          );
          final globalBaseline = MatrixUtils.transformPoint(
            transform,
            Offset(0, lineBaseline),
          ).dy;
          out.add(
            TikkunTextOp(
              text: text,
              style: run.style,
              left: globalRect.left,
              width: globalRect.width,
              baseline: globalBaseline,
              rtl: segment.rtl,
              mirrorCenter: mirrored ? globalRect.center.dx : null,
            ),
          );
        }
      }
    }
  } finally {
    painter.dispose();
  }
}

/// טווח התווים של [start]..[end] שנפל בתוך [box] — לקטע שנשבר לכמה שורות.
(int, int) _rangeInBox(
  TextPainter painter,
  ui.TextBox box,
  int start,
  int end,
) {
  final y = (box.top + box.bottom) / 2;
  final a = painter.getPositionForOffset(Offset(box.left + 0.01, y)).offset;
  final b = painter.getPositionForOffset(Offset(box.right - 0.01, y)).offset;
  final lo = (a < b ? a : b).clamp(start, end);
  final hi = (a < b ? b : a).clamp(start, end);
  return (lo, hi);
}

class _Run {
  final String text;
  final TextStyle style;
  final int start;

  const _Run(this.text, this.style, this.start);

  int get end => start + text.length;
}

class _Segment {
  final int start;
  final int end;
  final bool rtl;

  const _Segment(this.start, this.end, this.rtl);
}

/// קטעי הטקסט של הפסקה עם הסגנון האפקטיבי של כל אחד, לפי היסט בטקסט הפשוט.
List<_Run> _flattenRuns(InlineSpan root) {
  final runs = <_Run>[];
  var cursor = 0;

  void walk(InlineSpan span, TextStyle? inherited) {
    final style = inherited == null
        ? span.style
        : (span.style == null ? inherited : inherited.merge(span.style));
    if (span is TextSpan) {
      final text = span.text;
      if (text != null && text.isNotEmpty) {
        runs.add(_Run(text, style ?? const TextStyle(), cursor));
        cursor += text.length;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child, style);
      }
    } else {
      // Placeholder — תו אחד (U+FFFC) בטקסט הפשוט, בלי טקסט לצייר.
      cursor += 1;
    }
  }

  walk(root, null);
  return runs;
}

List<_Segment> _splitDirection(_Run run, bool baseRtl) {
  if (!baseRtl) return [_Segment(run.start, run.end, false)];
  final segments = <_Segment>[];
  var cursor = 0;
  for (final match in _ltrSegment.allMatches(run.text)) {
    if (match.start > cursor) {
      segments.add(_Segment(run.start + cursor, run.start + match.start, true));
    }
    segments.add(
      _Segment(run.start + match.start, run.start + match.end, false),
    );
    cursor = match.end;
  }
  if (cursor < run.text.length) {
    segments.add(_Segment(run.start + cursor, run.end, true));
  }
  return segments;
}

void _collectBorders(
  RenderDecoratedBox node,
  RenderBox root,
  List<TikkunRectOp> out,
) {
  final decoration = node.decoration;
  if (decoration is! BoxDecoration) return;
  final border = decoration.border;
  if (border == null) return;

  final direction = node.configuration.textDirection ?? TextDirection.rtl;
  final rect = MatrixUtils.transformRect(
    node.getTransformTo(root),
    Offset.zero & node.size,
  );

  void side(BorderSide s, Rect strip) {
    if (s.style == BorderStyle.none || s.width <= 0) return;
    out.add(TikkunRectOp(strip, s.color));
  }

  final BorderSide top, bottom, left, right;
  if (border is Border) {
    top = border.top;
    bottom = border.bottom;
    left = border.left;
    right = border.right;
  } else if (border is BorderDirectional) {
    top = border.top;
    bottom = border.bottom;
    final isRtl = direction == TextDirection.rtl;
    left = isRtl ? border.end : border.start;
    right = isRtl ? border.start : border.end;
  } else {
    return;
  }

  side(top, Rect.fromLTWH(rect.left, rect.top, rect.width, top.width));
  side(
    bottom,
    Rect.fromLTWH(
      rect.left,
      rect.bottom - bottom.width,
      rect.width,
      bottom.width,
    ),
  );
  side(left, Rect.fromLTWH(rect.left, rect.top, left.width, rect.height));
  side(
    right,
    Rect.fromLTWH(rect.right - right.width, rect.top, right.width, rect.height),
  );
}
