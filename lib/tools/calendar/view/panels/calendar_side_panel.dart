import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/widgets/otzaria_search_field.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/dialogs.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';

/// הפאנל הצדדי — מציג תוכן לפי מצב נבחר
enum CalendarSidePanelView { times, events, settings }

/// הפאנל הצדדי — מקבל מצב נבחר ומציג תוכן מתאים
class CalendarSidePanel extends StatefulWidget {
  final CalendarState state;
  final CalendarSidePanelView activeView;
  final ValueChanged<CalendarSidePanelView> onViewChanged;
  final Widget Function(BuildContext, CalendarState) buildTimesGrid;
  final Widget Function(BuildContext, CalendarState) buildDafYomiButtons;
  final Widget Function(BuildContext, CalendarState) buildCityDropdown;
  final Widget Function(BuildContext, CalendarState, bool) buildEventsList;
  final void Function(BuildContext, CalendarState) showCreateEventDialog;

  const CalendarSidePanel({
    super.key,
    required this.state,
    required this.activeView,
    required this.onViewChanged,
    required this.buildTimesGrid,
    required this.buildDafYomiButtons,
    required this.buildCityDropdown,
    required this.buildEventsList,
    required this.showCreateEventDialog,
  });

  @override
  State<CalendarSidePanel> createState() => _CalendarSidePanelState();
}

class _CalendarSidePanelState extends State<CalendarSidePanel>
    with SingleTickerProviderStateMixin {
  final ScrollController _timesScrollController = ScrollController();
  final ScrollController _eventsScrollController = ScrollController();
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
    _timesScrollController.dispose();
    _eventsScrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

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
                Tab(
                  icon: Icon(FluentIcons.clock_24_regular),
                ),
                Tab(
                  icon: Icon(FluentIcons.calendar_24_regular),
                ),
                Tab(
                  icon: Icon(FluentIcons.settings_24_regular),
                ),
              ],
              isScrollable: false,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorColor: theme.colorScheme.primary,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              dividerColor: theme.colorScheme.outlineVariant,
              overlayColor: WidgetStatePropertyAll(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: CalendarSidePanelView.values.indexOf(widget.activeView),
              children: [
                _buildTimesPanel(context, theme),
                _buildEventsPanel(context, theme),
                _buildSettingsPanel(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimesPanel(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      controller: _timesScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SettingsCard(
        title: 'זמני היום',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Spacer(),
                widget.buildCityDropdown(context, widget.state),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppTokens.radiusMD),
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'אין לסמוך על הזמנים כלל!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'שים לב! ',
                          style: TextStyle(fontSize: 12),
                        ),
                        WidgetSpan(
                          child: InkWell(
                            onTap: () => _showCalendarCalculationInfo(context),
                            child: Text(
                              'הזמנים שונים',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(
                          text: ' מהותית מהלוח \'עיתים לבינה\'!',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: widget.buildTimesGrid(context, widget.state),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: widget.buildDafYomiButtons(context, widget.state),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsPanel(BuildContext context, ThemeData theme) {
    return SingleChildScrollView(
      controller: _eventsScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SettingsCard(
        title: 'אירועים',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                RecommendedActionButton(
                  text: 'צור אירוע',
                  icon: FluentIcons.add_24_regular,
                  onPressed: () =>
                      widget.showCreateEventDialog(context, widget.state),
                ),
                if (widget.state.googleCalendarEnabled) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: widget.state.googleCalendarSyncInProgress
                        ? null
                        : () {
                            final cubit = context.read<CalendarCubit>();
                            if (widget.state.googleCalendarConnected) {
                              cubit.syncGoogleCalendar(interactive: true);
                            } else {
                              cubit.connectGoogleCalendar();
                            }
                          },
                    icon: widget.state.googleCalendarSyncInProgress
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            FluentIcons.arrow_sync_24_regular,
                            size: 16,
                          ),
                    label: Text(
                      widget.state.googleCalendarConnected
                          ? 'סנכרן Google'
                          : 'חבר ל-Google',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
                const Spacer(),
                NeutralActionButton(
                  text:
                      widget.state.showAllEvents ? 'הצג יום נוכחי' : 'הצג הכל',
                  icon: widget.state.showAllEvents
                      ? FluentIcons.calendar_month_24_regular
                      : FluentIcons.calendar_day_24_regular,
                  onPressed: () => context
                      .read<CalendarCubit>()
                      .toggleShowAllEvents(!widget.state.showAllEvents),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: OtzariaSearchField(
                    controller: TextEditingController(
                        text: widget.state.eventSearchQuery),
                    hintText: 'חפש אירועים...',
                    onChanged: (query) => context
                        .read<CalendarCubit>()
                        .setEventSearchQuery(query),
                    onClear: () =>
                        context.read<CalendarCubit>().setEventSearchQuery(''),
                  ),
                ),
                IconButton(
                  icon: Icon(widget.state.searchInDescriptions
                      ? FluentIcons.document_text_24_regular
                      : FluentIcons.text_t_24_regular),
                  tooltip: widget.state.searchInDescriptions
                      ? 'חפש רק בכותרת'
                      : 'חפש גם בתיאור',
                  onPressed: () => context
                      .read<CalendarCubit>()
                      .toggleSearchInDescriptions(
                          !widget.state.searchInDescriptions),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: widget.buildEventsList(
              context,
              widget.state,
              widget.state.eventSearchQuery.isNotEmpty,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel(BuildContext context) {
    return BlocProvider.value(
      value: context.read<CalendarCubit>(),
      child: const SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: CalendarSettingsTab(),
      ),
    );
  }

  // פונקציה להצגת מידע על חישוב הזמנים
  static Future<void> _showCalendarCalculationInfo(BuildContext context) async {
    await showSingleActionDialog(
      context: context,
      title: 'אודות חישובי הלוח',
      content:
          'חישובי הלוח בתוכנה זו מיוסדים על דרכו של הרב ישראל דוד הרפנס, כפי שנתבארה בספרו ישראל והזמנים ובשאר ספריו העוסקים בענייני זמני הלכה. מטרת הדברים איננה להציג חישוב עצמאי חדש, אלא ליישם בצורה מסודרת, מדויקת ובהירה את כללי חשבון הלוח העברי על פי הביאור והסידור שנתפרשו בספריו.\n\nהרב הרפנס, מו"ץ בהתאחדות הרבנים ורב קהילת ישראל והזמנים, נודע במיוחד בבירור סוגיות הזמן בהלכה, וספרו ישראל והזמנים נזכר בקובץ זה כספר היסוד שעל פיו נבנתה תשתית החישוב שבתוכנה. לצד ספר זה, חיבר הרב גם ספרים נוספים בענייני הלכה וזמנים.',
      confirmText: 'הבנתי',
    );
  }
}
