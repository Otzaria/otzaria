import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/services/calendar_alert_scheduler.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/tools/calendar/repository/google_calendar_repository.dart';
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';
import 'package:otzaria/tools/calendar/services/ics_calendar_service.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart'
    as zmanim_helpers;
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/models/zman_alert_preference.dart';
import 'package:otzaria/tools/calendar/models/calendar_location.dart'
    as calendar_location;
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/adapters/plugin_calendar_adapter.dart';
import 'package:otzaria/theme/calendar_event_colors.dart';
import 'package:timezone/timezone.dart' as tz;

export 'package:otzaria/tools/calendar/models/calendar_event.dart';
export 'package:otzaria/tools/calendar/models/zman_alert_preference.dart';

part 'calendar_state.dart';

/// Interface לטעינת אירועי plugin — מאפשר החלפה ב-mock בטסטים.
abstract class CalendarPluginSource {
  Future<List<CustomEvent>> loadAndMergePluginEvents(
    List<CustomEvent> existingEvents, {
    String? currentWorkspaceId,
    String? currentBookId,
    String? currentBookUid,
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
    String? currentBookUid,
  }) => PluginCalendarAdapter().loadAndMergePluginEvents(
    existingEvents,
    currentWorkspaceId: currentWorkspaceId,
    currentBookId: currentBookId,
    currentBookUid: currentBookUid,
  );
}

// Calendar Cubit
class CalendarCubit extends Cubit<CalendarState> {
  final SettingsRepository _settingsRepository;
  final NotificationService _notificationService;
  late final _alerts = CalendarAlertScheduler(
    notifications: _notificationService,
    settings: _settingsRepository,
    now: _now,
  );
  final GoogleCalendarRepository _googleCalendar;
  final IcsCalendarService _icsCalendarService;
  final CalendarPluginSource _pluginCalendarAdapter;
  final DateTime Function() _now;
  final Completer<void> _initializationCompleter = Completer<void>();
  Timer? _todayRefreshTimer;
  int _pluginRefreshGeneration = 0;
  int _calendarWidgetCount = 0;

  // רשת חודש מכילה עד 42 ימים; אין להרחיב את כל ההיסטוריה לטווחי ימים.
  List<CustomEvent>? _eventCacheSource;
  final _eventsByDate = <DateTime, List<CustomEvent>>{};

  // Getter for accessing notification service from outside
  NotificationService get notificationService => _notificationService;

  /// מסתיים לאחר שטעינת ההגדרות קבעה את היום הלוחי.
  Future<void> get initialized => _initializationCompleter.future;

  /// רישום מופע לוח פתוח; התאריך נשאר נבחר כל עוד יש מופע כזה.
  void registerCalendarWidget() {
    if (isClosed) return;
    _calendarWidgetCount++;
  }

  /// הסרת מופע לוח. רק סגירת המופע האחרון מחזירה את התאריך להיום.
  void unregisterCalendarWidget() {
    if (_calendarWidgetCount == 0) return;
    _calendarWidgetCount--;
    if (_calendarWidgetCount == 0) resetSelectionToTodayIfNeeded();
  }

  CalendarCubit({
    SettingsRepository? settingsRepository,
    NotificationService? notificationService,
    GoogleCalendarService? googleCalendarService,
    IcsCalendarService? icsCalendarService,
    CalendarPluginSource? pluginCalendarAdapter,
    DateTime Function()? now,
  }) : _settingsRepository = settingsRepository ?? SettingsRepository(),
       _notificationService = notificationService ?? NotificationService(),
       _googleCalendar = GoogleCalendarRepository(
         googleCalendarService ?? GoogleCalendarService(),
       ),
       _icsCalendarService = icsCalendarService ?? IcsCalendarService(),
       _pluginCalendarAdapter =
           pluginCalendarAdapter ?? const _DefaultPluginSource(),
       _now = now ?? DateTime.now,
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
    final List<IcsSubscription> icsSubscriptions = IcsSubscription.listFromJson(
      settings['calendarIcsSubscriptions'] as String? ?? '[]',
    );

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
        icsSubscriptions: icsSubscriptions,
      ),
    );
    if (!_initializationCompleter.isCompleted) {
      _initializationCompleter.complete();
    }
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
    if (isClosed) return;
    if (icsSubscriptions.isNotEmpty) {
      await refreshIcsSubscriptions();
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
  /// [currentBookUid] — המזהה היציב, שמאפשר scope מסוג `book:<uid>`.
  Future<void> refreshPluginEvents({
    String? currentWorkspaceId,
    String? currentBookId,
    String? currentBookUid,
  }) async {
    // בולע קריאות ישנות: רק הקריאה האחרונה שמסיימת מורשית ל-emit.
    final generation = ++_pluginRefreshGeneration;

    final pluginEvents = await _pluginCalendarAdapter.loadAndMergePluginEvents(
      [],
      currentWorkspaceId: currentWorkspaceId,
      currentBookId: currentBookId,
      currentBookUid: currentBookUid,
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

  /// שולח התראת בדיקה למערכת ההפעלה. מחזיר האם השליחה הצליחה.
  Future<bool> sendTestNotification() => _alerts.sendTestNotification();

  Future<void> setZmanAlertPreference({
    required String timeId,
    required String displayName,
    required int minutesBefore,
  }) async {
    if (!await _alerts.ensurePermission()) {
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

    await _alerts.cancelZmanAlert(timeId);

    UiSnack.show(ToolsMessages.zmanAlertCancelled(existing.displayName));
  }

  Future<void> _rescheduleZmanAlerts() async {
    await _alerts.rescheduleZmanAlerts(
      state.zmanAlerts,
      state.selectedCity,
      onCityNotFound: () => UiSnack.showError(ToolsMessages.cityDataNotFound),
    );
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

  @override
  Future<void> close() {
    _todayRefreshTimer?.cancel();
    if (!_initializationCompleter.isCompleted) {
      _initializationCompleter.complete();
    }
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
    final newDate = addCalendarDays(state.selectedGregorianDate, -7);
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
    final newDate = addCalendarDays(state.selectedGregorianDate, 7);
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
    final newDate = addCalendarDays(state.selectedGregorianDate, -1);
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
    final newDate = addCalendarDays(state.selectedGregorianDate, 1);
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

  /// חוזר להיום רק אם נבחר יום אחר — בלי emit מיותר כשהלוח נסגר על היום.
  void resetSelectionToTodayIfNeeded() {
    if (isClosed) return;
    final selected = state.selectedGregorianDate;
    final today = state.todayGregorianDate;
    if (selected.year == today.year &&
        selected.month == today.month &&
        selected.day == today.day) {
      return;
    }
    jumpToToday();
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

  /// פונקציה פנימית לניווט לפי מספר ימים
  void _navigateByDays(int days) {
    final newDate = addCalendarDays(state.selectedGregorianDate, days);
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
  void navigateToNextDay() => _navigateByDays(1);

  /// ניווט ליום הקודם (לשימוש עם מקשי חיצים)
  void navigateToPreviousDay() => _navigateByDays(-1);

  /// ניווט לשבוע הבא (לשימוש עם מקשי חיצים)
  void navigateToNextWeek() => _navigateByDays(7);

  /// ניווט לשבוע הקודם (לשימוש עם מקשי חיצים)
  void navigateToPreviousWeek() => _navigateByDays(-7);

  void setEventSearchQuery(String query) {
    emit(state.copyWith(eventSearchQuery: query));
  }

  void toggleSearchInDescriptions(bool value) {
    emit(state.copyWith(searchInDescriptions: value));
  }

  void toggleShowAllEvents(bool value) {
    emit(state.copyWith(showAllEvents: value));
  }

  Map<String, String> shortTimesFor(DateTime date) =>
      zmanim_helpers.calculateDailyTimes(
        date,
        state.selectedCity,
        only: const {'sunrise', 'sunset'},
      );

  // --- Google Calendar Integration ---

  Future<void> setGoogleCalendarEnabled(bool enabled) async {
    emit(state.copyWith(googleCalendarEnabled: enabled));
    await _settingsRepository.updateGoogleCalendarEnabled(enabled);

    if (!enabled) {
      await _googleCalendar.signOut();
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

  Future<List<GoogleCalendarInfo>> getAvailableCalendars() =>
      _googleCalendar.listCalendars();

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
      if (!await _googleCalendar.canConnect(interactive: true)) {
        emit(
          state.copyWith(
            googleCalendarSyncInProgress: false,
            googleCalendarConnected: false,
            googleCalendarSyncError: 'לא הצלחנו להתחבר לחשבון Google.',
          ),
        );
        return false;
      }

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
    await _googleCalendar.signOut();
    // אירוע שיובא מגוגל נושא את מזהה גוגל גם כ-id; אירוע שנוצר באוצריא
    // ונדחף לגוגל שומר id מקומי, ולכן נשאר — הוא נתון של המשתמש.
    final remaining = state.events
        .where((e) => e.googleEventId == null || e.googleEventId != e.id)
        .toList();
    emit(
      state.copyWith(
        events: remaining,
        googleCalendarConnected: false,
        clearGoogleCalendarSyncError: true,
      ),
    );
    await _saveEventsToStorage(remaining);
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
      // Calculate date range for sync
      final now = DateTime.now();
      final events = await _googleCalendar.fetchEvents(
        existingEvents: () => state.events,
        calendarIds: () => state.googleCalendarSelectedIds,
        timeMin: now.subtract(Duration(days: state.googleCalendarSyncPastDays)),
        timeMax: now.add(Duration(days: state.googleCalendarSyncFutureDays)),
        interactive: interactive,
      );
      if (events == null) {
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
        final syncTime = DateTime.now();
        emit(
          state.copyWith(
            events: events,
            googleCalendarConnected: true,
            googleCalendarSyncInProgress: false,
            googleCalendarLastSync: syncTime,
          ),
        );

        await _settingsRepository.updateGoogleCalendarLastSync(
          syncTime.millisecondsSinceEpoch,
        );
        await _saveEventsToStorage(events);
      } catch (e) {
        _emitGoogleSyncError(e);
      }
    } on GoogleCalendarSyncException catch (e) {
      _emitGoogleSyncError(e.cause);
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

  void _emitGoogleSyncError(Object error) {
    emit(
      state.copyWith(
        googleCalendarSyncInProgress: false,
        googleCalendarSyncError: 'שגיאה בסנכרון עם Google Calendar: $error',
      ),
    );
  }

  // --- ייבוא יומנים בפורמט ICS ---

  /// ייבוא חד-פעמי של תוכן קובץ ICS. מחזיר את מספר האירועים שיובאו.
  ///
  /// המזהים נגזרים מה-UID שבקובץ, כך שייבוא חוזר של אותו קובץ מעדכן
  /// אירועים קיימים במקום לשכפל אותם.
  Future<int> importIcsContent(String content) async {
    final parsed = IcsCalendarService.parseIcs(content);
    if (parsed.isEmpty) return 0;
    final newIds = parsed.map((e) => e.id).toSet();
    final events = [
      ...state.events.where((e) => !newIds.contains(e.id)),
      ...parsed,
    ];
    emit(state.copyWith(events: events));
    await _saveEventsToStorage(events);
    return parsed.length;
  }

  /// מוסיף מנוי ליומן מקישור ICS ומייבא את האירועים ממנו.
  /// מחזיר את מספר האירועים שיובאו, או null אם ההורדה נכשלה.
  Future<int?> addIcsSubscription({
    required String name,
    required String url,
  }) async {
    emit(state.copyWith(icsRefreshInProgress: true, clearIcsSyncError: true));
    try {
      final body = await _icsCalendarService.fetchIcs(url);
      final subscription = IcsSubscription(
        id: 'icssub_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        url: url,
        lastRefresh: DateTime.now(),
      );
      final parsed = IcsCalendarService.parseIcs(
        body,
        sourceId: subscription.id,
      );
      if (isClosed) return null;
      final events = [...state.events, ...parsed];
      final subscriptions = [...state.icsSubscriptions, subscription];
      emit(
        state.copyWith(
          events: events,
          icsSubscriptions: subscriptions,
          icsRefreshInProgress: false,
        ),
      );
      await _saveIcsSubscriptions(subscriptions);
      await _saveEventsToStorage(events);
      return parsed.length;
    } catch (e) {
      if (!isClosed) {
        emit(
          state.copyWith(
            icsRefreshInProgress: false,
            icsSyncError: _formatGoogleCalendarError(e),
          ),
        );
      }
      return null;
    }
  }

  /// מסיר מנוי יחד עם כל האירועים שיובאו ממנו.
  Future<void> removeIcsSubscription(String subscriptionId) async {
    final subscriptions = state.icsSubscriptions
        .where((s) => s.id != subscriptionId)
        .toList();
    final events = state.events
        .where((e) => e.icsSourceId != subscriptionId)
        .toList();
    emit(
      state.copyWith(
        icsSubscriptions: subscriptions,
        events: events,
        clearIcsSyncError: true,
      ),
    );
    await _saveIcsSubscriptions(subscriptions);
    await _saveEventsToStorage(events);
  }

  /// מרענן את אירועי המנויים מהקישורים. מנוי שנכשל שומר את אירועיו הקיימים.
  ///
  /// [onlyId] — רענון מנוי בודד; null = כל המנויים.
  Future<void> refreshIcsSubscriptions({String? onlyId}) async {
    final toRefresh = state.icsSubscriptions
        .where((s) => onlyId == null || s.id == onlyId)
        .toList();
    if (toRefresh.isEmpty) return;

    emit(state.copyWith(icsRefreshInProgress: true, clearIcsSyncError: true));
    String? error;

    for (final subscription in toRefresh) {
      try {
        final body = await _icsCalendarService.fetchIcs(subscription.url);
        final parsed = IcsCalendarService.parseIcs(
          body,
          sourceId: subscription.id,
        );
        if (isClosed) return;
        final events = [
          ...state.events.where((e) => e.icsSourceId != subscription.id),
          ...parsed,
        ];
        final subscriptions = state.icsSubscriptions
            .map(
              (s) => s.id == subscription.id
                  ? s.copyWith(lastRefresh: DateTime.now())
                  : s,
            )
            .toList();
        emit(state.copyWith(events: events, icsSubscriptions: subscriptions));
      } catch (e) {
        error =
            'רענון "${subscription.name}" נכשל: '
            '${_formatGoogleCalendarError(e)}';
      }
      if (isClosed) return;
    }

    emit(state.copyWith(icsRefreshInProgress: false, icsSyncError: error));
    await _saveIcsSubscriptions(state.icsSubscriptions);
    await _saveEventsToStorage(state.events);
  }

  Future<void> _saveIcsSubscriptions(
    List<IcsSubscription> subscriptions,
  ) async {
    await _settingsRepository.updateCalendarIcsSubscriptions(
      jsonEncode(subscriptions.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> _refreshGoogleConnectionStatus() async {
    if (!state.googleCalendarEnabled) {
      emit(state.copyWith(googleCalendarConnected: false));
      return;
    }

    final signedIn = await _googleCalendar.isSignedIn();
    emit(state.copyWith(googleCalendarConnected: signedIn));
  }

  Future<String?> _upsertGoogleEvent(CustomEvent event) async {
    if (!state.googleCalendarEnabled) return null;
    return _googleCalendar.upsertEvent(event, _resolveTimeZone());
  }

  Future<void> _deleteGoogleEvent(CustomEvent event) =>
      _googleCalendar.deleteEvent(event);

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

  // --- ניהול אירועים ---

  Future<void> addEvent({
    required String title,
    String? description,
    required DateTime baseGregorianDate,
    required RecurrenceType recurrenceType,
    int? recurringYears,
    TimeOfDay? eventTime,
    DateTime? endGregorianDate,
    DateTime? recurrenceEndDate,
    TimeOfDay? endTime,
    int? colorIndex,
    int? notificationMinutes,
  }) async {
    final baseJewish = JewishDate.fromDateTime(baseGregorianDate);
    final newEvent = CustomEvent(
      id: generateCalendarEventId(), // יצירת ID ייחודי
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
      recurrenceEndDate: recurrenceEndDate != null
          ? DateTime(
              recurrenceEndDate.year,
              recurrenceEndDate.month,
              recurrenceEndDate.day,
            )
          : null,
      endTime: endTime,
      colorIndex: colorIndex,
      googleColorId: CalendarEventColors.googleColorIdForIndex(colorIndex),
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

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  List<CustomEvent> eventsForDate(DateTime date) {
    if (!identical(_eventCacheSource, state.events)) {
      _eventsByDate.clear();
      _eventCacheSource = state.events;
    }
    final day = _dateOnly(date);
    var matches = _eventsByDate[day];
    if (matches == null) {
      if (_eventsByDate.length == 42) {
        _eventsByDate.remove(_eventsByDate.keys.first);
      }
      matches = state.events.where((e) => e.occursOn(date)).toList()
        ..sort(compareCalendarEventsByTime);
      _eventsByDate[day] = matches;
    }
    return List<CustomEvent>.of(matches);
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
      ..sort(compareCalendarEventsChronologically);
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

  Future<void> _rescheduleNotifications() =>
      _alerts.rescheduleEventNotifications(
        events: () => state.events,
        enabled: () => state.calendarNotificationsEnabled,
        defaultMinutes: () => state.calendarNotificationTime,
        soundEnabled: () => state.calendarNotificationSound,
      );
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

  return addCalendarDays(civilToday, 1);
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
    final date = addCalendarDays(civilToday, dayOffset);
    final alos90 = _calculateAlos90(date, city);
    if (alos90 != null) {
      candidates.add(tz.TZDateTime.from(alos90, tzLocation));
    }

    if (transition == CalendarDayTransition.midnight) {
      final nextDate = addCalendarDays(date, 1);
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
