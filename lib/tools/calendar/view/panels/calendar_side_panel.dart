import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/widgets/otzaria_search_field.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/dialogs.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_date_formatters.dart';

/// הפאנל הצדדי — כולל טאבים "זמני היום" ו"אירועים" + overlay הגדרות
class CalendarSidePanel extends StatefulWidget {
  final CalendarState state;
  final Widget Function(BuildContext, CalendarState) buildTimesGrid;
  final Widget Function(BuildContext, CalendarState) buildDafYomiButtons;
  final Widget Function(BuildContext, CalendarState) buildCityDropdown;
  final Widget Function(BuildContext, CalendarState, bool) buildEventsList;
  final void Function(BuildContext, CalendarState) showCreateEventDialog;
  final Widget Function(BuildContext, CalendarState) buildDateHeader;
  final List<String> hebrewDays;
  final void Function(TabController)? onTabControllerCreated;
  final void Function(VoidCallback)? onSettingsToggleCallbackCreated;

  const CalendarSidePanel({
    super.key,
    required this.state,
    required this.buildTimesGrid,
    required this.buildDafYomiButtons,
    required this.buildCityDropdown,
    required this.buildEventsList,
    required this.showCreateEventDialog,
    required this.buildDateHeader,
    required this.hebrewDays,
    this.onTabControllerCreated,
    this.onSettingsToggleCallbackCreated,
  });

  @override
  State<CalendarSidePanel> createState() => _CalendarSidePanelState();
}

class _CalendarSidePanelState extends State<CalendarSidePanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showingSettings = false;
  final ScrollController _timesScrollController = ScrollController();
  final ScrollController _eventsScrollController = ScrollController();
  double _timesScrollProgress = 0.0;
  double _eventsScrollProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    widget.onTabControllerCreated?.call(_tabController);
    widget.onSettingsToggleCallbackCreated?.call(_toggleSettings);

    _tabController.addListener(() {
      if (_showingSettings && !_tabController.indexIsChanging) {
        setState(() => _showingSettings = false);
      }
      if (!_tabController.indexIsChanging) setState(() {});
    });

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

  void _toggleSettings() {
    setState(() => _showingSettings = !_showingSettings);
  }

  @override
  void dispose() {
    _timesScrollController.dispose();
    _eventsScrollController.dispose();
    _tabController.dispose();
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
    final isDark = theme.brightness == Brightness.dark;
    final cardColor =
        isDark ? theme.colorScheme.surfaceContainer : theme.colorScheme.surface;

    return Card(
      elevation: 0,
      color: cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppTokens.radiusXL)),
      ),
      child: Column(
        children: [
          // Tab bar
          Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor, width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    onTap: (index) {
                      if (_showingSettings) {
                        setState(() => _showingSettings = false);
                      }
                    },
                    tabs: [
                      Tab(
                        icon: Icon(
                          _tabController.index == 0
                              ? FluentIcons.calendar_clock_24_filled
                              : FluentIcons.calendar_clock_24_regular,
                          size: 18,
                        ),
                        iconMargin: const EdgeInsets.only(bottom: 2),
                        height: 48,
                        child: const Text('זמני היום',
                            style: TextStyle(fontSize: 12)),
                      ),
                      Tab(
                        icon: Icon(
                          _tabController.index == 1
                              ? FluentIcons.calendar_ltr_24_filled
                              : FluentIcons.calendar_ltr_24_regular,
                          size: 18,
                        ),
                        iconMargin: const EdgeInsets.only(bottom: 2),
                        height: 48,
                        child: const Text('אירועים',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                    dividerColor: Colors.transparent,
                    dividerHeight: 0,
                    overlayColor: WidgetStateProperty.all(
                      theme.colorScheme.primary.withValues(alpha: 0.08),
                    ),
                    splashBorderRadius:
                        BorderRadius.circular(AppTokens.radiusMD),
                  ),
                ),
                // כפתור הגדרות
                Tooltip(
                  message: 'הגדרות',
                  child: IconButton(
                    icon: Icon(
                      _showingSettings
                          ? FluentIcons.settings_24_filled
                          : FluentIcons.settings_24_regular,
                      size: 20,
                    ),
                    onPressed: _toggleSettings,
                    isSelected: _showingSettings,
                    style: IconButton.styleFrom(
                      foregroundColor:
                          _showingSettings ? theme.colorScheme.primary : null,
                      backgroundColor: _showingSettings
                          ? theme.colorScheme.primary.withValues(alpha: 0.12)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Tab content
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: [
                    // ─── Tab: זמני היום ───────────────────────────────────
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: _buildAnimatedDateHeader(
                              context, _timesScrollProgress),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _timesScrollController,
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Spacer(),
                                    widget.buildCityDropdown(
                                        context, widget.state),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // אזהרת זמנים
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(
                                        AppTokens.radiusMD),
                                    border: Border.all(
                                        color: theme.colorScheme.primary,
                                        width: 1),
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
                                                style: TextStyle(fontSize: 12)),
                                            WidgetSpan(
                                              child: InkWell(
                                                onTap: () =>
                                                    _showCalendarCalculationInfo(
                                                        context),
                                                child: Text(
                                                  'הזמנים שונים',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: theme
                                                        .colorScheme.primary,
                                                    decoration: TextDecoration
                                                        .underline,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const TextSpan(
                                                text:
                                                    ' מהותית מהלוח \'עיתים לבינה\'!',
                                                style: TextStyle(fontSize: 12)),
                                          ],
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                widget.buildTimesGrid(context, widget.state),
                                const SizedBox(height: 16),
                                widget.buildDafYomiButtons(
                                    context, widget.state),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // ─── Tab: אירועים ────────────────────────────────────
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: _buildAnimatedDateHeader(
                              context, _eventsScrollProgress),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _eventsScrollController,
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    RecommendedActionButton(
                                      text: 'צור אירוע',
                                      icon: FluentIcons.add_24_regular,
                                      onPressed: () =>
                                          widget.showCreateEventDialog(
                                              context, widget.state),
                                    ),
                                    if (widget.state.googleCalendarEnabled) ...[
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        onPressed: widget.state
                                                .googleCalendarSyncInProgress
                                            ? null
                                            : () {
                                                final cubit = context
                                                    .read<CalendarCubit>();
                                                if (widget.state
                                                    .googleCalendarConnected) {
                                                  cubit.syncGoogleCalendar(
                                                      interactive: true);
                                                } else {
                                                  cubit.connectGoogleCalendar();
                                                }
                                              },
                                        icon: widget.state
                                                .googleCalendarSyncInProgress
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              )
                                            : const Icon(
                                                FluentIcons
                                                    .arrow_sync_24_regular,
                                                size: 16),
                                        label: Text(
                                          widget.state.googleCalendarConnected
                                              ? 'סנכרן Google'
                                              : 'חבר ל-Google',
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                          textStyle:
                                              const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                    const Spacer(),
                                    NeutralActionButton(
                                      text: widget.state.showAllEvents
                                          ? 'הצג יום נוכחי'
                                          : 'הצג הכל',
                                      icon: widget.state.showAllEvents
                                          ? FluentIcons
                                              .calendar_month_24_regular
                                          : FluentIcons.calendar_day_24_regular,
                                      onPressed: () => context
                                          .read<CalendarCubit>()
                                          .toggleShowAllEvents(
                                              !widget.state.showAllEvents),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OtzariaSearchField(
                                        controller: TextEditingController(
                                            text:
                                                widget.state.eventSearchQuery),
                                        hintText: 'חפש אירועים...',
                                        onChanged: (query) => context
                                            .read<CalendarCubit>()
                                            .setEventSearchQuery(query),
                                        onClear: () => context
                                            .read<CalendarCubit>()
                                            .setEventSearchQuery(''),
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(widget
                                              .state.searchInDescriptions
                                          ? FluentIcons.document_text_24_regular
                                          : FluentIcons.text_t_24_regular),
                                      tooltip: widget.state.searchInDescriptions
                                          ? 'חפש רק בכותרת'
                                          : 'חפש גם בתיאור',
                                      onPressed: () => context
                                          .read<CalendarCubit>()
                                          .toggleSearchInDescriptions(!widget
                                              .state.searchInDescriptions),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                widget.buildEventsList(context, widget.state,
                                    widget.state.eventSearchQuery.isNotEmpty),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Overlay הגדרות
                if (_showingSettings)
                  Container(
                    color: theme.colorScheme.surface,
                    child: BlocProvider.value(
                      value: context.read<CalendarCubit>(),
                      child: const SingleChildScrollView(
                        padding: EdgeInsets.all(16.0),
                        child: CalendarSettingsTab(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
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
