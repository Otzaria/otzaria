import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/utils/plugin_safe_mode.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_discard_policy.dart';
import 'package:otzaria/plugins/services/plugin_divine_names_filter.dart';
import 'package:otzaria/plugins/services/plugin_external_search_service.dart';
import 'package:otzaria/plugins/services/plugin_in_book_search_service.dart';
import 'package:otzaria/plugins/services/plugin_library_books_registry.dart';
import 'package:otzaria/plugins/services/plugin_restore_state_store.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/plugins/services/plugin_shortcut_registry.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_search_field_session_service.dart';
import 'package:otzaria/plugins/services/plugin_startup_contributions_service.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';
import 'package:otzaria/plugins/services/plugin_webview_focus.dart';

enum _PluginRuntimeShutdownMode { idle, restart, exit }

/// מזהה ייחודי לכל instance של webview (foreground/background) של אותו plugin.
typedef PluginInstanceId = String;

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

enum _PluginSuspensionState {
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
class _QueuedEvent {
  const _QueuedEvent(this.topic, this.json, {required this.targeted});
  final String topic;
  final String json;

  /// אירוע ממוקד אינו דורש הרשאת subscribe.
  final bool targeted;
}

/// מופע ריצה יחיד של תוסף — כל המצב שהיה מפוזר במפות per-plugin חי כאן.
class _PluginInstance {
  _PluginInstance({required this.pluginId, required this.instanceId});

  final String pluginId;
  final PluginInstanceId instanceId;

  InAppWebViewController? controller;
  int? viewId;
  Future<void> Function()? reloadCallback;
  Object? reloadToken;
  PluginInstanceHost? host;
  Object? hostToken;
  Future<void> lifecycleLock = Future.value();

  _PluginSuspensionState suspensionState = _PluginSuspensionState.active;

  /// חסימת מסירה אינה אישור שהמנוע הקפיא JavaScript.
  bool get eventsPaused => suspensionState != _PluginSuspensionState.active;
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
  PluginRestoreReason? nextBootReason;

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
  final LinkedHashMap<String, _QueuedEvent> queued = LinkedHashMap();
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
class _WindowVisibility {
  Set<PluginInstanceKey> visibleKeys = const {};
  bool readerScreenVisible = true;
  bool shown = true;
  bool minimized = false;

  bool get isForeground => readerScreenVisible && shown && !minimized;
}

class PluginRuntimeDispatcher {
  static final PluginRuntimeDispatcher instance = PluginRuntimeDispatcher._();
  PluginRuntimeDispatcher._();

  /// כל מופעי הריצה החיים, לפי מפתח (pluginId, instanceId). תוסף יכול לרוץ
  /// בכמה מופעים במקביל: טאבים קדמיים (PluginTabPage) + מופע רקע
  /// (PluginBackgroundHost) שהוער עצל דרך `contributes.startup`.
  final Map<PluginInstanceKey, _PluginInstance> _instances = {};

  /// אינדקס לשאילתות ברמת התוסף. סדר ההכנסה נשמר — "האחרון שנרשם".
  final Map<String, Set<PluginInstanceKey>> _instancesByPlugin = {};

  PluginRegistryRepository _repository = PluginRegistryRepository();

  @visibleForTesting
  set repositoryForTesting(PluginRegistryRepository repo) => _repository = repo;
  _PluginRuntimeShutdownMode _shutdownMode = _PluginRuntimeShutdownMode.idle;

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// עוקף את מגבלות הפינוי של הפלטפורמה — לבדיקות בלבד.
  @visibleForTesting
  PluginDiscardLimits? discardLimitsOverride;

  // Cache in-memory למניעת שאילתות SQLite חוזרות במסלול החם
  final Map<String, bool> _enabledCache = {};
  final Map<String, Map<String, bool?>> _permissionCache = {};

  /// controllers שאירוע שידור פג להם הזמן — מודרים ממסירה עד לרישום מחדש
  /// או להחייאה, כדי שמופע תקוע לא יעלה 3 שניות בכל אירוע.
  final Set<InAppWebViewController> _eventTimedOutControllers = Set.identity();

  /// Events whose work must continue in the non-suspended background host.
  /// All other broadcast events retain the legacy foreground-first behavior.
  static const Set<String> _backgroundEventTopics = {
    'reader.sectionContentChanged',
  };

  /// נושאי מצב: מופע מושהה מקבל ב-resume רק את האחרון מכל מפתח.
  static const Set<String> _stateTopics = {
    'theme.changed',
    'navigation.changed',
    'workspace.changed',
    'settings.changed',
    'calendar.date_changed',
    'calendar.city_changed',
    'reader.current_book_changed',
    'reader.current_ref_changed',
    'reader.selection_changed',
    'plugin.permissions_changed',
  };

  static const _maxQueuedOneShots = 50;

  static const _selectionTopic = 'reader.selection_changed';

  /// גרירת בחירה מייצרת אירוע בכל צעד; נשלח לכל היותר אחד בחלון, והאחרון
  /// נשלח בסופו.
  @visibleForTesting
  static const selectionThrottle = Duration(milliseconds: 150);
  Timer? _selectionTimer;
  Map<String, dynamic>? _pendingSelection;

  int _oneShotSequence = 0;

  /// מפתח האיחוד בתור של מופע מושהה, או null לאירוע חד-פעמי.
  @visibleForTesting
  static String? queueKeyFor(String topic, Map<String, dynamic> payload) {
    if (topic == 'settings.changed') {
      return 'settings.changed:${payload['key']}';
    }
    if (_stateTopics.contains(topic)) return topic;
    if (topic == 'reader.textReaderNavigate') return topic;
    if (topic == 'reader.textReaderCommand' && payload['action'] == 'display') {
      return 'reader.textReaderCommand:display';
    }
    return null;
  }

  // ── מחזור חיים של מופעים קדמיים (PluginTabPage) ──────────────────────────
  // משהים את ה-WebView של מופע שעזבו כדי לא לצרוך CPU/RAM ברקע. pause נייטיב =
  // TrySuspend ב-WebView2 (Windows) דורש אישור; onPause של Android אינו מקפיא JS.
  // לא נוגעים במופע הרקע ('background') — הוא הוער כדי לרוץ בלי דף נראה.
  //
  // קבוצה ולא מפתח יחיד: טאב מפוצל בעיון יכול להציג שני מופעים בו-זמנית.
  //
  // הנראות נשמרת לכל חלון לפי viewId: מופע רץ אם הוא מוצג בחלון כלשהו שמסך
  // העיון שלו גלוי והוא עצמו מוצג. בלי ריבוי חלונות קיים רק החלון הראשי.
  final Map<int, _WindowVisibility> _windows = {
    mainViewId: _WindowVisibility(),
  };
  bool _appVisible = true;
  Set<PluginInstanceKey> _runningForegroundKeys = const {};

  /// התצוגה של החלון הראשי (ה-implicit view).
  static const int mainViewId = 0;

  _WindowVisibility _window(int? viewId) =>
      _windows.putIfAbsent(viewId ?? mainViewId, _WindowVisibility.new);

  Set<PluginInstanceKey> get _visibleInstanceKeys => _windows.length == 1
      ? _windows.values.single.visibleKeys
      : {for (final window in _windows.values) ...window.visibleKeys};

  /// מסך העיון של החלון שמציג את [key]; מופע שאינו מוצג — של החלון הראשי.
  bool _readerScreenVisibleFor(PluginInstanceKey key) {
    for (final window in _windows.values) {
      if (window.visibleKeys.contains(key)) return window.readerScreenVisible;
    }
    return _window(mainViewId).readerScreenVisible;
  }

  // מסדר בחירת מופעים בלבד; המתנה למנוע מתבצעת בתור של כל מופע.
  Future<void> _lifecycleLock = Future.value();

  Timer? _discardDebounce;
  Timer? _discardAgeTimer;
  _PluginLifecycleObserver? _lifecycleObserver;

  PluginInstanceKey _keyOf(String pluginId, PluginInstanceId instanceId) =>
      (pluginId: pluginId, instanceId: instanceId);

  _PluginInstance _instanceFor(String pluginId, PluginInstanceId instanceId) {
    final key = _keyOf(pluginId, instanceId);
    final instance = _instances.putIfAbsent(
      key,
      () => _PluginInstance(pluginId: pluginId, instanceId: instanceId),
    );
    _instancesByPlugin
        .putIfAbsent(pluginId, () => <PluginInstanceKey>{})
        .add(key);
    return instance;
  }

  /// מסיר מופע שאין לו עוד controller ולא reload callback.
  void _removeInstanceIfEmpty(PluginInstanceKey key) {
    final instance = _instances[key];
    if (instance == null) return;
    if (instance.controller != null || instance.reloadCallback != null) return;
    _releaseRestoreRetention(instance);
    instance.graceTimer?.cancel();
    _instances.remove(key);
    final keys = _instancesByPlugin[key.pluginId];
    keys?.remove(key);
    if (keys != null && keys.isEmpty) _instancesByPlugin.remove(key.pluginId);
  }

  bool _hasAnyController(String pluginId) {
    final keys = _instancesByPlugin[pluginId];
    if (keys == null) return false;
    return keys.any((key) => _instances[key]?.controller != null);
  }

  InAppWebViewController? _backgroundControllerOf(String pluginId) =>
      _instances[_keyOf(pluginId, PluginInstanceIds.background)]?.controller;

  /// ה-WebView של מופע ריצה מסוים, או `null` אם אינו חי. משמש קריאות RPC
  /// שפועלות על התוכן המוצג עצמו (כמו `ui.print`).
  InAppWebViewController? controllerOf(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
  }) => _instances[_keyOf(pluginId, instanceId)]?.controller;

  /// המופע הקדמי ה"ראשי" של [pluginId]: הגלוי כרגע, ואם אין גלוי —
  /// האחרון שנרשם (סדר ההכנסה באינדקס).
  PluginInstanceKey? _primaryForegroundKey(String pluginId, {int? viewId}) {
    final keys = _instancesByPlugin[pluginId];
    if (keys == null) return null;
    PluginInstanceKey? lastRegistered;
    for (final key in keys) {
      final instance = _instances[key];
      if (instance == null ||
          instance.isBackground ||
          instance.controller == null ||
          (viewId != null && instance.viewId != viewId)) {
        continue;
      }
      if (_visibleInstanceKeys.contains(key)) return key;
      lastRegistered = key;
    }
    return lastRegistered;
  }

  /// האם המופע [key] מוצג כרגע בטאב העיון הפעיל.
  bool isInstanceVisible(PluginInstanceKey key) =>
      _visibleInstanceKeys.contains(key);

  /// האם המופע [key] מוצג עכשיו למשתמש (כולל מסך העיון והחלון).
  bool isInstanceShown(PluginInstanceKey key) =>
      _desiredForegroundKeys.contains(key);

  /// בוחר מופע יעד ללחיצה על תרומת UI מבין המופעים שרשמו אותה
  /// ([registrantInstanceIds], בסדר הרישום): קדמי גלוי, אחרת הקדמי החי
  /// האחרון שנרשם. אין קדמי חי — null, והקריאה ל-[dispatchEventToPlugin]
  /// בלי instanceId תבחר כרגיל (רקע / החייאה).
  PluginInstanceId? pickContributionTarget(
    String pluginId,
    Iterable<PluginInstanceId> registrantInstanceIds, {
    int? viewId,
  }) {
    PluginInstanceId? fallback;
    for (final instanceId in registrantInstanceIds) {
      final key = _keyOf(pluginId, instanceId);
      final instance = _instances[key];
      if (instance == null ||
          instance.isBackground ||
          instance.controller == null ||
          (viewId != null && instance.viewId != viewId)) {
        continue;
      }
      if ((viewId == null ? _visibleInstanceKeys : _window(viewId).visibleKeys)
          .contains(key)) {
        return instanceId;
      }
      fallback = instanceId;
    }
    return fallback;
  }

  void registerController(
    String pluginId,
    InAppWebViewController controller, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
    int? viewId,
  }) {
    if (_shutdownMode == _PluginRuntimeShutdownMode.exit) {
      debugPrint(
        'PluginRuntimeDispatcher: ignoring controller registration for '
        '$pluginId during app exit',
      );
      return;
    }
    _shutdownMode = _PluginRuntimeShutdownMode.idle;
    _eventTimedOutControllers.remove(controller);
    final instance = _instanceFor(pluginId, instanceId);
    instance.graceTimer?.cancel();
    instance.graceTimer = null;
    // בקשת פוקוס ממתינה אינה מבוצעת כאן אלא ב-onForegroundInstanceReady:
    // העברת פוקוס ל-WebView שהדף בו עוד לא נטען מקדימה את ה-autofocus שלו.
    instance
      ..viewId = viewId
      ..controller = controller
      ..suspensionState = _PluginSuspensionState.active
      ..suspendedAt = null
      ..busyCount = 0
      ..released = false
      ..ready = false
      ..resetEventOptions();
  }

  /// הדף הנוכחי של המופע לאפשרויות האירועים, או null כשהמופע אינו רץ.
  int? eventOptionsGeneration(String pluginId, PluginInstanceId instanceId) {
    final instance = _instances[_keyOf(pluginId, instanceId)];
    return instance?.controller == null
        ? null
        : instance!.eventOptionsGeneration;
  }

  /// `events.setOptions`: עם [raw] המופע מקבל את [topic] עם טקסט הספר כפי
  /// שנשמר. false — המופע אינו רץ, או שהדף [generation] כבר הוחלף.
  bool setEventRawDivineNames(
    String pluginId,
    PluginInstanceId instanceId,
    String topic, {
    required bool raw,
    required int generation,
  }) {
    final instance = _instances[_keyOf(pluginId, instanceId)];
    if (instance == null ||
        instance.controller == null ||
        instance.eventOptionsGeneration != generation) {
      return false;
    }
    if (raw) {
      instance.rawDivineNamesTopics.add(topic);
    } else {
      instance.rawDivineNamesTopics.remove(topic);
    }
    return true;
  }

  /// דף שנטען מחדש מתחיל בלי האפשרויות של קודמו.
  void resetEventOptions(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
  }) {
    final key = _keyOf(pluginId, instanceId);
    final instance = _instances[key];
    if (instance == null) return;
    instance.resetEventOptions();
    final controller = instance.controller;
    if (instance.isBackground || controller == null || !instance.eventsPaused) {
      return;
    }
    // ניווט מחליף את דף ה-JS, לא את ה-controller הנייטיבי. מבטלים השהיה
    // ישנה מיד כדי שגם boot של דף מוסתר יוכל להסתיים; onReady יקפיאו מחדש.
    final generation = instance.eventOptionsGeneration;
    instance.suspensionState = _PluginSuspensionState.resumeRequested;
    final resume = () async {
      final succeeded = await _setNativeSuspended(
        controller,
        key,
        suspended: false,
        isCurrent: () => _ownsLifecycle(key, instance, controller, generation),
      );
      if (!_ownsLifecycle(key, instance, controller, generation)) return;
      instance.suspensionState = succeeded
          ? _PluginSuspensionState.active
          : _PluginSuspensionState.failed;
      if (succeeded) instance.suspendedAt = null;
    }();
    instance.lifecycleLock = resume.catchError((Object error) {
      debugPrint('PluginRuntimeDispatcher: navigation resume failed: $error');
    });
  }

  @visibleForTesting
  Set<String> rawDivineNamesTopicsOf(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
  }) => {...?_instances[_keyOf(pluginId, instanceId)]?.rawDivineNamesTopics};

  /// [payload] כפי שהמופע [key] מקבל את [topic] — ראו [_encodePayload].
  String? _encodeFor(
    PluginInstanceKey key,
    String topic,
    Map<String, dynamic> payload,
  ) => _encodePayload(
    topic,
    payload,
    raw: _instances[key]?.rawDivineNamesTopics.contains(topic) ?? false,
  );

  /// [payload] מקודד כפי שתוסף מקבל אותו ([PluginDivineNamesPayload]). כשל
  /// בגרסה הגולמית נופל לגרסה המסוננת, ולא להפך; null — אין גרסה בטוחה.
  static String? _encodePayload(
    String topic,
    Map<String, dynamic> payload, {
    required bool raw,
  }) {
    try {
      return jsonEncode(PluginDivineNamesPayload.select(payload, raw: raw));
    } catch (e) {
      debugPrint(
        'PluginRuntimeDispatcher: $topic payload (raw: $raw) failed: $e',
      );
      return raw ? _encodePayload(topic, payload, raw: false) : null;
    }
  }

  /// רושם את המארח של מופע קדמי. [token] מזהה את בעליו (ראו
  /// [registerReloadCallback]).
  void registerInstanceHost(
    String pluginId,
    PluginInstanceHost host, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
    Object? token,
  }) {
    final instance = _instanceFor(pluginId, instanceId);
    instance.host = host;
    instance.hostToken = token;
  }

  void unregisterInstanceHost(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
    Object? token,
  }) {
    final instance = _instances[_keyOf(pluginId, instanceId)];
    if (instance == null || instance.host == null) return;
    if (token != null &&
        instance.hostToken != null &&
        instance.hostToken != token) {
      return;
    }
    instance.host = null;
    instance.hostToken = null;
  }

  /// האם המופע שוחרר והמארח שלו הוא [token] — בסגירת הטאב הוא הבעלים.
  bool isReleasedBy(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
    required Object token,
  }) {
    final instance = _instances[_keyOf(pluginId, instanceId)];
    return instance != null &&
        instance.released &&
        identical(instance.hostToken, token);
  }

  /// רושם את הצופה במחזור החיים של האפליקציה (מובייל ברקע, לחץ זיכרון).
  /// נקרא מ-widget, כדי שה-binding כבר קיים.
  void ensureLifecycleObserver() {
    if (_lifecycleObserver != null) return;
    final observer = _PluginLifecycleObserver(this);
    _lifecycleObserver = observer;
    WidgetsBinding.instance.addObserver(observer);
  }

  /// תחילת RPC מחזירה פעולת סיום הקשורה לדף שהתחיל אותה.
  VoidCallback beginInstanceWork(
    String pluginId, {
    required String instanceId,
  }) {
    final instance = _instances[_keyOf(pluginId, instanceId)];
    final controller = instance?.controller;
    if (instance == null || controller == null) return () {};
    var finished = false;
    instance.busyCount++;
    return () {
      if (finished) return;
      finished = true;
      if (identical(instance.controller, controller) &&
          instance.busyCount > 0) {
        instance.busyCount--;
      }
    };
  }

  /// מעביר את פוקוס המקלדת אל המופע הקדמי [instanceId] של [pluginId], כדי
  /// שניתן יהיה להקליד בתוסף מיד בפתיחתו בלי קליק.
  ///
  /// מחזיר האם הפוקוס הועבר עכשיו. אם המופע הנכון עדיין אינו מוכן (ה-WebView
  /// נוצר אחרי פתיחת הטאב, או שההחייאה שלו עוד רצה) הבקשה נזכרת ומתבצעת
  /// ברגע שיהיה מוכן.
  ///
  /// [deferred] - הבקשה נזכרה קודם ומתבצעת באיחור. רק אז שדה טקסט פעיל
  /// חוסם אותה: בבקשה ישירה המשתמש בדיוק עבר לטאב התוסף ועזב את השדה,
  /// ובאיחור הוא כבר עלול להקליד במקום אחר.
  ///
  /// [trustPageFocus] - ראה [PluginWebViewFocus.request].
  Future<bool> requestKeyboardFocus(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
    bool deferred = false,
    bool trustPageFocus = true,
  }) async {
    final key = _keyOf(pluginId, instanceId);
    final instance = _instances[key];
    final controller = instance?.controller;
    final isBackground = instanceId == PluginInstanceIds.background;
    final platformNeedsHandoff = supportsPluginKeyboardFocusHandoff(
      defaultTargetPlatform,
    );
    if (instance != null &&
        controller != null &&
        shouldMoveKeyboardFocusToPlugin(
          isBackground: instance.isBackground,
          hasController: true,
          isVisible: isInstanceVisible(key),
          isSuspended: instance.eventsPaused,
          readerScreenVisible: _readerScreenVisibleFor(key),
          platformNeedsHandoff: platformNeedsHandoff,
          appIsActive: appIsActiveNow(),
          flutterOwnsKeyboard: deferred && flutterOwnsKeyboardNow(),
        )) {
      instance.pendingKeyboardFocus = false;
      instance.pendingFocusTrustsPage = true;
      return PluginWebViewFocus.request(
        controller,
        trustPageFocus: trustPageFocus,
      );
    }
    if (shouldRememberKeyboardFocusRequest(
      isBackground: isBackground,
      isVisible: isInstanceVisible(key),
      readerScreenVisible: _readerScreenVisibleFor(key),
      platformNeedsHandoff: platformNeedsHandoff,
    )) {
      final pending = _instanceFor(pluginId, instanceId);
      pending.pendingFocusTrustsPage =
          (!pending.pendingKeyboardFocus || pending.pendingFocusTrustsPage) &&
          trustPageFocus;
      pending.pendingKeyboardFocus = true;
    }
    return false;
  }

  /// מחזיר את פוקוס המקלדת ל-WebView של המופע הפעיל של תוסף, אחרי שחלון
  /// האפליקציה חזר ממיזעור.
  ///
  /// אין אף מסלול אחר שמבקש את ההעברה: הטאב לא התחלף (ולכן אין בקשת מיקוד
  /// תוכן), ו-`AppLifecycleState.resumed` מגיע כש-`FocusManager` כבר העביר את
  /// `primaryFocus` ל-`rootScope` — ולכן [PluginWebViewFocusRestorer]
  /// מוותר. מה שנמדד בלעדיה: הדף מקבל `focus` ומדווח `document.hasFocus()`
  /// אמת, אבל אף הקשה אינה מגיעה אליו עד לחיצת עכבר.
  ///
  /// `trustPageFocus: false` מאותה סיבה — עדות הדף כוזבת כאן;
  /// `deferred: true` כדי ששדה טקסט או דיאלוג של Flutter, שהמקלדת שייכת
  /// להם בדין, לא יאבדו אותה.
  /// בטאב מפוצל שני WebView-ים יכולים להיות גלויים. רק החלונית הפעילה
  /// מועברת לכאן, כדי שלא נמסור את המקלדת לאחותה בסוף הלולאה.
  Future<void> restoreKeyboardFocusAfterWindowRestore(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
  }) async {
    await requestKeyboardFocus(
      pluginId,
      instanceId: instanceId,
      deferred: true,
      trustPageFocus: false,
    );
  }

  /// מבטל בקשות פוקוס שנזכרו. נדרש בעזיבת מסך העיון: בקשה ששרדה הייתה
  /// יורה כשהתוסף כבר אינו על המסך, ומעבירה את המקלדת לחלון בלתי-נראה.
  void cancelPendingKeyboardFocus() {
    for (final instance in _instances.values) {
      instance.pendingKeyboardFocus = false;
      instance.pendingFocusTrustsPage = true;
    }
  }

  /// מבצע בקשת פוקוס שנזכרה, עכשיו שהמופע מוכן.
  Future<void> _flushPendingKeyboardFocus(PluginInstanceKey key) async {
    final instance = _instances[key];
    if (instance == null || !instance.pendingKeyboardFocus) return;
    await requestKeyboardFocus(
      key.pluginId,
      instanceId: key.instanceId,
      deferred: true,
      trustPageFocus: instance.pendingFocusTrustsPage,
    );
  }

  void unregisterController(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
  }) {
    final key = _keyOf(pluginId, instanceId);
    final instance = _instances[key];
    if (instance != null) {
      _releaseRestoreRetention(instance);
      if (instance.controller != null) {
        _eventTimedOutControllers.remove(instance.controller);
      }
      instance.controller = null;
      instance.suspensionState = _PluginSuspensionState.active;
      instance.suspendedAt = null;
      instance.released = false;
      instance.ready = false;
      instance.busyCount = 0;
      instance.nextBootReason = null;
      instance.pendingKeyboardFocus = false;
      instance.pendingFocusTrustsPage = true;
      instance.pendingRedeliveries.clear();
      instance.resetEventOptions();
      instance.clearQueue();
      instance.graceTimer?.cancel();
      instance.graceTimer = null;
      _removeInstanceIfEmpty(key);
    }
    PluginSearchFieldSessionService.instance.onInstanceUnregistered(
      pluginId,
      instanceId,
      pluginHasEngine: _hasAnyController(pluginId),
    );
    // ה-cache והתרומות הם ברמת ה-plugin; ננקה רק כשלא נשאר אף מופע חי.
    if (!_hasAnyController(pluginId)) {
      _enabledCache.remove(pluginId);
      _permissionCache.remove(pluginId);
      ContextMenuRegistry.instance.removeAll(pluginId);
      PluginShortcutRegistry.instance.removeAll(pluginId);
      PluginToolbarRegistry.instance.removeAll(pluginId);
      // רישומים דקלרטיביים מהמניפסט אינם תלויים במנוע חי — נשארים גם אחרי
      // כיבוי עצל של מופע הרקע (אחרת הפקדים היו נעלמים אחרי 3 דקות).
      PluginStartupContributionsService.instance.reapply(pluginId);
    }
    // מופע קדמי נסגר (טאב נסגר) — לא נחזיק אותו כרץ.
    if (instanceId != PluginInstanceIds.background) {
      _runningForegroundKeys = {..._runningForegroundKeys}..remove(key);
    }
  }

  /// ה-WebView של המופע שוחרר — בפינוי או בנפילת תהליך — אבל המופע עצמו
  /// נשאר: הרישומים, בקשות הפוקוס והמסירה החוזרת נשמרים עד שייטען מחדש.
  void markInstanceReleased(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
    required PluginRestoreReason reason,
  }) {
    final key = _keyOf(pluginId, instanceId);
    final instance = _instances[key];
    if (instance == null) return;
    instance.restoreRetentionToken ??= PluginRestoreStateStore.instance.retain(
      key,
    );
    final controller = instance.controller;
    if (controller != null) _eventTimedOutControllers.remove(controller);
    instance.controller = null;
    instance.released = true;
    instance.ready = false;
    instance.suspensionState = _PluginSuspensionState.active;
    instance.suspendedAt = null;
    instance.busyCount = 0;
    instance.nextBootReason = reason;
    instance.resetEventOptions();
    instance.clearQueue();
    instance.graceTimer?.cancel();
    instance.graceTimer = null;
    _runningForegroundKeys = {..._runningForegroundKeys}..remove(key);
    PluginPageLauncher.instance.markPageClosed(
      pluginId,
      instanceId: instanceId,
      viewId: instance.viewId,
    );
    PluginSearchFieldSessionService.instance.onInstanceUnregistered(
      pluginId,
      instanceId,
      pluginHasEngine: _hasAnyController(pluginId),
    );
  }

  void _releaseRestoreRetention(_PluginInstance instance) {
    final token = instance.restoreRetentionToken;
    if (token == null) return;
    PluginRestoreStateStore.instance.releaseRetention(
      _keyOf(instance.pluginId, instance.instanceId),
      token,
    );
    instance.restoreRetentionToken = null;
  }

  /// ה-`restore` של `plugin.boot`, או null בפתיחה טרייה.
  /// [firstBoot] — ה-boot הראשון של הדף הזה; מצב שמור בלעדיו הוא טעינה חוזרת.
  Map<String, dynamic>? takeBootRestore(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
    required bool firstBoot,
  }) {
    final key = _keyOf(pluginId, instanceId);
    final instance = _instances[key];
    final store = PluginRestoreStateStore.instance;
    // טעינה חוזרת של דף קיים מדווחת תמיד; דף חדש — רק אם נשמר לו מצב.
    final reason =
        instance?.nextBootReason ??
        (!firstBoot
            ? PluginRestoreReason.reloaded
            : store.has(key)
            ? PluginRestoreReason.session
            : null);
    instance?.nextBootReason = null;
    if (reason == null || instance?.isBackground == true) return null;
    return {'reason': reason.name, 'state': store.stateOf(key)};
  }

  /// מעדכן אילו מופעי תוספים מוצגים כעת בטאב העיון הפעיל (ריק = אף אחד)
  /// של החלון [viewId] (`null` — החלון הראשי).
  void setVisiblePluginInstances(Set<PluginInstanceKey> keys, {int? viewId}) {
    final window = _window(viewId);
    if (setEquals(window.visibleKeys, keys)) return;
    window.visibleKeys = Set.unmodifiable(keys);
    _scheduleForegroundReconciliation();
  }

  /// מעדכן אם מסך העיון גלוי. ביציאה משהים את המופעים המוצגים, בחזרה מחדשים.
  void setReaderScreenVisible(bool visible, {int? viewId}) {
    final window = _window(viewId);
    if (window.readerScreenVisible == visible) return;
    window.readerScreenVisible = visible;
    _scheduleForegroundReconciliation();
  }

  /// מעדכן אם החלון עצמו מוצג. חלון שנסגר מוסתר ולא נהרס, ובלי זה
  /// התוספים שבו היו ממשיכים לרוץ ברקע.
  void setWindowShown(bool shown, {int? viewId}) {
    final window = _window(viewId);
    if (window.shown == shown) return;
    window.shown = shown;
    _scheduleForegroundReconciliation();
  }

  /// חלון ממוזער אינו מוצג: התוספים שבו מושהים עד השחזור.
  void setWindowMinimized(bool minimized, {int? viewId}) {
    final window = _window(viewId);
    if (window.minimized == minimized) return;
    window.minimized = minimized;
    _scheduleForegroundReconciliation();
  }

  /// מובייל: האפליקציה ברקע (hidden/paused) כמוה כחלון שאינו מוצג.
  void setAppVisible(bool visible) {
    if (_appVisible == visible) return;
    _appVisible = visible;
    _scheduleForegroundReconciliation();
  }

  /// חלון Dart נסגר: המופעים שהציג כבר אינם מוצגים בו. החלון הראשי נשאר תמיד.
  void forgetWindow(int viewId) {
    PluginPageLauncher.instance.forgetWindow(viewId);
    if (viewId == mainViewId || _windows.remove(viewId) == null) return;
    _scheduleForegroundReconciliation();
  }

  void _scheduleForegroundReconciliation() {
    for (final key in _desiredForegroundKeys) {
      final instance = _instances[key];
      final controller = instance?.controller;
      if (controller == null ||
          instance?.suspensionState !=
              _PluginSuspensionState.suspendRequested ||
          defaultTargetPlatform != TargetPlatform.windows) {
        continue;
      }
      // Resume מבטל TrySuspend ממתין; אין להמתין למנעול שמחזיק אותה בקשה.
      instance!.suspensionState = _PluginSuspensionState.resumeRequested;
      unawaited(
        controller.resume().timeout(_nativeLifecycleTimeout).catchError((
          Object e,
        ) {
          debugPrint(
            'PluginRuntimeDispatcher: suspend cancellation failed: $e',
          );
        }),
      );
    }
    unawaited(_serializeLifecycle(_reconcileForeground));
  }

  Set<PluginInstanceKey> get _desiredForegroundKeys {
    if (!_appVisible) return const {};
    if (_windows.length == 1) {
      final window = _windows.values.single;
      return window.isForeground ? window.visibleKeys : const {};
    }
    return {
      for (final window in _windows.values)
        if (window.isForeground) ...window.visibleKeys,
    };
  }

  /// מאפס את מצב הנראות בלבד (בלי לגעת ב-controllers). הדיספצ'ר הוא singleton,
  /// ובלי איפוס מפורש מצב מטסט אחד דולף לבא אחריו.
  @visibleForTesting
  void resetVisibilityForTesting() {
    _resetWindows();
    _runningForegroundKeys = const {};
    for (final instance in _instances.values) {
      instance.suspensionState = _PluginSuspensionState.active;
      instance.suspendedAt = null;
      instance.pendingKeyboardFocus = false;
      instance.pendingFocusTrustsPage = true;
      instance.pendingRedeliveries.clear();
      instance.clearQueue();
      instance.graceTimer?.cancel();
      instance.graceTimer = null;
    }
    _appVisible = true;
    _lifecycleLock = Future.value();
    _cancelTimers();
  }

  void _cancelTimers() {
    _discardDebounce?.cancel();
    _discardDebounce = null;
    _discardAgeTimer?.cancel();
    _discardAgeTimer = null;
    _selectionTimer?.cancel();
    _selectionTimer = null;
    _pendingSelection = null;
  }

  void _resetWindows() => _windows
    ..clear()
    ..[mainViewId] = _WindowVisibility();

  /// נקרא ע"י [PluginTabPage] כשה-WebView שלו סיים להיטען (אחרי boot).
  /// אם המופע נטען בזמן שאינו מוצג (למשל המשתמש עבר לטאב אחר לפני שהטעינה
  /// הסתיימה) — משהים אותו מיד; אחרת ה-boot ממשיך כרגיל.
  Future<void> onForegroundInstanceReady(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
  }) {
    final key = _keyOf(pluginId, instanceId);
    final readyInstance = _instances[key];
    final readyController = readyInstance?.controller;
    final readyGeneration = readyInstance?.eventOptionsGeneration;
    return _serializeInstanceLifecycle(key, () async {
      if (readyInstance == null ||
          readyController == null ||
          !_ownsLifecycle(
            key,
            readyInstance,
            readyController,
            readyGeneration!,
          )) {
        return;
      }
      // מסירה חוזרת: אירוע שהוזרק לטאב מושעה שההחייאה שלו גררה טעינת-דף
      // מחדש, או לטאב שפונה, נפל לדף בלי מאזינים. עכשיו, כשה-boot הסתיים,
      // מזריקים אותו שוב — הבקשות אידמפוטנטיות (אותו requestId).
      final instance = _instances[key];
      final controller = instance?.controller;
      instance?.ready = true;
      _releaseRestoreRetention(readyInstance);
      // ה-boot נתן theme עדכני, ואת השאר התוסף שואל בעצמו.
      instance?.clearQueue();
      final now = clock();
      final fresh =
          <({String topic, Map<String, dynamic> payload, DateTime at})>[];
      if (instance != null) {
        fresh.addAll(
          instance.pendingRedeliveries.where(
            (event) => now.difference(event.at) < _redeliverWindow,
          ),
        );
        instance.pendingRedeliveries.clear();
      }
      if (controller != null && fresh.isNotEmpty) {
        debugPrint(
          'PluginRuntimeDispatcher: redelivering ${fresh.length} event(s) '
          'to $pluginId',
        );
        for (final event in fresh) {
          if (!_ownsLifecycle(
            key,
            readyInstance,
            readyController,
            readyGeneration,
          )) {
            return;
          }
          final json = _encodeFor(key, event.topic, event.payload);
          if (json == null) continue;
          try {
            await controller
                .evaluateJavascript(
                  source:
                      "window.dispatchEvent(new CustomEvent('${event.topic}', "
                      '{ detail: $json }));',
                )
                .timeout(const Duration(seconds: 3));
          } catch (e) {
            debugPrint('Failed to redeliver ${event.topic} to $pluginId: $e');
          }
        }
      }
      if (!_ownsLifecycle(
        key,
        readyInstance,
        readyController,
        readyGeneration,
      )) {
        return;
      }
      if (!_desiredForegroundKeys.contains(key)) {
        if (controller != null && fresh.isNotEmpty) {
          // זה עתה נמסרו אירועים — הקפאה מיידית הייתה קוטעת את הטיפול בהם.
          _scheduleSuspendAfterGrace(key, controller);
        } else {
          await _suspendForeground(key);
        }
      } else {
        if (readyInstance.eventsPaused) {
          if (!await _resumeForeground(key)) return;
        } else {
          await _flushPendingKeyboardFocus(key);
        }
        _runningForegroundKeys = {..._runningForegroundKeys, key};
      }
    });
  }

  /// אירועים שהוזרקו לטאב מושעה וממתינים למסירה חוזרת אם הדף ייטען מחדש.
  static const _redeliverWindow = Duration(seconds: 30);
  static const _maxPendingRedeliveries = 5;

  Future<void> _serializeLifecycle(Future<void> Function() action) {
    final next = _lifecycleLock.then((_) => action());
    // catchError כדי ששגיאה בלינק אחד לא תשבור את השרשרת כולה.
    _lifecycleLock = next.catchError((_) {});
    return next;
  }

  Future<void> _serializeInstanceLifecycle(
    PluginInstanceKey key,
    Future<void> Function() action,
  ) {
    final instance = _instances[key];
    if (instance == null) return Future.value();
    final controller = instance.controller;
    final generation = instance.eventOptionsGeneration;
    final next = instance.lifecycleLock.then((_) async {
      if (!identical(_instances[key], instance) ||
          !identical(instance.controller, controller) ||
          instance.eventOptionsGeneration != generation) {
        return;
      }
      await action();
    });
    instance.lifecycleLock = next.catchError((_) {});
    return next;
  }

  /// משווה בין המופעים הרצויים-להרצה לרצים-בפועל ומשהה/מחדש בהתאם.
  /// הרצויים = המופעים המוצגים בטאב הפעיל כשמסך העיון גלוי, אחרת אף אחד.
  Future<void> _reconcileForeground() async {
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    final desired = _desiredForegroundKeys;
    if (setEquals(desired, _runningForegroundKeys)) return;
    final previous = _runningForegroundKeys;
    _runningForegroundKeys = Set.unmodifiable(desired);
    // חידוש לפני השהיה: המופע החדש כבר על המסך, וכל עוד הוא מוקפא הוא נראה
    // שחור. ההשהיה של המופע שעזבו יכולה לחכות — היא לא נראית למשתמש.
    for (final key in desired) {
      if (previous.contains(key)) continue;
      unawaited(
        _serializeInstanceLifecycle(key, () async {
          if (!_desiredForegroundKeys.contains(key)) return;
          final instance = _instances[key];
          if (instance != null && instance.released) {
            instance.host?.restoreWebView();
            return;
          }
          final controller = instance?.controller;
          final generation = instance?.eventOptionsGeneration;
          if (!await _resumeForeground(key) &&
              instance != null &&
              controller != null &&
              _ownsLifecycle(key, instance, controller, generation!)) {
            _runningForegroundKeys = {..._runningForegroundKeys}..remove(key);
          }
        }),
      );
    }
    for (final key in previous) {
      if (!desired.contains(key)) {
        unawaited(
          _serializeInstanceLifecycle(key, () => _suspendForeground(key)),
        );
      }
    }
  }

  /// לפי טבלת התמיכה של הפורק (`isMethodSupported` של pause, ‏setVisible
  /// ו-setAllMediaPlaybackSuspended); אינה נשאלת בזמן ריצה כי היא דורשת
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

  Future<void> _suspendForeground(PluginInstanceKey key) async {
    final instance = _instances[key];
    final controller = instance?.controller;
    if (instance == null ||
        controller == null ||
        _desiredForegroundKeys.contains(key)) {
      return;
    }
    if (instance.suspensionState == _PluginSuspensionState.suspendedConfirmed ||
        instance.suspensionState == _PluginSuspensionState.hidden) {
      return;
    }
    final generation = instance.eventOptionsGeneration;
    instance.suspensionState = _PluginSuspensionState.suspendRequested;
    instance.suspendedAt ??= clock();
    // המשתמש עזב את הטאב — בקשת פוקוס שנזכרה תחטוף את המקלדת מהטאב החדש.
    instance.pendingKeyboardFocus = false;
    instance.pendingFocusTrustsPage = true;
    // מודיעים ל-JS לפני ההקפאה כדי שיעצור timers בעצמו — זו ההגנה היחידה
    // בפלטפורמות שבהן pause נייטיב אינו נתמך (macOS/iOS/Linux).
    await _dispatchLifecycleEvent(controller, key.pluginId, 'plugin.suspended');
    if (!_ownsLifecycle(key, instance, controller, generation)) return;
    if (_desiredForegroundKeys.contains(key)) {
      await _resumeForeground(key);
      return;
    }
    instance.suspendAttempts++;
    final succeeded = await _setNativeSuspended(
      controller,
      key,
      suspended: true,
      isCurrent: () => _ownsLifecycle(key, instance, controller, generation),
    );
    if (!_ownsLifecycle(key, instance, controller, generation)) return;
    if (_desiredForegroundKeys.contains(key)) {
      instance.suspendCancelled++;
      await _resumeForeground(key);
      return;
    }
    if (instance.suspensionState == _PluginSuspensionState.resumeRequested) {
      instance.suspendCancelled++;
      // ההחייאה ביטלה pause, אבל המשתמש כבר הסתיר שוב את הטאב.
      await _suspendForeground(key);
      return;
    }
    if (!succeeded) {
      instance.suspensionState = _PluginSuspensionState.failed;
      instance.suspendFailures++;
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      instance.suspensionState = _PluginSuspensionState.suspendedConfirmed;
      instance.suspendConfirmed++;
    } else {
      instance.suspensionState = _PluginSuspensionState.hidden;
    }
    _scheduleDiscardCheck();
  }

  bool _ownsLifecycle(
    PluginInstanceKey key,
    _PluginInstance instance,
    InAppWebViewController controller,
    int generation,
  ) =>
      identical(_instances[key], instance) &&
      identical(instance.controller, controller) &&
      instance.eventOptionsGeneration == generation;

  static const _nativeLifecycleTimeout = Duration(seconds: 6);

  Future<bool> _setNativeSuspended(
    InAppWebViewController controller,
    PluginInstanceKey key, {
    required bool suspended,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return false;
    try {
      switch (suspendMode) {
        case PluginSuspendMode.nativePause:
          if (suspended) {
            // LOW לפני ההקפאה: renderer שכבר הוקפא אינו מקצץ את ה-working set.
            await _setWindowsMemoryTarget(
              controller,
              MemoryUsageTargetLevel.LOW,
            );
            if (!isCurrent() || _desiredForegroundKeys.contains(key)) {
              return false;
            }
            await controller.pause().timeout(_nativeLifecycleTimeout);
          } else {
            await controller.resume().timeout(_nativeLifecycleTimeout);
            if (!isCurrent()) return false;
            await _setWindowsMemoryTarget(
              controller,
              MemoryUsageTargetLevel.NORMAL,
            );
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
            !_desiredForegroundKeys.contains(key)) {
          // Hidden WebKit media replies may need one JS activity to complete.
          // Delivery still waits for both real completions.
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
    } catch (e) {
      debugPrint(
        'PluginRuntimeDispatcher: ${suspended ? 'pause' : 'resume'} failed '
        'for ${key.pluginId}: $e',
      );
      return false;
    }
  }

  /// כשל ביעד הזיכרון לא יעצור את ה-pause/resume שסביבו.
  static Future<void> _setWindowsMemoryTarget(
    InAppWebViewController controller,
    MemoryUsageTargetLevel level,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    try {
      await controller
          .setMemoryUsageTargetLevel(level)
          .timeout(_nativeLifecycleTimeout);
    } catch (e) {
      debugPrint('PluginRuntimeDispatcher: memory target failed: $e');
    }
  }

  Future<bool> _resumeForeground(PluginInstanceKey key) async {
    final instance = _instances[key];
    final controller = instance?.controller;
    if (instance == null || controller == null) return false;
    final generation = instance.eventOptionsGeneration;
    final elapsed = Stopwatch()..start();
    instance.suspensionState = _PluginSuspensionState.resumeRequested;
    final succeeded = await _setNativeSuspended(
      controller,
      key,
      suspended: false,
      isCurrent: () => _ownsLifecycle(key, instance, controller, generation),
    );
    if (!_ownsLifecycle(key, instance, controller, generation)) return false;
    instance.lastResumeMicros = elapsed.elapsedMicroseconds;
    if (!succeeded) {
      instance.suspensionState = _PluginSuspensionState.failed;
      return false;
    }
    instance.suspensionState = _PluginSuspensionState.active;
    instance.suspendedAt = null;
    _eventTimedOutControllers.remove(controller);
    await _dispatchLifecycleEvent(controller, key.pluginId, 'plugin.resumed');
    if (!_ownsLifecycle(key, instance, controller, generation)) return false;
    await _flushQueued(key, controller);
    if (!_ownsLifecycle(key, instance, controller, generation)) return false;
    await _flushPendingKeyboardFocus(key);
    return true;
  }

  /// מוסר ב-eval אחד את מה שהצטבר בזמן ההשהיה. ההרשאה נבדקת שוב, כדי
  /// שהרשאה שנשללה בזמן ההשהיה תכובד.
  Future<void> _flushQueued(
    PluginInstanceKey key,
    InAppWebViewController controller,
  ) async {
    final instance = _instances[key];
    if (instance == null || instance.queued.isEmpty) return;
    final generation = instance.eventOptionsGeneration;
    final events = instance.queued.values.toList(growable: false);
    instance.clearQueue();
    final allowed = <_QueuedEvent>[];
    for (final event in events) {
      if (event.targeted || await _canReceiveEvent(key.pluginId, event.topic)) {
        allowed.add(event);
      }
    }
    if (allowed.isEmpty ||
        !_ownsLifecycle(key, instance, controller, generation)) {
      return;
    }
    final batch = allowed
        .map((e) => '[${jsonEncode(e.topic)},${e.json}]')
        .join(',');
    try {
      // timeout: eval על WebView תקוע עלול לא להשלים לעולם, וכל שרשרת
      // ה-lifecycle (שרצה תחת מנעול) הייתה נתקעת איתו.
      await controller
          .evaluateJavascript(
            source:
                '(function(q){for(var i=0;i<q.length;i++){'
                'window.dispatchEvent(new CustomEvent(q[i][0],'
                '{detail:q[i][1]}));}})([$batch]);',
          )
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('Failed to flush queued events to ${key.pluginId}: $e');
    }
  }

  void _enqueue(
    _PluginInstance instance,
    String? queueKey,
    String topic,
    String json, {
    bool targeted = false,
  }) {
    final key = queueKey ?? '#${_oneShotSequence++}';
    if (queueKey == null) {
      if (instance.queuedOneShots >= _maxQueuedOneShots) {
        final oldest = instance.queued.keys.firstWhere(
          (k) => k.startsWith('#'),
        );
        instance.queued.remove(oldest);
        instance.queuedOneShots--;
        debugPrint(
          'PluginRuntimeDispatcher: queue full for ${instance.pluginId}, '
          'dropped oldest event',
        );
      }
      instance.queuedOneShots++;
    } else {
      instance.queued.remove(key);
    }
    instance.queued[key] = _QueuedEvent(topic, json, targeted: targeted);
  }

  Future<void> _dispatchLifecycleEvent(
    InAppWebViewController controller,
    String pluginId,
    String topic,
  ) async {
    try {
      // timeout: ראו _flushQueued — לא נותנים ל-WebView תקוע להקפיא את מנעול
      // ה-lifecycle לצמיתות.
      await controller
          .evaluateJavascript(
            source:
                "window.dispatchEvent(new CustomEvent('$topic', { detail: null }));",
          )
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('Failed to dispatch $topic to plugin $pluginId: $e');
    }
  }

  // ── פינוי מופעים מושהים ─────────────────────────────────────────────────

  PluginDiscardLimits get _discardLimits =>
      discardLimitsOverride ??
      PluginDiscardLimits.forPlatform(defaultTargetPlatform);

  void _scheduleDiscardCheck() {
    _discardDebounce?.cancel();
    _discardDebounce = Timer(const Duration(seconds: 5), () {
      _discardDebounce = null;
      unawaited(checkDiscard());
    });
    _discardAgeTimer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(checkDiscard());
    });
  }

  /// מפנה מופעים מושהים לפי [PluginDiscardLimits]. [memoryPressure] — כל
  /// מי שמותר לפנות.
  @visibleForTesting
  Future<void> checkDiscard({bool memoryPressure = false}) =>
      _serializeLifecycle(() async {
        if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
        final candidates = <PluginDiscardCandidate>[
          for (final instance in _instances.values)
            if (!instance.isBackground &&
                instance.controller != null &&
                instance.eventsPaused &&
                instance.suspendedAt != null &&
                !_desiredForegroundKeys.contains(
                  _keyOf(instance.pluginId, instance.instanceId),
                ))
              PluginDiscardCandidate(
                key: _keyOf(instance.pluginId, instance.instanceId),
                suspendedAt: instance.suspendedAt!,
                exempt: _isDiscardExempt(instance),
              ),
        ];
        if (candidates.isEmpty) {
          _discardAgeTimer?.cancel();
          _discardAgeTimer = null;
          return;
        }
        final victims = pickDiscardVictims(
          candidates,
          now: clock(),
          limits: _discardLimits,
          memoryPressure: memoryPressure,
        );
        for (final key in victims) {
          final instance = _instances[key];
          if (instance == null || _isDiscardExempt(instance)) continue;
          final retention = PluginRestoreStateStore.instance.retain(key);
          if (retention == null) continue;
          instance.restoreRetentionToken = retention;
          final host = instance.host!;
          debugPrint('PluginRuntimeDispatcher: discarding ${key.pluginId}');
          instance.lastDiscardedAt = clock();
          markInstanceReleased(
            key.pluginId,
            instanceId: key.instanceId,
            reason: PluginRestoreReason.discarded,
          );
          host.releaseWebView();
        }
      });

  bool _isDiscardExempt(_PluginInstance instance) =>
      _discardBlocker(instance) != null;

  /// First blocking reason, in the same order used by the discard policy.
  /// Returning a reason instead of a bool does not relax any exemption.
  String? _discardBlocker(_PluginInstance instance) {
    final key = _keyOf(instance.pluginId, instance.instanceId);
    final pluginId = instance.pluginId;
    final host = instance.host;
    if (host == null) return 'noHost';
    if (!host.canDiscard) return 'hostDisallowsDiscard';
    if (!instance.ready) return 'notReady';
    if (instance.suspensionState == _PluginSuspensionState.suspendRequested ||
        instance.suspensionState == _PluginSuspensionState.resumeRequested) {
      return 'lifecyclePending';
    }
    if (!PluginRestoreStateStore.instance.has(key)) return 'noRestoreState';
    if (!PluginRestoreStateStore.instance.canDiscard(key)) {
      return 'outdatedRestoreState';
    }
    if (instance.busyCount > 0) return 'busyRpc';
    if (instance.graceTimer != null) return 'gracePeriod';
    final now = clock();
    if (instance.pendingRedeliveries.any(
      (event) => now.difference(event.at) < _redeliverWindow,
    )) {
      return 'pendingRedelivery';
    }
    if (instance.queuedOneShots > 0) return 'queuedOneShot';
    if (PluginUnsavedChangesRegistry.instance.hasUnsavedChanges(key)) {
      return 'unsavedChanges';
    }
    if (PluginCorrectionSessionService.instance.hasSessionsFor(pluginId)) {
      return 'correctionSession';
    }
    if (PluginPageLauncher.instance.hasPendingFor(
      pluginId,
      instanceId: instance.instanceId,
    )) {
      return 'pendingPage';
    }
    if (PluginSearchFieldSessionService.instance.hasSessionFor(pluginId)) {
      return 'searchFieldSession';
    }
    if (ContextMenuRegistry.instance.hasInstance(key)) return 'contextMenu';
    if (PluginToolbarRegistry.instance.hasInstance(key)) return 'toolbar';
    if (PluginHighlightRegistry.instance.hasInstance(key)) return 'highlight';
    if (PluginSearchDialogRegistry.instance.hasInstance(key)) {
      return 'searchDialog';
    }
    final isLastEngine = !(_instancesByPlugin[pluginId] ?? const {}).any(
      (other) => other != key && _instances[other]?.controller != null,
    );
    if (isLastEngine) {
      if (PluginShortcutRegistry.instance.hasPlugin(pluginId)) {
        return 'lastShortcutEngine';
      }
      if (PluginInBookSearchService.instance.isProviderPlugin(pluginId)) {
        return 'lastInBookSearchEngine';
      }
      if (PluginExternalSearchService.instance.isProviderPlugin(pluginId)) {
        return 'lastExternalSearchEngine';
      }
      if (PluginLibraryBooksRegistry.instance.hasProviderFor(pluginId)) {
        return 'lastLibraryProviderEngine';
      }
    }
    return null;
  }

  /// Synchronous metadata only: no JS, native calls, database reads or
  /// restore-state contents. Counts cover all foreground instances;
  /// details are bounded. Eligibility is not a promise of immediate eviction.
  Map<String, Object?> describeForegroundResources() {
    final desired = _desiredForegroundKeys;
    final limits = _discardLimits;
    final details = <Map<String, Object?>>[];
    final blockers = <String, int>{};
    var registered = 0;
    var live = 0;
    var suspended = 0;
    var hidden = 0;
    var suspendRequested = 0;
    var failed = 0;
    var released = 0;
    var candidates = 0;
    var eligible = 0;
    var exempt = 0;
    for (final instance in _instances.values) {
      if (instance.isBackground) continue;
      registered++;
      final key = _keyOf(instance.pluginId, instance.instanceId);
      final hasController = instance.controller != null;
      final isHidden = hasController && !desired.contains(key);
      final isSuspended =
          hasController &&
          instance.suspensionState == _PluginSuspensionState.suspendedConfirmed;
      final candidate =
          isHidden && instance.eventsPaused && instance.suspendedAt != null;
      final blocker = candidate ? _discardBlocker(instance) : null;
      if (hasController) live++;
      if (isSuspended) suspended++;
      if (isHidden) hidden++;
      if (hasController &&
          instance.suspensionState == _PluginSuspensionState.suspendRequested) {
        suspendRequested++;
      }
      if (hasController &&
          instance.suspensionState == _PluginSuspensionState.failed) {
        failed++;
      }
      if (instance.released) released++;
      if (candidate) {
        candidates++;
        if (blocker == null) {
          eligible++;
        } else {
          exempt++;
          blockers.update(blocker, (n) => n + 1, ifAbsent: () => 1);
        }
      }
      if (details.length >= 100) continue;
      final since = instance.suspendedAt;
      details.add({
        'pluginId': instance.pluginId,
        'instanceId': instance.instanceId,
        'live': hasController,
        'suspended': isSuspended,
        'hidden': hasController && !desired.contains(key),
        'suspensionState': instance.suspensionState.name,
        'suspendAttempts': instance.suspendAttempts,
        'suspendConfirmed': instance.suspendConfirmed,
        'suspendFailures': instance.suspendFailures,
        'suspendCancelled': instance.suspendCancelled,
        'lastResumeMicros': ?instance.lastResumeMicros,
        'released': instance.released,
        'restoreAvailable': PluginRestoreStateStore.instance.has(key),
        'discardCandidate': candidate,
        'discardEligible': candidate && blocker == null,
        'firstBlockingReason': ?blocker,
        // Stable across samples; derive age from the enclosing log timestamp.
        'suspendedAt': ?(isSuspended ? since?.toUtc().toIso8601String() : null),
        'hiddenAt': ?(isHidden ? since?.toUtc().toIso8601String() : null),
        'lastDiscardedAt': ?instance.lastDiscardedAt?.toUtc().toIso8601String(),
      });
    }
    return {
      'registered': registered,
      'live': live,
      'suspended': suspended,
      'hidden': hidden,
      'suspendRequested': suspendRequested,
      'failed': failed,
      'backgroundLive': _instances.values
          .where(
            (instance) => instance.isBackground && instance.controller != null,
          )
          .length,
      'released': released,
      'discardCandidates': candidates,
      'eligible': eligible,
      'exempt': exempt,
      'firstBlockerCounts': blockers,
      'limits': {
        'maxLiveSuspended': limits.maxLiveSuspended,
        'maxSuspendedAgeMs': limits.maxSuspendedAge.inMilliseconds,
      },
      'instances': details,
      'detailsTruncated': registered > details.length,
    };
  }

  /// מנקה את ה-cache של תוסף ספציפי - יש לקרוא כשמשתמש משנה enabled/permissions
  void invalidatePlugin(String pluginId) {
    _enabledCache.remove(pluginId);
    _permissionCache.remove(pluginId);
  }

  Future<void> prepareForAppRestart() async {
    await _prepareControllersForTeardown(_PluginRuntimeShutdownMode.restart);
  }

  Future<void> prepareForAppShutdown() async {
    await _prepareControllersForTeardown(_PluginRuntimeShutdownMode.exit);
  }

  Future<void> _prepareControllersForTeardown(
    _PluginRuntimeShutdownMode shutdownMode,
  ) async {
    _shutdownMode = shutdownMode;
    final allControllers = <InAppWebViewController>[];
    final pluginIds = _instancesByPlugin.keys.toList(growable: false);
    for (final instance in _instances.values) {
      _releaseRestoreRetention(instance);
      instance.graceTimer?.cancel();
      final controller = instance.controller;
      if (controller != null) allControllers.add(controller);
    }

    _instances.clear();
    _instancesByPlugin.clear();
    _enabledCache.clear();
    _permissionCache.clear();
    _resetWindows();
    _runningForegroundKeys = const {};
    _appVisible = true;
    _lifecycleLock = Future.value();
    _cancelTimers();

    for (final pluginId in pluginIds) {
      ContextMenuRegistry.instance.removeAll(pluginId);
      PluginShortcutRegistry.instance.removeAll(pluginId);
      PluginToolbarRegistry.instance.removeAll(pluginId);
    }

    for (final controller in allControllers) {
      try {
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri.uri(Uri.parse('about:blank'))),
        );
      } catch (e) {
        // The underlying WebView may already be tearing down.
        debugPrint(
          'PluginRuntimeDispatcher: error during controller teardown: $e',
        );
      }
    }
  }

  /// האם ה-controller הרשום למופע [instanceId] הוא [controller].
  bool ownsController(
    String pluginId,
    InAppWebViewController? controller, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
  }) {
    if (controller == null) return false;
    return identical(
      _instances[_keyOf(pluginId, instanceId)]?.controller,
      controller,
    );
  }

  /// [token] מזהה את בעל ה-callback (בדרך כלל ה-`State` שרשם אותו), כדי
  /// שדף שהוחלף לא יבטל את הרישום של מחליפו.
  void registerReloadCallback(
    String pluginId,
    Future<void> Function() callback, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
    Object? token,
  }) {
    final instance = _instanceFor(pluginId, instanceId);
    instance.reloadCallback = callback;
    instance.reloadToken = token;
  }

  /// בעלות המארח קיימת גם לפני יצירת controller ובזמן פינויו.
  bool ownsHostRegistration(
    String pluginId, {
    required PluginInstanceId instanceId,
    required Object token,
  }) => identical(_instances[_keyOf(pluginId, instanceId)]?.reloadToken, token);

  void unregisterReloadCallback(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
    Object? token,
  }) {
    final key = _keyOf(pluginId, instanceId);
    final instance = _instances[key];
    if (instance == null || instance.reloadCallback == null) return;
    final registeredToken = instance.reloadToken;
    if (token != null && registeredToken != null && registeredToken != token) {
      return;
    }
    instance.reloadCallback = null;
    instance.reloadToken = null;
    _removeInstanceIfEmpty(key);
  }

  Future<void> reloadPlugin(String pluginId) async {
    await PluginSafeMode.ready;
    if (PluginSafeMode.isActive) return;
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    PluginCorrectionSessionService.instance.removeOwner(pluginId);
    ContextMenuRegistry.instance.removeAll(pluginId);
    PluginShortcutRegistry.instance.removeAll(pluginId);
    PluginToolbarRegistry.instance.removeAll(pluginId);
    PluginHighlightRegistry.instance.removePlugin(pluginId);
    // רישומים דקלרטיביים מהמניפסט אינם תלויים ב-JS — מוחזרים מיד.
    PluginStartupContributionsService.instance.reapply(pluginId);
    // עותק כדי לא לקרוס אם callback משתמש ב-unregister באמצעו
    final keys = _instancesByPlugin[pluginId]?.toList(growable: false);
    if (keys == null) return;
    final snapshot = [
      for (final key in keys)
        if (_instances[key]?.reloadCallback != null)
          _instances[key]!.reloadCallback!,
    ];
    for (final cb in snapshot) {
      await cb();
    }
  }

  /// בודק אם מותר לשלוח [topic] ל-[pluginId]: התוסף מופעל ויש לו הרשאת
  /// events.subscribe לנושא. משתמש ב-cache למניעת שאילתות SQLite חוזרות.
  Future<bool> _canReceiveEvent(String pluginId, String topic) async {
    final isEnabled =
        _enabledCache[pluginId] ?? await _repository.getIsEnabled(pluginId);
    _enabledCache[pluginId] = isEnabled;
    if (!isEnabled) return false;

    final permissions = _permissionCache[pluginId] ??= {};
    final permKey = 'events.subscribe:$topic';
    if (!permissions.containsKey(permKey)) {
      permissions[permKey] = await _repository.getPermission(pluginId, permKey);
    }
    return permissions[permKey] == true;
  }

  /// משדר אירוע לכל התוספים שנרשמו לו (הרשאת events.subscribe).
  Future<void> dispatchEvent(String topic, Map<String, dynamic> payload) {
    if (topic == _selectionTopic) return _throttleSelection(payload);
    return _dispatchBroadcast(topic, payload);
  }

  /// אירוע מצב לתוסף אחד, עם בדיקת subscribe ותור למופעים מושהים.
  Future<void> dispatchStateEventToPlugin(
    String pluginId,
    String topic,
    Map<String, dynamic> payload,
  ) => _dispatchBroadcast(topic, payload, onlyPluginId: pluginId);

  Future<void> _throttleSelection(Map<String, dynamic> payload) {
    // בלי מופע אין למי למסור, ו-timer היה נשאר תלוי אחרי כל בחירה.
    if (_instancesByPlugin.isEmpty) return Future.value();
    if (_selectionTimer != null) {
      _pendingSelection = payload;
      return Future.value();
    }
    _selectionTimer = Timer(selectionThrottle, _flushSelection);
    return _dispatchBroadcast(_selectionTopic, payload);
  }

  void _flushSelection() {
    _selectionTimer = null;
    final pending = _pendingSelection;
    _pendingSelection = null;
    if (pending == null) return;
    _selectionTimer = Timer(selectionThrottle, _flushSelection);
    unawaited(_dispatchBroadcast(_selectionTopic, pending));
  }

  Future<void> _dispatchBroadcast(
    String topic,
    Map<String, dynamic> payload, {
    String? onlyPluginId,
  }) async {
    await PluginSafeMode.ready;
    if (PluginSafeMode.isActive) return;
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    // הנקודה היחידה שדרכה עוברות כל הודעות שינוי ההגדרות — תנאי `when`
    // מוערכים מחדש כאן, בלי תלות באתר ה-UI שגרם לשינוי.
    if (topic == 'settings.changed') {
      PluginConditionEvaluator.instance.notifySettingsChanged();
    }
    // מקודד רק אם יש יעד שעבר את בדיקת ההרשאה, ולכל היותר פעם אחת לכל גרסה —
    // גם כשהקידוד נכשל, כדי שהכשל לא יחזור לכל תוסף.
    final encoded = <bool, String?>{};
    String? json({required bool raw}) => encoded.containsKey(raw)
        ? encoded[raw]
        : encoded[raw] = _encodePayload(topic, payload, raw: raw);
    debugPrint('PluginRuntimeDispatcher: Dispatching $topic');

    // מסירה מקבילית: WebView תקוע של תוסף אחד לא יחסום את המסירה לשאר.
    // אירועי עבודה שייכים למופע הרקע (אינו מושהה ביציאה ממסך העיון); theme
    // הוא אירוע UI ולכן מעדיפים עבורו את הקדמיים.
    final preferBackground = _backgroundEventTopics.contains(topic);
    final queueKey = queueKeyFor(topic, payload);
    final pluginIds = onlyPluginId != null
        ? [if (_instancesByPlugin.containsKey(onlyPluginId)) onlyPluginId]
        : _instancesByPlugin.keys.toList(growable: false);
    await Future.wait([
      for (final pluginId in pluginIds)
        _broadcastEventToPlugin(
          pluginId,
          topic,
          json,
          preferBackground: preferBackground,
          queueKey: queueKey,
        ),
    ]);
    if (onlyPluginId != null) return;

    // הערה עצלה: תוסף עם contributes.startup שהצהיר על הנושא ואין לו מופע
    // שמסוגל לקבל אותו — מקבל מנוע רק עכשיו, כשהאירוע באמת קרה.
    PluginLazyActivationService.instance.onBroadcast(
      topic,
      payload,
      hasUsableInstance: (pluginId) {
        final keys = _instancesByPlugin[pluginId];
        if (keys == null || keys.isEmpty) return false;
        // מופע רקע באמצע boot עוד לא מסוגל לקבל אירועים.
        if (_backgroundControllerOf(pluginId) != null &&
            !PluginLazyActivationService.instance.isBootPending(pluginId)) {
          return true;
        }
        for (final key in keys) {
          final inst = _instances[key];
          if (inst != null &&
              !inst.isBackground &&
              inst.controller != null &&
              !inst.eventsPaused) {
            return true;
          }
        }
        return false;
      },
    );
  }

  /// מסירת אירוע שידור לתוסף בודד — מבודדת כך שכשל/timeout באחד לא יחסום
  /// את השאר (הקוראת עוטפת ב-Future.wait).
  Future<void> _broadcastEventToPlugin(
    String pluginId,
    String topic,
    String? Function({required bool raw}) json, {
    required bool preferBackground,
    required String? queueKey,
  }) async {
    try {
      // בחירה לפני ה-await, סינון אחריו: כך מופע שנרשם בינתיים לא גונב את
      // האירוע (הוא עדיין דף ריק), ומופע שבוטל רישומו לא מקבל אותו.
      final selection = _selectEventTargets(
        pluginId,
        preferBackground: preferBackground,
        isState: queueKey != null,
      );
      if (selection.now.isEmpty && selection.queue.isEmpty) return;
      if (!await _canReceiveEvent(pluginId, topic)) return;
      final targets = <(InAppWebViewController, String)>[];
      for (final target in [...selection.now, ...selection.queue]) {
        if (!ownsController(
          pluginId,
          target.controller,
          instanceId: target.instanceId,
        )) {
          continue;
        }
        final instance = _instances[_keyOf(pluginId, target.instanceId)]!;
        final encoded = json(
          raw: instance.rawDivineNamesTopics.contains(topic),
        );
        if (encoded == null) continue;
        if (instance.eventsPaused && !instance.isBackground) {
          _enqueue(instance, queueKey, topic, encoded);
        } else {
          targets.add((target.controller, encoded));
        }
      }
      if (targets.isEmpty) return;
      _notifyBackgroundActivity(pluginId, [
        for (final (controller, _) in targets) controller,
      ]);
      await Future.wait([
        for (final (controller, encoded) in targets)
          _evalEvent(controller, pluginId, topic, encoded),
      ]);
    } catch (e) {
      debugPrint('Failed to dispatch $topic to plugin $pluginId: $e');
    }
  }

  /// משגר CustomEvent ל-WebView בודד עם timeout — WebView תקוע לא מקפיא את
  /// הקוראת (ראו _dispatchLifecycleEvent).
  Future<void> _evalEvent(
    InAppWebViewController controller,
    String pluginId,
    String topic,
    String jsonPayload,
  ) async {
    try {
      await controller
          .evaluateJavascript(
            source:
                "window.dispatchEvent(new CustomEvent('$topic', { detail: $jsonPayload }));",
          )
          .timeout(const Duration(seconds: 3));
    } on TimeoutException catch (e) {
      // בלי הסימון כל שידור הבא היה משלם שוב 3 שניות על אותו מופע תקוע,
      // וזרם אירועי הקריאה היה נחנק לאירוע אחד ל-3 שניות.
      _eventTimedOutControllers.add(controller);
      debugPrint('Timed out dispatching $topic to plugin $pluginId: $e');
    } catch (e) {
      debugPrint('Failed to dispatch $topic to plugin $pluginId: $e');
    }
  }

  /// שולח event לפלאגין ספציפי בלבד (ללא בדיקת הרשאת subscribe).
  /// משמש לאירועים ממוקדים כמו reader.context_menu_item_clicked.
  /// עם [instanceId] האירוע נמסר למופע הזה בלבד; בלעדיו — הלוגיקה הקיימת
  /// (רקע / קדמי ראשי / החייאה).
  Future<void> dispatchEventToPlugin(
    String pluginId,
    String topic,
    Map<String, dynamic> payload, {
    bool preferBackground = false,
    bool resumeForegroundIfNeeded = false,
    PluginInstanceId? instanceId,
    int? viewId,
    AppWindowKeys? windowKeys,
    bool Function()? isCurrent,
  }) async {
    await PluginSafeMode.ready;
    if (isCurrent != null && !isCurrent()) return;
    if (PluginSafeMode.isActive) return;
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    if (instanceId != null) {
      await _dispatchEventToInstance(
        pluginId,
        instanceId,
        topic,
        payload,
        isCurrent: isCurrent,
      );
      return;
    }
    // מופע רקע שנרשם אך טרם סיים boot: eval היה נבלע — האירוע ממתין בתור.
    if (PluginLazyActivationService.instance.queueIfBootPending(
      pluginId,
      topic,
      payload,
    )) {
      debugPrint('PluginRuntimeDispatcher: $topic → queued (boot pending)');
      return;
    }
    if (!_hasAnyController(pluginId) ||
        (viewId != null &&
            _backgroundControllerOf(pluginId) == null &&
            _primaryForegroundKey(pluginId, viewId: viewId) == null)) {
      // תנאי `when` שלא מתקיים = התוסף לא ביקש את האירוע; לא מעירים מנוע
      // וגם לא פותחים את דף התוסף.
      if (PluginLazyActivationService.instance.isActivationBlocked(
        pluginId,
        topic,
      )) {
        debugPrint('PluginRuntimeDispatcher: $topic → dropped (when)');
        return;
      }
      // אין מנוע חי — עם הרשאת ריצה ברקע התוסף מוּעָר בעצלנות והאירוע ממתין
      // בתור עד ה-boot; בלעדיה (false) לחיצה נופלת לפתיחת דף התוסף, שם
      // הדלקת המנוע גלויה למשתמש.
      if (PluginLazyActivationService.instance.queueTargetedEvent(
        pluginId,
        topic,
        payload,
      )) {
        debugPrint('PluginRuntimeDispatcher: $topic → queued (lazy boot)');
      } else if (preferBackground) {
        debugPrint('PluginRuntimeDispatcher: $topic → page launcher');
        PluginPageLauncher.instance.open(
          pluginId,
          topic: topic,
          payload: payload,
          viewId: viewId,
          windowKeys: windowKeys,
        );
      } else {
        debugPrint('PluginRuntimeDispatcher: $topic → dropped (no engine)');
      }
      return;
    }
    // מופע קדמי מושהה בלי מופע רקע מטופל בהמשך ע"י החייאת הטאב המושהה
    // (_dispatchToSuspendedForeground) — עדיף על הקמת מנוע רקע נוסף.
    try {
      final isEnabled =
          _enabledCache[pluginId] ?? await _repository.getIsEnabled(pluginId);
      if (isCurrent != null && !isCurrent()) return;
      _enabledCache[pluginId] = isEnabled;
      if (!isEnabled) return;
      final background = _backgroundControllerOf(pluginId);
      final primaryKey = _primaryForegroundKey(pluginId, viewId: viewId);
      final primary = primaryKey == null ? null : _instances[primaryKey];
      final primarySuspended = primary?.eventsPaused ?? false;
      final shouldResumeForeground =
          primarySuspended &&
          (resumeForegroundIfNeeded ||
              (preferBackground && background == null));
      if (shouldResumeForeground) {
        debugPrint('PluginRuntimeDispatcher: $topic → resume suspended tab');
        await _dispatchToSuspendedForeground(primaryKey!, topic, payload);
        return;
      }
      // אירועים ממוקדים (למשל לחיצה בתפריט הקשר) חייבים להגיע למנוע הפעיל.
      // המופע הקדמי עשוי להישאר רשום אך מושהה, ולכן הבחירה מתחשבת בכך.
      InAppWebViewController? target;
      PluginInstanceKey? targetKey;
      if ((preferBackground || primarySuspended || primary == null) &&
          background != null) {
        target = background;
        targetKey = _keyOf(pluginId, PluginInstanceIds.background);
      } else if (primary != null) {
        target = primary.controller;
        targetKey = primaryKey;
      }
      if (target == null || targetKey == null) return;
      final json = _encodeFor(targetKey, topic, payload);
      if (json == null) return;
      _notifyBackgroundActivity(pluginId, [target]);
      debugPrint('PluginRuntimeDispatcher: $topic → eval to 1 controller(s)');
      try {
        await target.evaluateJavascript(
          source:
              "window.dispatchEvent(new CustomEvent('$topic', { detail: $json }));",
        );
      } catch (e) {
        debugPrint('Failed to dispatch $topic to plugin $pluginId: $e');
      }
    } catch (e) {
      debugPrint('Failed to dispatch $topic to plugin $pluginId: $e');
    }
  }

  /// מסירה למופע מפורש בלבד — בלי fallback לרקע ובלי תור הערה עצלה,
  /// כדי שאירוע שמיועד לטאב מסוים לא ידלוף למופע אחר.
  Future<void> _dispatchEventToInstance(
    String pluginId,
    PluginInstanceId instanceId,
    String topic,
    Map<String, dynamic> payload, {
    bool Function()? isCurrent,
  }) async {
    final key = _keyOf(pluginId, instanceId);
    final instance = _instances[key];
    final controller = instance?.controller;
    final queueKey = queueKeyFor(topic, payload);
    if (instance != null && instance.released) {
      // אירוע מצב מתיישן — ה-boot של הדף המשוחזר מקבל את המצב העדכני.
      if (queueKey == null) {
        _addRedelivery(instance, topic, payload);
      }
      return;
    }
    if (instance == null || controller == null) {
      debugPrint(
        'PluginRuntimeDispatcher: $topic → dropped '
        '(instance $instanceId not registered)',
      );
      return;
    }
    try {
      final isEnabled =
          _enabledCache[pluginId] ?? await _repository.getIsEnabled(pluginId);
      if (isCurrent != null && !isCurrent()) return;
      if (!identical(_instances[key], instance) ||
          !identical(instance.controller, controller)) {
        return;
      }
      _enabledCache[pluginId] = isEnabled;
      if (!isEnabled) return;
      if (instance.eventsPaused && queueKey == null) {
        await _dispatchToSuspendedForeground(key, topic, payload);
        return;
      }
      final jsonPayload = _encodeFor(key, topic, payload);
      if (jsonPayload == null) return;
      if (instance.eventsPaused) {
        // מצב (ניווט בכרטיסיית ספר מוסתרת) אינו מצדיק להעיר את הטאב.
        _enqueue(instance, queueKey, topic, jsonPayload, targeted: true);
        return;
      }
      _notifyBackgroundActivity(pluginId, [controller]);
      await controller
          .evaluateJavascript(
            source:
                "window.dispatchEvent(new CustomEvent('$topic', { detail: $jsonPayload }));",
          )
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('Failed to dispatch $topic to plugin $pluginId: $e');
    }
  }

  void _addRedelivery(
    _PluginInstance instance,
    String topic,
    Map<String, dynamic> payload,
  ) {
    final pending = instance.pendingRedeliveries;
    if (pending.length >= _maxPendingRedeliveries) pending.removeAt(0);
    pending.add((topic: topic, payload: payload, at: clock()));
  }

  Future<void> _dispatchToSuspendedForeground(
    PluginInstanceKey key,
    String topic,
    Map<String, dynamic> payload,
  ) {
    final pluginId = key.pluginId;
    return _serializeInstanceLifecycle(key, () async {
      final instance = _instances[key];
      final controller = instance?.controller;
      if (instance == null || controller == null) return;
      final generation = instance.eventOptionsGeneration;
      final jsonPayload = _encodeFor(key, topic, payload);
      if (jsonPayload == null) return;
      // ההזרקה שלהלן אובדת אם ההחייאה גוררת טעינת-דף מחדש — האירוע נרשם
      // למסירה חוזרת כשה-boot של הדף יסתיים (onForegroundInstanceReady).
      _addRedelivery(instance, topic, payload);
      try {
        if (!await _resumeForeground(key) ||
            !_ownsLifecycle(key, instance, controller, generation)) {
          return;
        }
        // בפלטפורמות בלי pause נייטיבי הדף מעולם לא הוקפא — מצב ה"זומבי"
        // אינו קיים, ו-callAsyncJavaScript פחות בשל שם (Linux beta). מסלול
        // ה-eval הרגיל מספיק.
        if (suspendMode != PluginSuspendMode.nativePause) {
          await controller
              .evaluateJavascript(
                source:
                    "window.dispatchEvent(new CustomEvent('$topic', "
                    "{ detail: $jsonPayload }));",
              )
              .timeout(const Duration(seconds: 3));
          return;
        }
        // האימות והמסירה משתמשים באותו עולם JS. אובדן ack אחרי dispatch
        // אינו מוכיח שהפקודה לא טופלה או שאין במסמך מידע חי.
        Object? outcome;
        try {
          final result = await controller
              .callAsyncJavaScript(
                functionBody:
                    "if (!window.flutter_inappwebview || "
                    "!window.flutter_inappwebview.callHandler) "
                    "{ return 'no-bridge'; } "
                    "if (!window.Otzaria || window.Otzaria._booted !== true) "
                    "{ return 'no-page-world'; } "
                    "window.dispatchEvent(new CustomEvent('$topic', "
                    "{ detail: $jsonPayload })); "
                    "return (await window.flutter_inappwebview"
                    ".callHandler('otzaria_bridge_ping')) === true;",
              )
              .timeout(const Duration(seconds: 3));
          outcome = result?.value;
        } catch (_) {
          outcome = null;
        }
        if (!_ownsLifecycle(key, instance, controller, generation)) return;
        if (outcome != true) {
          final restoreStates = PluginRestoreStateStore.instance;
          if ((outcome != 'no-bridge' && outcome != 'no-page-world') ||
              !restoreStates.canDiscard(key) ||
              PluginUnsavedChangesRegistry.instance.hasUnsavedChanges(key)) {
            debugPrint(
              'PluginRuntimeDispatcher: $topic delivery to $pluginId not '
              'confirmed ($outcome) — preserving the live document',
            );
            return;
          }
          instance.restoreRetentionToken = restoreStates.retain(key);
          debugPrint(
            'PluginRuntimeDispatcher: $topic delivery to $pluginId not '
            'confirmed ($outcome) — reloading',
          );
          // הדף בדרך ל-reload: מחזירים את דגל ההשעיה כדי שגם ניסיון חוזר
          // של השירות (retry אחרי 8 שניות) יעבור דרך המסלול המאומת הזה
          // ויירשם למסירה חוזרת — ולא ייבלע ב-eval רגיל על דף באמצע טעינה.
          instance.suspensionState = _PluginSuspensionState.hidden;
          instance.ready = false;
          instance.nextBootReason = PluginRestoreReason.reloaded;
          try {
            await controller.reload().timeout(const Duration(seconds: 3));
          } catch (e) {
            debugPrint('PluginRuntimeDispatcher: reload failed: $e');
          }
        }
      } catch (e) {
        debugPrint('Failed to dispatch $topic to plugin $pluginId: $e');
      } finally {
        if (_ownsLifecycle(key, instance, controller, generation) &&
            !instance.eventsPaused) {
          if (_desiredForegroundKeys.contains(key)) {
            _runningForegroundKeys = {..._runningForegroundKeys, key};
          } else {
            // חלון חסד מאפשר לבקשה אסינכרונית להשלים לפני הקפאת ה-JS.
            _scheduleSuspendAfterGrace(key, controller);
          }
        }
      }
    });
  }

  /// חלון חסד להשלמת טיפול אסינכרוני לפני הקפאה חוזרת של טאב מושהה.
  static const _suspendGrace = Duration(seconds: 90);

  void _scheduleSuspendAfterGrace(
    PluginInstanceKey key,
    InAppWebViewController controller,
  ) {
    final instance = _instances[key];
    if (instance == null) return;
    // אירוע נוסף בתוך החלון מאריך אותו — הטאב עדיין בעבודה.
    instance.graceTimer?.cancel();
    late final Timer timer;
    timer = Timer(_suspendGrace, () {
      if (!identical(_instances[key], instance) ||
          !identical(instance.graceTimer, timer)) {
        return;
      }
      instance.graceTimer = null;
      unawaited(
        _serializeInstanceLifecycle(key, () async {
          final current = _instances[key];
          final stillRegistered = identical(current?.controller, controller);
          if (!stillRegistered ||
              _desiredForegroundKeys.contains(key) ||
              (current?.eventsPaused ?? false)) {
            return;
          }
          await _suspendForeground(key);
        }),
      );
    });
    instance.graceTimer = timer;
  }

  /// אירוע שנמסר למופע הרקע נחשב פעילות — מאפס את שעון הכיבוי העצל שלו.
  void _notifyBackgroundActivity(
    String pluginId,
    List<InAppWebViewController> targets,
  ) {
    final background = _backgroundControllerOf(pluginId);
    if (background != null && targets.contains(background)) {
      PluginLazyActivationService.instance.notifyActivity(pluginId);
    }
  }

  /// בוחר את יעדי ה-broadcast של [pluginId].
  ///
  /// `now`: כל המופעים הקדמיים החיים והלא-מושהים — ולא הרקע (שידור גורף
  /// לרקע היה מאפס את שעון הכיבוי העצל שלו ומחזיק אותו חי לנצח). הרקע נבחר
  /// רק כשהנושא מועדף-רקע ([preferBackground]) או כשאין שום מופע קדמי שמיש.
  ///
  /// `queue`: מופעים מושהים — תמיד לאירוע מצב ([isState]), כי כל מופע קדמי
  /// מצייר UI; ולאירוע חד-פעמי רק כשאין יעד אחר.
  ({List<_EventTarget> now, List<_EventTarget> queue}) _selectEventTargets(
    String pluginId, {
    required bool preferBackground,
    required bool isState,
  }) {
    final keys = _instancesByPlugin[pluginId] ?? const <PluginInstanceKey>{};
    _EventTarget? background;
    final active = <_EventTarget>[];
    final suspended = <_EventTarget>[];
    for (final key in keys) {
      final instance = _instances[key];
      final controller = instance?.controller;
      if (instance == null || controller == null) continue;
      if (instance.eventsPaused && !instance.isBackground) {
        suspended.add(_EventTarget(key.instanceId, controller));
        continue;
      }
      // מופע שאירוע קודם פג לו הזמן — כל שידור אליו עולה 3 שניות, ולכן הוא
      // מודר עד לרישום/החייאה הבאים.
      if (_eventTimedOutControllers.contains(controller)) continue;
      final target = _EventTarget(key.instanceId, controller);
      if (instance.isBackground) {
        background = target;
      } else {
        active.add(target);
      }
    }
    final now = preferBackground && background != null
        ? [background]
        : active.isNotEmpty
        ? active
        : background != null
        ? [background]
        : <_EventTarget>[];
    return (
      now: now,
      queue: isState || now.isEmpty ? suspended : const <_EventTarget>[],
    );
  }
}

/// יעד מסירה בודד — ה-instanceId נשמר כדי לאמת אחרי await שהמופע עדיין
/// מחזיק באותו controller.
class _EventTarget {
  const _EventTarget(this.instanceId, this.controller);
  final PluginInstanceId instanceId;
  final InAppWebViewController controller;
}

/// מובייל: אפליקציה ברקע אינה מציגה תוספים. בכל הפלטפורמות: לחץ זיכרון
/// מפנה מופעים מושהים.
class _PluginLifecycleObserver with WidgetsBindingObserver {
  _PluginLifecycleObserver(this._dispatcher);
  final PluginRuntimeDispatcher _dispatcher;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // בדסקטופ האות לא אמין (במזעור ב-Windows הוא נבלע), ושם מטפל
    // AppWindowListener.
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _dispatcher.setAppVisible(false);
      case AppLifecycleState.resumed:
        _dispatcher.setAppVisible(true);
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void didHaveMemoryPressure() {
    unawaited(_dispatcher.checkDiscard(memoryPressure: true));
  }
}
