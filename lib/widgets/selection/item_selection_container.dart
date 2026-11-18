import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/widgets/selection/paragraph_selection_container.dart';

/// עוטף פריט של רשימת קריאה כדי שקצות הבחירה יישמרו יחסית לפריט
/// ולא יחרגו לצדדים בגרירה (ראו [_ItemSelectionDelegate]).
class ItemSelectionContainer extends StatefulWidget {
  const ItemSelectionContainer({super.key, required this.child});

  final Widget child;

  @override
  State<ItemSelectionContainer> createState() => _ItemSelectionContainerState();
}

class _ItemSelectionContainerState extends State<ItemSelectionContainer> {
  late final _delegate = _ItemSelectionDelegate(context.findRenderObject);

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionContainer(delegate: _delegate, child: widget.child);
  }
}

/// Flutter שומר את קצות הבחירה בקואורדינטות מסך ומשדר אותם שוב כשהטקסט נבנה
/// מחדש; אחרי גלילה הם נוחתים על טקסט אחר, ולכן נשמרים יחסית לפריט.
class _ItemSelectionDelegate extends ParagraphSelectionDelegate {
  _ItemSelectionDelegate(this._box) : super(_box);

  final RenderObject? Function() _box;
  final _edges = <bool, Offset>{};

  @override
  SelectionResult handleSelectionEdgeUpdate(SelectionEdgeUpdateEvent event) {
    final p = event.globalPosition;
    final text = [
      for (final s in selectables)
        MatrixUtils.transformRect(
          s.getTransformTo(null),
          s.boundingBoxes.reduce((a, b) => a.expandToInclude(b)),
        ),
    ].fold<Rect?>(null, (all, r) => all?.expandToInclude(r) ?? r);
    if (text == null ||
        p.dy < text.top ||
        p.dy >= text.bottom ||
        text.contains(p)) {
      return super.handleSelectionEdgeUpdate(event);
    }
    final edgeEvent = event.type == SelectionEventType.startEdgeUpdate
        ? SelectionEdgeUpdateEvent.forStart
        : SelectionEdgeUpdateEvent.forEnd;
    return super.handleSelectionEdgeUpdate(
      edgeEvent(
        globalPosition: Offset(
          p.dx < text.left ? text.left : text.right - 1,
          p.dy,
        ),
        granularity: event.granularity,
      ),
    );
  }

  @override
  void updateLastSelectionEdgeLocation({
    required Offset globalSelectionEdgeLocation,
    required bool forEnd,
  }) {
    if (_box() case final RenderBox box when box.attached) {
      _edges[forEnd] = box.globalToLocal(globalSelectionEdgeLocation);
    }
    super.updateLastSelectionEdgeLocation(
      globalSelectionEdgeLocation: globalSelectionEdgeLocation,
      forEnd: forEnd,
    );
  }

  @override
  void clearInternalSelectionState() {
    _edges.clear();
    super.clearInternalSelectionState();
  }

  @override
  void didChangeSelectables() {
    if (_box() case final RenderBox box when box.attached) {
      _edges.forEach(
        (forEnd, edge) => super.updateLastSelectionEdgeLocation(
          globalSelectionEdgeLocation: box.localToGlobal(edge),
          forEnd: forEnd,
        ),
      );
    }
    super.didChangeSelectables();
  }
}
