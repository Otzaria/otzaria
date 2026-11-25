/// שורה ארוכה מאוד מוצגת כרצף פסקאות קצרות שנבנות בהדרגה, ונשארת פריט אחד
/// ברשימה. הטקסט המחובר של המקטעים, עם השבירות שביניהם, זהה לטקסט השורה.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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

/// מקטעי שורה ארוכה וטווח כל אחד בטקסט השורה. שבירה קשיחה שנחתכה (בין `ends[i]`
/// ל-`starts[i + 1]`) אינה באף מקטע, כי בקצה פסקה היא מוסיפה שורה ריקה.
@immutable
class LongLineSplit {
  const LongLineSplit._(
    this.source,
    this.text,
    this.chunks,
    this.starts,
    this.ends,
  );

  /// הספאן שפוצל.
  final TextSpan source;

  /// הטקסט הגלוי של השורה כולה.
  final String text;
  final List<TextSpan> chunks;
  final List<int> starts;
  final List<int> ends;
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

/// עם [keep] (שטקסטו זהה) החיתוך נשאר בגבולותיו, ו-null כשגבול כבר אסור.
LongLineSplit? _split(TextSpan span, {LongLineSplit? keep}) {
  final length = _plainLength(span);
  if (length <= kLongLineMinChars) return null;
  final scan = _Scan(length);
  if (!scan.visit(span, null)) return null;
  final text = scan.buffer.toString();
  final _Cuts cuts;
  if (keep == null) {
    cuts = _cutPositions(text, scan.ranks);
  } else {
    cuts = (
      ends: keep.ends.sublist(0, keep.ends.length - 1),
      nexts: keep.starts.sublist(1),
    );
    if (!_stillValid(cuts, scan.ranks)) return null;
  }
  if (cuts.ends.isEmpty) return null;
  final chunks = (_Slicer(cuts.ends, cuts.nexts)..visit(span)).chunks;
  return LongLineSplit._(
    span,
    keep?.text ?? text,
    chunks,
    [0, ...cuts.nexts],
    [...cuts.ends, text.length],
  );
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

/// דירוגי החיתוך: 1 הטוב ביותר, 0 אסור.
const int _hardBreak = 1;
const int _sentenceSpace = 2;
const int _space = 3;

/// רווח בתוך ספאן מעוצב: לא נבחר, אבל חיתוך קיים שנפל עליו נשמר.
const int _styledSpace = 4;

/// ספאן בעץ השורה, עם התכונות שחיתוך בתוכו (או בתוך אב שלו) תלוי בהן.
final class _Node {
  _Node(TextSpan span, this.parent)
    : depth = parent == null ? 0 : parent.depth + 1,
      style = span.style,
      // קישור, ריחוף או תווית נגישות שנחתכו היו מוכפלים בעץ הנגישות ובריחוף.
      locked =
          span.semanticsLabel != null ||
          span.recognizer != null ||
          span.onEnter != null ||
          span.onExit != null ||
          span.mouseCursor != MouseCursor.defer ||
          (parent?.locked ?? false),
      styled =
          (parent != null &&
              span.style != null &&
              span.style != parent.style) ||
          (parent?.styled ?? false);

  final _Node? parent;
  final int depth;
  final TextStyle? style;
  final bool locked;
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

  int spaceRank({required bool sentence}) {
    if (locked) return 0;
    if (styled) return _styledSpace;
    return sentence ? _sentenceSpace : _space;
  }
}

/// סריקה אחת של העץ: הטקסט הגלוי ודירוג החיתוך בכל מקום.
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
      _text('\uFFFC', parent);
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
          .spaceRank(sentence: pending.sentence);
    }
    buffer.write(text);
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      final at = start + i + 1;
      if (c == 0x0A) {
        // מפריד פסקה סוגר כל הטבעה ובידוד כיווני.
        _depth = 0;
        if (at - 1 > 0 && at < length && !node.locked) {
          ranks[at - 1] = _hardBreak;
        }
        continue;
      }
      if (_opensDirectional(c)) _depth++;
      if ((c == 0x2069 || c == 0x202C) && _depth > 0) _depth--;
      if (c != 0x20 || _depth != 0 || at >= length) continue;
      final previous = i > 0 ? text.codeUnitAt(i - 1) : -1;
      final sentence =
          previous == 0x2E ||
          previous == 0x3A ||
          previous == 0x3F ||
          previous == 0x21;
      if (i < text.length - 1) {
        ranks[at] = node.spaceRank(sentence: sentence);
      } else {
        _pending = (node: node, sentence: sentence);
      }
    }
    _offset += text.length;
  }
}

typedef _Cuts = ({List<int> ends, List<int> nexts});

/// שבירה קשיחה ליד היעד, אחרת רווח (אחרי סוף משפט קודם). סימן צירוף נבדק רק
/// במועמדים שבחלון, לא בכל רווח.
_Cuts _cutPositions(String text, Uint8List ranks) {
  bool accept(int i) {
    if (ranks[i] == _hardBreak) return true;
    // רווח לפני שבירה נעולה (בקישור) היה פותח את המקטע הבא בשורה ריקה.
    if (text.codeUnitAt(i) != 0x0A && !_startsWithMark(text, i)) return true;
    // גם החיפוש החלופי צריך לדלג על מועמד שכבר נפסל.
    ranks[i] = 0;
    return false;
  }

  final ends = <int>[];
  final nexts = <int>[];
  const quarter = kLongLineChunkChars ~/ 4;
  var target = kLongLineChunkChars;
  while (target < text.length - quarter) {
    final window = math.min(text.length, target + quarter);
    var cut = -1;
    for (var i = target - quarter; i < window && cut < 0; i++) {
      if (ranks[i] == _hardBreak) cut = i;
    }
    for (var rank = _sentenceSpace; rank <= _space && cut < 0; rank++) {
      for (var i = target; i < window; i++) {
        if (ranks[i] == rank && accept(i)) {
          cut = i;
          break;
        }
      }
    }
    if (cut < 0) {
      for (var i = target; i < text.length; i++) {
        final rank = ranks[i];
        if (rank != 0 && rank != _styledSpace && accept(i)) {
          cut = i;
          break;
        }
      }
    }
    if (cut < 0) break;
    final next = ranks[cut] == _hardBreak ? cut + 1 : cut;
    ends.add(cut);
    nexts.add(next);
    target = next + kLongLineChunkChars;
  }
  return (ends: ends, nexts: nexts);
}

/// חיתוך קיים נשאר מותר גם על רווח בספאן מעוצב, אבל לא בתוך קישור או תווית.
bool _stillValid(_Cuts cuts, Uint8List ranks) {
  for (var i = 0; i < cuts.ends.length; i++) {
    final rank = ranks[cuts.ends[i]];
    final hard = cuts.nexts[i] != cuts.ends[i];
    if (hard ? rank != _hardBreak : rank < _sentenceSpace) return false;
  }
  return true;
}

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

/// חותך את העץ: מקטע נסגר ב-`ends[i]`, והבא מתחיל ב-`nexts[i]`. התווים
/// שביניהם (שבירה קשיחה) אינם נכנסים לאף מקטע.
final class _Slicer {
  _Slicer(this.ends, this.nexts);

  final List<int> ends;
  final List<int> nexts;
  final List<TextSpan> chunks = [];
  final List<_Open> _stack = [];
  int _offset = 0;
  int _next = 0;
  int _skip = 0;

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
      if (_skip > 0) {
        final skipped = math.min(_skip, text.length - i);
        _skip -= skipped;
        _offset += skipped;
        i += skipped;
        continue;
      }
      final end = _next < ends.length
          ? math.min(text.length, i + ends[_next] - _offset)
          : text.length;
      final piece = i == 0 && end == text.length
          ? text
          : text.substring(i, end);
      final open = _stack.last;
      open.text = open.text == null ? piece : open.text! + piece;
      _offset += end - i;
      i = end;
    }
  }

  void _cutIfDue() {
    if (_next >= ends.length || ends[_next] != _offset) return;
    _skip = nexts[_next] - ends[_next];
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

/// מונה קריאות ל-[_startsWithMark], לבדיקות בלבד (נספר רק ב-debug).
@visibleForTesting
int debugMarkChecks = 0;

bool _startsWithMark(String text, int at) {
  assert(() {
    debugMarkChecks++;
    return true;
  }());
  return _mark.matchAsPrefix(text, at) != null;
}

/// סימן צירוף, תו בקרה בלתי נראה (ZWJ, ZWNJ, סימוני כיוון) או משנה גוון של
/// אמוג'י: כולם נצמדים לתו שלפניהם.
final RegExp _mark = RegExp(r'[\p{M}\p{Cf}\u{1F3FB}-\u{1F3FF}]', unicode: true);

/// מקטע של שורה ארוכה ב-render tree: [start] ו-[end] הם טווח המקטע בטקסט
/// השורה, ו-[skipped] הוא הטקסט שהושמט לפניו (שבירה קשיחה, או ריק).
class RenderLongLineChunk extends RenderProxyBox {
  RenderLongLineChunk({
    required this.lineText,
    required this.start,
    required this.end,
    required this.skipped,
  });

  String lineText;
  int start;
  int end;
  String skipped;

  // מקטע שכבר צויר אינו מצויר מחדש כשמקטע אחר נוסף או מתעדכן.
  @override
  bool get isRepaintBoundary => true;

  // צומת נגישות משלו: אחרת כל מקטע שנוסף בונה מחדש את הנגישות של כל המקטעים.
  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isSemanticBoundary = true;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _attachedChunks++;
  }

  @override
  void detach() {
    _attachedChunks--;
    super.detach();
  }
}

int _attachedChunks = 0;

/// האם יש בעץ מקטע של שורה ארוכה; בלי כזה אין טעם לחפש מקטעים.
bool get longLineChunksAttached => _attachedChunks > 0;

/// מקטע שנבנה: הפסקה שלו, הטווח שלו בטקסט השורה והטקסט שהושמט לפניו.
typedef LongLineParagraph = ({
  RenderParagraph paragraph,
  String lineText,
  int start,
  int end,
  String skipped,
});

/// המקטע ש-[paragraph] היא הפסקה שלו. פסקה בתוך ווידג'ט משובץ במקטע אינה
/// הפסקה שלו, ולכן עוצרים בפסקה אחרת בדרך.
RenderLongLineChunk? _chunkOf(RenderObject paragraph) {
  RenderObject? node = paragraph.parent;
  for (var depth = 0; node != null && depth < 3; depth++) {
    if (node is RenderLongLineChunk) return node;
    if (node is RenderParagraph) return null;
    node = node.parent;
  }
  return null;
}

LongLineParagraph? _describe(RenderParagraph? paragraph, RenderObject? chunk) =>
    paragraph == null || chunk is! RenderLongLineChunk
    ? null
    : (
        paragraph: paragraph,
        lineText: chunk.lineText,
        start: chunk.start,
        end: chunk.end,
        skipped: chunk.skipped,
      );

/// [paragraph] כמקטע של שורה ארוכה, או null.
LongLineParagraph? longLineChunkOf(RenderParagraph paragraph) =>
    _describe(paragraph, _chunkOf(paragraph));

/// הפסקאות של כל מקטעי השורה של [paragraph] שכבר נבנו, לפי הסדר. null כשהפסקה
/// אינה מקטע.
List<LongLineParagraph>? longLineParagraphsOf(RenderParagraph paragraph) {
  final chunk = _chunkOf(paragraph);
  final column = chunk?.parent;
  if (chunk == null || column == null) return null;
  final paragraphs = <LongLineParagraph>[];
  column.visitChildren((child) {
    final found = _describe(_firstParagraph(child), child);
    if (found != null && identical(found.lineText, chunk.lineText)) {
      paragraphs.add(found);
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
    super.key,
    required this.lineText,
    required this.start,
    required this.end,
    required this.skipped,
    required super.child,
  });

  final String lineText;
  final int start;
  final int end;
  final String skipped;

  @override
  RenderLongLineChunk createRenderObject(BuildContext context) =>
      RenderLongLineChunk(
        lineText: lineText,
        start: start,
        end: end,
        skipped: skipped,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLongLineChunk renderObject,
  ) {
    renderObject
      ..lineText = lineText
      ..start = start
      ..end = end
      ..skipped = skipped;
  }
}

/// שורות ארוכות שבנייתן טרם הושלמה.
final Set<_LongLineChunksState> _building = {};

/// ממתין לבניית השורות הארוכות, עד [maxFrames], ומחזיר האם הייתה בנייה פעילה.
/// עם [scrollController] או [scrollPosition] — רק לשורות שבגלילה הזו.
Future<bool> longLinesBuilt({
  int maxFrames = 240,
  ScrollController? scrollController,
  ScrollPosition? scrollPosition,
  bool Function()? isCurrent,
}) async {
  bool isBuilding() => _building.any(
    (line) =>
        (scrollController == null ||
            scrollController.positions.contains(line._scrollPosition)) &&
        (scrollPosition == null || line._scrollPosition == scrollPosition),
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
  late LongLineSplit _current = widget.split;
  late _Paragraph _paragraph = _paragraphOf(widget);

  /// מקטעים מגרסה קודמת שעוד מוצגים, בסדר הטקסט וכבר בלי קישורים.
  List<_Entry> _old = const [];

  /// מקטעי הגרסה הנוכחית שנבנו: הטווח `[_lo, _hi)`, שגדל מהמקטע הנראה.
  final Map<int, _Entry> _fresh = {};
  int _lo = 0;
  int _hi = 0;
  bool _growDown = true;

  /// המקטעים המוצגים, לפי הסדר.
  List<_Entry> _shown = const [];
  ({_Entry entry, double y, int generation})? _anchor;
  int _anchors = 0;
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
    _grow();
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
    // המקטעים הקודמים נשארים מוצגים (בלי קישורים, ש-fwfh כבר שחרר), והחדשים
    // מחליפים אותם לפי מקומם בטקסט, מהנראה החוצה — בלי כפילות ובלי קריסה.
    final visible = _visibleIndex();
    final top = visible == null ? null : _offsetOf(visible);
    _old = [for (final entry in _shown) entry.inert()];
    _current = _sameBoundaries(widget.split, _current) ?? widget.split;
    _paragraph = _paragraphOf(widget);
    _fresh.clear();
    final split = _current;
    var first = 0;
    if (visible != null) {
      final at = _old[visible].mapped(_old[visible].start, split);
      while (first < split.chunks.length - 1 && split.ends[first] <= at) {
        first++;
      }
    }
    _lo = _hi = first;
    _growDown = true;
    _grow();
    _hold(_fresh[first]!, top);
  }

  /// טקסט זהה (הדגשה חדשה): אותם גבולות ואותו מופע טקסט, כדי שמקטעים ישנים
  /// וחדשים יזוהו כשורה אחת.
  static LongLineSplit? _sameBoundaries(
    LongLineSplit split,
    LongLineSplit previous,
  ) {
    if (split.text.length != previous.text.length ||
        split.text != previous.text) {
      return null;
    }
    if (listEquals(split.starts, previous.starts) &&
        listEquals(split.ends, previous.ends)) {
      return LongLineSplit._(
        split.source,
        previous.text,
        split.chunks,
        split.starts,
        split.ends,
      );
    }
    return _split(split.source, keep: previous);
  }

  static _Paragraph _paragraphOf(LongLineChunks widget) {
    final style = widget.style;
    final strutStyle = widget.strutStyle;
    final textAlign = widget.textAlign;
    return widget.chunkBuilder ??
        (span) => SelectionFillText.rich(
          span,
          style: style,
          strutStyle: strutStyle,
          textAlign: textAlign,
        );
  }

  /// מוסיף מקטע חדש, מתחת לטווח שנבנה ומעליו לסירוגין, עד המכסה של פריים.
  void _grow() {
    _anchor = null;
    final split = _current;
    final count = split.chunks.length;
    for (var n = 0; n < kLongLineChunksPerFrame; n++) {
      final int index;
      if (_hi < count && (_growDown || _lo == 0)) {
        index = _hi++;
      } else if (_lo > 0) {
        final visible = _visibleIndex();
        if (visible != null) _hold(_shown[visible], _offsetOf(visible));
        index = --_lo;
      } else {
        break;
      }
      _fresh[index] = _Entry(split, index, _paragraph);
      _growDown = !_growDown;
    }
    if (_lo == 0 && _hi == count) _old = const [];
    final blockStart = split.starts[_lo];
    final blockEnd = split.ends[_hi - 1];
    _shown = [
      for (final entry in _old)
        if (entry.mapped(entry.end, split) <= blockStart) entry,
      for (var i = _lo; i < _hi; i++) _fresh[i]!,
      for (final entry in _old)
        if (entry.mapped(entry.start, split) >= blockEnd) entry,
    ];
    _scheduleMore();
  }

  /// [entry] נשאר בגובה [y] בעמודה, גם כשהמקטעים שמעליו מוחלפים: העמודה מוסיפה
  /// רווח בראשה, והוא מומר לתיקון גלילה כשההחלפה מסתיימת ([_release]).
  void _hold(_Entry entry, double? y) {
    if (y != null) _anchor = (entry: entry, y: y, generation: ++_anchors);
  }

  double? _offsetOf(int index) {
    final column = context.findRenderObject();
    if (column is! _RenderChunkColumn) return null;
    var i = 0;
    double? offset;
    column.visitChildren((child) {
      if (i++ == index) {
        offset = (child.parentData! as _ChunkParentData).offset.dy;
      }
    });
    return offset;
  }

  void _release() {
    final column = context.findRenderObject();
    if (column is _RenderChunkColumn) column.release(_scrollPosition);
  }

  /// המקטע המוצג הראשון שנמצא בחלון, או null כשאין עדיין פריסה.
  int? _visibleIndex() {
    final column = context.findRenderObject();
    final view = View.maybeOf(context);
    if (column is! RenderBox || !column.hasSize || view == null) return null;
    final height = view.physicalSize.height / view.devicePixelRatio;
    int? found;
    var index = 0;
    column.visitChildren((child) {
      if (found == null && child is RenderBox && child.hasSize) {
        final top = child.localToGlobal(Offset.zero).dy;
        if (top + child.size.height > 0 && top < height) found = index;
      }
      index++;
    });
    return found != null && found! < _shown.length ? found : null;
  }

  void _scheduleMore() {
    if (_scheduled) return;
    _scheduled = true;
    _setBuilding(true);
    final generation = ++_generation;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      if (_lo > 0 || _hi < _current.chunks.length) {
        setState(_grow);
        return;
      }
      _release();
      // הרשימה מפרסמת את המיקומים אחרי הפריסה; הניווט ממשיך בפריים הבא.
      SchedulerBinding.instance
        ..addPostFrameCallback((_) {
          if (generation == _generation) _setBuilding(false);
        })
        ..scheduleFrame();
    });
  }

  @override
  Widget build(BuildContext context) {
    final anchor = _anchor;
    return ParagraphSelectionContainer(
      child: _ChunkColumn(
        anchor: anchor == null
            ? null
            : (
                index: _shown.indexOf(anchor.entry),
                y: anchor.y,
                generation: anchor.generation,
              ),
        children: [for (final e in _shown) e.widget],
      ),
    );
  }
}

typedef _Paragraph = Widget Function(TextSpan chunk);

/// מקטע מוצג: המקטע ה-[index] של [split], בפסקה שבונה [paragraph].
final class _Entry {
  _Entry(this.split, this.index, this.paragraph, {bool inert = false})
    : widget = _LongLineChunk(
        key: ObjectKey(split.chunks[index]),
        lineText: split.text,
        start: split.starts[index],
        end: split.ends[index],
        skipped: index == 0
            ? ''
            : split.text.substring(split.ends[index - 1], split.starts[index]),
        child: paragraph(
          inert ? _inert(split.chunks[index]) as TextSpan : split.chunks[index],
        ),
      ),
      _isInert = inert;

  final LongLineSplit split;
  final int index;
  final _Paragraph paragraph;
  final Widget widget;
  final bool _isInert;

  int get start => split.starts[index];
  int get end => split.ends[index];

  _Entry inert() =>
      _isInert ? this : _Entry(split, index, paragraph, inert: true);

  /// היסט בטקסט של [other], ביחס לאורך: שינוי טקסט משמר בערך את המבנה.
  double mapped(int offset, LongLineSplit other) =>
      offset * other.text.length / split.text.length;
}

/// עותק של [span] בלי קישורים וריחוף, באותו מראה: מקטע ישן שעוד מוצג.
InlineSpan _inert(InlineSpan span) => span is! TextSpan
    ? span
    : TextSpan(
        text: span.text,
        children: span.children?.map(_inert).toList(),
        style: span.style,
        semanticsLabel: span.semanticsLabel,
        semanticsIdentifier: span.semanticsIdentifier,
        locale: span.locale,
        spellOut: span.spellOut,
      );

/// עמודת המקטעים: כל מקטע ברוחב המלא, זה מתחת לזה; ברוחב לא חסום — ברוחבו
/// הטבעי. תומכת במידות פנימיות, בפריסה יבשה ובקו בסיס יבש.
class _ChunkColumn extends MultiChildRenderObjectWidget {
  const _ChunkColumn({required this.anchor, required super.children});

  final _Anchor? anchor;

  @override
  _RenderChunkColumn createRenderObject(BuildContext context) =>
      _RenderChunkColumn(Directionality.of(context))..anchor = anchor;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderChunkColumn renderObject,
  ) {
    renderObject
      ..textDirection = Directionality.of(context)
      ..anchor = anchor;
  }
}

/// הילד ה-[index] צריך לעמוד בגובה [y]; כל [generation] חל פעם אחת.
typedef _Anchor = ({int index, double y, int generation});

class _ChunkParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderChunkColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ChunkParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ChunkParentData> {
  _RenderChunkColumn(this._textDirection);

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  _Anchor? _anchor;
  int _appliedAnchor = 0;
  set anchor(_Anchor? value) {
    if (value == null || value.generation == _appliedAnchor) return;
    _anchor = value;
    markNeedsLayout();
  }

  /// רווח בראש העמודה שמשאיר מקטע נראה במקומו בזמן החלפה.
  double _gap = 0;

  /// מסיר את הרווח ומתקן את [position] באותו פריים, כך שהתוכן לא זז.
  void release(ScrollPosition? position) {
    if (_gap == 0) return;
    if (position != null && position.hasPixels) position.correctBy(-_gap);
    _gap = 0;
    markNeedsLayout();
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport is RenderObject) (viewport as RenderObject).markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ChunkParentData) {
      child.parentData = _ChunkParentData();
    }
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) =>
      constraints.hasBoundedWidth
      ? BoxConstraints.tightFor(width: constraints.maxWidth)
      : const BoxConstraints();

  Size _stack(
    BoxConstraints constraints,
    Size Function(RenderBox child, BoxConstraints constraints) sizeOf,
  ) {
    final childConstraints = _childConstraints(constraints);
    var width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    var height = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final size = sizeOf(child, childConstraints);
      width = math.max(width, size.width);
      height += size.height;
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _stack(constraints, (child, c) => child.getDryLayout(c));

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => firstChild?.getDryBaseline(_childConstraints(constraints), baseline);

  @override
  void performLayout() {
    final natural = _stack(constraints.loosen(), (child, c) {
      child.layout(c, parentUsesSize: true);
      return child.size;
    });
    final anchor = _anchor;
    if (anchor != null) {
      _anchor = null;
      _appliedAnchor = anchor.generation;
      var top = 0.0;
      var i = 0;
      for (var child = firstChild; child != null; child = childAfter(child)) {
        if (i++ == anchor.index) {
          _gap = math.max(0, anchor.y - top);
          break;
        }
        top += child.size.height;
      }
    }
    size = constraints.constrain(
      Size(
        constraints.hasBoundedWidth ? constraints.maxWidth : natural.width,
        natural.height + _gap,
      ),
    );
    var y = _gap;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final x = _textDirection == TextDirection.rtl
          ? size.width - child.size.width
          : 0.0;
      (child.parentData! as _ChunkParentData).offset = Offset(x, y);
      y += child.size.height;
    }
  }

  double _sum(double Function(RenderBox child) extent) {
    var total = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      total += extent(child);
    }
    return total;
  }

  double _max(double Function(RenderBox child) extent) {
    var most = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      most = math.max(most, extent(child));
    }
    return most;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _max((child) => child.getMinIntrinsicWidth(double.infinity));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _max((child) => child.getMaxIntrinsicWidth(double.infinity));

  @override
  double computeMinIntrinsicHeight(double width) =>
      _sum((child) => child.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _sum((child) => child.getMaxIntrinsicHeight(width));

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
