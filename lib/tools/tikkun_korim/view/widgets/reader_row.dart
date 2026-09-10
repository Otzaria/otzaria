/// שורה בעמוד התיקון: טור סת"ם | טור מסמנים | טור מנוקד.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/nikud_word.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/stam_word.dart';

/// שיעור הפרשה המרונדר — וגם החלל המזערי שחייב להישאר בסוף שורת פתוחה כדי
/// שהיא תיראה פתוחה. נגזר מאותו שיעור של המנוע, כדי שהעימוד והתצוגה יסכימו.
double tikkunSetumaGapWidth(TextStyle style) =>
    tikkunWordWidth(kTikkunSetumaGapWord, style) * kTikkunSetumaGapWordCount +
    (style.fontSize ?? 0) *
        kTikkunWordGapAllowanceEm *
        (kTikkunSetumaGapWordCount - 1);

/// הרווח המזערי בין מילים בשורת פתוחה ובשורה חלקית (ב-em).
const double kTikkunPetuchaMinGapEm = 0.4;
const double kTikkunPartialMinGapEm = 0.6;

/// הרווח הבסיסי בין מילים, והתקרה להרחבתו בתאי השירות (ב-em).
const double kTikkunWordGapEm = 0.15;
const double kTikkunSpecialMaxGapEm = 0.5;

/// בונה את תוכן אחד הטורים. [contentWidth] הוא הרוחב הפנימי של הטור,
/// אחרי הריפוד — ממנו נגזרים כל הרווחים באחוזים.
typedef TikkunColumnBuilder =
    Widget Function(BuildContext context, double contentWidth, bool isStam);

/// רוחב טור אחד בתוך שורה שרוחבה [rowWidth].
double tikkunColumnWidth(
  double rowWidth,
  TikkunRenderMetrics metrics,
  TikkunSettings settings,
) {
  final free = rowWidth - metrics.markersWidth - metrics.columnGap * 2;
  final width = settings.showsSingleCenteredColumn ? free : free / 2;
  return width.clamp(0.0, rowWidth);
}

/// רוחב התוכן של טור — מקור יחיד גם לשורה עצמה וגם לחישוב הרווח הממוצע.
double tikkunColumnContentWidth({
  required double rowWidth,
  required TikkunRenderMetrics metrics,
  required TikkunSettings settings,
  required bool isStam,
  required bool hideNikud,
}) {
  final showNikudBorder = !isStam && !settings.hideRowBorders && !hideNikud;
  // הגבול של טור המנוקד גוזל 2px מרוחב התוכן — בלי זה כל האחוזים
  // בשורות המיוחדות חורגים.
  return (tikkunColumnWidth(rowWidth, metrics, settings) -
          metrics.em(0.5) * 2 -
          (showNikudBorder ? 2 : 0))
      .clamp(0.0, rowWidth);
}

/// הרווח הממוצע בין מילים בשורות המיושרות של העמוד, לכל טור בנפרד.
@immutable
class TikkunGapAverages {
  final double? stam;
  final double? nikud;

  const TikkunGapAverages({this.stam, this.nikud});

  static const TikkunGapAverages none = TikkunGapAverages();

  double? forColumn(bool isStam) => isStam ? stam : nikud;
}

/// מחשב את הרווח הממוצע של שורות העמוד — פעם אחת לעמוד, לא בכל build.
TikkunGapAverages computeTikkunGapAverages({
  required List<TikkunLine> lines,
  required TikkunRenderMetrics metrics,
  required TikkunSettings settings,
  required double rowWidth,
  required bool hideNikud,
  bool maskDivineName = false,
}) {
  double? averageFor(bool isStam) {
    final style = isStam ? metrics.stamStyle() : metrics.nikudStyle();
    final contentWidth = tikkunColumnContentWidth(
      rowWidth: rowWidth,
      metrics: metrics,
      settings: settings,
      isStam: isStam,
      hideNikud: hideNikud,
    );
    if (contentWidth <= 0) return null;
    var sum = 0.0;
    var count = 0;
    for (final line in lines) {
      if (line.isSpecial || line.isEmpty) continue;
      if (line.layout == LineLayout.petucha ||
          line.layout == LineLayout.partial) {
        continue;
      }
      final widths = tikkunLineItemWidths(
        words: line.words,
        style: style,
        contentWidth: contentWidth,
        isStam: isStam,
        maskDivineName: maskDivineName,
      );
      if (widths.length < 2) continue;
      final used = widths.fold(0.0, (a, b) => a + b);
      final gap = (contentWidth - used) / (widths.length - 1);
      if (gap <= 0) continue;
      sum += gap;
      count++;
    }
    return count == 0 ? null : sum / count;
  }

  return TikkunGapAverages(stam: averageFor(true), nikud: averageFor(false));
}

/// המעטפת המשותפת לכל שורה — מיקום הטורים, הסתרה, מירכוז וגבולות.
class TikkunRowShell extends StatelessWidget {
  final TikkunRenderMetrics metrics;
  final TikkunSettings settings;
  final bool hideStam;
  final bool hideNikud;
  final TikkunColumnBuilder columnBuilder;
  final Widget markers;

  const TikkunRowShell({
    super.key,
    required this.metrics,
    required this.settings,
    required this.hideStam,
    required this.hideNikud,
    required this.columnBuilder,
    required this.markers,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lineSpacing = settings.resolvedLineSpacing;
    final centered = settings.showsSingleCenteredColumn;

    return LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        final gap = metrics.columnGap;
        final columnWidth = tikkunColumnWidth(total, metrics, settings);
        final padding = metrics.em(0.5);

        Widget column(bool isStam) {
          final hidden = isStam ? hideStam : hideNikud;
          if (hidden && centered) return const SizedBox.shrink();
          final showNikudBorder =
              !isStam && !settings.hideRowBorders && !hideNikud;
          final contentWidth = tikkunColumnContentWidth(
            rowWidth: total,
            metrics: metrics,
            settings: settings,
            isStam: isStam,
            hideNikud: hideNikud,
          );
          final child = Container(
            width: columnWidth,
            padding: EdgeInsets.symmetric(horizontal: padding),
            decoration: showNikudBorder
                ? BoxDecoration(
                    // הגבול תמיד בצד שפונה אל טור הסת"ם, גם כשהטורים מוחלפים.
                    border: BorderDirectional(
                      start: settings.swapColumns
                          ? BorderSide.none
                          : BorderSide(color: cs.outlineVariant, width: 2),
                      end: settings.swapColumns
                          ? BorderSide(color: cs.outlineVariant, width: 2)
                          : BorderSide.none,
                    ),
                  )
                : null,
            child: ClipRect(
              clipper: const _HorizontalClipper(),
              child: columnBuilder(context, contentWidth, isStam),
            ),
          );
          if (!hidden) return child;
          // שומר את מקומו של הטור; באטימות אפס אין שכבת קומפוזיציה.
          return IgnorePointer(child: Opacity(opacity: 0, child: child));
        }

        // הרוחב שהטור תופס בשורה — אפס רק כשהוא מוסתר בתצוגת טור ממורכז.
        double slotWidth(bool isStam) =>
            (isStam ? hideStam : hideNikud) && centered ? 0 : columnWidth;

        Widget rowOf(List<Widget> items, CrossAxisAlignment cross) => Row(
          textDirection: settings.swapColumns
              ? TextDirection.ltr
              : TextDirection.rtl,
          mainAxisAlignment: centered
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          crossAxisAlignment: cross,
          children: items,
        );

        return Container(
          constraints: BoxConstraints(
            minHeight: metrics.minRowHeight(lineSpacing),
          ),
          margin: EdgeInsets.only(bottom: metrics.marginBottom(lineSpacing)),
          padding: EdgeInsets.only(
            bottom: settings.hideRowBorders
                ? 0
                : metrics.paddingBottom(lineSpacing),
          ),
          decoration: settings.hideRowBorders
              ? null
              : BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: cs.outlineVariant),
                  ),
                ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              rowOf([
                column(true),
                SizedBox(width: gap),
                SizedBox(width: metrics.markersWidth),
                SizedBox(width: gap),
                column(false),
              ], CrossAxisAlignment.start),
              // המסמנים בשכבה נפרדת: גובהם אינו מרווח את השורה, והם
              // ממורכזים בין קווי ההפרדה.
              Positioned.fill(
                child: rowOf([
                  SizedBox(width: slotWidth(true)),
                  SizedBox(width: gap),
                  SizedBox(
                    width: metrics.markersWidth,
                    child: OverflowBox(
                      minHeight: 0,
                      maxHeight: double.infinity,
                      alignment: Alignment.center,
                      child: markers,
                    ),
                  ),
                  SizedBox(width: gap),
                  SizedBox(width: slotWidth(false)),
                ], CrossAxisAlignment.center),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// חותך רק לרוחב הטור: ניקוד וטעמים חורגים מתיבת השורה של הגופן לגובה,
/// וחיתוך מלא היה גוזר אותם (ראה reader_row_nikud_clip_test).
class _HorizontalClipper extends CustomClipper<Rect> {
  const _HorizontalClipper();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -size.height, size.width, size.height * 2);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

/// שורה רגילה — מילים מפוזרות לרוחב הטור, עם רווחי סתומה/פתוחה.
class ReaderRow extends StatelessWidget {
  final TikkunLine line;
  final TikkunRenderMetrics metrics;
  final TikkunSettings settings;
  final bool hideStam;
  final bool hideNikud;
  final Widget markers;
  final TikkunGapAverages gaps;

  const ReaderRow({
    super.key,
    required this.line,
    required this.metrics,
    required this.settings,
    required this.hideStam,
    required this.hideNikud,
    required this.markers,
    this.gaps = TikkunGapAverages.none,
  });

  @override
  Widget build(BuildContext context) {
    return TikkunRowShell(
      metrics: metrics,
      settings: settings,
      hideStam: hideStam,
      hideNikud: hideNikud,
      markers: markers,
      columnBuilder: (context, contentWidth, isStam) => buildTikkunWordsRow(
        words: line.words,
        layout: line.layout,
        metrics: metrics,
        contentWidth: contentWidth,
        isStam: isStam,
        maskDivineName: settings.hideDivineName,
        averageGap: gaps.forColumn(isStam),
      ),
    );
  }
}

/// שורת מילים אחת בטור, לפי פריסת השורה. [averageGap] הוא הרווח הממוצע של
/// שורות העמוד — שורת פתוחה מתרווחת אליו כל עוד נשאר חלל ניכר בסופה.
Widget buildTikkunWordsRow({
  required List<LayoutWord> words,
  required LineLayout layout,
  required TikkunRenderMetrics metrics,
  required double contentWidth,
  required bool isStam,
  required bool maskDivineName,
  double factor = 1,
  double? averageGap,
}) {
  final style = isStam
      ? metrics.stamStyle(factor: factor)
      : metrics.nikudStyle(factor: factor);
  final minGap = switch (layout) {
    LineLayout.petucha => metrics.em(kTikkunPetuchaMinGapEm),
    LineLayout.partial => metrics.em(kTikkunPartialMinGapEm),
    _ => metrics.em(kTikkunWordGapEm),
  };
  final loose = layout == LineLayout.petucha || layout == LineLayout.partial;
  final spacing = loose
      ? tikkunFittedGap(
          words: words,
          style: style,
          contentWidth: contentWidth,
          availableWidth: contentWidth - tikkunSetumaGapWidth(style),
          isStam: isStam,
          maskDivineName: maskDivineName,
          minGap: minGap,
          targetGap: averageGap,
        )
      : minGap;
  // שורת סתומה עם טקסט משני צדי הרווח: העודף נבלע ברווח עצמו
  // ולא מתפזר בין המילים, כמנהג הסופרים.
  final expandGap = _setumaGapAbsorbsSlack(
    words: words,
    layout: layout,
    style: style,
    contentWidth: contentWidth,
    isStam: isStam,
    maskDivineName: maskDivineName,
    wordGap: averageGap ?? metrics.em(kTikkunWordGapEm),
  );

  final alignment = switch (layout) {
    LineLayout.petucha || LineLayout.partial => MainAxisAlignment.start,
    _ when expandGap => MainAxisAlignment.start,
    _ => MainAxisAlignment.spaceBetween,
  };

  return Row(
    mainAxisAlignment: alignment,
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    spacing: alignment == MainAxisAlignment.start
        ? (expandGap ? (averageGap ?? metrics.em(kTikkunWordGapEm)) : spacing)
        : 0,
    children: buildTikkunWordWidgets(
      words: words,
      style: style,
      metrics: metrics,
      contentWidth: contentWidth,
      isStam: isStam,
      maskDivineName: maskDivineName,
      expandGap: expandGap,
    ),
  );
}

/// האם רווח הסתומה יבלע את עודף השורה במקום לפזר אותו בין המילים.
bool _setumaGapAbsorbsSlack({
  required List<LayoutWord> words,
  required LineLayout layout,
  required TextStyle style,
  required double contentWidth,
  required bool isStam,
  required bool maskDivineName,
  required double wordGap,
}) {
  if (layout != LineLayout.setuma) return false;
  final gapIdx = words.indexWhere((w) => w.isGap);
  if (gapIdx <= 0 || gapIdx >= words.length - 1) return false;

  final widths = tikkunLineItemWidths(
    words: words,
    style: style,
    contentWidth: contentWidth,
    isStam: isStam,
    maskDivineName: maskDivineName,
  );
  if (widths.length < 3) return false;
  var used = 0.0;
  for (final w in widths) {
    used += w;
  }
  return contentWidth - used - wordGap * (widths.length - 1) > 0;
}

/// רשימת הווידג'טים של מילים ורווחים הלכתיים.
List<Widget> buildTikkunWordWidgets({
  required List<LayoutWord> words,
  required TextStyle style,
  required TikkunRenderMetrics metrics,
  required double contentWidth,
  required bool isStam,
  required bool maskDivineName,
  bool expandGap = false,
}) {
  final widgets = <Widget>[];
  for (final word in words) {
    if (word.isGap) {
      widgets.add(
        expandGap
            ? const Expanded(child: SizedBox.shrink())
            : SizedBox(width: tikkunSetumaGapWidth(style)),
      );
      continue;
    }
    if (word.isBigGap) {
      widgets.add(SizedBox(width: contentWidth * kTikkunBigGapFraction));
      continue;
    }
    final text = isStam ? word.stam : word.nikud;
    if (text.isEmpty) continue;
    final shown = maskDivineName ? maskTikkunDivineName(text) : text;
    widgets.add(
      isStam
          ? StamWord(text: shown, style: style)
          : NikudWord(text: shown, style: style),
    );
  }
  return widgets;
}

/// רוחבי הפריטים בשורה, באותו סדר ובאותם כללים של [buildTikkunWordWidgets].
List<double> tikkunLineItemWidths({
  required List<LayoutWord> words,
  required TextStyle style,
  required double contentWidth,
  required bool isStam,
  required bool maskDivineName,
}) {
  final widths = <double>[];
  for (final word in words) {
    if (word.isGap) {
      widths.add(tikkunSetumaGapWidth(style));
      continue;
    }
    if (word.isBigGap) {
      widths.add(contentWidth * kTikkunBigGapFraction);
      continue;
    }
    final text = isStam ? word.stam : word.nikud;
    if (text.isEmpty) continue;
    widths.add(
      tikkunWordWidth(
        maskDivineName ? maskTikkunDivineName(text) : text,
        style,
      ),
    );
  }
  return widths;
}

/// הרווח בין המילים כשהיעד הוא [targetGap] אך אסור לחרוג מ-[availableWidth];
/// לא פוחת מ-[minGap] ולא עולה על [maxGap].
double tikkunFittedGap({
  required List<LayoutWord> words,
  required TextStyle style,
  required double contentWidth,
  required double availableWidth,
  required bool isStam,
  required bool maskDivineName,
  required double minGap,
  double? targetGap,
  double? maxGap,
}) {
  if (targetGap == null || targetGap <= minGap) return minGap;
  final wanted = maxGap == null ? targetGap : math.min(targetGap, maxGap);
  if (wanted <= minGap) return minGap;
  final widths = tikkunLineItemWidths(
    words: words,
    style: style,
    contentWidth: contentWidth,
    isStam: isStam,
    maskDivineName: maskDivineName,
  );
  if (widths.length < 2) return minGap;
  final used = widths.fold(0.0, (a, b) => a + b);
  final free = availableWidth - used;
  if (free <= 0) return minGap;
  return math.max(minGap, math.min(wanted, free / (widths.length - 1)));
}

/// רוחב מילה מרונדרת — נמדד פעם אחת לכל (טקסט, גופן, גודל).
double tikkunWordWidth(String text, TextStyle style) {
  final key = '${style.fontFamily}|${style.fontSize}|$text';
  final cached = _wordWidthCache[key];
  if (cached != null) return cached;
  // אותם קטעים שהמרנדר מצייר — אחרת רוחב הנו"ן המנוזרת אינו נמדד כלל.
  var width = 0.0;
  for (final part in splitTikkunNun(text)) {
    final painter = TextPainter(
      text: TextSpan(
        style: style,
        children: tikkunRunSpans(splitTikkunRuns(part), style),
      ),
      textDirection: TextDirection.rtl,
    )..layout();
    width += painter.width;
    painter.dispose();
  }
  // גבול עליון פשוט — עמוד חדש מודד מחדש במקום להחזיק את כל התנ"ך בזיכרון.
  if (_wordWidthCache.length > 20000) _wordWidthCache.clear();
  _wordWidthCache[key] = width;
  return width;
}

final Map<String, double> _wordWidthCache = {};

final RegExp _divineNamePattern = RegExp(
  'י([֑-ׇֿ-]*)ה([֑-ׇֿ-]*)ו([֑-ׇֿ-]*)ה',
);

/// י-ה-ו-ה → י-ק-ו-ק, בשמירת הניקוד והטעמים שבין האותיות.
String maskTikkunDivineName(String text) => text.replaceAllMapped(
  _divineNamePattern,
  (m) => 'י${m[1]}ק${m[2]}ו${m[3]}ק',
);
