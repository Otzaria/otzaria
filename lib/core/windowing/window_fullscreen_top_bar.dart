import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/windowing/device_chrome.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/theme/layout_tokens.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

/// במסך מלא, כל [AppTopBar] שמתחתיו מסתיים בלחצן יציאה (ולא בלחצן צף) —
/// בקצה השמאלי, באותה פינה שבה יושב לחצן הכניסה למסך מלא בשורת הכותרת.
/// בלי [WindowFullscreenCubit] מעליו אין מסך מלא.
class WindowFullscreenTopBarScope extends StatelessWidget {
  final Widget child;

  const WindowFullscreenTopBarScope({super.key, required this.child});

  static List<AppTopBarItem> _items(BuildContext context, bool compact) {
    final isFullscreen = context.select(
      (WindowFullscreenCubit? cubit) => cubit?.state ?? false,
    );
    if (!isFullscreen) return const [];
    return [
      AppTopBarItem(
        widget: BarButton.icon(
          tooltip: 'צא ממסך מלא',
          icon: FluentIcons.full_screen_minimize_24_regular,
          compact: compact,
          onPressed: () => FullscreenHelper.toggleFullscreen(context, false),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) =>
      AppTopBarScope(trailing: _items, child: child);
}

/// רוחב החלון שממנו יש בשורת הכותרת מקום לכפתור המסך המלא גם כשהכרטיסיות
/// בתוכה: הפעולות (105), חיפוש הכרטיסיות, שתי כרטיסיות מלאות (2×140) וזוג
/// הכפתורים שבפינה.
const double kMobileFullscreenTitleBarMinWidth = 500;

/// בטלפון כפתור הכניסה למסך מלא יושב בשורת הכותרת, בפינה השמאלית ליד
/// "הגדרות תצוגת הספרים", כמו במחשב, כשיש בה מקום (הערת בעל הפרויקט, 4.11).
/// יש מקום כשהכרטיסיות בשורה שנייה או בעמודה בצד; כשהן בשורת הכותרת עצמה,
/// רק מרוחב [kMobileFullscreenTitleBarMinWidth]. אחרת הכפתור בסרגל הקורא
/// ([buildMobileFullscreenAction]).
bool mobileFullscreenInTitleBar(BuildContext context) {
  if (!DeviceChrome.isMobile) return false;
  final tabsOnSide = context.select(
    (SettingsBloc? bloc) => bloc?.state.readingTabsOnSide ?? false,
  );
  final tabsInTitleBar =
      WindowClass.usesSideNavigationOf(context) && !tabsOnSide;
  return !tabsInTitleBar ||
      MediaQuery.sizeOf(context).width >= kMobileFullscreenTitleBarMinWidth;
}

/// כניסה למסך מלא מסרגל הקורא, בטלפון בלבד (q12 Q8, B), כשאין לה מקום
/// בשורת הכותרת ([mobileFullscreenInTitleBar]): בטלפון אין F11. במסך מלא
/// הפעולה לא נבנית, כי כפתור היציאה כבר בסוף הסרגל
/// ([WindowFullscreenTopBarScope]).
///
/// הפעולה עוברת ל"עוד" לפי [ToolbarActionId.fullscreen] כשאין מקום.
ActionButtonData? buildMobileFullscreenAction(
  BuildContext context, {
  required bool compact,
}) {
  if (!DeviceChrome.isMobile) return null;
  if (mobileFullscreenInTitleBar(context)) return null;
  final isFullscreen = context.select(
    (WindowFullscreenCubit? cubit) => cubit?.state ?? false,
  );
  if (isFullscreen) return null;
  return ActionButtonData.simple(
    icon: FluentIcons.full_screen_maximize_24_regular,
    tooltip: 'מסך מלא',
    compact: compact,
    onPressed: () => FullscreenHelper.toggleFullscreen(context, true),
    actionId: ToolbarActionId.fullscreen,
  );
}
