import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

/// מנווט לדף תוסף ומוסר לו אירועים בחלון שפתח אותו, גם כשה-boot עדיין ממתין.
class PluginPageLauncher {
  static final PluginPageLauncher instance = PluginPageLauncher._();
  PluginPageLauncher._();

  final _navigators = Expando<void Function(String pluginId)>();

  void Function(String pluginId)? get navigator =>
      _navigators[AppWindowKeys.current];
  set navigator(void Function(String pluginId)? value) =>
      _navigators[AppWindowKeys.current] = value;

  void register(AppWindowKeys keys, void Function(String pluginId) navigator) =>
      _navigators[keys] = navigator;

  final _instanceOpeners = Expando<String? Function(String pluginId)>();

  /// [opener] פותח כרטיסיה חדשה של התוסף ומחזיר את מזהה המופע שלה, או `null`
  /// כשהפתיחה נדחתה (למשל כלי שאינו זמין).
  void registerInstanceOpener(
    AppWindowKeys keys,
    String? Function(String pluginId) opener,
  ) => _instanceOpeners[keys] = opener;

  void unregisterInstanceOpener(
    AppWindowKeys keys,
    String? Function(String pluginId) opener,
  ) {
    if (_instanceOpeners[keys] == opener) _instanceOpeners[keys] = null;
  }

  void unregister(
    AppWindowKeys keys,
    void Function(String pluginId) navigator,
  ) {
    if (_navigators[keys] == navigator) _navigators[keys] = null;
  }

  final Map<
    ({String pluginId, int? viewId}),
    List<({String topic, Map<String, dynamic> payload})>
  >
  _pending = {};

  /// אירועים שמיועדים למופע מסוים שנפתחה עבורו כרטיסיה חדשה. בלעדיהם האירוע
  /// היה נמסר ל"דף המוכן הראשון" של התוסף — כלומר למופע הקיים.
  final Map<
    PluginInstanceKey,
    List<({String topic, Map<String, dynamic> payload})>
  >
  _pendingByInstance = {};
  final Map<PluginInstanceKey, ({int? viewId, DateTime openedAt})>
  _pendingInstanceOrigins = {};

  /// כמה זמן אירוע ממוקד ממתין למופע שלא עלה, לפני שהוא נזנח. בלי זה כשל
  /// ב-boot משאיר אותו ומונע פינוי של כל מופעי התוסף.
  static const Duration pendingInstanceEventTtl = Duration(seconds: 60);

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  void _dropExpiredInstanceEvents() {
    final cutoff = clock().subtract(pendingInstanceEventTtl);
    final expired = [
      for (final entry in _pendingInstanceOrigins.entries)
        if (entry.value.openedAt.isBefore(cutoff)) entry.key,
    ];
    for (final key in expired) {
      _pendingInstanceOrigins.remove(key);
      _pendingByInstance.remove(key);
    }
  }
  final Map<PluginInstanceKey, int?> _readyPages = {};

  /// מופעים נוספים (שנפתחו דרך `newTab`). פתיחה רגילה לעולם אינה מוסרת להם
  /// אירוע: היעד שלה הוא המופע הראשי בלבד.
  final Set<PluginInstanceKey> _extraInstances = {};
  final Map<({String pluginId, int? viewId}), Future<void>> _deliveryChain = {};

  bool hasPendingFor(String pluginId) {
    _dropExpiredInstanceEvents();
    return _pending.entries.any(
          (entry) => entry.key.pluginId == pluginId && entry.value.isNotEmpty,
        ) ||
        _pendingByInstance.entries.any(
          (entry) => entry.key.pluginId == pluginId && entry.value.isNotEmpty,
        );
  }

  PluginInstanceKey? _readyPage(String pluginId, int? viewId) => _readyPages
      .entries
      .where(
        (entry) =>
            entry.key.pluginId == pluginId &&
            !_extraInstances.contains(entry.key) &&
            (viewId == null || entry.value == viewId),
      )
      .firstOrNull
      ?.key;

  void open(
    String pluginId, {
    String? topic,
    Map<String, dynamic> payload = const {},
    int? viewId,
    AppWindowKeys? windowKeys,
  }) {
    if (windowKeys != null && _navigators[windowKeys] == null) return;
    if (topic != null) {
      final ready = _readyPage(pluginId, viewId);
      if (ready != null) {
        _enqueueDelivery(
          pluginId,
          topic,
          payload,
          viewId: viewId,
          instanceId: ready.instanceId,
        );
      } else {
        _pending
            .putIfAbsent((pluginId: pluginId, viewId: viewId), () => [])
            .add((topic: topic, payload: payload));
      }
    }
    _navigators[windowKeys ?? AppWindowKeys.current]?.call(pluginId);
  }

  /// פותח את התוסף בכרטיסיה חדשה (מופע נוסף) ומוסר את [topic] למופע הזה בלבד.
  ///
  /// מחזיר את מזהה המופע החדש, או `null` כשלא נפתח מופע: אין פותח רשום
  /// לחלון (נסגר), או שהפותח דחה את הבקשה.
  String? openNewInstance(
    String pluginId, {
    String? topic,
    Map<String, dynamic> payload = const {},
    int? viewId,
    AppWindowKeys? windowKeys,
  }) {
    final opener = _instanceOpeners[windowKeys ?? AppWindowKeys.current];
    if (opener == null) return null;
    final instanceId = opener(pluginId);
    if (instanceId == null) return null;
    if (topic != null) {
      final key = (pluginId: pluginId, instanceId: instanceId);
      _pendingInstanceOrigins[key] = (viewId: viewId, openedAt: clock());
      _pendingByInstance
          .putIfAbsent(key, () => [])
          .add((topic: topic, payload: payload));
    }
    return instanceId;
  }

  void markPageReady(
    String pluginId, {
    String instanceId = PluginInstanceIds.defaultForeground,
    int? viewId,
    bool isPrimary = true,
  }) {
    final key = (pluginId: pluginId, instanceId: instanceId);
    _readyPages[key] = viewId;
    if (isPrimary) {
      _extraInstances.remove(key);
    } else {
      _extraInstances.add(key);
    }
    _pendingInstanceOrigins.remove((
      pluginId: pluginId,
      instanceId: instanceId,
    ));
    final targeted = _pendingByInstance.remove((
      pluginId: pluginId,
      instanceId: instanceId,
    ));
    if (targeted != null) {
      for (final event in targeted) {
        _enqueueDelivery(
          pluginId,
          event.topic,
          event.payload,
          viewId: viewId,
          instanceId: instanceId,
        );
      }
      // מופע שנפתח דרך openNewInstance מקבל רק אירועים שנועדו לו. אירועים
      // כלליים (openSelf רגיל כשלא היה דף מוכן) ממתינים לדף הראשי של התוסף.
      return;
    }
    if (!isPrimary) return;
    final pending = [
      ...?_pending.remove((pluginId: pluginId, viewId: viewId)),
      if (viewId != null)
        ...?_pending.remove((pluginId: pluginId, viewId: null)),
    ];
    for (final event in pending) {
      _enqueueDelivery(
        pluginId,
        event.topic,
        event.payload,
        viewId: viewId,
        instanceId: instanceId,
      );
    }
  }

  void markPageClosed(
    String pluginId, {
    String instanceId = PluginInstanceIds.defaultForeground,
    int? viewId,
  }) {
    final key = (pluginId: pluginId, instanceId: instanceId);
    _pendingByInstance.remove(key);
    _pendingInstanceOrigins.remove(key);
    _extraInstances.remove(key);
    final ownerView = _readyPages.containsKey(key)
        ? _readyPages.remove(key)
        : viewId;
    if (_readyPages.entries.any(
      (entry) => entry.key.pluginId == pluginId && entry.value == ownerView,
    )) {
      return;
    }
    _pending.remove((pluginId: pluginId, viewId: ownerView));
    _deliveryChain.remove((pluginId: pluginId, viewId: ownerView));
  }

  /// סגירה לפני יצירת דף אינה משאירה אירועים שממתינים לחלון שכבר איננו.
  void forgetWindow(int viewId) {
    final closedInstances = [
      for (final entry in _pendingInstanceOrigins.entries)
        if (entry.value.viewId == viewId) entry.key,
    ];
    for (final key in closedInstances) {
      _pendingInstanceOrigins.remove(key);
      _pendingByInstance.remove(key);
    }
    _pending.removeWhere((key, _) => key.viewId == viewId);
    _deliveryChain.removeWhere((key, _) => key.viewId == viewId);
    _extraInstances.removeWhere((key) => _readyPages[key] == viewId);
    _readyPages.removeWhere((_, owner) => owner == viewId);
  }

  void _enqueueDelivery(
    String pluginId,
    String topic,
    Map<String, dynamic> payload, {
    int? viewId,
    required String instanceId,
  }) {
    final key = (pluginId: pluginId, viewId: viewId);
    final previous = _deliveryChain[key] ?? Future<void>.value();
    final next = previous.then(
      (_) => PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
        pluginId,
        topic,
        payload,
        resumeForegroundIfNeeded: true,
        instanceId: instanceId,
      ),
    );
    _deliveryChain[key] = next.catchError((_) {});
  }
}
