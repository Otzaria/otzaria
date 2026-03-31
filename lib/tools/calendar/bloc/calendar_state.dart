import 'package:equatable/equatable.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/models/calendar_event.dart';

enum CalendarType { hebrew, gregorian, combined }

enum CalendarView { month, week, day }

/// העדפת התראה לזמן הלכתי ספציפי
class ZmanAlertPreference extends Equatable {
  final int minutesBefore;
  final String displayName;

  const ZmanAlertPreference({
    required this.minutesBefore,
    required this.displayName,
  });

  Map<String, dynamic> toJson() => {
        'minutesBefore': minutesBefore,
        'displayName': displayName,
      };

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

/// מצב לוח השנה
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
      selectedGregorianDate: selectedGregorianDate ?? this.selectedGregorianDate,
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
      calendarNotificationsEnabled: calendarNotificationsEnabled ?? this.calendarNotificationsEnabled,
      calendarNotificationTime: calendarNotificationTime ?? this.calendarNotificationTime,
      calendarNotificationSound: calendarNotificationSound ?? this.calendarNotificationSound,
      zmanAlerts: zmanAlerts ?? this.zmanAlerts,
      googleCalendarEnabled: googleCalendarEnabled ?? this.googleCalendarEnabled,
      googleCalendarConnected: googleCalendarConnected ?? this.googleCalendarConnected,
      googleCalendarSelectedIds: googleCalendarSelectedIds ?? this.googleCalendarSelectedIds,
      googleCalendarSyncInProgress: googleCalendarSyncInProgress ?? this.googleCalendarSyncInProgress,
      googleCalendarSyncError: clearGoogleCalendarSyncError
          ? null
          : (googleCalendarSyncError ?? this.googleCalendarSyncError),
      googleCalendarLastSync: googleCalendarLastSync ?? this.googleCalendarLastSync,
      googleCalendarSyncPastDays: googleCalendarSyncPastDays ?? this.googleCalendarSyncPastDays,
      googleCalendarSyncFutureDays: googleCalendarSyncFutureDays ?? this.googleCalendarSyncFutureDays,
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
        events,
        eventSearchQuery,
        searchInDescriptions,
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
