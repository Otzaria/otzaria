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
import 'package:otzaria/tools/shamor_zachor/utils/message_utils.dart';
import 'package:timezone/timezone.dart' as tz;

enum CalendarType { hebrew, gregorian, combined }

enum CalendarView { month, week, day }

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
  final CalendarType calendarType;
  final CalendarView calendarView;
  final List<CustomEvent> events;
  final String eventSearchQuery;
  final bool searchInDescriptions;
  final bool inIsrael;
  final bool showAllEvents;
  final bool calendarNotificationsEnabled;
  final int calendarNotificationTime;
  final bool calendarNotificationSound;
  final Map<String, ZmanAlertPreference> zmanAlerts;
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
    required this.calendarType,
    required this.calendarView,
    required this.inIsrael,
    this.events = const [],
    this.eventSearchQuery = '',
    this.searchInDescriptions = false,
    this.showAllEvents = false,
    this.calendarNotificationsEnabled = true,
    this.calendarNotificationTime = 60,
    this.calendarNotificationSound = true,
    this.zmanAlerts = const {},
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
      calendarType: CalendarType.combined,
      calendarView: CalendarView.month,
      searchInDescriptions: false,
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
    CalendarType? calendarType,
    CalendarView? calendarView,
    List<CustomEvent>? events,
    String? eventSearchQuery,
    bool? searchInDescriptions,
    bool? inIsrael,
    bool? showAllEvents,
    bool? calendarNotificationsEnabled,
    int? calendarNotificationTime,
    bool? calendarNotificationSound,
    Map<String, ZmanAlertPreference>? zmanAlerts,
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
      calendarType: calendarType ?? this.calendarType,
      calendarView: calendarView ?? this.calendarView,
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
        calendarType,
        calendarView,
        inIsrael,
        showAllEvents,
        calendarNotificationsEnabled,
        calendarNotificationTime,
        calendarNotificationSound,
        zmanAlerts,
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

// Calendar Cubit
class CalendarCubit extends Cubit<CalendarState> {
  static const String _primaryGoogleCalendarId = 'primary';
  static const int _zmanScheduleDaysAhead = 45;

  final SettingsRepository _settingsRepository;
  final NotificationService _notificationService;
  final GoogleCalendarService _googleCalendarService;

  // Getter for accessing notification service from outside
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
    final calendarTypeString = settings['calendarType'] as String;
    final calendarType = _stringToCalendarType(calendarTypeString);
    final selectedCity = settings['selectedCity'] as String;
    final eventsJson = settings['calendarEvents'] as String;
    final bool inIsrael = _isCityInIsrael(selectedCity);
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

    // טעינת אירועים מהאחסון
    List<CustomEvent> events = [];
    try {
      final List<dynamic> eventsList = jsonDecode(eventsJson);
      events =
          eventsList.map((eventMap) => CustomEvent.fromJson(eventMap)).toList();
    } catch (e) {
      // אם יש שגיאה בטעינה, נתחיל עם רשימה ריקה
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
      String actionLabel = 'הבנתי';

      if (Platform.isMacOS) {
        message = 'לא ניתן להפעיל התראות - נדרשות הרשאות.\n'
            'עבור להגדרות המערכת > פרטיות ואבטחה > התראות > אוצריא\n'
            'או הפעל מחדש את האפליקציה ואשר את בקשת ההרשאות';
      } else if (Platform.isIOS) {
        message = 'לא ניתן להפעיל התראות - נדרשות הרשאות.\n'
            'עבור להגדרות > התראות > אוצריא';
      } else {
        message = 'לא ניתן להפעיל התראות - נדרשות הרשאות.\n'
            'עבור להגדרות המכשיר > אפליקציות > אוצריא > הרשאות';
      }

      UiSnack.showWithAction(
        message: message,
        actionLabel: actionLabel,
        onAction: () {},
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 10),
      );
      return;
    }

    final updated = Map<String, ZmanAlertPreference>.from(state.zmanAlerts);
    updated[timeId] = ZmanAlertPreference(
      minutesBefore: minutesBefore,
      displayName: displayName,
    );
    emit(state.copyWith(zmanAlerts: updated));
    await _settingsRepository.updateCalendarZmanAlertsJson(
        jsonEncode(updated.map((k, v) => MapEntry(k, v.toJson()))));

    await _rescheduleZmanAlerts();
    UiSnack.show('התראה הופעלה עבור $displayName');
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
        jsonEncode(updated.map((k, v) => MapEntry(k, v.toJson()))));

    // Cancel scheduled notifications for this timeId in our rolling window.
    final notificationService = _notificationService;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (int i = 0; i <= _zmanScheduleDaysAhead; i++) {
      final d = today.add(Duration(days: i));
      final id = _zmanNotificationId(timeId, d);
      await notificationService.cancelNotification(id);
    }

    UiSnack.show('ההתראה בוטלה עבור ${existing.displayName}');
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
          'CalendarCubit: city data not found for "${state.selectedCity}", defaulting to Asia/Jerusalem timezone.');
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
        final times = _calculateDailyTimes(d, state.selectedCity);
        final timeStr = times[timeId];

        final cancellationId = _zmanNotificationId(timeId, d);

        if (timeStr == null) {
          // Ensure no stale notification for days the zman doesn't exist.
          await notificationService.cancelNotification(cancellationId);
          continue;
        }

        final parts = timeStr.split(':');
        if (parts.length != 2) {
          await notificationService.cancelNotification(cancellationId);
          continue;
        }

        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);

        if (h == null || m == null) {
          await notificationService.cancelNotification(cancellationId);
          continue;
        }

        // Construct TZDateTime in the correct timezone
        final eventDt = tz.TZDateTime(location, d.year, d.month, d.day, h, m);

        await notificationService.cancelNotification(cancellationId);

        await notificationService.scheduleNotification(
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

  void _updateTimesForDate(DateTime date, String city) {
    final newTimes = _calculateDailyTimes(date, city);
    emit(state.copyWith(dailyTimes: newTimes));
  }

  void selectDate(JewishDate jewishDate, DateTime gregorianDate) {
    final newTimes = _calculateDailyTimes(gregorianDate, state.selectedCity);
    // When in month view, selecting a cell should also update the month header anchors
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
    final newTimes = _calculateDailyTimes(state.selectedGregorianDate, newCity);
    final bool inIsrael = _isCityInIsrael(newCity);
    emit(state.copyWith(
      selectedCity: newCity,
      dailyTimes: newTimes,
      inIsrael: inIsrael,
    ));
    // שמור את הבחירה בהגדרות
    await _settingsRepository.updateSelectedCity(newCity);

    // Times shift with city, so reschedule zman alerts.
    await _rescheduleZmanAlerts();
  }

  Future<void> changeCalendarType(CalendarType type) async {
    emit(state.copyWith(calendarType: type));
    // שמור את הבחירה בהגדרות
    await _settingsRepository.updateCalendarType(_calendarTypeToString(type));
  }

  /// טעינה מחדש של הגדרות מהאחסון
  Future<void> reloadSettings() async {
    await _initializeCalendar();
  }

  void _previousMonth() {
    if (state.calendarType == CalendarType.gregorian) {
      final current = state.currentGregorianDate;
      final newDate = current.month == 1
          ? DateTime(current.year - 1, 12, 1)
          : DateTime(current.year, current.month - 1, 1);
      final newTimes = _calculateDailyTimes(newDate, state.selectedCity);
      emit(state.copyWith(
        currentGregorianDate: newDate,
        selectedGregorianDate: newDate,
        selectedJewishDate: JewishDate.fromDateTime(newDate),
        currentJewishDate: JewishDate.fromDateTime(newDate),
        dailyTimes: newTimes,
      ));
    } else {
      // Hebrew or combined calendar navigation based on Jewish month numbering (Nissan=1 ... Adar=12 / Adar II=13)
      final current = state.currentJewishDate;
      final newJewishDate = _computePreviousJewishMonth(current);
      final newGregorian = newJewishDate.getGregorianCalendar();
      final newTimes = _calculateDailyTimes(newGregorian, state.selectedCity);
      emit(state.copyWith(
        currentJewishDate: newJewishDate,
        currentGregorianDate:
            newGregorian, // keep gregorian in sync for headers
        selectedGregorianDate: newGregorian,
        selectedJewishDate: newJewishDate,
        dailyTimes: newTimes,
      ));
    }
  }

  void _nextMonth() {
    if (state.calendarType == CalendarType.gregorian) {
      final current = state.currentGregorianDate;
      final newDate = current.month == 12
          ? DateTime(current.year + 1, 1, 1)
          : DateTime(current.year, current.month + 1, 1);
      final newTimes = _calculateDailyTimes(newDate, state.selectedCity);
      emit(state.copyWith(
        currentGregorianDate: newDate,
        selectedGregorianDate: newDate,
        selectedJewishDate: JewishDate.fromDateTime(newDate),
        currentJewishDate: JewishDate.fromDateTime(newDate),
        dailyTimes: newTimes,
      ));
    } else {
      // Hebrew or combined
      final current = state.currentJewishDate;
      final newJewishDate = _computeNextJewishMonth(current);
      final newGregorian = newJewishDate.getGregorianCalendar();
      final newTimes = _calculateDailyTimes(newGregorian, state.selectedCity);
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
    final newDate = state.selectedGregorianDate.subtract(Duration(days: 7));
    final newJewishDate = JewishDate.fromDateTime(newDate);
    final newTimes = _calculateDailyTimes(newDate, state.selectedCity);
    emit(state.copyWith(
      selectedGregorianDate: newDate,
      selectedJewishDate: newJewishDate,
      dailyTimes: newTimes,
    ));
  }

  void _nextWeek() {
    final newDate = state.selectedGregorianDate.add(Duration(days: 7));
    final newJewishDate = JewishDate.fromDateTime(newDate);
    final newTimes = _calculateDailyTimes(newDate, state.selectedCity);
    emit(state.copyWith(
      selectedGregorianDate: newDate,
      selectedJewishDate: newJewishDate,
      dailyTimes: newTimes,
    ));
  }

  void _previousDay() {
    final newDate = state.selectedGregorianDate.subtract(Duration(days: 1));
    final newJewishDate = JewishDate.fromDateTime(newDate);
    final newTimes = _calculateDailyTimes(newDate, state.selectedCity);
    emit(state.copyWith(
      selectedGregorianDate: newDate,
      selectedJewishDate: newJewishDate,
      dailyTimes: newTimes,
    ));
  }

  void _nextDay() {
    final newDate = state.selectedGregorianDate.add(Duration(days: 1));
    final newJewishDate = JewishDate.fromDateTime(newDate);
    final newTimes = _calculateDailyTimes(newDate, state.selectedCity);
    emit(state.copyWith(
      selectedGregorianDate: newDate,
      selectedJewishDate: newJewishDate,
      dailyTimes: newTimes,
    ));
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
    final now = DateTime.now();
    final jewishNow = JewishDate();
    final newTimes = _calculateDailyTimes(now, state.selectedCity);

    emit(state.copyWith(
      selectedJewishDate: jewishNow,
      selectedGregorianDate: now,
      currentJewishDate: jewishNow,
      currentGregorianDate: now,
      dailyTimes: newTimes,
    ));
  }

  void jumpToDate(DateTime date) {
    final jewishDate = JewishDate.fromDateTime(date);
    final newTimes = _calculateDailyTimes(date, state.selectedCity);

    emit(state.copyWith(
      selectedJewishDate: jewishDate,
      selectedGregorianDate: date,
      currentJewishDate: jewishDate,
      currentGregorianDate: date,
      dailyTimes: newTimes,
    ));
  }

  /// פונקציה פנימית לניווט לפי משך זמן
  void _navigateByDuration(Duration duration) {
    final newDate = state.selectedGregorianDate.add(duration);
    final newJewishDate = JewishDate.fromDateTime(newDate);
    final newTimes = _calculateDailyTimes(newDate, state.selectedCity);

    emit(state.copyWith(
      selectedGregorianDate: newDate,
      selectedJewishDate: newJewishDate,
      dailyTimes: newTimes,
      currentGregorianDate: newDate,
      currentJewishDate: newJewishDate,
    ));
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
      final calendars = <GoogleCalendarInfo>[];

      for (final item in calendarList.items ?? []) {
        if (item.id != null && item.summary != null) {
          calendars.add(GoogleCalendarInfo(
            id: item.id!,
            name: item.summary!,
            isPrimary: item.primary ?? false,
          ));
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
      final errorMessage = _formatGoogleCalendarError(e);

      emit(state.copyWith(
        googleCalendarSyncInProgress: false,
        googleCalendarConnected: false,
        googleCalendarSyncError: errorMessage,
      ));
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
        // Calculate date range for sync
        final now = DateTime.now();
        final timeMin =
            now.subtract(Duration(days: state.googleCalendarSyncPastDays));
        final timeMax =
            now.add(Duration(days: state.googleCalendarSyncFutureDays));

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
      final errorMessage = _formatGoogleCalendarError(e);

      emit(state.copyWith(
        googleCalendarSyncInProgress: false,
        googleCalendarConnected: false,
        googleCalendarSyncError: errorMessage,
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

    final apiClient =
        await _googleCalendarService.getApiClient(interactive: false);
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

  List<CustomEvent> _mergeGoogleEvents(
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
      if (googleId.isNotEmpty) {
        byGoogleId[googleId] = updated.length - 1;
      }
    }

    return updated;
  }

  CustomEvent? _fromGoogleEvent(cal.Event gEvent) {
    final start = gEvent.start?.dateTime ?? gEvent.start?.date;
    if (start == null) return null;

    final date = DateTime(start.year, start.month, start.day);
    final jewishDate = JewishDate.fromDateTime(date);
    final otzariaId = gEvent.extendedProperties?.private?['otzaria_event_id'];

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
    );
  }

  String _generateUniqueId() {
    // Generate a more reliable unique ID
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
      ..extendedProperties =
          (cal.EventExtendedProperties()..private = extendedProps);

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
        // אירוע רגיל
        return e.baseGregorianDate.year == gY &&
            e.baseGregorianDate.month == gM &&
            e.baseGregorianDate.day == gD;
      }
    }).toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  List<CustomEvent> getFilteredEvents(String query) {
    if (query.isEmpty) {
      return [];
    }
    return state.events
        .where((e) =>
            e.title.contains(query) ||
            (state.searchInDescriptions && e.description.contains(query)))
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
        UiSnack.showWithAction(
          message: 'לא ניתן להפעיל התראות - נדרשות הרשאות.\n'
              'עבור להגדרות המכשיר > אפליקציות > אוצריא > הרשאות',
          actionLabel: 'הבנתי',
          onAction: () {
            // אפשר להוסיף כאן פתיחת הגדרות האפליקציה בעתיד
          },
          backgroundColor: Colors.orange,
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

  Future<void> _rescheduleNotifications() async {
    final notificationService = _notificationService;

    // Cancel previously scheduled calendar EVENT notifications only.
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
        // Schedule for the next 2 years
        for (int i = 0; i < 2; i++) {
          final DateTime occurrenceDate;
          if (event.recurOnHebrew) {
            final currentHebrewYear =
                JewishDate.fromDateTime(now).getJewishYear();
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
                  targetHebrewYear, event.baseJewishMonth, event.baseJewishDay);
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
              reminderMinutes: state.calendarNotificationTime,
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
  annualGregorian
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

    return CustomEvent(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      baseGregorianDate:
          DateTime.fromMillisecondsSinceEpoch(json['baseGregorianDate'] as int),
      baseJewishYear: json['baseJewishYear'] as int,
      baseJewishMonth: json['baseJewishMonth'] as int,
      baseJewishDay: json['baseJewishDay'] as int,
      recurrenceType: type,
      recurringYears: json['recurringYears'] as int?,
      googleEventId: json['googleEventId'] as String?,
      eventTime: eventTime,
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
      ];
}

// City coordinates map - מסודר לפי מדינות ובסדר א-ב
const Map<String, Map<String, Map<String, dynamic>>> cityCoordinates = {
  'ארץ ישראל': {
    'אופקים': {
      'lat': 31.3111,
      'lng': 34.6214,
      'elevation': 140.0,
      'timezone': 'Asia/Jerusalem'
    },
    'אילת': {
      'lat': 29.5581,
      'lng': 34.9482,
      'elevation': 12.0,
      'timezone': 'Asia/Jerusalem'
    },
    'אלעד': {
      'lat': 32.0519,
      'lng': 34.9517,
      'elevation': 75.0,
      'timezone': 'Asia/Jerusalem'
    },
    'אריאל': {
      'lat': 32.1069,
      'lng': 35.1897,
      'elevation': 650.0,
      'timezone': 'Asia/Jerusalem'
    },
    'אשדוד': {
      'lat': 31.8044,
      'lng': 34.6553,
      'elevation': 50.0,
      'timezone': 'Asia/Jerusalem'
    },
    'אשקלון': {
      'lat': 31.6688,
      'lng': 34.5742,
      'elevation': 50.0,
      'timezone': 'Asia/Jerusalem'
    },
    'באר שבע': {
      'lat': 31.2518,
      'lng': 34.7915,
      'elevation': 280.0,
      'timezone': 'Asia/Jerusalem'
    },
    'ביתר עילית': {
      'lat': 31.7025,
      'lng': 35.1156,
      'elevation': 740.0,
      'timezone': 'Asia/Jerusalem'
    },
    'בית שמש': {
      'lat': 31.7245,
      'lng': 34.9886,
      'elevation': 220.0,
      'timezone': 'Asia/Jerusalem'
    },
    'בני ברק': {
      'lat': 32.0809,
      'lng': 34.8338,
      'elevation': 50.0,
      'timezone': 'Asia/Jerusalem'
    },
    'בת ים': {
      'lat': 32.0167,
      'lng': 34.7500,
      'elevation': 5.0,
      'timezone': 'Asia/Jerusalem'
    },
    'גבעת זאב': {
      'lat': 31.8467,
      'lng': 35.1667,
      'elevation': 600.0,
      'timezone': 'Asia/Jerusalem'
    },
    'גבעתיים': {
      'lat': 32.0706,
      'lng': 34.8103,
      'elevation': 80.0,
      'timezone': 'Asia/Jerusalem'
    },
    'דימונה': {
      'lat': 31.0686,
      'lng': 35.0333,
      'elevation': 550.0,
      'timezone': 'Asia/Jerusalem'
    },
    'הוד השרון': {
      'lat': 32.1506,
      'lng': 34.8889,
      'elevation': 40.0,
      'timezone': 'Asia/Jerusalem'
    },
    'הרצליה': {
      'lat': 32.1624,
      'lng': 34.8443,
      'elevation': 40.0,
      'timezone': 'Asia/Jerusalem'
    },
    'חיפה': {
      'lat': 32.7940,
      'lng': 34.9896,
      'elevation': 30.0,
      'timezone': 'Asia/Jerusalem'
    },
    'חולון': {
      'lat': 32.0117,
      'lng': 34.7689,
      'elevation': 54.0,
      'timezone': 'Asia/Jerusalem'
    },
    'טבריה': {
      'lat': 32.7940,
      'lng': 35.5308,
      'elevation': -200.0,
      'timezone': 'Asia/Jerusalem'
    },
    'יבנה': {
      'lat': 31.8781,
      'lng': 34.7378,
      'elevation': 25.0,
      'timezone': 'Asia/Jerusalem'
    },
    'ירושלים': {
      'lat': 31.7683,
      'lng': 35.2137,
      'elevation': 800.0,
      'timezone': 'Asia/Jerusalem'
    },
    'כפר סבא': {
      'lat': 32.1742,
      'lng': 34.9067,
      'elevation': 75.0,
      'timezone': 'Asia/Jerusalem'
    },
    'כרמיאל': {
      'lat': 32.9186,
      'lng': 35.2958,
      'elevation': 300.0,
      'timezone': 'Asia/Jerusalem'
    },
    'לוד': {
      'lat': 31.9516,
      'lng': 34.8958,
      'elevation': 50.0,
      'timezone': 'Asia/Jerusalem'
    },
    'מודיעין עילית': {
      'lat': 31.9254,
      'lng': 35.0364,
      'elevation': 400.0,
      'timezone': 'Asia/Jerusalem'
    },
    'מצפה רמון': {
      'lat': 30.6097,
      'lng': 34.8017,
      'elevation': 860.0,
      'timezone': 'Asia/Jerusalem'
    },
    'מעלה אדומים': {
      'lat': 31.7767,
      'lng': 35.2973,
      'elevation': 740.0,
      'timezone': 'Asia/Jerusalem'
    },
    'נתיבות': {
      'lat': 31.4214,
      'lng': 34.5911,
      'elevation': 140.0,
      'timezone': 'Asia/Jerusalem'
    },
    'נתניה': {
      'lat': 32.3215,
      'lng': 34.8532,
      'elevation': 30.0,
      'timezone': 'Asia/Jerusalem'
    },
    'נצרת עילית': {
      'lat': 32.6992,
      'lng': 35.3289,
      'elevation': 400.0,
      'timezone': 'Asia/Jerusalem'
    },
    'עפולה': {
      'lat': 32.6078,
      'lng': 35.2897,
      'elevation': 60.0,
      'timezone': 'Asia/Jerusalem'
    },
    'ערד': {
      'lat': 31.2592,
      'lng': 35.2124,
      'elevation': 570.0,
      'timezone': 'Asia/Jerusalem'
    },
    'פתח תקווה': {
      'lat': 32.0870,
      'lng': 34.8873,
      'elevation': 80.0,
      'timezone': 'Asia/Jerusalem'
    },
    'צפת': {
      'lat': 32.9650,
      'lng': 35.4951,
      'elevation': 900.0,
      'timezone': 'Asia/Jerusalem'
    },
    'קרית אונו': {
      'lat': 32.0539,
      'lng': 34.8581,
      'elevation': 75.0,
      'timezone': 'Asia/Jerusalem'
    },
    'קרית ארבע': {
      'lat': 31.5244,
      'lng': 35.1031,
      'elevation': 930.0,
      'timezone': 'Asia/Jerusalem'
    },
    'קרית גת': {
      'lat': 31.6100,
      'lng': 34.7642,
      'elevation': 68.0,
      'timezone': 'Asia/Jerusalem'
    },
    'קרית מלאכי': {
      'lat': 31.7289,
      'lng': 34.7456,
      'elevation': 108.0,
      'timezone': 'Asia/Jerusalem'
    },
    'קרית שמונה': {
      'lat': 33.2072,
      'lng': 35.5692,
      'elevation': 135.0,
      'timezone': 'Asia/Jerusalem'
    },
    'ראשון לציון': {
      'lat': 31.9642,
      'lng': 34.8047,
      'elevation': 68.0,
      'timezone': 'Asia/Jerusalem'
    },
    'רחובות': {
      'lat': 31.8947,
      'lng': 34.8096,
      'elevation': 89.0,
      'timezone': 'Asia/Jerusalem'
    },
    'רמלה': {
      'lat': 31.9297,
      'lng': 34.8667,
      'elevation': 108.0,
      'timezone': 'Asia/Jerusalem'
    },
    'רמת גן': {
      'lat': 32.0719,
      'lng': 34.8244,
      'elevation': 80.0,
      'timezone': 'Asia/Jerusalem'
    },
    'רעננה': {
      'lat': 32.1847,
      'lng': 34.8706,
      'elevation': 45.0,
      'timezone': 'Asia/Jerusalem'
    },
    'תל אביב': {
      'lat': 32.0853,
      'lng': 34.7818,
      'elevation': 5.0,
      'timezone': 'Asia/Jerusalem'
    },
    'תפרח': {
      'lat': 31.3889,
      'lng': 34.6861,
      'elevation': 160.0,
      'timezone': 'Asia/Jerusalem'
    },
  },
  'ארצות הברית': {
    'אטלנטה': {
      'lat': 33.7490,
      'lng': -84.3880,
      'elevation': 320.0,
      'timezone': 'America/New_York'
    },
    'בוסטון': {
      'lat': 42.3601,
      'lng': -71.0589,
      'elevation': 43.0,
      'timezone': 'America/New_York'
    },
    'בלטימור': {
      'lat': 39.2904,
      'lng': -76.6122,
      'elevation': 10.0,
      'timezone': 'America/New_York'
    },
    'דטרויט': {
      'lat': 42.3314,
      'lng': -83.0458,
      'elevation': 183.0,
      'timezone': 'America/Detroit'
    },
    'דנבר': {
      'lat': 39.7392,
      'lng': -104.9903,
      'elevation': 1609.0,
      'timezone': 'America/Denver'
    },
    'לאס וגאס': {
      'lat': 36.1699,
      'lng': -115.1398,
      'elevation': 610.0,
      'timezone': 'America/Los_Angeles'
    },
    'ליקווד': {
      'lat': 40.0878,
      'lng': -74.2098,
      'elevation': 20.0,
      'timezone': 'America/New_York'
    },
    'לוס אנג\'לס': {
      'lat': 34.0522,
      'lng': -118.2437,
      'elevation': 71.0,
      'timezone': 'America/Los_Angeles'
    },
    'מיאמי': {
      'lat': 25.7617,
      'lng': -80.1918,
      'elevation': 2.0,
      'timezone': 'America/New_York'
    },
    'ניו יורק': {
      'lat': 40.7128,
      'lng': -74.0060,
      'elevation': 10.0,
      'timezone': 'America/New_York'
    },
    'סיאטל': {
      'lat': 47.6062,
      'lng': -122.3321,
      'elevation': 56.0,
      'timezone': 'America/Los_Angeles'
    },
    'סן פרנסיסקו': {
      'lat': 37.7749,
      'lng': -122.4194,
      'elevation': 16.0,
      'timezone': 'America/Los_Angeles'
    },
    'פילדלפיה': {
      'lat': 39.9526,
      'lng': -75.1652,
      'elevation': 12.0,
      'timezone': 'America/New_York'
    },
    'פיניקס': {
      'lat': 33.4484,
      'lng': -112.0740,
      'elevation': 331.0,
      'timezone': 'America/Phoenix'
    },
    'קליבלנד': {
      'lat': 41.4993,
      'lng': -81.6944,
      'elevation': 199.0,
      'timezone': 'America/New_York'
    },
    'שיקגו': {
      'lat': 41.8781,
      'lng': -87.6298,
      'elevation': 181.0,
      'timezone': 'America/Chicago'
    },
  },
  'קנדה': {
    'אדמונטון': {
      'lat': 53.5461,
      'lng': -113.4938,
      'elevation': 645.0,
      'timezone': 'America/Edmonton'
    },
    'אוטווה': {
      'lat': 45.4215,
      'lng': -75.6972,
      'elevation': 70.0,
      'timezone': 'America/Toronto'
    },
    'ונקובר': {
      'lat': 49.2827,
      'lng': -123.1207,
      'elevation': 70.0,
      'timezone': 'America/Vancouver'
    },
    'טורונטו': {
      'lat': 43.6532,
      'lng': -79.3832,
      'elevation': 76.0,
      'timezone': 'America/Toronto'
    },
    'מונטריאול': {
      'lat': 45.5017,
      'lng': -73.5673,
      'elevation': 36.0,
      'timezone': 'America/Toronto'
    },
    'קלגרי': {
      'lat': 51.0447,
      'lng': -114.0719,
      'elevation': 1048.0,
      'timezone': 'America/Edmonton'
    },
  },
  'בריטניה': {
    'אדינבורו': {
      'lat': 55.9533,
      'lng': -3.1883,
      'elevation': 47.0,
      'timezone': 'Europe/London'
    },
    'לונדון': {
      'lat': 51.5074,
      'lng': -0.1278,
      'elevation': 35.0,
      'timezone': 'Europe/London'
    },
  },
  'צרפת': {
    'פריז': {
      'lat': 48.8566,
      'lng': 2.3522,
      'elevation': 35.0,
      'timezone': 'Europe/Paris'
    },
  },
  'גרמניה': {
    'ברלין': {
      'lat': 52.5200,
      'lng': 13.4050,
      'elevation': 34.0,
      'timezone': 'Europe/Berlin'
    },
  },
  'איטליה': {
    'מילאנו': {
      'lat': 45.4642,
      'lng': 9.1900,
      'elevation': 122.0,
      'timezone': 'Europe/Rome'
    },
    'רומא': {
      'lat': 41.9028,
      'lng': 12.4964,
      'elevation': 21.0,
      'timezone': 'Europe/Rome'
    },
  },
  'ספרד': {
    'מדריד': {
      'lat': 40.4168,
      'lng': -3.7038,
      'elevation': 650.0,
      'timezone': 'Europe/Madrid'
    },
  },
  'הולנד': {
    'אמסטרדם': {
      'lat': 52.3676,
      'lng': 4.9041,
      'elevation': -2.0,
      'timezone': 'Europe/Amsterdam'
    },
  },
  'שוויץ': {
    'ציריך': {
      'lat': 47.3769,
      'lng': 8.5417,
      'elevation': 408.0,
      'timezone': 'Europe/Zurich'
    },
  },
  'אוסטריה': {
    'וינה': {
      'lat': 48.2082,
      'lng': 16.3738,
      'elevation': 171.0,
      'timezone': 'Europe/Vienna'
    },
  },
  'הונגריה': {
    'בודפשט': {
      'lat': 47.4979,
      'lng': 19.0402,
      'elevation': 102.0,
      'timezone': 'Europe/Budapest'
    },
  },
  'צ\'כיה': {
    'פראג': {
      'lat': 50.0755,
      'lng': 14.4378,
      'elevation': 200.0,
      'timezone': 'Europe/Prague'
    },
  },
  'פולין': {
    'ורשה': {
      'lat': 52.2297,
      'lng': 21.0122,
      'elevation': 100.0,
      'timezone': 'Europe/Warsaw'
    },
  },
  'רוסיה': {
    'מוסקבה': {
      'lat': 55.7558,
      'lng': 37.6176,
      'elevation': 156.0,
      'timezone': 'Europe/Moscow'
    },
  },
  'טורקיה': {
    'איסטנבול': {
      'lat': 41.0082,
      'lng': 28.9784,
      'elevation': 39.0,
      'timezone': 'Europe/Istanbul'
    },
  },
  'פורטוגל': {
    'ליסבון': {
      'lat': 38.7223,
      'lng': -9.1393,
      'elevation': 2.0,
      'timezone': 'Europe/Lisbon'
    },
  },
  'אירלנד': {
    'דבלין': {
      'lat': 53.3498,
      'lng': -6.2603,
      'elevation': 85.0,
      'timezone': 'Europe/Dublin'
    },
  },
  'שוודיה': {
    'סטוקהולם': {
      'lat': 59.3293,
      'lng': 18.0686,
      'elevation': 28.0,
      'timezone': 'Europe/Stockholm'
    },
  },
  'דנמרק': {
    'קופנהגן': {
      'lat': 55.6761,
      'lng': 12.5683,
      'elevation': 24.0,
      'timezone': 'Europe/Copenhagen'
    },
  },
  'פינלנד': {
    'הלסינקי': {
      'lat': 60.1699,
      'lng': 24.9384,
      'elevation': 26.0,
      'timezone': 'Europe/Helsinki'
    },
  },
  'נורווגיה': {
    'אוסלו': {
      'lat': 59.9139,
      'lng': 10.7522,
      'elevation': 23.0,
      'timezone': 'Europe/Oslo'
    },
  },
  'איסלנד': {
    'רייקיאוויק': {
      'lat': 64.1466,
      'lng': -21.9426,
      'elevation': 61.0,
      'timezone': 'Atlantic/Reykjavik'
    },
  },
  'ארגנטינה': {
    'בואנוס איירס': {
      'lat': -34.6118,
      'lng': -58.3960,
      'elevation': 25.0,
      'timezone': 'America/Argentina/Buenos_Aires'
    },
  },
  'ברזיל': {
    'ריו דה ז\'נרו': {
      'lat': -22.9068,
      'lng': -43.1729,
      'elevation': 2.0,
      'timezone': 'America/Sao_Paulo'
    },
    'סאו פאולו': {
      'lat': -23.5505,
      'lng': -46.6333,
      'elevation': 760.0,
      'timezone': 'America/Sao_Paulo'
    },
  },
  'צ\'ילה': {
    'סנטיאגו': {
      'lat': -33.4489,
      'lng': -70.6693,
      'elevation': 520.0,
      'timezone': 'America/Santiago'
    },
  },
  'ונצואלה': {
    'קראקס': {
      'lat': 10.4806,
      'lng': -66.9036,
      'elevation': 900.0,
      'timezone': 'America/Caracas'
    },
  },
  'פרו': {
    'לימה': {
      'lat': -12.0464,
      'lng': -77.0428,
      'elevation': 154.0,
      'timezone': 'America/Lima'
    },
  },
  'מקסיקו': {
    'מקסיקו סיטי': {
      'lat': 19.4326,
      'lng': -99.1332,
      'elevation': 2240.0,
      'timezone': 'America/Mexico_City'
    },
  },
  'מרוקו': {
    'קזבלנקה': {
      'lat': 33.5731,
      'lng': -7.5898,
      'elevation': 50.0,
      'timezone': 'Africa/Casablanca'
    },
  },
  'דרום אפריקה': {
    'יוהנסבורג': {
      'lat': -26.2041,
      'lng': 28.0473,
      'elevation': 1753.0,
      'timezone': 'Africa/Johannesburg'
    },
    'קייפטאון': {
      'lat': -33.9249,
      'lng': 18.4241,
      'elevation': 42.0,
      'timezone': 'Africa/Johannesburg'
    },
  },
  'מצרים': {
    'אלכסנדריה': {
      'lat': 31.2001,
      'lng': 29.9187,
      'elevation': 12.0,
      'timezone': 'Africa/Cairo'
    },
    'קהיר': {
      'lat': 30.0444,
      'lng': 31.2357,
      'elevation': 74.0,
      'timezone': 'Africa/Cairo'
    },
  },
  'הודו': {
    'דלהי': {
      'lat': 28.7041,
      'lng': 77.1025,
      'elevation': 216.0,
      'timezone': 'Asia/Kolkata'
    },
    'מומבאי': {
      'lat': 19.0760,
      'lng': 72.8777,
      'elevation': 14.0,
      'timezone': 'Asia/Kolkata'
    },
  },
  'תאילנד': {
    'בנגקוק': {
      'lat': 13.7563,
      'lng': 100.5018,
      'elevation': 1.5,
      'timezone': 'Asia/Bangkok'
    },
  },
  'סינגפור': {
    'סינגפור': {
      'lat': 1.3521,
      'lng': 103.8198,
      'elevation': 15.0,
      'timezone': 'Asia/Singapore'
    },
  },
  'הונג קונג': {
    'הונג קונג': {
      'lat': 22.3193,
      'lng': 114.1694,
      'elevation': 552.0,
      'timezone': 'Asia/Hong_Kong'
    },
  },
  'יפן': {
    'טוקיו': {
      'lat': 35.6762,
      'lng': 139.6503,
      'elevation': 40.0,
      'timezone': 'Asia/Tokyo'
    },
  },
  'דרום קוריאה': {
    'סיאול': {
      'lat': 37.5665,
      'lng': 126.9780,
      'elevation': 38.0,
      'timezone': 'Asia/Seoul'
    },
  },
  'סין': {
    'בייג\'ינג': {
      'lat': 39.9042,
      'lng': 116.4074,
      'elevation': 43.5,
      'timezone': 'Asia/Shanghai'
    },
    'שנחאי': {
      'lat': 31.2304,
      'lng': 121.4737,
      'elevation': 4.0,
      'timezone': 'Asia/Shanghai'
    },
  },
  'איחוד האמירויות': {
    'דובאי': {
      'lat': 25.2048,
      'lng': 55.2708,
      'elevation': 16.0,
      'timezone': 'Asia/Dubai'
    },
  },
  'כווית': {
    'כווית': {
      'lat': 29.3759,
      'lng': 47.9774,
      'elevation': 55.0,
      'timezone': 'Asia/Kuwait'
    },
  },
  'אוסטרליה': {
    'בריסביין': {
      'lat': -27.4698,
      'lng': 153.0251,
      'elevation': 27.0,
      'timezone': 'Australia/Brisbane'
    },
    'מלבורן': {
      'lat': -37.8136,
      'lng': 144.9631,
      'elevation': 31.0,
      'timezone': 'Australia/Melbourne'
    },
    'פרת': {
      'lat': -31.9505,
      'lng': 115.8605,
      'elevation': 46.0,
      'timezone': 'Australia/Perth'
    },
    'סידני': {
      'lat': -33.8688,
      'lng': 151.2093,
      'elevation': 58.0,
      'timezone': 'Australia/Sydney'
    },
  },
};

bool _isCityInIsrael(String cityName) {
  return cityCoordinates['ארץ ישראל']!.containsKey(cityName);
}

Map<String, dynamic>? _getCityData(String cityName) {
  for (var country in cityCoordinates.values) {
    if (country.containsKey(cityName)) {
      return country[cityName];
    }
  }
  return null;
}

// Calculate daily times function
Map<String, String> _calculateDailyTimes(DateTime date, String city) {
  final cityData = _getCityData(city);
  if (cityData == null) {
    return {};
  }

  final locationName = city;
  final latitude = cityData['lat']!;
  final longitude = cityData['lng']!;
  final elevation = cityData['elevation']!;
  final timeZoneId = cityData['timezone'] as String? ?? 'Asia/Jerusalem';

  final location = GeoLocation();
  location.setLocationName(locationName);
  location.setLatitude(latitude: latitude);
  location.setLongitude(longitude: longitude);
  location.setElevation(elevation > 0 ? elevation : 0);

  // Set the timezone for the location
  final tzLocation = tz.getLocation(timeZoneId);
  final tzDateTime = tz.TZDateTime.from(date, tzLocation);
  location.setDateTime(tzDateTime);

  final zmanimCalendar = ComplexZmanimCalendar.intGeoLocation(location);

  final bool isInIsrael = _isCityInIsrael(city);
  final jewishCalendar = JewishCalendar.fromDateTime(date);
  jewishCalendar.inIsrael = isInIsrael;

  final Map<String, String> times = {
    'alos': _formatTime(zmanimCalendar.getAlosHashachar()!, tzLocation),
    'alos16point1Degrees':
        _formatTime(zmanimCalendar.getAlos16Point1Degrees()!, tzLocation),
    'alos19point8Degrees':
        _formatTime(zmanimCalendar.getAlos19Point8Degrees()!, tzLocation),
    'sunrise': _formatTime(zmanimCalendar.getSunrise()!, tzLocation),
    'sofZmanShmaMGA':
        _formatTime(zmanimCalendar.getSofZmanShmaMGA()!, tzLocation),
    'sofZmanShmaGRA':
        _formatTime(zmanimCalendar.getSofZmanShmaGRA()!, tzLocation),
    'sofZmanTfilaMGA':
        _formatTime(zmanimCalendar.getSofZmanTfilaMGA()!, tzLocation),
    'sofZmanTfilaGRA':
        _formatTime(zmanimCalendar.getSofZmanTfilaGRA()!, tzLocation),
    'chatzos': _formatTime(zmanimCalendar.getChatzos()!, tzLocation),
    'chatzosLayla':
        _formatTime(_calculateChatzosLayla(zmanimCalendar), tzLocation),
    'minchaGedola': _formatTime(zmanimCalendar.getMinchaGedola()!, tzLocation),
    'minchaKetana': _formatTime(zmanimCalendar.getMinchaKetana()!, tzLocation),
    'plagHamincha': _formatTime(zmanimCalendar.getPlagHamincha()!, tzLocation),
    'sunset': _formatTime(zmanimCalendar.getSunset()!, tzLocation),
    'sunsetRT': _formatTime(_calculateSunsetRT(zmanimCalendar), tzLocation),
    'tzais': _formatTime(zmanimCalendar.getTzais()!, tzLocation),
  };

  // הוספת זמנים מיוחדים לחגים
  _addSpecialTimes(times, jewishCalendar, zmanimCalendar, city, tzLocation);

  return times;
}

String _formatTime(DateTime dt, tz.Location tzLocation) {
  // Convert to the correct timezone before formatting
  final tzDateTime = tz.TZDateTime.from(dt, tzLocation);
  return '${tzDateTime.hour.toString().padLeft(2, '0')}:${tzDateTime.minute.toString().padLeft(2, '0')}';
}

// חישוב חצות לילה - 12 שעות אחרי חצות היום
DateTime _calculateChatzosLayla(ComplexZmanimCalendar zmanimCalendar) {
  final chatzos = zmanimCalendar.getChatzos()!;
  return chatzos.add(const Duration(hours: 12));
}

// חישוב שקיעה לפי רבנו תם - בין השמשות רבנו תם
DateTime _calculateSunsetRT(ComplexZmanimCalendar zmanimCalendar) {
  // רבנו תם - 72 דקות אחרי השקיעה
  final sunset = zmanimCalendar.getSunset()!;
  return sunset.add(const Duration(minutes: 72));
}

// הוספת זמנים מיוחדים לחגים
void _addSpecialTimes(Map<String, String> times, JewishCalendar jewishCalendar,
    ComplexZmanimCalendar zmanimCalendar, String city, tz.Location tzLocation) {
  // זמנים מיוחדים לערב פסח
  if (jewishCalendar.getYomTovIndex() == JewishCalendar.EREV_PESACH) {
    // סוף זמן אכילת חמץ - מג"א (4 שעות זמניות)
    final sofZmanAchilasChametzMGA =
        zmanimCalendar.getSofZmanAchilasChametzMGA72Minutes();
    if (sofZmanAchilasChametzMGA != null) {
      times['sofZmanAchilasChametzMGA'] =
          _formatTime(sofZmanAchilasChametzMGA, tzLocation);
    }

    // סוף זמן אכילת חמץ - גר"א (4 שעות זמניות)
    final sofZmanAchilasChametzGRA =
        zmanimCalendar.getSofZmanAchilasChametzGRA();
    if (sofZmanAchilasChametzGRA != null) {
      times['sofZmanAchilasChametzGRA'] =
          _formatTime(sofZmanAchilasChametzGRA, tzLocation);
    }

    // סוף זמן ביעור חמץ - מג"א (5 שעות זמניות)
    final sofZmanBiurChametzMGA =
        zmanimCalendar.getSofZmanBiurChametzMGA72Minutes();
    if (sofZmanBiurChametzMGA != null) {
      times['sofZmanBiurChametzMGA'] =
          _formatTime(sofZmanBiurChametzMGA, tzLocation);
    }

    // סוף זמן ביעור חמץ - גר"א (5 שעות זמניות)
    final sofZmanBiurChametzGRA = zmanimCalendar.getSofZmanBiurChametzGRA();
    if (sofZmanBiurChametzGRA != null) {
      times['sofZmanBiurChametzGRA'] =
          _formatTime(sofZmanBiurChametzGRA, tzLocation);
    }
  }

  // זמני כניסת שבת/חג
  if (jewishCalendar.getDayOfWeek() == 6 || jewishCalendar.isErevYomTov()) {
    final candleLightingTime =
        _calculateCandleLightingTime(zmanimCalendar, city);
    if (candleLightingTime != null) {
      times['candleLighting'] = _formatTime(candleLightingTime, tzLocation);
    }
  }

  // זמני יציאת שבת/חג
  if (jewishCalendar.getDayOfWeek() == 7 || jewishCalendar.isYomTov()) {
    final shabbosExitTime1 = _calculateShabbosExitTime1(zmanimCalendar);
    final shabbosExitTime2 = _calculateShabbosExitTime2(zmanimCalendar);

    if (shabbosExitTime1 != null) {
      times['shabbosExit1'] = _formatTime(shabbosExitTime1, tzLocation);
    }
    if (shabbosExitTime2 != null) {
      times['shabbosExit2'] = _formatTime(shabbosExitTime2, tzLocation);
    }
  }

  // זמן ספירת העומר (מליל יום שני של פסח עד ערב שבועות)
  if (jewishCalendar.getDayOfOmer() != -1) {
    final omerCountingTime = _calculateOmerCountingTime(zmanimCalendar);
    if (omerCountingTime != null) {
      times['omerCounting'] = _formatTime(omerCountingTime, tzLocation);
    }
  }

  // זמני תענית
  if (jewishCalendar.isTaanis() &&
      jewishCalendar.getYomTovIndex() != JewishCalendar.YOM_KIPPUR) {
    final fastStartTime = _calculateFastStartTime(zmanimCalendar);
    final fastEndTime = _calculateFastEndTime(zmanimCalendar);

    if (fastStartTime != null) {
      times['fastStart'] = _formatTime(fastStartTime, tzLocation);
    }
    if (fastEndTime != null) {
      times['fastEnd'] = _formatTime(fastEndTime, tzLocation);
    }
  }

  // זמן קידוש לבנה
  if (_isKidushLevanaTime(jewishCalendar)) {
    final kidushLevanaEarliest =
        _calculateKidushLevanaEarliest(jewishCalendar, zmanimCalendar);
    final kidushLevanaLatest =
        _calculateKidushLevanaLatest(jewishCalendar, zmanimCalendar);

    if (kidushLevanaEarliest != null) {
      times['kidushLevanaEarliest'] =
          _formatTime(kidushLevanaEarliest, tzLocation);
    }
    if (kidushLevanaLatest != null) {
      times['kidushLevanaLatest'] = _formatTime(kidushLevanaLatest, tzLocation);
    }
  }

  // זמני קידוש לבנה
  try {
    final tchilasKidushLevana =
        zmanimCalendar.getTchilasZmanKidushLevana3Days();
    final sofZmanKidushLevana =
        zmanimCalendar.getSofZmanKidushLevanaBetweenMoldos();

    if (tchilasKidushLevana != null) {
      times['tchilasKidushLevana'] =
          _formatTime(tchilasKidushLevana, tzLocation);
    }
    if (sofZmanKidushLevana != null) {
      times['sofZmanKidushLevana'] =
          _formatTime(sofZmanKidushLevana, tzLocation);
    }
  } catch (e) {
    // Ignore errors in calculating moon times for certain dates
  }
}

// חישוב זמן הדלקת נרות לפי עיר
DateTime? _calculateCandleLightingTime(
    ComplexZmanimCalendar zmanimCalendar, String city) {
  final sunset = zmanimCalendar.getSunset();
  if (sunset == null) return null;

  int minutesBefore;
  switch (city) {
    case 'ירושלים':
      minutesBefore = 40;
      break;
    case 'בני ברק':
      minutesBefore = 22;
      break;
    case 'מודיעין עילית':
      minutesBefore = 30;
      break;
    default:
      minutesBefore = 30;
      break;
  }

  return sunset.subtract(Duration(minutes: minutesBefore));
}

// חישוב זמן יציאת שבת 1 - 34 דקות אחרי השקיעה
DateTime? _calculateShabbosExitTime1(ComplexZmanimCalendar zmanimCalendar) {
  final sunset = zmanimCalendar.getSunset();
  if (sunset == null) return null;

  return sunset.add(const Duration(minutes: 34));
}

// חישוב זמן יציאת שבת 2 - צאת השבת חזו"א - 38 דקות אחרי השקיעה
DateTime? _calculateShabbosExitTime2(ComplexZmanimCalendar zmanimCalendar) {
  final sunset = zmanimCalendar.getSunset();
  if (sunset == null) return null;

  return sunset.add(const Duration(minutes: 38));
}

// חישוב זמן ספירת העומר - אחרי צאת הכוכבים
DateTime? _calculateOmerCountingTime(ComplexZmanimCalendar zmanimCalendar) {
  return zmanimCalendar.getTzais();
}

// חישוב תחילת תענית - עלות השחר
DateTime? _calculateFastStartTime(ComplexZmanimCalendar zmanimCalendar) {
  return zmanimCalendar.getAlosHashachar();
}

// חישוב סיום תענית - צאת הכוכבים
DateTime? _calculateFastEndTime(ComplexZmanimCalendar zmanimCalendar) {
  return zmanimCalendar.getTzais();
}

// בדיקה אם זה זמן קידוש לבנה (מיום 3 עד יום 15 בחודש)
bool _isKidushLevanaTime(JewishCalendar jewishCalendar) {
  final dayOfMonth = jewishCalendar.getJewishDayOfMonth();
  return dayOfMonth >= 3 && dayOfMonth <= 15;
}

// חישוב תחילת זמן קידוש לבנה - 3 ימים אחרי המולד
DateTime? _calculateKidushLevanaEarliest(
    JewishCalendar jewishCalendar, ComplexZmanimCalendar zmanimCalendar) {
  // זמן קידוש לבנה מתחיל 3 ימים אחרי המולד, אחרי צאת הכוכבים
  if (jewishCalendar.getJewishDayOfMonth() == 3) {
    return zmanimCalendar.getTzais();
  }
  return null;
}

// חישוב סוף זמן קידוש לבנה - 15 ימים אחרי המולד
DateTime? _calculateKidushLevanaLatest(
    JewishCalendar jewishCalendar, ComplexZmanimCalendar zmanimCalendar) {
  // זמן קידוש לבנה מסתיים ביום 15, לפני עלות השחר
  if (jewishCalendar.getJewishDayOfMonth() == 15) {
    return zmanimCalendar.getAlosHashachar();
  }
  return null;
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
