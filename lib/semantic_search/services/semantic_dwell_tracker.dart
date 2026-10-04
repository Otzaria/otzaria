import 'dart:async';

import 'package:otzaria/search_feedback/search_feedback_api.dart';

/// מה שמעקב העיון צריך לדעת על המסך ברגע נתון.
class SemanticDwellObservation {
  /// החלונית הפעילה; `null` כשאין.
  final Object? activePane;

  /// כל החלוניות הפתוחות (לפי זהות).
  final Set<Object> openPanes;

  /// מסך הכרטיסיות (עיון או חיפוש) מוצג והחלון בפוקוס; אחרת — מסך אחר,
  /// חלון ממוזער או תוכנה אחרת.
  final bool showsTabs;

  SemanticDwellObservation({
    required this.activePane,
    required Iterable<Object> openPanes,
    required this.showsTabs,
  }) : openPanes = Set<Object>.identity()..addAll(openPanes);
}

/// מדווח על סיום עיון; התוצאה (אם היא Future) נמתנת ביציאה מהתוכנה.
typedef SemanticDwellEnd =
    FutureOr<void> Function(Duration dwell, SearchFeedbackDwellEnd reason);

class _DwellSession {
  _DwellSession({
    required this.tab,
    required this.resultsKey,
    required this.onEnd,
    required this.createdAt,
  });

  /// `null` עד שהכרטיסייה שנפתחה הופכת לפעילה (פתיחה עם מיקוד קיים).
  Object? tab;
  final Object resultsKey;
  final SemanticDwellEnd onEnd;
  final DateTime createdAt;
  DateTime? activeSince;

  /// הכרטיסייה כבר נראתה פתוחה (הוספה ברקע מגיעה למצב באיחור).
  bool seenOpen = false;
}

/// מודד כמה זמן כרטיסיית תוצאה שנפתחה נשארת הפעילה, ומדווח פעם אחת בסיום.
///
/// מזעור החלון או מעבר לתוכנה אחרת מסיימים את העיון ב-tabSwitched, בלי השהיה.
class SemanticDwellTracker {
  SemanticDwellTracker({
    DateTime Function()? clock,
    this.cap = const Duration(minutes: 30),
    this.bindTimeout = const Duration(seconds: 10),
    this.pendingTimeout = const Duration(minutes: 30),
    Timer Function(Duration, void Function())? timer,
    this._replacementOf,
    Object Function(Object tab)? resultsKeyOf,
  }) : _clock = clock ?? DateTime.now,
       _timer = timer ?? Timer.new,
       _resultsKeyOf = resultsKeyOf ?? _identityKey;

  static Object _identityKey(Object tab) => tab;

  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _timer;

  /// הכרטיסייה שהחליפה את [tab] במקומה (כרטיסיית טעינה), אם יש.
  final Object? Function(Object tab)? _replacementOf;

  /// מפתח יציב של כרטיסיית התוצאות — עותק משוכפל שלה נחשב אותה כרטיסייה.
  final Object Function(Object tab) _resultsKeyOf;
  final Duration cap;

  /// כמה זמן מחכים שפתיחה רגילה תוביל לכרטיסייה פעילה.
  final Duration bindTimeout;

  /// כרטיסייה שנפתחה ברקע ולא הופעלה — נזנחת אחרי הזמן הזה.
  final Duration pendingTimeout;

  final List<_DwellSession> _sessions = [];
  SemanticDwellObservation? _last;
  Timer? _deadlineTimer;

  bool get hasSessions => _sessions.isNotEmpty;

  /// מתחיל מעקב; [tab] `null` = הכרטיסייה הבאה שתהפוך לפעילה.
  void begin({
    Object? tab,
    required Object resultsTab,
    required SemanticDwellEnd onEnd,
  }) {
    _sessions.add(
      _DwellSession(
        tab: tab,
        resultsKey: _resultsKeyOf(resultsTab),
        onEnd: onEnd,
        createdAt: _clock(),
      ),
    );
    final last = _last;
    if (last != null) {
      observe(last);
    } else {
      _scheduleDeadline();
    }
  }

  void observe(SemanticDwellObservation observation) {
    _last = observation;
    final now = _clock();
    for (final session in List.of(_sessions)) {
      _advance(session, observation, now);
    }
    _scheduleDeadline();
  }

  /// סוגר את כל המעקבים (יציאה מהתוכנה) ומסתיים כשהדיווחים נרשמו.
  Future<void> endAll(SearchFeedbackDwellEnd reason) async {
    final now = _clock();
    final pending = <Future<void>>[];
    for (final session in List.of(_sessions)) {
      _sessions.remove(session);
      if (session.activeSince != null) {
        final result = _finish(session, reason, now);
        if (result is Future<void>) pending.add(result);
      }
    }
    _scheduleDeadline();
    await Future.wait(pending);
  }

  void dispose() {
    _deadlineTimer?.cancel();
    _sessions.clear();
    _last = null;
  }

  bool _isResults(Object? pane, _DwellSession session) =>
      pane != null && _resultsKeyOf(pane) == session.resultsKey;

  void _advance(
    _DwellSession session,
    SemanticDwellObservation observation,
    DateTime now,
  ) {
    final active = observation.showsTabs ? observation.activePane : null;
    final age = now.difference(session.createdAt);
    if (session.tab == null) {
      if (active != null && !_isResults(active, session)) {
        session.tab = active;
      } else {
        if (age >= bindTimeout) _sessions.remove(session);
        return;
      }
    }
    var tab = session.tab!;
    final replacement = observation.openPanes.contains(tab)
        ? null
        : _replacementOf?.call(tab);
    if (replacement != null && observation.openPanes.contains(replacement)) {
      tab = session.tab = replacement;
    }
    final since = session.activeSince;
    if (since != null && now.difference(since) >= cap) {
      _finish(session, SearchFeedbackDwellEnd.capped, now);
      return;
    }
    if (!observation.openPanes.contains(tab)) {
      if (since != null) {
        _finish(session, SearchFeedbackDwellEnd.tabClosed, now);
      } else if (session.seenOpen || age >= bindTimeout) {
        _sessions.remove(session);
      }
      return;
    }
    session.seenOpen = true;
    final isActive = identical(active, tab);
    if (since == null) {
      if (isActive) {
        session.activeSince = now;
      } else if (age >= pendingTimeout) {
        _sessions.remove(session);
      }
      return;
    }
    if (isActive) return;
    _finish(
      session,
      _isResults(active, session)
          ? SearchFeedbackDwellEnd.returnedToResults
          : SearchFeedbackDwellEnd.tabSwitched,
      now,
    );
  }

  FutureOr<void> _finish(
    _DwellSession session,
    SearchFeedbackDwellEnd reason,
    DateTime now,
  ) {
    _sessions.remove(session);
    final elapsed = now.difference(session.activeSince!);
    return session.onEnd(elapsed > cap ? cap : elapsed, reason);
  }

  /// הטיימר הבא: תקרת עיון, או זניחת מעקב שלא התחיל.
  void _scheduleDeadline() {
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    DateTime? earliest;
    for (final session in _sessions) {
      final since = session.activeSince;
      final deadline = since != null
          ? since.add(cap)
          : session.createdAt.add(
              session.tab == null || !session.seenOpen
                  ? bindTimeout
                  : pendingTimeout,
            );
      if (earliest == null || deadline.isBefore(earliest)) earliest = deadline;
    }
    if (earliest == null) return;
    final remaining = earliest.difference(_clock());
    _deadlineTimer = _timer(
      remaining.isNegative ? Duration.zero : remaining,
      () => observe(
        _last ??
            SemanticDwellObservation(
              activePane: null,
              openPanes: const [],
              showsTabs: false,
            ),
      ),
    );
  }
}
