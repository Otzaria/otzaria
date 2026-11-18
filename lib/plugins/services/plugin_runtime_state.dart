import 'dart:async';
import 'dart:collection';

import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/plugins/services/plugin_runtime.dart';

/// מזהה ייחודי לכל instance של webview (foreground/background) של אותו plugin.
enum PluginSuspensionState {
  active,
  hidden,
  suspendRequested,
  suspendedConfirmed,
  resumeRequested,
  failed,
}

/// ה-WebView של מופע קדמי, שהדיספצ'ר יכול לבקש ממנו לשחרר ולהקים מחדש.
abstract interface class PluginInstanceHost {
  /// משחרר את ה-WebView (פינוי). המופע נשאר רשום.
  void releaseWebView();

  /// מקים WebView חדש. נקרא רק כשהמופע מוצג.
  void restoreWebView();

  /// מותר לפנות את המופע (למשל לא תוסף פיתוח).
  bool get canDiscard;
}

/// אירוע שהגיע בזמן השהיה וממתין ל-resume.
class PluginQueuedEvent {
  const PluginQueuedEvent(
    this.topic,
    this.json, {
    required this.targeted,
    this.isCurrent,
  });
  final String topic;
  final String json;

  /// אירוע ממוקד אינו דורש הרשאת subscribe.
  final bool targeted;
  final bool Function()? isCurrent;
}

class PluginBootRestoreReason {
  PluginBootRestoreReason(this.value);
  final PluginRestoreReason value;
}

/// מופע ריצה יחיד של תוסף — כל המצב שהיה מפוזר במפות per-plugin חי כאן.
class PluginRuntimeInstance {
  PluginRuntimeInstance({required this.pluginId, required this.instanceId});

  final String pluginId;
  final String instanceId;

  PluginRuntime? runtime;
  int? viewId;
  Future<void> Function()? reloadCallback;
  Object? reloadToken;
  PluginInstanceHost? host;
  Object? hostToken;
  Future<void> lifecycleLock = Future.value();

  PluginSuspensionState suspensionState = PluginSuspensionState.active;

  /// חסימת מסירה אינה אישור שהמנוע הקפיא JavaScript.
  bool get eventsPaused => suspensionState != PluginSuspensionState.active;
  DateTime? suspendedAt;
  DateTime? lastDiscardedAt;
  Object? restoreRetentionToken;
  int suspendAttempts = 0;
  int suspendConfirmed = 0;
  int suspendFailures = 0;
  int suspendCancelled = 0;
  int? lastResumeMicros;

  /// ה-WebView שוחרר (פינוי או נפילה), והמופע ייטען מחדש כשיוצג.
  bool released = false;

  /// ה-boot של הדף הנוכחי הסתיים.
  bool ready = false;

  /// קריאות RPC פתוחות — מופע עסוק אינו מפונה.
  int busyCount = 0;

  /// סיבת הטעינה הבאה של הדף, עבור `restore` ב-boot.
  PluginBootRestoreReason? nextBootReason;

  /// בקשת פוקוס מקלדת שהגיעה לפני שה-WebView היה מוכן (הטאב נפתח לפני
  /// שנוצר, או שה-resume עוד רץ) — תתבצע ברגע שיהיה.
  bool pendingKeyboardFocus = false;

  /// ראה [PluginWebViewFocus.request]; false אם אחת הבקשות שנזכרו דרשה זאת.
  bool pendingFocusTrustsPage = true;

  /// אירועים שהוזרקו בזמן השעיה וממתינים למסירה חוזרת אחרי boot. מקודדים
  /// רק במסירה, לפי אפשרויות האירועים של הדף שנטען.
  final List<({String topic, Map<String, dynamic> payload, DateTime at})>
  pendingRedeliveries = [];

  /// אירועי מצב לפי מפתח (האחרון גובר ועובר לסוף), וחד-פעמיים לפי ההגעה.
  final LinkedHashMap<String, PluginQueuedEvent> queued = LinkedHashMap();
  int queuedOneShots = 0;

  /// חלון החסד להשלמת טיפול אסינכרוני לפני הקפאה חוזרת.
  Timer? graceTimer;

  /// נושאים שהדף ביקש בהם את טקסט הספר כפי שנשמר (`events.setOptions`).
  final Set<String> rawDivineNamesTopics = {};

  /// מתחלף בכל דף חדש, כדי ש-`events.setOptions` של דף קודם לא יחול עליו.
  int eventOptionsGeneration = 0;

  void resetEventOptions() {
    rawDivineNamesTopics.clear();
    eventOptionsGeneration++;
    lifecycleLock = Future.value();
    ready = false;
  }

  bool get isBackground => instanceId == PluginInstanceIds.background;

  void clearQueue() {
    queued.clear();
    queuedOneShots = 0;
  }
}

/// מצב הנראות של חלון אחד (תצוגה אחת).
class PluginWindowVisibility {
  Set<PluginInstanceKey> visibleKeys = const {};
  bool readerScreenVisible = true;
  bool shown = true;
  bool minimized = false;

  bool get isForeground => readerScreenVisible && shown && !minimized;

  bool get showsPlugins => isForeground && visibleKeys.isNotEmpty;
}
