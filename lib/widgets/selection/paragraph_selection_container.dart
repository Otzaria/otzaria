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
      // פסקה שמגיעה לקצה המקטע ממשיכה במקטע הסמוך.
      var end = range.end;
      for (var i = hit + 1; i < chunks.length; i++) {
        if (end < chunks[i - 1].end - chunks[i - 1].start) break;
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
      for (var i = hit - 1; i >= 0 && start == 0; i--) {
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
    if (parts == null) return super.getSelectedContent();

    // Flutter ממיין קטעים לפי מיקום במסך. ההעתקה צריכה ללכת לפי היסט בטקסט.
    final fragments = <({int offset, String text})>[];
    for (final selectable in selectables) {
      final text = selectable.getSelectedContent()?.plainText;
      if (text == null || text.isEmpty) continue;
      final part = parts
          .where((p) => p.paragraph.selectableBelongsToParagraph(selectable))
          .firstOrNull;
      if (part == null) return super.getSelectedContent();
      final range = selectable.getSelection()!;
      fragments.add((offset: part.start + range.startOffset, text: text));
    }
    if (fragments.isEmpty) return super.getSelectedContent();
    fragments.sort((a, b) => a.offset.compareTo(b.offset));
    return SelectedContent(
      plainText: fragments.map((part) => part.text).join(),
    );
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
