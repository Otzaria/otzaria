import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/windowing/multiview/view_window_native.dart';
import 'package:window_manager/legacy.dart' show ResizeEdge;

/// macOS: ערוץ `otzaria/view_window` של ה-runner. הידית היא `NSWindow*`.
/// הגאומטריה נשארת בנקודות מסך גלובליות, גם בין מסכים בעלי קנה מידה שונה.
class CocoaViewWindowNative implements ViewWindowNative {
  const CocoaViewWindowNative({this._channel = defaultChannel});

  static const MethodChannel defaultChannel = MethodChannel(
    'otzaria/view_window',
  );

  /// תקרה ל-handshake: הוא רץ לפני הפריים הראשון.
  static const Duration handshakeTimeout = Duration(seconds: 2);

  final MethodChannel _channel;

  /// חלון שנהרס, ערוץ חסר או ארגומנט שגוי — null, כמו ב-win32 על HWND מת.
  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      debugPrint('view_window.$method failed: ${e.code} ${e.message}');
    } on MissingPluginException {
      debugPrint('view_window.$method: no handler in the runner');
    }
    return null;
  }

  Future<T?> _window<T>(
    String method,
    int hwnd, [
    Map<String, Object?> extra = const {},
  ]) => _invoke<T>(method, {'handle': hwnd, ...extra});

  static Rect? _rect(Object? value) {
    if (value is! Map) return null;
    final x = value['x'], y = value['y'];
    final width = value['width'], height = value['height'];
    if (x is! num || y is! num || width is! num || height is! num) return null;
    return Rect.fromLTWH(
      x.toDouble(),
      y.toDouble(),
      width.toDouble(),
      height.toDouble(),
    );
  }

  /// null כשמוכן; אחרת הסיבה מה-runner. לפני [installWindowingOwner] במק.
  Future<String?> multiViewUnavailableReason({
    Duration timeout = handshakeTimeout,
  }) async {
    try {
      final ready = await _channel
          .invokeMethod<bool>('multiViewReady')
          .timeout(timeout);
      if (ready == true) return null;
      final status = await _channel
          .invokeMethod<String>('multiViewStatus')
          .timeout(timeout);
      return status ?? 'not ready';
    } on TimeoutException {
      return 'no answer in ${timeout.inMilliseconds}ms';
    } on MissingPluginException {
      return 'runner without otzaria/view_window';
    } on PlatformException catch (e) {
      return 'handshake failed: ${e.code} ${e.message}';
    }
  }

  /// לחיצה על ה-Dock כשאין חלון גלוי. [onReopen] מחזיר true כשהציג חלון;
  /// אחרת ה-runner משחזר בעצמו. ה-runner שואל רק אחרי `enableReopenHandling`.
  Future<void> handleDockReopen(Future<bool> Function() onReopen) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'reopenRequested') {
        throw MissingPluginException(call.method);
      }
      try {
        return await onReopen();
      } catch (e) {
        debugPrint('reopenRequested failed: $e');
        return false;
      }
    });
    await _invoke<void>('enableReopenHandling');
  }

  @override
  Future<Rect?> windowRect(int hwnd) async {
    return _rect(await _window<Object?>('frame', hwnd));
  }

  @override
  Future<void> setWindowRect(int hwnd, Rect rect) async {
    await _window<void>('setFrame', hwnd, {
      'x': rect.left,
      'y': rect.top,
      'width': rect.width,
      'height': rect.height,
    });
  }

  /// גם חלון שקוף עד הפריים הראשון נחשב גלוי (`NSWindow.isVisible`).
  @override
  Future<bool> isVisible(int hwnd) async =>
      await _window<bool>('isVisible', hwnd) ?? false;

  @override
  Future<void> show(int hwnd) => _window<void>('orderFront', hwnd);

  /// אין `orderOut` בערוץ: רק הריסה נדחית (Linux) מסתירה, ובמק ההריסה מיידית.
  @override
  Future<void> hide(int hwnd) async {}

  @override
  Future<void> focus(int hwnd) => _window<void>('makeKey', hwnd);

  @override
  Future<void> startDragging(int hwnd) => _window<void>('startDragging', hwnd);

  /// המערכת משנה גודל מהקצוות בעצמה (`.resizable` נשאר).
  @override
  Future<void> startResizing(int hwnd, ResizeEdge edge) async {}

  @override
  Future<void> maximizeVertically(int hwnd) async {}

  @override
  Future<Rect?> workArea(int hwnd) async {
    return _rect(await _window<Object?>('visibleFrame', hwnd));
  }

  @override
  Future<int?> foregroundWindow() => _invoke<int>('keyWindow');

  /// ההיסט בנקודות, ולכן DPI 96 גם במסך Retina.
  @override
  Future<({Rect normal, bool maximized, int dpi})?> placement(int hwnd) async {
    final value = await _window<Object?>('placement', hwnd);
    final frame = _rect(value);
    if (frame == null) return null;
    return (
      normal: frame,
      maximized: value is Map && value['maximized'] == true,
      dpi: 96,
    );
  }

  @override
  Future<void> installViewHooks(int hwnd) async {}

  /// מיד אחרי היצירה, בעוד החלון שקוף. `cloak` הוא גיבוי ל-hook של ה-runner;
  /// false שלו הוא גם "כבר מוסתר", ולכן אינו נבדק.
  @override
  Future<void> makeFrameless(int hwnd) async {
    await _window<bool>('cloak', hwnd);
    await _window<void>('makeFrameless', hwnd);
  }

  @override
  Future<void> reveal(int hwnd) async {
    final revealed = await _window<bool>('reveal', hwnd, {'activate': true});
    if (revealed != true) debugPrint('view_window.reveal: not a Dart window');
  }
}
