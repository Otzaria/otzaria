import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_caption_hit_test.dart';

/// כמו `DragToMoveArea` של window_manager, אבל גורר את החלון של ה-[AppWindowScope]
/// שמעליו ולא את ה-singleton — כדי שחלון Dart יגרור את עצמו.
///
/// האזור נשאר פעיל גם מעל דיאלוג פתוח ([WindowCaptionRegion]), כמו גרירה של
/// חלון רגיל. לחיצה פשוטה בו מגיעה גם לשכבת ההחשכה, וסוגרת תפריט או דיאלוג
/// שנסגר בלחיצה בחוץ. [aboveDialogs] = false כשבתוך האזור יש כפתור, שחייב להישאר
/// חסום מאחורי הדיאלוג.
class AppDragToMoveArea extends StatelessWidget {
  const AppDragToMoveArea({
    super.key,
    required this.child,
    this.aboveDialogs = true,
  });

  final Widget child;
  final bool aboveDialogs;

  @override
  Widget build(BuildContext context) {
    final area = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => AppWindowScope.controllerOf(context).startDragging(),
      onDoubleTap: () async {
        final window = AppWindowScope.controllerOf(context);
        if (await window.isMaximized()) {
          await window.unmaximize();
        } else {
          await window.maximize();
        }
      },
      child: child,
    );
    return aboveDialogs
        ? WindowCaptionRegion(isDragArea: true, child: area)
        : area;
  }
}
