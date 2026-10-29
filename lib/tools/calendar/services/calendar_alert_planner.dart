import 'package:flutter/foundation.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart'
    as zmanim_helpers;
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/models/calendar_location.dart'
    as calendar_location;
import 'package:otzaria/tools/calendar/models/zman_alert_preference.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

/// התראת מערכת אחת שהתוכנית דורשת שתהיה מתוזמנת.
@immutable
class PlannedAlert {
  const PlannedAlert({
    required this.id,
    required this.title,
    required this.body,
    required this.eventDate,
    required this.reminderMinutes,
    required this.soundEnabled,
  });

  final int id;
  final String title;
  final String body;
  final DateTime eventDate;
  final int reminderMinutes;
  final bool soundEnabled;

  @override
  bool operator ==(Object other) =>
      other is PlannedAlert &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.eventDate == eventDate &&
      other.reminderMinutes == reminderMinutes &&
      other.soundEnabled == soundEnabled;

  @override
  int get hashCode =>
      Object.hash(id, title, body, eventDate, reminderMinutes, soundEnabled);
}

/// מחשב אילו התראות לוח שנה צריכות להיות מתוזמנות, בלי לגעת במערכת.
///
/// ⚠️ המזהים מחושבים מ-[String.hashCode], כמו בגרסאות קודמות: שינוי בנוסחה
/// היה משאיר התראות ישנות שאי אפשר לבטל.
abstract final class CalendarAlertPlanner {
  static const int zmanScheduleDaysAhead = 45;
  // גם לאחר חודש בלי היום המבוקש, המרווח הבא בין מופעים יכול להגיע ל־61 יום.
  static const int eventScheduleDaysAhead = 62;

  /// תזכורות לאירועים מ-[now] והלאה. [events] הם אירועי משתמש ותוספים יחד.
  static List<PlannedAlert> planEventReminders({
    required List<CustomEvent> events,
    required bool enabled,
    required int defaultMinutes,
    required bool soundEnabled,
    required DateTime now,
  }) {
    if (!enabled) return const [];
    final plan = <PlannedAlert>[];

    void add(CustomEvent event, int id, DateTime eventDateTime) {
      if (!eventDateTime.isAfter(now)) return;
      final reminderMinutes = event.notificationMinutes ?? defaultMinutes;
      if (NotificationService.resolveScheduleTime(
            eventDate: eventDateTime,
            reminderMinutes: reminderMinutes,
            now: now,
          ) ==
          null) {
        return;
      }
      plan.add(
        PlannedAlert(
          id: id,
          title: event.title,
          body: event.description,
          eventDate: eventDateTime,
          reminderMinutes: reminderMinutes,
          soundEnabled: soundEnabled,
        ),
      );
    }

    for (final event in events) {
      if (!event.recurring) {
        final base = event.baseGregorianDate;
        final time = event.eventTime;
        // בלי שעה: צהריים, כדי שתזכורת "יום לפני" לא תיפול בלילה.
        add(
          event,
          event.id.hashCode,
          DateTime(
            base.year,
            base.month,
            base.day,
            time?.hour ?? 12,
            time?.minute ?? 0,
          ),
        );
        continue;
      }
      // שנתי: השנה והבאה; שבועי/חודשי: כל יום בחלון הקרוב שבו מתחיל מופע.
      final annual =
          event.recurrenceType == RecurrenceType.annualGregorian ||
          event.recurrenceType == RecurrenceType.annualHebrew;
      final candidates = annual ? 2 : eventScheduleDaysAhead + 1;
      for (int i = 0; i < candidates; i++) {
        final occurrenceDate = _occurrenceCandidate(event, now, i, annual);
        if (occurrenceDate == null) continue;
        if (!event.startsOccurrenceOn(occurrenceDate)) continue;
        final time = event.eventTime;
        add(
          event,
          '${event.id}${occurrenceDate.year}${occurrenceDate.month}${occurrenceDate.day}'
              .hashCode,
          DateTime(
            occurrenceDate.year,
            occurrenceDate.month,
            occurrenceDate.day,
            time?.hour ?? 0,
            time?.minute ?? 0,
          ),
        );
      }
    }
    return plan;
  }

  static DateTime? _occurrenceCandidate(
    CustomEvent event,
    DateTime now,
    int i,
    bool annual,
  ) {
    if (!annual) return DateTime(now.year, now.month, now.day + i);
    if (!event.recurOnHebrew) {
      return DateTime(
        now.year + i,
        event.baseGregorianDate.month,
        event.baseGregorianDate.day,
      );
    }
    final targetHebrewYear = JewishDate.fromDateTime(now).getJewishYear() + i;
    final yearStart = JewishDate()..setJewishDate(targetHebrewYear, 1, 1);
    if (event.baseJewishMonth == 13 && !yearStart.isJewishLeapYear()) {
      return null; // אדר ב' בשנה פשוטה
    }
    try {
      final jd = JewishDate()
        ..setJewishDate(
          targetHebrewYear,
          event.baseJewishMonth,
          event.baseJewishDay,
        );
      return jd.getGregorianCalendar();
    } catch (_) {
      // תאריך שאינו קיים בשנה הזו, כמו ל' חשוון.
      return null;
    }
  }

  /// התראות זמני היום ל-[city] בחלון המתגלגל. עצל, כדי שהקורא יוכל לפנות
  /// את ה-isolate בין חישובים.
  static Iterable<PlannedAlert> planZmanAlerts({
    required Map<String, ZmanAlertPreference> alerts,
    required String city,
    required DateTime now,
    bool twelveHourClock = false,
  }) sync* {
    if (alerts.isEmpty) return;
    final cityData = calendar_location.getCityData(city);
    final location = tz.getLocation(
      cityData?['timezone'] as String? ?? 'Asia/Jerusalem',
    );
    final today = DateTime(now.year, now.month, now.day);
    final timePattern = RegExp(
      '^\u2066?'
      r'(\d{1,2}):(\d{2})',
    );

    for (final entry in alerts.entries) {
      final timeId = entry.key;
      final pref = entry.value;
      for (int i = 0; i <= zmanScheduleDaysAhead; i++) {
        final d = DateTime(today.year, today.month, today.day + i);
        final timeStr = zmanim_helpers.calculateDailyTimes(d, city)[timeId];
        if (timeStr == null) continue;
        // מחלצים שעה:דקה תוך התעלמות מעטיפת ה-LTR isolate (\u2066) ומסימן
        // השניות (`.`/`:`) שבסוף.
        final match = timePattern.firstMatch(timeStr);
        if (match == null) continue;
        final eventDt = tz.TZDateTime(
          location,
          d.year,
          d.month,
          d.day,
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
        );
        if (NotificationService.resolveScheduleTime(
              eventDate: eventDt,
              reminderMinutes: pref.minutesBefore,
              now: now,
            ) ==
            null) {
          continue;
        }
        final shownTime = zmanim_helpers
            .zmanTimeForDisplay(
              timeStr.replaceFirst(RegExp('[.:](?=\u2069)'), ''),
              twelveHourClock: twelveHourClock,
            )
            .replaceAll(RegExp('[\u2066\u2069]'), '');
        yield PlannedAlert(
          id: zmanNotificationId(timeId, d),
          title: 'תזכורת: ${pref.displayName}',
          body:
              'בעוד ${formatMinutesBefore(pref.minutesBefore)} ${pref.displayName} ($shownTime)',
          eventDate: eventDt,
          reminderMinutes: pref.minutesBefore,
          soundEnabled: true,
        );
      }
    }
  }

  static int zmanNotificationId(String timeId, DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$timeId|$y$m$d'.hashCode & 0x7fffffff;
  }

  static String formatMinutesBefore(int minutes) {
    if (minutes <= 0) return 'עכשיו';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '$h שעות ו-$m דקות';
    if (h > 0) return '$h שעות';
    return '$m דקות';
  }
}
