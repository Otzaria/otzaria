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
  late final _delegate = _ParagraphSelectionDelegate(context.findRenderObject);

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  // בלי SelectionArea מעל, מיכל בחירה יתום משנה את רינדור הטקסט.
  @override
  Widget build(BuildContext context) =>
      SelectionContainer.maybeOf(context) == null
      ? widget.child
      : SelectionContainer(delegate: _delegate, child: widget.child);
}

class _ParagraphSelectionDelegate extends StaticSelectionContainerDelegate {
  _ParagraphSelectionDelegate(this._root);

  final RenderObject? Function() _root;

  @override
  SelectionResult handleSelectParagraph(SelectParagraphSelectionEvent event) {
    final fragments = event.absorb
        ? null
        : _paragraphFragmentsAt(event.globalPosition);
    if (fragments == null) return super.handleSelectParagraph(event);

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
    didReceiveSelectionBoundaryEvents();
    return SelectionResult.end;
  }

  /// אינדקסי קטעי הבחירה של הפסקה שתחת [globalPosition]; null — הפסקה לא
  /// מפוצלת, ונשארים בטיפול הרגיל.
  List<int>? _paragraphFragmentsAt(Offset globalPosition) {
    RenderParagraph? paragraph;
    void visit(RenderObject object) {
      if (object is RenderParagraph &&
          object.attached &&
          object.hasSize &&
          object.paintBounds.contains(object.globalToLocal(globalPosition))) {
        paragraph = object;
      }
      object.visitChildren(visit);
    }

    final root = _root();
    if (root == null) return null;
    visit(root);
    final target = paragraph;
    if (target == null) return null;
    final fragments = [
      for (var i = 0; i < selectables.length; i++)
        if (target.selectableBelongsToParagraph(selectables[i])) i,
    ];
    return fragments.length > 1 ? fragments : null;
  }
}
