import 'package:flutter/gestures.dart' show HitTestTarget;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// משייך מאזינים במסלול הפגיעה לגלילה של Flutter.
class ScrollableHitTestRegistry {
  final Expando<ScrollableState> _scrollables = Expando();

  ScrollableState? operator [](HitTestTarget target) => _scrollables[target];

  bool capture(BuildContext? notificationContext) {
    if (notificationContext == null) return false;
    final state = Scrollable.maybeOf(notificationContext);
    if (state == null) return false;

    final root = state.context.findRenderObject();
    var node = notificationContext.findRenderObject();
    while (node != null) {
      // המאזין לגלגלת נמצא בנתיב הפגיעה; שורש ה-Scrollable לא תמיד נמצא בו.
      if (node is RenderPointerListener && node.onPointerSignal != null) {
        _scrollables[node] = state;
        break;
      }
      if (identical(node, root)) break;
      node = node.parent;
    }
    return false;
  }
}
