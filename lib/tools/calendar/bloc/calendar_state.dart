part of 'calendar_cubit.dart';

enum CalendarType { hebrew, gregorian, combined }

enum CalendarNotificationMode { sound, silent, off }

enum CalendarView { month, week, day }

enum CalendarDayTransition { sunset, tzais, rabbeinuTam, midnight }

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
  final bool twelveHourClock;
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

  final List<IcsSubscription> icsSubscriptions;
  final bool icsRefreshInProgress;
  final String? icsSyncError;

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
    this.twelveHourClock = false,
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
    this.icsSubscriptions = const [],
    this.icsRefreshInProgress = false,
    this.icsSyncError,
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
    bool? twelveHourClock,
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
    List<IcsSubscription>? icsSubscriptions,
    bool? icsRefreshInProgress,
    String? icsSyncError,
    bool clearIcsSyncError = false,
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
      twelveHourClock: twelveHourClock ?? this.twelveHourClock,
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
      icsSubscriptions: icsSubscriptions ?? this.icsSubscriptions,
      icsRefreshInProgress: icsRefreshInProgress ?? this.icsRefreshInProgress,
      icsSyncError: clearIcsSyncError
          ? null
          : (icsSyncError ?? this.icsSyncError),
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
    twelveHourClock,
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
    icsSubscriptions,
    icsRefreshInProgress,
    icsSyncError,
  ];
}
