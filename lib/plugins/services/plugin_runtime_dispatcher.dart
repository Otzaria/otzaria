import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_startup_contributions_service.dart';
import 'package:otzaria/plugins/services/plugin_webview_focus.dart';

enum _PluginRuntimeShutdownMode { idle, restart, exit }

/// מזהה ייחודי לכל instance של webview (foreground/background) של אותו plugin.
typedef PluginInstanceId = String;

/// מופע ריצה יחיד של תוסף — כל המצב שהיה מפוזר במפות per-plugin חי כאן.
class _PluginInstance {
  _PluginInstance({required this.pluginId, required this.instanceId});

  final String pluginId;
  final PluginInstanceId instanceId;

  InAppWebViewController? controller;
  Future<void> Function()? reloadCallback;
  Object? reloadToken;

  /// מופע קדמי מושהה — evaluateJavascript עליו נבלע בשקט.
  bool suspended = false;

  /// בקשת פוקוס מקלדת שהגיעה לפני שה-WebView היה מוכן (הטאב נפתח לפני
  /// שנוצר, או שה-resume עוד רץ) — תתבצע ברגע שיהיה.
  bool pendingKeyboardFocus = false;

  /// אירועים שהוזרקו בזמן השעיה וממתינים למסירה חוזרת אחרי boot.
  final List<({String topic, String jsonPayload, DateTime at})>
  pendingRedeliveries = [];

  /// חלון החסד להשלמת טיפול אסינכרוני לפני הקפאה חוזרת.
  Timer? graceTimer;

  bool get isBackground => instanceId == PluginInstanceIds.background;
}

class PluginRuntimeDispatcher {
  static final PluginRuntimeDispatcher instance = PluginRuntimeDispatcher._();
  PluginRuntimeDispatcher._();

  /// כל מופעי הריצה החיים, לפי מפתח (pluginId, instanceId). תוסף יכול לרוץ
  /// בכמה מופעים במקביל: טאבים קדמיים (PluginTabPage) + מופע רקע
  /// (PluginBackgroundHost) כשהוענקה ההרשאה `app.run_on_startup`.
  final Map<PluginInstanceKey, _PluginInstance> _instances = {};

  /// אינדקס לשאילתות ברמת התוסף. סדר ההכנסה נשמר — "האחרון שנרשם".
  final Map<String, Set<PluginInstanceKey>> _instancesByPlugin = {};

  PluginRegistryRepository _repository = PluginRegistryRepository();

  @visibleForTesting
  set repositoryForTesting(PluginRegistryRepository repo) => _repository = repo;
  _PluginRuntimeShutdownMode _shutdownMode = _PluginRuntimeShutdownMode.idle;

  // Cache in-memory למניעת שאילתות SQLite חוזרות במסלול החם
  final Map<String, bool> _enabledCache = {};
  final Map<String, Map<String, bool?>> _permissionCache = {};

  /// controllers שאירוע שידור פג להם הזמן — מודרים ממסירה עד לרישום מחדש
  /// או להחייאה, כדי שמופע תקוע לא יעלה 3 שניות בכל אירוע.
  final Set<InAppWebViewController> _eventTimedOutControllers = Set.identity();

  // ה-payload האחרון של theme.changed — תוסף מושהה לא מקבל את האירוע
  // (ה-WebView מוקפא), ולכן מסנכרנים אותו מחדש בהתעוררות.
  Map<String, dynamic>? _lastThemePayload;

  /// Events whose work must continue in the non-suspended background host.
  /// All other broadcast events retain the legacy foreground-first behavior.
  static const Set<String> _backgroundEventTopics = {
    'reader.sectionContentChanged',
  };

  // ── מחזור חיים של מופעים קדמיים (PluginTabPage) ──────────────────────────
  // משהים את ה-WebView של מופע שעזבו כדי לא לצרוך CPU/RAM ברקע. pause נייטיב =
  // TrySuspend ב-WebView2 (Windows) / onPause (Android) — מקפיא בלי reload.
  // לא נוגעים במופע הרקע ('background') — תוספי run_on_startup אמורים לרוץ.
  //
  // קבוצה ולא מפתח יחיד: טאב מפוצל בעיון יכול להציג שני מופעים בו-זמנית.
  Set<PluginInstanceKey> _visibleInstanceKeys = const {};
  bool _readerScreenVisible = true;
  Set<PluginInstanceKey> _runningForegroundKeys = const {};

  // מסדר את כל פעולות מחזור-החיים בשרשרת אחת. בלי זה, שני reconciles
  // חופפים (מעבר מהיר בין תוספים/מסכים) מ-await בו-זמנית את pause/resume,
  // ועלולים להשאיר את המופע הלא-נכון מושהה או לשלוח resumed אחרי suspended.
  Future<void> _lifecycleLock = Future.value();

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

  /// המופע הקדמי ה"ראשי" של [pluginId]: הגלוי כרגע, ואם אין גלוי —
  /// האחרון שנרשם (סדר ההכנסה באינדקס).
  PluginInstanceKey? _primaryForegroundKey(String pluginId) {
    final keys = _instancesByPlugin[pluginId];
    if (keys == null) return null;
    PluginInstanceKey? lastRegistered;
    for (final key in keys) {
      final instance = _instances[key];
      if (instance == null ||
          instance.isBackground ||
          instance.controller == null) {
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

  /// בוחר מופע יעד ללחיצה על תרומת UI מבין המופעים שרשמו אותה
  /// ([registrantInstanceIds], בסדר הרישום): קדמי גלוי, אחרת הקדמי החי
  /// האחרון שנרשם. אין קדמי חי — null, והקריאה ל-[dispatchEventToPlugin]
  /// בלי instanceId תבחר כרגיל (רקע / החייאה).
  PluginInstanceId? pickContributionTarget(
    String pluginId,
    Iterable<PluginInstanceId> registrantInstanceIds,
  ) {
    PluginInstanceId? fallback;
    for (final instanceId in registrantInstanceIds) {
      final key = _keyOf(pluginId, instanceId);
      final instance = _instances[key];
      if (instance == null ||
          instance.isBackground ||
          instance.controller == null) {
        continue;
      }
      if (isInstanceVisible(key)) return instanceId;
      fallback = instanceId;
    }
    return fallback;
  }

  void registerController(
    String pluginId,
    InAppWebViewController controller, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
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
    // בקשת פוקוס ממתינה אינה מבוצעת כאן אלא ב-onForegroundInstanceReady:
    // העברת פוקוס ל-WebView שהדף בו עוד לא נטען מקדימה את ה-autofocus שלו.
    _instanceFor(pluginId, instanceId).controller = controller;
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
  Future<bool> requestKeyboardFocus(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
    bool deferred = false,
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
          isSuspended: instance.suspended,
          readerScreenVisible: _readerScreenVisible,
          platformNeedsHandoff: platformNeedsHandoff,
          appIsActive: appIsActiveNow(),
          flutterOwnsKeyboard: deferred && flutterOwnsKeyboardNow(),
        )) {
      instance.pendingKeyboardFocus = false;
      return PluginWebViewFocus.request(controller);
    }
    if (shouldRememberKeyboardFocusRequest(
      isBackground: isBackground,
      isVisible: isInstanceVisible(key),
      readerScreenVisible: _readerScreenVisible,
      platformNeedsHandoff: platformNeedsHandoff,
    )) {
      _instanceFor(pluginId, instanceId).pendingKeyboardFocus = true;
    }
    return false;
  }

  /// מבטל בקשות פוקוס שנזכרו. נדרש בעזיבת מסך העיון: בקשה ששרדה הייתה
  /// יורה כשהתוסף כבר אינו על המסך, ומעבירה את המקלדת לחלון בלתי-נראה.
  void cancelPendingKeyboardFocus() {
    for (final instance in _instances.values) {
      instance.pendingKeyboardFocus = false;
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
    );
  }

  void unregisterController(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
  }) {
    final key = _keyOf(pluginId, instanceId);
    final instance = _instances[key];
    if (instance != null) {
      if (instance.controller != null) {
        _eventTimedOutControllers.remove(instance.controller);
      }
      instance.controller = null;
      instance.suspended = false;
      instance.pendingKeyboardFocus = false;
      instance.pendingRedeliveries.clear();
      instance.graceTimer?.cancel();
      instance.graceTimer = null;
      _removeInstanceIfEmpty(key);
    }
    // ה-cache והתרומות הם ברמת ה-plugin; ננקה רק כשלא נשאר אף מופע חי.
    if (!_hasAnyController(pluginId)) {
      _enabledCache.remove(pluginId);
      _permissionCache.remove(pluginId);
      ContextMenuRegistry.instance.removeAll(pluginId);
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

  /// מעדכן אילו מופעי תוספים מוצגים כעת בטאב העיון הפעיל (ריק = אף אחד).
  void setVisiblePluginInstances(Set<PluginInstanceKey> keys) {
    if (setEquals(_visibleInstanceKeys, keys)) return;
    _visibleInstanceKeys = Set.unmodifiable(keys);
    unawaited(_serializeLifecycle(_reconcileForeground));
  }

  /// מעדכן אם מסך העיון גלוי. ביציאה משהים את המופעים המוצגים, בחזרה מחדשים.
  void setReaderScreenVisible(bool visible) {
    if (_readerScreenVisible == visible) return;
    _readerScreenVisible = visible;
    unawaited(_serializeLifecycle(_reconcileForeground));
  }

  Set<PluginInstanceKey> get _desiredForegroundKeys =>
      _readerScreenVisible ? _visibleInstanceKeys : const {};

  /// מאפס את מצב הנראות בלבד (בלי לגעת ב-controllers). הדיספצ'ר הוא singleton,
  /// ובלי איפוס מפורש מצב מטסט אחד דולף לבא אחריו.
  @visibleForTesting
  void resetVisibilityForTesting() {
    _visibleInstanceKeys = const {};
    _runningForegroundKeys = const {};
    for (final instance in _instances.values) {
      instance.suspended = false;
      instance.pendingKeyboardFocus = false;
      instance.pendingRedeliveries.clear();
      instance.graceTimer?.cancel();
      instance.graceTimer = null;
    }
    _readerScreenVisible = true;
    _lifecycleLock = Future.value();
  }

  /// נקרא ע"י [PluginTabPage] כשה-WebView שלו סיים להיטען (אחרי boot).
  /// אם המופע נטען בזמן שאינו מוצג (למשל המשתמש עבר לטאב אחר לפני שהטעינה
  /// הסתיימה) — משהים אותו מיד; אחרת ה-boot ממשיך כרגיל.
  Future<void> onForegroundInstanceReady(
    String pluginId, {
    PluginInstanceId instanceId = PluginInstanceIds.defaultForeground,
  }) {
    final key = _keyOf(pluginId, instanceId);
    return _serializeLifecycle(() async {
      // מסירה חוזרת: אירוע שהוזרק לטאב מושעה שההחייאה שלו גררה טעינת-דף
      // מחדש (ה-WebView מושמד בהשעיה) נפל לדף בלי מאזינים. עכשיו, כשה-boot
      // הסתיים, מזריקים אותו שוב — הבקשות אידמפוטנטיות (אותו requestId).
      final instance = _instances[key];
      final controller = instance?.controller;
      final now = DateTime.now();
      final fresh = <({String topic, String jsonPayload, DateTime at})>[];
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
          try {
            await controller.evaluateJavascript(
              source:
                  "window.dispatchEvent(new CustomEvent('${event.topic}', "
                  '{ detail: ${event.jsonPayload} }));',
            );
          } catch (e) {
            debugPrint('Failed to redeliver ${event.topic} to $pluginId: $e');
          }
        }
      }
      if (!_desiredForegroundKeys.contains(key)) {
        if (controller != null && fresh.isNotEmpty) {
          // זה עתה נמסרו אירועים — הקפאה מיידית הייתה קוטעת את הטיפול בהם.
          _scheduleSuspendAfterGrace(key, controller);
        } else {
          await _suspendForeground(key);
        }
      } else {
        // המופע נטען כשהוא כבר מוצג — מסירים סימון השהיה שנשאר מטעינה קודמת.
        _runningForegroundKeys = {..._runningForegroundKeys, key};
        instance?.suspended = false;
        await _flushPendingKeyboardFocus(key);
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

  /// משווה בין המופעים הרצויים-להרצה לרצים-בפועל ומשהה/מחדש בהתאם.
  /// הרצויים = המופעים המוצגים בטאב הפעיל כשמסך העיון גלוי, אחרת אף אחד.
  Future<void> _reconcileForeground() async {
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    final desired = _desiredForegroundKeys;
    if (setEquals(desired, _runningForegroundKeys)) return;
    final previous = _runningForegroundKeys;
    _runningForegroundKeys = Set.unmodifiable(desired);
    for (final key in previous) {
      if (!desired.contains(key)) await _suspendForeground(key);
    }
    for (final key in desired) {
      if (!previous.contains(key)) await _resumeForeground(key);
    }
  }

  bool get _supportsNativePauseResume =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.windows;

  Future<void> _suspendForeground(PluginInstanceKey key) async {
    final instance = _instances[key];
    final controller = instance?.controller;
    if (instance == null || controller == null) return;
    // הסימון לפני ההשהיה: מרגע זה כל אירוע חייב ללכת למופע אחר.
    instance.suspended = true;
    // המשתמש עזב את הטאב — בקשת פוקוס שנזכרה תחטוף את המקלדת מהטאב החדש.
    instance.pendingKeyboardFocus = false;
    // מודיעים ל-JS לפני ההקפאה כדי שיעצור timers בעצמו — זו ההגנה היחידה
    // בפלטפורמות שבהן pause נייטיב אינו נתמך (macOS/iOS/Linux).
    await _dispatchLifecycleEvent(controller, key.pluginId, 'plugin.suspended');
    if (_supportsNativePauseResume) {
      try {
        await controller.pause();
      } catch (e) {
        debugPrint(
          'PluginRuntimeDispatcher: pause failed for ${key.pluginId}: $e',
        );
      }
    }
  }

  Future<void> _resumeForeground(PluginInstanceKey key) async {
    final instance = _instances[key];
    final controller = instance?.controller;
    if (instance == null || controller == null) return;
    if (_supportsNativePauseResume) {
      try {
        await controller.resume();
      } catch (e) {
        debugPrint(
          'PluginRuntimeDispatcher: resume failed for ${key.pluginId}: $e',
        );
      }
    }
    instance.suspended = false;
    _eventTimedOutControllers.remove(controller);
    await _dispatchLifecycleEvent(controller, key.pluginId, 'plugin.resumed');
    await _resyncThemeOnResume(controller, key.pluginId);
    await _flushPendingKeyboardFocus(key);
  }

  /// שולח מחדש את ה-theme העדכני לתוסף שזה עתה התעורר — בזמן שהיה הוא לא
  /// קיבל את theme.changed (ה-WebView היה מוקפא), והיה נשאר בצבעים ישנים.
  /// מכבד enabled+permission כמו dispatchEvent, כדי שתוסף שהרשאתו נשללה
  /// בזמן ההשהיה לא יקבל את האירוע בהתעוררות.
  Future<void> _resyncThemeOnResume(
    InAppWebViewController controller,
    String pluginId,
  ) async {
    final payload = _lastThemePayload;
    if (payload == null) return;
    if (!await _canReceiveEvent(pluginId, 'theme.changed')) return;
    try {
      // timeout: eval על WebView תקוע עלול לא להשלים לעולם, וכל שרשרת
      // ה-lifecycle (שרצה תחת מנעול) הייתה נתקעת איתו.
      await controller
          .evaluateJavascript(
            source:
                "window.dispatchEvent(new CustomEvent('theme.changed', { detail: ${jsonEncode(payload)} }));",
          )
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('Failed to resync theme to plugin $pluginId: $e');
    }
  }

  Future<void> _dispatchLifecycleEvent(
    InAppWebViewController controller,
    String pluginId,
    String topic,
  ) async {
    try {
      // timeout: ראו _resyncThemeOnResume — לא נותנים ל-WebView תקוע להקפיא
      // את מנעול ה-lifecycle לצמיתות.
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
      instance.graceTimer?.cancel();
      final controller = instance.controller;
      if (controller != null) allControllers.add(controller);
    }

    _instances.clear();
    _instancesByPlugin.clear();
    _enabledCache.clear();
    _permissionCache.clear();
    _visibleInstanceKeys = const {};
    _runningForegroundKeys = const {};
    _readerScreenVisible = true;
    _lastThemePayload = null;
    _lifecycleLock = Future.value();

    for (final pluginId in pluginIds) {
      ContextMenuRegistry.instance.removeAll(pluginId);
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
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    ContextMenuRegistry.instance.removeAll(pluginId);
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

  Future<void> dispatchEvent(String topic, Map<String, dynamic> payload) async {
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    if (topic == 'theme.changed') _lastThemePayload = payload;
    // הנקודה היחידה שדרכה עוברות כל הודעות שינוי ההגדרות — תנאי `when`
    // מוערכים מחדש כאן, בלי תלות באתר ה-UI שגרם לשינוי.
    if (topic == 'settings.changed') {
      PluginConditionEvaluator.instance.notifySettingsChanged();
    }
    final jsonPayload = jsonEncode(payload);
    debugPrint('PluginRuntimeDispatcher: Dispatching $topic');

    // מסירה מקבילית: WebView תקוע של תוסף אחד לא יחסום את המסירה לשאר.
    // אירועי עבודה שייכים למופע הרקע (אינו מושהה ביציאה ממסך העיון); theme
    // הוא אירוע UI ולכן מעדיפים עבורו את הקדמיים.
    final preferBackground = _backgroundEventTopics.contains(topic);
    await Future.wait([
      for (final pluginId in _instancesByPlugin.keys.toList(growable: false))
        _broadcastEventToPlugin(
          pluginId,
          topic,
          jsonPayload,
          preferBackground: preferBackground,
        ),
    ]);

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
              !inst.suspended) {
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
    String jsonPayload, {
    required bool preferBackground,
  }) async {
    try {
      // בחירה לפני ה-await, סינון אחריו: כך מופע שנרשם בינתיים לא גונב את
      // האירוע (הוא עדיין דף ריק), ומופע שבוטל רישומו לא מקבל אותו.
      final targets = _selectEventTargets(
        pluginId,
        preferBackground: preferBackground,
      );
      if (targets.isEmpty) return;
      if (!await _canReceiveEvent(pluginId, topic)) return;
      final targetControllers = [
        for (final target in targets)
          if (ownsController(
            pluginId,
            target.controller,
            instanceId: target.instanceId,
          ))
            target.controller,
      ];
      if (targetControllers.isEmpty) return;
      _notifyBackgroundActivity(pluginId, targetControllers);
      await Future.wait([
        for (final controller in targetControllers)
          _evalEvent(controller, pluginId, topic, jsonPayload),
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
  }) async {
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    if (instanceId != null) {
      await _dispatchEventToInstance(pluginId, instanceId, topic, payload);
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
    if (!_hasAnyController(pluginId)) {
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
      _enabledCache[pluginId] = isEnabled;
      if (!isEnabled) return;
      final jsonPayload = jsonEncode(payload);
      final background = _backgroundControllerOf(pluginId);
      final primaryKey = _primaryForegroundKey(pluginId);
      final primary = primaryKey == null ? null : _instances[primaryKey];
      final primarySuspended = primary?.suspended ?? false;
      final shouldResumeForeground =
          primarySuspended &&
          (resumeForegroundIfNeeded ||
              (preferBackground && background == null));
      if (shouldResumeForeground) {
        debugPrint('PluginRuntimeDispatcher: $topic → resume suspended tab');
        await _dispatchToSuspendedForeground(primaryKey!, topic, jsonPayload);
        return;
      }
      // אירועים ממוקדים (למשל לחיצה בתפריט הקשר) חייבים להגיע למנוע הפעיל.
      // המופע הקדמי עשוי להישאר רשום אך מושהה, ולכן הבחירה מתחשבת בכך.
      InAppWebViewController? target;
      if ((preferBackground || primarySuspended || primary == null) &&
          background != null) {
        target = background;
      } else if (primary != null) {
        target = primary.controller;
      }
      if (target == null) return;
      _notifyBackgroundActivity(pluginId, [target]);
      debugPrint('PluginRuntimeDispatcher: $topic → eval to 1 controller(s)');
      try {
        await target.evaluateJavascript(
          source:
              "window.dispatchEvent(new CustomEvent('$topic', { detail: $jsonPayload }));",
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
    Map<String, dynamic> payload,
  ) async {
    final key = _keyOf(pluginId, instanceId);
    final instance = _instances[key];
    final controller = instance?.controller;
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
      _enabledCache[pluginId] = isEnabled;
      if (!isEnabled) return;
      final jsonPayload = jsonEncode(payload);
      if (instance.suspended) {
        await _dispatchToSuspendedForeground(key, topic, jsonPayload);
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

  Future<void> _dispatchToSuspendedForeground(
    PluginInstanceKey key,
    String topic,
    String jsonPayload,
  ) {
    final pluginId = key.pluginId;
    return _serializeLifecycle(() async {
      final instance = _instances[key];
      final controller = instance?.controller;
      if (instance == null || controller == null) return;
      // ההזרקה שלהלן אובדת אם ההחייאה גוררת טעינת-דף מחדש — האירוע נרשם
      // למסירה חוזרת כשה-boot של הדף יסתיים (onForegroundInstanceReady).
      final pending = instance.pendingRedeliveries;
      if (pending.length >= _maxPendingRedeliveries) pending.removeAt(0);
      pending.add((topic: topic, jsonPayload: jsonPayload, at: DateTime.now()));
      try {
        await _resumeForeground(key);
        // בפלטפורמות בלי pause נייטיבי הדף מעולם לא הוקפא — מצב ה"זומבי"
        // אינו קיים, ו-callAsyncJavaScript פחות בשל שם (Linux beta). מסלול
        // ה-eval הרגיל מספיק.
        if (!_supportsNativePauseResume) {
          await controller.evaluateJavascript(
            source:
                "window.dispatchEvent(new CustomEvent('$topic', "
                "{ detail: $jsonPayload }));",
          );
          return;
        }
        // בדיקה ומסירה בקריאה אסינכרונית אחת (תקציב זמן אחד): השעיה נייטיבית
        // עלולה להשאיר את הדף קפוא, מרוקן, או — המקרה הערמומי — context חדש
        // שבו eval רץ ומחזיר ערכים אבל מאזיני הדף האמיתי לא רואים את האירוע
        // (נצפה בפועל דרך CDP). לכן: (א) מוודאים שההרצה רואה את ה-world שבו
        // התוסף באמת נטען (window.Otzaria._booted מוצב רק ב-_boot); (ב)
        // משגרים את האירוע; (ג) מחזירים round-trip דרך ערוץ הגשר JS→Dart —
        // ערוץ מת משאיר את ה-Promise תלוי וה-timeout מטפל. כל כשל → reload,
        // והאירוע יימסר במסירה החוזרת אחרי ה-boot (onForegroundInstanceReady).
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
                    "return await window.flutter_inappwebview"
                    ".callHandler('otzaria_bridge_ping');",
              )
              .timeout(const Duration(seconds: 3));
          outcome = result?.value;
        } catch (_) {
          outcome = null;
        }
        if (outcome != true) {
          debugPrint(
            'PluginRuntimeDispatcher: $topic delivery to $pluginId not '
            'confirmed ($outcome) — reloading',
          );
          // הדף בדרך ל-reload: מחזירים את דגל ההשעיה כדי שגם ניסיון חוזר
          // של השירות (retry אחרי 8 שניות) יעבור דרך המסלול המאומת הזה
          // ויירשם למסירה חוזרת — ולא ייבלע ב-eval רגיל על דף באמצע טעינה.
          instance.suspended = true;
          try {
            await controller.reload();
          } catch (e) {
            debugPrint('PluginRuntimeDispatcher: reload failed: $e');
          }
        }
      } catch (e) {
        debugPrint('Failed to dispatch $topic to plugin $pluginId: $e');
      } finally {
        final stillRegistered = identical(
          _instances[key]?.controller,
          controller,
        );
        if (_desiredForegroundKeys.contains(key) && stillRegistered) {
          _runningForegroundKeys = {..._runningForegroundKeys, key};
        } else if (stillRegistered) {
          // אירוע ממוקד פותח לרוב טיפול אסינכרוני (בקשת חיפוש שעונה דרך
          // ה-bridge); הקפאה מיידית הייתה מקפיאה את ה-JS באמצע והתשובה
          // לא הייתה מגיעה לעולם. משהים מחדש רק אחרי חלון חסד.
          _scheduleSuspendAfterGrace(key, controller);
        } else {
          await _suspendForeground(key);
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
    instance.graceTimer = Timer(_suspendGrace, () {
      _instances[key]?.graceTimer = null;
      unawaited(
        _serializeLifecycle(() async {
          final current = _instances[key];
          final stillRegistered = identical(current?.controller, controller);
          if (!stillRegistered ||
              _desiredForegroundKeys.contains(key) ||
              (current?.suspended ?? false)) {
            return;
          }
          await _suspendForeground(key);
        }),
      );
    });
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

  /// בוחר את יעדי ה-broadcast של [pluginId]: כל המופעים הקדמיים החיים
  /// והלא-מושהים — ולא הרקע (שידור גורף לרקע היה מאפס את שעון הכיבוי העצל
  /// שלו ומחזיק אותו חי לנצח). הרקע נבחר רק כשהנושא מועדף-רקע
  /// ([preferBackground]) או כשאין שום מופע קדמי שמיש. `evaluateJavascript`
  /// על WebView מוקפא נבלע בשקט, ולכן מופע מושהה הוא יעד אחרון בלבד.
  List<_EventTarget> _selectEventTargets(
    String pluginId, {
    bool preferBackground = false,
  }) {
    final keys = _instancesByPlugin[pluginId] ?? const <PluginInstanceKey>{};
    _EventTarget? background;
    final active = <_EventTarget>[];
    final suspended = <_EventTarget>[];
    for (final key in keys) {
      final instance = _instances[key];
      final controller = instance?.controller;
      if (instance == null || controller == null) continue;
      // מופע שאירוע קודם פג לו הזמן — כל שידור אליו עולה 3 שניות, ולכן הוא
      // מודר עד לרישום/החייאה הבאים.
      if (_eventTimedOutControllers.contains(controller)) continue;
      final target = _EventTarget(key.instanceId, controller);
      if (instance.isBackground) {
        background = target;
        continue;
      }
      (instance.suspended ? suspended : active).add(target);
    }
    if (preferBackground && background != null) return [background];
    if (active.isNotEmpty) return active;
    if (background != null) return [background];
    return suspended;
  }
}

/// יעד מסירה בודד — ה-instanceId נשמר כדי לאמת אחרי await שהמופע עדיין
/// מחזיק באותו controller.
class _EventTarget {
  const _EventTarget(this.instanceId, this.controller);
  final PluginInstanceId instanceId;
  final InAppWebViewController controller;
}
