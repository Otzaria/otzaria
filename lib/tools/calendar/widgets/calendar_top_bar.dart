// lib/tools/calendar/widgets/calendar_top_bar.dart
//
// סרגל עליון מחודש ללוח השנה — מבוסס AppTopBar.
//
// פריסה (RTL):
// ┌──────────────────────────────────────────────────────────┐
// │ [יום|שבוע|חודש]  [← date →]  [היום] [📅]  ║  [⚙️][📅][⏰] ║ [🖨️] │
// └──────────────────────────────────────────────────────────┘
//
// RTL = ימין:  view switcher → prev → date text → next → היום → jump
// RTL = שמאל: הגדרות → אירועים → זמנים | הדפסה

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_side_panel.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/widgets/app_menu.dart';
import 'package:otzaria/widgets/app_top_bar.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

class CalendarTopBar extends StatefulWidget {
  final CalendarState state;
  final VoidCallback onJumpToToday;
  final VoidCallback onPreviousPeriod;
  final VoidCallback onNextPeriod;
  final ValueChanged<CalendarView> onViewChanged;
  final ValueChanged<CalendarSidePanelView> onSidePanelViewChanged;
  final CalendarSidePanelView activeSidePanelView;
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
    required this.onSidePanelViewChanged,
    required this.activeSidePanelView,
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

  String get _dateText {
    final s = widget.state;
    final heb =
        '${formatHebrewDay(s.selectedJewishDate.getJewishDayOfMonth())} '
        '${getHebrewMonthNameFor(s.selectedJewishDate)} '
        '${numberToHebrewWithoutQuotes(s.selectedJewishDate.getJewishYear())}';
    final greg =
        '${s.selectedGregorianDate.day} ${getGregorianMonthName(s.selectedGregorianDate.month)} ${s.selectedGregorianDate.year}';
    return '$heb  •  $greg';
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

    // ── Leading (ימין ב-RTL): view switcher + ניווט תאריך + היום + מעבר ──

    final viewSwitcher = _buildViewSwitcher(state);
    final prevBtn = ToolbarActionButton(
      compact: true,
      tooltip: 'קודם',
      icon: FluentIcons.chevron_right_24_regular,
      emphasis: ToolbarActionButtonEmphasis.subtle,
      onPressed: widget.onPreviousPeriod,
    );
    final nextBtn = ToolbarActionButton(
      compact: true,
      tooltip: 'הבא',
      icon: FluentIcons.chevron_left_24_regular,
      emphasis: ToolbarActionButtonEmphasis.subtle,
      onPressed: widget.onNextPeriod,
    );
    final dateText = Text(
      _dateText,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      textDirection: TextDirection.rtl,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
    final todayBtn = RecommendedActionButton(
      text: 'היום',
      onPressed: widget.onJumpToToday,
    );
    final jumpBtn = ToolbarActionButton(
      key: _jumpButtonKey,
      compact: true,
      tooltip: 'מעבר לתאריך',
      icon: FluentIcons.calendar_24_regular,
      emphasis: ToolbarActionButtonEmphasis.subtle,
      onPressed: _openJumpPopover,
    );

    // ── Trailing (שמאל ב-RTL): הגדרות, אירועים, זמנים | הדפסה ─────────────

    final settingsBtn = ToolbarActionButton(
      compact: true,
      tooltip: 'הגדרות לוח שנה',
      icon: FluentIcons.settings_24_regular,
      selected: widget.activeSidePanelView == CalendarSidePanelView.settings,
      onPressed: () =>
          widget.onSidePanelViewChanged(CalendarSidePanelView.settings),
    );
    final eventsBtn = ToolbarActionButton(
      compact: true,
      tooltip: 'אירועים',
      icon: FluentIcons.calendar_ltr_24_regular,
      selected: widget.activeSidePanelView == CalendarSidePanelView.events,
      onPressed: () =>
          widget.onSidePanelViewChanged(CalendarSidePanelView.events),
    );
    final timesBtn = ToolbarActionButton(
      compact: true,
      tooltip: 'זמנים',
      icon: FluentIcons.clock_24_regular,
      selected: widget.activeSidePanelView == CalendarSidePanelView.times,
      onPressed: () =>
          widget.onSidePanelViewChanged(CalendarSidePanelView.times),
    );
    final printBtn = ToolbarActionButton(
      compact: true,
      tooltip: 'הדפסה',
      icon: FluentIcons.print_24_regular,
      emphasis: ToolbarActionButtonEmphasis.subtle,
      onPressed: widget.onPrint,
    );

    return AppTopBar(
      isCompact: true,
      leadingItems: [
        AppTopBarItem(widget: viewSwitcher),
        AppTopBarItem(widget: prevBtn, dividerBefore: true),
        AppTopBarItem(widget: nextBtn),
        AppTopBarItem(widget: todayBtn, dividerBefore: true),
        AppTopBarItem(widget: jumpBtn),
      ],
      center: dateText,
      trailingItems: [
        AppTopBarItem(widget: printBtn),
        AppTopBarItem(widget: timesBtn, dividerBefore: true),
        AppTopBarItem(widget: eventsBtn),
        AppTopBarItem(widget: settingsBtn),
      ],
    );
  }

  // ── View switcher ─────────────────────────────────────────────────────────

  Widget _buildViewSwitcher(CalendarState state) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ViewBtn(
          label: 'יום',
          selected: state.calendarView == CalendarView.day,
          onPressed: () => widget.onViewChanged(CalendarView.day),
        ),
        _ViewBtn(
          label: 'שבוע',
          selected: state.calendarView == CalendarView.week,
          onPressed: () => widget.onViewChanged(CalendarView.week),
        ),
        _ViewBtn(
          label: 'חודש',
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

  const _ViewBtn({
    required this.label,
    required this.selected,
    required this.onPressed,
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
    final shadowColor = selected
        ? cs.shadow.withValues(alpha: 0.08)
        : Colors.transparent;

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
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            ),
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
