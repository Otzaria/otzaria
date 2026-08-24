import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// נעילת ציר "חכמה" לגלילת לוח מגע בצפיין ה-PDF (issues #821, #969).
///
/// האיזון בין שתי הדרישות:
/// - #821: גלילה אנכית תוך כדי זום לא צריכה להיסחף לצדדים.
/// - #969: תנועה מכוונת לצדדים ולאלכסונים חייבת להישאר חופשית.
///
/// לכן ההכרעה מתקבלת פעם אחת לכל מחווה, מתוך המרחק המצטבר של תחילתה
/// (ולא מהאירוע הבודד הראשון, שהוא רועש): רק מחווה שקרובה מאוד לציר
/// (יחס של [lockRatio] בין הצירים, ברירת מחדל ~18°) ננעלת אליו; כל
/// מחווה אלכסונית מוכרעת כחופשית ועוברת ללא קיצוץ עד סופה.
///
/// המחלקה משרתת שני מסלולי קלט:
/// - אירועי `PointerScrollEvent` (גלגלת / לוח מגע שמדווח כגלילה) דרך
///   [apply] - שם סוף המחווה מזוהה לפי הפסקה בזרם האירועים ([idleReset]).
/// - מחוות pan של לוח מגע מדויק דרך [applyDelta] - שם גבולות המחווה
///   ידועים במפורש, והקורא אחראי לקרוא ל-[reset] בסוף המחווה.
class TrackpadAxisLock {
  TrackpadAxisLock({
    this.idleReset = const Duration(milliseconds: 150),
    this.lockRatio = 3.0,
    this.decisionDistance = 8.0,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// זמן ההפסקה שאחריו מחוות גלילה נחשבת כמסתיימת (הרמת אצבעות),
  /// וההכרעה הבאה מתקבלת מחדש. רלוונטי רק למסלול [apply].
  final Duration idleReset;

  /// פי כמה הציר הדומיננטי צריך לגבור על הציר השני כדי לנעול אליו.
  /// 3.0 = זווית של עד ~18° מהציר. מחוות "רחבות" יותר נשארות חופשיות.
  final double lockRatio;

  /// המרחק המצטבר (בפיקסלים, לפני כל כפל-מהירות) שממנו מתקבלת ההכרעה.
  /// עד אליו התנועה עוברת חופשי - הכרעה מדגימה בודדת רועשת היא בדיוק
  /// מה שגרם ל"קפיצות לצדדים" שתוארו ב-#969.
  final double decisionDistance;

  final DateTime Function() _clock;

  Axis? _lockedAxis;
  bool _decidedFree = false;
  Offset _accumulated = Offset.zero;
  int? _lastEventTimeMs;

  /// הציר הנעול הנוכחי, או `null` כשאין נעילה (טרם הוכרע, או שהמחווה
  /// הוכרעה כחופשית - ראו [isFreeGesture]).
  Axis? get lockedAxis => _lockedAxis;

  /// האם המחווה הנוכחית הוכרעה כחופשית (אלכסונית) - בלי שום קיצוץ.
  bool get isFreeGesture => _decidedFree;

  /// ליבת הנעילה: מצטבר עד [decisionDistance], מכריע לפי [lockRatio],
  /// ומחזיר את ה-delta מקוצץ לציר הנעול או כמו שהוא כשאין נעילה.
  ///
  /// מיועד לקריאה ישירה ממסלול מחוות ה-pan, שם יש אירוע סיום מפורש -
  /// יש לקרוא ל-[reset] בסופה של כל מחווה.
  Offset applyDelta(Offset delta) {
    if (_decidedFree) {
      return delta;
    }
    if (_lockedAxis == null) {
      _accumulated += delta;
      if (_accumulated.distance < decisionDistance) {
        // עוד אין הכרעה - התנועה זורמת חופשי כדי לא לחסום את תחילת המחווה.
        return delta;
      }
      final adx = _accumulated.dx.abs();
      final ady = _accumulated.dy.abs();
      if (ady >= adx * lockRatio) {
        _lockedAxis = Axis.vertical;
      } else if (adx >= ady * lockRatio) {
        _lockedAxis = Axis.horizontal;
      } else {
        _decidedFree = true;
        return delta;
      }
    }
    return _lockedAxis == Axis.vertical
        ? Offset(0, delta.dy)
        : Offset(delta.dx, 0);
  }

  /// עטיפת [applyDelta] לאירועי גלילה: מזהה סוף מחווה לפי הפסקה בזרם
  /// האירועים, ומחזירה אירוע "מקוצץ" כשנעול ציר.
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
      _resetGesture();
    }
    _lastEventTimeMs = nowMs;

    final locked = applyDelta(event.scrollDelta);
    if (locked == event.scrollDelta) {
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

  /// מאפסת את מצב הנעילה - נקראת בסוף מחווה מפורש (מסלול ה-pan) או ידנית.
  void reset() {
    _resetGesture();
    _lastEventTimeMs = null;
  }

  void _resetGesture() {
    _lockedAxis = null;
    _decidedFree = false;
    _accumulated = Offset.zero;
  }
}
