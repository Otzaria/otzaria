// ignore_for_file: implementation_imports, invalid_use_of_internal_member
import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_native.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:window_manager/legacy.dart' show ResizeEdge;

import 'second_test_view.dart';

/// בקר חלון בלי נייטיב: המצב נקבע ידנית, ו-[notify] מדמה WM_SIZE/WM_ACTIVATE.
class StubWindowController extends RegularWindowController {
  StubWindowController(FlutterView view) : super.empty() {
    rootView = view;
  }

  VoidCallback? onDestroy;
  bool destroyed = false;
  bool disposed = false;
  bool activated = false;
  bool maximized = false;
  bool minimized = false;
  bool fullscreen = false;
  final List<String> titles = [];
  BoxConstraints? constraints;

  void notify() => notifyListeners();

  @override
  void destroy() {
    if (destroyed) return;
    destroyed = true;
    onDestroy?.call();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  @override
  Size get contentSize => Size.zero;
  @override
  String get title => titles.isEmpty ? '' : titles.last;
  @override
  bool get isActivated => activated;
  @override
  bool get isMaximized => maximized;
  @override
  bool get isMinimized => minimized;
  @override
  bool get isFullscreen => fullscreen;
  @override
  void setSize(Size size) {}
  @override
  void setConstraints(BoxConstraints constraints) =>
      this.constraints = constraints;
  @override
  void setTitle(String title) => titles.add(title);
  @override
  void activate() {}
  @override
  void setMaximized(bool maximized) => this.maximized = maximized;
  @override
  void setMinimized(bool minimized) => this.minimized = minimized;
  @override
  void setFullscreen(bool fullscreen, {Display? display}) =>
      this.fullscreen = fullscreen;
}

class StubWindowHandle extends ViewWindowHandle {
  StubWindowHandle(
    this.stub,
    this._onCloseRequested, {
    this.fakeHwnd,
    this.fakeFlutterView,
    super.defersDestroy,
  }) : super.forTesting(stub);

  final StubWindowController stub;
  final void Function(ViewWindowHandle handle) _onCloseRequested;
  final int? fakeHwnd;
  final int? fakeFlutterView;

  @override
  int? get hwnd => isDestroyed ? null : fakeHwnd;

  @override
  int? get flutterViewHandle => isDestroyed ? null : fakeFlutterView;

  @override
  int? get nativeHandle => hwnd;

  /// כמו WM_CLOSE מהמערכת (X, Alt+F4).
  void requestClose() => _onCloseRequested(this);
}

/// נייטיב בזיכרון: מלבן לכל HWND, ורישום של הקריאות.
class FakeViewWindowNative implements ViewWindowNative {
  final Map<int, Rect> rects = {};
  Rect area = const Rect.fromLTWH(0, 0, 3840, 2160);
  final List<int> hooked = [];
  final List<int> focused = [];
  final List<int> dragged = [];
  final List<int> frameless = [];
  final List<int> hidden = [];
  final List<int> revealed = [];
  final List<(int, ResizeEdge)> resized = [];
  final List<int> maximizedVertically = [];
  int? foreground;
  int dpi = 96;
  final Set<int> maximizedWindows = {};

  @override
  int? foregroundWindow() => foreground;
  @override
  ({Rect normal, bool maximized, int dpi})? placement(int hwnd) {
    final rect = rects[hwnd];
    if (rect == null) return null;
    return (normal: rect, maximized: maximizedWindows.contains(hwnd), dpi: dpi);
  }

  @override
  Rect? windowRect(int hwnd) => rects[hwnd];
  @override
  void setWindowRect(int hwnd, Rect rect) => rects[hwnd] = rect;
  @override
  bool isVisible(int hwnd) => rects.containsKey(hwnd);
  @override
  void show(int hwnd) {}
  @override
  void hide(int hwnd) => hidden.add(hwnd);
  @override
  void focus(int hwnd) => focused.add(hwnd);
  @override
  void startDragging(int hwnd) => dragged.add(hwnd);
  @override
  Rect? workArea(int hwnd) => area;
  @override
  Future<void> installViewHooks(int hwnd) async => hooked.add(hwnd);
  @override
  Future<void> makeFrameless(int hwnd) async => frameless.add(hwnd);
  @override
  Future<void> reveal(int hwnd) async => revealed.add(hwnd);
  @override
  void startResizing(int hwnd, ResizeEdge edge) => resized.add((hwnd, edge));
  @override
  void maximizeVertically(int hwnd) => maximizedVertically.add(hwnd);
}

/// רשימת חלונות שכל חלון בה הוא [SecondTestView] עם בקר מדומה.
class FakeViewWindows {
  FakeViewWindows(this.tester) {
    registry = ViewWindowRegistry(factory: _create, native: native);
  }

  final WidgetTester tester;
  final FakeViewWindowNative native = FakeViewWindowNative();
  late final ViewWindowRegistry registry;
  final List<StubWindowHandle> handles = [];
  var _nextId = 100;

  /// כמו ב-Linux: הסתרה ופירוק מיד, הריסה אחרי כמה פריימים.
  bool defersDestroy = false;

  ViewWindowHandle _create({
    required Size size,
    required String title,
    required void Function(ViewWindowHandle handle) onCloseRequested,
    required void Function(ViewWindowHandle handle) onDestroyed,
  }) {
    final id = _nextId++;
    final stub = StubWindowController(SecondTestView(tester.view, viewId: id));
    final handle = StubWindowHandle(
      stub,
      onCloseRequested,
      fakeHwnd: id,
      fakeFlutterView: id + 1000,
      defersDestroy: defersDestroy,
    );
    stub.onDestroy = () => onDestroyed(handle);
    handles.add(handle);
    return handle;
  }

  StubWindowHandle handleOf(ViewWindowEntry entry) =>
      entry.handle as StubWindowHandle;

  StubWindowController stubOf(ViewWindowEntry entry) => handleOf(entry).stub;
}
