/// עמוד (טור) התיקון — כותרת אופציונלית ורשימת השורות הגלולה.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// רוחב הדף ביחס לדף רגיל — של השורה הרחבה שבו (דף שירה).
double tikkunPageWidthFactor(List<TikkunLine> lines) =>
    lines.fold(1.0, (m, l) => math.max(m, l.widthFactor));

class ReaderPage extends StatefulWidget {
  final List<TikkunLine> lines;

  /// שינוי הזום במדרגה אחת לכל כיוון, או לערך מוחלט במחוות צביטה.
  final void Function(double zoom)? onZoomChanged;
  final TikkunSettings settings;

  /// תקציב רוחב השורה שהעימוד נחתך לפיו — ממנו נגזר גודל הכתב.
  final double lineWidthEm;
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
    required this.lineWidthEm,
    required this.hideStam,
    required this.hideNikud,
    this.headerTitle,
    this.headerSubtitle,
    this.scrollController,
    this.positionsListener,
    this.onZoomChanged,
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
  final ScrollController _horizontal = ScrollController();
  bool _zoomModifier = false;
  double _pinchStartZoom = 1;

  bool _onKeyEvent(KeyEvent event) {
    final down = HardwareKeyboard.instance.isControlPressed;
    if (down != _zoomModifier && mounted) setState(() => _zoomModifier = down);
    return false;
  }

  /// מקפיץ למדרגת הזום הבאה בכיוון [direction].
  void _stepZoom(int direction) {
    final callback = widget.onZoomChanged;
    if (callback == null) return;
    final current = widget.settings.zoom;
    if (direction > 0) {
      for (final stop in kTikkunZoomStops) {
        if (stop > current + 0.001) return callback(stop);
      }
      return;
    }
    for (final stop in kTikkunZoomStops.reversed) {
      if (stop < current - 0.001) return callback(stop);
    }
  }

  @override
  void initState() {
    super.initState();
    _markers = computeTikkunLineMarkers(widget.lines);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
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
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final zoom = widget.settings.zoom;
        final metrics = TikkunRenderMetrics.forWidth(
          constraints.maxWidth.clamp(
            0.0,
            TikkunRenderMetrics.referenceWidthFor(widget.settings),
          ),
          widget.settings,
          zoom: zoom,
          lineWidthEm: widget.lineWidthEm,
          pageWidthFactor: tikkunPageWidthFactor(widget.lines),
          maxPageWidth: constraints.maxWidth,
        );
        final zoomedWidth = metrics.pageWidth * zoom;
        Widget page = Column(
          children: [
            if (widget.headerTitle != null || widget.headerSubtitle != null)
              Center(
                child: SizedBox(
                  width: zoomedWidth,
                  child: _Header(
                    title: widget.headerTitle,
                    subtitle: widget.headerSubtitle,
                  ),
                ),
              ),
            Expanded(child: _buildList(metrics, zoomedWidth)),
          ],
        );
        if (zoomedWidth > constraints.maxWidth) {
          // העמוד רחב מהחלון — גוללים אותו לרוחב, כמו הגדלה בדפדפן.
          page = Scrollbar(
            controller: _horizontal,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: zoomedWidth, child: page),
            ),
          );
        }
        // גרירה בעכבר ובמגע בשני הצירים — העמוד מתנהג כקנבס כשהוא מוגדל.
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: PointerDeviceKind.values.toSet(),
          ),
          child: _wrapZoomGestures(page),
        );
      },
    );
  }

  /// Ctrl+גלגלת ומחוות צביטה. הגלילה האנכית ננעלת כל עוד Ctrl לחוץ, אחרת
  /// הרשימה הייתה גוללת יחד עם הזום.
  Widget _wrapZoomGestures(Widget child) {
    if (widget.onZoomChanged == null) return child;
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        if (!HardwareKeyboard.instance.isControlPressed) return;
        _stepZoom(event.scrollDelta.dy < 0 ? 1 : -1);
      },
      child: RawGestureDetector(
        gestures: {
          _PinchZoomRecognizer:
              GestureRecognizerFactoryWithHandlers<_PinchZoomRecognizer>(
                _PinchZoomRecognizer.new,
                (instance) => instance
                  ..onStart = ((_) {
                    _pinchStartZoom = widget.settings.zoom;
                  })
                  ..onUpdate = (details) {
                    final zoom = (_pinchStartZoom * details.scale).clamp(
                      kTikkunMinZoom,
                      kTikkunMaxZoom,
                    );
                    widget.onZoomChanged!(zoom);
                  },
              ),
        },
        child: child,
      ),
    );
  }

  Widget _buildList(TikkunRenderMetrics metrics, double width) {
    final horizontal = metrics.em(kTikkunRowPaddingEm);
    final gaps = _gapsFor(math.max(0.0, width - horizontal * 2), metrics);
    return ScrollablePositionedList.builder(
      physics: _zoomModifier ? const NeverScrollableScrollPhysics() : null,
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

/// מזהה צביטה שמתעורר רק לשתי אצבעות — אחרת הוא היה גונב את הגלילה האנכית
/// מהרשימה כבר במגע הראשון.
class _PinchZoomRecognizer extends ScaleGestureRecognizer {
  _PinchZoomRecognizer({super.debugOwner});

  final Set<int> _pointers = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _pointers.add(event.pointer);
    if (_pointers.length < 2) return;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
    }
    super.handleEvent(event);
  }
}
