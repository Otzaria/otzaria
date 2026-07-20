// lib/tools/calendar/widgets/calendar_main_panel.dart
//
// לוח חודש/שבוע מלא-מסך.
//
// **תצוגות:**
// • month: לוח חודש מלא — כל ימי החודש בגריד שבועי
// • week:  תצוגת שבוע — 7 תאים בלבד למילוי כל הגובה הזמין

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_day_cell.dart';

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCalendarWidth = _resolveMaxCalendarWidth(constraints);
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxCalendarWidth,
              minWidth: 0,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: [
                  _buildDayNamesRow(context),
                  const SizedBox(height: 4),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragEnd: (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity.abs() < 250) return;
                        final cubit = context.read<CalendarCubit>();
                        // גרירה מעלה = התקופה הבאה, גרירה מטה = הקודמת
                        velocity < 0 ? cubit.next() : cubit.previous();
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final slideAnimation = Tween<Offset>(
                            begin: const Offset(0.03, 0),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: slideAnimation,
                              child: child,
                            ),
                          );
                        },
                        layoutBuilder: (currentChild, previousChildren) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              ...previousChildren,
                              ?currentChild,
                            ],
                          );
                        },
                        child: KeyedSubtree(
                          key: _buildGridKey(state),
                          child: _buildCalendarGrid(context, state),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Key _buildGridKey(CalendarState state) {
    if (state.calendarView == CalendarView.week) {
      final weekStart = state.selectedGregorianDate.subtract(
        Duration(days: state.selectedGregorianDate.weekday % 7),
      );
      return ValueKey(
        'week-${weekStart.year}-${weekStart.month}-${weekStart.day}',
      );
    }
    if (state.calendarType == CalendarType.hebrew ||
        state.calendarType == CalendarType.combined) {
      final jd = state.currentJewishDate;
      return ValueKey(
        '${state.calendarView}-${jd.getJewishYear()}-${jd.getJewishMonth()}',
      );
    }
    return ValueKey(
      '${state.calendarView}-${state.currentGregorianDate.month}-${state.currentGregorianDate.year}',
    );
  }

  double _resolveMaxCalendarWidth(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    if (height <= 0 || width <= 0) {
      return width;
    }

    final isTallLayout = height > width * 1.15;
    if (isTallLayout) {
      return width;
    }

    final ratioLimitedWidth = height * 1.52;
    return ratioLimitedWidth.clamp(0.0, width);
  }

  // ── Row של שמות הימים ─────────────────────────────────────────────────────

  Widget _buildDayNamesRow(BuildContext context) {
    return Row(
      children: kHebrewDays
          .map(
            (day) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  day,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  // ── Grid ──────────────────────────────────────────────────────────────────

  Widget _buildCalendarGrid(BuildContext context, CalendarState state) {
    if (state.calendarView == CalendarView.week) {
      return _buildWeekView(context, state);
    }
    return state.calendarType == CalendarType.gregorian
        ? _buildGregorianGrid(context, state)
        : _buildHebrewGrid(context, state);
  }

  // ── Week view — 7 תאים ממלאים את כל הגובה ────────────────────────────────

  Widget _buildWeekView(BuildContext context, CalendarState state) {
    final selected = state.selectedGregorianDate;
    // תחילת השבוע: ראשון (weekday % 7 → 0=ראשון, 1=שני, ..., 6=שבת)
    final weekStart = selected.subtract(Duration(days: selected.weekday % 7));

    final cells = <_CellData>[];
    for (int i = 0; i < 7; i++) {
      final d = weekStart.add(Duration(days: i));
      cells.add(_CellData(d, JewishDate.fromDateTime(d)));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: cells.map((cell) {
        final shortTimes = context.read<CalendarCubit>().shortTimesFor(
          cell.gregorian,
        );
        final additionalInfoLines = <String>[
          if (shortTimes['sunrise'] case final sunrise?) 'זריחה $sunrise',
          if (shortTimes['sunset'] case final sunset?) 'שקיעה $sunset',
        ];
        return Expanded(
          child: buildDayCell(
            context,
            state,
            cell.gregorian,
            cell.jewish,
            false,
            () => context.read<CalendarCubit>().selectDate(
              cell.jewish,
              cell.gregorian,
            ),
            () => onCreateEvent(specificDate: cell.gregorian),
            additionalInfoLines: additionalInfoLines,
          ),
        );
      }).toList(),
    );
  }

  // ── Gregorian grid ────────────────────────────────────────────────────────

  Widget _buildGregorianGrid(BuildContext context, CalendarState state) {
    final current = state.currentGregorianDate;
    final firstDay = DateTime(current.year, current.month, 1);
    final daysInMonth = DateTime(current.year, current.month + 1, 0).day;
    final startWeekday = firstDay.weekday % 7;

    final cells = <_CellData>[];

    // ימים מהחודש הקודם
    if (startWeekday > 0) {
      final prevMonthDays = DateTime(current.year, current.month, 0).day;
      for (int i = startWeekday - 1; i >= 0; i--) {
        final d = DateTime(current.year, current.month - 1, prevMonthDays - i);
        cells.add(_CellData(d, JewishDate.fromDateTime(d), isOtherMonth: true));
      }
    }

    // ימי החודש הנוכחי
    for (int day = 1; day <= daysInMonth; day++) {
      final d = DateTime(current.year, current.month, day);
      cells.add(_CellData(d, JewishDate.fromDateTime(d)));
    }

    // ימים מהחודש הבא
    const totalCells = 42;
    final daysFromNext = totalCells - cells.length;
    for (int day = 1; day <= daysFromNext; day++) {
      final d = DateTime(current.year, current.month + 1, day);
      cells.add(_CellData(d, JewishDate.fromDateTime(d), isOtherMonth: true));
    }

    return _buildRowsFromCells(context, state, cells);
  }

  // ── Hebrew grid ───────────────────────────────────────────────────────────

  Widget _buildHebrewGrid(BuildContext context, CalendarState state) {
    final currentJD = state.currentJewishDate;
    final daysInMonth = currentJD.getDaysInJewishMonth();
    final firstDay = JewishDate()
      ..setJewishDate(currentJD.getJewishYear(), currentJD.getJewishMonth(), 1);
    final startWeekday = firstDay.getGregorianCalendar().weekday % 7;

    final cells = <_CellData>[];

    // ימים מהחודש הקודם
    if (startWeekday > 0) {
      final prevMonth = JewishDate()
        ..setJewishDate(
          currentJD.getJewishYear(),
          currentJD.getJewishMonth(),
          1,
        );
      prevMonth.back();
      final daysInPrev = prevMonth.getDaysInJewishMonth();
      for (int i = startWeekday - 1; i >= 0; i--) {
        final jd = JewishDate()
          ..setJewishDate(
            prevMonth.getJewishYear(),
            prevMonth.getJewishMonth(),
            daysInPrev - i,
          );
        cells.add(_CellData(jd.getGregorianCalendar(), jd, isOtherMonth: true));
      }
    }

    // ימי החודש הנוכחי
    for (int day = 1; day <= daysInMonth; day++) {
      final jd = JewishDate()
        ..setJewishDate(
          currentJD.getJewishYear(),
          currentJD.getJewishMonth(),
          day,
        );
      cells.add(_CellData(jd.getGregorianCalendar(), jd));
    }

    // ימים מהחודש הבא
    const totalCells = 42;
    final lastDay = JewishDate()
      ..setJewishDate(
        currentJD.getJewishYear(),
        currentJD.getJewishMonth(),
        daysInMonth,
      );
    lastDay.forward();
    final daysFromNext = totalCells - cells.length;
    for (int day = 1; day <= daysFromNext; day++) {
      final jd = JewishDate()
        ..setJewishDate(lastDay.getJewishYear(), lastDay.getJewishMonth(), day);
      cells.add(_CellData(jd.getGregorianCalendar(), jd, isOtherMonth: true));
    }

    return _buildRowsFromCells(context, state, cells);
  }

  // ── בנה שורות ─────────────────────────────────────────────────────────────

  Widget _buildRowsFromCells(
    BuildContext context,
    CalendarState state,
    List<_CellData> cells,
  ) {
    final numRows = cells.length ~/ 7;

    return Column(
      children: [
        for (int row = 0; row < numRows; row++)
          Expanded(
            child: _buildWeekRow(
              context,
              state,
              cells.sublist(row * 7, (row + 1) * 7),
            ),
          ),
      ],
    );
  }

  Widget _buildWeekRow(
    BuildContext context,
    CalendarState state,
    List<_CellData> weekCells,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: weekCells.map((cell) {
          return Expanded(
            child: buildDayCell(
              context,
              state,
              cell.gregorian,
              cell.jewish,
              cell.isOtherMonth,
              () {
                if (cell.isOtherMonth) {
                  context.read<CalendarCubit>().jumpToDate(cell.gregorian);
                } else {
                  context.read<CalendarCubit>().selectDate(
                    cell.jewish,
                    cell.gregorian,
                  );
                }
              },
              () => onCreateEvent(specificDate: cell.gregorian),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── _CellData ─────────────────────────────────────────────────────────────────

class _CellData {
  final DateTime gregorian;
  final JewishDate jewish;
  final bool isOtherMonth;

  const _CellData(this.gregorian, this.jewish, {this.isOtherMonth = false});
}
