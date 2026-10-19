import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart'
    as zmanim_helpers;
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/models/calendar_location.dart'
    as calendar_location;
import 'package:otzaria/tools/calendar/models/zman_alert_preference.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

/// Schedules the calendar's system notifications: zman alerts over a rolling
/// window, and reminders for calendar events.
class CalendarAlertScheduler {
  CalendarAlertScheduler({
    required this._notifications,
    required this._settings,
    required this._now,
  });

  static const int _zmanScheduleDaysAhead = 45;
  // גם לאחר חודש בלי היום המבוקש, המרווח הבא בין מופעים יכול להגיע ל־61 יום.
  static const int _eventScheduleDaysAhead = 62;

  final NotificationService _notifications;
  final SettingsRepository _settings;
  final DateTime Function() _now;

  // ⚠️ ריצות מקבילות קראו את אותם מזהים שמורים ותזמנו כל אחת הכול. ב-Windows
  // AddToSchedule אינו דורס, ונשארה התראה כפולה שאי אפשר לבטל.
  final _eventRuns = _CoalescingRunner();
  Future<void> _zmanQueue = Future.value();

  /// Initializes notifications and asks for permission when it is missing.
  Future<bool> ensurePermission() async {
    if (!await _ensureInitialized()) return false;

    bool hasPermission = await _notifications.checkPermissions();
    if (!hasPermission) {
      if (Platform.isMacOS) {
        hasPermission = await _notifications.forceRequestPermissions();
      } else {
        hasPermission = await _notifications.requestPermissions();
      }
    }
    return hasPermission;
  }

  /// שולח התראת בדיקה למערכת ההפעלה. מחזיר האם השליחה הצליחה.
  Future<bool> sendTestNotification() async {
    if (!await ensurePermission()) return false;
    return _notifications.sendTestNotification();
  }

  Future<bool> _ensureInitialized() async =>
      _notifications.isInitialized || await _notifications.ensureInitialized();

  Future<bool> _ensureReadyToCancel() async =>
      _notifications.isInitialized ||
      await _notifications.ensureReadyToCancel();

  Future<void> _enqueueZman(Future<void> Function() job) {
    final run = _zmanQueue.catchError((Object _) {}).then((_) => job());
    _zmanQueue = run;
    return run;
  }

  /// Cancels the notifications of [timeId] in the rolling window.
  Future<void> cancelZmanAlert(String timeId) =>
      _enqueueZman(() => _cancelZmanAlertNow(timeId));

  Future<void> _cancelZmanAlertNow(String timeId) async {
    if (!await _ensureReadyToCancel()) return;
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    for (int i = 0; i <= _zmanScheduleDaysAhead; i++) {
      final d = DateTime(today.year, today.month, today.day + i);
      final id = _zmanNotificationId(timeId, d);
      // cancelNotification עצמו async (platform channel) — מספיק כדי לא לחסום UI
      await _notifications.cancelNotification(id);
    }
  }

  /// Schedules [alerts] for [city] over the rolling window. When [city] has no
  /// data, [onCityNotFound] is called and Asia/Jerusalem is used.
  Future<void> rescheduleZmanAlerts(
    Map<String, ZmanAlertPreference> alerts,
    String city, {
    void Function()? onCityNotFound,
  }) => _enqueueZman(
    () => _rescheduleZmanAlertsNow(alerts, city, onCityNotFound),
  );

  Future<void> _rescheduleZmanAlertsNow(
    Map<String, ZmanAlertPreference> alerts,
    String city,
    void Function()? onCityNotFound,
  ) async {
    if (alerts.isEmpty) return;

    if (!await _ensureInitialized()) return;

    // Don't prompt here; only schedule if we already have permissions.
    final hasPermission = await _notifications.checkPermissions();
    if (!hasPermission) return;

    final cityData = calendar_location.getCityData(city);
    final String timeZoneId;
    if (cityData == null) {
      debugPrint(
        'CalendarCubit: city data not found for "$city", defaulting to Asia/Jerusalem timezone.',
      );
      onCityNotFound?.call();
      timeZoneId = 'Asia/Jerusalem';
    } else {
      timeZoneId = cityData['timezone'] as String? ?? 'Asia/Jerusalem';
    }
    final location = tz.getLocation(timeZoneId);

    final now = _now();
    final today = DateTime(now.year, now.month, now.day);

    for (final entry in alerts.entries) {
      final timeId = entry.key;
      final pref = entry.value;

      for (int i = 0; i <= _zmanScheduleDaysAhead; i++) {
        // yield לאירוע loop — מאפשר ל-UI לרנדר פריים בין כל חישוב
        await Future.delayed(Duration.zero);
        final d = DateTime(today.year, today.month, today.day + i);
        final times = zmanim_helpers.calculateDailyTimes(d, city);
        final timeStr = times[timeId];

        final cancellationId = _zmanNotificationId(timeId, d);

        if (timeStr == null) {
          // Ensure no stale notification for days the zman doesn't exist.
          await _notifications.cancelNotification(cancellationId);
          continue;
        }

        // מחלצים שעה:דקה תוך התעלמות מעטיפת ה-LTR isolate (\u2066) ומסימן
        // השניות (`.`/`:`) שבסוף.
        final match = RegExp(
          '^\u2066?'
          r'(\d{1,2}):(\d{2})',
        ).firstMatch(timeStr);
        if (match == null) {
          await _notifications.cancelNotification(cancellationId);
          continue;
        }

        final h = int.parse(match.group(1)!);
        final m = int.parse(match.group(2)!);

        // Construct TZDateTime in the correct timezone
        final eventDt = tz.TZDateTime(location, d.year, d.month, d.day, h, m);

        await _notifications.cancelNotification(cancellationId);

        try {
          await _notifications.scheduleNotification(
            id: cancellationId,
            title: 'תזכורת: ${pref.displayName}',
            body:
                'בעוד ${_formatMinutesBefore(pref.minutesBefore)} ${pref.displayName} (${timeStr.replaceAll(RegExp('[\u2066\u2069]'), '').replaceFirst(RegExp(r'[.:]$'), '')})',
            eventDate: eventDt,
            reminderMinutes: pref.minutesBefore,
            soundEnabled: true,
          );
        } catch (e) {
          debugPrint('CalendarAlertScheduler: zman alert not scheduled: $e');
          return;
        }
      }
    }
  }

  /// מחליף את תזכורות האירועים לפי המצב העדכני לאחר ביטול התזכורות הקודמות.
  /// זמן התזכורת והצליל נקראים לפני כל תזמון.
  ///
  /// מאתחל את ההתראות רק כשיש מה לבטל או לתזמן. כשהן אינן זמינות המזהים
  /// השמורים נשארים, כדי שהתזמון הבא יבטל אותם.
  ///
  /// ריצה אחת בכל פעם; בקשות שמגיעות בינתיים מתאחדות לריצה אחת נוספת.
  Future<void> rescheduleEventNotifications({
    required List<CustomEvent> Function() events,
    required bool Function() enabled,
    required int Function() defaultMinutes,
    required bool Function() soundEnabled,
  }) => _eventRuns.run(
    () => _rescheduleEventNotificationsNow(
      events: events,
      enabled: enabled,
      defaultMinutes: defaultMinutes,
      soundEnabled: soundEnabled,
    ),
  );

  Future<void> _rescheduleEventNotificationsNow({
    required List<CustomEvent> Function() events,
    required bool Function() enabled,
    required int Function() defaultMinutes,
    required bool Function() soundEnabled,
  }) async {
    // Cancel previously scheduled calendar EVENT notifications only.
    final prevIds = _storedEventNotificationIds();
    final willSchedule = enabled() && _eventReminders(events()).isNotEmpty;
    if (willSchedule) {
      if (!await _ensureInitialized()) return;
    } else if (prevIds.isNotEmpty) {
      if (!await _ensureReadyToCancel()) return;
    }

    for (final id in prevIds) {
      await _notifications.cancelNotification(id);
    }

    if (!enabled()) {
      await _settings.updateCalendarEventNotificationIdsJson('[]');
      return;
    }

    final scheduledIds = <int>{};
    for (final reminder in _eventReminders(events())) {
      try {
        await _notifications.scheduleNotification(
          id: reminder.id,
          title: reminder.event.title,
          body: reminder.event.description,
          eventDate: reminder.date,
          reminderMinutes:
              reminder.event.notificationMinutes ?? defaultMinutes(),
          soundEnabled: soundEnabled(),
        );
        scheduledIds.add(reminder.id);
      } catch (e) {
        debugPrint('CalendarAlertScheduler: event reminder not scheduled: $e');
      }
    }

    await _settings.updateCalendarEventNotificationIdsJson(
      jsonEncode(scheduledIds.toList()),
    );
  }

  List<int> _storedEventNotificationIds() {
    final ids = <int>[];
    try {
      final decoded = jsonDecode(
        _settings.getCalendarEventNotificationIdsJson(),
      );
      if (decoded is List) {
        for (final v in decoded) {
          if (v is int) ids.add(v);
        }
      }
    } catch (_) {}
    return ids;
  }

  /// מופעי האירועים העתידיים בחלון התזמון, עם מזהה ההתראה של כל מופע.
  List<({int id, CustomEvent event, DateTime date})> _eventReminders(
    List<CustomEvent> events,
  ) {
    final reminders = <({int id, CustomEvent event, DateTime date})>[];
    final now = _now();

    for (final event in events) {
      if (event.recurring) {
        // שנתי: השנה והבאה; שבועי/חודשי: כל יום בחלון הקרוב שבו מתחיל מופע.
        final annual =
            event.recurrenceType == RecurrenceType.annualGregorian ||
            event.recurrenceType == RecurrenceType.annualHebrew;
        final candidates = annual ? 2 : _eventScheduleDaysAhead + 1;
        for (int i = 0; i < candidates; i++) {
          final DateTime occurrenceDate;
          if (!annual) {
            occurrenceDate = DateTime(now.year, now.month, now.day + i);
          } else if (event.recurOnHebrew) {
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
          if (!event.startsOccurrenceOn(occurrenceDate)) continue;

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
            reminders.add((
              id: '${event.id}${occurrenceDate.year}${occurrenceDate.month}${occurrenceDate.day}'
                  .hashCode,
              event: event,
              date: eventDateTime,
            ));
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
          reminders.add((
            id: event.id.hashCode,
            event: event,
            date: eventDateTime,
          ));
        }
      }
    }

    return reminders;
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
}

/// מריץ עבודה אחת בכל פעם. בקשות שמגיעות בזמן ריצה מתאחדות לריצה אחת
/// נוספת, שמבצעת את הבקשה האחרונה.
class _CoalescingRunner {
  Future<void>? _running;
  Future<void>? _queued;
  Future<void> Function()? _latest;

  Future<void> run(Future<void> Function() job) {
    _latest = job;
    final running = _running;
    if (running == null) return _start();
    return _queued ??= running.catchError((Object _) {}).then((_) {
      _queued = null;
      return _start();
    });
  }

  Future<void> _start() {
    late final Future<void> current;
    current = Future.sync(_latest!).whenComplete(() {
      if (identical(_running, current)) _running = null;
    });
    _running = current;
    return current;
  }
}
