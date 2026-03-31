import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';

/// מחזיר צבע רקע עדין לשבתות, מועדים ותעניות
Color? getDayBackgroundColor(
  BuildContext context,
  DateTime date,
  bool isSelected,
  bool isToday,
  bool inIsrael,
) {
  if (isSelected || isToday) return null;
  final jc = JewishCalendar.fromDateTime(date)..inIsrael = inIsrael;
  if (jc.getDayOfWeek() == 7 ||
      jc.isYomTov() ||
      jc.isTaanis() ||
      jc.isRoshChodesh()) {
    return Theme.of(context)
        .colorScheme
        .secondaryContainer
        .withValues(alpha: 0.4);
  }
  return null;
}

/// תא יום בלוח השנה
Widget buildDayCell(
  BuildContext context,
  CalendarState state,
  DateTime gregorianDate,
  JewishDate jewishDate,
  bool isFromOtherMonth,
  VoidCallback onTap,
  VoidCallback onAdd,
) {
  final isSelected = state.selectedJewishDate.getJewishDayOfMonth() ==
          jewishDate.getJewishDayOfMonth() &&
      state.selectedJewishDate.getJewishMonth() ==
          jewishDate.getJewishMonth() &&
      state.selectedJewishDate.getJewishYear() == jewishDate.getJewishYear();

  final today = DateTime.now();
  final isToday = gregorianDate.day == today.day &&
      gregorianDate.month == today.month &&
      gregorianDate.year == today.year;

  final cs = Theme.of(context).colorScheme;
  final baseCellColor = AppSurfaces.card(context);

  return HoverableDayCell(
    onAdd: onAdd,
    builder: (isHovered) {
      final baseBackground = getDayBackgroundColor(
              context, gregorianDate, isSelected, isToday, state.inIsrael) ??
          (isSelected
              ? cs.primaryContainer
              : isToday
                  ? cs.primary.withValues(alpha: 0.25)
                  : baseCellColor);
      final tintedBackground = (isHovered || isToday)
          ? Color.alphaBlend(
              cs.surfaceTint.withValues(alpha: 0.08), baseBackground)
          : baseBackground;
      final elevation = (isHovered || isToday) ? AppTokens.elevation2 : 0.0;

      return GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: isFromOtherMonth ? 0.4 : 1.0,
          child: Material(
            elevation: elevation,
            color: Colors.transparent,
            shadowColor: cs.shadow.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              margin: const EdgeInsets.all(2),
              height: 88,
              decoration: BoxDecoration(
                color: tintedBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? cs.primary
                      : isToday
                          ? cs.primary
                          : cs.outlineVariant,
                  width: isToday ? 2 : 1,
                ),
              ),
              child: Stack(
                children: [
                  // Primary date (ימין)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          (state.calendarType == CalendarType.hebrew ||
                                  state.calendarType == CalendarType.combined)
                              ? formatHebrewDay(
                                  jewishDate.getJewishDayOfMonth())
                              : '${gregorianDate.day}',
                          style: TextStyle(
                            color: isSelected
                                ? cs.onPrimaryContainer
                                : cs.onSurface,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize:
                                state.calendarType == CalendarType.combined
                                    ? 12
                                    : 14,
                          ),
                        ),
                        // שם חודש עברי בתחילת חודש אדר בשנה מעוברת
                        if ((state.calendarType == CalendarType.hebrew ||
                                state.calendarType == CalendarType.combined) &&
                            jewishDate.isJewishLeapYear() &&
                            (jewishDate.getJewishMonth() == 12 ||
                                jewishDate.getJewishMonth() == 13) &&
                            jewishDate.getJewishDayOfMonth() == 1)
                          Text(
                            getHebrewMonthNameFor(jewishDate),
                            style: TextStyle(
                              fontSize: 8,
                              color: isSelected
                                  ? cs.onPrimaryContainer
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Secondary date (שמאל — תצוגה משולבת)
                  if (state.calendarType == CalendarType.combined)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Text(
                        '${gregorianDate.day}',
                        style: TextStyle(
                          color: isSelected
                              ? cs.onPrimaryContainer.withValues(alpha: 0.85)
                              : cs.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  // אירועים ומועדים
                  Positioned(
                    top: 30,
                    left: 4,
                    right: 4,
                    child: DayExtras(
                        date: gregorianDate, inIsrael: state.inIsrael),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// מציג מועדים ואירועים מתחת לתאריך בתא
class DayExtras extends StatelessWidget {
  final DateTime date;
  final bool inIsrael;

  const DayExtras({super.key, required this.date, required this.inIsrael});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CalendarCubit>();
    final events = cubit.eventsForDate(date);
    final List<Widget> lines = [];
    final jc = JewishCalendar.fromDateTime(date)..inIsrael = inIsrael;

    for (final e in _calcJewishEvents(jc).take(2)) {
      lines.add(Text(
        e,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ));
    }

    for (final e in events.take(2)) {
      lines.add(Text(
        '• ${e.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontSize: 10,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ));
    }

    return Column(mainAxisSize: MainAxisSize.min, children: lines);
  }

  static String _numberToHebrewLetter(int n) {
    const letters = ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח'];
    if (n > 0 && n <= letters.length) return letters[n - 1];
    return '';
  }

  static List<String> _calcJewishEvents(JewishCalendar jc) {
    final List<String> l = [];
    final hdf = HebrewDateFormatter()..hebrewFormat = true;

    final yomTov = hdf.formatYomTov(jc);
    if (yomTov.isNotEmpty) {
      l.addAll(yomTov.split(',').map((e) => e.trim()));
    }

    if (jc.getDayOfWeek() == 7) {
      final parsha = hdf.formatParsha(jc);
      if (parsha.isNotEmpty) l.add(parsha);
    }

    if (jc.isRoshChodesh() && !l.contains('ראש חודש')) l.add('ר"ח');

    final yomTovIndex = jc.getYomTovIndex();

    if (yomTovIndex == JewishCalendar.CHOL_HAMOED_SUCCOS ||
        yomTovIndex == JewishCalendar.CHOL_HAMOED_PESACH) {
      l.removeWhere((e) => e.contains('חול המועד'));
      final dayOfCholHamoed = jc.getJewishDayOfMonth() - 15;
      l.add('${_numberToHebrewLetter(dayOfCholHamoed)} דחוה"מ');
    }

    if (yomTovIndex == JewishCalendar.CHANUKAH) {
      l.removeWhere((e) => e.contains('חנוכה'));
      final dayOfChanukah = jc.getDayOfChanukah();
      if (dayOfChanukah != -1) {
        l.add('נר ${_numberToHebrewLetter(dayOfChanukah)} דחנוכה');
      }
    }

    if (yomTovIndex == JewishCalendar.HOSHANA_RABBA) l.add("ו' דחוה\"מ");

    if (jc.getJewishMonth() == 7) {
      if (jc.getJewishDayOfMonth() == 22) {
        if (!l.contains('שמיני עצרת')) l.add('שמיני עצרת');
        if (jc.inIsrael && !l.contains('שמחת תורה')) l.add('שמחת תורה');
      }
      if (jc.getJewishDayOfMonth() == 23 && !jc.inIsrael) {
        if (!l.contains('שמחת תורה')) l.add('שמחת תורה');
      }
    }

    return l.toSet().toList();
  }
}

/// עוטף תא יום — מציג כפתור הוספה בריחוף
class HoverableDayCell extends StatefulWidget {
  final Widget Function(bool isHovered) builder;
  final VoidCallback onAdd;

  const HoverableDayCell({
    super.key,
    required this.builder,
    required this.onAdd,
  });

  @override
  State<HoverableDayCell> createState() => _HoverableDayCellState();
}

class _HoverableDayCellState extends State<HoverableDayCell> {
  bool _showButton = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() {
        _showButton = true;
        _isHovered = true;
      }),
      onExit: (_) => setState(() {
        _showButton = false;
        _isHovered = false;
      }),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Listener(
            onPointerDown: (_) => setState(() {
              _showButton = true;
              _isHovered = true;
            }),
            child: widget.builder(_isHovered),
          ),
          AnimatedOpacity(
            opacity: _showButton ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: IgnorePointer(
                ignoring: !_showButton,
                child: Tooltip(
                  message: 'צור אירוע',
                  verticalOffset: -40.0,
                  child: IconButton.filled(
                    icon: const Icon(FluentIcons.add_24_regular, size: 16),
                    onPressed: widget.onAdd,
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
            ),
          ),
        ],
      ),
    );
  }
}
