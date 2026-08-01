import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';

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
      if (!_desiredForegroundIds.contains(pluginId)) {
        await _suspendForeground(pluginId);
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

  Future<void> _suspendForeground(String pluginId) async {
    final controller = _controllersByPlugin[pluginId]?['default'];
    if (controller == null) return;
    // הסימון לפני ההשהיה: מרגע זה כל אירוע חייב ללכת ל-instance הרקע.
    _suspendedForegroundIds.add(pluginId);
    // מודיעים ל-JS לפני ההקפאה כדי שיעצור timers בעצמו — זו ההגנה היחידה
    // בפלטפורמות שבהן pause נייטיב אינו נתמך (macOS/iOS/Linux).
    await _dispatchLifecycleEvent(controller, pluginId, 'plugin.suspended');
    try {
      await controller.pause();
    } catch (e) {
      debugPrint('PluginRuntimeDispatcher: pause failed for $pluginId: $e');
    }
  }

  Future<void> _resumeForeground(String pluginId) async {
    final controller = _controllersByPlugin[pluginId]?['default'];
    if (controller == null) return;
    try {
      await controller.resume();
    } catch (e) {
      debugPrint('PluginRuntimeDispatcher: resume failed for $pluginId: $e');
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
      await controller.evaluateJavascript(
        source:
            "window.dispatchEvent(new CustomEvent('theme.changed', { detail: ${jsonEncode(payload)} }));",
      );
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
      await controller.evaluateJavascript(
        source:
            "window.dispatchEvent(new CustomEvent('$topic', { detail: null }));",
      );
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

    for (final controller in allControllers) {
      try {
        await controller.loadUrl(
          urlRequest: URLRequest(
            url: WebUri.uri(Uri.parse('about:blank')),
          ),
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
    PluginHighlightRegistry.instance.removePlugin(pluginId);
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

    _permissionCache[pluginId] ??= {};
    final permKey = 'events.subscribe:$topic';
    if (!_permissionCache[pluginId]!.containsKey(permKey)) {
      _permissionCache[pluginId]![permKey] = await _repository.getPermission(
        pluginId,
        permKey,
      );
    }
    return _permissionCache[pluginId]![permKey] == true;
  }

  Future<void> dispatchEvent(String topic, Map<String, dynamic> payload) async {
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    if (topic == 'theme.changed') _lastThemePayload = payload;
    final jsonPayload = jsonEncode(payload);
    debugPrint('PluginRuntimeDispatcher: Dispatching $topic');

    for (final entry in _controllersByPlugin.entries) {
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
  }

  /// שולח event לפלאגין ספציפי בלבד (ללא בדיקת הרשאת subscribe).
  /// משמש לאירועים ממוקדים כמו reader.context_menu_item_clicked.
  Future<void> dispatchEventToPlugin(
    String pluginId,
    String topic,
    Map<String, dynamic> payload, {
    bool preferBackground = false,
  }) async {
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    final instances = _controllersByPlugin[pluginId];
    if (instances == null || instances.isEmpty) return;
    try {
      final isEnabled =
          _enabledCache[pluginId] ?? await _repository.getIsEnabled(pluginId);
      _enabledCache[pluginId] = isEnabled;
      if (!isEnabled) return;
      final jsonPayload = jsonEncode(payload);
      // אירועים ממוקדים (למשל לחיצה בתפריט הקשר) חייבים להגיע למנוע הפעיל.
      // ה-foreground עשוי להישאר רשום אך מושהה, ולכן הבחירה מתחשבת בכך.
      final targetControllers = _selectEventControllers(
        pluginId,
        instances,
        preferBackground: preferBackground,
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
