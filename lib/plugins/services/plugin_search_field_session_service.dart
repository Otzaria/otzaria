import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

/// מצב התצוגה של כפתור פעולה בזמן סשן, כפי שהתוסף מדווח.
enum PluginSearchFieldActionState { idle, active, busy }

/// הצד של השדה בסשן: מה כתוב בו עכשיו, איך כותבים אליו ואיך מריצים חיפוש.
abstract interface class PluginSearchFieldBinding {
  PluginSearchField get field;
  TextEditingValue get currentValue;

  /// כתיבת טקסט שהתוסף הרכיב — בלי שהשדה יחשוב שהמשתמש הקליד.
  void applyPluginText(TextEditingValue value);

  /// הרצת החיפוש כאילו המשתמש לחץ Enter.
  void submit();
}

/// סשן אחד: נפתח רק בלחיצת משתמש על כפתור של תוסף בשדה מסוים, ונסגר
/// כשהתוסף מסיים, כשהמשתמש עורך את השדה, כשהשדה נסגר או כשסשן אחר מחליף אותו.
class PluginSearchFieldSession {
  final String id;
  final String pluginId;
  final String actionId;
  final PluginSearchFieldBinding binding;

  /// הטקסט שמחוץ לבחירה ברגע הלחיצה — נשמר כמות שהוא בכל כתיבה של התוסף.
  final String before;
  final String after;

  /// הטקסט שהשדה אמור להכיל עכשיו; כל שינוי אחר הוא עריכה של המשתמש.
  String expectedText;
  PluginSearchFieldActionState state = PluginSearchFieldActionState.idle;
  String? tooltip;

  /// המופע של התוסף שענה ראשון; קריאות ממופע אחר נדחות.
  String? instanceId;

  PluginSearchFieldSession._({
    required this.id,
    required this.pluginId,
    required this.actionId,
    required this.binding,
    required this.before,
    required this.after,
    required this.expectedText,
  });
}

typedef PluginSearchFieldEventDispatcher =
    Future<void> Function(
      String pluginId,
      String topic,
      Map<String, dynamic> payload, {
      bool preferBackground,
      String? instanceId,
    });

class PluginSearchFieldSessionException implements Exception {
  final String code;
  final String message;

  const PluginSearchFieldSessionException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

/// מנהל את הסשנים של כפתורי תוספים בשדות חיפוש ואת מסלול ה-API
/// `search.setFieldText` / `search.setFieldActionState` / `search.endFieldSession`.
class PluginSearchFieldSessionService extends ChangeNotifier {
  static final PluginSearchFieldSessionService instance =
      PluginSearchFieldSessionService._(
        (pluginId, topic, payload, {preferBackground = false, instanceId}) =>
            PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
              pluginId,
              topic,
              payload,
              preferBackground: preferBackground,
              instanceId: instanceId,
            ),
      );

  PluginSearchFieldSessionService._(this._dispatch);

  @visibleForTesting
  PluginSearchFieldSessionService.forTesting(this._dispatch);

  static const invokedTopic = 'search.fieldAction.invoked';
  static const stopRequestedTopic = 'search.fieldAction.stopRequested';
  static const endedTopic = 'search.fieldAction.ended';

  static const endReasonPlugin = 'plugin';
  static const endReasonClosed = 'closed';
  static const endReasonEdited = 'edited';
  static const endReasonReplaced = 'replaced';

  /// אורך מרבי לטקסט שתוסף כותב לשדה בקריאה אחת.
  static const int maxTextLength = 1000;
  static const int maxTooltipLength = 120;

  final PluginSearchFieldEventDispatcher _dispatch;
  final Map<String, PluginSearchFieldSession> _sessions = {};
  final Random _random = Random.secure();

  PluginSearchFieldSession? sessionFor(
    PluginSearchFieldBinding binding,
    String pluginId,
    String actionId,
  ) {
    for (final session in _sessions.values) {
      if (identical(session.binding, binding) &&
          session.pluginId == pluginId &&
          session.actionId == actionId) {
        return session;
      }
    }
    return null;
  }

  bool hasSessionsFor(PluginSearchFieldBinding binding) =>
      _sessions.values.any((s) => identical(s.binding, binding));

  /// לחיצת משתמש על כפתור: פותחת סשן חדש, או — כשכבר יש סשן לכפתור הזה
  /// בשדה הזה — מבקשת מהתוסף לעצור.
  Future<void> press({
    required PluginSearchFieldBinding binding,
    required String pluginId,
    required String actionId,
  }) async {
    final existing = sessionFor(binding, pluginId, actionId);
    if (existing != null) {
      await _send(existing, stopRequestedTopic, {
        'actionId': existing.actionId,
        'sessionId': existing.id,
      }, preferBackground: true);
      return;
    }
    // סשן אחד לכל שדה ולכל תוסף: מיקרופון אחד לא מכתיב לשני שדות.
    final replaced = _sessions.values
        .where((s) => identical(s.binding, binding) || s.pluginId == pluginId)
        .toList();
    for (final session in replaced) {
      _end(session, endReasonReplaced);
    }

    final value = binding.currentValue;
    final text = value.text;
    final selection = value.selection;
    final start = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;
    final end = selection.isValid
        ? selection.end.clamp(start, text.length)
        : text.length;
    final session = PluginSearchFieldSession._(
      id: _newSessionId(),
      pluginId: pluginId,
      actionId: actionId,
      binding: binding,
      before: text.substring(0, start),
      after: text.substring(end),
      expectedText: text,
    );
    _sessions[session.id] = session;
    notifyListeners();
    await _send(session, invokedTopic, {
      'actionId': actionId,
      'sessionId': session.id,
      'field': binding.field.name,
      'text': text,
      'selectionStart': start,
      'selectionEnd': end,
    }, preferBackground: true);
  }

  /// `search.setFieldText`: כותב לשדה `before + text + after`, עם רווח מפריד
  /// כשצריך. התוסף שולח תמיד את כל הטקסט שלו, לא תוספות.
  void setFieldText(
    String pluginId,
    String sessionId,
    Object? text, {
    String? instanceId,
  }) {
    if (text is! String) {
      throw const PluginSearchFieldSessionException(
        'error.invalid_params',
        'text must be a string',
      );
    }
    if (text.length > maxTextLength) {
      throw const PluginSearchFieldSessionException(
        'error.invalid_params',
        'text is longer than $maxTextLength characters',
      );
    }
    // שדות הספרייה ואיתור המקור מנתבים קישור otzaria:// ב-Enter; קישור מתוסף
    // היה עוקף את הרשאותיו (למשל פתיחת תוסף אחר או התקנה).
    if (text.contains('://')) {
      throw const PluginSearchFieldSessionException(
        'error.invalid_params',
        'text must not contain links',
      );
    }
    final session = _ownedSession(pluginId, sessionId, instanceId);
    final clean = text.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ');
    final value = compose(session.before, clean, session.after);
    session.expectedText = value.text;
    session.binding.applyPluginText(value);
  }

  /// `search.setFieldActionState`.
  void setActionState(
    String pluginId,
    String sessionId,
    Object? state, {
    Object? tooltip,
    String? instanceId,
  }) {
    final parsed = state is String
        ? PluginSearchFieldActionState.values
              .where((value) => value.name == state)
              .firstOrNull
        : null;
    if (parsed == null) {
      throw const PluginSearchFieldSessionException(
        'error.invalid_params',
        'state must be "idle", "active" or "busy"',
      );
    }
    if (tooltip != null &&
        (tooltip is! String ||
            tooltip.length > maxTooltipLength ||
            RegExp(r'[\u0000-\u001F\u007F]').hasMatch(tooltip))) {
      throw const PluginSearchFieldSessionException(
        'error.invalid_params',
        'tooltip must be short single-line text',
      );
    }
    final session = _ownedSession(pluginId, sessionId, instanceId);
    session.state = parsed;
    session.tooltip = tooltip as String?;
    notifyListeners();
  }

  /// `search.endFieldSession`; [submit] מריץ את החיפוש כאילו נלחץ Enter.
  void endSession(
    String pluginId,
    String sessionId, {
    bool submit = false,
    String? instanceId,
  }) {
    final session = _ownedSession(pluginId, sessionId, instanceId);
    _end(session, endReasonPlugin);
    if (submit) session.binding.submit();
  }

  /// נקרא מהשדה בכל שינוי טקסט: שינוי שלא התוסף כתב מסיים את הסשן.
  void onFieldTextChanged(PluginSearchFieldBinding binding, String text) {
    final edited = _sessions.values
        .where((s) => identical(s.binding, binding) && s.expectedText != text)
        .toList();
    for (final session in edited) {
      _end(session, endReasonEdited);
    }
  }

  /// נקרא מ-dispose של השדה. ההודעה למאזינים נדחית: עדכון ווידג'טים אחרים
  /// בזמן פירוק העץ נכשל ב-"widget tree was locked".
  void onBindingDisposed(PluginSearchFieldBinding binding) {
    final closed = _sessions.values
        .where((s) => identical(s.binding, binding))
        .toList();
    for (final session in closed) {
      _end(session, endReasonClosed, notify: false);
    }
    if (closed.isNotEmpty) scheduleMicrotask(notifyListeners);
  }

  /// התוסף הושבת, הוסר או איבד את ההרשאה.
  void removePlugin(String pluginId) =>
      _closeWhere((s) => s.pluginId == pluginId);

  /// הכפתור הוסר מהמניפסט.
  void removeAction(String pluginId, String actionId) => _closeWhere(
    (s) => s.pluginId == pluginId && s.actionId == actionId,
  );

  void _closeWhere(bool Function(PluginSearchFieldSession) test) {
    final closed = _sessions.values.where(test).toList();
    for (final session in closed) {
      _end(session, endReasonClosed);
    }
  }

  /// מופע של התוסף נסגר: סשן שקשור אליו — או כל סשן, כשלא נשאר מנוע חי —
  /// לא יקבל עוד תשובה, ולכן נסגר במקום להשאיר כפתור "פעיל" תקוע.
  void onInstanceUnregistered(
    String pluginId,
    String instanceId, {
    required bool pluginHasEngine,
  }) => _closeWhere(
    (s) =>
        s.pluginId == pluginId &&
        (!pluginHasEngine || s.instanceId == instanceId),
  );

  @visibleForTesting
  static TextEditingValue compose(String before, String text, String after) {
    if (text.isEmpty) {
      return TextEditingValue(
        text: before + after,
        selection: TextSelection.collapsed(offset: before.length),
      );
    }
    final lead = before.isNotEmpty && !_isSpace(before[before.length - 1])
        ? ' '
        : '';
    final trail = after.isNotEmpty && !_isSpace(after[0]) ? ' ' : '';
    final head = '$before$lead$text';
    return TextEditingValue(
      text: '$head$trail$after',
      selection: TextSelection.collapsed(offset: head.length),
    );
  }

  static bool _isSpace(String char) => char.trim().isEmpty;

  PluginSearchFieldSession _ownedSession(
    String pluginId,
    String sessionId,
    String? instanceId,
  ) {
    final session = _sessions[sessionId];
    // סשן זר, שהסתיים או שלא היה — אותה שגיאה, כדי לא לחשוף סשנים של אחרים.
    if (session == null || session.pluginId != pluginId) {
      throw const PluginSearchFieldSessionException(
        'error.not_found',
        'unknown search field session',
      );
    }
    if (instanceId != null) {
      session.instanceId ??= instanceId;
      if (session.instanceId != instanceId) {
        throw const PluginSearchFieldSessionException(
          'error.not_found',
          'unknown search field session',
        );
      }
    }
    return session;
  }

  void _end(
    PluginSearchFieldSession session,
    String reason, {
    bool notify = true,
  }) {
    if (_sessions.remove(session.id) == null) return;
    if (notify) notifyListeners();
    // בלי preferBackground: הודעת סגירה לא תפתח את דף התוסף למשתמש.
    unawaited(
      _send(session, endedTopic, {
        'actionId': session.actionId,
        'sessionId': session.id,
        'reason': reason,
      }, preferBackground: false),
    );
  }

  Future<void> _send(
    PluginSearchFieldSession session,
    String topic,
    Map<String, dynamic> payload, {
    required bool preferBackground,
  }) async {
    try {
      await _dispatch(
        session.pluginId,
        topic,
        payload,
        preferBackground: session.instanceId == null && preferBackground,
        instanceId: session.instanceId,
      );
    } catch (error) {
      debugPrint('PluginSearchFieldSessionService: $topic failed: $error');
    }
  }

  String _newSessionId() {
    String id;
    do {
      id =
          's_${List<int>.generate(12, (_) => _random.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    } while (_sessions.containsKey(id));
    return id;
  }
}
