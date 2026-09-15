/// שורה מיוחדת (שירה / רשימה) — פריסה דו-טורית זהה בסת"ם ובמנוקד.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tikkun_processor.dart'
    show kTikkunShiraMinCondense;
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';

/// הרווח המזערי בין תיבות בתא של שורה מיוחדת: מלוא אות קטנה, הנמדדת מן
/// הכתב עצמו ולכן מתאימה את עצמה לגופן.
double tikkunCellMinGap(TextStyle style) => tikkunWordWidth('י', style);

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
    return TikkunRowShell(
      metrics: metrics,
      settings: settings,
      hideStam: hideStam,
      hideNikud: hideNikud,
      markers: markers,
      columnBuilder: (context, contentWidth, isStam) => _buildColumn(
        contentWidth: contentWidth,
        isStam: isStam,
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
    minGap: tikkunCellMinGap(style),
    targetGap: gaps.forColumn(isStam),
    maxGap: metrics.em(kTikkunSpecialMaxGapEm),
  );

  /// הרווח בין טורי השירה: שיעור הפרשה, הנמדד מן הכתב עצמו ולכן מתאים את
  /// עצמו לגופן. קבוע לכל השורות, כמו הרווח שבין טורי השירה בספר תורה.
  double _manualGap(Set<String> classes, TextStyle baseStyle) {
    if (classes.contains('justify-cells')) {
      return tikkunSetumaGapWidth(baseStyle) * line.cellGapFactor;
    }
    if (classes.contains('flex-cells')) return metrics.em(4);
    return 0;
  }

  /// המקדם שבו יש לצמצם את הכתב כדי שכל תא בשורה יישב בשורה אחת (עד 1).
  double _rowFitFactor(
    double contentWidth,
    TextStyle style,
    bool isStam,
    Set<String> classes,
  ) {
    final groups = _cellGroups(contentWidth, classes, style);
    double naturalWidth(List<LayoutWord> words, TextStyle s) {
      final widths = tikkunLineItemWidths(
        words: words,
        style: s,
        contentWidth: contentWidth,
        isStam: isStam,
        maskDivineName: settings.hideDivineName,
      );
      final minGap = tikkunCellMinGap(s);
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
            naturalWidth(words, current) + tikkunCellMinGap(current);
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

  /// הכיווץ האופקי שבו כתב השורה נכנס (עד 1). באריחי שירה נמדד כל הכתב מול
  /// השורה פחות שיעור סתומה של רווח, שהרי הרווחים שביניהם מצטמצמים תחילה.
  double _rowCondense(
    double contentWidth,
    TextStyle style,
    Set<String> classes,
  ) {
    final air = tikkunCellMinGap(style);
    final groups = _cellGroups(contentWidth, classes, style);
    List<double> itemsOf(List<LayoutWord> words) => tikkunLineItemWidths(
      words: words,
      style: style,
      contentWidth: contentWidth,
      isStam: true,
      maskDivineName: settings.hideDivineName,
    );
    if (_isBrickRow(classes)) {
      var used = 0.0;
      var fixed = tikkunSetumaGapWidth(style);
      for (final (words, _) in groups) {
        if (words == null || words.isEmpty) continue;
        final widths = itemsOf(words);
        used += widths.fold(0.0, (a, b) => a + b);
        fixed += air * math.max(0, widths.length - 1) + 0.5;
      }
      final room = contentWidth - fixed;
      return used > room ? math.max(0.0, room / used) : 1.0;
    }
    var condense = 1.0;
    for (final (words, available) in groups) {
      if (words == null || words.isEmpty || available <= 0) continue;
      final widths = itemsOf(words);
      final used = widths.fold(0.0, (a, b) => a + b);
      final room = available - air * widths.length;
      if (used > room) {
        condense = math.min(condense, math.max(0.0, room / used));
      }
    }
    return condense;
  }

  /// שורת אריחים: תאים ידניים שאינם מיושרים — הרווח שביניהם מצטמצם.
  bool _isBrickRow(Set<String> classes) =>
      line.zigzagRow == ZigzagRow.manual &&
      (line.manualCells?.length ?? 0) >= 2 &&
      !classes.contains('justify-cells') &&
      !classes.contains('flex-cells');

  /// התאים של השורה עם הרוחב העומד לרשות כל אחד — באותה חלוקה שבה הם נבנים.
  List<(List<LayoutWord>?, double)> _cellGroups(
    double contentWidth,
    Set<String> classes,
    TextStyle baseStyle,
  ) {
    final cells = line.cells;
    if (cells != null) {
      final half = cells.length ~/ 2;
      final midGap = math.max(
        contentWidth * 0.08,
        tikkunChWidth(baseStyle) * 2,
      );
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
      final gap = _manualGap(classes, baseStyle);
      final available = math.max(
        0.0,
        contentWidth - gap * math.max(0, manual.length - 1),
      );
      return [
        for (var i = 0; i < manual.length; i++)
          (
            manual[i].words,
            classes.contains('flex-cells')
                ? math.max(0.0, contentWidth - metrics.em(4))
                : available * manual[i].width / 100,
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
          tikkunChWidth(baseStyle) * (compact ? 2 : 3),
        );
        final side = math.max(0.0, (contentWidth - gapWidth) / 2);
        return [(line.rightWords, side), (line.leftWords, side)];
    }
  }

  Widget _buildColumn({
    required double contentWidth,
    required bool isStam,
    required Set<String> classes,
  }) {
    // הכתב בקטע מיוחד בגודל מלא; מצטמצם רק כשתא אינו נכנס ברוחבו.
    final baseStyle = isStam ? metrics.stamStyle() : metrics.nikudStyle();
    // אריח שאינו נכנס בתאו מצמצם את כתב השורה כולה — כסופר, ולא גולש לשורה שנייה.
    // בסת"ם, עד שיעור הדחיסה של השירה, נדחסות האותיות במקום שהכתב יקטן.
    final manual =
        line.zigzagRow == ZigzagRow.manual && line.manualCells != null;
    final justifyCells = classes.contains('justify-cells');
    var condense = isStam && manual && !justifyCells
        ? _rowCondense(contentWidth, baseStyle, classes)
        : 1.0;
    if (condense < kTikkunShiraMinCondense) condense = 1;
    final fit = isStam && (justifyCells || condense < 1)
        ? 1.0
        : _rowFitFactor(contentWidth, baseStyle, isStam, classes);
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
      return _buildManual(
        contentWidth,
        style,
        baseStyle,
        isStam,
        classes,
        condense,
      );
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

  /// פריסת אריחי שירה: לכל תא הרווח שלפניו ורוחב הכתב שבו. הכתב צמוד לצדדי
  /// הטור, וכל המרווח שנותר מתחלק בין האריחים ביחס שבתבנית — כבספר תורה.
  List<({double gap, double width})> _brickLayout({
    required double contentWidth,
    required TextStyle style,
    required bool isStam,
    required double condense,
    required List<double> spacings,
  }) {
    final cells = line.manualCells!;
    final natural = <double>[];
    final nominal = <double>[];
    var offset = 0.0;
    var previousEnd = 0.0;
    for (var i = 0; i < cells.length; i++) {
      final widths = tikkunLineItemWidths(
        words: cells[i].words,
        style: style,
        contentWidth: contentWidth,
        isStam: isStam,
        maskDivineName: settings.hideDivineName,
      );
      // חצי פיקסל של אוויר: עיגול המדידה אינו מפיל תיבה לשורה שנייה.
      final nat =
          widths.fold(0.0, (a, b) => a + b) * condense +
          spacings[i] * math.max(0, widths.length - 1) +
          0.5;
      final cellWidth = contentWidth * cells[i].width / 100;
      final align = i == 0
          ? 0.0
          : i == cells.length - 1
          ? 1.0
          : 0.5;
      final start = offset + (cellWidth - nat) * align;
      natural.add(nat);
      nominal.add(i == 0 ? 0.0 : math.max(0.0, start - previousEnd));
      previousEnd = start + nat;
      offset += cellWidth;
    }
    final free = math.max(
      0.0,
      contentWidth - natural.fold(0.0, (a, b) => a + b),
    );
    final total = nominal.fold(0.0, (a, b) => a + b);
    return [
      for (var i = 0; i < cells.length; i++)
        (
          gap: total == 0
              ? free / math.max(1, cells.length - 1)
              : free * nominal[i] / total,
          width: natural[i],
        ),
    ];
  }

  /// פריסה ידנית: לכל תא רוחב באחוזים ויישור לפי מיקומו בשורה.
  Widget _buildManual(
    double contentWidth,
    TextStyle style,
    TextStyle baseStyle,
    bool isStam,
    Set<String> classes,
    double condense,
  ) {
    final cells = line.manualCells!;
    final justifyCells = classes.contains('justify-cells');
    final flexCells = classes.contains('flex-cells');
    final gap = _manualGap(classes, baseStyle);
    final available = math.max(
      0.0,
      contentWidth - gap * math.max(0, cells.length - 1),
    );
    final spacings = [
      for (final cell in cells)
        _cellGap(
          words: cell.words,
          style: style,
          contentWidth: contentWidth,
          available: available * cell.width / 100,
          isStam: isStam,
        ),
    ];
    final bricks = _isBrickRow(classes)
        ? _brickLayout(
            contentWidth: contentWidth,
            style: style,
            isStam: isStam,
            condense: condense,
            spacings: spacings,
          )
        : null;

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

      final cellWidth = flexCells
          ? math.max(0.0, contentWidth - metrics.em(4))
          : bricks?[i].width ?? available * cell.width / 100;
      // חצי שיטה מיושר נסגר כשורה רגילה: רווחים עד התקרה, ואז מתיחת אותיות.
      final words = buildTikkunWordWidgets(
        words: cell.words,
        style: style,
        metrics: metrics,
        contentWidth: contentWidth,
        isStam: isStam,
        maskDivineName: settings.hideDivineName,
        fit: justifyCells && isStam
            ? fitTikkunLine(
                words: cell.words,
                style: style,
                contentWidth: cellWidth,
                maskDivineName: settings.hideDivineName,
              )
            : TikkunLineFit(condense: condense),
      );
      final content = Wrap(
        alignment: justifyCells
            ? WrapAlignment.spaceBetween
            : bricks != null
            ? WrapAlignment.start
            : alignment,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: justifyCells ? 0 : spacings[i],
        runSpacing: metrics.em(0.15),
        children: words,
      );
      if (bricks != null && bricks[i].gap > 0) {
        children.add(SizedBox(width: bricks[i].gap));
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
