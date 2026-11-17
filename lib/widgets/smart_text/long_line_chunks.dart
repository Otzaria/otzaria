/// שורה ארוכה מאוד מוצגת כרצף פסקאות קצרות שנבנות בהדרגה, ונשארת פריט אחד
/// ברשימה. הטקסט המחובר של המקטעים זהה לטקסט השורה.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/widgets/smart_text/selection_fill_text.dart';

/// שורה שהטקסט הגלוי שלה ארוך מזה מוצגת במקטעים.
const int kLongLineMinChars = 2 * kLongLineChunkChars;

/// האורך המשוער של מקטע; החיתוך ברווח שאחריו. לכל פסקה יש עלות קבועה
/// בפריסה מחדש (שינוי רוחב), ולכן מקטעים קטנים יותר מאטים אותה.
const int kLongLineChunkChars = 16000;

/// כמה מקטעים נבנים בכל פריים, כולל הראשון.
const int kLongLineChunksPerFrame = 1;

/// מקטעי שורה ארוכה: הספאנים ותחילת כל אחד בטקסט השורה.
@immutable
class LongLineSplit {
  const LongLineSplit._(this.text, this.chunks, this.starts);

  /// הטקסט הגלוי של השורה כולה.
  final String text;
  final List<TextSpan> chunks;
  final List<int> starts;
}

final Expando<LongLineSplit> _splitCache = Expando<LongLineSplit>(
  'longLineSplit',
);

/// מפצל את [span] (התוצר השטוח של `SimpleInlineHtml.tryParse`) למקטעים.
/// null כשהשורה קצרה או כשאין בה מקום בטוח לחיתוך.
LongLineSplit? splitLongLine(TextSpan span) {
  final cached = _splitCache[span];
  if (cached != null) return cached;
  final split = _split(span);
  if (split != null) _splitCache[span] = split;
  return split;
}

LongLineSplit? _split(TextSpan span) {
  if (span.style != null || span.recognizer != null) return null;
  final List<TextSpan> leaves;
  if (span.children == null) {
    final text = span.text;
    if (text == null) return null;
    leaves = [TextSpan(text: text)];
  } else {
    if (span.text != null) return null;
    leaves = <TextSpan>[];
    for (final child in span.children!) {
      if (child is! TextSpan ||
          child.children != null ||
          child.text == null ||
          child.recognizer != null) {
        return null;
      }
      leaves.add(child);
    }
  }
  final text = leaves.map((leaf) => leaf.text!).join();
  if (text.length <= kLongLineMinChars) return null;
  final cuts = _cutPositions(text, leaves);
  if (cuts.isEmpty) return null;

  final chunks = <TextSpan>[];
  final starts = <int>[0, ...cuts];
  var current = <TextSpan>[];
  var leafStart = 0;
  var nextCut = 0;
  for (final leaf in leaves) {
    final leafText = leaf.text!;
    final leafEnd = leafStart + leafText.length;
    var from = leafStart;
    // חיתוכים נבחרים רק בספאנים בלי עיצוב, ולכן ספאן מעוצב לא מתפצל.
    while (nextCut < cuts.length && cuts[nextCut] <= leafEnd) {
      final cut = cuts[nextCut++];
      if (cut > from) {
        current.add(
          TextSpan(text: leafText.substring(from - leafStart, cut - leafStart)),
        );
      }
      chunks.add(TextSpan(children: current));
      current = <TextSpan>[];
      from = cut;
    }
    if (from == leafStart) {
      current.add(leaf);
    } else if (from < leafEnd) {
      current.add(TextSpan(text: leafText.substring(from - leafStart)));
    }
    leafStart = leafEnd;
  }
  chunks.add(TextSpan(children: current));
  return LongLineSplit._(text, chunks, starts);
}

/// מקומות החיתוך בטקסט: אחרי רווח בספאן בלי עיצוב, מחוץ לבידוד או הטבעה
/// כיווניים, ולא לפני סימן צירוף. עדיף סוף משפט קרוב. סימן הצירוף נבדק
/// רק במועמדים בחלונות הבחירה, לא בכל רווח.
List<int> _cutPositions(String text, List<TextSpan> leaves) {
  final cuttable = Uint8List(text.length + 1);
  var depth = 0;
  var offset = 0;
  for (final leaf in leaves) {
    final leafText = leaf.text!;
    for (var i = 0; i < leafText.length; i++) {
      final c = leafText.codeUnitAt(i);
      if (_opensDirectional(c)) depth++;
      if ((c == 0x2069 || c == 0x202C) && depth > 0) depth--;
      final at = offset + i + 1;
      if (leaf.style == null && c == 0x20 && depth == 0 && at < text.length) {
        final previous = i > 0 ? leafText.codeUnitAt(i - 1) : -1;
        final sentence =
            previous == 0x2E ||
                previous == 0x3A ||
                previous == 0x3F ||
                previous == 0x21
            ? 2
            : 1;
        cuttable[at] = sentence;
      }
    }
    offset += leafText.length;
  }

  final cuts = <int>[];
  var target = kLongLineChunkChars;
  while (target < text.length - kLongLineChunkChars ~/ 4) {
    final window = math.min(text.length, target + kLongLineChunkChars ~/ 4);
    var cut = -1;
    for (var i = target; i < window; i++) {
      if (cuttable[i] == 2) {
        if (_startsWithMark(text, i)) {
          // גם החיפוש החלופי צריך לדלג על מועמד שכבר נפסל.
          cuttable[i] = 0;
          continue;
        }
        cut = i;
        break;
      }
    }
    if (cut < 0) {
      for (var i = target; i < text.length; i++) {
        if (cuttable[i] != 0 && !_startsWithMark(text, i)) {
          cut = i;
          break;
        }
      }
    }
    if (cut < 0) break;
    cuts.add(cut);
    target = cut + kLongLineChunkChars;
  }
  return cuts;
}

/// LRE RLE LRO RLO ו-LRI RLI FSI; נסגרים ב-PDF וב-PDI.
bool _opensDirectional(int c) =>
    (c >= 0x202A && c <= 0x202E && c != 0x202C) || (c >= 0x2066 && c <= 0x2068);

/// מונה קריאות ל-[_startsWithMark], לבדיקות בלבד.
@visibleForTesting
int debugMarkChecks = 0;

bool _startsWithMark(String text, int at) {
  debugMarkChecks++;
  return _mark.matchAsPrefix(text, at) != null;
}

final RegExp _mark = RegExp(r'\p{M}', unicode: true);

/// מקטע של שורה ארוכה ב-render tree: [start] הוא היסט המקטע בטקסט השורה.
class RenderLongLineChunk extends RenderProxyBox {
  RenderLongLineChunk({required this.lineText, required this.start});

  String lineText;
  int start;
}

/// טקסט השורה וההיסט של [paragraph] בתוכו, כשהפסקה היא מקטע של שורה ארוכה.
({String lineText, int start})? longLineChunkOf(RenderObject paragraph) {
  RenderObject? node = paragraph.parent;
  // בין הפסקה למקטע יש רק את ה-MouseRegion של SelectionFillText.
  for (var depth = 0; node != null && depth < 3; depth++) {
    if (node is RenderLongLineChunk) {
      return (lineText: node.lineText, start: node.start);
    }
    node = node.parent;
  }
  return null;
}

class _LongLineChunk extends SingleChildRenderObjectWidget {
  const _LongLineChunk({
    required this.lineText,
    required this.start,
    required super.child,
  });

  final String lineText;
  final int start;

  @override
  RenderLongLineChunk createRenderObject(BuildContext context) =>
      RenderLongLineChunk(lineText: lineText, start: start);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLongLineChunk renderObject,
  ) {
    renderObject
      ..lineText = lineText
      ..start = start;
  }
}

/// שורות ארוכות שבנייתן טרם הושלמה.
final Set<_LongLineChunksState> _building = {};

/// ממתין לבניית השורות הארוכות, עד [maxFrames], ומחזיר האם הייתה בנייה פעילה.
/// כשמועבר [scrollController], ממתין רק לשורות המחוברות אליו.
Future<bool> longLinesBuilt({
  int maxFrames = 240,
  ScrollController? scrollController,
  bool Function()? isCurrent,
}) async {
  bool isBuilding() => _building.any(
    (line) =>
        scrollController == null ||
        scrollController.positions.contains(line._scrollPosition),
  );
  final wasBuilding = isBuilding();
  for (
    var i = 0;
    i < maxFrames && isBuilding() && (isCurrent?.call() ?? true);
    i++
  ) {
    await WidgetsBinding.instance.endOfFrame;
  }
  return wasBuilding;
}

/// מציג את מקטעי [split] בזה אחר זה. בכל פריים נבנים
/// [kLongLineChunksPerFrame] מקטעים, כדי שהפריסה תתחלק בין כמה פריימים.
class LongLineChunks extends StatefulWidget {
  const LongLineChunks({
    super.key,
    required this.split,
    required this.style,
    this.strutStyle,
    required this.textAlign,
  });

  final LongLineSplit split;
  final TextStyle style;
  final StrutStyle? strutStyle;
  final TextAlign textAlign;

  @override
  State<LongLineChunks> createState() => _LongLineChunksState();
}

class _LongLineChunksState extends State<LongLineChunks> {
  /// מקטעים שכבר נבנו נשמרים כאותו מופע, כדי שהוספת מקטע לא תעדכן את כולם.
  final List<Widget> _built = [];
  bool _scheduled = false;
  ScrollPosition? _scrollPosition;
  int _generation = 0;

  void _setBuilding(bool value) {
    if (value) {
      _building.add(this);
    } else {
      _building.remove(this);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollPosition = Scrollable.maybeOf(context)?.position;
  }

  @override
  void dispose() {
    _setBuilding(false);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _addChunks();
  }

  @override
  void didUpdateWidget(LongLineChunks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.split, oldWidget.split) &&
        widget.style == oldWidget.style &&
        widget.strutStyle == oldWidget.strutStyle &&
        widget.textAlign == oldWidget.textAlign) {
      return;
    }
    // הדגשה חדשה באותו טקסט נבנית מחדש בבת אחת; טקסט או גופן אחר — בהדרגה.
    final keep =
        widget.split.text == oldWidget.split.text &&
            widget.style == oldWidget.style
        ? math.min(_built.length, widget.split.chunks.length)
        : 0;
    _built.clear();
    _addChunks(math.max(keep, kLongLineChunksPerFrame));
  }

  void _addChunks([int count = kLongLineChunksPerFrame]) {
    final split = widget.split;
    final end = math.min(_built.length + count, split.chunks.length);
    for (var i = _built.length; i < end; i++) {
      _built.add(
        _LongLineChunk(
          lineText: split.text,
          start: split.starts[i],
          child: SelectionFillText.rich(
            split.chunks[i],
            style: widget.style,
            strutStyle: widget.strutStyle,
            textAlign: widget.textAlign,
          ),
        ),
      );
    }
    _scheduleMore();
  }

  void _scheduleMore() {
    if (_scheduled) return;
    _scheduled = true;
    _setBuilding(true);
    final generation = ++_generation;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      if (_built.length < widget.split.chunks.length) {
        setState(_addChunks);
        return;
      }
      // הרשימה מפרסמת את המיקומים אחרי הפריסה; הניווט ממשיך בפריים הבא.
      SchedulerBinding.instance
        ..addPostFrameCallback((_) {
          if (generation == _generation) _setBuilding(false);
        })
        ..scheduleFrame();
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: List.of(_built),
  );
}
