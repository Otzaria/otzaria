import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

/// מנווט את המשתמש לדף תוסף ומוסר לו payload כאירוע JS.
///
/// פותר את המרוץ בין הניווט לטעינת ה-WebView: אם דף התוסף עדיין לא סיים
/// boot, ה-payload נשמר כממתין ונמסר רק כשה-[PluginTabPage] מדווח שהדף מוכן.
class PluginPageLauncher {
  static final PluginPageLauncher instance = PluginPageLauncher._();
  PluginPageLauncher._();

  /// מנווט לדף התוסף — נרשם ע"י MainWindowScreen (בעל הגישה למסך הכלים).
  void Function(String pluginId)? navigator;

  final Map<String, List<({String topic, Map<String, dynamic> payload})>>
  _pending = {};
  final Set<String> _readyPages = {};

  // שרשרת מסירה פר-תוסף: כל אירוע ממתין לקודמו, כך שהסדר נשמר גם כשאירוע
  // חדש מגיע בזמן ריקון הממתינים.
  final Map<String, Future<void>> _deliveryChain = {};

  /// פותח את דף התוסף. אם סופק [topic], ה-[payload] יימסר לתוסף כאירוע —
  /// מיד אם הדף כבר מוכן, אחרת לאחר סיום ה-boot שלו.
  void open(
    String pluginId, {
    String? topic,
    Map<String, dynamic> payload = const {},
  }) {
    if (topic != null) {
      if (_readyPages.contains(pluginId)) {
        _enqueueDelivery(pluginId, topic, payload);
      } else {
        _pending.putIfAbsent(pluginId, () => []).add((
          topic: topic,
          payload: payload,
        ));
      }
    }
    navigator?.call(pluginId);
  }

  /// נקרא ע"י PluginTabPage כשה-boot הסתיים — מוסר את האירועים הממתינים בסדרם.
  void markPageReady(String pluginId) {
    _readyPages.add(pluginId);
    final pending = _pending.remove(pluginId);
    if (pending == null) return;
    for (final event in pending) {
      _enqueueDelivery(pluginId, event.topic, event.payload);
    }
  }

  /// נקרא ע"י PluginTabPage בעת dispose של דף התוסף.
  void markPageClosed(String pluginId) {
    _readyPages.remove(pluginId);
    _pending.remove(pluginId);
    _deliveryChain.remove(pluginId);
  }

  void _enqueueDelivery(
    String pluginId,
    String topic,
    Map<String, dynamic> payload,
  ) {
    final previous = _deliveryChain[pluginId] ?? Future<void>.value();
    final next = previous.then(
      (_) => PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
        pluginId,
        topic,
        payload,
      ),
    );
    // catchError כדי ששגיאה במסירה אחת לא תחסום את הבאות בשרשרת.
    _deliveryChain[pluginId] = next.catchError((_) {});
  }
}
