import 'package:flutter/widgets.dart';

/// משכי התנועה של הממשק, בכפוף להעדפת "הפחתת אנימציות" של המערכת.
///
/// לאנימציות ממשק בלבד (חלונית, לשונית, הרחבה). אנימציה שמעבירה מידע,
/// כמו התקדמות, לא עוברת כאן.
class AppMotion {
  AppMotion._();

  /// [token] (בדרך כלל `AppTokens.anim*`), או [Duration.zero] כשהמערכת
  /// מבקשת להפחית אנימציות.
  static Duration duration(BuildContext context, Duration token) =>
      reduced(context) ? Duration.zero : token;

  /// האם המערכת מבקשת להפחית אנימציות.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// גלילה מונפשת (DD-21): [animate] במשך [token], או [jump] כשהמערכת מבקשת
  /// להפחית אנימציות. `animateTo`/`scrollTo` לא מקבלים משך 0, ולכן הקפיצה
  /// מפורשת. ל־`Scrollable.ensureVisible` מספיק [duration]: הוא קופץ במשך 0.
  static Future<void> scroll(
    BuildContext context,
    Duration token, {
    required Future<void> Function(Duration duration) animate,
    required void Function() jump,
  }) {
    if (reduced(context)) {
      jump();
      return Future<void>.value();
    }
    return animate(token);
  }

  /// [scroll] של [position] אל [offset].
  static Future<void> scrollPosition(
    ScrollPosition position,
    double offset,
    Duration token, {
    Curve curve = Curves.easeInOut,
  }) => scroll(
    position.context.storageContext,
    token,
    animate: (duration) =>
        position.animateTo(offset, duration: duration, curve: curve),
    jump: () => position.jumpTo(offset),
  );
}
