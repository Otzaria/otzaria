import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_date_formatters.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_day_cell.dart';
import 'package:otzaria/widgets/app_floating_panel.dart';

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
    return AppFloatingPanel(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildCalendarGrid(context, state),
          ],
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
    return Column(
      children: [
        _buildDayNamesRow(context),
        const SizedBox(height: 8),
        _buildWeekDays(context, state),
      ],
    );
  }

  Widget _buildDayView(BuildContext context, CalendarState state) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        border:
            Border.all(color: cs.primary.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  kHebrewDays[state.selectedGregorianDate.weekday % 7],
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${formatHebrewDay(state.selectedJewishDate.getJewishDayOfMonth())} ${getHebrewMonthNameFor(state.selectedJewishDate)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${state.selectedGregorianDate.day} ${getGregorianMonthName(state.selectedGregorianDate.month)} ${state.selectedGregorianDate.year}',
                  style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: Tooltip(
              message: 'צור אירוע',
              child: IconButton.filled(
                icon: const Icon(FluentIcons.add_24_regular, size: 16),
                onPressed: () => onCreateEvent(),
                style: IconButton.styleFrom(
                  minimumSize: const Size(24, 24),
                  backgroundColor: cs.primaryContainer,
                  foregroundColor: cs.onPrimaryContainer,
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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

  Widget _buildWeekDays(BuildContext context, CalendarState state) {
    final selectedDate = state.selectedGregorianDate;
    final startOfWeek =
        selectedDate.subtract(Duration(days: selectedDate.weekday % 7));
    return Row(
      children: [
        for (int i = 0; i < 7; i++)
          Builder(
            builder: (context) {
              final dayDate = startOfWeek.add(Duration(days: i));
              final jewishDate = JewishDate.fromDateTime(dayDate);
              return Expanded(
                child: buildDayCell(
                  context,
                  state,
                  dayDate,
                  jewishDate,
                  false,
                  () => context
                      .read<CalendarCubit>()
                      .selectDate(jewishDate, dayDate),
                  () => onCreateEvent(specificDate: dayDate),
                ),
              );
            },
          ),
      ],
    );
  }
}
