import 'package:flutter/material.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/pane_drop_geometry.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// עוטף את אזור הקריאה ומקבל כרטיסייה שנגררת אליו, עם חיווי חי של הצד
/// שהספר ייכנס אליו.
///
/// טאב שכבר מפוצל אינו מקבל הפלות: הפיצול הוא לשתי חלוניות בלבד, וכרטיסייה
/// שנגררת אליו נשארת במקומה בשורת הכרטיסיות.
class PaneDropTarget extends StatefulWidget {
  /// הטאב המוצג — היעד שהכרטיסייה הנגררת תפצל.
  final OpenedTab tab;

  /// תוכן הטאב.
  final Widget child;

  /// נקרא כשהמשתמש משחרר כרטיסייה מעל אזור הקריאה.
  final void Function(OpenedTab dragged, PaneDropSide side) onDrop;

  const PaneDropTarget({
    super.key,
    required this.tab,
    required this.child,
    required this.onDrop,
  });

  @override
  State<PaneDropTarget> createState() => _PaneDropTargetState();
}

class _PaneDropTargetState extends State<PaneDropTarget> {
  PaneDropSide? _side;

  /// גרירה שלא תוכל לפצל אינה מציגה חיווי: טאב שכבר מפוצל, טאב מפוצל
  /// שנגרר (פיצול אינו מקונן), או הטאב שכבר מוצג כאן.
  bool _accepts(OpenedTab dragged) =>
      widget.tab is! CombinedTab &&
      dragged is! CombinedTab &&
      !identical(dragged, widget.tab);

  void _updateSide(Offset globalOffset) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    // מסך צר מדי לשתי חלוניות קריאות אינו מציע פיצול כלל.
    final next = canSplitPane(box.size)
        ? dropSideFor(
            localPosition: box.globalToLocal(globalOffset),
            size: box.size,
            textDirection: Directionality.of(context),
          )
        : null;
    if (next != _side) setState(() => _side = next);
  }

  void _clearSide() {
    if (_side != null) setState(() => _side = null);
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<OpenedTab>(
      onWillAcceptWithDetails: (details) {
        if (!_accepts(details.data)) return false;
        _updateSide(details.offset);
        // אזור צר מכדי לפצל נדחה במפורש: קבלה שאינה מפצלת הייתה בולעת את
        // השחרור בלי חיווי, והכרטיסייה הייתה חוזרת בלי סיבה נראית.
        return _side != null;
      },
      onMove: (details) {
        if (_accepts(details.data)) _updateSide(details.offset);
      },
      onLeave: (_) => _clearSide(),
      onAcceptWithDetails: (details) {
        final side = _side;
        _clearSide();
        if (side != null) widget.onDrop(details.data, side);
      },
      builder: (context, candidate, rejected) {
        final side = _side;
        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (side != null)
              Positioned.fill(
                child: IgnorePointer(child: _DropPreview(side: side)),
              ),
          ],
        );
      },
    );
  }
}

/// המלבן המונפש שמסמן את החצי שהספר הנגרר יתפוס.
class _DropPreview extends StatelessWidget {
  final PaneDropSide side;

  const _DropPreview({required this.side});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rect = previewRectFor(
          side: side,
          size: constraints.biggest,
          textDirection: Directionality.of(context),
        );

        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppSurfaces.paneDropPreview(colorScheme),
                  border: Border.all(
                    color: AppSurfaces.paneDropPreviewBorder(colorScheme),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
