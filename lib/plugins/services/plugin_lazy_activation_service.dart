import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/plugin_startup_contributions.dart';
import 'package:otzaria/plugins/models/plugin_when_condition.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';

/// מרים מופע רקע לפי לחיצה, אירוע מוצהר או `app.startup` דחוי.
/// אירועים שהגיעו לפני ה־boot נשמרים ונמסרים אחרי מוכנות המופע.
class PluginLazyActivationService {
  static final PluginLazyActivationService instance =
      PluginLazyActivationService._();
  PluginLazyActivationService._()
    : _conditions = PluginConditionEvaluator.instance,
      _hasEssentialState = _backgroundHasEssentialState;

  @visibleForTesting
  PluginLazyActivationService.forTesting({
    PluginConditionEvaluator? conditionEvaluator,
    bool Function(String pluginId)? hasEssentialState,
  }) : _conditions = conditionEvaluator ?? PluginConditionEvaluator.instance,
       _hasEssentialState = hasEssentialState ?? _backgroundHasEssentialState;

  final PluginConditionEvaluator _conditions;
  final bool Function(String pluginId) _hasEssentialState;

  static const int _maxPendingPerPlugin = 20;

  /// השהיית טריגר `app.startup` — כדי שהרמת המנוע לא תתחרה בעליית התוכנה.
  static const Duration startupActivationDelay = Duration(seconds: 8);

  /// מופע רקע שהוער עצל ולא הראה פעילות (RPC או אירוע נכנס) במשך זמן זה —
  /// מכובה ומשחרר את תהליכי ה-WebView2. הטריגר הבא יעיר אותו מחדש.
  static const Duration idleTeardownDelay = Duration(minutes: 3);

  @visibleForTesting
  Duration? startupDelayOverride;

  @visibleForTesting
  Duration? idleDelayOverride;

  /// עוקף את מסירת האירועים דרך ה-Dispatcher — לבדיקות בלבד.
  @visibleForTesting
  Future<void> Function(
    String pluginId,
    String topic,
    Map<String, dynamic> payload,
  )?
  deliverOverride;

  /// נרשם ע"י PluginBackgroundHost — מרים מופע רקע לפי דרישה. זריקה מתוכו
  /// (תוסף לא זמין / אין WebView2) מנקה את התור של אותו תוסף.
  Future<void> Function(String pluginId)? backgroundActivator;

  /// נרשם ע"י PluginBackgroundHost — מכבה מופע רקע שהוער עצל וכעת באפס
  /// פעילות. ההרס עצמו (dispose של ה-WebView) באחריות ה-host.
  void Function(String pluginId)? backgroundDeactivator;

  /// תוספים שמותר להעיר בעצלנות לפי ההרשאות והתרומות שסונכרנו.
  final Set<String> _activatable = {};

  /// נושאי שידור שמעירים כל תוסף (מסונכרן כולל בדיקת הרשאת subscribe).
  final Map<String, Set<String>> _broadcastTopics = {};

  /// pluginId → נושא → תנאי `when` שחייב להתקיים כדי להעיר את המנוע.
  final Map<String, Map<String, PluginWhenCondition>> _activationConditions =
      {};

  final Map<String, List<({String topic, Map<String, dynamic> payload})>>
  _pending = {};
  final Map<String, int> _activating = {};
  final Map<String, int> _activationGenerations = {};

  /// טריגר `app.startup` מופעל פעם אחת לכל סשן — נשמר גם אחרי removePlugin
  /// כדי שסנכרון חוזר (LoadPlugins) לא יפעיל את התוסף שוב.
  final Set<String> _startupFired = {};
  final Map<String, Timer> _startupTimers = {};

  /// תוספים שהמופע שלהם הוער עצל ולכן כפוף לכיבוי אחרי חוסר פעילות.
  final Set<String> _idleTracked = {};
  final Map<String, Timer> _idleTimers = {};
  final Map<String, Timer> _immediateTeardownTimers = {};
  // בקשת סגירה שה-RPC המקורי שלה עדיין פעיל, לפי דור תחילת העבודה.
  final Map<String, int> _deferredImmediateTeardowns = {};
  final Set<String> _keepAlive = {};

  /// מונה RPC שעדיין רצים פר תוסף — כל עוד חיובי, פקיעת שעון הכיבוי רק
  /// מחדשת אותו, כדי לא לקטוע פעולה ארוכה (download/extractZip).
  final Map<String, _BackgroundRuntime> _runtimes = {};

  /// הבעלים מתחלף לפני יצירת controller; dispose של הדף הקודם אינו מנקה אותו.
  Object attachBackgroundInstance(String pluginId) {
    _idleTimers.remove(pluginId)?.cancel();
    _immediateTeardownTimers.remove(pluginId)?.cancel();
    _deferredImmediateTeardowns.remove(pluginId);
    return _runtimes[pluginId] = _BackgroundRuntime();
  }

  bool _ownsRuntime(String pluginId, Object? token) =>
      token == null || identical(_runtimes[pluginId], token);

  void syncPlugin(
    String pluginId, {
    required Set<String> broadcastTopics,
    required bool scheduleStartup,
    bool keepAlive = false,
    Map<String, PluginWhenCondition> activationConditions = const {},
    String? version,
  }) {
    // גרסה חדשה של התוסף מקבלת הזדמנות נוספת אחרי נפילות חוזרות.
    if (version != null && _syncedVersions[pluginId] != version) {
      _syncedVersions[pluginId] = version;
      _clearFailures(pluginId);
    }
    _activationGenerations.putIfAbsent(pluginId, () => 0);
    _activatable.add(pluginId);
    _broadcastTopics[pluginId] = Set.unmodifiable(broadcastTopics);
    if (activationConditions.isEmpty) {
      _activationConditions.remove(pluginId);
    } else {
      _activationConditions[pluginId] = Map.unmodifiable(activationConditions);
    }
    if (keepAlive) {
      _keepAlive.add(pluginId);
      _idleTimers.remove(pluginId)?.cancel();
    } else {
      _keepAlive.remove(pluginId);
      if (_idleTracked.contains(pluginId)) _restartIdleTimer(pluginId);
    }
    if (scheduleStartup && _startupFired.add(pluginId)) {
      final generation = activationGeneration(pluginId);
      _startupTimers[pluginId] = Timer(
        startupDelayOverride ?? startupActivationDelay,
        () {
          _startupTimers.remove(pluginId);
          if (!isActivationCurrent(pluginId, generation)) return;
          if (!_activationAllowed(
            pluginId,
            PluginStartupContributions.startupActivationTopic,
          )) {
            return;
          }
          _activate(pluginId);
        },
      );
    }
  }

  void removePlugin(String pluginId) {
    _activationGenerations.update(
      pluginId,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    _activatable.remove(pluginId);
    _broadcastTopics.remove(pluginId);
    _activationConditions.remove(pluginId);
    _pending.remove(pluginId);
    _activating.remove(pluginId);
    _keepAlive.remove(pluginId);
    _clearFailures(pluginId);
    _syncedVersions.remove(pluginId);
    _startupTimers.remove(pluginId)?.cancel();
    final wasTracked = _idleTracked.contains(pluginId);
    _stopIdleTracking(pluginId);
    // תוסף שאיבד את הזכאות (שלילת הרשאה/השבתה) בזמן שמופע עצל שלו רץ —
    // המופע מכובה מיד, לא ממשיך עד סוף הסשן.
    if (wasTracked) backgroundDeactivator?.call(pluginId);
  }

  /// מתזמן כיבוי מיידי למופע רקע שבמעקב, בלי לפגוע בדף הקדמי.
  /// מחזיר האם בקשת `plugin.backgroundDone` התקבלה.
  bool requestImmediateTeardown(String pluginId, {Object? runtimeToken}) {
    if (!_ownsRuntime(pluginId, runtimeToken)) return false;
    if (!_idleTracked.contains(pluginId)) return false;
    final runtime = _runtimes[pluginId];
    _idleTimers.remove(pluginId)?.cancel();
    _deferredImmediateTeardowns.remove(pluginId);
    _scheduleImmediateTeardown(pluginId, runtime, runtime?.workRevision ?? 0);
    return true;
  }

  void _scheduleImmediateTeardown(
    String pluginId,
    _BackgroundRuntime? runtime,
    int workRevision,
  ) {
    _immediateTeardownTimers.remove(pluginId)?.cancel();
    // מאפשרים לתשובת ה-RPC להגיע ל-JavaScript לפני הרס ה-WebView.
    _immediateTeardownTimers[pluginId] = Timer(
      const Duration(milliseconds: 300),
      () {
        _immediateTeardownTimers.remove(pluginId);
        if (!_idleTracked.contains(pluginId) ||
            (runtime != null && !identical(_runtimes[pluginId], runtime))) {
          return;
        }
        // RPC חדש מאז בקשת הסגירה מבטל את הקדימות: העבודה החדשה זכאית
        // לשעון חוסר-הפעילות הרגיל.
        if (runtime != null && runtime.workRevision != workRevision) {
          _restartIdleTimer(pluginId);
          return;
        }
        if (isBusy(pluginId)) {
          // ה-RPC שהכריז backgroundDone עשוי להשתהות מעבר ל-300ms
          // בהעברת התשובה ב-WebKit. ממתינים לסיומו בפועל, ללא polling.
          // אסור להחליף כאן לשעון 3 דקות ולשכוח את בקשת הסגירה.
          if (runtime != null) {
            _deferredImmediateTeardowns[pluginId] = workRevision;
          } else {
            _restartIdleTimer(pluginId);
          }
          return;
        }
        if (!canTeardown(pluginId)) {
          _restartIdleTimer(pluginId);
          return;
        }
        backgroundDeactivator?.call(pluginId);
      },
    );
  }

  /// האם המופע של [pluginId] בתהליך הרמה (הופעל אך טרם סיים boot).
  bool isBootPending(String pluginId) => _activating.containsKey(pluginId);

  /// האם רץ כרגע RPC של [pluginId] — מופע כזה אסור בהריגה (פינוי LRU),
  /// אחרת הפעולה נקטעת באמצע וה-Promise בתוסף לא נפתר.
  bool isBusy(String pluginId) => (_runtimes[pluginId]?.workCount ?? 0) > 0;

  /// הגנות משותפות לפינוי לפי גיל ולפי תקרת מספר מופעי הרקע.
  bool canTeardown(String pluginId) =>
      !isBusy(pluginId) &&
      !isBootPending(pluginId) &&
      _pending[pluginId]?.isNotEmpty != true &&
      !_hasEssentialState(pluginId);

  static bool _backgroundHasEssentialState(String pluginId) =>
      PluginUnsavedChangesRegistry.instance.hasUnsavedChanges((
        pluginId: pluginId,
        instanceId: PluginInstanceIds.background,
      )) ||
      PluginCorrectionSessionService.instance.hasSessionsFor(pluginId);

  /// דור ההפעלה הנוכחי. משתנה בכל שלילת זכאות, כדי לבטל Future שכבר ממתין.
  int activationGeneration(String pluginId) =>
      _activationGenerations[pluginId] ?? 0;

  bool isActivationCurrent(String pluginId, int generation) =>
      _activatable.contains(pluginId) &&
      activationGeneration(pluginId) == generation;

  /// אירוע ממוקד שהגיע בזמן שהמופע עוד עולה — נכנס לתור וימסר אחרי ה-boot.
  /// שליחה ישירה ב-evaluateJavascript לפני שה-SDK נטען הייתה נבלעת בשקט.
  bool queueIfBootPending(
    String pluginId,
    String topic,
    Map<String, dynamic> payload,
  ) {
    if (!isBootPending(pluginId)) return false;
    final list = _pending.putIfAbsent(pluginId, () => []);
    if (list.length >= _maxPendingPerPlugin) list.removeAt(0);
    list.add((topic: topic, payload: payload));
    return true;
  }

  /// מסמן שמופע הרקע של [pluginId] הוער עצל — נקרא ע"י ה-host בעת הפעלה
  /// לפי דרישה. שעון הכיבוי מתחיל לרוץ רק אחרי שה-boot הסתיים.
  bool trackIdleTeardown(String pluginId, {int? generation}) {
    if (generation != null && !isActivationCurrent(pluginId, generation)) {
      return false;
    }
    _idleTracked.add(pluginId);
    return true;
  }

  /// פעילות של המופע (RPC מהתוסף או אירוע שנמסר אליו) — מאפסת את השעון.
  void notifyActivity(String pluginId) {
    if (!_idleTracked.contains(pluginId) || _keepAlive.contains(pluginId)) {
      return;
    }
    _restartIdleTimer(pluginId);
  }

  /// סיום ה-RPC שייך למופע שהתחיל אותו, ואינו משחרר עבודה של מחליפו.
  VoidCallback beginWork(String pluginId, {Object? runtimeToken}) {
    if (!_ownsRuntime(pluginId, runtimeToken)) return () {};
    final runtime = _runtimes.putIfAbsent(pluginId, _BackgroundRuntime.new);
    runtime.workRevision++;
    runtime.workCount++;
    notifyActivity(pluginId);
    var ended = false;
    return () {
      if (ended || !identical(_runtimes[pluginId], runtime)) return;
      ended = true;
      runtime.workCount--;
      notifyActivity(pluginId);
      if (runtime.workCount == 0) {
        final deferredRevision = _deferredImmediateTeardowns.remove(pluginId);
        if (deferredRevision != null &&
            runtime.workRevision == deferredRevision &&
            _idleTracked.contains(pluginId)) {
          _scheduleImmediateTeardown(pluginId, runtime, deferredRevision);
        }
      }
    };
  }

  void _restartIdleTimer(String pluginId) {
    _idleTimers.remove(pluginId)?.cancel();
    if (_keepAlive.contains(pluginId)) return;
    _idleTimers[pluginId] = Timer(idleDelayOverride ?? idleTeardownDelay, () {
      _idleTimers.remove(pluginId);
      if (!_idleTracked.contains(pluginId)) return;
      if (!canTeardown(pluginId)) {
        _restartIdleTimer(pluginId);
        return;
      }
      backgroundDeactivator?.call(pluginId);
    });
  }

  void _stopIdleTracking(String pluginId) {
    _idleTracked.remove(pluginId);
    _idleTimers.remove(pluginId)?.cancel();
    _immediateTeardownTimers.remove(pluginId)?.cancel();
    _deferredImmediateTeardowns.remove(pluginId);
    _runtimes.remove(pluginId);
  }

  /// שער הערת המנוע: תנאי `when` על נושא ההפעלה. חל רק על הערת מנוע כבוי —
  /// אירועים למנוע חי אינם עוברים כאן כלל.
  bool _activationAllowed(String pluginId, String topic) {
    final condition = _activationConditions[pluginId]?[topic];
    if (condition == null) return true;
    return _conditions.evaluate(pluginId, condition);
  }

  /// האם תנאי `when` על [topic] חוסם כרגע את הערת המנוע של [pluginId].
  /// אירוע חסום נזרק — גם לא נופל לפתיחת דף התוסף.
  bool isActivationBlocked(String pluginId, String topic) =>
      !_activationAllowed(pluginId, topic);

  /// אירוע ממוקד (לחיצת פקד/תפריט) לתוסף בלי מנוע חי. מחזיר true אם התוסף
  /// ניתן להערה והאירוע נכנס לתור; false אומר לקורא שהאירוע אבד.
  bool queueTargetedEvent(
    String pluginId,
    String topic,
    Map<String, dynamic> payload,
  ) {
    if (!_activatable.contains(pluginId)) return false;
    if (!_activationAllowed(pluginId, topic)) return false;
    if (_failureBlocked.contains(pluginId)) return false;
    final list = _pending.putIfAbsent(pluginId, () => []);
    if (list.length >= _maxPendingPerPlugin) list.removeAt(0);
    list.add((topic: topic, payload: payload));
    _activate(pluginId);
    return true;
  }

  /// אירוע שידור — מעיר כל תוסף שהצהיר על הנושא ב-activationEvents ואין לו
  /// כרגע מופע שמסוגל לקבל אותו.
  void onBroadcast(
    String topic,
    Map<String, dynamic> payload, {
    required bool Function(String pluginId) hasUsableInstance,
  }) {
    for (final entry in _broadcastTopics.entries) {
      if (!entry.value.contains(topic)) continue;
      if (hasUsableInstance(entry.key)) continue;
      queueTargetedEvent(entry.key, topic, payload);
    }
  }

  void _activate(String pluginId) {
    if (_activating.containsKey(pluginId)) return;
    if (_failureBlocked.contains(pluginId)) return;
    final activator = backgroundActivator;
    if (activator == null) return;
    final generation = activationGeneration(pluginId);
    _activating[pluginId] = generation;
    unawaited(
      activator(pluginId).catchError((Object e) {
        if (_activating[pluginId] != generation) return;
        _activating.remove(pluginId);
        _pending.remove(pluginId);
        debugPrint(
          'PluginLazyActivationService: activation failed '
          'for $pluginId: $e',
        );
      }),
    );
  }

  /// נקרא ע"י ה-runner של מופע הרקע אחרי שה-boot הסתיים — מוסר את
  /// האירועים הממתינים בסדרם.
  Future<void> onBackgroundInstanceReady(
    String pluginId, {
    int? generation,
    Object? runtimeToken,
    bool Function()? isCurrent,
  }) async {
    final readyGeneration = generation ?? activationGeneration(pluginId);
    bool stale() =>
        !_ownsRuntime(pluginId, runtimeToken) ||
        activationGeneration(pluginId) != readyGeneration ||
        (generation != null && !isActivationCurrent(pluginId, generation)) ||
        (isCurrent != null && !isCurrent());
    if (stale()) return;
    _startupTimers.remove(pluginId)?.cancel();
    _activating.remove(pluginId);
    if (_idleTracked.contains(pluginId) && !_keepAlive.contains(pluginId)) {
      _restartIdleTimer(pluginId);
    }
    final pending = _pending.remove(pluginId);
    if (pending == null) return;
    for (final event in pending) {
      if (stale()) return;
      final deliver = deliverOverride;
      if (deliver != null) {
        await deliver(pluginId, event.topic, event.payload);
      } else {
        await PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
          pluginId,
          event.topic,
          event.payload,
          instanceId: PluginInstanceIds.background,
          isCurrent: () => !stale(),
        );
      }
    }
  }

  /// מסמן שכשל boot של מופע רקע ומאפשר לטריגר הבא לנסות שוב.
  void onBackgroundInstanceFailed(
    String pluginId, {
    int? generation,
    Object? runtimeToken,
  }) {
    if (!_ownsRuntime(pluginId, runtimeToken)) return;
    if (generation != null && !isActivationCurrent(pluginId, generation)) {
      return;
    }
    final failedGeneration = generation ?? activationGeneration(pluginId);
    _activationGenerations[pluginId] = failedGeneration + 1;
    _activating.remove(pluginId);
    _pending.remove(pluginId);
    _stopIdleTracking(pluginId);
    backgroundDeactivator?.call(pluginId);
  }

  /// התהליך של מופע הרקע נפל: נספר לתקציב הנפילות, ואז כמו כל כשל.
  void onBackgroundProcessGone(
    String pluginId, {
    int? generation,
    Object? runtimeToken,
  }) {
    if (!_ownsRuntime(pluginId, runtimeToken)) return;
    if (generation != null && !isActivationCurrent(pluginId, generation)) {
      return;
    }
    _recordFailure(pluginId);
    onBackgroundInstanceFailed(
      pluginId,
      generation: generation,
      runtimeToken: runtimeToken,
    );
  }

  /// מופע רקע שתהליכו נופל שוב ושוב לא מוער עוד, עד שהתוסף מוסר, מושבת
  /// ומופעל מחדש, או מתעדכן.
  static const int _maxFailures = 3;
  static const Duration _failureWindow = Duration(minutes: 10);
  final Map<String, List<DateTime>> _failures = {};
  final Set<String> _failureBlocked = {};
  final Map<String, String> _syncedVersions = {};

  void _clearFailures(String pluginId) {
    _failures.remove(pluginId);
    _failureBlocked.remove(pluginId);
  }

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  bool isFailureBlocked(String pluginId) => _failureBlocked.contains(pluginId);

  void _recordFailure(String pluginId) {
    final now = clock();
    final list = _failures.putIfAbsent(pluginId, () => [])
      ..removeWhere((at) => now.difference(at) >= _failureWindow)
      ..add(now);
    if (list.length < _maxFailures) return;
    _failureBlocked.add(pluginId);
    debugPrint(
      'PluginLazyActivationService: $pluginId failed $_maxFailures times; '
      'not activating it again this session',
    );
  }

  void onBackgroundInstanceClosed(
    String pluginId, {
    int? generation,
    Object? runtimeToken,
  }) {
    if (!_ownsRuntime(pluginId, runtimeToken)) return;
    if (generation != null && !isActivationCurrent(pluginId, generation)) {
      return;
    }
    _activating.remove(pluginId);
    // המופע נסגר — עוצרים את השעון בלי לגעת ביכולת ההערה: הטריגר הבא
    // יעיר את התוסף מחדש ויירשם למעקב שוב דרך ה-host.
    _stopIdleTracking(pluginId);
  }
}

class _BackgroundRuntime {
  int workCount = 0;
  int workRevision = 0;
}
