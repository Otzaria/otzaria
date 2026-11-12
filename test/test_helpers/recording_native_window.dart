import 'dart:async';

import 'package:nativeapi/nativeapi.dart' as nativeapi;

/// A strict in-memory nativeapi Window for test code which still exercises the
/// production window_manager 0.6 compatibility facade. No OS window is made.
class RecordingNativeWindow extends nativeapi.Window {
  RecordingNativeWindow({
    this.visible = true,
    this.minimized = false,
    this.maximized = false,
    this.fullScreen = false,
    this.windowOpacity = 1,
    nativeapi.Rectangle? initialBounds,
  }) : nativeBounds =
           initialBounds ??
           const nativeapi.Rectangle(x: 1, y: 2, width: 3, height: 4),
       super.borrowed(0);

  final List<String> calls = <String>[];
  bool visible;
  bool minimized;
  bool maximized;
  bool fullScreen;
  double windowOpacity;
  nativeapi.Rectangle nativeBounds;
  nativeapi.Size? minimum;
  nativeapi.TitleBarStyle? barStyle;
  bool? controlButtonsVisible;
  final Map<int, FutureOr<void> Function(nativeapi.WindowEvent)> _listeners =
      {};
  int _nextListener = 1;

  Future<void> emit(nativeapi.WindowEvent event) async {
    for (final callback in List.of(_listeners.values)) {
      await callback(event);
    }
  }

  @override
  nativeapi.ListenerId addListener(
    FutureOr<void> Function(nativeapi.WindowEvent) callback,
  ) {
    final id = _nextListener++;
    _listeners[id] = callback;
    return id;
  }

  @override
  bool removeListener(nativeapi.ListenerId id) => _listeners.remove(id) != null;

  @override
  bool get isVisible => visible;

  @override
  bool get isMinimized => minimized;

  @override
  bool get isMaximized => maximized;

  @override
  bool get isFullScreen => fullScreen;

  @override
  set isFullScreen(bool value) {
    calls.add('setFullScreen');
    fullScreen = value;
  }

  @override
  double get opacity => windowOpacity;

  @override
  void show() {
    calls.add('show');
    visible = true;
  }

  @override
  void showInactive() {
    calls.add('showInactive');
    visible = true;
  }

  @override
  void hide() {
    calls.add('hide');
    visible = false;
  }

  @override
  void focus() => calls.add('focus');

  @override
  void blur() => calls.add('blur');

  @override
  void minimize() {
    calls.add('minimize');
    minimized = true;
  }

  @override
  void maximize() {
    calls.add('maximize');
    maximized = true;
  }

  @override
  void unmaximize() {
    calls.add('unmaximize');
    maximized = false;
  }

  @override
  void restore() {
    calls.add('restore');
    minimized = false;
  }

  @override
  void startDragging() => calls.add('startDragging');

  @override
  void center() => calls.add('center');

  @override
  bool close() {
    calls.add('close');
    return true;
  }

  @override
  nativeapi.Rectangle get bounds {
    calls.add('getBounds');
    return nativeBounds;
  }

  @override
  set bounds(nativeapi.Rectangle value) {
    calls.add('setBounds');
    nativeBounds = value;
  }

  @override
  nativeapi.Size get size {
    calls.add('getSize');
    return nativeapi.Size(
      width: nativeBounds.width,
      height: nativeBounds.height,
    );
  }

  @override
  void setSize(nativeapi.Size size, bool animate) {
    calls.add('setSize');
    nativeBounds = nativeapi.Rectangle(
      x: nativeBounds.x,
      y: nativeBounds.y,
      width: size.width,
      height: size.height,
    );
  }

  @override
  set minimumSize(nativeapi.Size value) {
    calls.add('setMinimumSize');
    minimum = value;
  }

  @override
  set titleBarStyle(nativeapi.TitleBarStyle value) {
    calls.add('setTitleBarStyle');
    barStyle = value;
  }

  @override
  set isWindowControlButtonsVisible(bool value) {
    calls.add('setWindowControlButtonsVisible');
    controlButtonsVisible = value;
  }
}
