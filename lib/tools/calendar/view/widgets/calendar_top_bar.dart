import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/inputs/segmented_button_tile.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_state.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_date_formatters.dart';

class CalendarTopBar extends StatelessWidget implements PreferredSizeWidget {
  final CalendarState state;
  final bool isMobile;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onJumpToToday;
  final VoidCallback onJumpToDate;
  final VoidCallback onPrint;
  final VoidCallback onToggleSidebar;
  final ValueChanged<CalendarView> onViewChanged;

  const CalendarTopBar({
    super.key,
    required this.state,
    required this.isMobile,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onJumpToToday,
    required this.onJumpToDate,
    required this.onPrint,
    required this.onToggleSidebar,
    required this.onViewChanged,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: AppTokens.spaceMD,
      centerTitle: true,
      title: Text(
        getCurrentMonthYearText(state),
        textDirection: TextDirection.rtl,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      actions: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'חודש קודם',
              onPressed: onPreviousMonth,
              icon: const Icon(FluentIcons.chevron_left_24_regular),
            ),
            IconButton(
              tooltip: 'חודש הבא',
              onPressed: onNextMonth,
              icon: const Icon(FluentIcons.chevron_right_24_regular),
            ),
            const SizedBox(width: AppTokens.spaceXS),
            RecommendedActionButton(
              text: 'היום',
              onPressed: onJumpToToday,
            ),
            const SizedBox(width: AppTokens.spaceXS),
            RecommendedActionButton(
              text: 'מעבר לתאריך',
              onPressed: onJumpToDate,
            ),
            const SizedBox(width: AppTokens.spaceMD),
            AppSegmentedControl<CalendarView>(
              options: const [
                SegmentOption(value: CalendarView.day, label: 'יום'),
                SegmentOption(value: CalendarView.week, label: 'שבוע'),
                SegmentOption(value: CalendarView.month, label: 'חודש'),
              ],
              currentValue: state.calendarView,
              onChanged: onViewChanged,
            ),
            const SizedBox(width: AppTokens.spaceMD),
            SizedBox(
              height: 24,
              child: VerticalDivider(
                color: Theme.of(context).dividerColor,
                thickness: 1,
              ),
            ),
            const SizedBox(width: AppTokens.spaceMD),
            IconButton(
              tooltip: 'הדפס',
              icon: const Icon(FluentIcons.print_24_regular),
              onPressed: onPrint,
            ),
            IconButton(
              tooltip: 'לוח צד',
              icon: const Icon(FluentIcons.panel_right_24_regular),
              onPressed: onToggleSidebar,
            ),
          ],
        ),
      ],
    );
  }
}
