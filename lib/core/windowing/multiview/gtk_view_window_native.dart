import 'dart:ffi';
import 'dart:ui' show Rect;

import 'package:ffi/ffi.dart';
import 'package:otzaria/core/windowing/multiview/view_window_native.dart';
import 'package:window_manager/legacy.dart' show ResizeEdge;

/// Linux: GTK3 ב-FFI מתוך התהליך. GTK עובד ביחידות לוגיות, וכאן מכפילים בקנה
/// המידה של החלון כדי שהממשק יישאר בפיקסלים פיזיים, כמו ב-Windows.
class GtkViewWindowNative implements ViewWindowNative {
  const GtkViewWindowNative();

  static final _normalRectKey = 'otzaria-normal-rect'.toNativeUtf8();

  static Rect? _normalRect(int hwnd) {
    final value = _Gtk.getData(_p(hwnd), _normalRectKey).cast<_GdkRectangle>();
    if (value == nullptr) return null;
    final rect = value.ref;
    return Rect.fromLTWH(
      rect.x.toDouble(),
      rect.y.toDouble(),
      rect.width.toDouble(),
      rect.height.toDouble(),
    );
  }

  static void _rememberNormalRect(int hwnd, Rect rect) {
    final value = calloc<_GdkRectangle>();
    value.ref
      ..x = rect.left.round()
      ..y = rect.top.round()
      ..width = rect.width.round()
      ..height = rect.height.round();
    _Gtk.setData(_p(hwnd), _normalRectKey, value.cast(), _Gtk.free);
  }

  static const int _maximizedState = 1 << 2; // GDK_WINDOW_STATE_MAXIMIZED
  static const int _unplacedStates = (1 << 1) | (1 << 2) | (1 << 4);

  static Pointer<Void> _p(int handle) => Pointer<Void>.fromAddress(handle);

  static int _scale(int handle) {
    final scale = _Gtk.scaleFactor(_p(handle));
    return scale > 0 ? scale : 1;
  }

  static int _state(int handle) {
    final gdkWindow = _Gtk.widgetGetWindow(_p(handle));
    return gdkWindow == nullptr ? 0 : _Gtk.gdkWindowGetState(gdkWindow);
  }

  @override
  Rect? windowRect(int hwnd) {
    final x = calloc<Int>(), y = calloc<Int>();
    final w = calloc<Int>(), h = calloc<Int>();
    try {
      _Gtk.getPosition(_p(hwnd), x, y);
      _Gtk.getSize(_p(hwnd), w, h);
      final s = _scale(hwnd).toDouble();
      final rect = Rect.fromLTWH(
        x.value * s,
        y.value * s,
        w.value * s,
        h.value * s,
      );
      if (_state(hwnd) & _unplacedStates == 0) _rememberNormalRect(hwnd, rect);
      return rect;
    } finally {
      calloc
        ..free(x)
        ..free(y)
        ..free(w)
        ..free(h);
    }
  }

  @override
  void setWindowRect(int hwnd, Rect rect) {
    final s = _scale(hwnd);
    // ב-Wayland המיקום נדחה על ידי הקומפוזיטור; הגודל חל.
    _Gtk.move(_p(hwnd), rect.left ~/ s, rect.top ~/ s);
    _Gtk.resize(_p(hwnd), rect.width ~/ s, rect.height ~/ s);
    if (_state(hwnd) & _unplacedStates == 0) _rememberNormalRect(hwnd, rect);
  }

  @override
  bool isVisible(int hwnd) => _Gtk.getVisible(_p(hwnd)) != 0;

  @override
  void show(int hwnd) => _Gtk.show(_p(hwnd));

  @override
  void hide(int hwnd) => _Gtk.hide(_p(hwnd));

  @override
  void focus(int hwnd) => _Gtk.present(_p(hwnd));

  static ({int x, int y})? _pointer(int hwnd) {
    final display = _Gtk.widgetGetDisplay(_p(hwnd));
    if (display == nullptr) return null;
    final device = _Gtk.seatGetPointer(_Gtk.displayGetDefaultSeat(display));
    if (device == nullptr) return null;
    final x = calloc<Int>(), y = calloc<Int>();
    try {
      _Gtk.deviceGetPosition(device, nullptr, x, y);
      return (x: x.value, y: y.value);
    } finally {
      calloc
        ..free(x)
        ..free(y);
    }
  }

  // כמו window_manager: לחצן 1 במיקום הסמן, בזמן שהלחצן עוד לחוץ.
  @override
  void startDragging(int hwnd) {
    final at = _pointer(hwnd);
    if (at == null) return;
    _Gtk.beginMoveDrag(_p(hwnd), 1, at.x, at.y, _currentTime);
  }

  // GdkWindowEdge.
  static const Map<ResizeEdge, int> _edges = {
    ResizeEdge.topLeft: 0,
    ResizeEdge.top: 1,
    ResizeEdge.topRight: 2,
    ResizeEdge.left: 3,
    ResizeEdge.right: 4,
    ResizeEdge.bottomLeft: 5,
    ResizeEdge.bottom: 6,
    ResizeEdge.bottomRight: 7,
  };

  @override
  void startResizing(int hwnd, ResizeEdge edge) {
    final at = _pointer(hwnd);
    if (at == null) return;
    _Gtk.beginResizeDrag(_p(hwnd), _edges[edge]!, 1, at.x, at.y, _currentTime);
  }

  static const int _currentTime = 0; // GDK_CURRENT_TIME

  /// ל-GTK אין מיקסום אנכי.
  @override
  void maximizeVertically(int hwnd) {}

  @override
  Rect? workArea(int hwnd) {
    final gdkWindow = _Gtk.widgetGetWindow(_p(hwnd));
    final display = _Gtk.widgetGetDisplay(_p(hwnd));
    if (gdkWindow == nullptr || display == nullptr) return null;
    final monitor = _Gtk.monitorAtWindow(display, gdkWindow);
    if (monitor == nullptr) return null;
    final area = calloc<_GdkRectangle>();
    try {
      _Gtk.monitorGetWorkarea(monitor, area);
      final s = _scale(hwnd).toDouble();
      final r = area.ref;
      return Rect.fromLTWH(r.x * s, r.y * s, r.width * s, r.height * s);
    } finally {
      calloc.free(area);
    }
  }

  @override
  int? foregroundWindow() {
    final list = _Gtk.listToplevels();
    try {
      for (var item = list; item != nullptr; item = item.ref.next) {
        final window = item.ref.data;
        if (_Gtk.isActive(window) != 0) return window.address;
      }
      return null;
    } finally {
      _Gtk.listFree(list);
    }
  }

  @override
  ({Rect normal, bool maximized, int dpi})? placement(int hwnd) {
    final rect = windowRect(hwnd);
    if (rect == null) return null;
    final state = _state(hwnd);
    Rect normal = rect;
    if (state & _unplacedStates != 0) {
      final w = calloc<Int>(), h = calloc<Int>();
      try {
        _Gtk.getDefaultSize(_p(hwnd), w, h);
        final scale = _scale(hwnd);
        normal =
            _normalRect(hwnd) ??
            Rect.fromLTWH(
              rect.left,
              rect.top,
              (w.value > 0 ? w.value : 1280) * scale.toDouble(),
              (h.value > 0 ? h.value : 800) * scale.toDouble(),
            );
      } finally {
        calloc
          ..free(w)
          ..free(h);
      }
    }
    return (
      normal: normal,
      maximized: state & _maximizedState != 0,
      dpi: 96 * _scale(hwnd),
    );
  }

  /// התיקונים של #1441 ו-#1645 שייכים ל-runner של Windows.
  @override
  Future<void> installViewHooks(int hwnd) async {
    windowRect(hwnd);
  }

  /// כמו `TitleBarStyle.hidden` בחלון הראשי: בלי כותרת ומסגרת של המערכת.
  @override
  Future<void> makeFrameless(int hwnd) async => _Gtk.setDecorated(_p(hwnd), 0);

  @override
  Future<void> reveal(int hwnd) async => show(hwnd);
}

final class _GList extends Struct {
  external Pointer<Void> data;
  external Pointer<_GList> next;
  external Pointer<_GList> prev;
}

final class _GdkRectangle extends Struct {
  @Int()
  external int x;
  @Int()
  external int y;
  @Int()
  external int width;
  @Int()
  external int height;
}

typedef _VoidPtr = Void Function(Pointer<Void>);
typedef _DartVoidPtr = void Function(Pointer<Void>);
typedef _IntPtr = Int Function(Pointer<Void>);
typedef _DartIntPtr = int Function(Pointer<Void>);
typedef _PtrPtr = Pointer<Void> Function(Pointer<Void>);
typedef _TwoInts = Void Function(Pointer<Void>, Int, Int);
typedef _DartTwoInts = void Function(Pointer<Void>, int, int);
typedef _TwoOut = Void Function(Pointer<Void>, Pointer<Int>, Pointer<Int>);
typedef _DartTwoOut = void Function(Pointer<Void>, Pointer<Int>, Pointer<Int>);

/// הקישור נפתר בקריאה הראשונה, ולכן אינו נוגע בספריות מחוץ ל-Linux.
abstract final class _Gtk {
  static final DynamicLibrary _lib = DynamicLibrary.process();

  static final getData = _lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)
      >('g_object_get_data');
  static final free = _lib.lookup<NativeFunction<Void Function(Pointer<Void>)>>(
    'g_free',
  );
  static final setData = _lib
      .lookupFunction<
        Void Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Void>,
          Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
        ),
        void Function(
          Pointer<Void>,
          Pointer<Utf8>,
          Pointer<Void>,
          Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
        )
      >('g_object_set_data_full');
  static final getDefaultSize = _lib.lookupFunction<_TwoOut, _DartTwoOut>(
    'gtk_window_get_default_size',
  );
  static final getPosition = _lib.lookupFunction<_TwoOut, _DartTwoOut>(
    'gtk_window_get_position',
  );
  static final getSize = _lib.lookupFunction<_TwoOut, _DartTwoOut>(
    'gtk_window_get_size',
  );
  static final move = _lib.lookupFunction<_TwoInts, _DartTwoInts>(
    'gtk_window_move',
  );
  static final resize = _lib.lookupFunction<_TwoInts, _DartTwoInts>(
    'gtk_window_resize',
  );
  static final scaleFactor = _lib.lookupFunction<_IntPtr, _DartIntPtr>(
    'gtk_widget_get_scale_factor',
  );
  static final getVisible = _lib.lookupFunction<_IntPtr, _DartIntPtr>(
    'gtk_widget_get_visible',
  );
  static final show = _lib.lookupFunction<_VoidPtr, _DartVoidPtr>(
    'gtk_widget_show',
  );
  static final hide = _lib.lookupFunction<_VoidPtr, _DartVoidPtr>(
    'gtk_widget_hide',
  );
  static final present = _lib.lookupFunction<_VoidPtr, _DartVoidPtr>(
    'gtk_window_present',
  );
  static final isActive = _lib.lookupFunction<_IntPtr, _DartIntPtr>(
    'gtk_window_is_active',
  );
  static final setDecorated = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Int),
        void Function(Pointer<Void>, int)
      >('gtk_window_set_decorated');
  static final widgetGetWindow = _lib.lookupFunction<_PtrPtr, _PtrPtr>(
    'gtk_widget_get_window',
  );
  static final widgetGetDisplay = _lib.lookupFunction<_PtrPtr, _PtrPtr>(
    'gtk_widget_get_display',
  );
  static final gdkWindowGetState = _lib.lookupFunction<_IntPtr, _DartIntPtr>(
    'gdk_window_get_state',
  );
  static final monitorAtWindow = _lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Void>)
      >('gdk_display_get_monitor_at_window');
  static final monitorGetWorkarea = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<_GdkRectangle>),
        void Function(Pointer<Void>, Pointer<_GdkRectangle>)
      >('gdk_monitor_get_workarea');
  static final displayGetDefaultSeat = _lib.lookupFunction<_PtrPtr, _PtrPtr>(
    'gdk_display_get_default_seat',
  );
  static final seatGetPointer = _lib.lookupFunction<_PtrPtr, _PtrPtr>(
    'gdk_seat_get_pointer',
  );
  static final deviceGetPosition = _lib
      .lookupFunction<
        Void Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<Int>,
          Pointer<Int>,
        ),
        void Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<Int>,
          Pointer<Int>,
        )
      >('gdk_device_get_position');
  static final beginMoveDrag = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Int, Int, Int, Uint32),
        void Function(Pointer<Void>, int, int, int, int)
      >('gtk_window_begin_move_drag');
  static final beginResizeDrag = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Int, Int, Int, Int, Uint32),
        void Function(Pointer<Void>, int, int, int, int, int)
      >('gtk_window_begin_resize_drag');
  static final listToplevels = _lib
      .lookupFunction<Pointer<_GList> Function(), Pointer<_GList> Function()>(
        'gtk_window_list_toplevels',
      );
  static final listFree = _lib
      .lookupFunction<
        Void Function(Pointer<_GList>),
        void Function(Pointer<_GList>)
      >('g_list_free');
}
