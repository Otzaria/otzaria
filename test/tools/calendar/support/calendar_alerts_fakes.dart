import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_store.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';

/// התראה שהגיעה למערכת.
typedef ScheduledCall = ({
  int id,
  String title,
  String body,
  DateTime eventDate,
  int minutes,
  bool sound,
});

/// מתנהג כמו התוסף ב-Windows: תזמון מוסיף מופע ואינו דורס, וביטול מסיר
/// מופע אחד בלבד. כך כפילות שנשארת נראית בספירה.
class WindowsLikeNotifications implements NotificationService {
  final counts = <int, int>{};
  var pendingQueries = 0;
  final scheduled = <ScheduledCall>[];
  final cancelled = <int>[];
  final shown = <int>[];
  final failingIds = <int>{};
  int initCalls = 0;
  bool permissions = true;
  bool _initialized = false;

  /// כשמוגדר, האתחול ממתין לו — כמו שער החשיפה של החלון.
  Completer<void>? initGate;

  /// כשמוגדר, כל תזמון ממתין לו.
  Completer<void>? scheduleGate;

  /// נקרא לפני כל תזמון, עם מספר התזמון (מ-1).
  void Function(int call)? onSchedule;

  /// כשמוגדר, כל ביטול ממתין לו.
  Completer<void>? cancelGate;

  /// נקרא לפני כל ביטול.
  void Function()? onCancel;

  Set<int> get present => {
    for (final entry in counts.entries)
      if (entry.value > 0) entry.key,
  };

  bool get everyIdAtMostOnce => counts.values.every((count) => count <= 1);

  @override
  bool get isInitialized => _initialized;

  @override
  bool get hasPermissions => permissions;

  @override
  Future<bool> ensureInitialized() async {
    if (_initialized) return true;
    initCalls++;
    await initGate?.future;
    _initialized = true;
    return true;
  }

  @override
  Future<bool> ensureReadyToCancel() => ensureInitialized();

  @override
  Future<bool> checkPermissions() async => permissions;

  @override
  Future<bool> requestPermissions() async => permissions;

  @override
  Future<bool> forceRequestPermissions() async => permissions;

  @override
  Future<bool> sendTestNotification() async => permissions;

  @override
  Future<void> cancelNotifications(Iterable<int> ids) async {
    onCancel?.call();
    await cancelGate?.future;
    await Future<void>.delayed(Duration.zero);
    for (final id in ids) {
      cancelled.add(id);
      final count = counts[id] ?? 0;
      if (count > 0) counts[id] = count - 1;
    }
  }

  @override
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime eventDate,
    required int reminderMinutes,
    bool soundEnabled = true,
  }) async {
    onSchedule?.call(scheduled.length + 1);
    await scheduleGate?.future;
    await Future<void>.delayed(Duration.zero);
    if (!permissions) throw StateError('Notification permissions not granted');
    if (failingIds.contains(id)) throw StateError('schedule failed');
    scheduled.add((
      id: id,
      title: title,
      body: body,
      eventDate: eventDate,
      minutes: reminderMinutes,
      sound: soundEnabled,
    ));
    counts[id] = (counts[id] ?? 0) + 1;
  }

  @override
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    shown.add(id);
  }

  @override
  Future<List<int>> pendingNotificationIds() async {
    pendingQueries++;
    return [
      for (final entry in counts.entries)
        for (var i = 0; i < entry.value; i++) entry.key,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// רישום מזהי ההתראות של התוספים בזיכרון.
class MemoryPluginIds implements PluginNotificationIdStore {
  final ids = <String, List<int>>{};

  @override
  Future<List<int>> read(String pluginId) async {
    await Future<void>.delayed(Duration.zero);
    return [...?ids[pluginId]];
  }

  @override
  Future<void> write(String pluginId, List<int> value) async {
    await Future<void>.delayed(Duration.zero);
    ids[pluginId] = [...value];
  }
}

/// מצב הבעלים בזיכרון, עם יומן כתיבות הרישום.
class MemoryAlertsStore implements CalendarAlertsStore {
  MemoryAlertsStore([Map<String, Object?> values = const {}])
    : values = {...CalendarAlertsKeys.defaults, ...values};

  final Map<String, Object?> values;
  List<int> ledger = [];
  final ledgerWrites = <List<int>>[];
  bool duplicatesCleaned = false;

  @override
  Future<Map<String, Object?>> readValues() async {
    await Future<void>.delayed(Duration.zero);
    return Map.of(values);
  }

  @override
  Future<void> writeValues(Map<String, Object?> changed) async {
    await Future<void>.delayed(Duration.zero);
    values.addAll(changed);
  }

  @override
  List<int> readLedger() => [...ledger];

  @override
  Future<void> writeLedger(List<int> ids) async {
    ledger = [...ids];
    ledgerWrites.add([...ids]);
  }

  @override
  bool readDuplicatesCleaned() => duplicatesCleaned;

  @override
  Future<void> markDuplicatesCleaned() async => duplicatesCleaned = true;
}

/// הגדרות בזיכרון שמשדרות כתיבה כמו `HiveCache`.
class MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  void put(String key, Object? value) =>
      value == null ? _values.remove(key) : _values[key] = value;

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    return value is T ? value : defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async => _values.clear();

  @override
  Future<void> setBool(String key, bool? value) => setObject(key, value);

  @override
  Future<void> setDouble(String key, double? value) => setObject(key, value);

  @override
  Future<void> setInt(String key, int? value) => setObject(key, value);

  @override
  Future<void> setString(String key, String? value) => setObject(key, value);

  @override
  Future<void> setObject<T>(String key, T? value) async {
    // כמו Hive: הכתיבה אסינכרונית, ופקודה אחרת יכולה לקרוא באמצעה.
    await Future<void>.delayed(Duration.zero);
    put(key, value);
  }
}

/// אירוע משתמש עתידי ביום [day] של אוקטובר 2026.
CustomEvent futureEvent(String id, {int day = 25, String? icsSourceId}) =>
    CustomEvent(
      id: id,
      title: 'אירוע $id',
      description: '',
      createdAt: DateTime(2026, 10, 1),
      baseGregorianDate: DateTime(2026, 10, day),
      baseJewishYear: 5787,
      baseJewishMonth: 8,
      baseJewishDay: 14,
      recurrenceType: RecurrenceType.none,
      recurringYears: null,
      eventTime: const TimeOfDay(hour: 18, minute: 0),
      icsSourceId: icsSourceId,
    );

/// המזהה שהפלנר נותן לתזכורת של אירוע חד-פעמי.
int reminderId(String eventId) => eventId.hashCode;
