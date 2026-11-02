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
}
