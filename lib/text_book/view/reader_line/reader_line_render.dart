/// רכיבי רינדור שמזהים שורת מקור בתוך פריט קריאה: פסקה ממוזגת, שורה
/// שמוצגת כבלוק בתוך פריט, וסמן הבחירה שבשוליים.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/book_common/selection/selection_hit_test.dart';
import 'package:otzaria/text_book/utils/reading_layout.dart';
import 'package:otzaria/text_book/view/widgets/selection_gutter_painter.dart';

/// שורת המקור שתחת נקודה בפריט קריאה.
@immutable
class ReaderLineHit {
  const ReaderLineHit({
    required this.lineIndex,
    required this.root,
    this.column,
    this.lineRange,
  });

  final int lineIndex;

  /// מיקום הנקודה בטקסט המוצג של השורה.
  final int? column;

  /// טווח השורה בטקסט ה-RenderParagraph שתחת [root]; null — השורה היא הפסקה כולה.
  final TextRange? lineRange;

  /// תת-העץ שבו נמצאת השורה, לעוזרי ה-hit-test של הבחירה.
  final RenderObject root;
}

/// שורת מקור אחת בתוך פסקה ממוזגת.
@immutable
class ReaderParagraphLineData {
  const ReaderParagraphLineData({
    required this.lineIndex,
    required this.range,
    this.background,
    this.selected = false,
  });

  final int lineIndex;

  /// טווח הטקסט של השורה (UTF-16) בטקסט הפסקה, בלי כותרת ובלי הרווח המחבר.
  final TextRange range;
  final Color? background;
  final bool selected;

  @override
  bool operator ==(Object other) =>
      other is ReaderParagraphLineData &&
      other.lineIndex == lineIndex &&
      other.range == range &&
      other.background == background &&
      other.selected == selected;

  @override
  int get hashCode => Object.hash(lineIndex, range, background, selected);
}

/// נושא את מפת השורות של פסקה ממוזגת ומצייר את רקע השורות המודגשות.
class ReaderParagraphLines extends SingleChildRenderObjectWidget {
  const ReaderParagraphLines({
    super.key,
    required this.lines,
    required super.child,
  });

  final List<ReaderParagraphLineData> lines;

  @override
  RenderReaderParagraphLines createRenderObject(BuildContext context) =>
      RenderReaderParagraphLines(lines);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReaderParagraphLines renderObject,
  ) {
    renderObject.lines = lines;
  }
}

class RenderReaderParagraphLines extends RenderProxyBox {
  RenderReaderParagraphLines(this._lines);

  List<ReaderParagraphLineData> _lines;
  List<ReaderParagraphLineData> get lines => _lines;
  set lines(List<ReaderParagraphLineData> value) {
    if (listEquals(value, _lines)) return;
    _lines = value;
    _rects.clear();
    markNeedsPaint();
  }

  RenderParagraph? _paragraph;
  final Map<int, List<Rect>> _rects = {};

  @override
  void performLayout() {
    super.performLayout();
    _paragraph = null;
    _rects.clear();
  }

  RenderParagraph? get paragraph {
    final cached = _paragraph;
    if (cached != null && cached.attached) return cached;
    RenderParagraph? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderParagraph) {
        found = object;
        return;
      }
      object.visitChildren(visit);
    }

    final child = this.child;
    if (child != null) visit(child);
    return _paragraph = found;
  }

  TextRange? rangeForLine(int lineIndex) {
    for (final line in _lines) {
      if (line.lineIndex == lineIndex) return line.range;
    }
    return null;
  }

  /// מלבני השורה בגובה שורת התצוגה המלא, במרחב של הפסקה. מקטעים מופרדים
  /// (טקסט דו-כיווני) נשארים נפרדים, כדי לא לכסות את טקסט השורה השכנה.
  List<Rect> lineRects(int lineIndex) {
    final cached = _rects[lineIndex];
    if (cached != null) return cached;
    final range = rangeForLine(lineIndex);
    final paragraph = this.paragraph;
    if (range == null ||
        paragraph == null ||
        !paragraph.hasSize ||
        range.isCollapsed) {
      return const [];
    }
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
      boxHeightStyle: ui.BoxHeightStyle.max,
    );
    final rows = <Rect>[];
    for (final box in boxes) {
      final rect = box.toRect();
      final row = rows.indexWhere(
        (r) =>
            (r.top - rect.top).abs() < 0.5 &&
            (r.bottom - rect.bottom).abs() < 0.5 &&
            rect.left <= r.right + 0.5 &&
            rect.right >= r.left - 0.5,
      );
      if (row < 0) {
        rows.add(rect);
      } else {
        rows[row] = rows[row].expandToInclude(rect);
      }
    }
    final transform = paragraph.getTransformTo(this);
    final result = [
      for (final rect in rows) MatrixUtils.transformRect(transform, rect),
    ];
    _rects[lineIndex] = result;
    return result;
  }

  /// הטווח האנכי של [lineIndex] במרחב של הפסקה הזו; לשורה ריקה — שורת הסמן.
  ({double top, double bottom})? lineExtent(int lineIndex) {
    final rects = lineRects(lineIndex);
    if (rects.isEmpty) {
      final range = rangeForLine(lineIndex);
      final paragraph = this.paragraph;
      if (range == null || paragraph == null || !paragraph.hasSize) {
        return null;
      }
      final position = TextPosition(offset: range.start);
      final caret = paragraph.getOffsetForCaret(position, Rect.zero);
      final height = paragraph.getFullHeightForCaret(position);
      final rect = MatrixUtils.transformRect(
        paragraph.getTransformTo(this),
        Rect.fromLTWH(caret.dx, caret.dy, 1, height),
      );
      return (top: rect.top, bottom: rect.bottom);
    }
    var top = rects.first.top;
    var bottom = rects.first.bottom;
    for (final rect in rects.skip(1)) {
      if (rect.top < top) top = rect.top;
      if (rect.bottom > bottom) bottom = rect.bottom;
    }
    return (top: top, bottom: bottom);
  }

  /// כמו [lineExtent], אך נגמר בתחילת השורה הבאה בפסקה: שורת תצוגה משותפת
  /// שייכת לשורה שמתחילה בה, כך שהשורות מחלקות את הגובה בלי חפיפה.
  ({double top, double bottom})? flowExtent(int lineIndex) {
    final extent = lineExtent(lineIndex);
    if (extent == null) return null;
    final at = _lines.indexWhere((line) => line.lineIndex == lineIndex);
    if (at < 0 || at + 1 >= _lines.length) return extent;
    final next = lineExtent(_lines[at + 1].lineIndex);
    if (next == null || next.top >= extent.bottom) return extent;
    return (
      top: extent.top,
      bottom: next.top < extent.top ? extent.top : next.top,
    );
  }

  /// הטווח האנכי של כל שורה נבחרת, במרחב של הפסקה הזו.
  List<({double top, double bottom})> selectedExtents() => [
    for (final line in _lines)
      if (line.selected && lineRects(line.lineIndex).isNotEmpty)
        lineExtent(line.lineIndex)!,
  ];

  /// השורה שתחת [globalPosition]; נקודה בכותרת המוזרקת שייכת לשורה שאחריה.
  ReaderLineHit? locate(Offset globalPosition) {
    final paragraph = this.paragraph;
    if (paragraph == null || !paragraph.hasSize || _lines.isEmpty) return null;
    final offset = paragraph
        .getPositionForOffset(paragraph.globalToLocal(globalPosition))
        .offset;
    var line = _lines.last;
    for (final candidate in _lines) {
      if (offset <= candidate.range.end) {
        line = candidate;
        break;
      }
    }
    final column = (offset - line.range.start)
        .clamp(0, line.range.end - line.range.start)
        .toInt();
    return ReaderLineHit(
      lineIndex: line.lineIndex,
      column: column,
      lineRange: line.range,
      root: this,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    for (final line in _lines) {
      final color = line.background;
      if (color == null) continue;
      final paint = Paint()..color = color;
      for (final rect in lineRects(line.lineIndex)) {
        canvas.drawRect(rect.shift(offset), paint);
      }
    }
    super.paint(context, offset);
  }
}

/// שורת מקור שמוצגת כבלוק נפרד בתוך פריט (שורה מיושרת, טבלה וכו').
class ReaderLineBlock extends SingleChildRenderObjectWidget {
  const ReaderLineBlock({
    super.key,
    required this.lineIndex,
    this.selected = false,
    required super.child,
  });

  final int lineIndex;
  final bool selected;

  @override
  RenderReaderLineBlock createRenderObject(BuildContext context) =>
      RenderReaderLineBlock(lineIndex: lineIndex, selected: selected);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReaderLineBlock renderObject,
  ) {
    renderObject
      ..lineIndex = lineIndex
      ..selected = selected;
  }
}

class RenderReaderLineBlock extends RenderProxyBox {
  RenderReaderLineBlock({required this.lineIndex, required this._selected});

  int lineIndex;

  bool _selected;
  bool get selected => _selected;
  set selected(bool value) {
    if (value == _selected) return;
    _selected = value;
    markNeedsPaint();
  }
}

/// סמן הבחירה שבשוליים לפריט של כמה שורות: נמתח רק לאורך השורות הנבחרות.
class ReaderLineGutter extends SingleChildRenderObjectWidget {
  const ReaderLineGutter({
    super.key,
    required this.color,
    required this.selectedLines,
    required this.gutter,
    required super.child,
  });

  final Color color;

  /// משמש לזיהוי שינוי בבחירה; הציור עצמו נקרא מהשורות שבתת-העץ.
  final Set<int> selectedLines;

  /// רוחב השוליים הפנויים מימין לרכיב, שבהם מצויר הסמן.
  final double gutter;

  @override
  RenderReaderLineGutter createRenderObject(BuildContext context) =>
      RenderReaderLineGutter(
        color: color,
        selectedLines: selectedLines,
        gutter: gutter,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReaderLineGutter renderObject,
  ) {
    renderObject
      ..color = color
      ..selectedLines = selectedLines
      ..gutter = gutter;
  }
}

class RenderReaderLineGutter extends RenderProxyBox {
  RenderReaderLineGutter({
    required this._color,
    required this._selectedLines,
    required this._gutter,
  });

  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  Set<int> _selectedLines;
  set selectedLines(Set<int> value) {
    if (setEquals(value, _selectedLines)) return;
    _selectedLines = value;
    markNeedsPaint();
  }

  double _gutter;
  set gutter(double value) {
    if (value == _gutter) return;
    _gutter = value;
    markNeedsPaint();
  }

  /// מלבני הסמן במרחב של הרכיב הזה.
  @visibleForTesting
  List<Rect> barRects() {
    final rects = <Rect>[];
    final child = this.child;
    if (_selectedLines.isEmpty || child == null || !hasSize) return rects;
    void add(double top, double bottom) {
      rects.add(selectionBarRect(size.width, _gutter, top, bottom));
    }

    void visit(RenderObject object) {
      if (object is RenderReaderParagraphLines) {
        if (!object.hasSize) return;
        final transform = object.getTransformTo(this);
        for (final extent in object.selectedExtents()) {
          final rect = MatrixUtils.transformRect(
            transform,
            Rect.fromLTRB(0, extent.top, 1, extent.bottom),
          );
          add(rect.top, rect.bottom);
        }
        return;
      }
      if (object is RenderReaderLineBlock) {
        if (object.selected && object.hasSize) {
          final rect = MatrixUtils.transformRect(
            object.getTransformTo(this),
            Offset.zero & object.size,
          );
          add(rect.top, rect.bottom);
        }
        return;
      }
      object.visitChildren(visit);
    }

    visit(child);
    return rects;
  }

  void _paintBars(PaintingContext context, Offset offset) {
    final paint = Paint()..color = _color;
    for (final rect in mergeSelectionBars(barRects())) {
      context.canvas.drawRRect(selectionBarShape(rect.shift(offset)), paint);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _paintBars(context, offset);
  }
}

/// פריטי הקריאה הבנויים, למדידת שורות ולעיגון בזמן שינוי פריסה.
class ReaderItemBoxes {
  final Map<int, RenderReaderItemBox> _boxes = {};

  RenderBox? boxForItem(int item) {
    final box = _boxes[item];
    return box != null && box.attached && box.hasSize ? box : null;
  }

  /// גבולות [line] בפריט [item] כחלק מגובהו; null כשהפריט או השורה לא בנויים.
  ({double top, double bottom})? lineExtent(int item, int line) {
    final box = _boxes[item];
    if (box == null || !box.attached || !box.hasSize) return null;
    final height = box.size.height;
    if (height <= 0) return null;
    final rect = _lineRect(box, line);
    if (rect == null) return null;
    return (top: rect.top / height, bottom: rect.bottom / height);
  }

  static Rect? _lineRect(RenderBox box, int line) {
    Rect? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderReaderParagraphLines) {
        if (object.hasSize && object.rangeForLine(line) != null) {
          final extent = object.flowExtent(line);
          if (extent != null) {
            found = MatrixUtils.transformRect(
              object.getTransformTo(box),
              Rect.fromLTRB(0, extent.top, 1, extent.bottom),
            );
          }
        }
        return;
      }
      if (object is RenderReaderLineBlock) {
        if (object.lineIndex == line && object.hasSize) {
          found = MatrixUtils.transformRect(
            object.getTransformTo(box),
            Offset.zero & object.size,
          );
        }
        return;
      }
      object.visitChildren(visit);
    }

    visit(box);
    return found;
  }
}

/// עוטף פריט ברשימת הקורא — חייב להיות שורש הפריט, כי הגבולות
/// נמדדים ביחס לגובה הפריט שהרשימה מדווחת.
class ReaderItemBox extends SingleChildRenderObjectWidget {
  const ReaderItemBox({
    super.key,
    required this.item,
    required this.boxes,
    required super.child,
  });

  final int item;
  final ReaderItemBoxes boxes;

  @override
  RenderReaderItemBox createRenderObject(BuildContext context) =>
      RenderReaderItemBox(item: item, boxes: boxes);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderReaderItemBox renderObject,
  ) {
    renderObject.update(item: item, boxes: boxes);
  }
}

/// רושם רק פריטים בנויים; הרישום מוסר כשהפריט יוצא מהעץ.
Widget wrapReaderItem({
  required int item,
  required ReadingLayout layout,
  required ReaderItemBoxes boxes,
  required Widget child,
}) => ReaderItemBox(item: item, boxes: boxes, child: child);

class RenderReaderItemBox extends RenderProxyBox {
  RenderReaderItemBox({required this._item, required this._boxes});

  int _item;
  ReaderItemBoxes _boxes;

  void update({required int item, required ReaderItemBoxes boxes}) {
    if (item == _item && identical(boxes, _boxes)) return;
    _unregister();
    _item = item;
    _boxes = boxes;
    if (attached) _boxes._boxes[_item] = this;
  }

  void _unregister() {
    if (identical(_boxes._boxes[_item], this)) _boxes._boxes.remove(_item);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _boxes._boxes[_item] = this;
  }

  @override
  void detach() {
    _unregister();
    super.detach();
  }
}

/// שורת המקור שתחת [globalPosition] בתת-העץ של [root], או null כשהנקודה
/// אינה בגובה של פסקה ממוזגת או של בלוק שורה (כרטיס מפרשים, כותרת, רווח).
ReaderLineHit? readerLineAt(RenderObject root, Offset globalPosition) {
  RenderBox? hit;
  void visit(RenderObject object) {
    if (hit != null) return;
    if (object is RenderReaderParagraphLines ||
        object is RenderReaderLineBlock) {
      final box = object as RenderBox;
      if (!box.attached || !box.hasSize) return;
      final dy = box.globalToLocal(globalPosition).dy;
      if (dy >= 0 && dy <= box.size.height) hit = box;
      return;
    }
    object.visitChildren(visit);
  }

  visit(root);
  final box = hit;
  if (box is RenderReaderParagraphLines) return box.locate(globalPosition);
  if (box is RenderReaderLineBlock) {
    return ReaderLineHit(
      lineIndex: box.lineIndex,
      column: renderedTextOffsetAtPosition(
        root: box,
        globalPosition: globalPosition,
      ),
      root: box,
    );
  }
  return null;
}
