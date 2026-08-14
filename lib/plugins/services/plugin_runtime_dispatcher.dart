import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_startup_contributions_service.dart';

enum _PluginRuntimeShutdownMode { idle, restart, exit }

/// מזהה ייחודי לכל instance של webview (foreground/background) של אותו plugin.
typedef PluginInstanceId = String;

class PluginRuntimeDispatcher {
  static final PluginRuntimeDispatcher instance = PluginRuntimeDispatcher._();
  PluginRuntimeDispatcher._();

  /// מיפוי pluginId → רשימת controllers פעילים. תוסף יכול לרוץ בכמה
  /// מקומות במקביל: instance רגיל ב-PluginTabPage + instance רקע
  /// ב-PluginBackgroundHost כשהוענקה ההרשאה `app.run_on_startup`.
  final Map<String, Map<PluginInstanceId, InAppWebViewController>>
  _controllersByPlugin = {};
  PluginRegistryRepository _repository = PluginRegistryRepository();

  @visibleForTesting
  set repositoryForTesting(PluginRegistryRepository repo) => _repository = repo;
  _PluginRuntimeShutdownMode _shutdownMode = _PluginRuntimeShutdownMode.idle;

  // Cache in-memory למניעת שאילתות SQLite חוזרות במסלול החם
  final Map<String, bool> _enabledCache = {};
  final Map<String, Map<String, bool?>> _permissionCache = {};

  // ה-payload האחרון של theme.changed — תוסף מושהה לא מקבל את האירוע
  // (ה-WebView מוקפא), ולכן מסנכרנים אותו מחדש בהתעוררות.
  Map<String, dynamic>? _lastThemePayload;

  /// Events whose work must continue in the non-suspended background host.
  /// All other broadcast events retain the legacy foreground-first behavior.
  static const Set<String> _backgroundEventTopics = {
    'reader.sectionContentChanged',
  };

  /// callback לטעינה מחדש של תוסף — מופעל פר instance כדי שכל
  /// host יוכל לרענן את ה-webview שלו בנפרד.
  final Map<String, Map<PluginInstanceId, Future<void> Function()>>
  _reloadCallbacks = {};

  // ── מחזור חיים של ה-instance ה-foreground (PluginTabPage) ────────────────
  // משהים את ה-WebView של תוסף שעזבו כדי לא לצרוך CPU/RAM ברקע. pause נייטיב =
  // TrySuspend ב-WebView2 (Windows) / onPause (Android) — מקפיא בלי reload.
  // לא נוגעים ב-instance הרקע ('background') — תוספי run_on_startup אמורים לרוץ.
  //
  // קבוצה ולא מזהה יחיד: טאב מפוצל בעיון יכול להציג שני תוספים בו-זמנית,
  // ועם מזהה יחיד אחד מהם היה נשאר מוקפא על המסך.
  Set<String> _visiblePluginIds = const {};
  bool _readerScreenVisible = true;
  Set<String> _runningForegroundPluginIds = const {};

  /// תוספים שה-instance ה-foreground שלהם מושהה כרגע. אירוע שנשלח ל-WebView
  /// מוקפא נבלע בשקט, ולכן [_selectEventControllers] מדלג עליהם ונופל
  /// ל-instance הרקע.
  final Set<String> _suspendedForegroundIds = {};

  // מסדר את כל פעולות מחזור-החיים בשרשרת אחת. בלי זה, שני reconciles
  // חופפים (מעבר מהיר בין תוספים/מסכים) מ-await בו-זמנית את pause/resume,
  // ועלולים להשאיר את התוסף הלא-נכון מושהה או לשלוח resumed אחרי suspended.
  Future<void> _lifecycleLock = Future.value();

  void registerController(
    String pluginId,
    InAppWebViewController controller, {
    PluginInstanceId instanceId = 'default',
  }) {
    if (_shutdownMode == _PluginRuntimeShutdownMode.exit) {
      debugPrint(
        'PluginRuntimeDispatcher: ignoring controller registration for '
        '$pluginId during app exit',
      );
      return;
    }
    _shutdownMode = _PluginRuntimeShutdownMode.idle;
    final instances = _controllersByPlugin.putIfAbsent(pluginId, () => {});
    instances[instanceId] = controller;
  }

  void unregisterController(
    String pluginId, {
    PluginInstanceId instanceId = 'default',
  }) {
    final instances = _controllersByPlugin[pluginId];
    if (instances != null) {
      instances.remove(instanceId);
      if (instances.isEmpty) {
        _controllersByPlugin.remove(pluginId);
      }
    }
    // ה-cache הוא ברמת ה-plugin; ננקה רק כשלא נשאר אף instance.
    if (_controllersByPlugin[pluginId] == null) {
      _enabledCache.remove(pluginId);
      _permissionCache.remove(pluginId);
      ContextMenuRegistry.instance.removeAll(pluginId);
      PluginToolbarRegistry.instance.removeAll(pluginId);
      // רישומים דקלרטיביים מהמניפסט אינם תלויים במנוע חי — נשארים גם אחרי
      // כיבוי עצל של מופע הרקע (אחרת הפקדים היו נעלמים אחרי 3 דקות).
      PluginStartupContributionsService.instance.reapply(pluginId);
    }
    // ה-controller ה-foreground נסגר (טאב נסגר) — לא נחזיק מצביע מת.
    if (instanceId == 'default') {
      _runningForegroundPluginIds = {..._runningForegroundPluginIds}
        ..remove(pluginId);
      _suspendedForegroundIds.remove(pluginId);
    }
  }

  /// מעדכן אילו תוספים מוצגים כעת בטאב העיון הפעיל (קבוצה ריקה = אף אחד).
  void setVisiblePluginTabs(Set<String> pluginIds) {
    if (setEquals(_visiblePluginIds, pluginIds)) return;
    _visiblePluginIds = Set.unmodifiable(pluginIds);
    unawaited(_serializeLifecycle(_reconcileForeground));
  }

  /// מעדכן אם מסך העיון גלוי. ביציאה משהים את התוספים המוצגים, בחזרה מחדשים.
  void setReaderScreenVisible(bool visible) {
    if (_readerScreenVisible == visible) return;
    _readerScreenVisible = visible;
    unawaited(_serializeLifecycle(_reconcileForeground));
  }

  Set<String> get _desiredForegroundIds =>
      _readerScreenVisible ? _visiblePluginIds : const {};

  /// מאפס את מצב הנראות בלבד (בלי לגעת ב-controllers). הדיספצ'ר הוא singleton,
  /// ובלי איפוס מפורש מצב מטסט אחד דולף לבא אחריו.
  @visibleForTesting
  void resetVisibilityForTesting() {
    _visiblePluginIds = const {};
    _runningForegroundPluginIds = const {};
    _suspendedForegroundIds.clear();
    _readerScreenVisible = true;
    _lifecycleLock = Future.value();
  }

  /// נקרא ע"י [PluginTabPage] כשה-WebView שלו סיים להיטען (אחרי boot).
  /// אם התוסף נטען בזמן שאינו מוצג (למשל המשתמש עבר לטאב אחר לפני שהטעינה
  /// הסתיימה) — משהים אותו מיד; אחרת ה-boot ממשיך כרגיל.
  Future<void> onForegroundInstanceReady(String pluginId) {
    return _serializeLifecycle(() async {
      // מסירה חוזרת: אירוע שהוזרק לטאב מושעה שההחייאה שלו גררה טעינת-דף
      // מחדש (ה-WebView מושמד בהשעיה) נפל לדף בלי מאזינים. עכשיו, כשה-boot
      // הסתיים, מזריקים אותו שוב — הבקשות אידמפוטנטיות (אותו requestId).
      final controller = _controllersByPlugin[pluginId]?['default'];
      final now = DateTime.now();
      final fresh = (_pendingRedeliveries.remove(pluginId) ?? const [])
          .where((event) => now.difference(event.at) < _redeliverWindow)
          .toList();
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
      if (!_desiredForegroundIds.contains(pluginId)) {
        if (controller != null && fresh.isNotEmpty) {
          // זה עתה נמסרו אירועים — הקפאה מיידית הייתה קוטעת את הטיפול בהם.
          _scheduleSuspendAfterGrace(pluginId, controller);
        } else {
          await _suspendForeground(pluginId);
        }
      } else {
        // התוסף נטען כשהוא כבר מוצג — מסירים סימון השהיה שנשאר ממופע קודם.
        _runningForegroundPluginIds = {
          ..._runningForegroundPluginIds,
          pluginId,
        };
        _suspendedForegroundIds.remove(pluginId);
      }
    });
  }

  /// אירועים שהוזרקו לטאב מושעה וממתינים למסירה חוזרת אם הדף ייטען מחדש.
  static const _redeliverWindow = Duration(seconds: 30);
  static const _maxPendingRedeliveries = 5;
  final Map<String, List<({String topic, String jsonPayload, DateTime at})>>
  _pendingRedeliveries = {};

  Future<void> _serializeLifecycle(Future<void> Function() action) {
    final next = _lifecycleLock.then((_) => action());
    // catchError כדי ששגיאה בלינק אחד לא תשבור את השרשרת כולה.
    _lifecycleLock = next.catchError((_) {});
    return next;
  }

  /// משווה בין התוספים הרצויים-להרצה לרצים-בפועל ומשהה/מחדש בהתאם.
  /// הרצויים = התוספים המוצגים בטאב הפעיל כשמסך העיון גלוי, אחרת אף אחד.
  Future<void> _reconcileForeground() async {
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    final desired = _desiredForegroundIds;
    if (setEquals(desired, _runningForegroundPluginIds)) return;
    final previous = _runningForegroundPluginIds;
    _runningForegroundPluginIds = Set.unmodifiable(desired);
    for (final pluginId in previous) {
      if (!desired.contains(pluginId)) await _suspendForeground(pluginId);
    }
    for (final pluginId in desired) {
      if (!previous.contains(pluginId)) await _resumeForeground(pluginId);
    }
  }

  bool get _supportsNativePauseResume =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.windows;

  Future<void> _suspendForeground(String pluginId) async {
    final controller = _controllersByPlugin[pluginId]?['default'];
    if (controller == null) return;
    // הסימון לפני ההשהיה: מרגע זה כל אירוע חייב ללכת ל-instance הרקע.
    _suspendedForegroundIds.add(pluginId);
    // מודיעים ל-JS לפני ההקפאה כדי שיעצור timers בעצמו — זו ההגנה היחידה
    // בפלטפורמות שבהן pause נייטיב אינו נתמך (macOS/iOS/Linux).
    await _dispatchLifecycleEvent(controller, pluginId, 'plugin.suspended');
    if (_supportsNativePauseResume) {
      try {
        await controller.pause();
      } catch (e) {
        debugPrint('PluginRuntimeDispatcher: pause failed for $pluginId: $e');
      }
    }
  }

  Future<void> _resumeForeground(String pluginId) async {
    final controller = _controllersByPlugin[pluginId]?['default'];
    if (controller == null) return;
    if (_supportsNativePauseResume) {
      try {
        await controller.resume();
      } catch (e) {
        debugPrint('PluginRuntimeDispatcher: resume failed for $pluginId: $e');
      }
    }
    _suspendedForegroundIds.remove(pluginId);
    await _dispatchLifecycleEvent(controller, pluginId, 'plugin.resumed');
    await _resyncThemeOnResume(controller, pluginId);
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
    final pluginIds = _controllersByPlugin.keys.toList(growable: false);
    for (final instances in _controllersByPlugin.values) {
      allControllers.addAll(instances.values);
    }

    _controllersByPlugin.clear();
    _enabledCache.clear();
    _permissionCache.clear();
    _reloadCallbacks.clear();
    _reloadCallbackTokens.clear();
    _visiblePluginIds = const {};
    _runningForegroundPluginIds = const {};
    _suspendedForegroundIds.clear();
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

  /// האם ה-controller ה-foreground הרשום לתוסף הוא [controller].
  ///
  /// דף שמוחלף (עדכון תוסף משנה את ה-key) חייב לבדוק זאת לפני שהוא מבטל
  /// רישום: ה-`initState` של הדף החדש רץ לפני ה-`dispose` של הישן.
  bool ownsForegroundController(
    String pluginId,
    InAppWebViewController? controller,
  ) {
    if (controller == null) return false;
    return identical(_controllersByPlugin[pluginId]?['default'], controller);
  }

  /// [token] מזהה את בעל ה-callback (בדרך כלל ה-`State` שרשם אותו), כדי
  /// שדף שהוחלף לא יבטל את הרישום של מחליפו.
  final Map<String, Map<PluginInstanceId, Object?>> _reloadCallbackTokens = {};

  void registerReloadCallback(
    String pluginId,
    Future<void> Function() callback, {
    PluginInstanceId instanceId = 'default',
    Object? token,
  }) {
    final instances = _reloadCallbacks.putIfAbsent(pluginId, () => {});
    instances[instanceId] = callback;
    _reloadCallbackTokens.putIfAbsent(pluginId, () => {})[instanceId] = token;
  }

  void unregisterReloadCallback(
    String pluginId, {
    PluginInstanceId instanceId = 'default',
    Object? token,
  }) {
    final registeredToken = _reloadCallbackTokens[pluginId]?[instanceId];
    if (token != null && registeredToken != null && registeredToken != token) {
      return;
    }
    final instances = _reloadCallbacks[pluginId];
    if (instances != null) {
      instances.remove(instanceId);
      if (instances.isEmpty) {
        _reloadCallbacks.remove(pluginId);
      }
    }
    final tokens = _reloadCallbackTokens[pluginId];
    if (tokens != null) {
      tokens.remove(instanceId);
      if (tokens.isEmpty) _reloadCallbackTokens.remove(pluginId);
    }
  }

  Future<void> reloadPlugin(String pluginId) async {
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    ContextMenuRegistry.instance.removeAll(pluginId);
    PluginToolbarRegistry.instance.removeAll(pluginId);
    PluginHighlightRegistry.instance.removePlugin(pluginId);
    // רישומים דקלרטיביים מהמניפסט אינם תלויים ב-JS — מוחזרים מיד.
    PluginStartupContributionsService.instance.reapply(pluginId);
    final callbacks = _reloadCallbacks[pluginId];
    if (callbacks == null || callbacks.isEmpty) return;
    // עותק כדי לא לקרוס אם callback משתמש ב-unregister באמצעו
    final snapshot = callbacks.values.toList(growable: false);
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

    // מחזיקים את המפה הפנימית: סגירת טאב באמצע ה-await מוחקת את הרשומה
    // מ-_permissionCache (unregisterController), וקריאה חוזרת דרכה תזרוק.
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
    final jsonPayload = jsonEncode(payload);
    debugPrint('PluginRuntimeDispatcher: Dispatching $topic');

    // עותק: ה-await שבגוף הלולאה משחרר את לולאת האירועים, וסגירת טאב מסירה
    // בינתיים את התוסף מהמפה (unregisterController) — איטרציה חיה קורסת.
    for (final entry in _controllersByPlugin.entries.toList(growable: false)) {
      final pluginId = entry.key;
      final instances = entry.value;
      if (instances.isEmpty) continue;

      try {
        if (!await _canReceiveEvent(pluginId, topic)) continue;

        // אירועי עבודה שייכים ל-instance הרקע, שאינו מושהה ביציאה ממסך
        // העיון. theme הוא אירוע UI ולכן מעדיפים עבורו את ה-foreground.
        final targetControllers = _selectEventControllers(
          pluginId,
          instances,
          preferBackground: _backgroundEventTopics.contains(topic),
        );
        _notifyBackgroundActivity(pluginId, instances, targetControllers);
        for (final controller in targetControllers) {
          try {
            await controller.evaluateJavascript(
              source:
                  "window.dispatchEvent(new CustomEvent('$topic', { detail: $jsonPayload }));",
            );
          } catch (e) {
            debugPrint('Failed to dispatch $topic to plugin $pluginId: $e');
          }
        }
      } catch (e) {
        debugPrint('Failed to dispatch $topic to plugin $pluginId: $e');
      }
    }

    // הערה עצלה: תוסף עם contributes.startup שהצהיר על הנושא ואין לו מופע
    // שמסוגל לקבל אותו — מקבל מנוע רק עכשיו, כשהאירוע באמת קרה.
    PluginLazyActivationService.instance.onBroadcast(
      topic,
      payload,
      hasUsableInstance: (pluginId) {
        final instances = _controllersByPlugin[pluginId];
        if (instances == null || instances.isEmpty) return false;
        // מופע רקע באמצע boot עוד לא מסוגל לקבל אירועים.
        if (instances.containsKey('background') &&
            !PluginLazyActivationService.instance.isBootPending(pluginId)) {
          return true;
        }
        return instances.containsKey('default') &&
            !_suspendedForegroundIds.contains(pluginId);
      },
    );
  }

  /// שולח event לפלאגין ספציפי בלבד (ללא בדיקת הרשאת subscribe).
  /// משמש לאירועים ממוקדים כמו reader.context_menu_item_clicked.
  Future<void> dispatchEventToPlugin(
    String pluginId,
    String topic,
    Map<String, dynamic> payload, {
    bool preferBackground = false,
    bool resumeForegroundIfNeeded = false,
  }) async {
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    // מופע רקע שנרשם אך טרם סיים boot: eval היה נבלע — האירוע ממתין בתור.
    if (PluginLazyActivationService.instance.queueIfBootPending(
      pluginId,
      topic,
      payload,
    )) {
      debugPrint('PluginRuntimeDispatcher: $topic → queued (boot pending)');
      return;
    }
    final instances = _controllersByPlugin[pluginId];
    if (instances == null || instances.isEmpty) {
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
    // foreground מושהה בלי מופע רקע מטופל בהמשך ע"י החייאת הטאב המושהה
    // (_dispatchToSuspendedForeground) — עדיף על הקמת מנוע רקע נוסף.
    try {
      final isEnabled =
          _enabledCache[pluginId] ?? await _repository.getIsEnabled(pluginId);
      _enabledCache[pluginId] = isEnabled;
      if (!isEnabled) return;
      final jsonPayload = jsonEncode(payload);
      final foregroundSuspended = _suspendedForegroundIds.contains(pluginId);
      final shouldResumeForeground =
          foregroundSuspended &&
          instances.containsKey('default') &&
          (resumeForegroundIfNeeded ||
              (preferBackground && !instances.containsKey('background')));
      if (shouldResumeForeground) {
        debugPrint('PluginRuntimeDispatcher: $topic → resume suspended tab');
        await _dispatchToSuspendedForeground(pluginId, topic, jsonPayload);
        return;
      }
      // אירועים ממוקדים (למשל לחיצה בתפריט הקשר) חייבים להגיע למנוע הפעיל.
      // ה-foreground עשוי להישאר רשום אך מושהה, ולכן הבחירה מתחשבת בכך.
      final targetControllers = _selectEventControllers(
        pluginId,
        instances,
        preferBackground: preferBackground,
      );
      _notifyBackgroundActivity(pluginId, instances, targetControllers);
      debugPrint(
        'PluginRuntimeDispatcher: $topic → eval to '
        '${targetControllers.length} controller(s)',
      );
      for (final controller in targetControllers) {
        try {
          await controller.evaluateJavascript(
            source:
                "window.dispatchEvent(new CustomEvent('$topic', { detail: $jsonPayload }));",
          );
        } catch (e) {
          debugPrint('Failed to dispatch $topic to plugin $pluginId: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to dispatch $topic to plugin $pluginId: $e');
    }
  }

  Future<void> _dispatchToSuspendedForeground(
    String pluginId,
    String topic,
    String jsonPayload,
  ) {
    return _serializeLifecycle(() async {
      final controller = _controllersByPlugin[pluginId]?['default'];
      if (controller == null) return;
      // ההזרקה שלהלן אובדת אם ההחייאה גוררת טעינת-דף מחדש — האירוע נרשם
      // למסירה חוזרת כשה-boot של הדף יסתיים (onForegroundInstanceReady).
      final pending = _pendingRedeliveries.putIfAbsent(pluginId, () => []);
      if (pending.length >= _maxPendingRedeliveries) pending.removeAt(0);
      pending.add((topic: topic, jsonPayload: jsonPayload, at: DateTime.now()));
      try {
        await _resumeForeground(pluginId);
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
          _suspendedForegroundIds.add(pluginId);
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
          _controllersByPlugin[pluginId]?['default'],
          controller,
        );
        if (_desiredForegroundIds.contains(pluginId) && stillRegistered) {
          _runningForegroundPluginIds = {
            ..._runningForegroundPluginIds,
            pluginId,
          };
        } else if (stillRegistered) {
          // אירוע ממוקד פותח לרוב טיפול אסינכרוני (בקשת חיפוש שעונה דרך
          // ה-bridge); הקפאה מיידית הייתה מקפיאה את ה-JS באמצע והתשובה
          // לא הייתה מגיעה לעולם. משהים מחדש רק אחרי חלון חסד.
          _scheduleSuspendAfterGrace(pluginId, controller);
        } else {
          await _suspendForeground(pluginId);
        }
      }
    });
  }

  /// חלון חסד להשלמת טיפול אסינכרוני לפני הקפאה חוזרת של טאב מושהה.
  static const _suspendGrace = Duration(seconds: 90);
  final Map<String, Timer> _suspendGraceTimers = {};

  void _scheduleSuspendAfterGrace(
    String pluginId,
    InAppWebViewController controller,
  ) {
    // אירוע נוסף בתוך החלון מאריך אותו — הטאב עדיין בעבודה.
    _suspendGraceTimers.remove(pluginId)?.cancel();
    _suspendGraceTimers[pluginId] = Timer(_suspendGrace, () {
      _suspendGraceTimers.remove(pluginId);
      unawaited(
        _serializeLifecycle(() async {
          final stillRegistered = identical(
            _controllersByPlugin[pluginId]?['default'],
            controller,
          );
          if (!stillRegistered ||
              _desiredForegroundIds.contains(pluginId) ||
              _suspendedForegroundIds.contains(pluginId)) {
            return;
          }
          await _suspendForeground(pluginId);
        }),
      );
    });
  }

  /// אירוע שנמסר למופע הרקע נחשב פעילות — מאפס את שעון הכיבוי העצל שלו.
  void _notifyBackgroundActivity(
    String pluginId,
    Map<PluginInstanceId, InAppWebViewController> instances,
    List<InAppWebViewController> targets,
  ) {
    final background = instances['background'];
    if (background != null && targets.contains(background)) {
      PluginLazyActivationService.instance.notifyActivity(pluginId);
    }
  }

  /// [pluginId] נדרש כדי לדעת אם ה-instance ה-foreground מושהה: `evaluateJavascript`
  /// על WebView מוקפא נבלע בשקט, ולכן אירוע כזה חייב ללכת ל-instance הרקע.
  /// טאבי כלים נשארים רשומים כל עוד הטאב פתוח, ולכן "רשום אך מושהה" הוא מצב
  /// שכיח ולא חריג.
  List<InAppWebViewController> _selectEventControllers(
    String pluginId,
    Map<PluginInstanceId, InAppWebViewController> instances, {
    bool preferBackground = false,
  }) {
    final foregroundSuspended = _suspendedForegroundIds.contains(pluginId);
    if ((preferBackground || foregroundSuspended) &&
        instances.containsKey('background')) {
      return [instances['background']!];
    }
    if (instances.containsKey('default')) {
      return [instances['default']!];
    }
    if (instances.containsKey('background')) {
      return [instances['background']!];
    }
    return instances.values.toList(growable: false);
  }
}
