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

/// מפצל את [span] (ספאן שורה של המסלול המהיר, או פסקה של HtmlWidget)
/// למקטעים. null כשהשורה קצרה או כשאין בה מקום בטוח לחיתוך.
LongLineSplit? splitLongLine(TextSpan span) {
  final cached = _splitCache[span];
  if (cached != null) return cached;
  final split = _split(span);
  if (split != null) _splitCache[span] = split;
  return split;
}

/// טקסט של ספאן אחד (או תו מציין של WidgetSpan), ו-[cuttable] — מותר לחתוך בו.
typedef _Leaf = ({String text, bool cuttable});

LongLineSplit? _split(TextSpan span) {
  final leaves = <_Leaf>[];
  if (!_collectLeaves(span, false, leaves)) return null;
  final length = leaves.fold(0, (sum, leaf) => sum + leaf.text.length);
  if (length <= kLongLineMinChars) return null;
  final text = leaves.map((leaf) => leaf.text).join();
  final cuts = _cutPositions(text, leaves);
  if (cuts.isEmpty) return null;
  final chunks = [
    for (final (_, chunk) in _Slicer(cuts).pieces(span)) chunk as TextSpan,
  ];
  return LongLineSplit._(text, chunks, [0, ...cuts]);
}

/// ספאן עם אינטראקציה אינו נחתך, וגם לא הספאנים שבתוכו; עיצוב עובר לכל חלק.
bool _collectLeaves(InlineSpan span, bool blocked, List<_Leaf> leaves) {
  if (span is PlaceholderSpan) {
    leaves.add((
      text: String.fromCharCode(PlaceholderSpan.placeholderCodeUnit),
      cuttable: false,
    ));
    return true;
  }
  if (span is! TextSpan) return false;
  blocked =
      blocked ||
      span.recognizer != null ||
      span.onEnter != null ||
      span.onExit != null ||
      span.semanticsLabel != null;
  final text = span.text;
  if (text != null) leaves.add((text: text, cuttable: !blocked));
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (!_collectLeaves(child, blocked, leaves)) return false;
  }
  return true;
}

/// מחלק עץ ספאנים לפי [cuts]; ספאן שכולו במקטע אחד נשאר אותו מופע.
class _Slicer {
  _Slicer(this.cuts);

  final List<int> cuts;
  int _offset = 0;
  int _chunk = 0;

  /// מספר המקטע של [offset]; נקרא בסדר עולה בלבד.
  int _chunkAt(int offset) {
    while (_chunk < cuts.length && cuts[_chunk] <= offset) {
      _chunk++;
    }
    return _chunk;
  }

  /// החלקים של [span] לפי הסדר, כל אחד עם מספר המקטע שלו.
  List<(int, InlineSpan)> pieces(InlineSpan span) {
    final first = _chunkAt(_offset);
    if (span is! TextSpan) {
      _offset++;
      return [(first, span)];
    }
    final texts = <int, String>{};
    final text = span.text;
    if (text != null) {
      var from = 0;
      while (from < text.length) {
        final chunk = _chunkAt(_offset + from);
        final end = chunk < cuts.length
            ? math.min(text.length, cuts[chunk] - _offset)
            : text.length;
        texts[chunk] = text.substring(from, end);
        from = end;
      }
      _offset += text.length;
    }
    final children = <int, List<InlineSpan>>{};
    for (final child in span.children ?? const <InlineSpan>[]) {
      for (final (chunk, piece) in pieces(child)) {
        (children[chunk] ??= []).add(piece);
      }
    }
    final chunks = {...texts.keys, ...children.keys}.toList()..sort();
    if (chunks.length <= 1) return [(first, span)];
    return [
      for (final chunk in chunks)
        (
          chunk,
          TextSpan(
            text: texts[chunk],
            children: children[chunk],
            style: span.style,
            mouseCursor: span.mouseCursor,
            locale: span.locale,
            spellOut: span.spellOut,
          ),
        ),
    ];
  }
}

/// מקומות החיתוך בטקסט: אחרי רווח בספאן בלי אינטראקציה, מחוץ לבידוד או הטבעה
/// כיווניים, ולא לפני סימן צירוף. עדיף סוף משפט קרוב. סימן הצירוף נבדק
/// רק במועמדים בחלונות הבחירה, לא בכל רווח.
List<int> _cutPositions(String text, List<_Leaf> leaves) {
  final cuttable = Uint8List(text.length + 1);
  var depth = 0;
  var offset = 0;
  for (final leaf in leaves) {
    final leafText = leaf.text;
    for (var i = 0; i < leafText.length; i++) {
      final c = leafText.codeUnitAt(i);
      if (_opensDirectional(c)) depth++;
      if ((c == 0x2069 || c == 0x202C) && depth > 0) depth--;
      final at = offset + i + 1;
      if (leaf.cuttable && c == 0x20 && depth == 0 && at < text.length) {
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
    required TextStyle this.style,
    this.strutStyle,
    required TextAlign this.textAlign,
  }) : paragraph = null;

  /// מקטעי פסקה ש-HtmlWidget בנה: כל מקטע הוא עותק של [paragraph] עם טקסט המקטע.
  const LongLineChunks.paragraph({
    super.key,
    required this.split,
    required Widget this.paragraph,
    this.strutStyle,
  }) : style = null,
       textAlign = null;

  final LongLineSplit split;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final Widget? paragraph;

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
        widget.textAlign == oldWidget.textAlign &&
        widget.paragraph == oldWidget.paragraph) {
      return;
    }
    // הדגשה חדשה באותו טקסט נבנית מחדש בבת אחת; טקסט או גופן אחר — בהדרגה.
    // בפסקה של HtmlWidget הגופן נמצא בסגנון השורש של הספאן ולא ב-[style].
    final keep =
        widget.split.text == oldWidget.split.text &&
            widget.style == oldWidget.style &&
            widget.strutStyle == oldWidget.strutStyle &&
            widget.split.chunks.first.style ==
                oldWidget.split.chunks.first.style
        ? math.min(_built.length, widget.split.chunks.length)
        : 0;
    _built.clear();
    _addChunks(math.max(keep, kLongLineChunksPerFrame));
  }

  void _addChunks([int count = kLongLineChunksPerFrame]) {
    final split = widget.split;
    final end = math.min(_built.length + count, split.chunks.length);
    final paragraph = widget.paragraph;
    for (var i = _built.length; i < end; i++) {
      _built.add(
        _LongLineChunk(
          lineText: split.text,
          start: split.starts[i],
          child: paragraph != null
              ? withSelectionFillRichText(
                  paragraph,
                  strutStyle: widget.strutStyle,
                  text: split.chunks[i],
                )
              : SelectionFillText.rich(
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
