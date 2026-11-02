import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

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
