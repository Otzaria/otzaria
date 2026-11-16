import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:timezone/timezone.dart' as tz;

/// מנוי ליומן חיצוני בפורמט ICS (קישור שמתרענן).
class IcsSubscription extends Equatable {
  final String id;
  final String name;
  final String url;
  final DateTime? lastRefresh;

  const IcsSubscription({
    required this.id,
    required this.name,
    required this.url,
    this.lastRefresh,
  });

  IcsSubscription copyWith({DateTime? lastRefresh}) {
    return IcsSubscription(
      id: id,
      name: name,
      url: url,
      lastRefresh: lastRefresh ?? this.lastRefresh,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'lastRefresh': lastRefresh?.millisecondsSinceEpoch,
  };

  static IcsSubscription? fromJson(dynamic json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final url = json['url'];
    if (id is! String || name is! String || url is! String) return null;
    final lastRefreshMillis = json['lastRefresh'];
    return IcsSubscription(
      id: id,
      name: name,
      url: url,
      lastRefresh: lastRefreshMillis is int
          ? DateTime.fromMillisecondsSinceEpoch(lastRefreshMillis)
          : null,
    );
  }

  /// מפענח רשימת מנויים מ-JSON. פריט פגום מדולג ולא מפיל את השאר.
  static List<IcsSubscription> listFromJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! List) return const [];
      return decoded.map(fromJson).whereType<IcsSubscription>().toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  List<Object?> get props => [id, name, url, lastRefresh];
}

/// ייבוא יומנים בפורמט iCalendar (ICS) — מקובץ או מקישור.
///
/// תומך ב-VEVENT: תאריכים (יום שלם / עם שעה, UTC / TZID), טווח רב-יומי,
/// חזרתיות בסיסית (RRULE שבועי/חודשי/שנתי + UNTIL) וטקסט עם escaping.
class IcsCalendarService {
  static const Duration _fetchTimeout = Duration(seconds: 20);
  static const int _maxIcsBytes = 5 * 1024 * 1024;

  IcsCalendarService({Future<String> Function(Uri uri)? httpFetcher})
    : _httpFetcher = httpFetcher ?? _defaultFetch;

  final Future<String> Function(Uri uri) _httpFetcher;

  /// מוריד קובץ ICS מהקישור. זורק [FormatException] אם התוכן אינו יומן.
  Future<String> fetchIcs(String url) async {
    var normalized = url.trim();
    if (normalized.startsWith('webcal://')) {
      normalized = 'https://${normalized.substring('webcal://'.length)}';
    }
    final body = await _httpFetcher(Uri.parse(normalized));
    if (!body.contains('BEGIN:VCALENDAR')) {
      throw const FormatException('הקישור לא החזיר קובץ יומן (ICS) תקין');
    }
    return body;
  }

  static Future<String> _defaultFetch(Uri uri) async {
    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(_fetchTimeout);
      if (response.statusCode != 200) {
        throw Exception('שגיאת רשת (HTTP ${response.statusCode})');
      }
      if (response.contentLength != null &&
          response.contentLength! > _maxIcsBytes) {
        throw const FormatException('קובץ היומן גדול מדי');
      }

      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(_fetchTimeout)) {
        if (bytes.length + chunk.length > _maxIcsBytes) {
          throw const FormatException('קובץ היומן גדול מדי');
        }
        bytes.add(chunk);
      }
      return utf8.decode(bytes.takeBytes(), allowMalformed: true);
    } finally {
      client.close();
    }
  }

  /// מפענח תוכן ICS לאירועי לוח שנה.
  ///
  /// [sourceId] — מזהה מנוי; אירועי מנוי מתויגים בו כדי שרענון יחליף אותם.
  /// null = ייבוא חד-פעמי מקובץ. אירוע פגום מדולג ולא מפיל את השאר.
  static List<CustomEvent> parseIcs(String icsText, {String? sourceId}) {
    final lines = _unfoldLines(icsText.replaceFirst('\ufeff', ''));
    final events = <CustomEvent>[];
    Map<String, _IcsProperty>? current;

    for (final line in lines) {
      if (line == 'BEGIN:VEVENT') {
        current = {};
        continue;
      }
      if (line == 'END:VEVENT') {
        if (current != null) {
          try {
            final event = _buildEvent(current, sourceId: sourceId);
            if (event != null) events.add(event);
          } catch (e) {
            debugPrint('[IcsCalendar] skipping malformed event: $e');
          }
        }
        current = null;
        continue;
      }
      if (current == null) continue;
      final prop = _IcsProperty.parse(line);
      if (prop != null) current.putIfAbsent(prop.name, () => prop);
    }
    return events;
  }

  static CustomEvent? _buildEvent(
    Map<String, _IcsProperty> props, {
    String? sourceId,
  }) {
    if (props['STATUS']?.value.toUpperCase() == 'CANCELLED') return null;

    final start = _parseIcsDateTime(props['DTSTART']);
    if (start == null) return null;
    final end = _parseIcsDateTime(props['DTEND']);

    final date = DateTime(start.value.year, start.value.month, start.value.day);
    final jewishDate = JewishDate.fromDateTime(date);

    DateTime? endDate;
    if (end != null) {
      // באירוע יום-שלם ה-DTEND בלעדי (היום שאחרי) — כמו בגוגל.
      final inclusiveEnd = end.dateOnly
          ? DateTime(end.value.year, end.value.month, end.value.day - 1)
          : DateTime(end.value.year, end.value.month, end.value.day);
      if (inclusiveEnd.isAfter(date)) endDate = inclusiveEnd;
    }

    final recurrence = _parseSupportedRecurrence(props['RRULE']?.value ?? '');
    if (recurrence == null) return null;
    // המודל שומר ימים ושעה מקומיים בלבד, בלי אזור זמן לכל מופע חוזר.
    if (recurrence.weeklyDays != null &&
        !start.dateOnly &&
        (props['DTSTART']!.value.endsWith('Z') ||
            props['DTSTART']!.params.containsKey('TZID'))) {
      return null;
    }

    final summary = _unescapeText(props['SUMMARY']?.value ?? '');
    final uid = props['UID']?.value ?? '';
    final key = uid.isNotEmpty
        ? uid
        : 'noid_${'${props['DTSTART']?.value}|$summary'.hashCode & 0x7fffffff}';

    return CustomEvent(
      id: 'ics_${_sanitizeIdPart(sourceId ?? 'file')}_${_sanitizeIdPart(key)}',
      title: summary.isEmpty ? 'אירוע ללא כותרת' : summary,
      description: _unescapeText(props['DESCRIPTION']?.value ?? ''),
      createdAt: DateTime.now(),
      baseGregorianDate: date,
      baseJewishYear: jewishDate.getJewishYear(),
      baseJewishMonth: jewishDate.getJewishMonth(),
      baseJewishDay: jewishDate.getJewishDayOfMonth(),
      recurrenceType: recurrence.type,
      weeklyDays: recurrence.weeklyDays,
      recurrenceEndDate: recurrence.endDate,
      eventTime: start.dateOnly
          ? null
          : TimeOfDay(hour: start.value.hour, minute: start.value.minute),
      endGregorianDate: endDate,
      endTime: start.dateOnly || end == null || end.dateOnly
          ? null
          : TimeOfDay(hour: end.value.hour, minute: end.value.minute),
      icsSourceId: sourceId,
    );
  }

  static _IcsDateTime? _parseIcsDateTime(_IcsProperty? prop) {
    if (prop == null) return null;
    final raw = prop.value.trim();

    final dateOnlyMatch = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(raw);
    if (dateOnlyMatch != null || prop.params['VALUE'] == 'DATE') {
      final m =
          dateOnlyMatch ?? RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(raw);
      if (m == null) return null;
      return _IcsDateTime(
        DateTime(
          int.parse(m.group(1)!),
          int.parse(m.group(2)!),
          int.parse(m.group(3)!),
        ),
        dateOnly: true,
      );
    }

    final m = RegExp(
      r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$',
    ).firstMatch(raw);
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final h = int.parse(m.group(4)!);
    final mi = int.parse(m.group(5)!);
    final s = int.parse(m.group(6)!);

    if (m.group(7) == 'Z') {
      return _IcsDateTime(DateTime.utc(y, mo, d, h, mi, s).toLocal());
    }
    final tzid = prop.params['TZID'];
    if (tzid != null && tzid.isNotEmpty) {
      try {
        final location = tz.getLocation(tzid);
        return _IcsDateTime(
          tz.TZDateTime(location, y, mo, d, h, mi, s).toLocal(),
        );
      } catch (_) {
        // TZID לא מוכר — מתייחסים לשעה כשעה מקומית
      }
    }
    return _IcsDateTime(DateTime(y, mo, d, h, mi, s));
  }

  /// מאחה שורות מקופלות — שורת המשך מתחילה ברווח או בטאב (RFC 5545).
  static List<String> _unfoldLines(String text) {
    final rawLines = text.split(RegExp(r'\r\n|\n|\r'));
    final result = <String>[];
    for (final line in rawLines) {
      if ((line.startsWith(' ') || line.startsWith('\t')) &&
          result.isNotEmpty) {
        result[result.length - 1] += line.substring(1);
      } else {
        result.add(line);
      }
    }
    return result;
  }

  static String _unescapeText(String value) {
    return value.replaceAllMapped(RegExp(r'\\(.)'), (m) {
      final c = m.group(1)!;
      return (c == 'n' || c == 'N') ? '\n' : c;
    });
  }

  /// מזהי אירועים חייבים להישאר ללא ':' — מזהה עם ':' נחשב אירוע plugin
  /// ונמחק ברענון (ראה CalendarCubit.refreshPluginEvents).
  static String _sanitizeIdPart(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_@.\-]'), '_');
  }

  static _IcsRecurrence? _parseSupportedRecurrence(String raw) {
    if (raw.trim().isEmpty) return const _IcsRecurrence(RecurrenceType.none);

    final parts = <String, String>{};
    for (final part in raw.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) return null;
      final key = part.substring(0, separator).toUpperCase();
      final value = part.substring(separator + 1).toUpperCase();
      if (parts.containsKey(key)) return null;
      parts[key] = value;
    }

    const supportedKeys = {'FREQ', 'UNTIL', 'INTERVAL', 'WKST', 'BYDAY'};
    if (!parts.keys.every(supportedKeys.contains) ||
        (parts['INTERVAL'] != null && parts['INTERVAL'] != '1')) {
      return null;
    }

    final type = switch (parts['FREQ']) {
      'WEEKLY' => RecurrenceType.weekly,
      'MONTHLY' => RecurrenceType.monthlyGregorian,
      'YEARLY' => RecurrenceType.annualGregorian,
      _ => null,
    };
    if (type == null) return null;
    // BYDAY is supported only for weekly rules, without ordinal prefixes.
    if (parts.containsKey('BYDAY') && type != RecurrenceType.weekly) {
      return null;
    }
    final days = parseCalendarWeekdays(parts['BYDAY']);
    if (parts.containsKey('BYDAY') && days == null) return null;

    final until = parts['UNTIL'];
    if (until == null) return _IcsRecurrence(type, weeklyDays: days);
    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(?:T\d{6}Z?)?$',
    ).firstMatch(until);
    if (match == null) return null;
    return _IcsRecurrence(
      type,
      weeklyDays: days,
      endDate: DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      ),
    );
  }
}

class _IcsRecurrence {
  final RecurrenceType type;
  final List<int>? weeklyDays;
  final DateTime? endDate;

  const _IcsRecurrence(this.type, {this.weeklyDays, this.endDate});
}

class _IcsDateTime {
  final DateTime value;
  final bool dateOnly;
  const _IcsDateTime(this.value, {this.dateOnly = false});
}

class _IcsProperty {
  final String name;
  final Map<String, String> params;
  final String value;

  const _IcsProperty(this.name, this.params, this.value);

  /// מפרק שורת ICS לשם, פרמטרים וערך. ':' בתוך פרמטר מצוטט אינו מפריד.
  static _IcsProperty? parse(String line) {
    var inQuotes = false;
    var separator = -1;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') inQuotes = !inQuotes;
      if (c == ':' && !inQuotes) {
        separator = i;
        break;
      }
    }
    if (separator <= 0) return null;

    final head = line.substring(0, separator);
    final value = line.substring(separator + 1);
    final headParts = head.split(';');
    final params = <String, String>{};
    for (final part in headParts.skip(1)) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      params[part.substring(0, eq).toUpperCase()] = part
          .substring(eq + 1)
          .replaceAll('"', '');
    }
    return _IcsProperty(headParts.first.toUpperCase(), params, value);
  }
}
