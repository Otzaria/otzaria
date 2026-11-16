import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/app_virtual_window_frame.dart';

/// מצב הכפתור כפי שהמערכת רואה אותו, כשהיא ולא Flutter מקבלת את העכבר.
typedef SnapButtonBuilder =
    Widget Function(BuildContext context, bool hovered, bool pressed);

/// כפתור הגדלה שמציג את תפריט Snap Layouts של Windows 11 (#4021). מעליו העכבר
/// עובר ל-runner (HTMAXBUTTON), שמחזיר ריחוף, לחיצה והקלקה.
class SnapLayoutsMaximizeButton extends StatefulWidget {
  const SnapLayoutsMaximizeButton({
    super.key,
    required this.window,
    required this.maximized,
    required this.onPressed,
    required this.builder,
  });

  /// 0 לחלון הראשי, אחרת ה-HWND של חלון Dart; null מכבה (לא Windows).
  final int? window;

  /// מצב ההגדלה שכבר נקרא בידי כפתורי הכותרת.
  final bool maximized;
  final VoidCallback onPressed;
  final SnapButtonBuilder builder;

  @override
  State<SnapLayoutsMaximizeButton> createState() =>
      _SnapLayoutsMaximizeButtonState();
}

class _SnapLayoutsMaximizeButtonState extends State<SnapLayoutsMaximizeButton> {
  final _probeKey = GlobalKey();
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    SnapLayoutsBridge.instance._attach(this);
  }

  @override
  void didUpdateWidget(SnapLayoutsMaximizeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.window != widget.window) {
      SnapLayoutsBridge.instance._detach(this, oldWidget.window);
      _setState(hovered: false, pressed: false);
      SnapLayoutsBridge.instance._attach(this);
    }
  }

  @override
  void dispose() {
    SnapLayoutsBridge.instance._detach(this, widget.window);
    super.dispose();
  }

  void _setState({required bool hovered, required bool pressed}) {
    if (_hovered == hovered && _pressed == pressed) return;
    if (!mounted) return;
    setState(() {
      _hovered = hovered;
      _pressed = pressed;
    });
  }

  /// המלבן הנייטיבי בפיקסלים פיזיים, או null כשמשהו אחר מקבל חלק ממנו.
  Rect? _exposedRect() {
    final box = _probeKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final view = View.maybeOf(context);
    if (view == null) return null;
    var rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    // פס שינוי הגודל נשאר של Flutter; רק שאר הכפתור עובר ל-Windows.
    if (!widget.maximized) {
      rect = rect.intersect(
        Rect.fromLTRB(
          rect.left,
          AppVirtualWindowFrame.edgeSize,
          rect.right,
          rect.bottom,
        ),
      );
    }
    if (rect.isEmpty) return null;
    // פינות, אמצעי הצלעות והמרכז: כל מלבן גדול מהכפתור שחופף לו (תפריט,
    // דיאלוג) מכסה פינה אחת לפחות; המרכז לבדו מפספס תפריט שמכסה רק קצה.
    final inner = rect.deflate(1);
    for (final x in [inner.left, inner.center.dx, inner.right]) {
      for (final y in [inner.top, inner.center.dy, inner.bottom]) {
        if (!_isTopmostAt(box, Offset(x, y), view.viewId)) return null;
      }
    }
    final ratio = view.devicePixelRatio;
    return Rect.fromLTRB(
      (rect.left * ratio).roundToDouble(),
      (rect.top * ratio).ceilToDouble(),
      (rect.right * ratio).roundToDouble(),
      (rect.bottom * ratio).roundToDouble(),
    );
  }

  static bool _isTopmostAt(RenderObject box, Offset position, int viewId) {
    final result = HitTestResult();
    GestureBinding.instance.hitTestInView(result, position, viewId);
    if (result.path.isEmpty) return false;
    final target = result.path.first.target;
    RenderObject? node = target is RenderObject ? target : null;
    while (node != null) {
      if (identical(node, box)) return true;
      node = node.parent;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: _probeKey,
    child: widget.builder(context, _hovered, _pressed),
  );
}

/// הערוץ מול ה-runner, ובדיקה אחרי כל פריים שהכפתורים עדיין חשופים.
class SnapLayoutsBridge {
  SnapLayoutsBridge._();

  static final instance = SnapLayoutsBridge._();

  static const MethodChannel channel = MethodChannel('otzaria/snap_layouts');

  /// דורס את זמינות הפלטפורמה **בבדיקות בלבד**.
  @visibleForTesting
  static bool? debugPlatformOverride;

  static bool get _platformMaySupport =>
      debugPlatformOverride ?? (!kIsWeb && Platform.isWindows);

  final Map<int, _SnapLayoutsMaximizeButtonState> _buttons = {};
  final Map<int, Rect?> _sent = {};

  /// false אחרי שה-runner ענה שאין Snap Layouts (Windows 10) או אין ערוץ.
  bool _supported = true;
  bool _frameCallbackPending = false;
  bool _handlerInstalled = false;

  void _attach(_SnapLayoutsMaximizeButtonState button) {
    final window = button.widget.window;
    if (window == null || !_platformMaySupport || !_supported) return;
    _buttons[window] = button;
    if (!_handlerInstalled) {
      _handlerInstalled = true;
      channel.setMethodCallHandler(_handle);
    }
    _scheduleCheck();
  }

  void _detach(_SnapLayoutsMaximizeButtonState button, int? window) {
    if (window == null || !identical(_buttons[window], button)) return;
    _buttons.remove(window);
    _publish(window, null);
  }

  void _scheduleCheck() {
    if (_frameCallbackPending || _buttons.isEmpty) return;
    _frameCallbackPending = true;
    // לא מבקש פריים: הבדיקה רצה רק אחרי פריים שכבר צויר.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _frameCallbackPending = false;
      if (!_supported) return;
      for (final MapEntry(key: window, value: button)
          in _buttons.entries.toList()) {
        if (button.mounted) _publish(window, button._exposedRect());
      }
      _scheduleCheck();
    }, debugLabel: 'SnapLayoutsBridge.check');
  }

  void _publish(int window, Rect? rect) {
    if (!_supported) return;
    if (_sent.containsKey(window) && _sent[window] == rect) return;
    if (rect == null && !_sent.containsKey(window)) return;
    if (rect == null) {
      _sent.remove(window);
    } else {
      _sent[window] = rect;
    }
    unawaited(_send(window, rect));
  }

  Future<void> _send(int window, Rect? rect) async {
    try {
      final ok = await channel.invokeMethod<bool>('setMaximizeButton', {
        'hwnd': window,
        'left': rect?.left.toInt() ?? 0,
        'top': rect?.top.toInt() ?? 0,
        'right': rect?.right.toInt() ?? 0,
        'bottom': rect?.bottom.toInt() ?? 0,
      });
      if (ok != true && rect != null) _disable();
    } on MissingPluginException {
      _disable();
    } on PlatformException {
      _disable();
    }
  }

  void _disable() {
    _supported = false;
    _sent.clear();
    for (final button in _buttons.values) {
      button._setState(hovered: false, pressed: false);
    }
  }

  Future<void> _handle(MethodCall call) async {
    if (call.method != 'maximizeButton') return;
    final args = (call.arguments as Map).cast<String, Object?>();
    final button = _buttons[args['hwnd']];
    if (button == null || !button.mounted) return;
    button._setState(
      hovered: args['hovered'] == true,
      pressed: args['pressed'] == true,
    );
    if (args['clicked'] == true) button.widget.onPressed();
  }

  /// מאפס את המצב בין בדיקות.
  @visibleForTesting
  void debugReset() {
    _buttons.clear();
    _sent.clear();
    _supported = true;
    _frameCallbackPending = false;
    if (_handlerInstalled) channel.setMethodCallHandler(null);
    _handlerInstalled = false;
  }
}
