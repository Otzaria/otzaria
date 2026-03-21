import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/view/panels/calendar_side_panel.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_date_formatters.dart';
import 'package:otzaria/widgets/app_menu.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:otzaria/core/widgets/otzaria_search_field.dart';

class CalendarTopBar extends StatefulWidget implements PreferredSizeWidget {
  final CalendarState state;
  final bool isSearchMode;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onToggleSearch;
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
    required this.isSearchMode,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.onToggleSearch,
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
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  State<CalendarTopBar> createState() => _CalendarTopBarState();
}

class _CalendarTopBarState extends State<CalendarTopBar> {
  final GlobalKey _jumpButtonKey = GlobalKey();

  bool get _showLabels {
    final width = MediaQuery.of(context).size.width;
    return width >= 1180;
  }

  Future<void> _openJumpPopover() async {
    final anchorContext = _jumpButtonKey.currentContext;
    if (anchorContext == null) return;

    final selected = await showAnchoredAppMenu<DateTime>(
      context: context,
      anchorContext: anchorContext,
      itemsBuilder: (metrics) => [
        buildAppCustomPopupMenuItem<DateTime>(
          context: context,
          metrics: metrics,
          child: SizedBox(
            width: 360,
            child: _JumpToDatePopover(
              parseInputDate: widget.parseInputDate,
              onDateSelected: (date) {
                Navigator.of(context).pop(date);
              },
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
    final isWide = _showLabels;
    final dayText =
        '${kHebrewDays[state.selectedGregorianDate.weekday % 7]} • ${formatHebrewDay(state.selectedJewishDate.getJewishDayOfMonth())} ${getHebrewMonthNameFor(state.selectedJewishDate)} • ${state.selectedGregorianDate.day} ${getGregorianMonthName(state.selectedGregorianDate.month)} ${state.selectedGregorianDate.year}';

    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: AppTokens.spaceMD,
      centerTitle: true,
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: widget.isSearchMode
            ? Row(
                key: const ValueKey('search'),
                children: [
                  Expanded(
                    child: OtzariaSearchField(
                      controller: widget.searchController,
                      focusNode: widget.searchFocusNode,
                      autofocus: true,
                      hintText: 'חפש אירועים, זמנים או טקסט',
                      onChanged: widget.onSearchChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ToolbarActionButton(
                    key: _jumpButtonKey,
                    tooltip: 'מעבר לתאריך',
                    icon: FluentIcons.calendar_24_regular,
                    onPressed: _openJumpPopover,
                  ),
                ],
              )
            : Row(
                key: const ValueKey('date'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  ToolbarActionButton(
                    tooltip: 'קודם',
                    icon: FluentIcons.chevron_right_24_regular,
                    onPressed: widget.onPreviousPeriod,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      dayText,
                      textDirection: TextDirection.rtl,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ToolbarActionButton(
                    tooltip: 'הבא',
                    icon: FluentIcons.chevron_left_24_regular,
                    onPressed: widget.onNextPeriod,
                  ),
                ],
              ),
      ),
      actions: [
        ToolbarActionButton(
          tooltip: widget.isSearchMode ? 'סגור חיפוש' : 'חיפוש',
          icon: widget.isSearchMode
              ? FluentIcons.dismiss_24_regular
              : FluentIcons.search_24_regular,
          selected: widget.isSearchMode,
          onPressed: widget.onToggleSearch,
        ),
        const SizedBox(width: 8),
        RecommendedActionButton(
          text: 'היום',
          icon: FluentIcons.calendar_today_24_regular,
          onPressed: widget.onJumpToToday,
        ),
        const SizedBox(width: 8),
        ToolbarActionButton(
          tooltip: 'יום',
          icon: FluentIcons.calendar_24_regular,
          selected: state.calendarView == CalendarView.day,
          label: isWide ? 'יום' : null,
          onPressed: () => widget.onViewChanged(CalendarView.day),
        ),
        const SizedBox(width: 8),
        ToolbarActionButton(
          tooltip: 'שבוע',
          icon: FluentIcons.calendar_24_filled,
          selected: state.calendarView == CalendarView.week,
          label: isWide ? 'שבוע' : null,
          onPressed: () => widget.onViewChanged(CalendarView.week),
        ),
        const SizedBox(width: 8),
        ToolbarActionButton(
          tooltip: 'חודש',
          icon: FluentIcons.calendar_month_24_regular,
          selected: state.calendarView == CalendarView.month,
          label: isWide ? 'חודש' : null,
          onPressed: () => widget.onViewChanged(CalendarView.month),
        ),
        const SizedBox(width: 8),
        ToolbarActionButton(
          tooltip: 'הדפס',
          icon: FluentIcons.print_24_regular,
          onPressed: widget.onPrint,
        ),
        const SizedBox(width: 8),
        ToolbarActionButton(
          tooltip: 'זמנים',
          icon: FluentIcons.clock_24_regular,
          selected: widget.activeSidePanelView == CalendarSidePanelView.times,
          label: isWide ? 'זמנים' : null,
          onPressed: () =>
              widget.onSidePanelViewChanged(CalendarSidePanelView.times),
        ),
        const SizedBox(width: 8),
        ToolbarActionButton(
          tooltip: 'אירועים',
          icon: FluentIcons.calendar_ltr_24_regular,
          selected: widget.activeSidePanelView == CalendarSidePanelView.events,
          label: isWide ? 'אירועים' : null,
          onPressed: () =>
              widget.onSidePanelViewChanged(CalendarSidePanelView.events),
        ),
        const SizedBox(width: 8),
        ToolbarActionButton(
          tooltip: 'הגדרות',
          icon: FluentIcons.settings_24_regular,
          selected:
              widget.activeSidePanelView == CalendarSidePanelView.settings,
          label: isWide ? 'הגדרות' : null,
          onPressed: () =>
              widget.onSidePanelViewChanged(CalendarSidePanelView.settings),
        ),
        const SizedBox(width: 8),
        ToolbarActionButton(
          tooltip: 'הצג/הסתר לוח צד',
          icon: FluentIcons.panel_right_24_regular,
          onPressed: widget.onToggleSidebar,
        ),
      ],
    );
  }
}

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
                  onDateChanged: (date) {
                    setState(() {
                      _selectedDate = date;
                      _controller.text =
                          '${date.day}/${date.month}/${date.year}';
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  NeutralActionButton(
                    text: 'ביטול',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  RecommendedActionButton(
                    text: 'פתח',
                    onPressed: _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
