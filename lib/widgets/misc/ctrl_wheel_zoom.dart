import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/widgets/misc/middle_click_autoscroll.dart';

/// Turns Ctrl + wheel (Cmd + wheel on Mac, as in browsers) into zoom steps.
/// Touchpads without a precision driver send their pinch the same way.
class CtrlWheelZoom extends SingleChildRenderObjectWidget {
  const CtrlWheelZoom({super.key, required this.onZoom, super.child});

  /// Called once per wheel notch; [zoomIn] when the wheel turns away from
  /// the user.
  final void Function(bool zoomIn) onZoom;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderCtrlWheelZoom(onZoom: onZoom);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCtrlWheelZoom renderObject,
  ) {
    renderObject.onZoom = onZoom;
  }
}

class RenderCtrlWheelZoom extends RenderProxyBox {
  RenderCtrlWheelZoom({required this.onZoom});

  void Function(bool zoomIn) onZoom;

  /// The scroll distance of one zoom step. A Windows wheel notch is 33 to 100
  /// and makes one step; a pinch arrives as small deltas that add up to it.
  static const double stepDistance = 30;

  double _pending = 0;

  /// Added before the children, so this claims the wheel before a nested
  /// scrollable scrolls with it.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return hitTestChildren(result, position: position);
  }

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) {
    if (event is! PointerScrollEvent ||
        event.device == kAutoScrollSyntheticDevice ||
        event.scrollDelta.dy == 0) {
      return;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!ShortcutHelper.isCtrlOrMacCmdOnly ||
        keyboard.isShiftPressed ||
        keyboard.isAltPressed) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (claimed) => _addDelta((claimed as PointerScrollEvent).scrollDelta.dy),
    );
  }

  void _addDelta(double dy) {
    if (_pending != 0 && _pending.sign != dy.sign) _pending = 0;
    _pending += dy;
    if (_pending.abs() < stepDistance) return;
    onZoom(_pending < 0);
    _pending = 0;
  }
}
