import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';

/// PluginCalendarAdapter
///
/// ממיר records מסוג `calendar.event` שפורסמו על-ידי תוספים
/// (פורמט ה-spec: title, startsAt, source?, importance?, scope?, workspaceId?, bookId?)
/// ל-[CustomEvent] פנימי של אוצריא.
///
/// ### scope semantics (spec §published-data):
/// | scope               | מה זה אומר                     |
/// |---------------------|--------------------------------|
/// | `global`            | הצג תמיד בלוח                  |
/// | `workspace:<id>`    | הצג רק כשה-workspaceId תואם    |
/// | `book:<bookUid>`    | הצג רק כשה-bookUid/כותרת תואם  |
///
/// currentWorkspaceId / currentBookId מוזנקים מבחוץ (ראה [loadAndMergePluginEvents]).
class PluginCalendarAdapter {
  const PluginCalendarAdapter();

  /// טוען records מסוג calendar.event ומאחד עם [existingEvents].
  ///
  /// [currentWorkspaceId] — מזהה ה-workspace הנוכחי (אופציונלי, לסינון workspace-scope)
  /// [currentBookId]      — מזהה הספר הנוכחי (אופציונלי, לסינון book-scope)
  Future<List<CustomEvent>> loadAndMergePluginEvents(
    List<CustomEvent> existingEvents, {
    String? currentWorkspaceId,
    String? currentBookId,
    String? currentBookUid,
  }) async {
    try {
      final records = await PluginSystemDatabase.instance
          .getPublishedRecordsFull('calendar.event');

      final pluginEvents = <CustomEvent>[];
      for (final record in records) {
        try {
          final pluginId = record['plugin_id'] as String;
          final key = record['key'] as String;
          final scope = record['scope'] as String;
          final rawPayload = jsonDecode(record['payload_json'] as String);

          if (rawPayload is! Map<String, dynamic>) continue;

          // סינון לפי scope
          if (!_isScopeVisible(
            scope: scope,
            currentWorkspaceId: currentWorkspaceId,
            currentBookId: currentBookId,
            currentBookUid: currentBookUid,
          )) {
            continue;
          }

          final event = _fromPluginPayload(pluginId, key, rawPayload);
          if (event != null) pluginEvents.add(event);
        } catch (e) {
          debugPrint('PluginCalendarAdapter: failed to parse record: $e');
        }
      }

      return [...existingEvents, ...pluginEvents];
    } catch (e) {
      debugPrint('PluginCalendarAdapter: failed to load events: $e');
      return existingEvents;
    }
  }

  /// קובע האם record מסוים צריך להיות גלוי לפי ה-scope שלו.
  bool _isScopeVisible({
    required String scope,
    String? currentWorkspaceId,
    String? currentBookId,
    String? currentBookUid,
  }) {
    if (scope == 'global') return true;

    if (scope.startsWith('workspace:')) {
      final workspaceId = scope.substring('workspace:'.length);
      return currentWorkspaceId != null && currentWorkspaceId == workspaceId;
    }

    if (scope.startsWith('book:')) {
      // מזוהה גם scope חדש (`book:<bookUid>`) וגם ישן (`book:<כותרת>`).
      final bookId = scope.substring('book:'.length);
      return (currentBookId != null && currentBookId == bookId) ||
          (currentBookUid != null && currentBookUid == bookId);
    }

    // scope לא מוכר — בטח לא להציג
    return false;
  }

  /// ממיר spec payload → [CustomEvent] פנימי.
  ///
  /// ```json
  /// { "title": "ערב שבת", "startsAt": "2026-03-27T16:00:00+02:00",
  ///   "source": "my-plugin", "importance": "high" }
  /// ```
  CustomEvent? _fromPluginPayload(
    String pluginId,
    String key,
    Map<String, dynamic> payload,
  ) {
    final title = payload['title'] as String?;
    final startsAtRaw = payload['startsAt'] as String?;
    if (title == null || startsAtRaw == null) return null;

    final startsAt = DateTime.tryParse(startsAtRaw);
    if (startsAt == null) return null;

    // source + importance → description
    final source = payload['source'] as String? ?? '';
    final importance = payload['importance'] as String?;
    final description = (importance != null && importance.isNotEmpty)
        ? '$source ($importance)'
        : source;

    // המרה לתאריך עברי
    final jwDate = JewishDate.fromDateTime(startsAt);

    return CustomEvent(
      id: '$pluginId:$key',
      title: title,
      description: description,
      createdAt: DateTime.now(),
      baseGregorianDate: DateTime(startsAt.year, startsAt.month, startsAt.day),
      baseJewishYear: jwDate.getJewishYear(),
      baseJewishMonth: jwDate.getJewishMonth(),
      baseJewishDay: jwDate.getJewishDayOfMonth(),
      recurrenceType: RecurrenceType.none,
    );
  }
}
