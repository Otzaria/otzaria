import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_state.dart';
import 'package:otzaria/tools/calendar/view/panels/widgets/calendar_events_panel.dart';
import 'package:otzaria/tools/calendar/view/panels/widgets/calendar_settings_panel.dart';
import 'package:otzaria/tools/calendar/view/panels/widgets/calendar_times_panel.dart';
import 'package:otzaria/theme/theme_exports.dart';

enum CalendarSidePanelView { times, events, settings }

class CalendarSidePanel extends StatefulWidget {
  final CalendarState state;
  final CalendarSidePanelView activeView;
  final ValueChanged<CalendarSidePanelView> onViewChanged;
  final CalendarTimesPanel timesPanel;
  final CalendarEventsPanel eventsPanel;
  final CalendarSettingsPanel settingsPanel;

  const CalendarSidePanel({
    super.key,
    required this.state,
    required this.activeView,
    required this.onViewChanged,
    required this.timesPanel,
    required this.eventsPanel,
    required this.settingsPanel,
  });

  @override
  State<CalendarSidePanel> createState() => _CalendarSidePanelState();
}

class _CalendarSidePanelState extends State<CalendarSidePanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: CalendarSidePanelView.values.length,
      vsync: this,
      initialIndex: CalendarSidePanelView.values.indexOf(widget.activeView),
    );
  }

  @override
  void didUpdateWidget(covariant CalendarSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = CalendarSidePanelView.values.indexOf(widget.activeView);
    if (_tabController.index != nextIndex) {
      _tabController.animateTo(nextIndex);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: AppSurfaces.panelBackground(context),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TabBar(
              controller: _tabController,
              onTap: (index) => widget.onViewChanged(
                CalendarSidePanelView.values[index],
              ),
              tabs: const [
                Tab(icon: Icon(FluentIcons.clock_24_regular)),
                Tab(icon: Icon(FluentIcons.calendar_24_regular)),
                Tab(icon: Icon(FluentIcons.settings_24_regular)),
              ],
              isScrollable: false,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorColor: theme.colorScheme.primary,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              dividerColor: theme.colorScheme.outlineVariant,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: CalendarSidePanelView.values.indexOf(widget.activeView),
              children: [
                widget.timesPanel,
                widget.eventsPanel,
                widget.settingsPanel,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
