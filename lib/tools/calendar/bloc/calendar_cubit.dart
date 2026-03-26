import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_state.dart';
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/models/calendar_location.dart';
import 'package:otzaria/tools/calendar/models/google_calendar_info.dart';
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_navigation_helpers.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart';
import 'package:timezone/timezone.dart' as tz;

export 'package:otzaria/tools/calendar/bloc/calendar_state.dart';
export 'package:otzaria/tools/calendar/models/calendar_event.dart';
export 'package:otzaria/tools/calendar/models/google_calendar_info.dart';

// Helper — CalendarType serialization
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

/// ה-Cubit הראשי של לוח השנה — מנהל מצב, ניווט, אירועים, התראות וגוגל קלנדר
class CalendarCubit extends Cubit<CalendarState> {
  static const String _primaryGoogleCalendarId = 'primary';
  static const int _zmanScheduleDaysAhead = 45;

  final SettingsRepository _settingsRepository;
  final NotificationService _notificationService;
  final GoogleCalendarService _googleCalendarService;

  NotificationService get notificationService => _notificationService;

  CalendarCubit({
    SettingsRepository? settingsRepository,
    NotificationService? notificationService,
    GoogleCalendarService? googleCalendarService,
  })  : _settingsRepository = settingsRepository ?? SettingsRepository(),
        _notificationService = notificationService ?? NotificationService(),
        _googleCalendarService =
            googleCalendarService ?? GoogleCalendarService(),
        super(CalendarState.initial()) {
    _initializeCalendar();
  }

  Future<void> _initializeCalendar() async {
    final settings = await _settingsRepository.loadSettings();
    final calendarType =
        _stringToCalendarType(settings['calendarType'] as String);
    final selectedCity = settings['selectedCity'] as String;
    final eventsJson = settings['calendarEvents'] as String;
    final bool inIsrael = isCityInIsrael(selectedCity);
    final bool calendarNotificationsEnabled =
        settings['calendarNotificationsEnabled'] as bool;
    final int calendarNotificationTime =
        settings['calendarNotificationTime'] as int;
    final bool calendarNotificationSound =
        settings['calendarNotificationSound'] as bool;
    final String zmanAlertsJson = settings['calendarZmanAlerts'] as String;
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

    List<CustomEvent> events = [];
    try {
      final List<dynamic> eventsList = jsonDecode(eventsJson);
      events = eventsList.map((e) => CustomEvent.fromJson(e)).toList();
    } catch (_) {
      events = [];
    }

    emit(state.copyWith(
      calendarType: calendarType,
      selectedCity: selectedCity,
      events: events,
      inIsrael: inIsrael,
      calendarNotificationsEnabled: calendarNotificationsEnabled,
      calendarNotificationTime: calendarNotificationTime,
      calendarNotificationSound: calendarNotificationSound,
      zmanAlerts: zmanAlerts,
      googleCalendarEnabled: googleCalendarEnabled,
      googleCalendarSelectedIds: googleCalendarSelectedIds,
      googleCalendarSyncPastDays: googleCalendarSyncPastDays,
      googleCalendarSyncFutureDays: googleCalendarSyncFutureDays,
      googleCalendarLastSync: googleCalendarLastSyncRaw > 0
          ? DateTime.fromMillisecondsSinceEpoch(googleCalendarLastSyncRaw)
          : null,
    ));
    _updateTimesForDate(state.selectedGregorianDate, selectedCity);
    await _rescheduleNotifications();
    await _rescheduleZmanAlerts();
    await _refreshGoogleConnectionStatus();
    if (googleCalendarEnabled) {
      await syncGoogleCalendar(interactive: false);
    }
  }

  static Map<String, ZmanAlertPreference> _parseZmanAlertPreferences(
      String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return {};
      final result = <String, ZmanAlertPreference>{};
      decoded.forEach((key, value) {
        if (key is! String) return;
        final pref = ZmanAlertPreference.fromJson(value, fallbackName: key);
        if (pref != null) result[key] = pref;
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  static int _zmanNotificationId(String timeId, DateTime date) {
    final key =
        '$timeId|${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
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

  // ─── Zman Alerts ──────────────────────────────────────────────────────────

  Future<void> setZmanAlertPreference({
    required String timeId,
    required String displayName,
    required int minutesBefore,
  }) async {
    if (!_notificationService.isInitialized) {
      await _notificationService.init();
    }

    bool hasPermission = await _notificationService.checkPermissions();
    if (!hasPermission) {
      hasPermission = Platform.isMacOS
          ? await _notificationService.forceRequestPermissions()
          : await _notificationService.requestPermissions();
    }

    if (!hasPermission) {
      final message = Platform.isMacOS
          ? 'לא ניתן להפעיל התראות - נדרשות הרשאות.\n'
              'עבור להגדרות המערכת > פרטיות ואבטחה > התראות > אוצריא'
          : Platform.isIOS
              ? 'לא ניתן להפעיל התראות - נדרשות הרשאות.\n'
                  'עבור להגדרות > התראות > אוצריא'
              : 'לא ניתן להפעיל התראות - נדרשות הרשאות.\n'
                  'עבור להגדרות המכשיר > אפליקציות > אוצריא > הרשאות';
      UiSnack.showError(message);
      return;
    }

    final updated = Map<String, ZmanAlertPreference>.from(state.zmanAlerts);
    updated[timeId] = ZmanAlertPreference(
        minutesBefore: minutesBefore, displayName: displayName);
    emit(state.copyWith(zmanAlerts: updated));
    await _settingsRepository.updateCalendarZmanAlertsJson(
        jsonEncode(updated.map((k, v) => MapEntry(k, v.toJson()))));
    await _rescheduleZmanAlerts();
    UiSnack.show('התראה הופעלה עבור $displayName');
  }

  Future<void> cancelZmanAlertPreference({required String timeId}) async {
    final existing = state.zmanAlerts[timeId];
    if (existing == null) return;

    final updated = Map<String, ZmanAlertPreference>.from(state.zmanAlerts);
    updated.remove(timeId);
    emit(state.copyWith(zmanAlerts: updated));
    await _settingsRepository.updateCalendarZmanAlertsJson(
        jsonEncode(updated.map((k, v) => MapEntry(k, v.toJson()))));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (int i = 0; i <= _zmanScheduleDaysAhead; i++) {
      final d = today.add(Duration(days: i));
      await _notificationService
          .cancelNotification(_zmanNotificationId(timeId, d));
    }
    UiSnack.show('ההתראה בוטלה עבור ${existing.displayName}');
  }

  Future<void> _rescheduleZmanAlerts() async {
    if (state.zmanAlerts.isEmpty) return;
    if (!_notificationService.isInitialized) return;

    final hasPermission = await _notificationService.checkPermissions();
    if (!hasPermission) return;

    final cityData = getCityData(state.selectedCity);
    final String timeZoneId;
    if (cityData == null) {
      debugPrint(
          'CalendarCubit: city data not found, defaulting to Asia/Jerusalem');
      UiSnack.showError(
          'לא נמצאו נתונים עבור העיר שנבחרה. נעשה שימוש באזור זמן ברירת המחדל.');
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
        final d = today.add(Duration(days: i));
        final times = calculateDailyTimes(d, state.selectedCity);
        final timeStr = times[timeId];
        final cancellationId = _zmanNotificationId(timeId, d);

        if (timeStr == null) {
          await _notificationService.cancelNotification(cancellationId);
          continue;
        }

        final parts = timeStr.split(':');
        if (parts.length != 2) {
          await _notificationService.cancelNotification(cancellationId);
          continue;
        }

        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h == null || m == null) {
          await _notificationService.cancelNotification(cancellationId);
          continue;
        }

        final eventDt = tz.TZDateTime(location, d.year, d.month, d.day, h, m);
        await _notificationService.cancelNotification(cancellationId);
        await _notificationService.scheduleNotification(
          id: cancellationId,
          title: 'תזכורת: ${pref.displayName}',
          body:
              'בעוד ${_formatMinutesBefore(pref.minutesBefore)} ${pref.displayName} ($timeStr)',
          eventDate: eventDt,
          reminderMinutes: pref.minutesBefore,
          soundEnabled: true,
        );
      }
    }
  }

  // ─── Navigation & Date ────────────────────────────────────────────────────

  void _updateTimesForDate(DateTime date, String city) {
    emit(state.copyWith(dailyTimes: calculateDailyTimes(date, city)));
  }

  void selectDate(JewishDate jewishDate, DateTime gregorianDate) {
    final newTimes = calculateDailyTimes(gregorianDate, state.selectedCity);
    final bool updateMonthAnchors = state.calendarView == CalendarView.month;
    emit(state.copyWith(
      selectedJewishDate: jewishDate,
      selectedGregorianDate: gregorianDate,
      dailyTimes: newTimes,
      currentJewishDate:
          updateMonthAnchors ? jewishDate : state.currentJewishDate,
      currentGregorianDate:
          updateMonthAnchors ? gregorianDate : state.currentGregorianDate,
    ));
  }

  Future<void> changeCity(String newCity) async {
    final newTimes = calculateDailyTimes(state.selectedGregorianDate, newCity);
    emit(state.copyWith(
      selectedCity: newCity,
      dailyTimes: newTimes,
      inIsrael: isCityInIsrael(newCity),
    ));
    await _settingsRepository.updateSelectedCity(newCity);
    await _rescheduleZmanAlerts();
  }

  Future<void> changeCalendarType(CalendarType type) async {
    emit(state.copyWith(calendarType: type));
    await _settingsRepository.updateCalendarType(_calendarTypeToString(type));
  }

  Future<void> reloadSettings() async => _initializeCalendar();

  void _previousMonth() {
    if (state.calendarType == CalendarType.gregorian) {
      final newDate = shiftGregorianMonthPreservingDay(
        state.currentGregorianDate,
        forward: false,
      );
      final newTimes = calculateDailyTimes(newDate, state.selectedCity);
      emit(state.copyWith(
        currentGregorianDate: newDate,
        selectedGregorianDate: newDate,
        selectedJewishDate: JewishDate.fromDateTime(newDate),
        currentJewishDate: JewishDate.fromDateTime(newDate),
        dailyTimes: newTimes,
      ));
    } else {
      final newJewishDate = shiftJewishMonthPreservingDay(
        state.currentJewishDate,
        forward: false,
      );
      final newGregorian = newJewishDate.getGregorianCalendar();
      final newTimes = calculateDailyTimes(newGregorian, state.selectedCity);
      emit(state.copyWith(
        currentJewishDate: newJewishDate,
        currentGregorianDate: newGregorian,
        selectedGregorianDate: newGregorian,
        selectedJewishDate: newJewishDate,
        dailyTimes: newTimes,
      ));
    }
  }

  void _nextMonth() {
    if (state.calendarType == CalendarType.gregorian) {
      final newDate = shiftGregorianMonthPreservingDay(
        state.currentGregorianDate,
        forward: true,
      );
      final newTimes = calculateDailyTimes(newDate, state.selectedCity);
      emit(state.copyWith(
        currentGregorianDate: newDate,
        selectedGregorianDate: newDate,
        selectedJewishDate: JewishDate.fromDateTime(newDate),
        currentJewishDate: JewishDate.fromDateTime(newDate),
        dailyTimes: newTimes,
      ));
    } else {
      final newJewishDate = shiftJewishMonthPreservingDay(
        state.currentJewishDate,
        forward: true,
      );
      final newGregorian = newJewishDate.getGregorianCalendar();
      final newTimes = calculateDailyTimes(newGregorian, state.selectedCity);
      emit(state.copyWith(
        currentJewishDate: newJewishDate,
        currentGregorianDate: newGregorian,
        selectedGregorianDate: newGregorian,
        selectedJewishDate: newJewishDate,
        dailyTimes: newTimes,
      ));
    }
  }

  void _previousWeek() {
    final newDate =
        state.selectedGregorianDate.subtract(const Duration(days: 7));
    final newJewishDate = JewishDate.fromDateTime(newDate);
    emit(state.copyWith(
      selectedGregorianDate: newDate,
      selectedJewishDate: newJewishDate,
      dailyTimes: calculateDailyTimes(newDate, state.selectedCity),
    ));
  }

  void _nextWeek() {
    final newDate = state.selectedGregorianDate.add(const Duration(days: 7));
    final newJewishDate = JewishDate.fromDateTime(newDate);
    emit(state.copyWith(
      selectedGregorianDate: newDate,
      selectedJewishDate: newJewishDate,
      dailyTimes: calculateDailyTimes(newDate, state.selectedCity),
    ));
  }

  void _previousDay() {
    final newDate =
        state.selectedGregorianDate.subtract(const Duration(days: 1));
    final newJewishDate = JewishDate.fromDateTime(newDate);
    emit(state.copyWith(
      selectedGregorianDate: newDate,
      selectedJewishDate: newJewishDate,
      dailyTimes: calculateDailyTimes(newDate, state.selectedCity),
    ));
  }

  void _nextDay() {
    final newDate = state.selectedGregorianDate.add(const Duration(days: 1));
    final newJewishDate = JewishDate.fromDateTime(newDate);
    emit(state.copyWith(
      selectedGregorianDate: newDate,
      selectedJewishDate: newJewishDate,
      dailyTimes: calculateDailyTimes(newDate, state.selectedCity),
    ));
  }

  void changeCalendarView(CalendarView view) {
    emit(state.copyWith(calendarView: view));
  }

  void previous() {
    switch (state.calendarView) {
      case CalendarView.month:
        _previousMonth();
      case CalendarView.week:
        _previousWeek();
      case CalendarView.day:
        _previousDay();
    }
  }

  void next() {
    switch (state.calendarView) {
      case CalendarView.month:
        _nextMonth();
      case CalendarView.week:
        _nextWeek();
      case CalendarView.day:
        _nextDay();
    }
  }

  void jumpToToday() {
    final now = DateTime.now();
    final jewishNow = JewishDate();
    emit(state.copyWith(
      selectedJewishDate: jewishNow,
      selectedGregorianDate: now,
      currentJewishDate: jewishNow,
      currentGregorianDate: now,
      dailyTimes: calculateDailyTimes(now, state.selectedCity),
    ));
  }

  void jumpToDate(DateTime date) {
    final jewishDate = JewishDate.fromDateTime(date);
    emit(state.copyWith(
      selectedJewishDate: jewishDate,
      selectedGregorianDate: date,
      currentJewishDate: jewishDate,
      currentGregorianDate: date,
      dailyTimes: calculateDailyTimes(date, state.selectedCity),
    ));
  }

  void _navigateByDuration(Duration duration) {
    final newDate = state.selectedGregorianDate.add(duration);
    final newJewishDate = JewishDate.fromDateTime(newDate);
    emit(state.copyWith(
      selectedGregorianDate: newDate,
      selectedJewishDate: newJewishDate,
      dailyTimes: calculateDailyTimes(newDate, state.selectedCity),
      currentGregorianDate: newDate,
      currentJewishDate: newJewishDate,
    ));
  }

  void navigateToNextDay() => _navigateByDuration(const Duration(days: 1));
  void navigateToPreviousDay() => _navigateByDuration(const Duration(days: -1));
  void navigateToNextWeek() => _navigateByDuration(const Duration(days: 7));
  void navigateToPreviousWeek() =>
      _navigateByDuration(const Duration(days: -7));

  // ─── Search / filter helpers ───────────────────────────────────────────────

  void setEventSearchQuery(String query) =>
      emit(state.copyWith(eventSearchQuery: query));

  void toggleSearchInDescriptions(bool value) =>
      emit(state.copyWith(searchInDescriptions: value));

  void toggleShowAllEvents(bool value) =>
      emit(state.copyWith(showAllEvents: value));

  Map<String, String> shortTimesFor(DateTime date) {
    final full = calculateDailyTimes(date, state.selectedCity);
    return {
      if (full['sunrise'] != null) 'sunrise': full['sunrise']!,
      if (full['sunset'] != null) 'sunset': full['sunset']!,
    };
  }

  // ─── Google Calendar ───────────────────────────────────────────────────────

  Future<void> setGoogleCalendarEnabled(bool enabled) async {
    emit(state.copyWith(googleCalendarEnabled: enabled));
    await _settingsRepository.updateGoogleCalendarEnabled(enabled);
    if (!enabled) {
      await _googleCalendarService.signOut();
      emit(state.copyWith(
        googleCalendarConnected: false,
        clearGoogleCalendarSyncError: true,
      ));
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
    final apiClient =
        await _googleCalendarService.getApiClient(interactive: false);
    if (apiClient == null) return [];
    try {
      final calendarList = await apiClient.api.calendarList.list();
      return [
        for (final item in calendarList.items ?? [])
          if (item.id != null && item.summary != null)
            GoogleCalendarInfo(
              id: item.id!,
              name: item.summary!,
              isPrimary: item.primary ?? false,
            ),
      ];
    } catch (_) {
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
      final apiClient =
          await _googleCalendarService.getApiClient(interactive: true);
      if (apiClient == null) {
        emit(state.copyWith(
          googleCalendarSyncInProgress: false,
          googleCalendarConnected: false,
          googleCalendarSyncError: 'לא הצלחנו להתחבר לחשבון Google.',
        ));
        return false;
      }
      apiClient.close();
      emit(state.copyWith(
        googleCalendarConnected: true,
        googleCalendarSyncInProgress: false,
        clearGoogleCalendarSyncError: true,
      ));
      await syncGoogleCalendar(interactive: false);
      return true;
    } catch (e) {
      emit(state.copyWith(
        googleCalendarSyncInProgress: false,
        googleCalendarConnected: false,
        googleCalendarSyncError: _formatGoogleCalendarError(e),
      ));
      return false;
    }
  }

  String _formatGoogleCalendarError(dynamic error) {
    String msg = error.toString();
    if (msg.startsWith('Exception: ')) {
      msg = msg.substring('Exception: '.length);
    }
    return msg;
  }

  Future<void> disconnectGoogleCalendar() async {
    await _googleCalendarService.signOut();
    emit(state.copyWith(
      googleCalendarConnected: false,
      clearGoogleCalendarSyncError: true,
    ));
  }

  Future<void> syncGoogleCalendar({required bool interactive}) async {
    if (!state.googleCalendarEnabled) return;
    emit(state.copyWith(
      googleCalendarSyncInProgress: true,
      clearGoogleCalendarSyncError: true,
    ));
    try {
      final apiClient =
          await _googleCalendarService.getApiClient(interactive: interactive);
      if (apiClient == null) {
        emit(state.copyWith(
          googleCalendarSyncInProgress: false,
          googleCalendarConnected: false,
          googleCalendarSyncError: 'לא הצלחנו להתחבר לחשבון Google.',
        ));
        return;
      }
      try {
        final now = DateTime.now();
        final timeMin =
            now.subtract(Duration(days: state.googleCalendarSyncPastDays));
        final timeMax =
            now.add(Duration(days: state.googleCalendarSyncFutureDays));

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
                maxResults: 2500,
                pageToken: pageToken,
              );
              allGoogleEvents.addAll(result.items ?? []);
              pageToken = result.nextPageToken;
            } while (pageToken != null);
          } catch (e) {
            debugPrint('Failed to sync calendar $calendarId: $e');
          }
        }

        final merged = _mergeGoogleEvents(state.events, allGoogleEvents);
        final syncTime = DateTime.now();
        emit(state.copyWith(
          events: merged,
          googleCalendarConnected: true,
          googleCalendarSyncInProgress: false,
          googleCalendarLastSync: syncTime,
        ));
        await _settingsRepository
            .updateGoogleCalendarLastSync(syncTime.millisecondsSinceEpoch);
        await _saveEventsToStorage(merged);
      } catch (e) {
        emit(state.copyWith(
          googleCalendarSyncInProgress: false,
          googleCalendarSyncError: 'שגיאה בסנכרון עם Google Calendar: $e',
        ));
      } finally {
        apiClient.close();
      }
    } catch (e) {
      emit(state.copyWith(
        googleCalendarSyncInProgress: false,
        googleCalendarConnected: false,
        googleCalendarSyncError: _formatGoogleCalendarError(e),
      ));
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
    final apiClient =
        await _googleCalendarService.getApiClient(interactive: false);
    if (apiClient == null) return null;
    try {
      final timeZoneId = _resolveTimeZone();
      final googleEvent = _toGoogleEvent(event, timeZoneId);
      if (event.googleEventId == null || event.googleEventId!.isEmpty) {
        final created = await apiClient.api.events
            .insert(googleEvent, _primaryGoogleCalendarId);
        return created.id;
      } else {
        final updated = await apiClient.api.events.update(
            googleEvent, _primaryGoogleCalendarId, event.googleEventId!);
        return updated.id ?? event.googleEventId;
      }
    } catch (e) {
      debugPrint('Failed to upsert Google event: $e');
      return null;
    } finally {
      apiClient.close();
    }
  }

  Future<void> _deleteGoogleEvent(CustomEvent event) async {
    if (event.googleEventId == null || event.googleEventId!.isEmpty) return;
    final apiClient =
        await _googleCalendarService.getApiClient(interactive: false);
    if (apiClient == null) return;
    try {
      await apiClient.api.events
          .delete(_primaryGoogleCalendarId, event.googleEventId!);
    } catch (e) {
      debugPrint('Failed to delete Google event: $e');
    } finally {
      apiClient.close();
    }
  }

  String _resolveTimeZone() {
    final cityData = getCityData(state.selectedCity);
    return cityData?['timezone'] as String? ?? 'Asia/Jerusalem';
  }

  void _replaceEventWithGoogleId(String eventId, String googleEventId) {
    final events = List<CustomEvent>.from(state.events);
    final index = events.indexWhere((e) => e.id == eventId);
    if (index == -1) return;
    events[index] = events[index].copyWith(googleEventId: googleEventId);
    emit(state.copyWith(events: events));
    _saveEventsToStorage(events);
  }

  List<CustomEvent> _mergeGoogleEvents(
      List<CustomEvent> existing, List<cal.Event> googleEvents) {
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
      final mapped = _fromGoogleEvent(gEvent);
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
        );
        continue;
      }
      updated.add(mapped);
      if (googleId.isNotEmpty) byGoogleId[googleId] = updated.length - 1;
    }
    return updated;
  }

  CustomEvent? _fromGoogleEvent(cal.Event gEvent) {
    final start = gEvent.start?.dateTime ?? gEvent.start?.date;
    if (start == null) return null;
    final date = DateTime(start.year, start.month, start.day);
    final jewishDate = JewishDate.fromDateTime(date);
    final otzariaId = gEvent.extendedProperties?.private?['otzaria_event_id'];
    RecurrenceType recurrenceType = RecurrenceType.none;
    if (gEvent.recurrence != null && gEvent.recurrence!.isNotEmpty) {
      final rrule = gEvent.recurrence!.first;
      if (rrule.contains('FREQ=WEEKLY')) {
        recurrenceType = RecurrenceType.weekly;
      } else if (rrule.contains('FREQ=MONTHLY')) {
        recurrenceType = rrule.contains('X-OTZARIA-TYPE=otzaria_hebrew_monthly')
            ? RecurrenceType.monthlyHebrew
            : RecurrenceType.monthlyGregorian;
      } else if (rrule.contains('FREQ=YEARLY')) {
        recurrenceType = rrule.contains('X-OTZARIA-TYPE=otzaria_hebrew_yearly')
            ? RecurrenceType.annualHebrew
            : RecurrenceType.annualGregorian;
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
      recurringYears: null,
      googleEventId: gEvent.id,
    );
  }

  String _generateUniqueId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(0x7FFFFFFF);
    return 'otzaria_${timestamp}_$random';
  }

  cal.Event _toGoogleEvent(CustomEvent event, String timeZoneId) {
    final baseDate = event.baseGregorianDate;
    final startDate = DateTime(baseDate.year, baseDate.month, baseDate.day);
    final endDate = startDate.add(const Duration(days: 1));
    final extendedProps = {
      'otzaria_event_id': event.id,
      'otzaria_recurrence_type': event.recurrenceType.index.toString(),
    };
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
      ..extendedProperties =
          (cal.EventExtendedProperties()..private = extendedProps);
    final recurrence = _googleRecurrenceRule(event);
    if (recurrence != null) googleEvent.recurrence = [recurrence];
    return googleEvent;
  }

  String? _googleRecurrenceRule(CustomEvent event) {
    String? freq;
    String? marker;
    switch (event.recurrenceType) {
      case RecurrenceType.weekly:
        freq = 'WEEKLY';
      case RecurrenceType.monthlyGregorian:
        freq = 'MONTHLY';
      case RecurrenceType.monthlyHebrew:
        freq = 'MONTHLY';
        marker = 'otzaria_hebrew_monthly';
      case RecurrenceType.annualGregorian:
        freq = 'YEARLY';
      case RecurrenceType.annualHebrew:
        freq = 'YEARLY';
        marker = 'otzaria_hebrew_yearly';
      case RecurrenceType.none:
        return null;
    }
    final buffer = StringBuffer('RRULE:FREQ=$freq');
    if (marker != null) buffer.write(';X-OTZARIA-TYPE=$marker');
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

  // ─── Events CRUD ──────────────────────────────────────────────────────────

  Future<void> addEvent({
    required String title,
    String? description,
    required DateTime baseGregorianDate,
    required RecurrenceType recurrenceType,
    int? recurringYears,
    TimeOfDay? eventTime,
  }) async {
    final baseJewish = JewishDate.fromDateTime(baseGregorianDate);
    final newEvent = CustomEvent(
      id: _generateUniqueId(),
      title: title,
      description: description ?? '',
      createdAt: DateTime.now(),
      baseGregorianDate: DateTime(baseGregorianDate.year,
          baseGregorianDate.month, baseGregorianDate.day),
      baseJewishYear: baseJewish.getJewishYear(),
      baseJewishMonth: baseJewish.getJewishMonth(),
      baseJewishDay: baseJewish.getJewishDayOfMonth(),
      recurrenceType: recurrenceType,
      recurringYears: recurringYears,
      eventTime: eventTime,
    );
    final updated = List<CustomEvent>.from(state.events)..add(newEvent);
    emit(state.copyWith(events: updated));
    _saveEventsToStorage(updated);
    if (state.googleCalendarEnabled) {
      final googleId = await _upsertGoogleEvent(newEvent);
      if (googleId != null) _replaceEventWithGoogleId(newEvent.id, googleId);
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
        if (e.recurringYears != null && e.recurringYears! > 0) {
          bool expired = false;
          if (e.recurrenceType == RecurrenceType.annualHebrew ||
              e.recurrenceType == RecurrenceType.monthlyHebrew) {
            if (hY >= e.baseJewishYear + e.recurringYears!) expired = true;
          } else {
            if (gY >= e.baseGregorianDate.year + e.recurringYears!) {
              expired = true;
            }
          }
          if (expired) return false;
        }
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
        return e.baseGregorianDate.year == gY &&
            e.baseGregorianDate.month == gM &&
            e.baseGregorianDate.day == gD;
      }
    }).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  List<CustomEvent> getFilteredEvents(String query) {
    if (query.isEmpty) return [];
    return state.events
        .where((e) =>
            e.title.contains(query) ||
            (state.searchInDescriptions && e.description.contains(query)))
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  Future<void> _saveEventsToStorage(List<CustomEvent> events) async {
    try {
      final eventsJson = jsonEncode(events.map((e) => e.toJson()).toList());
      await _settingsRepository.updateCalendarEvents(eventsJson);
      await _rescheduleNotifications();
    } catch (e) {
      debugPrint('שגיאה בשמירת אירועים: $e');
    }
  }

  // ─── Notification Settings ────────────────────────────────────────────────

  Future<void> changeCalendarNotificationsEnabled(bool enabled) async {
    if (enabled) {
      if (!_notificationService.isInitialized) {
        await _notificationService.init();
      }
      bool hasPermission = await _notificationService.checkPermissions();
      if (!hasPermission) {
        hasPermission = await _notificationService.requestPermissions();
      }
      if (!hasPermission) {
        emit(state.copyWith(calendarNotificationsEnabled: false));
        await _settingsRepository.updateCalendarNotificationsEnabled(false);
        UiSnack.showError(
          'לא ניתן להפעיל התראות - נדרשות הרשאות.\n'
          'עבור להגדרות המכשיר > אפליקציות > אוצריא > הרשאות',
          duration: const Duration(seconds: 8),
        );
        return;
      }
    }
    emit(state.copyWith(calendarNotificationsEnabled: enabled));
    await _settingsRepository.updateCalendarNotificationsEnabled(enabled);
    await _rescheduleNotifications();
  }

  Future<void> changeCalendarNotificationTime(int time) async {
    final oldTime = state.calendarNotificationTime;
    emit(state.copyWith(calendarNotificationTime: time));
    await _settingsRepository.updateCalendarNotificationTime(time);
    if (oldTime != time && state.calendarNotificationsEnabled) {
      await _rescheduleNotifications();
    }
  }

  Future<void> changeCalendarNotificationSound(bool enabled) async {
    emit(state.copyWith(calendarNotificationSound: enabled));
    await _settingsRepository.updateCalendarNotificationSound(enabled);
  }

  Future<void> _rescheduleNotifications() async {
    final notificationService = _notificationService;
    final prevIdsJson =
        _settingsRepository.getCalendarEventNotificationIdsJson();
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
        for (int i = 0; i < 2; i++) {
          final DateTime occurrenceDate;
          if (event.recurOnHebrew) {
            final currentHebrewYear =
                JewishDate.fromDateTime(now).getJewishYear();
            final targetHebrewYear = currentHebrewYear + i;
            final tempJd = JewishDate();
            tempJd.setJewishDate(targetHebrewYear, 1, 1);
            if (event.baseJewishMonth == 13 && !tempJd.isJewishLeapYear()) {
              continue;
            }
            try {
              final jd = JewishDate();
              jd.setJewishDate(
                  targetHebrewYear, event.baseJewishMonth, event.baseJewishDay);
              occurrenceDate = jd.getGregorianCalendar();
            } catch (_) {
              continue;
            }
          } else {
            occurrenceDate = DateTime(
              now.year + i,
              event.baseGregorianDate.month,
              event.baseGregorianDate.day,
            );
          }

          final DateTime eventDateTime;
          if (event.eventTime != null) {
            eventDateTime = DateTime(
                occurrenceDate.year,
                occurrenceDate.month,
                occurrenceDate.day,
                event.eventTime!.hour,
                event.eventTime!.minute);
          } else {
            eventDateTime = DateTime(occurrenceDate.year, occurrenceDate.month,
                occurrenceDate.day, 0, 0);
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
              reminderMinutes: state.calendarNotificationTime,
              soundEnabled: state.calendarNotificationSound,
            );
          }
        }
      } else {
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
            reminderMinutes: state.calendarNotificationTime,
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
