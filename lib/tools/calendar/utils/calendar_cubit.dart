import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart'
    as zmanim_helpers;
import 'package:otzaria/tools/calendar/models/calendar_location.dart'
    as calendar_location;
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/adapters/plugin_calendar_adapter.dart';
import 'package:timezone/timezone.dart' as tz;

enum CalendarType { hebrew, gregorian, combined }

enum CalendarNotificationMode { sound, silent, off }

enum CalendarView { month, week, day }

enum CalendarDayTransition { sunset, tzais, rabbeinuTam, midnight }

class ZmanAlertPreference extends Equatable {
  final int minutesBefore;
  final String displayName;

  const ZmanAlertPreference({
    required this.minutesBefore,
    required this.displayName,
  });

  Map<String, dynamic> toJson() {
    return {
      'minutesBefore': minutesBefore,
      'displayName': displayName,
    };
  }

  static ZmanAlertPreference? fromJson(dynamic json, {String? fallbackName}) {
    if (json is int) {
      return ZmanAlertPreference(
        minutesBefore: json,
        displayName: fallbackName ?? '',
      );
    }
    if (json is! Map) return null;
    final minutesBefore = json['minutesBefore'];
    final displayName = json['displayName'] ?? fallbackName;
    if (minutesBefore is! int) return null;
    if (displayName is! String || displayName.isEmpty) return null;
    return ZmanAlertPreference(
      minutesBefore: minutesBefore,
      displayName: displayName,
    );
  }

  @override
  List<Object?> get props => [minutesBefore, displayName];
}

// Calendar State
class CalendarState extends Equatable {
  final JewishDate selectedJewishDate;
  final DateTime selectedGregorianDate;
  final String selectedCity;
  final Map<String, String> dailyTimes;
  final JewishDate currentJewishDate;
  final DateTime currentGregorianDate;
  final DateTime todayGregorianDate;
  final CalendarType calendarType;
  final CalendarView calendarView;
  final CalendarDayTransition dayTransition;
  final int? _calendarClockTick;
  int get calendarClockTick => _calendarClockTick ?? 0;

  CalendarNotificationMode get notificationMode {
    if (!calendarNotificationsEnabled) return CalendarNotificationMode.off;
    return calendarNotificationSound
        ? CalendarNotificationMode.sound
        : CalendarNotificationMode.silent;
  }

  final List<CustomEvent> events;
  final String eventSearchQuery;
  final bool searchInDescriptions;
  final bool inIsrael;
  final bool showAllEvents;
  final bool calendarNotificationsEnabled;
  final int calendarNotificationTime;
  final bool calendarNotificationSound;
  final Map<String, ZmanAlertPreference> zmanAlerts;

  /// מזהי הזמנים (ZmanDefinition.id) שהמשתמש בחר להציג בלוח.
  final Set<String> enabledZmanim;

  final bool googleCalendarEnabled;
  final bool googleCalendarConnected;
  final List<String> googleCalendarSelectedIds;
  final bool googleCalendarSyncInProgress;
  final String? googleCalendarSyncError;
  final DateTime? googleCalendarLastSync;
  final int googleCalendarSyncPastDays;
  final int googleCalendarSyncFutureDays;

  const CalendarState({
    required this.selectedJewishDate,
    required this.selectedGregorianDate,
    required this.selectedCity,
    required this.dailyTimes,
    required this.currentJewishDate,
    required this.currentGregorianDate,
    required this.todayGregorianDate,
    required this.calendarType,
    required this.calendarView,
    required this.dayTransition,
    required this.inIsrael,
    this._calendarClockTick = 0,
    this.events = const [],
    this.eventSearchQuery = '',
    this.searchInDescriptions = false,
    this.showAllEvents = false,
    this.calendarNotificationsEnabled = true,
    this.calendarNotificationTime = 60,
    this.calendarNotificationSound = true,
    this.zmanAlerts = const {},
    this.enabledZmanim = const {},
    this.googleCalendarEnabled = false,
    this.googleCalendarConnected = false,
    this.googleCalendarSelectedIds = const ['primary'],
    this.googleCalendarSyncInProgress = false,
    this.googleCalendarSyncError,
    this.googleCalendarLastSync,
    this.googleCalendarSyncPastDays = 60,
    this.googleCalendarSyncFutureDays = 365,
  });

  factory CalendarState.initial() {
    final now = DateTime.now();
    final jewishNow = JewishDate();

    return CalendarState(
      selectedJewishDate: jewishNow,
      selectedGregorianDate: now,
      selectedCity: 'ירושלים',
      dailyTimes: const {},
      currentJewishDate: jewishNow,
      currentGregorianDate: now,
      todayGregorianDate: DateTime(now.year, now.month, now.day),
      calendarType: CalendarType.combined,
      calendarView: CalendarView.month,
      dayTransition: CalendarDayTransition.sunset,
      searchInDescriptions: false,
      enabledZmanim: zmanim_helpers.kDefaultEnabledZmanim,
      inIsrael: true,
      showAllEvents: false,
      googleCalendarEnabled: false,
      googleCalendarConnected: false,
      googleCalendarSelectedIds: const ['primary'],
      googleCalendarSyncInProgress: false,
      googleCalendarSyncPastDays: 60,
      googleCalendarSyncFutureDays: 365,
    );
  }

  CalendarState copyWith({
    JewishDate? selectedJewishDate,
    DateTime? selectedGregorianDate,
    String? selectedCity,
    Map<String, String>? dailyTimes,
    JewishDate? currentJewishDate,
    DateTime? currentGregorianDate,
    DateTime? todayGregorianDate,
    CalendarType? calendarType,
    CalendarView? calendarView,
    CalendarDayTransition? dayTransition,
    int? calendarClockTick,
    List<CustomEvent>? events,
    String? eventSearchQuery,
    bool? searchInDescriptions,
    bool? inIsrael,
    bool? showAllEvents,
    bool? calendarNotificationsEnabled,
    int? calendarNotificationTime,
    bool? calendarNotificationSound,
    Map<String, ZmanAlertPreference>? zmanAlerts,
    Set<String>? enabledZmanim,
    bool? googleCalendarEnabled,
    bool? googleCalendarConnected,
    List<String>? googleCalendarSelectedIds,
    bool? googleCalendarSyncInProgress,
    String? googleCalendarSyncError,
    DateTime? googleCalendarLastSync,
    int? googleCalendarSyncPastDays,
    int? googleCalendarSyncFutureDays,
    bool clearGoogleCalendarSyncError = false,
  }) {
    return CalendarState(
      selectedJewishDate: selectedJewishDate ?? this.selectedJewishDate,
      selectedGregorianDate:
          selectedGregorianDate ?? this.selectedGregorianDate,
      selectedCity: selectedCity ?? this.selectedCity,
      dailyTimes: dailyTimes ?? this.dailyTimes,
      currentJewishDate: currentJewishDate ?? this.currentJewishDate,
      currentGregorianDate: currentGregorianDate ?? this.currentGregorianDate,
      todayGregorianDate: todayGregorianDate ?? this.todayGregorianDate,
      calendarType: calendarType ?? this.calendarType,
      calendarView: calendarView ?? this.calendarView,
      dayTransition: dayTransition ?? this.dayTransition,
      calendarClockTick: calendarClockTick ?? this.calendarClockTick,
      events: events ?? this.events,
      eventSearchQuery: eventSearchQuery ?? this.eventSearchQuery,
      searchInDescriptions: searchInDescriptions ?? this.searchInDescriptions,
      inIsrael: inIsrael ?? this.inIsrael,
      showAllEvents: showAllEvents ?? this.showAllEvents,
      calendarNotificationsEnabled:
          calendarNotificationsEnabled ?? this.calendarNotificationsEnabled,
      calendarNotificationTime:
          calendarNotificationTime ?? this.calendarNotificationTime,
      calendarNotificationSound:
          calendarNotificationSound ?? this.calendarNotificationSound,
      zmanAlerts: zmanAlerts ?? this.zmanAlerts,
      enabledZmanim: enabledZmanim ?? this.enabledZmanim,
      googleCalendarEnabled:
          googleCalendarEnabled ?? this.googleCalendarEnabled,
      googleCalendarConnected:
          googleCalendarConnected ?? this.googleCalendarConnected,
      googleCalendarSelectedIds:
          googleCalendarSelectedIds ?? this.googleCalendarSelectedIds,
      googleCalendarSyncInProgress:
          googleCalendarSyncInProgress ?? this.googleCalendarSyncInProgress,
      googleCalendarSyncError: clearGoogleCalendarSyncError
          ? null
          : (googleCalendarSyncError ?? this.googleCalendarSyncError),
      googleCalendarLastSync:
          googleCalendarLastSync ?? this.googleCalendarLastSync,
      googleCalendarSyncPastDays:
          googleCalendarSyncPastDays ?? this.googleCalendarSyncPastDays,
      googleCalendarSyncFutureDays:
          googleCalendarSyncFutureDays ?? this.googleCalendarSyncFutureDays,
    );
  }

  @override
  List<Object?> get props => [
    selectedJewishDate.getJewishYear(),
    selectedJewishDate.getJewishMonth(),
    selectedJewishDate.getJewishDayOfMonth(),

    selectedGregorianDate,
    selectedCity,
    dailyTimes,
    // events – ensure rebuild on changes
    events,

    eventSearchQuery,
    searchInDescriptions,

    // "פירקנו" גם את התאריך של תצוגת החודש
    currentJewishDate.getJewishYear(),
    currentJewishDate.getJewishMonth(),
    currentJewishDate.getJewishDayOfMonth(),

    currentGregorianDate,
    todayGregorianDate,
    calendarType,
    calendarView,
    dayTransition,
    calendarClockTick,
    inIsrael,
    showAllEvents,
    calendarNotificationsEnabled,
    calendarNotificationTime,
    calendarNotificationSound,
    zmanAlerts,
    enabledZmanim,
    googleCalendarEnabled,
    googleCalendarConnected,
    googleCalendarSelectedIds,
    googleCalendarSyncInProgress,
    googleCalendarSyncError,
    googleCalendarLastSync,
    googleCalendarSyncPastDays,
    googleCalendarSyncFutureDays,
  ];
}

/// Interface לטעינת אירועי plugin — מאפשר החלפה ב-mock בטסטים.
abstract class CalendarPluginSource {
  Future<List<CustomEvent>> loadAndMergePluginEvents(
    List<CustomEvent> existingEvents, {
    String? currentWorkspaceId,
    String? currentBookId,
  });
}

/// מימוש ברירת מחדל שמעביר ל-PluginCalendarAdapter האמיתי.
class _DefaultPluginSource implements CalendarPluginSource {
  const _DefaultPluginSource();

  @override
  Future<List<CustomEvent>> loadAndMergePluginEvents(
    List<CustomEvent> existingEvents, {
    String? currentWorkspaceId,
    String? currentBookId,
  }) => PluginCalendarAdapter().loadAndMergePluginEvents(
    existingEvents,
    currentWorkspaceId: currentWorkspaceId,
    currentBookId: currentBookId,
  );
}

// Calendar Cubit
class CalendarCubit extends Cubit<CalendarState> {
  static const String _primaryGoogleCalendarId = 'primary';
  static const int _zmanScheduleDaysAhead = 45;

  final SettingsRepository _settingsRepository;
  final NotificationService _notificationService;
  final GoogleCalendarService _googleCalendarService;
  final CalendarPluginSource _pluginCalendarAdapter;
  Timer? _todayRefreshTimer;
  int _pluginRefreshGeneration = 0;

  // Getter for accessing notification service from outside
  NotificationService get notificationService => _notificationService;

  CalendarCubit({
    SettingsRepository? settingsRepository,
    NotificationService? notificationService,
    GoogleCalendarService? googleCalendarService,
    CalendarPluginSource? pluginCalendarAdapter,
  }) : _settingsRepository = settingsRepository ?? SettingsRepository(),
       _notificationService = notificationService ?? NotificationService(),
       _googleCalendarService =
           googleCalendarService ?? GoogleCalendarService(),
       _pluginCalendarAdapter =
           pluginCalendarAdapter ?? const _DefaultPluginSource(),
       super(CalendarState.initial()) {
    _initializeCalendar(resetSelectedToToday: true);
  }

  Future<void> _initializeCalendar({bool resetSelectedToToday = false}) async {
    final settings = await _settingsRepository.loadSettings();
    if (isClosed) return;
    final calendarTypeString = settings['calendarType'] as String;
    final calendarType = _stringToCalendarType(calendarTypeString);
    final dayTransitionString = settings['calendarDayTransition'] as String;
    final dayTransition = calendarDayTransitionFromString(dayTransitionString);
    final selectedCity = settings['selectedCity'] as String;
    final today = resolveCalendarDayForTransition(
      now: DateTime.now(),
      city: selectedCity,
      transition: dayTransition,
    );
    final todayJewishDate = JewishDate.fromDateTime(today);
    final selectedGregorianDate = resetSelectedToToday
        ? today
        : state.selectedGregorianDate;
    final selectedJewishDate = resetSelectedToToday
        ? todayJewishDate
        : JewishDate.fromDateTime(selectedGregorianDate);
    final currentGregorianDate = resetSelectedToToday
        ? today
        : state.currentGregorianDate;
    final currentJewishDate = resetSelectedToToday
        ? todayJewishDate
        : JewishDate.fromDateTime(currentGregorianDate);
    final eventsJson = settings['calendarEvents'] as String;
    final bool inIsrael = _isCityInIsrael(selectedCity);
    final bool calendarNotificationsEnabled =
        settings['calendarNotificationsEnabled'] as bool;
    final int calendarNotificationTime =
        settings['calendarNotificationTime'] as int;
    final bool calendarNotificationSound =
        settings['calendarNotificationSound'] as bool;
    final String zmanAlertsJson = settings['calendarZmanAlerts'] as String;
    final String enabledZmanimJson =
        settings['calendarEnabledZmanim'] as String;
    final Set<String> enabledZmanim = _parseEnabledZmanim(enabledZmanimJson);
    final bool googleCalendarEnabled =
        settings['googleCalendarEnabled'] as bool;
    final String googleCalendarSelectedIdsStr =
        settings['googleCalendarSelectedIds'] as String;
    final List<String> googleCalendarSelectedIds = googleCalendarSelectedIdsStr
        .split(',')
        .where((s) => s.isNotEmpty)
        .toList();
    final int googleCalendarSyncPastDays =
        settings['googleCalendarSyncPastDays'] as int;
    final int googleCalendarSyncFutureDays =
        settings['googleCalendarSyncFutureDays'] as int;
    final int googleCalendarLastSyncRaw =
        settings['googleCalendarLastSync'] as int;

    final Map<String, ZmanAlertPreference> zmanAlerts =
        _parseZmanAlertPreferences(zmanAlertsJson);

    // טעינת אירועים מהאחסון. פרסור פר-פריט: אירוע פגום אחד לא מאבד
    // את כל האירועים שהמשתמש שמר.
    List<CustomEvent> events = [];
    try {
      final List<dynamic> eventsList = jsonDecode(eventsJson);
      for (final eventMap in eventsList) {
        try {
          events.add(CustomEvent.fromJson(eventMap));
        } catch (e) {
          debugPrint('[Calendar] skipping corrupt saved event: $e');
        }
      }
    } catch (e) {
      debugPrint('[Calendar] failed to load saved events: $e');
    }

    if (isClosed) return;

    // Add plugin published events via adapter
    events = await _pluginCalendarAdapter.loadAndMergePluginEvents(events);

    if (isClosed) return;

    emit(
      state.copyWith(
        calendarType: calendarType,
        dayTransition: dayTransition,
        selectedCity: selectedCity,
        selectedJewishDate: selectedJewishDate,
        selectedGregorianDate: selectedGregorianDate,
        currentJewishDate: currentJewishDate,
        currentGregorianDate: currentGregorianDate,
        todayGregorianDate: today,
        events: events,
        inIsrael: inIsrael,
        calendarNotificationsEnabled: calendarNotificationsEnabled,
        calendarNotificationTime: calendarNotificationTime,
        calendarNotificationSound: calendarNotificationSound,
        zmanAlerts: zmanAlerts,
        enabledZmanim: enabledZmanim,
        googleCalendarEnabled: googleCalendarEnabled,
        googleCalendarSelectedIds: googleCalendarSelectedIds,
        googleCalendarSyncPastDays: googleCalendarSyncPastDays,
        googleCalendarSyncFutureDays: googleCalendarSyncFutureDays,
        googleCalendarLastSync: googleCalendarLastSyncRaw > 0
            ? DateTime.fromMillisecondsSinceEpoch(googleCalendarLastSyncRaw)
            : null,
      ),
    );
    if (isClosed) return;
    _updateTimesForDate(selectedGregorianDate, selectedCity);
    await _rescheduleNotifications();
    if (isClosed) return;
    await _rescheduleZmanAlerts();
    if (isClosed) return;
    await _refreshGoogleConnectionStatus();
    if (isClosed) return;
    if (googleCalendarEnabled) {
      await syncGoogleCalendar(interactive: false);
    }
    _scheduleTodayRefresh();
  }

  /// מרענן אירועי plugin בזמן אמת.
  ///
  /// מסיר מה-state את כל האירועים שנוצרו על-ידי plugin
  /// (id בפורמט `pluginId:key`) ומוסיף מחדש את כל ה-records
  /// מה-DB לאחר upsert / remove.
  ///
  /// [currentWorkspaceId] / [currentBookId] — לסינון workspace/book scope.
  Future<void> refreshPluginEvents({
    String? currentWorkspaceId,
    String? currentBookId,
  }) async {
    // בולע קריאות ישנות: רק הקריאה האחרונה שמסיימת מורשית ל-emit.
    final generation = ++_pluginRefreshGeneration;

    final pluginEvents = await _pluginCalendarAdapter.loadAndMergePluginEvents(
      [],
      currentWorkspaceId: currentWorkspaceId,
      currentBookId: currentBookId,
    );

    if (isClosed || generation != _pluginRefreshGeneration) return;

    // קריאת אירועי המשתמש מה-state הנוכחי (אחרי ה-await, כדי לא לדרוס אירועים
    // שנטענו ב-_initializeCalendar בזמן שהמתנו לתשובת ה-DB)
    final userEvents = state.events.where((e) => !e.id.contains(':')).toList();
    emit(state.copyWith(events: [...userEvents, ...pluginEvents]));
  }

  /// מפענח את רשימת מזהי הזמנים המופעלים. מחרוזת ריקה/לא תקינה →
  /// ברירת המחדל מתוך רישום הזמנים.
  static Set<String> _parseEnabledZmanim(String jsonStr) {
    if (jsonStr.isEmpty) return zmanim_helpers.kDefaultEnabledZmanim;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! List) return zmanim_helpers.kDefaultEnabledZmanim;
      return decoded.whereType<String>().toSet();
    } catch (_) {
      return zmanim_helpers.kDefaultEnabledZmanim;
    }
  }

  /// מפעיל/מכבה הצגת זמן בלוח ושומר את הבחירה. כשמכבים זמן עם התראה
  /// פעילה — ההתראה נשמרת (כדי שתחזור אם הזמן יופעל שוב), אך הזמן לא
  /// יוצג עוד ככרטיס.
  Future<void> setZmanEnabled(String zmanId, bool enabled) async {
    final updated = Set<String>.from(state.enabledZmanim);
    if (enabled) {
      updated.add(zmanId);
    } else {
      updated.remove(zmanId);
    }
    emit(state.copyWith(enabledZmanim: updated));
    await _settingsRepository.updateCalendarEnabledZmanim(
      jsonEncode(updated.toList()),
    );
  }

  static Map<String, ZmanAlertPreference> _parseZmanAlertPreferences(
    String jsonStr,
  ) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return {};
      final result = <String, ZmanAlertPreference>{};
      decoded.forEach((key, value) {
        if (key is! String) return;
        final pref = ZmanAlertPreference.fromJson(value, fallbackName: key);
        if (pref != null) {
          result[key] = pref;
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  static int _zmanNotificationId(String timeId, DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final key = '$timeId|$y$m$d';
    return key.hashCode & 0x7fffffff;
  }

  static String _formatMinutesBefore(int minutes) {
    if (minutes <= 0) return 'עכשיו';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '$h שעות ו-$m דקות';
    if (h > 0) return '$h שעות';
    return '$m דקות';
  }

  Future<void> setZmanAlertPreference({
    required String timeId,
    required String displayName,
    required int minutesBefore,
  }) async {
    final notificationService = _notificationService;

    if (!notificationService.isInitialized) {
      await notificationService.init();
    }

    bool hasPermission = await notificationService.checkPermissions();
    if (!hasPermission) {
      if (Platform.isMacOS) {
        hasPermission = await notificationService.forceRequestPermissions();
      } else {
        hasPermission = await notificationService.requestPermissions();
      }
    }

    if (!hasPermission) {
      String message;

      if (Platform.isMacOS) {
        message = ToolsMessages.notificationsPermissionRequiredMacos;
      } else if (Platform.isIOS) {
        message = ToolsMessages.notificationsPermissionRequiredIos;
      } else {
        message = ToolsMessages.notificationsPermissionRequired;
      }

      UiSnack.showWarning(message, duration: const Duration(seconds: 10));
      return;
    }

    final updated = Map<String, ZmanAlertPreference>.from(state.zmanAlerts);
    updated[timeId] = ZmanAlertPreference(
      minutesBefore: minutesBefore,
      displayName: displayName,
    );
    emit(state.copyWith(zmanAlerts: updated));
    await _settingsRepository.updateCalendarZmanAlertsJson(
      jsonEncode(updated.map((k, v) => MapEntry(k, v.toJson()))),
    );

    await _rescheduleZmanAlerts();
    UiSnack.show(ToolsMessages.zmanAlertEnabled(displayName));
  }

  Future<void> cancelZmanAlertPreference({
    required String timeId,
  }) async {
    final existing = state.zmanAlerts[timeId];
    if (existing == null) return;

    final updated = Map<String, ZmanAlertPreference>.from(state.zmanAlerts);
    updated.remove(timeId);
    emit(state.copyWith(zmanAlerts: updated));
    await _settingsRepository.updateCalendarZmanAlertsJson(
      jsonEncode(updated.map((k, v) => MapEntry(k, v.toJson()))),
    );

    // Cancel scheduled notifications for this timeId in our rolling window.
    final notificationService = _notificationService;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (int i = 0; i <= _zmanScheduleDaysAhead; i++) {
      final d = today.add(Duration(days: i));
      final id = _zmanNotificationId(timeId, d);
      // cancelNotification עצמו async (platform channel) — מספיק כדי לא לחסום UI
      await notificationService.cancelNotification(id);
    }

    UiSnack.show(ToolsMessages.zmanAlertCancelled(existing.displayName));
  }

  Future<void> _rescheduleZmanAlerts() async {
    if (state.zmanAlerts.isEmpty) return;

    final notificationService = _notificationService;
    if (!notificationService.isInitialized) {
      return;
    }

    // Don't prompt here; only schedule if we already have permissions.
    final hasPermission = await notificationService.checkPermissions();
    if (!hasPermission) return;

    final cityData = _getCityData(state.selectedCity);
    final String timeZoneId;
    if (cityData == null) {
      debugPrint(
        'CalendarCubit: city data not found for "${state.selectedCity}", defaulting to Asia/Jerusalem timezone.',
      );
      UiSnack.showError(ToolsMessages.cityDataNotFound);
      timeZoneId = 'Asia/Jerusalem';
    } else {
      timeZoneId = cityData['timezone'] as String? ?? 'Asia/Jerusalem';
    }
    final location = tz.getLocation(timeZoneId);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final entry in state.zmanAlerts.entries) {
      final timeId = entry.key;
      final pref = entry.value;

      for (int i = 0; i <= _zmanScheduleDaysAhead; i++) {
        // yield לאירוע loop — מאפשר ל-UI לרנדר פריים בין כל חישוב
        await Future.delayed(Duration.zero);
        final d = today.add(Duration(days: i));
        final times = _calculateDailyTimes(d, state.selectedCity);
        final timeStr = times[timeId];

        final cancellationId = _zmanNotificationId(timeId, d);

        if (timeStr == null) {
          // Ensure no stale notification for days the zman doesn't exist.
          await notificationService.cancelNotification(cancellationId);
          continue;
        }

        // מחלצים שעה:דקה תוך התעלמות מעטיפת ה-LTR isolate (\u2066) ומסימן
        // השניות (`.`/`:`) שבסוף.
        final match = RegExp(
          '^\u2066?'
          r'(\d{1,2}):(\d{2})',
        ).firstMatch(timeStr);
        if (match == null) {
          await notificationService.cancelNotification(cancellationId);
          continue;
        }

        final h = int.parse(match.group(1)!);
        final m = int.parse(match.group(2)!);

        // Construct TZDateTime in the correct timezone
        final eventDt = tz.TZDateTime(location, d.year, d.month, d.day, h, m);

        await notificationService.cancelNotification(cancellationId);

        await notificationService.scheduleNotification(
          id: cancellationId,
          title: 'תזכורת: ${pref.displayName}',
          body:
              'בעוד ${_formatMinutesBefore(pref.minutesBefore)} ${pref.displayName} (${timeStr.replaceAll(RegExp('[\u2066\u2069]'), '').replaceFirst(RegExp(r'[.:]$'), '')})',
          eventDate: eventDt,
          reminderMinutes: pref.minutesBefore,
          soundEnabled: true,
        );
      }
    }
  }

  void _updateTimesForDate(DateTime date, String city) {
    final newTimes = _calculateDailyTimes(date, city);
    emit(state.copyWith(dailyTimes: newTimes));
  }

  void _scheduleTodayRefresh() {
    _todayRefreshTimer?.cancel();
    if (isClosed) return;

    final nextRefresh = nextCalendarTodayRefreshTime(
      now: DateTime.now(),
      city: state.selectedCity,
      transition: state.dayTransition,
    );
    final duration = nextRefresh.difference(DateTime.now());
    _todayRefreshTimer = Timer(
      duration.isNegative ? const Duration(seconds: 1) : duration,
      _refreshCalendarToday,
    );
  }

  void _refreshCalendarToday() {
    if (isClosed) return;

    final previousToday = state.todayGregorianDate;
    final today = resolveCalendarDayForTransition(
      now: DateTime.now(),
      city: state.selectedCity,
      transition: state.dayTransition,
    );
    final wasViewingToday = _isSameDateOnly(
      state.selectedGregorianDate,
      previousToday,
    );

    if (!_isSameDateOnly(today, previousToday)) {
      final jewishToday = JewishDate.fromDateTime(today);
      final newTimes = wasViewingToday
          ? _calculateDailyTimes(today, state.selectedCity)
          : state.dailyTimes;
      emit(
        state.copyWith(
          todayGregorianDate: today,
          selectedGregorianDate: wasViewingToday
              ? today
              : state.selectedGregorianDate,
          selectedJewishDate: wasViewingToday
              ? jewishToday
              : state.selectedJewishDate,
          currentGregorianDate: wasViewingToday
              ? today
              : state.currentGregorianDate,
          currentJewishDate: wasViewingToday
              ? jewishToday
              : state.currentJewishDate,
          dailyTimes: newTimes,
          calendarClockTick: state.calendarClockTick + 1,
        ),
      );
    } else {
      emit(
        state.copyWith(
          todayGregorianDate: today,
          calendarClockTick: state.calendarClockTick + 1,
        ),
      );
    }

    _scheduleTodayRefresh();
  }

  void selectDate(JewishDate jewishDate, DateTime gregorianDate) {
    final newTimes = _calculateDailyTimes(gregorianDate, state.selectedCity);
    // When in month view, selecting a cell should also update the month header anchors
    final bool updateMonthAnchors = state.calendarView == CalendarView.month;
    emit(
      state.copyWith(
        selectedJewishDate: jewishDate,
        selectedGregorianDate: gregorianDate,
        dailyTimes: newTimes,
        currentJewishDate: updateMonthAnchors
            ? jewishDate
            : state.currentJewishDate,
        currentGregorianDate: updateMonthAnchors
            ? gregorianDate
            : state.currentGregorianDate,
      ),
    );
  }

  Future<void> changeCity(String newCity) async {
    final bool inIsrael = _isCityInIsrael(newCity);
    final wasViewingToday = _isSameDateOnly(
      state.selectedGregorianDate,
      state.todayGregorianDate,
    );
    final today = resolveCalendarDayForTransition(
      now: DateTime.now(),
      city: newCity,
      transition: state.dayTransition,
    );
    final jewishToday = JewishDate.fromDateTime(today);
    final selectedDate = wasViewingToday ? today : state.selectedGregorianDate;
    final newTimes = _calculateDailyTimes(selectedDate, newCity);
    emit(
      state.copyWith(
        selectedCity: newCity,
        dailyTimes: newTimes,
        inIsrael: inIsrael,
        todayGregorianDate: today,
        selectedGregorianDate: wasViewingToday
            ? today
            : state.selectedGregorianDate,
        selectedJewishDate: wasViewingToday
            ? jewishToday
            : state.selectedJewishDate,
        currentGregorianDate: wasViewingToday
            ? today
            : state.currentGregorianDate,
        currentJewishDate: wasViewingToday
            ? jewishToday
            : state.currentJewishDate,
      ),
    );
    // שמור את הבחירה בהגדרות
    await _settingsRepository.updateSelectedCity(newCity);

    // Times shift with city, so reschedule zman alerts.
    await _rescheduleZmanAlerts();
    _scheduleTodayRefresh();
  }

  Future<void> changeCalendarType(CalendarType type) async {
    emit(state.copyWith(calendarType: type));
    // שמור את הבחירה בהגדרות
    await _settingsRepository.updateCalendarType(_calendarTypeToString(type));
  }

  Future<void> changeCalendarDayTransition(
    CalendarDayTransition transition,
  ) async {
    final wasViewingToday = _isSameDateOnly(
      state.selectedGregorianDate,
      state.todayGregorianDate,
    );
    final today = resolveCalendarDayForTransition(
      now: DateTime.now(),
      city: state.selectedCity,
      transition: transition,
    );
    final jewishToday = JewishDate.fromDateTime(today);
    final newTimes = wasViewingToday
        ? _calculateDailyTimes(today, state.selectedCity)
        : state.dailyTimes;
    emit(
      state.copyWith(
        dayTransition: transition,
        todayGregorianDate: today,
        selectedGregorianDate: wasViewingToday
            ? today
            : state.selectedGregorianDate,
        selectedJewishDate: wasViewingToday
            ? jewishToday
            : state.selectedJewishDate,
        currentGregorianDate: wasViewingToday
            ? today
            : state.currentGregorianDate,
        currentJewishDate: wasViewingToday
            ? jewishToday
            : state.currentJewishDate,
        dailyTimes: newTimes,
      ),
    );
    await _settingsRepository.updateCalendarDayTransition(
      calendarDayTransitionToString(transition),
    );
    _scheduleTodayRefresh();
  }

  /// טעינה מחדש של הגדרות מהאחסון
  Future<void> reloadSettings() async {
    await _initializeCalendar();
  }

  @override
  Future<void> close() {
    _todayRefreshTimer?.cancel();
    return super.close();
  }

  void _previousMonth() {
    if (state.calendarType == CalendarType.gregorian) {
      final current = state.currentGregorianDate;
      final newDate = current.month == 1
          ? DateTime(current.year - 1, 12, 1)
          : DateTime(current.year, current.month - 1, 1);
      final newTimes = _calculateDailyTimes(newDate, state.selectedCity);
      emit(
        state.copyWith(
          currentGregorianDate: newDate,
          selectedGregorianDate: newDate,
          selectedJewishDate: JewishDate.fromDateTime(newDate),
          currentJewishDate: JewishDate.fromDateTime(newDate),
          dailyTimes: newTimes,
        ),
      );
    } else {
      // Hebrew or combined calendar navigation based on Jewish month numbering (Nissan=1 ... Adar=12 / Adar II=13)
      final current = state.currentJewishDate;
      final newJewishDate = _computePreviousJewishMonth(current);
      final newGregorian = newJewishDate.getGregorianCalendar();
      final newTimes = _calculateDailyTimes(newGregorian, state.selectedCity);
      emit(
        state.copyWith(
          currentJewishDate: newJewishDate,
          currentGregorianDate:
              newGregorian, // keep gregorian in sync for headers
          selectedGregorianDate: newGregorian,
          selectedJewishDate: newJewishDate,
          dailyTimes: newTimes,
        ),
      );
    }
  }

  void _nextMonth() {
    if (state.calendarType == CalendarType.gregorian) {
      final current = state.currentGregorianDate;
      final newDate = current.month == 12
          ? DateTime(current.year + 1, 1, 1)
          : DateTime(current.year, current.month + 1, 1);
      final newTimes = _calculateDailyTimes(newDate, state.selectedCity);
      emit(
        state.copyWith(
          currentGregorianDate: newDate,
          selectedGregorianDate: newDate,
          selectedJewishDate: JewishDate.fromDateTime(newDate),
          currentJewishDate: JewishDate.fromDateTime(newDate),
          dailyTimes: newTimes,
        ),
      );
    } else {
      // Hebrew or combined
      final current = state.currentJewishDate;
      final newJewishDate = _computeNextJewishMonth(current);
      final newGregorian = newJewishDate.getGregorianCalendar();
      final newTimes = _calculateDailyTimes(newGregorian, state.selectedCity);
      emit(
        state.copyWith(
          currentJewishDate: newJewishDate,
          currentGregorianDate: newGregorian,
          selectedGregorianDate: newGregorian,
          selectedJewishDate: newJewishDate,
          dailyTimes: newTimes,
        ),
      );
    }
  }

  void _previousWeek() {
    final newDate = state.selectedGregorianDate.subtract(Duration(days: 7));
    final newJewishDate = JewishDate.fromDateTime(newDate);
    final newTimes = _calculateDailyTimes(newDate, state.selectedCity);
    emit(
      state.copyWith(
        selectedGregorianDate: newDate,
        selectedJewishDate: newJewishDate,
        dailyTimes: newTimes,
      ),
    );
  }

  void _nextWeek() {
    final newDate = state.selectedGregorianDate.add(Duration(days: 7));
    final newJewishDate = JewishDate.fromDateTime(newDate);
    final newTimes = _calculateDailyTimes(newDate, state.selectedCity);
    emit(
      state.copyWith(
        selectedGregorianDate: newDate,
        selectedJewishDate: newJewishDate,
        dailyTimes: newTimes,
      ),
    );
  }

  void _previousDay() {
    final newDate = state.selectedGregorianDate.subtract(Duration(days: 1));
    final newJewishDate = JewishDate.fromDateTime(newDate);
    final newTimes = _calculateDailyTimes(newDate, state.selectedCity);
    emit(
      state.copyWith(
        selectedGregorianDate: newDate,
        selectedJewishDate: newJewishDate,
        dailyTimes: newTimes,
      ),
    );
  }

  void _nextDay() {
    final newDate = state.selectedGregorianDate.add(Duration(days: 1));
    final newJewishDate = JewishDate.fromDateTime(newDate);
    final newTimes = _calculateDailyTimes(newDate, state.selectedCity);
    emit(
      state.copyWith(
        selectedGregorianDate: newDate,
        selectedJewishDate: newJewishDate,
        dailyTimes: newTimes,
      ),
    );
  }

  void changeCalendarView(CalendarView view) {
    emit(state.copyWith(calendarView: view));
  }

  void previous() {
    switch (state.calendarView) {
      case CalendarView.month:
        _previousMonth();
        break;
      case CalendarView.week:
        _previousWeek();
        break;
      case CalendarView.day:
        _previousDay();
        break;
    }
  }

  void next() {
    switch (state.calendarView) {
      case CalendarView.month:
        _nextMonth();
        break;
      case CalendarView.week:
        _nextWeek();
        break;
      case CalendarView.day:
        _nextDay();
        break;
    }
  }

  void jumpToToday() {
    final today = resolveCalendarDayForTransition(
      now: DateTime.now(),
      city: state.selectedCity,
      transition: state.dayTransition,
    );
    final jewishToday = JewishDate.fromDateTime(today);
    final newTimes = _calculateDailyTimes(today, state.selectedCity);

    emit(
      state.copyWith(
        selectedJewishDate: jewishToday,
        selectedGregorianDate: today,
        currentJewishDate: jewishToday,
        currentGregorianDate: today,
        todayGregorianDate: today,
        dailyTimes: newTimes,
      ),
    );
  }

  void jumpToDate(DateTime date) {
    final jewishDate = JewishDate.fromDateTime(date);
    final newTimes = _calculateDailyTimes(date, state.selectedCity);

    emit(
      state.copyWith(
        selectedJewishDate: jewishDate,
        selectedGregorianDate: date,
        currentJewishDate: jewishDate,
        currentGregorianDate: date,
        dailyTimes: newTimes,
      ),
    );
  }

  /// פונקציה פנימית לניווט לפי משך זמן
  void _navigateByDuration(Duration duration) {
    final newDate = state.selectedGregorianDate.add(duration);
    final newJewishDate = JewishDate.fromDateTime(newDate);
    final newTimes = _calculateDailyTimes(newDate, state.selectedCity);

    emit(
      state.copyWith(
        selectedGregorianDate: newDate,
        selectedJewishDate: newJewishDate,
        dailyTimes: newTimes,
        currentGregorianDate: newDate,
        currentJewishDate: newJewishDate,
      ),
    );
  }

  /// ניווט ליום הבא (לשימוש עם מקשי חיצים)
  void navigateToNextDay() => _navigateByDuration(const Duration(days: 1));

  /// ניווט ליום הקודם (לשימוש עם מקשי חיצים)
  void navigateToPreviousDay() => _navigateByDuration(const Duration(days: -1));

  /// ניווט לשבוע הבא (לשימוש עם מקשי חיצים)
  void navigateToNextWeek() => _navigateByDuration(const Duration(days: 7));

  /// ניווט לשבוע הקודם (לשימוש עם מקשי חיצים)
  void navigateToPreviousWeek() =>
      _navigateByDuration(const Duration(days: -7));

  void setEventSearchQuery(String query) {
    emit(state.copyWith(eventSearchQuery: query));
  }

  void toggleSearchInDescriptions(bool value) {
    emit(state.copyWith(searchInDescriptions: value));
  }

  void toggleShowAllEvents(bool value) {
    emit(state.copyWith(showAllEvents: value));
  }

  Map<String, String> shortTimesFor(DateTime date) {
    final full = _calculateDailyTimes(date, state.selectedCity);
    return {
      if (full['sunrise'] != null) 'sunrise': full['sunrise']!,
      if (full['sunset'] != null) 'sunset': full['sunset']!,
    };
  }

  // --- Google Calendar Integration ---

  Future<void> setGoogleCalendarEnabled(bool enabled) async {
    emit(state.copyWith(googleCalendarEnabled: enabled));
    await _settingsRepository.updateGoogleCalendarEnabled(enabled);

    if (!enabled) {
      await _googleCalendarService.signOut();
      emit(
        state.copyWith(
          googleCalendarConnected: false,
          clearGoogleCalendarSyncError: true,
        ),
      );
      return;
    }

    await _refreshGoogleConnectionStatus();
    if (state.googleCalendarConnected) {
      await syncGoogleCalendar(interactive: false);
    }
  }

  Future<void> updateGoogleCalendarSelectedIds(List<String> calendarIds) async {
    emit(state.copyWith(googleCalendarSelectedIds: calendarIds));
    await _settingsRepository.updateGoogleCalendarSelectedIds(calendarIds);
  }

  Future<List<GoogleCalendarInfo>> getAvailableCalendars() async {
    final apiClient = await _googleCalendarService.getApiClient(
      interactive: false,
    );
    if (apiClient == null) return [];

    try {
      final calendarList = await apiClient.api.calendarList.list();
      final calendars = <GoogleCalendarInfo>[];

      for (final item in calendarList.items ?? []) {
        if (item.id != null && item.summary != null) {
          calendars.add(
            GoogleCalendarInfo(
              id: item.id!,
              name: item.summary!,
              isPrimary: item.primary ?? false,
            ),
          );
        }
      }

      return calendars;
    } catch (e) {
      // Failed to fetch calendars
      return [];
    } finally {
      apiClient.close();
    }
  }

  Future<void> updateGoogleCalendarSyncPastDays(int days) async {
    emit(state.copyWith(googleCalendarSyncPastDays: days));
    await _settingsRepository.updateGoogleCalendarSyncPastDays(days);
  }

  Future<void> updateGoogleCalendarSyncFutureDays(int days) async {
    emit(state.copyWith(googleCalendarSyncFutureDays: days));
    await _settingsRepository.updateGoogleCalendarSyncFutureDays(days);
  }

  Future<bool> connectGoogleCalendar() async {
    emit(state.copyWith(googleCalendarSyncInProgress: true));

    try {
      final apiClient = await _googleCalendarService.getApiClient(
        interactive: true,
      );
      if (apiClient == null) {
        emit(
          state.copyWith(
            googleCalendarSyncInProgress: false,
            googleCalendarConnected: false,
            googleCalendarSyncError: 'לא הצלחנו להתחבר לחשבון Google.',
          ),
        );
        return false;
      }

      apiClient.close();
      emit(
        state.copyWith(
          googleCalendarConnected: true,
          googleCalendarSyncInProgress: false,
          clearGoogleCalendarSyncError: true,
        ),
      );
      await syncGoogleCalendar(interactive: false);
      return true;
    } catch (e) {
      final errorMessage = _formatGoogleCalendarError(e);

      emit(
        state.copyWith(
          googleCalendarSyncInProgress: false,
          googleCalendarConnected: false,
          googleCalendarSyncError: errorMessage,
        ),
      );
      return false;
    }
  }

  String _formatGoogleCalendarError(dynamic error) {
    String errorMessage = error.toString();

    // Remove "Exception: " prefix if present
    if (errorMessage.startsWith('Exception: ')) {
      errorMessage = errorMessage.substring('Exception: '.length);
    }

    return errorMessage;
  }

  Future<void> disconnectGoogleCalendar() async {
    await _googleCalendarService.signOut();
    emit(
      state.copyWith(
        googleCalendarConnected: false,
        clearGoogleCalendarSyncError: true,
      ),
    );
  }

  Future<void> syncGoogleCalendar({required bool interactive}) async {
    if (!state.googleCalendarEnabled) return;

    emit(
      state.copyWith(
        googleCalendarSyncInProgress: true,
        clearGoogleCalendarSyncError: true,
      ),
    );

    try {
      final apiClient = await _googleCalendarService.getApiClient(
        interactive: interactive,
      );
      if (apiClient == null) {
        emit(
          state.copyWith(
            googleCalendarSyncInProgress: false,
            googleCalendarConnected: false,
            googleCalendarSyncError: 'לא הצלחנו להתחבר לחשבון Google.',
          ),
        );
        return;
      }

      try {
        // Calculate date range for sync
        final now = DateTime.now();
        final timeMin = now.subtract(
          Duration(days: state.googleCalendarSyncPastDays),
        );
        final timeMax = now.add(
          Duration(days: state.googleCalendarSyncFutureDays),
        );

        // Fetch events from all selected calendars with pagination
        List<cal.Event> allGoogleEvents = [];
        for (final calendarId in state.googleCalendarSelectedIds) {
          try {
            String? pageToken;
            do {
              final result = await apiClient.api.events.list(
                calendarId,
                singleEvents: true,
                orderBy: 'startTime',
                timeMin: timeMin.toUtc(),
                timeMax: timeMax.toUtc(),
                maxResults: 2500, // Google's max per request
                pageToken: pageToken,
              );
              allGoogleEvents.addAll(result.items ?? []);
              pageToken = result.nextPageToken;
            } while (pageToken != null);
          } catch (e) {
            // Continue with other calendars if one fails
            debugPrint('Failed to sync calendar $calendarId: $e');
          }
        }

        final merged = mergeGoogleEvents(state.events, allGoogleEvents);
        final syncTime = DateTime.now();
        emit(
          state.copyWith(
            events: merged,
            googleCalendarConnected: true,
            googleCalendarSyncInProgress: false,
            googleCalendarLastSync: syncTime,
          ),
        );

        await _settingsRepository.updateGoogleCalendarLastSync(
          syncTime.millisecondsSinceEpoch,
        );
        await _saveEventsToStorage(merged);
      } catch (e) {
        emit(
          state.copyWith(
            googleCalendarSyncInProgress: false,
            googleCalendarSyncError: 'שגיאה בסנכרון עם Google Calendar: $e',
          ),
        );
      } finally {
        apiClient.close();
      }
    } catch (e) {
      final errorMessage = _formatGoogleCalendarError(e);

      emit(
        state.copyWith(
          googleCalendarSyncInProgress: false,
          googleCalendarConnected: false,
          googleCalendarSyncError: errorMessage,
        ),
      );
    }
  }

  Future<void> _refreshGoogleConnectionStatus() async {
    if (!state.googleCalendarEnabled) {
      emit(state.copyWith(googleCalendarConnected: false));
      return;
    }

    final signedIn = await _googleCalendarService.isSignedIn();
    emit(state.copyWith(googleCalendarConnected: signedIn));
  }

  Future<String?> _upsertGoogleEvent(CustomEvent event) async {
    if (!state.googleCalendarEnabled) return null;

    final apiClient = await _googleCalendarService.getApiClient(
      interactive: false,
    );
    if (apiClient == null) return null;

    try {
      final timeZoneId = _resolveTimeZone();
      final googleEvent = toGoogleEvent(event, timeZoneId);

      if (event.googleEventId == null || event.googleEventId!.isEmpty) {
        final created = await apiClient.api.events.insert(
          googleEvent,
          _primaryGoogleCalendarId,
        );
        return created.id;
      } else {
        final updated = await apiClient.api.events.update(
          googleEvent,
          _primaryGoogleCalendarId,
          event.googleEventId!,
        );
        return updated.id ?? event.googleEventId;
      }
    } catch (e) {
      debugPrint('Failed to upsert Google event: $e');
      // Return null to indicate failure, but don't crash the app
      return null;
    } finally {
      apiClient.close();
    }
  }

  Future<void> _deleteGoogleEvent(CustomEvent event) async {
    if (event.googleEventId == null || event.googleEventId!.isEmpty) return;

    final apiClient = await _googleCalendarService.getApiClient(
      interactive: false,
    );
    if (apiClient == null) return;

    try {
      await apiClient.api.events.delete(
        _primaryGoogleCalendarId,
        event.googleEventId!,
      );
    } catch (e) {
      debugPrint('Failed to delete Google event: $e');
      // Ignore delete failures to avoid blocking local delete
    } finally {
      apiClient.close();
    }
  }

  String _resolveTimeZone() {
    final cityData = _getCityData(state.selectedCity);
    if (cityData == null) return 'Asia/Jerusalem';
    return cityData['timezone'] as String? ?? 'Asia/Jerusalem';
  }

  void _replaceEventWithGoogleId(String eventId, String googleEventId) {
    final events = List<CustomEvent>.from(state.events);
    final index = events.indexWhere((e) => e.id == eventId);
    if (index == -1) return;
    events[index] = events[index].copyWith(googleEventId: googleEventId);
    emit(state.copyWith(events: events));
    _saveEventsToStorage(events);
  }

  @visibleForTesting
  List<CustomEvent> mergeGoogleEvents(
    List<CustomEvent> existing,
    List<cal.Event> googleEvents,
  ) {
    final updated = List<CustomEvent>.from(existing);
    final byGoogleId = <String, int>{};
    final byLocalId = <String, int>{};

    for (int i = 0; i < updated.length; i++) {
      final e = updated[i];
      byLocalId[e.id] = i;
      if (e.googleEventId != null && e.googleEventId!.isNotEmpty) {
        byGoogleId[e.googleEventId!] = i;
      }
    }

    for (final gEvent in googleEvents) {
      if (gEvent.status == 'cancelled') continue;

      final mapped = fromGoogleEvent(gEvent);
      if (mapped == null) continue;

      final otzariaId = gEvent.extendedProperties?.private?['otzaria_event_id'];
      final googleId = gEvent.id ?? '';

      if (googleId.isNotEmpty && byGoogleId.containsKey(googleId)) {
        final index = byGoogleId[googleId]!;
        updated[index] = updated[index].copyWith(
          title: mapped.title,
          description: mapped.description,
          baseGregorianDate: mapped.baseGregorianDate,
          baseJewishYear: mapped.baseJewishYear,
          baseJewishMonth: mapped.baseJewishMonth,
          baseJewishDay: mapped.baseJewishDay,
          endGregorianDate: () => mapped.endGregorianDate,
        );
        continue;
      }

      if (otzariaId != null && byLocalId.containsKey(otzariaId)) {
        final index = byLocalId[otzariaId]!;
        updated[index] = updated[index].copyWith(
          title: mapped.title,
          description: mapped.description,
          baseGregorianDate: mapped.baseGregorianDate,
          baseJewishYear: mapped.baseJewishYear,
          baseJewishMonth: mapped.baseJewishMonth,
          baseJewishDay: mapped.baseJewishDay,
          googleEventId: googleId.isEmpty ? null : googleId,
          endGregorianDate: () => mapped.endGregorianDate,
        );
        continue;
      }

      updated.add(mapped);
      if (googleId.isNotEmpty) {
        byGoogleId[googleId] = updated.length - 1;
      }
    }

    return updated;
  }

  @visibleForTesting
  CustomEvent? fromGoogleEvent(cal.Event gEvent) {
    final start = gEvent.start?.dateTime ?? gEvent.start?.date;
    if (start == null) return null;

    final date = DateTime(start.year, start.month, start.day);
    final jewishDate = JewishDate.fromDateTime(date);
    final otzariaId = gEvent.extendedProperties?.private?['otzaria_event_id'];

    // באירוע יום-שלם ה-end של גוגל בלעדי (day after) — מחסירים יום להצגת היום האחרון בפועל
    DateTime? endDate;
    final rawEnd = gEvent.end?.dateTime ?? gEvent.end?.date;
    if (rawEnd != null) {
      final isAllDay = gEvent.end?.date != null && gEvent.end?.dateTime == null;
      // end עם שעה שנופל בדיוק בחצות = סוף היום הקודם, לא יום נוסף
      final endsAtMidnight =
          !isAllDay &&
          rawEnd.hour == 0 &&
          rawEnd.minute == 0 &&
          rawEnd.second == 0;
      // חשבון קלנדרי (לא Duration) — ביום מעבר שעון subtract של 24ש מקצר יום
      final inclusiveEnd = (isAllDay || endsAtMidnight)
          ? DateTime(rawEnd.year, rawEnd.month, rawEnd.day - 1)
          : DateTime(rawEnd.year, rawEnd.month, rawEnd.day);
      if (inclusiveEnd.isAfter(date)) {
        endDate = inclusiveEnd;
      }
    }

    // Parse recurrence from Google event
    RecurrenceType recurrenceType = RecurrenceType.none;

    if (gEvent.recurrence != null && gEvent.recurrence!.isNotEmpty) {
      final rrule = gEvent.recurrence!.first;

      if (rrule.contains('FREQ=WEEKLY')) {
        recurrenceType = RecurrenceType.weekly;
      } else if (rrule.contains('FREQ=MONTHLY')) {
        // Check for Hebrew monthly marker
        if (rrule.contains('X-OTZARIA-TYPE=otzaria_hebrew_monthly')) {
          recurrenceType = RecurrenceType.monthlyHebrew;
        } else {
          recurrenceType = RecurrenceType.monthlyGregorian;
        }
      } else if (rrule.contains('FREQ=YEARLY')) {
        // Check for Hebrew yearly marker
        if (rrule.contains('X-OTZARIA-TYPE=otzaria_hebrew_yearly')) {
          recurrenceType = RecurrenceType.annualHebrew;
        } else {
          recurrenceType = RecurrenceType.annualGregorian;
        }
      }
    }

    return CustomEvent(
      id: otzariaId ?? gEvent.id ?? _generateUniqueId(),
      title: gEvent.summary ?? 'אירוע ללא כותרת',
      description: gEvent.description ?? '',
      createdAt: gEvent.created ?? DateTime.now(),
      baseGregorianDate: DateTime(date.year, date.month, date.day),
      baseJewishYear: jewishDate.getJewishYear(),
      baseJewishMonth: jewishDate.getJewishMonth(),
      baseJewishDay: jewishDate.getJewishDayOfMonth(),
      recurrenceType: recurrenceType,
      recurringYears: null, // Not used in current implementation
      googleEventId: gEvent.id,
      endGregorianDate: endDate,
    );
  }

  String _generateUniqueId() {
    // Generate a more reliable unique ID
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(0x7FFFFFFF);
    return 'otzaria_${timestamp}_$random';
  }

  @visibleForTesting
  cal.Event toGoogleEvent(CustomEvent event, String timeZoneId) {
    final baseDate = event.baseGregorianDate;
    final startDate = DateTime(baseDate.year, baseDate.month, baseDate.day);
    // גוגל מצפה ל-end בלעדי (day after) באירוע יום-שלם — מוסיפים יום מעבר ליום האחרון בפועל
    final lastDay = event.endGregorianDate != null
        ? DateTime(
            event.endGregorianDate!.year,
            event.endGregorianDate!.month,
            event.endGregorianDate!.day,
          )
        : startDate;
    // חשבון קלנדרי (לא Duration) — ביום מעבר שעון add של 24ש מאריך יום
    final endDate = DateTime(lastDay.year, lastDay.month, lastDay.day + 1);

    final extendedProps = {
      'otzaria_event_id': event.id,
      'otzaria_recurrence_type': event.recurrenceType.index.toString(),
    };

    // Store recurring years if set
    if (event.recurringYears != null) {
      extendedProps['recurring_years'] = event.recurringYears.toString();
    }

    final googleEvent = cal.Event()
      ..summary = event.title
      ..description = event.description
      ..start = (cal.EventDateTime()
        ..date = startDate
        ..timeZone = timeZoneId)
      ..end = (cal.EventDateTime()
        ..date = endDate
        ..timeZone = timeZoneId)
      ..extendedProperties = (cal.EventExtendedProperties()
        ..private = extendedProps);

    final recurrence = _googleRecurrenceRule(event);
    if (recurrence != null) {
      googleEvent.recurrence = [recurrence];
    }

    return googleEvent;
  }

  String? _googleRecurrenceRule(CustomEvent event) {
    String? freq;
    String? marker; // Marker to identify Hebrew recurrences

    switch (event.recurrenceType) {
      case RecurrenceType.weekly:
        freq = 'WEEKLY';
        break;
      case RecurrenceType.monthlyGregorian:
        freq = 'MONTHLY';
        break;
      case RecurrenceType.monthlyHebrew:
        // Store as monthly with a marker in extended properties
        freq = 'MONTHLY';
        marker = 'otzaria_hebrew_monthly';
        break;
      case RecurrenceType.annualGregorian:
        freq = 'YEARLY';
        break;
      case RecurrenceType.annualHebrew:
        // Store as yearly with a marker in extended properties
        freq = 'YEARLY';
        marker = 'otzaria_hebrew_yearly';
        break;
      case RecurrenceType.none:
        return null;
    }

    final buffer = StringBuffer('RRULE:FREQ=$freq');

    // Add marker for Hebrew recurrences as a comment
    if (marker != null) {
      buffer.write(';X-OTZARIA-TYPE=$marker');
    }

    if (event.recurringYears != null && event.recurringYears! > 0) {
      final until = DateTime(
        event.baseGregorianDate.year + event.recurringYears!,
        event.baseGregorianDate.month,
        event.baseGregorianDate.day,
        23,
        59,
        59,
      ).toUtc();
      buffer.write(';UNTIL=${_formatRRuleUntil(until)}');
    }

    return buffer.toString();
  }

  String _formatRRuleUntil(DateTime dateUtc) {
    final y = dateUtc.year.toString().padLeft(4, '0');
    final m = dateUtc.month.toString().padLeft(2, '0');
    final d = dateUtc.day.toString().padLeft(2, '0');
    final h = dateUtc.hour.toString().padLeft(2, '0');
    final min = dateUtc.minute.toString().padLeft(2, '0');
    final s = dateUtc.second.toString().padLeft(2, '0');
    return '$y$m${d}T$h$min${s}Z';
  }

  // --- ניהול אירועים ---

  Future<void> addEvent({
    required String title,
    String? description,
    required DateTime baseGregorianDate,
    required RecurrenceType recurrenceType,
    int? recurringYears,
    TimeOfDay? eventTime,
    DateTime? endGregorianDate,
    int? colorIndex,
    int? notificationMinutes,
  }) async {
    final baseJewish = JewishDate.fromDateTime(baseGregorianDate);
    final newEvent = CustomEvent(
      id: _generateUniqueId(), // יצירת ID ייחודי
      title: title,
      description: description ?? '',
      createdAt: DateTime.now(),
      baseGregorianDate: DateTime(
        baseGregorianDate.year,
        baseGregorianDate.month,
        baseGregorianDate.day,
      ),
      baseJewishYear: baseJewish.getJewishYear(),
      baseJewishMonth: baseJewish.getJewishMonth(),
      baseJewishDay: baseJewish.getJewishDayOfMonth(),
      recurrenceType: recurrenceType,
      recurringYears: recurringYears,
      eventTime: eventTime,
      endGregorianDate: endGregorianDate != null
          ? DateTime(
              endGregorianDate.year,
              endGregorianDate.month,
              endGregorianDate.day,
            )
          : null,
      colorIndex: colorIndex,
      notificationMinutes: notificationMinutes,
    );
    final updated = List<CustomEvent>.from(state.events)..add(newEvent);
    emit(state.copyWith(events: updated));
    _saveEventsToStorage(updated);

    if (state.googleCalendarEnabled) {
      final googleId = await _upsertGoogleEvent(newEvent);
      if (googleId != null) {
        _replaceEventWithGoogleId(newEvent.id, googleId);
      }
    }
  }

  Future<void> updateEvent(CustomEvent updatedEvent) async {
    final events = List<CustomEvent>.from(state.events);
    final index = events.indexWhere((e) => e.id == updatedEvent.id);
    if (index != -1) {
      events[index] = updatedEvent;
      emit(state.copyWith(events: events));
      _saveEventsToStorage(events);

      if (state.googleCalendarEnabled) {
        final googleId = await _upsertGoogleEvent(updatedEvent);
        if (googleId != null && googleId != updatedEvent.googleEventId) {
          _replaceEventWithGoogleId(updatedEvent.id, googleId);
        }
      }
    }
  }

  Future<void> deleteEvent(String eventId) async {
    CustomEvent? existing;
    for (final e in state.events) {
      if (e.id == eventId) {
        existing = e;
        break;
      }
    }
    final events = List<CustomEvent>.from(state.events)
      ..removeWhere((e) => e.id == eventId);
    emit(state.copyWith(events: events));
    _saveEventsToStorage(events);

    if (state.googleCalendarEnabled && existing != null) {
      await _deleteGoogleEvent(existing);
    }
  }

  List<CustomEvent> eventsForDate(DateTime date) {
    final jd = JewishDate.fromDateTime(date);
    final gY = date.year, gM = date.month, gD = date.day;
    final hY = jd.getJewishYear(),
        hM = jd.getJewishMonth(),
        hD = jd.getJewishDayOfMonth();
    final gWeekday = date.weekday;

    return state.events.where((e) {
      if (e.recurrenceType != RecurrenceType.none) {
        // בדוק אם האירוע החוזר עדיין בתוקף
        if (e.recurringYears != null && e.recurringYears! > 0) {
          bool expired = false;
          if (e.recurrenceType == RecurrenceType.annualHebrew ||
              e.recurrenceType == RecurrenceType.monthlyHebrew) {
            if (hY >= e.baseJewishYear + e.recurringYears!) {
              expired = true;
            }
          } else {
            // Gregorian based (Weekly, MonthlyGregorian, AnnualGregorian)
            if (gY >= e.baseGregorianDate.year + e.recurringYears!) {
              expired = true;
            }
          }
          if (expired) return false;
        }

        // בדיקת התאמה לפי סוג החזרה
        switch (e.recurrenceType) {
          case RecurrenceType.weekly:
            return e.baseGregorianDate.weekday == gWeekday;
          case RecurrenceType.monthlyHebrew:
            return e.baseJewishDay == hD;
          case RecurrenceType.monthlyGregorian:
            return e.baseGregorianDate.day == gD;
          case RecurrenceType.annualHebrew:
            return e.baseJewishMonth == hM && e.baseJewishDay == hD;
          case RecurrenceType.annualGregorian:
            return e.baseGregorianDate.month == gM &&
                e.baseGregorianDate.day == gD;
          case RecurrenceType.none:
            return false;
        }
      } else {
        // אירוע חד-פעמי — מוצג בכל יום שבטווח [התחלה, סיום]
        final start = DateTime(
          e.baseGregorianDate.year,
          e.baseGregorianDate.month,
          e.baseGregorianDate.day,
        );
        final end = e.endGregorianDate != null
            ? DateTime(
                e.endGregorianDate!.year,
                e.endGregorianDate!.month,
                e.endGregorianDate!.day,
              )
            : start;
        final current = DateTime(gY, gM, gD);
        return !current.isBefore(start) && !current.isAfter(end);
      }
    }).toList()..sort((a, b) => a.title.compareTo(b.title));
  }

  List<CustomEvent> getFilteredEvents(String query) {
    if (query.isEmpty) {
      return [];
    }
    return state.events
        .where(
          (e) =>
              e.title.contains(query) ||
              (state.searchInDescriptions && e.description.contains(query)),
        )
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  // שמירת אירועים לאחסון קבוע
  Future<void> _saveEventsToStorage(List<CustomEvent> events) async {
    try {
      final eventsJson = jsonEncode(events.map((e) => e.toJson()).toList());
      await _settingsRepository.updateCalendarEvents(eventsJson);
      await _rescheduleNotifications();
    } catch (e) {
      // במקרה של שגיאה, נדפיס הודעה לקונסול
      debugPrint('שגיאה בשמירת אירועים: $e');
    }
  }

  // --- Notification Settings ---
  Future<void> changeCalendarNotificationsEnabled(bool enabled) async {
    if (enabled) {
      // בקש הרשאות לפני הפעלת התראות
      final notificationService = _notificationService;
      if (!notificationService.isInitialized) {
        await notificationService.init();
      }
      // בדוק תחילה אם ההרשאות כבר ניתנו
      bool hasPermission = await notificationService.checkPermissions();

      // אם אין הרשאות, בקש אותן
      if (!hasPermission) {
        hasPermission = await notificationService.requestPermissions();
      }

      // אם אין הרשאה, אל תפעיל את ההתראות והצג הודעה למשתמש
      if (!hasPermission) {
        emit(state.copyWith(calendarNotificationsEnabled: false));
        await _settingsRepository.updateCalendarNotificationsEnabled(false);

        // הצג הודעת שגיאה למשתמש עם הוראות מפורטות
        UiSnack.showWarning(
          ToolsMessages.notificationsPermissionRequired,
          duration: const Duration(seconds: 8),
        );
        return;
      }
    }

    emit(state.copyWith(calendarNotificationsEnabled: enabled));
    await _settingsRepository.updateCalendarNotificationsEnabled(enabled);
    // Reschedule only if enabling/disabling notifications
    await _rescheduleNotifications();
  }

  Future<void> changeCalendarNotificationTime(int time) async {
    final oldTime = state.calendarNotificationTime;
    emit(state.copyWith(calendarNotificationTime: time));
    await _settingsRepository.updateCalendarNotificationTime(time);
    // Reschedule only if time actually changed and notifications are enabled
    if (oldTime != time && state.calendarNotificationsEnabled) {
      await _rescheduleNotifications();
    }
  }

  Future<void> changeCalendarNotificationSound(bool enabled) async {
    emit(state.copyWith(calendarNotificationSound: enabled));
    await _settingsRepository.updateCalendarNotificationSound(enabled);
    // No need to reschedule for sound changes - it only affects new notifications
  }

  Future<void> changeCalendarNotificationMode(
    CalendarNotificationMode mode,
  ) async {
    switch (mode) {
      case CalendarNotificationMode.sound:
        await changeCalendarNotificationsEnabled(true);
        if (state.calendarNotificationsEnabled) {
          await changeCalendarNotificationSound(true);
        }
      case CalendarNotificationMode.silent:
        await changeCalendarNotificationsEnabled(true);
        if (state.calendarNotificationsEnabled) {
          await changeCalendarNotificationSound(false);
        }
      case CalendarNotificationMode.off:
        await changeCalendarNotificationsEnabled(false);
    }
  }

  Future<void> _rescheduleNotifications() async {
    final notificationService = _notificationService;

    // Cancel previously scheduled calendar EVENT notifications only.
    final prevIdsJson = _settingsRepository
        .getCalendarEventNotificationIdsJson();
    final prevIds = <int>[];
    try {
      final decoded = jsonDecode(prevIdsJson);
      if (decoded is List) {
        for (final v in decoded) {
          if (v is int) prevIds.add(v);
        }
      }
    } catch (_) {}

    for (final id in prevIds) {
      await notificationService.cancelNotification(id);
    }

    if (!state.calendarNotificationsEnabled) {
      await _settingsRepository.updateCalendarEventNotificationIdsJson('[]');
      return;
    }

    final scheduledIds = <int>{};

    final now = DateTime.now();

    for (final event in state.events) {
      if (event.recurring) {
        // Schedule for the next 2 years
        for (int i = 0; i < 2; i++) {
          final DateTime occurrenceDate;
          if (event.recurOnHebrew) {
            final currentHebrewYear = JewishDate.fromDateTime(
              now,
            ).getJewishYear();
            final targetHebrewYear = currentHebrewYear + i;

            // Handle leap years and Adar
            final tempJd = JewishDate();
            tempJd.setJewishDate(targetHebrewYear, 1, 1);
            if (event.baseJewishMonth == 13 && !tempJd.isJewishLeapYear()) {
              continue; // Skip Adar II in non-leap year
            }
            try {
              final jd = JewishDate();
              jd.setJewishDate(
                targetHebrewYear,
                event.baseJewishMonth,
                event.baseJewishDay,
              );
              occurrenceDate = jd.getGregorianCalendar();
            } catch (e) {
              // could be an invalid date like 30th of Cheshvan
              continue;
            }
          } else {
            occurrenceDate = DateTime(
              now.year + i,
              event.baseGregorianDate.month,
              event.baseGregorianDate.day,
            );
          }

          // שילוב השעה אם קיימת
          final DateTime eventDateTime;
          if (event.eventTime != null) {
            eventDateTime = DateTime(
              occurrenceDate.year,
              occurrenceDate.month,
              occurrenceDate.day,
              event.eventTime!.hour,
              event.eventTime!.minute,
            );
          } else {
            // אם אין שעה, השתמש בחצות
            eventDateTime = DateTime(
              occurrenceDate.year,
              occurrenceDate.month,
              occurrenceDate.day,
              0,
              0,
            );
          }

          if (eventDateTime.isAfter(now)) {
            final id =
                '${event.id}${occurrenceDate.year}${occurrenceDate.month}${occurrenceDate.day}'
                    .hashCode;
            scheduledIds.add(id);
            await notificationService.scheduleNotification(
              id: id,
              title: event.title,
              body: event.description,
              eventDate: eventDateTime,
              reminderMinutes:
                  event.notificationMinutes ?? state.calendarNotificationTime,
              soundEnabled: state.calendarNotificationSound,
            );
          }
        }
      } else {
        // Non-recurring event
        // שילוב השעה אם קיימת
        final DateTime eventDateTime;
        if (event.eventTime != null) {
          eventDateTime = DateTime(
            event.baseGregorianDate.year,
            event.baseGregorianDate.month,
            event.baseGregorianDate.day,
            event.eventTime!.hour,
            event.eventTime!.minute,
          );
        } else {
          // אם אין שעה, השתמש בחצות
          eventDateTime = DateTime(
            event.baseGregorianDate.year,
            event.baseGregorianDate.month,
            event.baseGregorianDate.day,
            12,
            0,
          );
        }

        if (eventDateTime.isAfter(now)) {
          final id = event.id.hashCode;
          scheduledIds.add(id);
          await notificationService.scheduleNotification(
            id: id,
            title: event.title,
            body: event.description,
            eventDate: eventDateTime,
            reminderMinutes:
                event.notificationMinutes ?? state.calendarNotificationTime,
            soundEnabled: state.calendarNotificationSound,
          );
        }
      }
    }

    await _settingsRepository.updateCalendarEventNotificationIdsJson(
      jsonEncode(scheduledIds.toList()),
    );
  }
}

// --- Helper logic for robust Jewish month navigation ---

/// Computes the next Jewish month preserving correct leap year Adar I/II logic
/// Year changes ONLY when moving from Elul (6) -> Tishrei (7)
JewishDate _computeNextJewishMonth(JewishDate current) {
  final y = current.getJewishYear();
  final m = current.getJewishMonth();
  final leap = current.isJewishLeapYear();
  final JewishDate next = JewishDate();

  if (m == 6) {
    // Elul -> Tishrei, year increments
    next.setJewishDate(y + 1, 7, 1);
  } else if (leap && m == 12) {
    // Adar I -> Adar II (same year)
    next.setJewishDate(y, 13, 1);
  } else if ((!leap && m == 12) || m == 13) {
    // Adar (non-leap) or Adar II (leap) -> Nissan (same year)
    next.setJewishDate(y, 1, 1);
  } else {
    next.setJewishDate(y, m + 1, 1);
  }
  return next;
}

/// Computes the previous Jewish month with proper year boundary handling
/// Year changes ONLY when moving from Tishrei (7) -> Elul (6)
JewishDate _computePreviousJewishMonth(JewishDate current) {
  final y = current.getJewishYear();
  final m = current.getJewishMonth();
  final leap = current.isJewishLeapYear();
  final JewishDate prev = JewishDate();

  if (m == 7) {
    // Tishrei -> Elul, year decrements
    prev.setJewishDate(y - 1, 6, 1);
  } else if (leap && m == 13) {
    // Adar II -> Adar I (same year)
    prev.setJewishDate(y, 12, 1);
  } else if (m == 1) {
    // Nissan -> Adar (same year, depending on leap)
    final lastMonthThisYear = leap ? 13 : 12;
    prev.setJewishDate(y, lastMonthThisYear, 1);
  } else {
    prev.setJewishDate(y, m - 1, 1);
  }
  return prev;
}

// Public wrappers (for testing)
JewishDate computeNextJewishMonth(JewishDate current) =>
    _computeNextJewishMonth(current);
JewishDate computePreviousJewishMonth(JewishDate current) =>
    _computePreviousJewishMonth(current);

// Simple event model kept here for scope

enum RecurrenceType {
  none,
  weekly,
  monthlyHebrew,
  monthlyGregorian,
  annualHebrew,
  annualGregorian,
}

class CustomEvent extends Equatable {
  final String id; // מזהה ייחודי
  final String title;
  final String description;
  final DateTime createdAt;
  final DateTime baseGregorianDate;
  final int baseJewishYear;
  final int baseJewishMonth;
  final int baseJewishDay;
  final RecurrenceType recurrenceType;
  final int? recurringYears; // כמה שנים האירוע יחזור
  final String? googleEventId;
  final TimeOfDay? eventTime; // שעת האירוע (אופציונלי)
  // תאריך סיום לאירוע מרובה-ימים; null = אירוע של יום אחד. רלוונטי רק לאירוע חד-פעמי
  final DateTime? endGregorianDate;
  // אינדקס לפלטת CalendarEventColors; null = ללא צבע מיוחד
  final int? colorIndex;
  // דקות לפני האירוע להצגת ההתראה. null = השתמש בהגדרה הגלובלית.
  final int? notificationMinutes;

  bool get recurring => recurrenceType != RecurrenceType.none;
  bool get recurOnHebrew =>
      recurrenceType == RecurrenceType.annualHebrew ||
      recurrenceType == RecurrenceType.monthlyHebrew;

  const CustomEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.baseGregorianDate,
    required this.baseJewishYear,
    required this.baseJewishMonth,
    required this.baseJewishDay,
    required this.recurrenceType,
    this.recurringYears,
    this.googleEventId,
    this.eventTime,
    this.endGregorianDate,
    this.colorIndex,
    this.notificationMinutes,
  });

  // פונקציה שמאפשרת ליצור עותק של אירוע עם שינויים
  CustomEvent copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? createdAt,
    DateTime? baseGregorianDate,
    int? baseJewishYear,
    int? baseJewishMonth,
    int? baseJewishDay,
    RecurrenceType? recurrenceType,
    int? recurringYears,
    String? googleEventId,
    TimeOfDay? eventTime,
    // עטוף ב-ValueGetter כדי לאפשר איפוס מפורש ל-null (לביטול טווח)
    ValueGetter<DateTime?>? endGregorianDate,
    // עטוף ב-ValueGetter כדי לאפשר איפוס מפורש ל-null (הסרת צבע)
    ValueGetter<int?>? colorIndex,
    int? notificationMinutes,
  }) {
    return CustomEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      baseGregorianDate: baseGregorianDate ?? this.baseGregorianDate,
      baseJewishYear: baseJewishYear ?? this.baseJewishYear,
      baseJewishMonth: baseJewishMonth ?? this.baseJewishMonth,
      baseJewishDay: baseJewishDay ?? this.baseJewishDay,
      recurrenceType: recurrenceType ?? this.recurrenceType,
      recurringYears: recurringYears ?? this.recurringYears,
      googleEventId: googleEventId ?? this.googleEventId,
      eventTime: eventTime ?? this.eventTime,
      endGregorianDate: endGregorianDate != null
          ? endGregorianDate()
          : this.endGregorianDate,
      colorIndex: colorIndex != null ? colorIndex() : this.colorIndex,
      notificationMinutes: notificationMinutes ?? this.notificationMinutes,
    );
  }

  // המרה ל-JSON לשמירה
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'baseGregorianDate': baseGregorianDate.millisecondsSinceEpoch,
      'baseJewishYear': baseJewishYear,
      'baseJewishMonth': baseJewishMonth,
      'baseJewishDay': baseJewishDay,
      'recurrenceType': recurrenceType.index,
      'recurringYears': recurringYears,
      'googleEventId': googleEventId,
      'eventTime': eventTime != null
          ? {'hour': eventTime!.hour, 'minute': eventTime!.minute}
          : null,
      'endGregorianDate': endGregorianDate?.millisecondsSinceEpoch,
      'colorIndex': colorIndex,
      'notificationMinutes': notificationMinutes,
    };
  }

  // יצירה מ-JSON לטעינה
  factory CustomEvent.fromJson(Map<String, dynamic> json) {
    RecurrenceType type;
    if (json.containsKey('recurrenceType')) {
      type = RecurrenceType.values[json['recurrenceType'] as int];
    } else {
      // Backward compatibility
      final bool recurring = json['recurring'] as bool? ?? false;
      final bool recurOnHebrew = json['recurOnHebrew'] as bool? ?? true;
      if (!recurring) {
        type = RecurrenceType.none;
      } else {
        type = recurOnHebrew
            ? RecurrenceType.annualHebrew
            : RecurrenceType.annualGregorian;
      }
    }

    TimeOfDay? eventTime;
    if (json.containsKey('eventTime') && json['eventTime'] != null) {
      final timeMap = json['eventTime'] as Map<String, dynamic>;
      eventTime = TimeOfDay(
        hour: timeMap['hour'] as int,
        minute: timeMap['minute'] as int,
      );
    }

    final endMillis = json['endGregorianDate'] as int?;

    return CustomEvent(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      baseGregorianDate: DateTime.fromMillisecondsSinceEpoch(
        json['baseGregorianDate'] as int,
      ),
      baseJewishYear: json['baseJewishYear'] as int,
      baseJewishMonth: json['baseJewishMonth'] as int,
      baseJewishDay: json['baseJewishDay'] as int,
      recurrenceType: type,
      recurringYears: json['recurringYears'] as int?,
      googleEventId: json['googleEventId'] as String?,
      eventTime: eventTime,
      endGregorianDate: endMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(endMillis)
          : null,
      colorIndex: json['colorIndex'] as int?,
      notificationMinutes: json['notificationMinutes'] as int?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    description,
    createdAt,
    baseGregorianDate,
    baseJewishYear,
    baseJewishMonth,
    baseJewishDay,
    recurrenceType,
    recurringYears,
    googleEventId,
    eventTime,
    endGregorianDate,
    colorIndex,
    notificationMinutes,
  ];
}

bool _isCityInIsrael(String cityName) {
  return calendar_location.isCityInIsrael(cityName);
}

Map<String, dynamic>? _getCityData(String cityName) {
  return calendar_location.getCityData(cityName);
}

// Calculate daily times function
Map<String, String> _calculateDailyTimes(DateTime date, String city) {
  return zmanim_helpers.calculateDailyTimes(date, city);
}

// Helper functions for CalendarType conversion
CalendarType _stringToCalendarType(String value) {
  switch (value) {
    case 'hebrew':
      return CalendarType.hebrew;
    case 'gregorian':
      return CalendarType.gregorian;
    case 'combined':
    default:
      return CalendarType.combined;
  }
}

String _calendarTypeToString(CalendarType type) {
  switch (type) {
    case CalendarType.hebrew:
      return 'hebrew';
    case CalendarType.gregorian:
      return 'gregorian';
    case CalendarType.combined:
      return 'combined';
  }
}

/// מחזירה את היום הלוחי לפי זמן מעבר היום שנבחר והעיר הנוכחית.
DateTime resolveCalendarDayForTransition({
  required DateTime now,
  required String city,
  required CalendarDayTransition transition,
}) {
  final cityData = _getCityData(city);
  final timeZoneId = cityData?['timezone'] as String? ?? 'Asia/Jerusalem';
  final tzLocation = tz.getLocation(timeZoneId);
  final nowInCity = tz.TZDateTime.from(now, tzLocation);
  final civilToday = DateTime(
    nowInCity.year,
    nowInCity.month,
    nowInCity.day,
  );

  if (transition == CalendarDayTransition.midnight) {
    return civilToday;
  }

  final transitionTime = _calculateDayTransitionTime(
    civilToday,
    city,
    transition,
  );
  if (transitionTime == null) {
    return civilToday;
  }

  final transitionInCity = tz.TZDateTime.from(transitionTime, tzLocation);
  if (nowInCity.isBefore(transitionInCity)) {
    return civilToday;
  }

  return civilToday.add(const Duration(days: 1));
}

/// ממירה מחרוזת שמורה להגדרת מעבר היום, עם ברירת מחדל לשקיעה.
CalendarDayTransition calendarDayTransitionFromString(String value) {
  switch (value) {
    case 'tzais':
      return CalendarDayTransition.tzais;
    case 'rabbeinuTam':
      return CalendarDayTransition.rabbeinuTam;
    case 'midnight':
      return CalendarDayTransition.midnight;
    case 'sunset':
    default:
      return CalendarDayTransition.sunset;
  }
}

/// ממירה את הגדרת מעבר היום למחרוזת לשמירה בהגדרות.
String calendarDayTransitionToString(CalendarDayTransition transition) {
  switch (transition) {
    case CalendarDayTransition.sunset:
      return 'sunset';
    case CalendarDayTransition.tzais:
      return 'tzais';
    case CalendarDayTransition.rabbeinuTam:
      return 'rabbeinuTam';
    case CalendarDayTransition.midnight:
      return 'midnight';
  }
}

/// בודקת אם יש להציג את התאריך העברי העליון בנוסח "אור ל...".
bool shouldShowOhrPrefixForCalendarHeader({
  required CalendarState state,
  DateTime? now,
}) {
  if (!_isSameDateOnly(state.selectedGregorianDate, state.todayGregorianDate)) {
    return false;
  }

  final cityData = _getCityData(state.selectedCity);
  if (cityData == null) return false;

  final timeZoneId = cityData['timezone'] as String? ?? 'Asia/Jerusalem';
  final tzLocation = tz.getLocation(timeZoneId);
  final nowInCity = now == null
      ? tz.TZDateTime.now(tzLocation)
      : tz.TZDateTime.from(now, tzLocation);
  final alos90 = _calculateAlos90(
    state.todayGregorianDate,
    state.selectedCity,
  );
  if (alos90 == null) return false;

  return nowInCity.isBefore(tz.TZDateTime.from(alos90, tzLocation));
}

/// מחזירה את זמן הרענון הבא לסימון "היום" ולתצוגת "אור ל...".
DateTime nextCalendarTodayRefreshTime({
  required DateTime now,
  required String city,
  required CalendarDayTransition transition,
}) {
  final cityData = _getCityData(city);
  final timeZoneId = cityData?['timezone'] as String? ?? 'Asia/Jerusalem';
  final tzLocation = tz.getLocation(timeZoneId);
  final nowInCity = tz.TZDateTime.from(now, tzLocation);
  final civilToday = DateTime(
    nowInCity.year,
    nowInCity.month,
    nowInCity.day,
  );
  final candidates = <DateTime>[];

  for (int dayOffset = 0; dayOffset <= 1; dayOffset++) {
    final date = civilToday.add(Duration(days: dayOffset));
    final alos90 = _calculateAlos90(date, city);
    if (alos90 != null) {
      candidates.add(tz.TZDateTime.from(alos90, tzLocation));
    }

    if (transition == CalendarDayTransition.midnight) {
      final nextDate = date.add(const Duration(days: 1));
      candidates.add(
        tz.TZDateTime(
          tzLocation,
          nextDate.year,
          nextDate.month,
          nextDate.day,
        ),
      );
    } else {
      final transitionTime = _calculateDayTransitionTime(
        date,
        city,
        transition,
      );
      if (transitionTime != null) {
        candidates.add(tz.TZDateTime.from(transitionTime, tzLocation));
      }
    }
  }

  candidates.sort();
  for (final candidate in candidates) {
    if (candidate.isAfter(nowInCity)) {
      return candidate.add(const Duration(seconds: 2));
    }
  }

  return now.add(const Duration(hours: 1));
}

DateTime? _calculateDayTransitionTime(
  DateTime date,
  String city,
  CalendarDayTransition transition,
) {
  final context = zmanim_helpers.buildZmanimCalendarContext(date, city);
  if (context == null) return null;
  final zmanimCalendar = context.zmanimCalendar;
  switch (transition) {
    case CalendarDayTransition.sunset:
      return zmanimCalendar.getSunset();
    case CalendarDayTransition.tzais:
      return zmanimCalendar.getTzais();
    case CalendarDayTransition.rabbeinuTam:
      final sunset = zmanimCalendar.getSunset();
      return sunset?.add(const Duration(minutes: 72));
    case CalendarDayTransition.midnight:
      return null;
  }
}

DateTime? _calculateAlos90(DateTime date, String city) {
  final context = zmanim_helpers.buildZmanimCalendarContext(date, city);
  final sunrise = context?.zmanimCalendar.getSunrise();
  return sunrise?.subtract(const Duration(minutes: 90));
}

bool _isSameDateOnly(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

// Google Calendar Info
class GoogleCalendarInfo {
  final String id;
  final String name;
  final bool isPrimary;

  GoogleCalendarInfo({
    required this.id,
    required this.name,
    required this.isPrimary,
  });
}
