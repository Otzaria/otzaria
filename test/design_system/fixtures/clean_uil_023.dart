import 'package:flutter/material.dart';

class AppTokens {
  static const Duration animFast = Duration(milliseconds: 150);
}

class AppMotion {
  static Duration duration(BuildContext context, Duration d) => d;
}

Widget a(BuildContext context, Widget child) => AnimatedOpacity(
  opacity: 1,
  duration: AppMotion.duration(context, AppTokens.animFast),
  child: child,
);
Widget b(Widget child) =>
    AnimatedSwitcher(duration: Duration.zero, child: child);
Future<void> wait() => Future.delayed(const Duration(milliseconds: 300));
Widget tip(Widget child) => Tooltip(
  message: 'x',
  waitDuration: const Duration(milliseconds: 500),
  child: child,
);
// Through AppMotion: reduced motion still zeroes it (DD-21).
Widget wrapped(BuildContext context, Widget child) => AnimatedSwitcher(
  duration: AppMotion.duration(context, const Duration(milliseconds: 280)),
  child: child,
);
Future<void> page(BuildContext context, PageController c) => c.nextPage(
  duration: AppMotion.duration(context, AppTokens.animFast),
  curve: Curves.ease,
);

// גלילה לשורה היא ניווט ולא אנימציית ממשק (הכרעה 18.11): לא נתפסת.
class FakeLines {
  Future<void> scrollToLine(int line, {Duration? duration}) async {}
}

Future<void> scrollToLineNavigation(FakeLines lines) => lines.scrollToLine(
  3,
  duration: const Duration(milliseconds: 300),
);
const Duration _kDebounce = Duration(milliseconds: 300);
Future<void> debounceConstant() => Future<void>.delayed(_kDebounce);
Widget tokenConstant(Duration d, Widget child) =>
    AnimatedOpacity(opacity: 1, duration: d, child: child);
