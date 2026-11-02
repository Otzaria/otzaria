import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';

/// למה פקודה לא אושרה.
enum CalendarAlertsFailure {
  /// הבעלים דחה את הפקודה או נכשל בה.
  rejected,
}

/// תשובת הבעלים לפקודה.
@immutable
class CalendarAlertsAck {
  const CalendarAlertsAck._({
    this.failure,
    this.update,
    this.value,
    this.error,
  });

  const CalendarAlertsAck.failed(CalendarAlertsFailure failure, [String? error])
    : this._(failure: failure, error: error);

  final CalendarAlertsFailure? failure;

  /// המצב אחרי הפקודה; null בפקודה שאינה משנה מצב.
  final CalendarAlertsUpdate? update;
  final Object? value;
  final String? error;

  bool get ok => failure == null;

  static CalendarAlertsAck fromReply(Object? reply) {
    if (reply is! Map) {
      return const CalendarAlertsAck.failed(CalendarAlertsFailure.rejected);
    }
    if (reply['ok'] != true) {
      return CalendarAlertsAck.failed(
        CalendarAlertsFailure.rejected,
        reply['error'] as String?,
      );
    }
    return CalendarAlertsAck._(
      update: reply['values'] == null
          ? null
          : CalendarAlertsUpdate.fromJson(reply),
      value: reply['value'],
    );
  }
}

/// הדרך של חלון לשנות את מצב ההתראות: תמיד דרך הבעלים.
abstract class CalendarAlertsClient {
  /// כל החלונות באותו isolate עם הבעלים.
  static CalendarAlertsClient forCurrentWindow() =>
      LocalCalendarAlertsClient.instance;

  Future<CalendarAlertsAck> send(
    String op, [
    Map<String, Object?> args = const {},
  ]);

  /// עדכוני מצב בסדר עולה בלבד. עדכון ישן נזרק.
  Stream<CalendarAlertsUpdate> get updates;

  Stream<CalendarScheduleStatus> get scheduleStatuses;
}

/// מסנן עדכונים לפי epoch ו-revision, ומפרסם רק את החדשים.
mixin _OrderedUpdates {
  String? _epoch;
  int _revision = -1;
  Future<void>? _applying;
  int _applyingDepth = 0;

  final StreamController<CalendarAlertsUpdate> _updates =
      StreamController<CalendarAlertsUpdate>.broadcast(sync: true);

  Stream<CalendarAlertsUpdate> get updates => _updates.stream;

  /// מחיל ומפרסם את [update] אם הוא חדש. מחזיר false כשנזרק.
  Future<bool> accept(CalendarAlertsUpdate update) {
    if (!update.isNewerThan(_epoch, _revision)) return Future.value(false);
    _epoch = update.epoch;
    _revision = update.revision;
    Future<bool> apply() async {
      // עדכון חדש יותר הגיע בינתיים: הוא שיוחל ויפורסם.
      if (_epoch != update.epoch || _revision != update.revision) return false;
      _updates.add(update);
      return true;
    }

    final previous = _applying;
    final applied = previous == null ? apply() : previous.then((_) => apply());
    _applyingDepth++;
    _applying = applied.then<void>((_) {}, onError: (Object _) {}).whenComplete(
      () {
        if (--_applyingDepth == 0) _applying = null;
      },
    );
    return applied;
  }
}

/// הבעלים באותו isolate, ולכן גם אותן הגדרות.
class LocalCalendarAlertsClient
    with _OrderedUpdates
    implements CalendarAlertsClient {
  LocalCalendarAlertsClient(this.owner) {
    owner.updates.listen(accept);
  }

  static final LocalCalendarAlertsClient instance = LocalCalendarAlertsClient(
    CalendarAlertsOwner.instance,
  );

  final CalendarAlertsOwner owner;

  @override
  Stream<CalendarScheduleStatus> get scheduleStatuses => owner.scheduleStatuses;

  @override
  Future<CalendarAlertsAck> send(
    String op, [
    Map<String, Object?> args = const {},
  ]) async {
    final ack = CalendarAlertsAck.fromReply(await owner.execute(op, args));
    final update = ack.update;
    if (update != null) await accept(update);
    return ack;
  }
}
