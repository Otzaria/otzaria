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
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_day_cell.dart';
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
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return FloatingPanel(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          children: [
            _buildDayNamesRow(context),
            const SizedBox(height: 4),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: KeyedSubtree(
                  key: ValueKey(
                      '${state.calendarView}-${state.currentGregorianDate.month}-${state.currentGregorianDate.year}-${state.selectedGregorianDate.day}'),
                  child: _buildCalendarGrid(context, state),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Row של שמות הימים ─────────────────────────────────────────────────────

  Widget _buildDayNamesRow(BuildContext context) {
    return Row(
      children: kHebrewDays
          .map((day) => Expanded(
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
              ))
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
        return Expanded(
          child: buildDayCell(
            context,
            state,
            cell.gregorian,
            cell.jewish,
            false,
            () => context
                .read<CalendarCubit>()
                .selectDate(cell.jewish, cell.gregorian),
            () => onCreateEvent(specificDate: cell.gregorian),
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
    final totalCells = ((cells.length / 7).ceil()) * 7;
    for (int day = 1; day <= totalCells - cells.length; day++) {
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
            currentJD.getJewishYear(), currentJD.getJewishMonth(), 1);
      prevMonth.back();
      final daysInPrev = prevMonth.getDaysInJewishMonth();
      for (int i = startWeekday - 1; i >= 0; i--) {
        final jd = JewishDate()
          ..setJewishDate(prevMonth.getJewishYear(), prevMonth.getJewishMonth(),
              daysInPrev - i);
        cells.add(_CellData(jd.getGregorianCalendar(), jd, isOtherMonth: true));
      }
    }

    // ימי החודש הנוכחי
    for (int day = 1; day <= daysInMonth; day++) {
      final jd = JewishDate()
        ..setJewishDate(
            currentJD.getJewishYear(), currentJD.getJewishMonth(), day);
      cells.add(_CellData(jd.getGregorianCalendar(), jd));
    }

    // ימים מהחודש הבא
    final totalCells = ((cells.length / 7).ceil()) * 7;
    final lastDay = JewishDate()
      ..setJewishDate(
          currentJD.getJewishYear(), currentJD.getJewishMonth(), daysInMonth);
    lastDay.forward();
    for (int day = 1; day <= totalCells - cells.length; day++) {
      final jd = JewishDate()
        ..setJewishDate(lastDay.getJewishYear(), lastDay.getJewishMonth(), day);
      cells.add(_CellData(jd.getGregorianCalendar(), jd, isOtherMonth: true));
    }

    return _buildRowsFromCells(context, state, cells);
  }

  // ── בנה שורות ─────────────────────────────────────────────────────────────

  Widget _buildRowsFromCells(
      BuildContext context, CalendarState state, List<_CellData> cells) {
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
                  context
                      .read<CalendarCubit>()
                      .selectDate(cell.jewish, cell.gregorian);
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
