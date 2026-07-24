// lib/tools/calendar/widgets/calendar_date_picker_panel.dart
//
// בורר תאריך משותף ללוח השנה: רשת חודש עברי או לועזי — באותו עיצוב.
// משמש גם בדיאלוג האירוע וגם בחיפוש "מעבר לתאריך" בסרגל העליון.
// כפתור החלפת הלוח (עברי/לועזי) חיצוני — מוצב בכותרת הדיאלוג ע"י הקורא.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart'
    show CalendarType;
import 'package:otzaria/widgets/controls/action_buttons.dart';

/// האם להציג את הלוח העברי כברירת מחדל לפי סוג הלוח שבהגדרות:
/// משולב/עברי → עברי, לועזי → לועזי.
bool calendarDefaultShowHebrew(CalendarType type) =>
    type != CalendarType.gregorian;

/// כפתור החלפה בין לוח עברי ללועזי — נועד להצבה בכותרת הדיאלוג.
class CalendarTypeToggleButton extends StatelessWidget {
  final bool showHebrew;
  final VoidCallback onPressed;

  const CalendarTypeToggleButton({
    super.key,
    required this.showHebrew,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ActionButton.ghost(
      text: showHebrew ? 'הצג בלוח לועזי' : 'הצג בלוח עברי',
      icon: FluentIcons.arrow_sync_24_regular,
      onPressed: onPressed,
    );
  }
}

/// פאנל בחירת תאריך שמציג רשת חודש עברי או לועזי לפי [showHebrew].
///
/// מבוקר: הקורא מחזיק את מצב [showHebrew] ומחליף אותו דרך
/// [CalendarTypeToggleButton] בכותרת.
class CalendarDatePickerPanel extends StatelessWidget {
  final DateTime selectedDate;
  final DateTime currentDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDateChanged;
  final bool showHebrew;
  final double bodyHeight;

  const CalendarDatePickerPanel({
    super.key,
    required this.selectedDate,
    required this.currentDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDateChanged,
    required this.showHebrew,
    this.bodyHeight = 300,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: bodyHeight,
      child: showHebrew
          ? _HebrewMonthGrid(
              selectedDate: selectedDate,
              currentDate: currentDate,
              firstDate: firstDate,
              lastDate: lastDate,
              onDateChanged: onDateChanged,
            )
          : _GregorianMonthGrid(
              selectedDate: selectedDate,
              currentDate: currentDate,
              firstDate: firstDate,
              lastDate: lastDate,
              onDateChanged: onDateChanged,
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  רשת חודש — עברי / לועזי (עיצוב זהה)
// ═══════════════════════════════════════════════════════════════════════════

const List<String> _kWeekdayLabels = ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ש'];

/// כותרת ניווט חודש + שמות ימים + רשת התאים — משותפת לשני הלוחות.
class _MonthGridScaffold extends StatelessWidget {
  final String monthTitle;
  final bool canGoPrev;
  final bool canGoNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final int leadingBlanks;
  final int daysInMonth;
  final Widget Function(int day) buildCell;

  const _MonthGridScaffold({
    required this.monthTitle,
    required this.canGoPrev,
    required this.canGoNext,
    required this.onPrev,
    required this.onNext,
    required this.leadingBlanks,
    required this.daysInMonth,
    required this.buildCell,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rowCount = ((leadingBlanks + daysInMonth) / 7).ceil();

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: canGoPrev ? onPrev : null,
              icon: const Icon(FluentIcons.chevron_left_24_regular),
              tooltip: 'חודש קודם',
            ),
            Expanded(
              child: Center(
                child: Text(monthTitle, style: theme.textTheme.titleMedium),
              ),
            ),
            IconButton(
              onPressed: canGoNext ? onNext : null,
              icon: const Icon(FluentIcons.chevron_right_24_regular),
              tooltip: 'חודש הבא',
            ),
          ],
        ),
        Row(
          children: [
            for (final label in _kWeekdayLabels)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Column(
            children: [
              for (int r = 0; r < rowCount; r++)
                Expanded(
                  child: Row(
                    children: [
                      for (int c = 0; c < 7; c++)
                        Expanded(
                          child: Builder(
                            builder: (_) {
                              final index = r * 7 + c;
                              if (index < leadingBlanks ||
                                  index >= leadingBlanks + daysInMonth) {
                                return const SizedBox.shrink();
                              }
                              return buildCell(index - leadingBlanks + 1);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// תא יום בודד — עיצוב משותף לשני הלוחות.
class _DateCell extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isToday;
  final bool enabled;
  final VoidCallback onTap;

  const _DateCell({
    required this.label,
    required this.isSelected,
    required this.isToday,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: isSelected ? cs.primary : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: isToday && !isSelected
              ? BorderSide(color: cs.primary)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? cs.onPrimary
                    : enabled
                    ? cs.onSurface
                    : Theme.of(context).disabledColor,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── רשת חודש עברי ───────────────────────────────────────────────────────────

class _HebrewMonthGrid extends StatefulWidget {
  final DateTime selectedDate;
  final DateTime currentDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDateChanged;

  const _HebrewMonthGrid({
    required this.selectedDate,
    required this.currentDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDateChanged,
  });

  @override
  State<_HebrewMonthGrid> createState() => _HebrewMonthGridState();
}

class _HebrewMonthGridState extends State<_HebrewMonthGrid> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _syncToSelected();
  }

  @override
  void didUpdateWidget(covariant _HebrewMonthGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) _syncToSelected();
  }

  void _syncToSelected() {
    final jd = JewishDate.fromDateTime(widget.selectedDate);
    _year = jd.getJewishYear();
    _month = jd.getJewishMonth();
  }

  void _shiftMonth(int delta) {
    final jd = JewishDate()..setJewishDate(_year, _month, 1);
    if (delta > 0) {
      jd.forward(Calendar.MONTH, delta);
    } else {
      jd.back(Calendar.MONTH, -delta);
    }
    setState(() {
      _year = jd.getJewishYear();
      _month = jd.getJewishMonth();
    });
  }

  bool get _canGoNext {
    final jd = JewishDate()..setJewishDate(_year, _month, 1);
    jd.forward(Calendar.MONTH, 1);
    return !jd.getGregorianCalendar().isAfter(widget.lastDate);
  }

  bool get _canGoPrev {
    final jd = JewishDate()..setJewishDate(_year, _month, 1);
    jd.back(Calendar.MONTH, 1);
    final lastDay = JewishDate()
      ..setJewishDate(
        jd.getJewishYear(),
        jd.getJewishMonth(),
        jd.getDaysInJewishMonth(),
      );
    return !lastDay.getGregorianCalendar().isBefore(widget.firstDate);
  }

  @override
  Widget build(BuildContext context) {
    final monthStart = JewishDate()..setJewishDate(_year, _month, 1);
    final daysInMonth = monthStart.getDaysInJewishMonth();
    final selectedJd = JewishDate.fromDateTime(widget.selectedDate);
    final todayJd = JewishDate.fromDateTime(widget.currentDate);

    return _MonthGridScaffold(
      monthTitle:
          '${getHebrewMonthNameFor(monthStart)} ${formatHebrewYear(_year)}',
      canGoPrev: _canGoPrev,
      canGoNext: _canGoNext,
      onPrev: () => _shiftMonth(-1),
      onNext: () => _shiftMonth(1),
      leadingBlanks: monthStart.getDayOfWeek() - 1,
      daysInMonth: daysInMonth,
      buildCell: (day) {
        final cellDate = (JewishDate()..setJewishDate(_year, _month, day))
            .getGregorianCalendar();
        return _DateCell(
          label: formatHebrewDay(day),
          isSelected:
              _year == selectedJd.getJewishYear() &&
              _month == selectedJd.getJewishMonth() &&
              day == selectedJd.getJewishDayOfMonth(),
          isToday:
              _year == todayJd.getJewishYear() &&
              _month == todayJd.getJewishMonth() &&
              day == todayJd.getJewishDayOfMonth(),
          enabled:
              !cellDate.isBefore(widget.firstDate) &&
              !cellDate.isAfter(widget.lastDate),
          onTap: () => widget.onDateChanged(cellDate),
        );
      },
    );
  }
}

// ── רשת חודש לועזי ──────────────────────────────────────────────────────────

class _GregorianMonthGrid extends StatefulWidget {
  final DateTime selectedDate;
  final DateTime currentDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDateChanged;

  const _GregorianMonthGrid({
    required this.selectedDate,
    required this.currentDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDateChanged,
  });

  @override
  State<_GregorianMonthGrid> createState() => _GregorianMonthGridState();
}

class _GregorianMonthGridState extends State<_GregorianMonthGrid> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _syncToSelected();
  }

  @override
  void didUpdateWidget(covariant _GregorianMonthGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) _syncToSelected();
  }

  void _syncToSelected() {
    _year = widget.selectedDate.year;
    _month = widget.selectedDate.month;
  }

  void _shiftMonth(int delta) {
    setState(() {
      final shifted = DateTime(_year, _month + delta, 1);
      _year = shifted.year;
      _month = shifted.month;
    });
  }

  bool get _canGoNext =>
      !DateTime(_year, _month + 1, 1).isAfter(widget.lastDate);

  bool get _canGoPrev {
    final prevMonthLastDay = DateTime(_year, _month, 0);
    return !prevMonthLastDay.isBefore(widget.firstDate);
  }

  @override
  Widget build(BuildContext context) {
    final monthStart = DateTime(_year, _month, 1);
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final selected = widget.selectedDate;
    final today = widget.currentDate;

    return _MonthGridScaffold(
      monthTitle: '${getGregorianMonthName(_month)} $_year',
      canGoPrev: _canGoPrev,
      canGoNext: _canGoNext,
      onPrev: () => _shiftMonth(-1),
      onNext: () => _shiftMonth(1),
      leadingBlanks: monthStart.weekday % 7,
      daysInMonth: daysInMonth,
      buildCell: (day) {
        final cellDate = DateTime(_year, _month, day);
        return _DateCell(
          label: '$day',
          isSelected:
              _year == selected.year &&
              _month == selected.month &&
              day == selected.day,
          isToday:
              _year == today.year && _month == today.month && day == today.day,
          enabled:
              !cellDate.isBefore(widget.firstDate) &&
              !cellDate.isAfter(widget.lastDate),
          onTap: () => widget.onDateChanged(cellDate),
        );
      },
    );
  }
}
