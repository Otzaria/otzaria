import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';

enum RecurrenceType {
  none,
  weekly,
  monthlyHebrew,
  monthlyGregorian,
  annualHebrew,
  annualGregorian,
}

/// אורך המחזור המזערי בימים לכל סוג חזרה — טווח אירוע חוזר חייב להיות קצר ממנו.
int minRecurrencePeriodDays(RecurrenceType type) {
  return switch (type) {
    RecurrenceType.weekly => 7,
    RecurrenceType.monthlyGregorian => 28,
    RecurrenceType.monthlyHebrew => 29,
    RecurrenceType.annualGregorian => 365,
    RecurrenceType.annualHebrew => 353,
    RecurrenceType.none => 0,
  };
}

/// ממיין אירועים בתוך יום אחד: אירועים ללא שעה תחילה, אחריהם לפי שעה עולה,
/// ולבסוף לפי כותרת כשובר-שוויון.
int compareCalendarEventsByTime(CustomEvent a, CustomEvent b) {
  final timeA = a.eventTime;
  final timeB = b.eventTime;
  if (timeA == null || timeB == null) {
    if (timeA == null && timeB == null) return a.title.compareTo(b.title);
    return timeA == null ? -1 : 1;
  }
  final diff =
      (timeA.hour * 60 + timeA.minute) - (timeB.hour * 60 + timeB.minute);
  return diff != 0 ? diff : a.title.compareTo(b.title);
}

/// ממיין אירועים לפי תאריך הבסיס ואז לפי שעה — לרשימות שחורגות מיום בודד.
int compareCalendarEventsChronologically(CustomEvent a, CustomEvent b) {
  final dateDiff =
      DateTime(
        a.baseGregorianDate.year,
        a.baseGregorianDate.month,
        a.baseGregorianDate.day,
      ).compareTo(
        DateTime(
          b.baseGregorianDate.year,
          b.baseGregorianDate.month,
          b.baseGregorianDate.day,
        ),
      );
  return dateDiff != 0 ? dateDiff : compareCalendarEventsByTime(a, b);
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
  /// סוף טווח הימים של האירוע (המופע הראשון באירוע חוזר). null = יום אחד.
  final DateTime? endGregorianDate;

  /// מועד הפסקת החזרה (UNTIL) באירוע חוזר; null = לפי recurringYears או לתמיד.
  final DateTime? recurrenceEndDate;
  final TimeOfDay? endTime;
  final String? googleColorId;
  final int? inheritedColorIndex;
  // אינדקס לפלטת CalendarEventColors; null = ללא צבע מיוחד
  final int? colorIndex;

  int? get displayColorIndex => colorIndex ?? inheritedColorIndex;
  // דקות לפני האירוע להצגת ההתראה. null = השתמש בהגדרה הגלובלית.
  final int? notificationMinutes;

  /// מזהה מנוי ה-ICS שממנו יובא האירוע; null = אירוע רגיל / ייבוא מקובץ.
  final String? icsSourceId;

  bool get recurring => recurrenceType != RecurrenceType.none;
  bool get recurOnHebrew =>
      recurrenceType == RecurrenceType.annualHebrew ||
      recurrenceType == RecurrenceType.monthlyHebrew;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// האם האירוע חל בתאריך הנתון — כולל טווח רב-יומי, חזרתיות וסוף חזרה.
  bool occursOn(DateTime date) {
    final current = _dateOnly(date);
    final start = _dateOnly(baseGregorianDate);
    final durationDays = endGregorianDate == null
        ? 0
        : _dateOnly(endGregorianDate!).difference(start).inDays.clamp(0, 366);

    if (recurrenceType == RecurrenceType.none) {
      return !current.isBefore(start) &&
          current.difference(start).inDays <= durationDays;
    }

    if (current.isBefore(start)) return false;
    // מחפשים תחילת מופע שהתאריך הנוכחי בתוך טווח הימים שלו.
    for (var back = 0; back <= durationDays; back++) {
      final day = addCalendarDays(current, -back);
      if (day.isBefore(start)) break;
      if (_isOccurrenceStart(day) && _occurrenceInEffect(day)) return true;
    }
    return false;
  }

  /// האם מופע של האירוע החוזר מתחיל בתאריך הנתון.
  bool startsOccurrenceOn(DateTime date) {
    final day = _dateOnly(date);
    return !day.isBefore(_dateOnly(baseGregorianDate)) &&
        _isOccurrenceStart(day) &&
        _occurrenceInEffect(day);
  }

  bool _isOccurrenceStart(DateTime day) {
    switch (recurrenceType) {
      case RecurrenceType.weekly:
        return day.weekday == baseGregorianDate.weekday;
      case RecurrenceType.monthlyGregorian:
        return day.day == baseGregorianDate.day;
      case RecurrenceType.annualGregorian:
        return day.month == baseGregorianDate.month &&
            day.day == baseGregorianDate.day;
      case RecurrenceType.monthlyHebrew:
        return JewishDate.fromDateTime(day).getJewishDayOfMonth() ==
            baseJewishDay;
      case RecurrenceType.annualHebrew:
        final jd = JewishDate.fromDateTime(day);
        return jd.getJewishMonth() == baseJewishMonth &&
            jd.getJewishDayOfMonth() == baseJewishDay;
      case RecurrenceType.none:
        return false;
    }
  }

  bool _occurrenceInEffect(DateTime occurrenceStart) {
    if (recurrenceEndDate != null &&
        occurrenceStart.isAfter(_dateOnly(recurrenceEndDate!))) {
      return false;
    }
    final years = recurringYears;
    if (years == null || years <= 0) return true;
    if (recurOnHebrew) {
      return JewishDate.fromDateTime(occurrenceStart).getJewishYear() <
          baseJewishYear + years;
    }
    return occurrenceStart.year < baseGregorianDate.year + years;
  }

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
    this.recurrenceEndDate,
    this.endTime,
    this.googleColorId,
    this.inheritedColorIndex,
    this.colorIndex,
    this.notificationMinutes,
    this.icsSourceId,
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
    ValueGetter<int?>? recurringYears,
    String? googleEventId,
    ValueGetter<TimeOfDay?>? eventTime,
    // עטוף ב-ValueGetter כדי לאפשר איפוס מפורש ל-null (לביטול טווח)
    ValueGetter<DateTime?>? endGregorianDate,
    ValueGetter<DateTime?>? recurrenceEndDate,
    ValueGetter<TimeOfDay?>? endTime,
    ValueGetter<String?>? googleColorId,
    ValueGetter<int?>? inheritedColorIndex,
    // עטוף ב-ValueGetter כדי לאפשר איפוס מפורש ל-null (הסרת צבע)
    ValueGetter<int?>? colorIndex,
    int? notificationMinutes,
    String? icsSourceId,
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
      recurringYears: recurringYears != null
          ? recurringYears()
          : this.recurringYears,
      googleEventId: googleEventId ?? this.googleEventId,
      eventTime: eventTime != null ? eventTime() : this.eventTime,
      endGregorianDate: endGregorianDate != null
          ? endGregorianDate()
          : this.endGregorianDate,
      recurrenceEndDate: recurrenceEndDate != null
          ? recurrenceEndDate()
          : this.recurrenceEndDate,
      endTime: endTime != null ? endTime() : this.endTime,
      googleColorId: googleColorId != null
          ? googleColorId()
          : this.googleColorId,
      inheritedColorIndex: inheritedColorIndex != null
          ? inheritedColorIndex()
          : this.inheritedColorIndex,
      colorIndex: colorIndex != null ? colorIndex() : this.colorIndex,
      notificationMinutes: notificationMinutes ?? this.notificationMinutes,
      icsSourceId: icsSourceId ?? this.icsSourceId,
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
      'recurrenceEndDate': recurrenceEndDate?.millisecondsSinceEpoch,
      'endTime': endTime != null
          ? {'hour': endTime!.hour, 'minute': endTime!.minute}
          : null,
      'googleColorId': googleColorId,
      'inheritedColorIndex': inheritedColorIndex,
      'colorIndex': colorIndex,
      'notificationMinutes': notificationMinutes,
      'icsSourceId': icsSourceId,
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
    DateTime? endGregorianDate = endMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(endMillis)
        : null;
    final recurrenceEndMillis = json['recurrenceEndDate'] as int?;
    DateTime? recurrenceEndDate = recurrenceEndMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(recurrenceEndMillis)
        : null;
    // הגירה מפורמט ישן שבו endGregorianDate שימש כסוף החזרה באירוע חוזר.
    // טווח קצר מהמחזור נועד כמשך האירוע ולכן נשאר כטווח.
    if (!json.containsKey('recurrenceEndDate') &&
        type != RecurrenceType.none &&
        endGregorianDate != null) {
      final base = DateTime.fromMillisecondsSinceEpoch(
        json['baseGregorianDate'] as int,
      );
      final span = DateTime(
        endGregorianDate.year,
        endGregorianDate.month,
        endGregorianDate.day,
      ).difference(DateTime(base.year, base.month, base.day)).inDays;
      if (span >= minRecurrencePeriodDays(type)) {
        recurrenceEndDate = endGregorianDate;
        endGregorianDate = null;
      }
    }
    TimeOfDay? endTime;
    if (json['endTime'] case final Map<String, dynamic> timeMap) {
      endTime = TimeOfDay(
        hour: timeMap['hour'] as int,
        minute: timeMap['minute'] as int,
      );
    }

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
      endGregorianDate: endGregorianDate,
      recurrenceEndDate: recurrenceEndDate,
      endTime: endTime,
      googleColorId: json['googleColorId'] as String?,
      inheritedColorIndex: json['inheritedColorIndex'] as int?,
      colorIndex: json['colorIndex'] as int?,
      notificationMinutes: json['notificationMinutes'] as int?,
      icsSourceId: json['icsSourceId'] as String?,
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
    recurrenceEndDate,
    endTime,
    googleColorId,
    inheritedColorIndex,
    colorIndex,
    notificationMinutes,
    icsSourceId,
  ];
}

/// A new unique id for a calendar event.
String generateCalendarEventId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final random = Random().nextInt(0x7FFFFFFF);
  return 'otzaria_${timestamp}_$random';
}
