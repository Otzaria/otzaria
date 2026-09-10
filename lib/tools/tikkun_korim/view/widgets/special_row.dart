/// שורה מיוחדת (שירה / רשימה) — פריסה דו-טורית זהה בסת"ם ובמנוקד.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';

/// הרווח המזערי בין מילים בתא של שורה מיוחדת, ביחס לגופן הטקסט עצמו —
/// רווח שנגזר מגופן השורה (16px) נעלם ליד אותיות של 25px.
const double kTikkunCellMinGapEm = 0.2;

class SpecialRow extends StatelessWidget {
  final TikkunLine line;
  final TikkunRenderMetrics metrics;
  final TikkunSettings settings;
  final bool hideStam;
  final bool hideNikud;
  final Widget markers;
  final TikkunGapAverages gaps;

  const SpecialRow({
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
    final classes = line.cssClasses;
    final factor = tikkunCompactFactor(classes);
    return TikkunRowShell(
      metrics: metrics,
      settings: settings,
      hideStam: hideStam,
      hideNikud: hideNikud,
      markers: markers,
      columnBuilder: (context, contentWidth, isStam) => _buildColumn(
        contentWidth: contentWidth,
        isStam: isStam,
        factor: factor,
        classes: classes,
      ),
    );
  }

  /// הרווח בתא: הרווח הממוצע של העמוד, מוקטן עד שהמילים נכנסות ברוחב התא.
  double _cellGap({
    required List<LayoutWord> words,
    required TextStyle style,
    required double contentWidth,
    required double available,
    required bool isStam,
  }) => tikkunFittedGap(
    words: words,
    style: style,
    contentWidth: contentWidth,
    availableWidth: available,
    isStam: isStam,
    maskDivineName: settings.hideDivineName,
    minGap: (style.fontSize ?? metrics.rowFontSize) * kTikkunCellMinGapEm,
    targetGap: gaps.forColumn(isStam),
    maxGap: metrics.em(kTikkunSpecialMaxGapEm),
  );

  /// המקדם שבו יש לצמצם את הכתב כדי שכל תא בשורה יישב בשורה אחת (עד 1).
  double _rowFitFactor(
    double contentWidth,
    TextStyle style,
    bool isStam,
    Set<String> classes,
  ) {
    final groups = _cellGroups(contentWidth, classes);
    double naturalWidth(List<LayoutWord> words, TextStyle s) {
      final widths = tikkunLineItemWidths(
        words: words,
        style: s,
        contentWidth: contentWidth,
        isStam: isStam,
        maskDivineName: settings.hideDivineName,
      );
      final minGap = (s.fontSize ?? metrics.rowFontSize) * kTikkunCellMinGapEm;
      return widths.fold(0.0, (a, b) => a + b) + minGap * (widths.length - 1);
    }

    // מדידת טקסט אינה ליניארית בגודל הגופן, ולכן מודדים שוב בגודל המצומצם.
    var fit = 1.0;
    var current = style;
    for (var pass = 0; pass < 2; pass++) {
      var passFit = 1.0;
      for (final (words, available) in groups) {
        if (words == null || words.isEmpty || available <= 0) continue;
        // רווח-תא אחד של אוויר בקצה, כדי שעיגולי המדידה לא יגלישו מילה.
        final natural =
            naturalWidth(words, current) +
            (current.fontSize ?? metrics.rowFontSize) * kTikkunCellMinGapEm;
        if (natural > available) {
          passFit = math.min(passFit, available / natural);
        }
      }
      if (passFit >= 1) break;
      fit *= passFit;
      current = style.copyWith(fontSize: (style.fontSize ?? 0) * fit);
    }
    return fit;
  }

  /// התאים של השורה עם הרוחב העומד לרשות כל אחד — באותה חלוקה שבה הם נבנים.
  List<(List<LayoutWord>?, double)> _cellGroups(
    double contentWidth,
    Set<String> classes,
  ) {
    final cells = line.cells;
    if (cells != null) {
      final half = cells.length ~/ 2;
      final midGap = math.max(contentWidth * 0.08, metrics.em(2));
      final groupWidth = math.max(0.0, (contentWidth - midGap) / 2);
      List<LayoutWord> flat(List<List<LayoutWord>> g) => [
        for (final c in g) ...c,
      ];
      double avail(List<List<LayoutWord>> g) => math.max(
        0.0,
        groupWidth - metrics.em(0.5) * math.max(0, g.length - 1),
      );
      return [
        (flat(cells.sublist(0, half)), avail(cells.sublist(0, half))),
        (flat(cells.sublist(half)), avail(cells.sublist(half))),
      ];
    }
    final manual = line.manualCells;
    if (line.zigzagRow == ZigzagRow.manual && manual != null) {
      final spaced =
          classes.contains('justify-cells') || classes.contains('flex-cells');
      final gap = spaced ? metrics.em(4) : 0.0;
      final available = math.max(
        0.0,
        contentWidth - gap * math.max(0, manual.length - 1),
      );
      return [
        for (final cell in manual)
          (
            cell.words,
            classes.contains('flex-cells')
                ? math.max(0.0, contentWidth - metrics.em(4))
                : available * cell.width / 100,
          ),
      ];
    }
    switch (line.zigzagRow) {
      case ZigzagRow.triple:
        return [
          (line.rightWords, contentWidth * 0.25),
          (line.centerWords, contentWidth * 0.5),
          (line.leftWords, contentWidth * 0.25),
        ];
      case ZigzagRow.single:
        return [(line.centerWords, contentWidth / 3)];
      case ZigzagRow.double:
        return [
          (line.rightWords, contentWidth * 0.5),
          (line.leftWords, contentWidth * 0.5),
        ];
      default:
        final compact = classes.contains('compact');
        final gapWidth = math.max(
          contentWidth * (compact ? 0.08 : 0.12),
          metrics.em(compact ? 2 : 3),
        );
        final side = math.max(0.0, (contentWidth - gapWidth) / 2);
        return [(line.rightWords, side), (line.leftWords, side)];
    }
  }

  Widget _buildColumn({
    required double contentWidth,
    required bool isStam,
    required double factor,
    required Set<String> classes,
  }) {
    final baseStyle = isStam
        ? metrics.stamStyle(factor: factor)
        : metrics.nikudStyle(factor: factor);
    // אריח שאינו נכנס בתאו מצמצם את כתב השורה כולה — כסופר, ולא גולש לשורה שנייה.
    final fit = _rowFitFactor(contentWidth, baseStyle, isStam, classes);
    final style = fit < 1
        ? baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 0) * fit)
        : baseStyle;
    final ch = tikkunChWidth(style);
    double cellGap(List<LayoutWord>? words, double available) => _cellGap(
      words: words ?? const [],
      style: style,
      contentWidth: contentWidth,
      available: available,
      isStam: isStam,
    );

    Widget block(
      List<LayoutWord>? words,
      WrapAlignment alignment, {
      double? width,
      required double available,
    }) {
      final spacing = cellGap(words, available);
      final content = Wrap(
        alignment: alignment,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: spacing,
        runSpacing: metrics.em(0.15),
        children: buildTikkunWordWidgets(
          words: words ?? const [],
          style: style,
          metrics: metrics,
          contentWidth: width ?? contentWidth,
          isStam: isStam,
          maskDivineName: settings.hideDivineName,
        ),
      );
      return width == null ? content : SizedBox(width: width, child: content);
    }

    if (line.cells != null) {
      return _buildQuad(contentWidth, ch, style, isStam);
    }
    if (line.zigzagRow == ZigzagRow.manual && line.manualCells != null) {
      return _buildManual(contentWidth, style, isStam, classes);
    }
    if (line.zigzagRow == ZigzagRow.triple) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          block(
            line.rightWords,
            WrapAlignment.start,
            width: contentWidth * 0.25,
            available: contentWidth * 0.25,
          ),
          block(
            line.centerWords,
            WrapAlignment.center,
            width: contentWidth * 0.5,
            available: contentWidth * 0.5,
          ),
          block(
            line.leftWords,
            WrapAlignment.end,
            width: contentWidth * 0.25,
            available: contentWidth * 0.25,
          ),
        ],
      );
    }
    if (line.zigzagRow == ZigzagRow.single) {
      // שלושת הילדים גמישים בחלקים שווים — התא המרכזי מקבל שליש מהטור.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: SizedBox(height: 0, width: ch * 2)),
          Flexible(
            child: block(
              line.centerWords,
              WrapAlignment.center,
              available: contentWidth / 3,
            ),
          ),
          Expanded(child: SizedBox(height: 0, width: ch * 2)),
        ],
      );
    }
    if (line.zigzagRow == ZigzagRow.double) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          block(
            line.rightWords,
            WrapAlignment.start,
            width: contentWidth * 0.5,
            available: contentWidth * 0.5,
          ),
          block(
            line.leftWords,
            WrapAlignment.end,
            width: contentWidth * 0.5,
            available: contentWidth * 0.5,
          ),
        ],
      );
    }
    // shira_parallel / list_pairs / list_alternating
    final compact = classes.contains('compact');
    final gapWidth = math.max(
      contentWidth * (compact ? 0.08 : 0.12),
      ch * (compact ? 2 : 3),
    );
    final sideWidth = math.max(0.0, (contentWidth - gapWidth) / 2);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: block(
            line.rightWords,
            WrapAlignment.start,
            available: sideWidth,
          ),
        ),
        SizedBox(width: gapWidth),
        Expanded(
          child: block(line.leftWords, WrapAlignment.end, available: sideWidth),
        ),
      ],
    );
  }

  /// שני זוגות תאים עם רווח אמצעי: [שם … אחד] [רווח 8%] [שם … אחד].
  Widget _buildQuad(
    double contentWidth,
    double ch,
    TextStyle style,
    bool isStam,
  ) {
    final cells = line.cells!;
    final half = cells.length ~/ 2;
    final midGap = math.max(contentWidth * 0.08, ch * 2);
    // כל אחד משני הצדדים מקבל מחצית ממה שנשאר אחרי הרווח האמצעי.
    final groupWidth = math.max(0.0, (contentWidth - midGap) / 2);

    Widget cellRow(List<List<LayoutWord>> group) {
      final between = metrics.em(0.5) * math.max(0, group.length - 1);
      final gap = _cellGap(
        words: [for (final cell in group) ...cell],
        style: style,
        contentWidth: contentWidth,
        available: math.max(0.0, groupWidth - between),
        isStam: isStam,
      );
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: metrics.em(0.5),
        children: [
          for (final cell in group)
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: gap,
              children: buildTikkunWordWidgets(
                words: cell,
                style: style,
                metrics: metrics,
                contentWidth: contentWidth,
                isStam: isStam,
                maskDivineName: settings.hideDivineName,
              ),
            ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: cellRow(cells.sublist(0, half))),
        SizedBox(width: midGap),
        Expanded(child: cellRow(cells.sublist(half))),
      ],
    );
  }

  /// פריסה ידנית: לכל תא רוחב באחוזים ויישור לפי מיקומו בשורה.
  Widget _buildManual(
    double contentWidth,
    TextStyle style,
    bool isStam,
    Set<String> classes,
  ) {
    final cells = line.manualCells!;
    final justifyCells = classes.contains('justify-cells');
    final flexCells = classes.contains('flex-cells');
    final gap = (justifyCells || flexCells) ? metrics.em(4) : 0.0;
    final available = math.max(
      0.0,
      contentWidth - gap * math.max(0, cells.length - 1),
    );

    final children = <Widget>[];
    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      final isFirst = i == 0;
      final isLast = i == cells.length - 1;
      final single = cells.length == 1;
      final alignment = single
          ? WrapAlignment.spaceBetween
          : isFirst
          ? WrapAlignment.start
          : isLast
          ? WrapAlignment.end
          : WrapAlignment.center;

      final words = buildTikkunWordWidgets(
        words: cell.words,
        style: style,
        metrics: metrics,
        contentWidth: contentWidth,
        isStam: isStam,
        maskDivineName: settings.hideDivineName,
      );
      final cellWidth = flexCells
          ? math.max(0.0, contentWidth - metrics.em(4))
          : available * cell.width / 100;
      Widget content = Wrap(
        alignment: justifyCells ? WrapAlignment.spaceBetween : alignment,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: justifyCells
            ? 0
            : _cellGap(
                words: cell.words,
                style: style,
                contentWidth: contentWidth,
                available: cellWidth,
                isStam: isStam,
              ),
        runSpacing: metrics.em(0.15),
        children: words,
      );
      if (justifyCells) {
        content = Padding(
          padding: EdgeInsetsDirectional.only(
            end: isFirst ? metrics.em(1) : 0,
            start: isLast ? metrics.em(1) : 0,
          ),
          child: content,
        );
      }
      children.add(
        flexCells
            ? ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cellWidth),
                child: content,
              )
            : SizedBox(width: cellWidth, child: content),
      );
    }

    return Row(
      mainAxisAlignment: flexCells
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: flexCells ? 0 : gap,
      children: children,
    );
  }
}
