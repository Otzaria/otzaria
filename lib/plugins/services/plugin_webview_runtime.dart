import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_runtime.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_focus.dart';

/// מה ה-WebView יודע לעשות כשמופע עוזב את המסך.
@visibleForTesting
enum PluginSuspendMode {
  /// Windows (TrySuspend) ו-Android (onPause).
  nativePause,

  /// Linux: הדף מסומן מוסתר.
  visibility,

  /// iOS/macOS: רק האירוע, והתוסף עוצר בעצמו.
  eventOnly,
}

/// [PluginRuntime] של תוסף שרץ ב-WebView.
class WebViewPluginRuntime implements PluginRuntime {
  WebViewPluginRuntime._(this.controller);

  /// אותו controller מחזיר תמיד אותו מופע — ה-dispatcher מזהה מנוע לפי זהות.
  factory WebViewPluginRuntime.of(InAppWebViewController controller) =>
      _byController[controller] ??= WebViewPluginRuntime._(controller);

  static final Expando<WebViewPluginRuntime> _byController = Expando();

  final InAppWebViewController controller;

  static const _nativeLifecycleTimeout = Duration(seconds: 6);

  /// לפי טבלת `isMethodSupported` של הפורק; לא נשאלת בזמן ריצה כי היא דורשת
  /// מימוש פלטפורמה רשום.
  @visibleForTesting
  static PluginSuspendMode get suspendMode => switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.android => PluginSuspendMode.nativePause,
    TargetPlatform.linux => PluginSuspendMode.visibility,
    _ => PluginSuspendMode.eventOnly,
  };

  static const _pauseMediaScript =
      "document.querySelectorAll('audio,video')"
      '.forEach(function (m) { m.pause(); });';

  /// ב-Windows ההקפאה עוצרת מדיה; ב-Apple וב-Linux עוצרים אותה במפורש.
  static bool get _suspendsMediaExplicitly => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS || TargetPlatform.linux => true,
    _ => false,
  };

  @override
  Future<void> evaluate(String source) =>
      controller.evaluateJavascript(source: source);

  @override
  Future<Object?> dispatchEventWithAck(String topic, String detailJson) async {
    final result = await controller.callAsyncJavaScript(
      functionBody:
          "if (!window.flutter_inappwebview || "
          "!window.flutter_inappwebview.callHandler) "
          "{ return 'no-bridge'; } "
          "if (!window.Otzaria || window.Otzaria._booted !== true) "
          "{ return 'no-page-world'; } "
          "window.dispatchEvent(new CustomEvent('$topic', "
          "{ detail: $detailJson })); "
          "return (await window.flutter_inappwebview"
          ".callHandler('otzaria_bridge_ping')) === true;",
    );
    return result?.value;
  }

  // בלי pause נייטיבי הדף מעולם לא הוקפא, ו-callAsyncJavaScript פחות בשל
  // שם (Linux beta).
  @override
  bool get freezesWhenSuspended => suspendMode == PluginSuspendMode.nativePause;

  @override
  Future<bool> setSuspended(
    bool suspended, {
    required bool Function() isCurrent,
    required bool Function() isShown,
  }) async {
    switch (suspendMode) {
      case PluginSuspendMode.nativePause:
        if (suspended) {
          // LOW לפני ההקפאה: renderer שכבר הוקפא אינו מקצץ את ה-working set.
          await _setWindowsMemoryTarget(MemoryUsageTargetLevel.LOW);
          if (!isCurrent() || isShown()) return false;
          await controller.pause().timeout(_nativeLifecycleTimeout);
        } else {
          await controller.resume().timeout(_nativeLifecycleTimeout);
          if (!isCurrent()) return false;
          await _setWindowsMemoryTarget(MemoryUsageTargetLevel.NORMAL);
        }
      case PluginSuspendMode.visibility:
        await controller
            .setVisible(visible: !suspended)
            .timeout(_nativeLifecycleTimeout);
      case PluginSuspendMode.eventOnly:
        break;
    }
    if (!isCurrent()) return false;
    if (_suspendsMediaExplicitly) {
      final media = controller.setAllMediaPlaybackSuspended(
        suspended: suspended,
      );
      if (!suspended &&
          suspendMode == PluginSuspendMode.eventOnly &&
          !isShown()) {
        // תשובת מדיה של WebKit מוסתר עשויה לחכות לפעילות JS אחת; ממתינים
        // לשתי ההשלמות האמיתיות.
        await Future.wait<void>([
          media,
          Future.sync(
            () => controller.evaluateJavascript(source: 'void 0;'),
          ).then<void>((_) {}),
        ], eagerError: true).timeout(_nativeLifecycleTimeout);
      } else {
        await media.timeout(_nativeLifecycleTimeout);
      }
    } else if (suspended && defaultTargetPlatform == TargetPlatform.android) {
      // onPause אינו עוצר מדיה; כמו ב-Windows, עוזבים טאב — המדיה נעצרת.
      await controller
          .evaluateJavascript(source: _pauseMediaScript)
          .timeout(const Duration(seconds: 3));
    }
    return true;
  }

  /// כשל ביעד הזיכרון לא יעצור את ה-pause/resume שסביבו.
  Future<void> _setWindowsMemoryTarget(MemoryUsageTargetLevel level) async {
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    try {
      await controller
          .setMemoryUsageTargetLevel(level)
          .timeout(_nativeLifecycleTimeout);
    } catch (e) {
      debugPrint('PluginRuntimeDispatcher: memory target failed: $e');
    }
  }

  // Resume מבטל TrySuspend ממתין.
  @override
  Future<void> cancelPendingSuspend() => controller.resume();

  @override
  Future<void> reload() => controller.reload();

  @override
  Future<void> unload() => controller.loadUrl(
    urlRequest: URLRequest(url: WebUri.uri(Uri.parse('about:blank'))),
  );

  @override
  Future<bool> requestKeyboardFocus({required bool trustPageFocus}) =>
      PluginWebViewFocus.request(controller, trustPageFocus: trustPageFocus);
}

/// גישה ל-dispatcher במונחי WebView, לקוד שמחזיק [InAppWebViewController].
extension PluginRuntimeDispatcherWebView on PluginRuntimeDispatcher {
  void registerController(
    String pluginId,
    InAppWebViewController controller, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
    int? viewId,
  }) => registerRuntime(
    pluginId,
    WebViewPluginRuntime.of(controller),
    instanceId: instanceId,
    viewId: viewId,
  );

  /// ה-WebView של המופע, או `null` אם אינו חי או שאינו רץ ב-WebView. משמש
  /// פעולות שקיימות רק ב-WebView (כמו `ui.print`).
  InAppWebViewController? controllerOf(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
  }) => switch (runtimeOf(pluginId, instanceId: instanceId)) {
    WebViewPluginRuntime(:final controller) => controller,
    _ => null,
  };

  bool ownsController(
    String pluginId,
    InAppWebViewController? controller, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
  }) =>
      controller != null &&
      ownsRuntime(
        pluginId,
        WebViewPluginRuntime.of(controller),
        instanceId: instanceId,
      );
}
