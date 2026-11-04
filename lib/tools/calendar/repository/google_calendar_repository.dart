import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/theme/calendar_event_colors.dart';
import 'package:otzaria/tools/calendar/models/calendar_event.dart';
import 'package:otzaria/tools/calendar/services/google_calendar_service.dart';
import 'package:timezone/timezone.dart' as tz;

/// Thrown when fetching events fails after an authorized client was obtained.
class GoogleCalendarSyncException implements Exception {
  GoogleCalendarSyncException(this.cause);

  final Object cause;

  @override
  String toString() => '$cause';
}

/// Google Calendar access for the calendar: the API calls, and the conversion
/// between Google events and [CustomEvent].
class GoogleCalendarRepository {
  GoogleCalendarRepository(this._service);

  final GoogleCalendarService _service;

  static const String _primaryGoogleCalendarId = 'primary';

  /// בלי חסם, חיבור תקוע ברשת מסוננת משאיר את הסנכרון "בתהליך" לעד.
  static const Duration _apiTimeout = Duration(seconds: 20);

  Future<bool> isSignedIn() => _service.isSignedIn();

  Future<void> signOut() => _service.signOut();

  /// Whether an authorized client is available. Errors while obtaining it
  /// propagate to the caller.
  Future<bool> canConnect({required bool interactive}) async {
    final apiClient = await _service.getApiClient(interactive: interactive);
    if (apiClient == null) return false;
    apiClient.close();
    return true;
  }

  Future<List<GoogleCalendarInfo>> listCalendars() async {
    final apiClient = await _service.getApiClient(interactive: true);
    if (apiClient == null) return [];

    try {
      final calendarList = await apiClient.api.calendarList.list().timeout(
        _apiTimeout,
      );
      final calendars = <GoogleCalendarInfo>[];

      for (final item in calendarList.items ?? []) {
        if (item.id != null && item.summary != null) {
          calendars.add(
            GoogleCalendarInfo(
              id: item.id!,
              name: item.summary!,
              isPrimary: item.primary ?? false,
            ),
          );
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

  /// ממזג אירועים מהלוחות שנבחרו בטווח [timeMin]–[timeMax].
  /// הבחירה והאירועים המקומיים נקראים אחרי קבלת ההרשאה וטעינת צבעי הלוחות.
  Future<List<CustomEvent>?> fetchEvents({
    required List<CustomEvent> Function() existingEvents,
    required List<String> Function() calendarIds,
    required DateTime timeMin,
    required DateTime timeMax,
    required bool interactive,
  }) async {
    final apiClient = await _service.getApiClient(interactive: interactive);
    if (apiClient == null) return null;

    try {
      final calendarColorIndices = await _loadGoogleCalendarColorIndices(
        apiClient.api,
      );
      final merger = _GoogleEventsMerger(
        existing: existingEvents(),
        mapper: fromGoogleEvent,
      );

      // Fetch events from all selected calendars with pagination.
      var allCalendarsLoaded = true;
      for (final calendarId in calendarIds()) {
        try {
          String? pageToken;
          do {
            final result = await apiClient.api.events
                .list(
                  calendarId,
                  singleEvents: true,
                  // בלעדיו אירוע שנמחק בגוגל פשוט חסר, והעותק המקומי נשאר.
                  showDeleted: true,
                  orderBy: 'startTime',
                  timeMin: timeMin.toUtc(),
                  timeMax: timeMax.toUtc(),
                  maxResults: 2500, // Google's max per request
                  pageToken: pageToken,
                )
                .timeout(_apiTimeout);
            merger.mergePage(
              result.items ?? const [],
              calendarId: calendarId,
              inheritedColorIndex: calendarColorIndices[calendarId],
            );
            pageToken = result.nextPageToken;
          } while (pageToken != null);
        } catch (e) {
          allCalendarsLoaded = false;
          // Continue with other calendars if one fails
          debugPrint('Failed to sync calendar $calendarId: $e');
        }
      }
      // עותק פעיל עשוי להיות בלוח או בדף שנכשל; דוחים רק את המחיקות.
      if (!allCalendarsLoaded) return merger.events;
      for (final MapEntry(key: series, value: calendarId)
          in merger.seriesToCheck.entries) {
        try {
          final master = await apiClient.api.events
              .get(calendarId, series)
              .timeout(_apiTimeout);
          if (master.status == 'cancelled') merger.deletedSeries.add(series);
        } catch (e) {
          debugPrint('Failed to check Google series $series: $e');
        }
      }
      return merger.merged;
    } catch (e) {
      throw GoogleCalendarSyncException(e);
    } finally {
      apiClient.close();
    }
  }

  /// Creates or updates [event] in the primary calendar and returns its
  /// Google id, or null when it could not be written.
  Future<String?> upsertEvent(CustomEvent event, String timeZoneId) async {
    final apiClient = await _service.getApiClient(interactive: false);
    if (apiClient == null) return null;

    try {
      final googleEvent = toGoogleEvent(event, timeZoneId);

      if (event.googleEventId == null || event.googleEventId!.isEmpty) {
        // timeout לא מבטל יצירה בשרת; איבוד המזהה גורם ליצירה כפולה בעריכה.
        final created = await apiClient.api.events.insert(
          googleEvent,
          _primaryGoogleCalendarId,
        );
        return created.id;
      } else {
        final updated = await apiClient.api.events
            .update(googleEvent, _primaryGoogleCalendarId, event.googleEventId!)
            .timeout(_apiTimeout);
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

  Future<void> deleteEvent(CustomEvent event) async {
    if (event.googleEventId == null || event.googleEventId!.isEmpty) return;

    final apiClient = await _service.getApiClient(interactive: false);
    if (apiClient == null) return;

    try {
      await apiClient.api.events
          .delete(_primaryGoogleCalendarId, event.googleEventId!)
          .timeout(_apiTimeout);
    } catch (e) {
      debugPrint('Failed to delete Google event: $e');
      // Ignore delete failures to avoid blocking local delete
    } finally {
      apiClient.close();
    }
  }

  Future<Map<String, int>> _loadGoogleCalendarColorIndices(
    cal.CalendarApi api,
  ) async {
    final colors = <String, int>{};
    try {
      String? pageToken;
      do {
        final page = await api.calendarList
            .list(pageToken: pageToken)
            .timeout(_apiTimeout);
        for (final calendar in page.items ?? []) {
          final id = calendar.id;
          final color = CalendarEventColors.indexForGoogleColorHex(
            calendar.backgroundColor,
          );
          if (id != null && color != null) colors[id] = color;
        }
        pageToken = page.nextPageToken;
      } while (pageToken != null);
    } catch (error) {
      debugPrint('Failed to load Google calendar colors: $error');
    }
    return colors;
  }

  @visibleForTesting
  List<CustomEvent> mergeGoogleEventPages(
    List<CustomEvent> existing,
    Iterable<List<cal.Event>> pages, {
    int? inheritedColorIndex,
  }) {
    final merger = _GoogleEventsMerger(
      existing: existing,
      mapper: fromGoogleEvent,
    );
    for (final page in pages) {
      merger.mergePage(
        page,
        calendarId: _primaryGoogleCalendarId,
        inheritedColorIndex: inheritedColorIndex,
      );
    }
    return merger.merged;
  }

  @visibleForTesting
  CustomEvent? fromGoogleEvent(
    cal.Event gEvent, {
    int? inheritedColorIndex,
  }) {
    final start = gEvent.start?.dateTime ?? gEvent.start?.date;
    if (start == null) return null;

    final date = DateTime(start.year, start.month, start.day);
    final jewishDate = JewishDate.fromDateTime(date);
    final otzariaId = gEvent.extendedProperties?.private?['otzaria_event_id'];

    final isAllDay =
        gEvent.start?.date != null && gEvent.start?.dateTime == null;
    DateTime? endDate;
    final rawEnd = gEvent.end?.dateTime ?? gEvent.end?.date;
    if (rawEnd != null) {
      // באירוע יום-שלם ה-end של גוגל בלעדי (day after).
      final inclusiveEnd = isAllDay
          ? DateTime(rawEnd.year, rawEnd.month, rawEnd.day - 1)
          : DateTime(rawEnd.year, rawEnd.month, rawEnd.day);
      if (inclusiveEnd.isAfter(date)) {
        endDate = inclusiveEnd;
      }
    }

    RecurrenceType recurrenceType = RecurrenceType.none;
    final recurrenceRule = gEvent.recurrence?.isNotEmpty == true
        ? gEvent.recurrence!.first
        : null;

    if (recurrenceRule != null) {
      if (recurrenceRule.contains('FREQ=WEEKLY')) {
        recurrenceType = RecurrenceType.weekly;
      } else if (recurrenceRule.contains('FREQ=MONTHLY')) {
        // Check for Hebrew monthly marker
        if (recurrenceRule.contains('X-OTZARIA-TYPE=otzaria_hebrew_monthly')) {
          recurrenceType = RecurrenceType.monthlyHebrew;
        } else {
          recurrenceType = RecurrenceType.monthlyGregorian;
        }
      } else if (recurrenceRule.contains('FREQ=YEARLY')) {
        // Check for Hebrew yearly marker
        if (recurrenceRule.contains('X-OTZARIA-TYPE=otzaria_hebrew_yearly')) {
          recurrenceType = RecurrenceType.annualHebrew;
        } else {
          recurrenceType = RecurrenceType.annualGregorian;
        }
      }
    }

    return CustomEvent(
      id: otzariaId ?? gEvent.id ?? generateCalendarEventId(),
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
      eventTime: isAllDay
          ? null
          : TimeOfDay(hour: start.hour, minute: start.minute),
      endGregorianDate: endDate,
      recurrenceEndDate: recurrenceType == RecurrenceType.none
          ? null
          : _parseGoogleRecurrenceEnd(recurrenceRule),
      endTime: isAllDay || rawEnd == null
          ? null
          : TimeOfDay(hour: rawEnd.hour, minute: rawEnd.minute),
      colorIndex: CalendarEventColors.indexForGoogleColorId(gEvent.colorId),
      inheritedColorIndex: gEvent.colorId == null ? inheritedColorIndex : null,
      googleColorId: gEvent.colorId,
    );
  }

  DateTime? _parseGoogleRecurrenceEnd(String? recurrenceRule) {
    final match = RegExp(
      r'(?:^|;)UNTIL=(\d{8})',
    ).firstMatch(recurrenceRule ?? '');
    if (match == null) return null;
    final date = match.group(1)!;
    return DateTime(
      int.parse(date.substring(0, 4)),
      int.parse(date.substring(4, 6)),
      int.parse(date.substring(6, 8)),
    );
  }

  @visibleForTesting
  cal.Event toGoogleEvent(CustomEvent event, String timeZoneId) {
    final baseDate = event.baseGregorianDate;
    final startDate = DateTime(baseDate.year, baseDate.month, baseDate.day);
    final isTimed = event.eventTime != null;
    final lastDay = event.endGregorianDate != null
        ? DateTime(
            event.endGregorianDate!.year,
            event.endGregorianDate!.month,
            event.endGregorianDate!.day,
          )
        : startDate;

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
      ..start = _googleEventDateTime(
        date: startDate,
        time: event.eventTime,
        timeZoneId: timeZoneId,
      )
      ..end = _googleEventDateTime(
        date: isTimed
            ? lastDay
            : DateTime(lastDay.year, lastDay.month, lastDay.day + 1),
        time: event.endTime,
        timeZoneId: timeZoneId,
        fallbackStartTime: event.eventTime,
        moveToNextDayWhenEarlier:
            isTimed && DateUtils.isSameDay(lastDay, startDate),
      )
      ..extendedProperties = (cal.EventExtendedProperties()
        ..private = extendedProps);

    googleEvent.colorId =
        event.googleColorId ??
        CalendarEventColors.googleColorIdForIndex(event.colorIndex);

    final recurrence = _googleRecurrenceRule(event);
    if (recurrence != null) {
      googleEvent.recurrence = [recurrence];
    }

    return googleEvent;
  }

  cal.EventDateTime _googleEventDateTime({
    required DateTime date,
    required String timeZoneId,
    TimeOfDay? time,
    TimeOfDay? fallbackStartTime,
    bool moveToNextDayWhenEarlier = false,
  }) {
    final value = cal.EventDateTime()..timeZone = timeZoneId;
    if (time == null && fallbackStartTime == null) {
      value.date = date;
      return value;
    }

    final resolvedTime =
        time ??
        TimeOfDay(
          hour: (fallbackStartTime!.hour + 1) % 24,
          minute: fallbackStartTime.minute,
        );
    final location = tz.getLocation(timeZoneId);
    final movesToNextDay =
        moveToNextDayWhenEarlier &&
        (resolvedTime.hour * 60 + resolvedTime.minute) <=
            (fallbackStartTime!.hour * 60 + fallbackStartTime.minute);
    value.dateTime = tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day + (movesToNextDay ? 1 : 0),
      resolvedTime.hour,
      resolvedTime.minute,
    );
    return value;
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

    final recurrenceEnd =
        event.recurrenceEndDate ??
        (event.recurringYears != null && event.recurringYears! > 0
            ? DateTime(
                event.baseGregorianDate.year + event.recurringYears!,
                event.baseGregorianDate.month,
                event.baseGregorianDate.day,
              )
            : null);
    if (recurrenceEnd != null) {
      final until = DateTime(
        recurrenceEnd.year,
        recurrenceEnd.month,
        recurrenceEnd.day,
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
}

typedef _GoogleEventMapper =
    CustomEvent? Function(cal.Event event, {int? inheritedColorIndex});

class _GoogleEventsMerger {
  _GoogleEventsMerger({
    required List<CustomEvent> existing,
    required this.mapper,
  }) : events = List<CustomEvent>.from(existing) {
    for (var index = 0; index < events.length; index++) {
      final event = events[index];
      _byLocalId[event.id] = index;
      final googleId = event.googleEventId;
      if (googleId != null && googleId.isNotEmpty) {
        _byGoogleId[googleId] = index;
      }
    }
  }

  final _GoogleEventMapper mapper;
  final List<CustomEvent> events;
  final Map<String, int> _byGoogleId = {};
  final Map<String, int> _byLocalId = {};
  final Set<String> _cancelledGoogleIds = {};
  final Set<String> _activeGoogleIds = {};
  final Map<String, String> _seriesOfCancelled = {};
  final Map<String, String> _calendarOfCancelledSeries = {};
  final Set<String> _activeSeries = {};

  /// סדרות שאירוע האב שלהן מבוטל בגוגל.
  final Set<String> deletedSeries = {};

  /// [events] בלי מה שנמחק בגוגל — אלא אם הוא עדיין קיים בלוח נבחר אחר.
  List<CustomEvent> get merged {
    final deleted = _cancelledGoogleIds.difference(_activeGoogleIds);
    if (deleted.isEmpty && deletedSeries.isEmpty) return events;
    return [
      for (final event in events)
        if (event.recurrenceType == RecurrenceType.none
            ? !deleted.contains(event.googleEventId)
            : !deletedSeries.contains(_cancelledSeriesOf(event)))
          event,
    ];
  }

  /// סדרה → לוח, לכל סדרה מקומית שכל מופעיה בטווח בוטלו: מופע מבוטל נראה
  /// אותו דבר כשנמחק מופע אחד וכשנמחקה הסדרה, ורק אירוע האב מכריע.
  Map<String, String> get seriesToCheck => {
    for (final series in events.map(_cancelledSeriesOf).nonNulls)
      series: _calendarOfCancelledSeries[series]!,
  };

  String? _cancelledSeriesOf(CustomEvent event) {
    if (event.recurrenceType == RecurrenceType.none) return null;
    final googleId = event.googleEventId;
    final series = _seriesOfCancelled[googleId] ?? googleId;
    if (series == null || _activeSeries.contains(series)) return null;
    return _calendarOfCancelledSeries.containsKey(series) ? series : null;
  }

  void mergePage(
    List<cal.Event> googleEvents, {
    required String calendarId,
    int? inheritedColorIndex,
  }) {
    for (final googleEvent in googleEvents) {
      final googleId = googleEvent.id ?? '';
      final series = googleEvent.recurringEventId;
      if (googleEvent.status == 'cancelled') {
        if (googleId.isNotEmpty) _cancelledGoogleIds.add(googleId);
        if (series != null) {
          _seriesOfCancelled[googleId] = series;
          _calendarOfCancelledSeries[series] = calendarId;
        }
        continue;
      }
      _activeGoogleIds.add(googleId);
      if (series != null) _activeSeries.add(series);

      final mapped = mapper(
        googleEvent,
        inheritedColorIndex: inheritedColorIndex,
      );
      if (mapped == null) continue;

      final localId =
          googleEvent.extendedProperties?.private?['otzaria_event_id'];
      final matchedIndex =
          (googleId.isNotEmpty ? _byGoogleId[googleId] : null) ??
          _byLocalId[localId];

      if (matchedIndex != null) {
        final existing = events[matchedIndex];
        events[matchedIndex] = existing.copyWith(
          title: mapped.title,
          description: mapped.description,
          baseGregorianDate: mapped.baseGregorianDate,
          baseJewishYear: mapped.baseJewishYear,
          baseJewishMonth: mapped.baseJewishMonth,
          baseJewishDay: mapped.baseJewishDay,
          googleEventId: googleId.isEmpty ? null : googleId,
          endGregorianDate: () => mapped.endGregorianDate,
          recurrenceEndDate: () => mapped.recurrenceEndDate,
          eventTime: () => mapped.eventTime,
          endTime: () => mapped.endTime,
          colorIndex: () => mapped.colorIndex,
          inheritedColorIndex: () => mapped.inheritedColorIndex,
          googleColorId: () => mapped.googleColorId,
        );
        if (googleId.isNotEmpty) _byGoogleId[googleId] = matchedIndex;
        continue;
      }

      events.add(mapped);
      final index = events.length - 1;
      _byLocalId[mapped.id] = index;
      if (googleId.isNotEmpty) _byGoogleId[googleId] = index;
    }
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
