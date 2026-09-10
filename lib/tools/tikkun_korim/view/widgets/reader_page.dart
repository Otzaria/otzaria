/// עמוד (טור) התיקון — כותרת אופציונלית ורשימת השורות הגלולה.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/markers_column.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/special_row.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// מה שמוצג בעמודת המסמנים של שורה — מספר הפרק מוצג רק כשהוא חדש.
class TikkunLineMarkers {
  final int? chapterNum;
  final int? verseNum;

  const TikkunLineMarkers({this.chapterNum, this.verseNum});
}

/// מחשב לכל שורה אם להציג את מספר הפרק, בדיוק כמו `buildMarkerContent`.
List<TikkunLineMarkers> computeTikkunLineMarkers(List<TikkunLine> lines) {
  final result = <TikkunLineMarkers>[];
  int? prevChapter;
  for (final line in lines) {
    final chapter = line.firstChapterNum;
    final verse = line.firstVerseNum;
    final isNewChapter = chapter != null && chapter != prevChapter;
    result.add(
      TikkunLineMarkers(
        chapterNum: isNewChapter ? chapter : null,
        verseNum: isNewChapter ? (verse ?? 1) : verse,
      ),
    );
    if (chapter != null) prevChapter = chapter;
  }
  return result;
}

class ReaderPage extends StatefulWidget {
  final List<TikkunLine> lines;
  final TikkunSettings settings;
  final bool hideStam;
  final bool hideNikud;
  final String? headerTitle;
  final String? headerSubtitle;
  final ItemScrollController? scrollController;
  final ItemPositionsListener? positionsListener;

  const ReaderPage({
    super.key,
    required this.lines,
    required this.settings,
    required this.hideStam,
    required this.hideNikud,
    this.headerTitle,
    this.headerSubtitle,
    this.scrollController,
    this.positionsListener,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late List<TikkunLineMarkers> _markers;
  TikkunGapAverages _gaps = TikkunGapAverages.none;
  double? _gapsRowWidth;
  TikkunSettings? _gapsSettings;
  List<TikkunLine>? _gapsLines;
  bool? _gapsHideNikud;

  @override
  void initState() {
    super.initState();
    _markers = computeTikkunLineMarkers(widget.lines);
  }

  @override
  void didUpdateWidget(covariant ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lines, widget.lines)) {
      _markers = computeTikkunLineMarkers(widget.lines);
    }
  }

  /// הרווח הממוצע נמדד פעם אחת לעמוד — מדידת TextPainter לכל מילה יקרה מדי
  /// לביצוע בכל build.
  TikkunGapAverages _gapsFor(double rowWidth, TikkunRenderMetrics metrics) {
    if (_gapsRowWidth == rowWidth &&
        _gapsSettings == widget.settings &&
        identical(_gapsLines, widget.lines) &&
        _gapsHideNikud == widget.hideNikud) {
      return _gaps;
    }
    _gapsRowWidth = rowWidth;
    _gapsSettings = widget.settings;
    _gapsLines = widget.lines;
    _gapsHideNikud = widget.hideNikud;
    _gaps = computeTikkunGapAverages(
      lines: widget.lines,
      metrics: metrics,
      settings: widget.settings,
      rowWidth: rowWidth,
      hideNikud: widget.hideNikud,
      maskDivineName: widget.settings.hideDivineName,
    );
    return _gaps;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(
          0.0,
          TikkunRenderMetrics.referenceWidthFor(widget.settings),
        );
        final metrics = TikkunRenderMetrics.forWidth(width, widget.settings);
        return Column(
          children: [
            if (widget.headerTitle != null || widget.headerSubtitle != null)
              Center(
                child: SizedBox(
                  width: width,
                  child: _Header(
                    title: widget.headerTitle,
                    subtitle: widget.headerSubtitle,
                  ),
                ),
              ),
            Expanded(child: _buildList(metrics, width)),
          ],
        );
      },
    );
  }

  Widget _buildList(TikkunRenderMetrics metrics, double width) {
    final horizontal = metrics.em(kTikkunRowPaddingEm);
    final gaps = _gapsFor(math.max(0.0, width - horizontal * 2), metrics);
    return ScrollablePositionedList.builder(
      itemScrollController: widget.scrollController,
      itemPositionsListener: widget.positionsListener,
      itemCount: widget.lines.length,
      padding: EdgeInsets.symmetric(vertical: metrics.em(1)),
      // הרשימה תופסת את כל הרוחב כדי שפס הגלילה יישב בקצה החלונית;
      // מירכוז העמוד נעשה בכל שורה בנפרד.
      itemBuilder: (context, index) => Center(
        child: SizedBox(
          width: width,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal),
            child: buildTikkunLineWidget(
              line: widget.lines[index],
              markers: _markers[index],
              metrics: metrics,
              settings: widget.settings,
              hideStam: widget.hideStam,
              hideNikud: widget.hideNikud,
              gaps: gaps,
            ),
          ),
        ),
      ),
    );
  }
}

/// בונה שורה בודדת — רגילה או מיוחדת.
Widget buildTikkunLineWidget({
  required TikkunLine line,
  required TikkunLineMarkers markers,
  required TikkunRenderMetrics metrics,
  required TikkunSettings settings,
  required bool hideStam,
  required bool hideNikud,
  TikkunGapAverages gaps = TikkunGapAverages.none,
}) {
  final markersWidget = MarkersColumn(
    metrics: metrics,
    aliyaName: line.aliyaName,
    combinedAliyaName: line.combinedAliyaName,
    maftirName: line.maftirName,
    weekdayAliyaName: line.weekdayAliyaName,
    aliyaAlternative: line.aliyaAlternative,
    torahScrollLabel: line.torahScrollLabel,
    chapterNum: markers.chapterNum,
    verseNum: markers.verseNum,
  );
  if (line.isSpecial) {
    return SpecialRow(
      line: line,
      metrics: metrics,
      settings: settings,
      hideStam: hideStam,
      hideNikud: hideNikud,
      markers: markersWidget,
      gaps: gaps,
    );
  }
  return ReaderRow(
    line: line,
    metrics: metrics,
    settings: settings,
    hideStam: hideStam,
    hideNikud: hideNikud,
    markers: markersWidget,
    gaps: gaps,
  );
}

class _Header extends StatelessWidget {
  final String? title;
  final String? subtitle;

  const _Header({this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(
        children: [
          if (title != null)
            Text(
              title!,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}
