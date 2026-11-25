import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/widgets/smart_text/long_line_chunks.dart';

/// לחיצה משולשת בוחרת את כל הפסקה גם כש-[WidgetSpan] מפצל את ה-[RichText]
/// לכמה קטעי בחירה, כמו ב-[Text], וגם כשהפסקה חוצה מקטעים של שורה ארוכה.
// TODO: את הטיפול ב-WidgetSpan להסיר כשהתיקון ל-flutter/flutter#196903 ייכנס
// ל-Flutter היציב שהאפליקציה משתמשת בו.
class ParagraphSelectionContainer extends StatefulWidget {
  const ParagraphSelectionContainer({super.key, required this.child});

  final Widget child;

  @override
  State<ParagraphSelectionContainer> createState() =>
      _ParagraphSelectionContainerState();
}

class _ParagraphSelectionContainerState
    extends State<ParagraphSelectionContainer> {
  late final _delegate = ParagraphSelectionDelegate(context.findRenderObject);

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registrar = SelectionContainer.maybeOf(context);
    if (registrar == null || registrar is ParagraphSelectionDelegate) {
      return widget.child;
    }
    return SelectionContainer(delegate: _delegate, child: widget.child);
  }
}

/// מרחיב בחירת פסקה לכל קטעי הטקסט שלה משני צדי ווידג'טים משובצים, ולמקטעים
/// הסמוכים כשהפסקה חוצה מקטעים של שורה ארוכה.
class ParagraphSelectionDelegate extends StaticSelectionContainerDelegate {
  ParagraphSelectionDelegate(this._root);

  final RenderObject? Function() _root;
  List<({RenderParagraph paragraph, int start})>? _selectedParagraphs;

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    _selectedParagraphs = null;
    return super.dispatchSelectionEvent(event);
  }

  @override
  SelectionResult handleSelectParagraph(SelectParagraphSelectionEvent event) {
    final paragraph = event.absorb ? null : _paragraphAt(event.globalPosition);
    if (paragraph == null) return super.handleSelectParagraph(event);
    final chunks = longLineParagraphsOf(paragraph) ?? const [];
    final hit = chunks.indexWhere((c) => identical(c.paragraph, paragraph));
    final fragments = <int>{};
    final selected = <int>[];
    final parts = <({RenderParagraph paragraph, int start})>[];
    if (hit < 0) {
      if (_fragmentsOf(paragraph).length < 2) {
        return super.handleSelectParagraph(event);
      }
      handleClearSelection(const ClearSelectionEvent());
      _selectIn(paragraph, event.globalPosition, fragments, selected);
      parts.add((paragraph: paragraph, start: 0));
    } else {
      handleClearSelection(const ClearSelectionEvent());
      final range = _selectIn(
        paragraph,
        event.globalPosition,
        fragments,
        selected,
      );
      if (range == null) return super.handleSelectParagraph(event);
      parts.add((paragraph: paragraph, start: chunks[hit].start));
      // פסקה שמגיעה לקצה המקטע ממשיכה במקטע הסמוך, אלא אם הם נחתכו בשבירה.
      var end = range.end;
      for (var i = hit + 1; i < chunks.length; i++) {
        if (end < chunks[i - 1].end - chunks[i - 1].start ||
            chunks[i].skipped.isNotEmpty) {
          break;
        }
        final next = chunks[i].paragraph;
        if (!next.hasSize) break;
        final nextRange = _selectIn(
          next,
          next.localToGlobal(_corner(next, end: false)),
          fragments,
          selected,
        );
        if (nextRange == null) break;
        parts.add((paragraph: next, start: chunks[i].start));
        end = nextRange.end;
      }
      var start = range.start;
      for (
        var i = hit - 1;
        i >= 0 && start == 0 && chunks[i + 1].skipped.isEmpty;
        i--
      ) {
        final previous = chunks[i].paragraph;
        if (!previous.hasSize) break;
        final previousRange = _selectIn(
          previous,
          previous.localToGlobal(_corner(previous, end: true)),
          fragments,
          selected,
        );
        if (previousRange == null) break;
        parts.add((paragraph: previous, start: chunks[i].start));
        start = previousRange.start;
      }
    }
    if (selected.isEmpty) return super.handleSelectParagraph(event);
    selected.sort();
    for (var i = selected.first + 1; i < selected.last; i++) {
      if (!fragments.contains(i)) {
        dispatchSelectionEventToChild(
          selectables[i],
          SelectParagraphSelectionEvent(
            globalPosition: event.globalPosition,
            absorb: true,
          ),
        );
      }
    }
    currentSelectionStartIndex = selected.first;
    currentSelectionEndIndex = selected.last;
    _selectedParagraphs = parts;
    didReceiveSelectionBoundaryEvents();
    return SelectionResult.end;
  }

  Set<int> _fragmentsOf(RenderParagraph paragraph) => {
    for (var i = 0; i < selectables.length; i++)
      if (paragraph.selectableBelongsToParagraph(selectables[i])) i,
  };

  /// בוחר את הפסקה ב-[globalPosition] בכל קטעי [paragraph]; כל קטע מחשב את
  /// גבול הפסקה על הטקסט המלא ובוחר את החלק שלו. מחזיר את הטווח שנבחר.
  ({int start, int end})? _selectIn(
    RenderParagraph paragraph,
    Offset globalPosition,
    Set<int> fragments,
    List<int> selected,
  ) {
    int? start;
    int? end;
    for (final index in _fragmentsOf(paragraph)) {
      fragments.add(index);
      final selectable = selectables[index];
      dispatchSelectionEventToChild(
        selectable,
        SelectParagraphSelectionEvent(globalPosition: globalPosition),
      );
      final range = selectable.getSelection();
      if (selectable.value.status != SelectionStatus.uncollapsed ||
          range == null) {
        continue;
      }
      selected.add(index);
      final low = math.min(range.startOffset, range.endOffset);
      final high = math.max(range.startOffset, range.endOffset);
      start = start == null ? low : math.min(start, low);
      end = end == null ? high : math.max(end, high);
    }
    return start == null ? null : (start: start, end: end!);
  }

  /// פינת תחילת הטקסט או סופו, בכיוון הפסקה.
  Offset _corner(RenderParagraph paragraph, {required bool end}) {
    final size = paragraph.size;
    final rtl = paragraph.textDirection == TextDirection.rtl;
    return end
        ? Offset(rtl ? 0 : size.width, size.height)
        : Offset(rtl ? size.width : 0, 0);
  }

  @override
  SelectedContent? getSelectedContent() {
    final parts = _selectedParagraphs;
    final contents = [
      for (final selectable in selectables)
        (
          selectable: selectable,
          text: selectable.getSelectedContent()?.plainText,
        ),
    ].where((content) => content.text?.isNotEmpty ?? false).toList();
    if (contents.isEmpty) return super.getSelectedContent();
    final chunks = _chunkParagraphs();
    if (parts == null && chunks.isEmpty) return super.getSelectedContent();

    final pieces = <_Piece>[];
    for (final (index, content) in contents.indexed) {
      final selectable = content.selectable;
      final range = selectable.getSelection();
      final low = range == null
          ? 0
          : math.min(range.startOffset, range.endOffset);
      final high = range == null
          ? 0
          : math.max(range.startOffset, range.endOffset);
      var order = index;
      if (parts != null) {
        // Flutter ממיין קטעים לפי מיקום במסך. ההעתקה צריכה ללכת לפי היסט בטקסט.
        final part = parts
            .where((p) => p.paragraph.selectableBelongsToParagraph(selectable))
            .firstOrNull;
        if (part == null) return super.getSelectedContent();
        order = part.start + low;
      }
      pieces.add((
        order: order,
        text: content.text!,
        chunk: chunks
            .where((c) => c.paragraph.selectableBelongsToParagraph(selectable))
            .firstOrNull,
        start: low,
        end: high,
      ));
    }
    if (parts != null) pieces.sort((a, b) => a.order.compareTo(b.order));

    // שבירה שהושמטה בין מקטעים חוזרת לטקסט כשהבחירה חוצה אותה.
    final out = StringBuffer();
    for (var i = 0; i < pieces.length; i++) {
      final piece = pieces[i];
      if (i > 0 && _continues(pieces[i - 1], piece)) {
        out.write(piece.chunk!.skipped);
      }
      out.write(piece.text);
    }
    final last = pieces.last.chunk;
    if (parts != null &&
        last != null &&
        pieces.last.end == last.end - last.start &&
        _breakAfter(last)) {
      out.writeln();
    }
    return SelectedContent(plainText: out.toString());
  }

  bool _continues(_Piece previous, _Piece next) {
    final a = previous.chunk;
    final b = next.chunk;
    return a != null &&
        b != null &&
        identical(a.lineText, b.lineText) &&
        previous.end == a.end - a.start &&
        next.start == 0 &&
        b.start - b.skipped.length == a.end;
  }

  /// מקטע שנחתך בשבירה קשיחה: פסקה שמסתיימת בו כוללת אותה, כמו בפסקה אחת.
  bool _breakAfter(LongLineParagraph chunk) =>
      chunk.end < chunk.lineText.length &&
      chunk.lineText.codeUnitAt(chunk.end) == 0x0A;

  List<LongLineParagraph> _chunkParagraphs() {
    final root = _root();
    final chunks = <LongLineParagraph>[];
    void visit(RenderObject node) {
      if (node is RenderParagraph) {
        final chunk = longLineParagraphOf(node);
        if (chunk != null) chunks.add(chunk);
        return;
      }
      node.visitChildren(visit);
    }

    if (root != null) visit(root);
    return chunks;
  }

  RenderParagraph? _paragraphAt(Offset globalPosition) {
    final root = _root();
    if (root is! RenderBox || !root.attached || !root.hasSize) return null;
    final hit = BoxHitTestResult();
    root.hitTest(hit, position: root.globalToLocal(globalPosition));
    return hit.path
        .map((entry) => entry.target)
        .whereType<RenderParagraph>()
        .firstOrNull;
  }
}

typedef _Piece = ({
  int order,
  String text,
  LongLineParagraph? chunk,
  int start,
  int end,
});
