import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/settings/settings_repository.dart';
import 'package:otzaria/services/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

enum CalendarType { hebrew, gregorian, combined }

enum CalendarView { month, week, day }

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
      ];
}

// Calendar Cubit
class CalendarCubit extends Cubit<CalendarState> {
  final SettingsRepository _settingsRepository;

  CalendarCubit({SettingsRepository? settingsRepository})
      : _settingsRepository = settingsRepository ?? SettingsRepository(),
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
    ));
    _updateTimesForDate(state.selectedGregorianDate, selectedCity);
    _rescheduleNotifications();
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

  // --- ניהול אירועים ---

  void addEvent({
    required String title,
    String? description,
    required DateTime baseGregorianDate,
    required bool isRecurring,
    required bool recurOnHebrew,
    int? recurringYears,
  }) {
    final baseJewish = JewishDate.fromDateTime(baseGregorianDate);
    final newEvent = CustomEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // יצירת ID ייחודי
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
      recurring: isRecurring,
      recurOnHebrew: recurOnHebrew,
      recurringYears: recurringYears,
    );
    final updated = List<CustomEvent>.from(state.events)..add(newEvent);
    emit(state.copyWith(events: updated));
    _saveEventsToStorage(updated);
  }

  void updateEvent(CustomEvent updatedEvent) {
    final events = List<CustomEvent>.from(state.events);
    final index = events.indexWhere((e) => e.id == updatedEvent.id);
    if (index != -1) {
      events[index] = updatedEvent;
      emit(state.copyWith(events: events));
      _saveEventsToStorage(events);
    }
  }

  void deleteEvent(String eventId) {
    final events = List<CustomEvent>.from(state.events)
      ..removeWhere((e) => e.id == eventId);
    emit(state.copyWith(events: events));
    _saveEventsToStorage(events);
  }

  List<CustomEvent> eventsForDate(DateTime date) {
    final jd = JewishDate.fromDateTime(date);
    final gY = date.year, gM = date.month, gD = date.day;
    final hY = jd.getJewishYear(),
        hM = jd.getJewishMonth(),
        hD = jd.getJewishDayOfMonth();

    return state.events.where((e) {
      if (e.recurring) {
        // בדוק אם האירוע החוזר עדיין בתוקף
        if (e.recurringYears != null && e.recurringYears! > 0) {
          if (e.recurOnHebrew) {
            if (hY >= e.baseJewishYear + e.recurringYears!) {
              return false; // עבר זמנו
            }
          } else {
            if (gY >= e.baseGregorianDate.year + e.recurringYears!) {
              return false; // עבר זמנו
            }
          }
        }
        // אם הוא בתוקף, בדוק אם התאריך מתאים
        if (e.recurOnHebrew) {
          return e.baseJewishMonth == hM && e.baseJewishDay == hD;
        } else {
          return e.baseGregorianDate.month == gM &&
              e.baseGregorianDate.day == gD;
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
      _rescheduleNotifications();
    } catch (e) {
      // במקרה של שגיאה, נדפיס הודעה לקונסול
      debugPrint('שגיאה בשמירת אירועים: $e');
    }
  }

  // --- Notification Settings ---
  Future<void> changeCalendarNotificationsEnabled(bool enabled) async {
    if (enabled) {
      // בקש הרשאות לפני הפעלת התראות
      final notificationService = NotificationService();
      if (!notificationService.isInitialized) {
        await notificationService.init();
      }
      final hasPermission = await notificationService.requestPermissions();

      // אם אין הרשאה, אל תפעיל את ההתראות
      if (!hasPermission) {
        emit(state.copyWith(calendarNotificationsEnabled: false));
        await _settingsRepository.updateCalendarNotificationsEnabled(false);
        return;
      }
    }

    emit(state.copyWith(calendarNotificationsEnabled: enabled));
    await _settingsRepository.updateCalendarNotificationsEnabled(enabled);
    // Reschedule only if enabling/disabling notifications
    _rescheduleNotifications();
  }

  Future<void> changeCalendarNotificationTime(int time) async {
    final oldTime = state.calendarNotificationTime;
    emit(state.copyWith(calendarNotificationTime: time));
    await _settingsRepository.updateCalendarNotificationTime(time);
    // Reschedule only if time actually changed and notifications are enabled
    if (oldTime != time && state.calendarNotificationsEnabled) {
      _rescheduleNotifications();
    }
  }

  Future<void> changeCalendarNotificationSound(bool enabled) async {
    emit(state.copyWith(calendarNotificationSound: enabled));
    await _settingsRepository.updateCalendarNotificationSound(enabled);
    // No need to reschedule for sound changes - it only affects new notifications
  }

  void _rescheduleNotifications() {
    final notificationService = NotificationService();
    notificationService.cancelAllNotifications();

    if (!state.calendarNotificationsEnabled) {
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

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

          if (occurrenceDate.isAfter(today)) {
            final id =
                '${event.id}${occurrenceDate.year}${occurrenceDate.month}${occurrenceDate.day}'
                    .hashCode;
            notificationService.scheduleNotification(
              id: id,
              title: event.title,
              body: event.description,
              eventDate: occurrenceDate,
              reminderMinutes: state.calendarNotificationTime,
              soundEnabled: state.calendarNotificationSound,
            );
          }
        }
      } else {
        // Non-recurring event
        if (event.baseGregorianDate.isAfter(today)) {
          notificationService.scheduleNotification(
            id: event.id.hashCode,
            title: event.title,
            body: event.description,
            eventDate: event.baseGregorianDate,
            reminderMinutes: state.calendarNotificationTime,
            soundEnabled: state.calendarNotificationSound,
          );
        }
      }
    }
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
class CustomEvent extends Equatable {
  final String id; // מזהה ייחודי
  final String title;
  final String description;
  final DateTime createdAt;
  final DateTime baseGregorianDate;
  final int baseJewishYear;
  final int baseJewishMonth;
  final int baseJewishDay;
  final bool recurring;
  final bool recurOnHebrew;
  final int? recurringYears; // כמה שנים האירוע יחזור

  const CustomEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.baseGregorianDate,
    required this.baseJewishYear,
    required this.baseJewishMonth,
    required this.baseJewishDay,
    required this.recurring,
    required this.recurOnHebrew,
    this.recurringYears,
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
    bool? recurring,
    bool? recurOnHebrew,
    int? recurringYears,
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
      recurring: recurring ?? this.recurring,
      recurOnHebrew: recurOnHebrew ?? this.recurOnHebrew,
      recurringYears: recurringYears ?? this.recurringYears,
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
      'recurring': recurring,
      'recurOnHebrew': recurOnHebrew,
      'recurringYears': recurringYears,
    };
  }

  // יצירה מ-JSON לטעינה
  factory CustomEvent.fromJson(Map<String, dynamic> json) {
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
      recurring: json['recurring'] as bool,
      recurOnHebrew: json['recurOnHebrew'] as bool,
      recurringYears: json['recurringYears'] as int?,
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
        recurring,
        recurOnHebrew,
        recurringYears,
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
    'alos': _formatTime(zmanimCalendar.getAlosHashachar()!),
    'alos16point1Degrees':
        _formatTime(zmanimCalendar.getAlos16Point1Degrees()!),
    'alos19point8Degrees':
        _formatTime(zmanimCalendar.getAlos19Point8Degrees()!),
    'sunrise': _formatTime(zmanimCalendar.getSunrise()!),
    'sofZmanShmaMGA': _formatTime(zmanimCalendar.getSofZmanShmaMGA()!),
    'sofZmanShmaGRA': _formatTime(zmanimCalendar.getSofZmanShmaGRA()!),
    'sofZmanTfilaMGA': _formatTime(zmanimCalendar.getSofZmanTfilaMGA()!),
    'sofZmanTfilaGRA': _formatTime(zmanimCalendar.getSofZmanTfilaGRA()!),
    'chatzos': _formatTime(zmanimCalendar.getChatzos()!),
    'chatzosLayla': _formatTime(_calculateChatzosLayla(zmanimCalendar)),
    'minchaGedola': _formatTime(zmanimCalendar.getMinchaGedola()!),
    'minchaKetana': _formatTime(zmanimCalendar.getMinchaKetana()!),
    'plagHamincha': _formatTime(zmanimCalendar.getPlagHamincha()!),
    'sunset': _formatTime(zmanimCalendar.getSunset()!),
    'sunsetRT': _formatTime(_calculateSunsetRT(zmanimCalendar)),
    'tzais': _formatTime(zmanimCalendar.getTzais()!),
  };

  // הוספת זמנים מיוחדים לחגים
  _addSpecialTimes(times, jewishCalendar, zmanimCalendar, city);

  return times;
}

String _formatTime(DateTime dt) {
  return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
    ComplexZmanimCalendar zmanimCalendar, String city) {
  // זמנים מיוחדים לערב פסח
  if (jewishCalendar.getYomTovIndex() == JewishCalendar.EREV_PESACH) {
    // סוף זמן אכילת חמץ - מג"א (4 שעות זמניות)
    final sofZmanAchilasChametzMGA =
        zmanimCalendar.getSofZmanAchilasChametzMGA72Minutes();
    if (sofZmanAchilasChametzMGA != null) {
      times['sofZmanAchilasChametzMGA'] = _formatTime(sofZmanAchilasChametzMGA);
    }

    // סוף זמן אכילת חמץ - גר"א (4 שעות זמניות)
    final sofZmanAchilasChametzGRA =
        zmanimCalendar.getSofZmanAchilasChametzGRA();
    if (sofZmanAchilasChametzGRA != null) {
      times['sofZmanAchilasChametzGRA'] = _formatTime(sofZmanAchilasChametzGRA);
    }

    // סוף זמן ביעור חמץ - מג"א (5 שעות זמניות)
    final sofZmanBiurChametzMGA =
        zmanimCalendar.getSofZmanBiurChametzMGA72Minutes();
    if (sofZmanBiurChametzMGA != null) {
      times['sofZmanBiurChametzMGA'] = _formatTime(sofZmanBiurChametzMGA);
    }

    // סוף זמן ביעור חמץ - גר"א (5 שעות זמניות)
    final sofZmanBiurChametzGRA = zmanimCalendar.getSofZmanBiurChametzGRA();
    if (sofZmanBiurChametzGRA != null) {
      times['sofZmanBiurChametzGRA'] = _formatTime(sofZmanBiurChametzGRA);
    }
  }

  // זמני כניסת שבת/חג
  if (jewishCalendar.getDayOfWeek() == 6 || jewishCalendar.isErevYomTov()) {
    final candleLightingTime =
        _calculateCandleLightingTime(zmanimCalendar, city);
    if (candleLightingTime != null) {
      times['candleLighting'] = _formatTime(candleLightingTime);
    }
  }

  // זמני יציאת שבת/חג
  if (jewishCalendar.getDayOfWeek() == 7 || jewishCalendar.isYomTov()) {
    final shabbosExitTime1 = _calculateShabbosExitTime1(zmanimCalendar);
    final shabbosExitTime2 = _calculateShabbosExitTime2(zmanimCalendar);

    if (shabbosExitTime1 != null) {
      times['shabbosExit1'] = _formatTime(shabbosExitTime1);
    }
    if (shabbosExitTime2 != null) {
      times['shabbosExit2'] = _formatTime(shabbosExitTime2);
    }
  }

  // זמן ספירת העומר (מליל יום שני של פסח עד ערב שבועות)
  if (jewishCalendar.getDayOfOmer() != -1) {
    final omerCountingTime = _calculateOmerCountingTime(zmanimCalendar);
    if (omerCountingTime != null) {
      times['omerCounting'] = _formatTime(omerCountingTime);
    }
  }

  // זמני תענית
  if (jewishCalendar.isTaanis() &&
      jewishCalendar.getYomTovIndex() != JewishCalendar.YOM_KIPPUR) {
    final fastStartTime = _calculateFastStartTime(zmanimCalendar);
    final fastEndTime = _calculateFastEndTime(zmanimCalendar);

    if (fastStartTime != null) {
      times['fastStart'] = _formatTime(fastStartTime);
    }
    if (fastEndTime != null) {
      times['fastEnd'] = _formatTime(fastEndTime);
    }
  }

  // זמן קידוש לבנה
  if (_isKidushLevanaTime(jewishCalendar)) {
    final kidushLevanaEarliest =
        _calculateKidushLevanaEarliest(jewishCalendar, zmanimCalendar);
    final kidushLevanaLatest =
        _calculateKidushLevanaLatest(jewishCalendar, zmanimCalendar);

    if (kidushLevanaEarliest != null) {
      times['kidushLevanaEarliest'] = _formatTime(kidushLevanaEarliest);
    }
    if (kidushLevanaLatest != null) {
      times['kidushLevanaLatest'] = _formatTime(kidushLevanaLatest);
    }
  }

  // זמני קידוש לבנה
  try {
    final tchilasKidushLevana =
        zmanimCalendar.getTchilasZmanKidushLevana3Days();
    final sofZmanKidushLevana =
        zmanimCalendar.getSofZmanKidushLevanaBetweenMoldos();

    if (tchilasKidushLevana != null) {
      times['tchilasKidushLevana'] = _formatTime(tchilasKidushLevana);
    }
    if (sofZmanKidushLevana != null) {
      times['sofZmanKidushLevana'] = _formatTime(sofZmanKidushLevana);
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
