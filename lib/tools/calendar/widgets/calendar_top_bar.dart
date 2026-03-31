// lib/tools/calendar/widgets/calendar_top_bar.dart
//
// סרגל עליון ללוח השנה — מבוסס AppTopBar.
//
// פריסה — מסך רחב (RTL):
// ┌──────────────────────────────────────────────────────────────────────┐
// │ [שבוע|חודש]  ║  [← תאריך קבוע →  היום  📅]  ║  [⏰][📋][⚙️] ║ [🖨️] │
// └──────────────────────────────────────────────────────────────────────┘
//
// פריסה — מסך צר (שורה שניה):
// שורה 1: [← תאריך קבוע →]
// שורה 2: [שבוע|חודש | היום | 📅 | 🖨️ | ⏰ | 📋 | ⚙️]
//
// החיצים ותאריך תמיד בשורה עליונה, במיקום קבוע שלא זז עם שינוי אורך התאריך.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_side_panel.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/widgets/app_menu.dart';
import 'package:otzaria/widgets/app_top_bar.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

// הרוחב שמתחתיו עוברים לשורה שנייה
const double _kTopBarNarrowBreakpoint = 540.0;
const double _kTopBarMediumBreakpoint = 860.0;
const double _kTopBarWideBreakpoint = 1160.0;
const double _kMonthDateAreaWidth = 252.0;
const double _kWeekDateAreaWidth = 344.0;
const double _kMonthDateNavGap = 20.0;
const double _kWeekDateNavGap = 12.0;
const double _kWideQuickActionsOffsetMonth = 256.0;
const double _kWideQuickActionsOffsetWeek = 306.0;

class CalendarTopBar extends StatefulWidget {
  final CalendarState state;
  final VoidCallback onJumpToToday;
  final VoidCallback onPreviousPeriod;
  final VoidCallback onNextPeriod;
  final ValueChanged<CalendarView> onViewChanged;
  final CalendarSidePanelView activeSidePanelView;
  final bool isSidePanelVisible;
  final bool isSettingsPanelOpen;
  final VoidCallback onToggleTimesPanel;
  final VoidCallback onToggleEventsPanel;
  final VoidCallback onToggleSettingsPanel;
  final VoidCallback onPrint;
  final VoidCallback onToggleSidebar;
  final DateTime? Function(String input) parseInputDate;
  final ValueChanged<DateTime> onJumpToDateSelected;

  const CalendarTopBar({
    super.key,
    required this.state,
    required this.onJumpToToday,
    required this.onPreviousPeriod,
    required this.onNextPeriod,
    required this.onViewChanged,
    required this.activeSidePanelView,
    required this.isSidePanelVisible,
    required this.isSettingsPanelOpen,
    required this.onToggleTimesPanel,
    required this.onToggleEventsPanel,
    required this.onToggleSettingsPanel,
    required this.onPrint,
    required this.onToggleSidebar,
    required this.parseInputDate,
    required this.onJumpToDateSelected,
  });

  @override
  State<CalendarTopBar> createState() => _CalendarTopBarState();
}

class _CalendarTopBarState extends State<CalendarTopBar> {
  final GlobalKey _jumpButtonKey = GlobalKey();

  String _formatWeekHebrewRange(CalendarState state) {
    final selected = state.selectedGregorianDate;
    final weekStart = selected.subtract(Duration(days: selected.weekday % 7));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final startJewish = JewishDate.fromDateTime(weekStart);
    final endJewish = JewishDate.fromDateTime(weekEnd);

    final sameHebrewMonth =
        startJewish.getJewishMonth() == endJewish.getJewishMonth() &&
            startJewish.getJewishYear() == endJewish.getJewishYear();

    if (sameHebrewMonth) {
      return '${formatHebrewDay(startJewish.getJewishDayOfMonth())}-${formatHebrewDay(endJewish.getJewishDayOfMonth())} '
          '${getHebrewMonthNameFor(startJewish)} '
          '${numberToHebrewWithoutQuotes(startJewish.getJewishYear())}';
    }

    return '${formatHebrewDay(startJewish.getJewishDayOfMonth())} ${getHebrewMonthNameFor(startJewish)} '
        '${numberToHebrewWithoutQuotes(startJewish.getJewishYear())}'
        ' - '
        '${formatHebrewDay(endJewish.getJewishDayOfMonth())} ${getHebrewMonthNameFor(endJewish)} '
        '${numberToHebrewWithoutQuotes(endJewish.getJewishYear())}';
  }

  String _formatWeekGregorianRange(CalendarState state) {
    final selected = state.selectedGregorianDate;
    final weekStart = selected.subtract(Duration(days: selected.weekday % 7));
    final weekEnd = weekStart.add(const Duration(days: 6));

    final sameGregorianMonth =
        weekStart.month == weekEnd.month && weekStart.year == weekEnd.year;

    if (sameGregorianMonth) {
      return '${weekStart.day}-${weekEnd.day} ${getGregorianMonthName(weekStart.month)} ${weekStart.year}';
    }

    return '${weekStart.day} ${getGregorianMonthName(weekStart.month)} ${weekStart.year}'
        ' - '
        '${weekEnd.day} ${getGregorianMonthName(weekEnd.month)} ${weekEnd.year}';
  }

  Widget _buildDateText(BuildContext context) {
    final s = widget.state;
    final heb = s.calendarView == CalendarView.week
        ? _formatWeekHebrewRange(s)
        : '${formatHebrewDay(s.selectedJewishDate.getJewishDayOfMonth())} '
            '${getHebrewMonthNameFor(s.selectedJewishDate)} '
            '${numberToHebrewWithoutQuotes(s.selectedJewishDate.getJewishYear())}';
    final greg = s.calendarView == CalendarView.week
        ? _formatWeekGregorianRange(s)
        : '${s.selectedGregorianDate.day} ${getGregorianMonthName(s.selectedGregorianDate.month)} ${s.selectedGregorianDate.year}';

    final defaultStyle = Theme.of(context).textTheme.bodyMedium!;
    final baseStyle = s.calendarView == CalendarView.week
        ? defaultStyle.copyWith(
            fontSize: ((defaultStyle.fontSize ?? 14) - 1).clamp(12.0, 14.0),
          )
        : defaultStyle;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: RichText(
        overflow: TextOverflow.visible,
        maxLines: 1,
        textDirection: TextDirection.rtl,
        text: TextSpan(
          style: baseStyle,
          children: [
            TextSpan(
              text: heb,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const TextSpan(text: '  •  '),
            TextSpan(
              text: greg,
              style: const TextStyle(fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleSyncStatus(BuildContext context) {
    final state = widget.state;
    if (!state.googleCalendarEnabled) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final isSyncing = state.googleCalendarSyncInProgress;
    final hasError = state.googleCalendarSyncError != null &&
        state.googleCalendarSyncError!.isNotEmpty;

    final backgroundColor = hasError
        ? scheme.errorContainer.withValues(alpha: 0.75)
        : isSyncing
            ? scheme.primaryContainer.withValues(alpha: 0.75)
            : scheme.secondaryContainer.withValues(alpha: 0.55);
    final foregroundColor = hasError
        ? scheme.onErrorContainer
        : isSyncing
            ? scheme.onPrimaryContainer
            : scheme.onSecondaryContainer;

    final tooltip = hasError
        ? state.googleCalendarSyncError!
        : isSyncing
            ? 'סנכרון Google פעיל'
            : state.googleCalendarConnected
                ? 'Google Calendar מחובר'
                : 'Google Calendar מופעל אך לא מחובר';

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Tooltip(
        message: tooltip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: foregroundColor.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSyncing)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                  ),
                )
              else
                Icon(
                  hasError
                      ? FluentIcons.warning_24_regular
                      : state.googleCalendarConnected
                          ? FluentIcons.arrow_sync_circle_24_filled
                          : FluentIcons.arrow_sync_24_regular,
                  size: 14,
                  color: foregroundColor,
                ),
              const SizedBox(width: 6),
              Text(
                isSyncing ? 'מסנכרן' : (hasError ? 'שגיאת סנכרון' : 'Google'),
                textDirection: TextDirection.rtl,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: foregroundColor,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openJumpPopover() async {
    final anchorCtx = _jumpButtonKey.currentContext;
    if (anchorCtx == null) return;

    final selected = await showAnchoredAppMenu<DateTime>(
      context: context,
      anchorContext: anchorCtx,
      itemsBuilder: (metrics) => [
        buildAppCustomPopupMenuItem<DateTime>(
          context: context,
          metrics: metrics,
          child: SizedBox(
            width: 360,
            child: _JumpToDatePopover(
              parseInputDate: widget.parseInputDate,
              onDateSelected: (d) => Navigator.of(context).pop(d),
            ),
          ),
        ),
      ],
    );

    if (selected != null && mounted) {
      widget.onJumpToDateSelected(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final isCompact = settingsState.compactMenuMode;

        // ── כפתורים משותפים ───────────────────────────────────────────────
        final prevBtn = ToolbarActionButton(
          compact: isCompact,
          tooltip: 'קודם',
          icon: FluentIcons.chevron_left_24_regular,
          emphasis: ToolbarActionButtonEmphasis.subtle,
          onPressed: widget.onPreviousPeriod,
        );
        final nextBtn = ToolbarActionButton(
          compact: isCompact,
          tooltip: 'הבא',
          icon: FluentIcons.chevron_right_24_regular,
          emphasis: ToolbarActionButtonEmphasis.subtle,
          onPressed: widget.onNextPeriod,
        );
        final todayBtn = RecommendedActionButton(
          text: 'היום',
          onPressed: widget.onJumpToToday,
        );
        final jumpBtn = ToolbarActionButton(
          key: _jumpButtonKey,
          compact: isCompact,
          tooltip: 'מעבר לתאריך',
          icon: FluentIcons.calendar_search_20_regular,
          iconWidget: Transform.flip(
            flipX: true,
            child: Icon(
              FluentIcons.calendar_search_20_regular,
              size: isCompact ? 16 : 20,
            ),
          ),
          emphasis: ToolbarActionButtonEmphasis.subtle,
          onPressed: _openJumpPopover,
        );
        final settingsBtn = ToolbarActionButton(
          compact: isCompact,
          tooltip: 'הגדרות לוח שנה',
          icon: widget.isSettingsPanelOpen
              ? FluentIcons.settings_24_filled
              : FluentIcons.settings_24_regular,
          selected: widget.isSettingsPanelOpen,
          onPressed: widget.onToggleSettingsPanel,
        );
        final eventsBtn = ToolbarActionButton(
          compact: isCompact,
          tooltip: 'אירועים',
          icon: widget.isSidePanelVisible &&
                  widget.activeSidePanelView == CalendarSidePanelView.events
              ? FluentIcons.task_list_square_rtl_24_filled
              : FluentIcons.task_list_square_rtl_24_regular,
          selected: widget.isSidePanelVisible &&
              widget.activeSidePanelView == CalendarSidePanelView.events,
          onPressed: widget.onToggleEventsPanel,
        );
        final timesBtn = ToolbarActionButton(
          compact: isCompact,
          tooltip: 'זמנים',
          icon: widget.isSidePanelVisible &&
                  widget.activeSidePanelView == CalendarSidePanelView.times
              ? FluentIcons.clock_24_filled
              : FluentIcons.clock_24_regular,
          selected: widget.isSidePanelVisible &&
              widget.activeSidePanelView == CalendarSidePanelView.times,
          onPressed: widget.onToggleTimesPanel,
        );
        final printBtn = ToolbarActionButton(
          compact: isCompact,
          tooltip: 'הדפסה',
          icon: FluentIcons.print_24_regular,
          emphasis: ToolbarActionButtonEmphasis.subtle,
          onPressed: widget.onPrint,
        );
        final viewSwitcher = _buildViewSwitcher(state);
        final quickActions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            todayBtn,
            const SizedBox(width: 2),
            jumpBtn,
          ],
        );
        final trailingActions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildGoogleSyncStatus(context),
            printBtn,
            _buildTopBarDivider(context, isCompact),
            timesBtn,
            eventsBtn,
            _buildTopBarDivider(context, isCompact),
            settingsBtn,
          ],
        );
        final dateAreaWidth = state.calendarView == CalendarView.week
            ? _kWeekDateAreaWidth
            : _kMonthDateAreaWidth;
        final dateNavGap = state.calendarView == CalendarView.week
            ? _kWeekDateNavGap
            : _kMonthDateNavGap;
        final wideQuickActionsOffset = state.calendarView == CalendarView.week
            ? _kWideQuickActionsOffsetWeek
            : _kWideQuickActionsOffsetMonth;

        // ── קבוצת חיצים + תאריך, ממורכזת תמיד ──────────────────────────────
        final dateNavGroup = Directionality(
          textDirection: TextDirection.rtl,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              prevBtn,
              SizedBox(width: dateNavGap),
              ConstrainedBox(
                constraints: BoxConstraints(minWidth: dateAreaWidth),
                child: IntrinsicWidth(
                  child: Center(child: _buildDateText(context)),
                ),
              ),
              SizedBox(width: dateNavGap),
              nextBtn,
            ],
          ),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < _kTopBarNarrowBreakpoint;
            final isMedium =
                constraints.maxWidth >= _kTopBarNarrowBreakpoint &&
                    constraints.maxWidth < _kTopBarMediumBreakpoint;
            final isWide =
                constraints.maxWidth >= _kTopBarMediumBreakpoint &&
                    constraints.maxWidth < _kTopBarWideBreakpoint;

            if (isNarrow) {
              final secondaryRow = Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runAlignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    viewSwitcher,
                    quickActions,
                    trailingActions,
                  ],
                ),
              );

              return AppTopBar(
                center: Align(
                  alignment: Alignment.center,
                  child: FittedBox(
                    alignment: Alignment.center,
                    fit: BoxFit.scaleDown,
                    child: dateNavGroup,
                  ),
                ),
                secondaryRow: secondaryRow,
              );
            }

            if (isMedium) {
              final secondaryRow = Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runAlignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    viewSwitcher,
                    quickActions,
                    trailingActions,
                  ],
                ),
              );

              return AppTopBar(
                center: Align(
                  alignment: Alignment.center,
                  child: FittedBox(
                    alignment: Alignment.center,
                    fit: BoxFit.scaleDown,
                    child: dateNavGroup,
                  ),
                ),
                secondaryRow: secondaryRow,
              );
            }

            if (isWide) {
              return AppTopBar(
                leadingItems: [
                  AppTopBarItem(widget: viewSwitcher),
                ],
                center: Align(
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: dateNavGroup),
                      const SizedBox(width: 10),
                      quickActions,
                    ],
                  ),
                ),
                trailingItems: [
                  AppTopBarItem(widget: trailingActions),
                ],
              );
            }

            {
              return AppTopBar(
                center: Stack(
                  alignment: Alignment.center,
                  children: [
                    dateNavGroup,
                    Transform.translate(
                      offset: Offset(wideQuickActionsOffset, 0),
                      child: quickActions,
                    ),
                    PositionedDirectional(
                      start: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          viewSwitcher,
                          _buildTopBarDivider(context, isCompact),
                        ],
                      ),
                    ),
                    PositionedDirectional(
                      end: 0,
                      child: trailingActions,
                    ),
                  ],
                ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildTopBarDivider(BuildContext context, bool isCompact) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        height: isCompact ? 18.0 : 24.0,
        child: VerticalDivider(
          width: 9.0,
          thickness: 1.0,
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.32),
        ),
      ),
    );
  }

  // ── View switcher ─────────────────────────────────────────────────────────

  Widget _buildViewSwitcher(CalendarState state) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ViewBtn(
          label: 'שבוע',
          regularIcon: FluentIcons.calendar_week_numbers_24_regular,
          filledIcon: FluentIcons.calendar_week_numbers_24_filled,
          selected: state.calendarView == CalendarView.week,
          onPressed: () => widget.onViewChanged(CalendarView.week),
        ),
        _ViewBtn(
          label: 'חודש',
          regularIcon: FluentIcons.calendar_month_24_regular,
          filledIcon: FluentIcons.calendar_month_24_filled,
          selected: state.calendarView == CalendarView.month,
          onPressed: () => widget.onViewChanged(CalendarView.month),
        ),
      ],
    );
  }
}

// ── _ViewBtn ──────────────────────────────────────────────────────────────────

class _ViewBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final IconData regularIcon;
  final IconData filledIcon;

  const _ViewBtn({
    required this.label,
    required this.selected,
    required this.onPressed,
    required this.regularIcon,
    required this.filledIcon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected
        ? Color.alphaBlend(
            cs.secondaryContainer.withValues(alpha: 0.82),
            cs.surfaceContainerHigh,
          )
        : Colors.transparent;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    final borderColor = selected
        ? cs.outlineVariant.withValues(alpha: 0.38)
        : Colors.transparent;
    final shadowColor =
        selected ? cs.shadow.withValues(alpha: 0.08) : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        hoverColor: cs.onSurface.withValues(alpha: 0.04),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? filledIcon : regularIcon,
                size: 16,
                color: fg,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _JumpToDatePopover ────────────────────────────────────────────────────────

class _JumpToDatePopover extends StatefulWidget {
  final DateTime? Function(String input) parseInputDate;
  final ValueChanged<DateTime> onDateSelected;

  const _JumpToDatePopover({
    required this.parseInputDate,
    required this.onDateSelected,
  });

  @override
  State<_JumpToDatePopover> createState() => _JumpToDatePopoverState();
}

class _JumpToDatePopoverState extends State<_JumpToDatePopover> {
  late final TextEditingController _controller;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final input = _controller.text.trim();
    final result = input.isEmpty ? _selectedDate : widget.parseInputDate(input);
    if (result == null) {
      UiSnack.showError('לא הצלחנו לפרש את התאריך.');
      return;
    }
    widget.onDateSelected(result);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RtlTextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'הזן תאריך',
                  hintText: '15/3/2025 או כ״ה אדר תשפ״ה',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: CalendarDatePicker(
                  initialDate: _selectedDate,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2100),
                  onDateChanged: (d) {
                    setState(() {
                      _selectedDate = d;
                      _controller.text = '${d.day}/${d.month}/${d.year}';
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  NeutralActionButton(
                      text: 'ביטול',
                      onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(width: 8),
                  RecommendedActionButton(text: 'פתח', onPressed: _submit),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
