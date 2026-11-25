/// שורה ארוכה מאוד מוצגת כרצף פסקאות קצרות שנבנות בהדרגה, ונשארת פריט אחד
/// ברשימה. הטקסט המחובר של המקטעים זהה לטקסט השורה.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/widgets/selection/paragraph_selection_container.dart';
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

/// מפצל את [span] למקטעים. העץ יכול להיות מקונן, מעוצב ועם קישורים או
/// ווידג'טים משובצים. null כשהשורה קצרה או כשאין בה מקום בטוח לחיתוך.
LongLineSplit? splitLongLine(TextSpan span) {
  final cached = _splitCache[span];
  if (cached != null) return cached;
  final split = _split(span);
  if (split != null) _splitCache[span] = split;
  return split;
}

LongLineSplit? _split(TextSpan span) {
  final length = _plainLength(span);
  if (length <= kLongLineMinChars) return null;
  final scan = _Scan(length);
  if (!scan.visit(span, null)) return null;
  final text = scan.buffer.toString();
  final cuts = _cutPositions(text, scan.ranks);
  if (cuts.isEmpty) return null;
  final chunks = (_Slicer(cuts)..visit(span)).chunks;
  return LongLineSplit._(text, chunks, [0, ...cuts]);
}

/// אורך הטקסט הגלוי בלי לבנות אותו; ווידג'ט משובץ הוא תו אחד.
int _plainLength(InlineSpan span) {
  var length = 0;
  span.visitChildren((child) {
    length += child is TextSpan ? child.text?.length ?? 0 : 1;
    return true;
  });
  return length;
}

/// ספאן בעץ השורה, עם התכונות שחיתוך בתוכו (או בתוך אב שלו) תלוי בהן.
final class _Node {
  _Node(TextSpan span, this.parent)
    : depth = parent == null ? 0 : parent.depth + 1,
      labeled = span.semanticsLabel != null || (parent?.labeled ?? false),
      interactive =
          span.recognizer != null ||
          span.onEnter != null ||
          span.onExit != null ||
          span.mouseCursor != MouseCursor.defer ||
          (parent?.interactive ?? false),
      styled =
          (parent != null && span.style != null) || (parent?.styled ?? false);

  final _Node? parent;
  final int depth;
  final bool labeled;
  final bool interactive;
  final bool styled;

  /// הספאן הפנימי ביותר שמכיל את שניהם: חיתוך ביניהם מפצל אותו ואת אבותיו.
  _Node commonAncestor(_Node other) {
    var a = this;
    var b = other;
    while (a.depth > b.depth) {
      a = a.parent!;
    }
    while (b.depth > a.depth) {
      b = b.parent!;
    }
    while (!identical(a, b)) {
      a = a.parent!;
      b = b.parent!;
    }
    return a;
  }

  /// דירוג חיתוך בתוך הספאן: 1 הטוב ביותר, 0 אסור. ספאן עם תווית נגישות אינו
  /// נחתך, ובתוך קישור חותכים רק כשאין ברירה אחרת בחלון.
  int rank({required bool sentence}) {
    if (labeled) return 0;
    final tier = interactive
        ? 2
        : styled
        ? 1
        : 0;
    return tier * 2 + (sentence ? 1 : 2);
  }
}

/// סריקה אחת של העץ: הטקסט הגלוי ודירוג החיתוך אחרי כל רווח.
final class _Scan {
  _Scan(this.length) : ranks = Uint8List(length + 1);

  final int length;
  final Uint8List ranks;
  final StringBuffer buffer = StringBuffer();
  int _offset = 0;
  int _depth = 0;

  /// רווח שסיים ספאן: הדירוג תלוי גם בספאן שבא אחריו.
  ({_Node node, bool sentence})? _pending;

  bool visit(InlineSpan span, _Node? parent) {
    if (span is PlaceholderSpan && parent != null) {
      _text('￼', parent);
      return true;
    }
    // תת-מחלקה של TextSpan עלולה לשאת שדות שההעתק לא ישמור.
    if (span.runtimeType != TextSpan) return false;
    span as TextSpan;
    final node = _Node(span, parent);
    final text = span.text;
    if (text != null && text.isNotEmpty) _text(text, node);
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (!visit(child, node)) return false;
    }
    return true;
  }

  void _text(String text, _Node node) {
    final start = _offset;
    final pending = _pending;
    if (pending != null) {
      _pending = null;
      ranks[start] = pending.node
          .commonAncestor(node)
          .rank(sentence: pending.sentence);
    }
    buffer.write(text);
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (_opensDirectional(c)) _depth++;
      if ((c == 0x2069 || c == 0x202C) && _depth > 0) _depth--;
      final at = start + i + 1;
      if (c != 0x20 || _depth != 0 || at >= length) continue;
      final previous = i > 0 ? text.codeUnitAt(i - 1) : -1;
      final sentence =
          previous == 0x2E ||
          previous == 0x3A ||
          previous == 0x3F ||
          previous == 0x21;
      if (i < text.length - 1) {
        ranks[at] = node.rank(sentence: sentence);
      } else {
        _pending = (node: node, sentence: sentence);
      }
    }
    _offset += text.length;
  }
}

/// מקומות החיתוך בטקסט: אחרי רווח, מחוץ לבידוד או הטבעה כיווניים, ולא לפני
/// סימן צירוף. בכל חלון נבחר הדירוג הטוב ביותר ([_Node.rank]). סימן הצירוף
/// נבדק רק במועמדים בחלונות הבחירה, לא בכל רווח.
List<int> _cutPositions(String text, Uint8List ranks) {
  bool accept(int i) {
    if (!_startsWithMark(text, i)) return true;
    // גם החיפוש החלופי צריך לדלג על מועמד שכבר נפסל.
    ranks[i] = 0;
    return false;
  }

  final cuts = <int>[];
  var target = kLongLineChunkChars;
  while (target < text.length - kLongLineChunkChars ~/ 4) {
    final window = math.min(text.length, target + kLongLineChunkChars ~/ 4);
    var cut = -1;
    for (var rank = 1; rank <= _worstRank && cut < 0; rank++) {
      for (var i = target; i < window; i++) {
        if (ranks[i] == rank && accept(i)) {
          cut = i;
          break;
        }
      }
    }
    if (cut < 0) {
      for (var i = target; i < text.length; i++) {
        if (ranks[i] != 0 && accept(i)) {
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

const int _worstRank = 6;

/// ספאן פתוח במקטע הנוכחי. ספאן שלא נחתך נשאר אותו מופע.
final class _Open {
  _Open(this.source, {this.split = false});

  final TextSpan source;
  bool split;
  String? text;
  final List<InlineSpan> children = [];

  /// ההעתק שומר כל שדה של TextSpan.
  TextSpan copy() => TextSpan(
    text: text,
    children: children.isEmpty ? null : children,
    style: source.style,
    recognizer: source.recognizer,
    mouseCursor: source.mouseCursor,
    onEnter: source.onEnter,
    onExit: source.onExit,
    semanticsLabel: source.semanticsLabel,
    semanticsIdentifier: source.semanticsIdentifier,
    locale: source.locale,
    spellOut: source.spellOut,
  );

  /// חלק ריק של ספאן שנחתך (החיתוך נפל בגבולו) אינו נכנס למקטע.
  InlineSpan? build() {
    if (!split) return source;
    if (text == null && children.isEmpty) return null;
    return copy();
  }
}

/// חותך את העץ ב-[cuts]: כל מקטע מקבל העתק של שרשרת הספאנים הפתוחים.
final class _Slicer {
  _Slicer(this.cuts);

  final List<int> cuts;
  final List<TextSpan> chunks = [];
  final List<_Open> _stack = [];
  int _offset = 0;
  int _next = 0;

  void visit(InlineSpan span) {
    if (span is! TextSpan) {
      _cutIfDue();
      _stack.last.children.add(span);
      _offset++;
      return;
    }
    _stack.add(_Open(span));
    final text = span.text;
    if (text != null) _text(text);
    for (final child in span.children ?? const <InlineSpan>[]) {
      visit(child);
    }
    final current = _stack.removeLast();
    if (_stack.isEmpty) {
      chunks.add(current.copy());
      return;
    }
    final built = current.build();
    if (built != null) _stack.last.children.add(built);
  }

  void _text(String text) {
    if (text.isEmpty) {
      _stack.last.text = text;
      return;
    }
    var i = 0;
    while (i < text.length) {
      _cutIfDue();
      final end = _next < cuts.length
          ? math.min(text.length, i + cuts[_next] - _offset)
          : text.length;
      _stack.last.text = i == 0 && end == text.length
          ? text
          : text.substring(i, end);
      _offset += end - i;
      i = end;
    }
  }

  void _cutIfDue() {
    if (_next >= cuts.length || cuts[_next] != _offset) return;
    _next++;
    InlineSpan? child;
    for (var i = _stack.length - 1; i >= 0; i--) {
      final open = _stack[i]..split = true;
      if (child != null) open.children.add(child);
      child = i == 0 ? open.copy() : open.build();
    }
    chunks.add(child! as TextSpan);
    for (var i = 0; i < _stack.length; i++) {
      _stack[i] = _Open(_stack[i].source, split: true);
    }
  }
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

/// מקטע של שורה ארוכה ב-render tree: [start] ו-[end] הם טווח המקטע בטקסט
/// השורה.
class RenderLongLineChunk extends RenderProxyBox {
  RenderLongLineChunk({
    required this.lineText,
    required this.start,
    required this.end,
  });

  String lineText;
  int start;
  int end;
}

RenderLongLineChunk? _chunkAbove(RenderObject paragraph) {
  RenderObject? node = paragraph.parent;
  // בין הפסקה למקטע יש רק את ה-MouseRegion של SelectionFillText.
  for (var depth = 0; node != null && depth < 3; depth++) {
    if (node is RenderLongLineChunk) return node;
    node = node.parent;
  }
  return null;
}

/// טקסט השורה וההיסט של [paragraph] בתוכו, כשהפסקה היא מקטע של שורה ארוכה.
({String lineText, int start})? longLineChunkOf(RenderObject paragraph) {
  final chunk = _chunkAbove(paragraph);
  return chunk == null ? null : (lineText: chunk.lineText, start: chunk.start);
}

/// הפסקאות של כל מקטעי השורה של [paragraph] שכבר נבנו, לפי הסדר, עם טווח
/// כל אחד בטקסט השורה. null כשהפסקה אינה מקטע.
List<({RenderParagraph paragraph, int start, int end})>? longLineParagraphsOf(
  RenderParagraph paragraph,
) {
  final chunk = _chunkAbove(paragraph);
  final column = chunk?.parent;
  if (chunk == null || column == null) return null;
  final paragraphs = <({RenderParagraph paragraph, int start, int end})>[];
  column.visitChildren((child) {
    if (child is! RenderLongLineChunk ||
        !identical(child.lineText, chunk.lineText)) {
      return;
    }
    final found = _firstParagraph(child);
    if (found != null) {
      paragraphs.add((paragraph: found, start: child.start, end: child.end));
    }
  });
  return paragraphs;
}

RenderParagraph? _firstParagraph(RenderObject node) {
  if (node is RenderParagraph) return node;
  RenderParagraph? found;
  node.visitChildren((child) => found ??= _firstParagraph(child));
  return found;
}

class _LongLineChunk extends SingleChildRenderObjectWidget {
  const _LongLineChunk({
    required this.lineText,
    required this.start,
    required this.end,
    required super.child,
  });

  final String lineText;
  final int start;
  final int end;

  @override
  RenderLongLineChunk createRenderObject(BuildContext context) =>
      RenderLongLineChunk(lineText: lineText, start: start, end: end);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLongLineChunk renderObject,
  ) {
    renderObject
      ..lineText = lineText
      ..start = start
      ..end = end;
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
    this.chunkBuilder,
  });

  final LongLineSplit split;
  final TextStyle style;
  final StrutStyle? strutStyle;
  final TextAlign textAlign;

  /// בונה את הפסקה של מקטע. בלעדיו — [SelectionFillText] ב-[style].
  final Widget Function(TextSpan chunk)? chunkBuilder;

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

  Widget _paragraph(TextSpan span) =>
      widget.chunkBuilder?.call(span) ??
      SelectionFillText.rich(
        span,
        style: widget.style,
        strutStyle: widget.strutStyle,
        textAlign: widget.textAlign,
      );

  void _addChunks([int count = kLongLineChunksPerFrame]) {
    final split = widget.split;
    final end = math.min(_built.length + count, split.chunks.length);
    for (var i = _built.length; i < end; i++) {
      _built.add(
        _LongLineChunk(
          lineText: split.text,
          start: split.starts[i],
          end: i + 1 < split.starts.length
              ? split.starts[i + 1]
              : split.text.length,
          child: _paragraph(split.chunks[i]),
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // ברוחב לא חסום (גלילה אופקית) עמודה מתוחה נכשלת; אין שם מה לפצל.
      if (!constraints.hasBoundedWidth) {
        return _paragraph(TextSpan(children: widget.split.chunks));
      }
      return ParagraphSelectionContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.of(_built),
        ),
      );
    },
  );
}
