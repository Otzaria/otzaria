import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// לחיצה משולשת בוחרת את כל הפסקה גם כש-[WidgetSpan] מפצל את ה-[RichText]
/// לכמה קטעי בחירה, כמו ב-[Text].
// TODO: להסיר כשהתיקון ל-https://github.com/flutter/flutter/issues/196903
// ייכנס ל-Flutter היציב שהאפליקציה משתמשת בו.
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

/// מרחיב בחירת פסקה לכל קטעי הטקסט שלה משני צדי ווידג'טים משובצים.
class ParagraphSelectionDelegate extends StaticSelectionContainerDelegate {
  ParagraphSelectionDelegate(this._root);

  final RenderObject? Function() _root;
  RenderParagraph? _selectedParagraph;

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    _selectedParagraph = null;
    return super.dispatchSelectionEvent(event);
  }

  @override
  SelectionResult handleSelectParagraph(SelectParagraphSelectionEvent event) {
    final paragraph = event.absorb ? null : _paragraphAt(event.globalPosition);
    if (paragraph == null) return super.handleSelectParagraph(event);
    final fragments = {
      for (var i = 0; i < selectables.length; i++)
        if (paragraph.selectableBelongsToParagraph(selectables[i])) i,
    };
    if (fragments.length < 2) return super.handleSelectParagraph(event);

    handleClearSelection(const ClearSelectionEvent());
    // כל קטע מחשב את גבול הפסקה על הטקסט המלא ובוחר את החלק שלו בה.
    final selected = <int>[];
    for (final index in fragments) {
      dispatchSelectionEventToChild(selectables[index], event);
      if (selectables[index].value.status == SelectionStatus.uncollapsed) {
        selected.add(index);
      }
    }
    if (selected.isEmpty) return super.handleSelectParagraph(event);
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
    _selectedParagraph = paragraph;
    didReceiveSelectionBoundaryEvents();
    return SelectionResult.end;
  }

  @override
  SelectedContent? getSelectedContent() {
    final paragraph = _selectedParagraph;
    if (paragraph == null) return super.getSelectedContent();

    // Flutter ממיין קטעים לפי מיקום במסך. ההעתקה צריכה ללכת לפי היסט בטקסט.
    final fragments = <({int offset, String text})>[];
    for (final selectable in selectables) {
      final text = selectable.getSelectedContent()?.plainText;
      if (text == null || text.isEmpty) continue;
      if (!paragraph.selectableBelongsToParagraph(selectable)) {
        return super.getSelectedContent();
      }
      final range = selectable.getSelection()!;
      fragments.add((offset: range.startOffset, text: text));
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
