import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_date_formatters.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_day_cell.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/floating_panel.dart';

class CalendarMainPanel extends StatelessWidget {
  final CalendarState state;
  final void Function({CustomEvent? existingEvent, DateTime? specificDate})
      onCreateEvent;

  const CalendarMainPanel({
    super.key,
    required this.state,
    required this.onCreateEvent,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingPanel(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: KeyedSubtree(
            key: ValueKey(state.calendarView),
            child: _buildCalendarGrid(context, state),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarGrid(BuildContext context, CalendarState state) {
    return switch (state.calendarView) {
      CalendarView.month => _buildMonthView(context, state),
      CalendarView.week => _buildWeekView(context, state),
      CalendarView.day => _buildDayView(context, state),
    };
  }

  Widget _buildDayNamesRow(BuildContext context) {
    return Row(
      children: kHebrewDays
          .map(
            (day) => Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  day,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildMonthView(BuildContext context, CalendarState state) {
    return Column(
      children: [
        _buildDayNamesRow(context),
        const SizedBox(height: 8),
        _buildCalendarDays(context, state),
      ],
    );
  }

  Widget _buildWeekView(BuildContext context, CalendarState state) {
    return _buildScheduleView(
      context,
      state,
      title: 'תצוגת שבוע',
      days: _buildWeekDates(state),
    );
  }

  Widget _buildDayView(BuildContext context, CalendarState state) {
    return _buildScheduleView(
      context,
      state,
      title: 'תצוגת יום',
      days: [state.selectedGregorianDate],
    );
  }

  Widget _buildScheduleView(
    BuildContext context,
    CalendarState state, {
    required String title,
    required List<DateTime> days,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: state.calendarView == CalendarView.day
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTokens.radiusLG),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                ToolbarActionButton(
                  tooltip: 'צור אירוע',
                  icon: FluentIcons.add_24_regular,
                  onPressed: () => onCreateEvent(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (days.length == 1)
              _buildSingleDayTimeline(context, state, days.first)
            else
              Column(
                children: [
                  for (final day in days) ...[
                    _buildWeekDaySection(context, state, day),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleDayTimeline(
    BuildContext context,
    CalendarState state,
    DateTime day,
  ) {
    final events = _eventsForDate(state, day);
    final allDayEvents =
        events.where((event) => event.eventTime == null).toList();
    final timedEvents =
        events.where((event) => event.eventTime != null).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDayHeader(context, state, day),
        if (allDayEvents.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildAllDayEvents(context, allDayEvents),
        ],
        const SizedBox(height: 12),
        for (int hour = 0; hour < 24; hour++)
          _buildHourSlot(
            context,
            hour: hour,
            events: timedEvents.where((event) {
              final time = event.eventTime;
              return time != null && time.hour == hour;
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildWeekDaySection(
    BuildContext context,
    CalendarState state,
    DateTime day,
  ) {
    final events = _eventsForDate(state, day);
    final allDayEvents =
        events.where((event) => event.eventTime == null).toList();
    final timedEvents =
        events.where((event) => event.eventTime != null).toList();

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDayHeader(context, state, day),
            if (allDayEvents.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildAllDayEvents(context, allDayEvents),
            ],
            const SizedBox(height: 10),
            for (int hour = 0; hour < 24; hour++)
              _buildHourSlot(
                context,
                compact: true,
                hour: hour,
                events: timedEvents.where((event) {
                  final time = event.eventTime;
                  return time != null && time.hour == hour;
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayHeader(
    BuildContext context,
    CalendarState state,
    DateTime day,
  ) {
    final jewishDate = JewishDate.fromDateTime(day);
    final isSelected = day.year == state.selectedGregorianDate.year &&
        day.month == state.selectedGregorianDate.month &&
        day.day == state.selectedGregorianDate.day;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kHebrewDays[day.weekday % 7],
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatHebrewDay(jewishDate.getJewishDayOfMonth())} ${getHebrewMonthNameFor(jewishDate)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Text(
            '${day.day} ${getGregorianMonthName(day.month)} ${day.year}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllDayEvents(
    BuildContext context,
    List<CustomEvent> events,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final event in events)
          _buildEventCard(
            context,
            event,
            compact: true,
            showTime: false,
          ),
      ],
    );
  }

  Widget _buildHourSlot(
    BuildContext context, {
    required int hour,
    required List<CustomEvent> events,
    bool compact = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 4 : 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: hour.isEven
            ? scheme.surfaceContainerLowest
            : scheme.surfaceContainerLow.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              '${hour.toString().padLeft(2, '0')}:00',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: events.isEmpty
                ? const SizedBox.shrink()
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final event in events)
                        _buildEventCard(
                          context,
                          event,
                          compact: compact,
                          showTime: true,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(
    BuildContext context,
    CustomEvent event, {
    required bool compact,
    required bool showTime,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final bgColor = event.eventTime != null
        ? scheme.primaryContainer.withValues(alpha: 0.6)
        : scheme.secondaryContainer.withValues(alpha: 0.55);
    final fgColor = event.eventTime != null
        ? scheme.onPrimaryContainer
        : scheme.onSecondaryContainer;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: compact ? 140 : 170,
        maxWidth: compact ? 220 : 260,
      ),
      child: Card(
        elevation: 0,
        color: bgColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMD),
          side: BorderSide(color: fgColor.withValues(alpha: 0.15)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                event.title,
                maxLines: compact ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: fgColor,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (showTime && event.eventTime != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${event.eventTime!.hour.toString().padLeft(2, '0')}:${event.eventTime!.minute.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: fgColor,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<DateTime> _buildWeekDates(CalendarState state) {
    final selectedDate = state.selectedGregorianDate;
    final startOfWeek =
        selectedDate.subtract(Duration(days: selectedDate.weekday % 7));
    return [
      for (int i = 0; i < 7; i++) startOfWeek.add(Duration(days: i)),
    ];
  }

  Widget _buildCalendarDays(BuildContext context, CalendarState state) {
    return state.calendarType == CalendarType.gregorian
        ? _buildGregorianCalendarDays(context, state)
        : _buildHebrewCalendarDays(context, state);
  }

  Widget _buildHebrewCalendarDays(BuildContext context, CalendarState state) {
    final currentJewishDate = state.currentJewishDate;
    final daysInMonth = currentJewishDate.getDaysInJewishMonth();
    final firstDayOfMonth = JewishDate()
      ..setJewishDate(
        currentJewishDate.getJewishYear(),
        currentJewishDate.getJewishMonth(),
        1,
      );
    final startingWeekday = firstDayOfMonth.getGregorianCalendar().weekday % 7;

    final dayWidgets = <Widget>[];
    if (startingWeekday > 0) {
      final previousMonth = JewishDate()
        ..setJewishDate(
          currentJewishDate.getJewishYear(),
          currentJewishDate.getJewishMonth(),
          1,
        );
      previousMonth.back();
      final daysInPreviousMonth = previousMonth.getDaysInJewishMonth();
      for (int i = startingWeekday - 1; i >= 0; i--) {
        dayWidgets.add(
          _buildHebrewDayCell(
            context,
            state,
            daysInPreviousMonth - i,
            isFromOtherMonth: true,
            monthOffset: -1,
          ),
        );
      }
    }
    for (int day = 1; day <= daysInMonth; day++) {
      dayWidgets.add(_buildHebrewDayCell(context, state, day));
    }
    final totalCells = ((dayWidgets.length / 7).ceil()) * 7;
    for (int day = 1; day <= totalCells - dayWidgets.length; day++) {
      dayWidgets.add(
        _buildHebrewDayCell(
          context,
          state,
          day,
          isFromOtherMonth: true,
          monthOffset: 1,
        ),
      );
    }
    return Column(
      children: [
        for (int i = 0; i < dayWidgets.length; i += 7)
          Row(
            children: dayWidgets
                .sublist(
                  i,
                  i + 7 > dayWidgets.length ? dayWidgets.length : i + 7,
                )
                .map((w) => Expanded(child: w))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildGregorianCalendarDays(
    BuildContext context,
    CalendarState state,
  ) {
    final current = state.currentGregorianDate;
    final firstDayOfMonth = DateTime(current.year, current.month, 1);
    final daysInMonth = DateTime(current.year, current.month + 1, 0).day;
    final startingWeekday = firstDayOfMonth.weekday % 7;

    final dayWidgets = <Widget>[];
    if (startingWeekday > 0) {
      final daysInPreviousMonth = DateTime(current.year, current.month, 0).day;
      for (int i = startingWeekday - 1; i >= 0; i--) {
        dayWidgets.add(
          _buildGregorianDayCell(
            context,
            state,
            daysInPreviousMonth - i,
            isFromOtherMonth: true,
            monthOffset: -1,
          ),
        );
      }
    }
    for (int day = 1; day <= daysInMonth; day++) {
      dayWidgets.add(_buildGregorianDayCell(context, state, day));
    }
    final totalCells = ((dayWidgets.length / 7).ceil()) * 7;
    for (int day = 1; day <= totalCells - dayWidgets.length; day++) {
      dayWidgets.add(
        _buildGregorianDayCell(
          context,
          state,
          day,
          isFromOtherMonth: true,
          monthOffset: 1,
        ),
      );
    }
    return Column(
      children: [
        for (int i = 0; i < dayWidgets.length; i += 7)
          Row(
            children: dayWidgets
                .sublist(
                  i,
                  i + 7 > dayWidgets.length ? dayWidgets.length : i + 7,
                )
                .map((w) => Expanded(child: w))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildHebrewDayCell(
    BuildContext context,
    CalendarState state,
    int day, {
    bool isFromOtherMonth = false,
    int monthOffset = 0,
  }) {
    final jewishDate = JewishDate()
      ..setJewishDate(
        state.currentJewishDate.getJewishYear(),
        state.currentJewishDate.getJewishMonth(),
        1,
      );
    if (isFromOtherMonth) {
      if (monthOffset < 0) {
        jewishDate.back();
        jewishDate.setJewishDate(
          jewishDate.getJewishYear(),
          jewishDate.getJewishMonth(),
          1,
        );
      } else if (monthOffset > 0) {
        final daysInMonth = jewishDate.getDaysInJewishMonth();
        jewishDate.setJewishDate(
          jewishDate.getJewishYear(),
          jewishDate.getJewishMonth(),
          daysInMonth,
        );
        jewishDate.forward();
      }
      jewishDate.setJewishDate(
        jewishDate.getJewishYear(),
        jewishDate.getJewishMonth(),
        day,
      );
    } else {
      jewishDate.setJewishDate(
        state.currentJewishDate.getJewishYear(),
        state.currentJewishDate.getJewishMonth(),
        day,
      );
    }
    final gregorianDate = jewishDate.getGregorianCalendar();
    return buildDayCell(
      context,
      state,
      gregorianDate,
      jewishDate,
      isFromOtherMonth,
      () {
        if (isFromOtherMonth) {
          context.read<CalendarCubit>().jumpToDate(gregorianDate);
        } else {
          context.read<CalendarCubit>().selectDate(jewishDate, gregorianDate);
        }
      },
      () => onCreateEvent(specificDate: gregorianDate),
    );
  }

  Widget _buildGregorianDayCell(
    BuildContext context,
    CalendarState state,
    int day, {
    bool isFromOtherMonth = false,
    int monthOffset = 0,
  }) {
    final gregorianDate = DateTime(
      state.currentGregorianDate.year,
      state.currentGregorianDate.month + monthOffset,
      day,
    );
    final jewishDate = JewishDate.fromDateTime(gregorianDate);
    return buildDayCell(
      context,
      state,
      gregorianDate,
      jewishDate,
      isFromOtherMonth,
      () {
        if (isFromOtherMonth) {
          context.read<CalendarCubit>().jumpToDate(gregorianDate);
        } else {
          context.read<CalendarCubit>().selectDate(jewishDate, gregorianDate);
        }
      },
      () => onCreateEvent(specificDate: gregorianDate),
    );
  }

  List<CustomEvent> _eventsForDate(CalendarState state, DateTime date) {
    final jd = JewishDate.fromDateTime(date);
    final gY = date.year;
    final gM = date.month;
    final gD = date.day;
    final hY = jd.getJewishYear();
    final hM = jd.getJewishMonth();
    final hD = jd.getJewishDayOfMonth();
    final gWeekday = date.weekday;

    return state.events.where((event) {
      if (event.recurrenceType != RecurrenceType.none) {
        if (event.recurringYears != null && event.recurringYears! > 0) {
          bool expired = false;
          if (event.recurrenceType == RecurrenceType.annualHebrew ||
              event.recurrenceType == RecurrenceType.monthlyHebrew) {
            if (hY >= event.baseJewishYear + event.recurringYears!) {
              expired = true;
            }
          } else {
            if (gY >= event.baseGregorianDate.year + event.recurringYears!) {
              expired = true;
            }
          }
          if (expired) return false;
        }
        return switch (event.recurrenceType) {
          RecurrenceType.weekly => event.baseGregorianDate.weekday == gWeekday,
          RecurrenceType.monthlyHebrew => event.baseJewishDay == hD,
          RecurrenceType.monthlyGregorian => event.baseGregorianDate.day == gD,
          RecurrenceType.annualHebrew =>
            event.baseJewishMonth == hM && event.baseJewishDay == hD,
          RecurrenceType.annualGregorian =>
            event.baseGregorianDate.month == gM &&
                event.baseGregorianDate.day == gD,
          RecurrenceType.none => false,
        };
      }
      return event.baseGregorianDate.year == gY &&
          event.baseGregorianDate.month == gM &&
          event.baseGregorianDate.day == gD;
    }).toList()
      ..sort((a, b) {
        final aTime = a.eventTime;
        final bTime = b.eventTime;
        if (aTime == null && bTime != null) return -1;
        if (aTime != null && bTime == null) return 1;
        if (aTime == null && bTime == null) {
          return a.title.compareTo(b.title);
        }
        final aMinutes = aTime!.hour * 60 + aTime.minute;
        final bMinutes = bTime!.hour * 60 + bTime.minute;
        final timeCompare = aMinutes.compareTo(bMinutes);
        return timeCompare != 0 ? timeCompare : a.title.compareTo(b.title);
      });
  }
}
