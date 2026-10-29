import 'dart:convert';

import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

/// מפתחות ההגדרות שרק בעל ההתראות כותב, וערכי ברירת המחדל שלהם.
abstract final class CalendarAlertsKeys {
  static const String events = SettingsRepository.keyCalendarEvents;
  static const String enabled =
      SettingsRepository.keyCalendarNotificationsEnabled;
  static const String time = SettingsRepository.keyCalendarNotificationTime;
  static const String sound = SettingsRepository.keyCalendarNotificationSound;
  static const String zmanAlerts = SettingsRepository.keyCalendarZmanAlerts;
  static const String city = SettingsRepository.keySelectedCity;
  static const String icsSubscriptions =
      SettingsRepository.keyCalendarIcsSubscriptions;
  static const String twelveHourClock =
      SettingsRepository.keyCalendarTwelveHourClock;

  /// רישום המזהים שהבעלים תזמן. פרטי לבעלים ואינו משודר לאף חלון.
  static const String ledger =
      SettingsRepository.keyCalendarEventNotificationIds;

  static const Map<String, Object> defaults = {
    events: '[]',
    enabled: true,
    time: 60,
    sound: true,
    zmanAlerts: '{}',
    city: 'ירושלים',
    icsSubscriptions: '[]',
    twelveHourClock: false,
  };
}

/// המצב השמור של הבעלים: ערכי [CalendarAlertsKeys.defaults] ורישום המזהים.
abstract class CalendarAlertsStore {
  /// הערכים העדכניים, עם ברירות מחדל למפתח חסר.
  Future<Map<String, Object?>> readValues();

  Future<void> writeValues(Map<String, Object?> changed);

  List<int> readLedger();

  Future<void> writeLedger(List<int> ids);
}

/// קורא וכותב ישירות להגדרות של ה-isolate, כך שכל פקודה רואה את הערך העדכני.
class SettingsCalendarAlertsStore implements CalendarAlertsStore {
  const SettingsCalendarAlertsStore();

  @override
  Future<Map<String, Object?>> readValues() async => {
    for (final entry in CalendarAlertsKeys.defaults.entries)
      entry.key: _read(entry.key, entry.value),
  };

  static Object _read(String key, Object fallback) {
    final value = Settings.getValue<Object>(key);
    return sameKind(value, fallback) ? value! : fallback;
  }

  @override
  Future<void> writeValues(Map<String, Object?> changed) async {
    for (final entry in changed.entries) {
      await Settings.setValue<Object?>(entry.key, entry.value);
    }
  }

  @override
  List<int> readLedger() => decodeLedger(
    Settings.getValue<String>(CalendarAlertsKeys.ledger) ?? '[]',
  );

  @override
  Future<void> writeLedger(List<int> ids) =>
      Settings.setValue<String>(CalendarAlertsKeys.ledger, jsonEncode(ids));
}

/// מעל [SettingsRepository] שהוזרק (בדיקות): נטען פעם אחת ומוחזק בזיכרון.
class RepositoryCalendarAlertsStore implements CalendarAlertsStore {
  RepositoryCalendarAlertsStore(this._repository);

  final SettingsRepository _repository;
  Map<String, Object?>? _values;

  @override
  Future<Map<String, Object?>> readValues() async {
    final cached = _values;
    if (cached != null) return Map.of(cached);
    final settings = await _repository.loadSettings();
    final loaded = <String, Object?>{
      CalendarAlertsKeys.events: settings['calendarEvents'],
      CalendarAlertsKeys.enabled: settings['calendarNotificationsEnabled'],
      CalendarAlertsKeys.time: settings['calendarNotificationTime'],
      CalendarAlertsKeys.sound: settings['calendarNotificationSound'],
      CalendarAlertsKeys.zmanAlerts: settings['calendarZmanAlerts'],
      CalendarAlertsKeys.city: settings['selectedCity'],
      CalendarAlertsKeys.icsSubscriptions: settings['calendarIcsSubscriptions'],
      CalendarAlertsKeys.twelveHourClock: settings['calendarTwelveHourClock'],
    };
    for (final entry in CalendarAlertsKeys.defaults.entries) {
      final value = loaded[entry.key];
      if (!sameKind(value, entry.value)) loaded[entry.key] = entry.value;
    }
    return Map.of(_values ??= loaded);
  }

  @override
  Future<void> writeValues(Map<String, Object?> changed) async {
    await readValues();
    for (final entry in changed.entries) {
      _values![entry.key] = entry.value;
      final value = entry.value;
      switch (entry.key) {
        case CalendarAlertsKeys.events:
          await _repository.updateCalendarEvents(value as String);
        case CalendarAlertsKeys.enabled:
          await _repository.updateCalendarNotificationsEnabled(value as bool);
        case CalendarAlertsKeys.time:
          await _repository.updateCalendarNotificationTime(value as int);
        case CalendarAlertsKeys.sound:
          await _repository.updateCalendarNotificationSound(value as bool);
        case CalendarAlertsKeys.zmanAlerts:
          await _repository.updateCalendarZmanAlertsJson(value as String);
        case CalendarAlertsKeys.city:
          await _repository.updateSelectedCity(value as String);
        case CalendarAlertsKeys.icsSubscriptions:
          await _repository.updateCalendarIcsSubscriptions(value as String);
        case CalendarAlertsKeys.twelveHourClock:
          await _repository.updateCalendarTwelveHourClock(value as bool);
      }
    }
  }

  @override
  List<int> readLedger() =>
      decodeLedger(_repository.getCalendarEventNotificationIdsJson());

  @override
  Future<void> writeLedger(List<int> ids) =>
      _repository.updateCalendarEventNotificationIdsJson(jsonEncode(ids));
}

bool sameKind(Object? value, Object fallback) => switch (fallback) {
  String() => value is String,
  bool() => value is bool,
  int() => value is int,
  _ => false,
};

/// ערך פגום נקרא כרשימה ריקה: עדיף לא לבטל מאשר להפיל את המחזור.
List<int> decodeLedger(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is List) return decoded.whereType<int>().toList();
  } catch (_) {}
  return const [];
}

/// מזהי התראות המערכת שתוסף תזמן, ב-KV הפנימי שלו.
abstract class PluginNotificationIdStore {
  Future<List<int>> read(String pluginId);

  Future<void> write(String pluginId, List<int> ids);
}

class RegistryPluginNotificationIdStore implements PluginNotificationIdStore {
  RegistryPluginNotificationIdStore([PluginRegistryRepository? repository])
    : _repository = repository ?? PluginRegistryRepository();

  final PluginRegistryRepository _repository;

  static const String namespace = '_internal';
  static const String key = 'notification_ids';

  @override
  Future<List<int>> read(String pluginId) async {
    final raw = await _repository.getKV(pluginId, namespace, key);
    return raw == null ? const [] : decodeLedger(raw);
  }

  @override
  Future<void> write(String pluginId, List<int> ids) => ids.isEmpty
      ? _repository.removeKV(pluginId, namespace, key)
      : _repository.setKV(pluginId, namespace, key, jsonEncode(ids));
}
