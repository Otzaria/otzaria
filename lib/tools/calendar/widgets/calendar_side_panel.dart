import 'package:flutter/material.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_state.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_events_panel.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_times_panel.dart';
import 'package:otzaria/theme/theme_exports.dart';

enum CalendarSidePanelView { times, events, settings }

class CalendarSidePanel extends StatelessWidget {
  final CalendarState state;
  final CalendarSidePanelView activeView;
  final ValueChanged<CalendarSidePanelView> onViewChanged;
  final CalendarTimesPanel timesPanel;
  final CalendarEventsPanel eventsPanel;

  const CalendarSidePanel({
    super.key,
    required this.state,
    required this.activeView,
    required this.onViewChanged,
    required this.timesPanel,
    required this.eventsPanel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppSurfaces.panelBackground(context),
      child: IndexedStack(
        index: activeView == CalendarSidePanelView.events ? 1 : 0,
        children: [
          timesPanel,
          eventsPanel,
        ],
      ),
    );
  }
}
