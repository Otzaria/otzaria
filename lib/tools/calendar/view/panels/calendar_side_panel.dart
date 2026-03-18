import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/widgets/otzaria_search_field.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/dialogs.dart';
import 'package:otzaria/widgets/inputs/segmented_button_tile.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_date_formatters.dart';

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
  final List<String> hebrewDays;

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
    required this.hebrewDays,
  });

  @override
  State<CalendarSidePanel> createState() => _CalendarSidePanelState();
}

class _CalendarSidePanelState extends State<CalendarSidePanel> {
  final ScrollController _timesScrollController = ScrollController();
  final ScrollController _eventsScrollController = ScrollController();
  double _timesScrollProgress = 0.0;
  double _eventsScrollProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _timesScrollController.addListener(() {
      const maxScroll = 60.0;
      final progress =
          (_timesScrollController.offset / maxScroll).clamp(0.0, 1.0);
      if (progress != _timesScrollProgress) {
        setState(() => _timesScrollProgress = progress);
      }
    });

    _eventsScrollController.addListener(() {
      const maxScroll = 60.0;
      final progress =
          (_eventsScrollController.offset / maxScroll).clamp(0.0, 1.0);
      if (progress != _eventsScrollProgress) {
        setState(() => _eventsScrollProgress = progress);
      }
    });
  }

  @override
  void dispose() {
    _timesScrollController.dispose();
    _eventsScrollController.dispose();
    super.dispose();
  }

  // ─── Animated date header ──────────────────────────────────────────────────

  Widget _buildAnimatedDateHeader(BuildContext context, double progress) {
    final state = widget.state;
    final dayOfWeek =
        widget.hebrewDays[state.selectedGregorianDate.weekday % 7];
    final jewishDay =
        formatHebrewDay(state.selectedJewishDate.getJewishDayOfMonth());
    final jewishMonth = getHebrewMonthNameFor(state.selectedJewishDate);
    final gregorianDay = state.selectedGregorianDate.day;
    final gregorianMonth =
        getGregorianMonthName(state.selectedGregorianDate.month);
    final gregorianYear = state.selectedGregorianDate.year;

    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fontSize = 20.0 - (6.0 * progress);
    final padding = 16.0 - (8.0 * progress);
    final opacity = 1.0 - progress;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: isDark
            ? cs.surfaceContainer
            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '$dayOfWeek $jewishDay $jewishMonth',
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          ),
          if (opacity > 0.01)
            Opacity(
              opacity: opacity,
              child: Padding(
                padding: EdgeInsets.only(top: 4.0 * opacity),
                child: Text(
                  '$gregorianDay $gregorianMonth $gregorianYear',
                  style: TextStyle(
                    fontSize: 16.0 - (2.0 * progress),
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                ),
              ),
            ),
        ],
      ),
    );
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: AppSegmentedControl<CalendarSidePanelView>(
              options: const [
                SegmentOption(
                  value: CalendarSidePanelView.times,
                  label: 'זמני היום',
                ),
                SegmentOption(
                  value: CalendarSidePanelView.events,
                  label: 'אירועים',
                ),
                SegmentOption(
                  value: CalendarSidePanelView.settings,
                  label: 'הגדרות',
                ),
              ],
              currentValue: widget.activeView,
              onChanged: widget.onViewChanged,
            ),
          ),
          const SizedBox(height: AppTokens.spaceMD),
          Expanded(
            child: IndexedStack(
              index: CalendarSidePanelView.values.indexOf(widget.activeView),
              children: [
                _buildTimesPanel(context, theme),
                _buildEventsPanel(context, theme),
                _buildSettingsPanel(context, theme),
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildAnimatedDateHeader(context, _timesScrollProgress),
          ),
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildAnimatedDateHeader(context, _eventsScrollProgress),
          ),
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

  Widget _buildSettingsPanel(BuildContext context, ThemeData theme) {
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
