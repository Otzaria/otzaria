import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';

/// נועלת את ציר הגלילה של לוח מגע ברגע שמתחילה גלילה משמעותית בציר
/// אחד, ומחזירה אירוע "מקוצץ" לציר הנעול. הנעילה משתחררת אחרי הפסקה
/// קצרה בזרם האירועים (= הרמת אצבעות מלוח המגע) - אותה התנהגות שיש
/// בכל קורא PDF סטנדרטי, כדי שהצופה לא יזוז לצדדים בטעות בזמן גלילה
/// אנכית.
///
/// שימוש: יצירת מופע ושמירתו ב-state, וקריאה ל-[apply] על כל
/// `PointerSignalEvent` לפני שמעבירים אותו ל-pdfrx.
class TrackpadAxisLock {
  TrackpadAxisLock({
    this.idleReset = const Duration(milliseconds: 150),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// זמן ההפסקה שאחריו הנעילה משתחררת. הפסקה זו מזהה הרמת אצבעות
  /// מלוח המגע.
  final Duration idleReset;
  final DateTime Function() _clock;

  Axis? _lockedAxis;
  int? _lastEventTimeMs;

  /// הציר הנעול הנוכחי, או `null` אם אין נעילה פעילה.
  Axis? get lockedAxis => _lockedAxis;

  /// מחזירה אירוע מתוקן - כשנעול ציר אנכי, רכיב ה-dx מתאפס, ולהפך.
  ///
  /// - אירועים שאינם `PointerScrollEvent` (כמו `PointerScaleEvent` של
  ///   pinch) מוחזרים כמו שהם.
  /// - כש-Ctrl לחוץ (זום) הנעילה מתאפסת והאירוע עובר ללא שינוי, כי
  ///   pdfrx מסכם את שני הצירים לחישוב הזום.
  PointerSignalEvent apply(
    PointerSignalEvent event, {
    bool isControlPressed = false,
  }) {
    if (event is! PointerScrollEvent) {
      return event;
    }
    if (isControlPressed) {
      reset();
      return event;
    }

    final nowMs = _clock().millisecondsSinceEpoch;
    final lastMs = _lastEventTimeMs;
    if (lastMs == null || nowMs - lastMs > idleReset.inMilliseconds) {
      _lockedAxis = null;
    }
    _lastEventTimeMs = nowMs;

    final delta = event.scrollDelta;
    if (_lockedAxis == null) {
      if (delta.dx == 0 && delta.dy == 0) {
        return event;
      }
      _lockedAxis = delta.dy.abs() >= delta.dx.abs()
          ? Axis.vertical
          : Axis.horizontal;
    }

    final Offset locked = _lockedAxis == Axis.vertical
        ? Offset(0, delta.dy)
        : Offset(delta.dx, 0);
    if (locked == delta) {
      return event;
    }

    return PointerScrollEvent(
      viewId: event.viewId,
      timeStamp: event.timeStamp,
      kind: event.kind,
      device: event.device,
      position: event.position,
      scrollDelta: locked,
      embedderId: event.embedderId,
    );
  }

  /// מאפסת את מצב הנעילה ידנית.
  void reset() {
    _lockedAxis = null;
    _lastEventTimeMs = null;
  }
}
