import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:window_manager/legacy.dart' show ResizeEdge;

/// כמו `VirtualWindowFrame` של window_manager ב-Windows, לחלון של ה-
/// [AppWindowScope]: הקצה העליון משנה גודל, ושאר הקצוות הם של המערכת.
class AppVirtualWindowFrame extends StatefulWidget {
  const AppVirtualWindowFrame({super.key, required this.child});

  final Widget child;

  /// עובי פסי שינוי הגודל, כמו `DragToResizeArea`.
  static const double edgeSize = 8;

  @override
  State<AppVirtualWindowFrame> createState() => _AppVirtualWindowFrameState();
}

class _AppVirtualWindowFrameState extends State<AppVirtualWindowFrame> {
  AppWindowController? _window;
  bool _resizable = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final window = AppWindowScope.controllerOf(context);
    if (identical(window, _window)) return;
    _window?.stateChanges.removeListener(_refresh);
    _window = window..stateChanges.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    _window?.stateChanges.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final window = _window;
    if (window == null) return;
    final fixed = await window.isMaximized() || await window.isFullScreen();
    if (mounted && identical(window, _window) && _resizable == fixed) {
      setState(() => _resizable = !fixed);
    }
  }

  Widget _edge(ResizeEdge edge, MouseCursor cursor, {double? width}) {
    return SizedBox(
      width: width,
      height: AppVirtualWindowFrame.edgeSize,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => (_window as AppWindowResizing).startResizing(edge),
          onDoubleTap: edge == ResizeEdge.top
              ? () => (_window as AppWindowResizing).maximizeVertically()
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_window is! AppWindowResizing) return widget.child;
    const size = AppVirtualWindowFrame.edgeSize;
    // מבנה קבוע: הילד לא נבנה מחדש כשהחלון עובר ל-maximize וחזרה.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (_resizable)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            // הפינות לפי המסך ולא לפי כיוון הטקסט (RTL).
            child: Row(
              textDirection: TextDirection.ltr,
              children: [
                _edge(
                  ResizeEdge.topLeft,
                  SystemMouseCursors.resizeUpLeft,
                  width: size,
                ),
                Expanded(
                  child: _edge(ResizeEdge.top, SystemMouseCursors.resizeUp),
                ),
                _edge(
                  ResizeEdge.topRight,
                  SystemMouseCursors.resizeUpRight,
                  width: size,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
