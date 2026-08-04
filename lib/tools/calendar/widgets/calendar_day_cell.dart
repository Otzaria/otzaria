import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';

/// מחזיר צבע רקע עדין לשבתות, מועדים ותעניות
Color? getDayBackgroundColor(
  BuildContext context,
  JewishCalendar jc,
  bool isSelected,
  bool isToday,
) {
  if (isSelected || isToday) return null;
  if (jc.getDayOfWeek() == 7 ||
      jc.isYomTov() ||
      jc.isTaanis() ||
      jc.isRoshChodesh()) {
    return Theme.of(
      context,
    ).colorScheme.secondaryContainer.withValues(alpha: 0.4);
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
  VoidCallback onAdd, {
  List<String> additionalInfoLines = const [],
}) {
  final isSelected =
      state.selectedJewishDate.getJewishDayOfMonth() ==
          jewishDate.getJewishDayOfMonth() &&
      state.selectedJewishDate.getJewishMonth() ==
          jewishDate.getJewishMonth() &&
      state.selectedJewishDate.getJewishYear() == jewishDate.getJewishYear();

  final today = state.todayGregorianDate;
  final isToday =
      gregorianDate.day == today.day &&
      gregorianDate.month == today.month &&
      gregorianDate.year == today.year;

  final cs = Theme.of(context).colorScheme;
  final baseCellColor = AppSurfaces.card(context);

  // נבנה פעם אחת ומשותף ל-getDayBackgroundColor ול-DayExtras; ריחוף עכבר
  // (setState של HoverableDayCell) לא בונה אותו מחדש.
  final jewishCalendar = JewishCalendar.fromDateTime(gregorianDate)
    ..inIsrael = state.inIsrael;

  return HoverableDayCell(
    onAdd: onAdd,
    builder: (isHovered) {
      final baseBackground =
          getDayBackgroundColor(context, jewishCalendar, isSelected, isToday) ??
          (isSelected
              ? cs.primaryContainer
              : isToday
              ? cs.primary.withValues(alpha: 0.25)
              : baseCellColor);
      final tintedBackground = (isHovered || isToday)
          ? Color.alphaBlend(
              cs.surfaceTint.withValues(alpha: 0.08),
              baseBackground,
            )
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
            borderRadius: AppTokens.borderRadiusAll,
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: tintedBackground,
                borderRadius: AppTokens.borderRadiusAll,
                border: Border.all(
                  color: isSelected
                      ? cs.primary
                      : isToday
                      ? cs.primary
                      : cs.outlineVariant,
                  width: isToday ? 2 : 1,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compactCell = constraints.maxHeight < 84;
                  final veryCompactCell = constraints.maxHeight < 64;
                  final primaryFontSize =
                      state.calendarType == CalendarType.combined
                      ? (compactCell ? 11.0 : 12.0)
                      : (compactCell ? 12.0 : 14.0);
                  final secondaryFontSize = compactCell ? 9.0 : 10.0;
                  final monthLabelFontSize = compactCell ? 7.0 : 8.0;

                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      4,
                      compactCell ? 3 : 4,
                      4,
                      compactCell ? 3 : 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (state.calendarType == CalendarType.combined)
                              Text(
                                '${gregorianDate.day}',
                                style: TextStyle(
                                  color: isSelected
                                      ? cs.onPrimaryContainer.withValues(
                                          alpha: 0.85,
                                        )
                                      : cs.onSurfaceVariant,
                                  fontSize: secondaryFontSize,
                                ),
                              ),
                            const Spacer(),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  (state.calendarType == CalendarType.hebrew ||
                                          state.calendarType ==
                                              CalendarType.combined)
                                      ? formatHebrewDay(
                                          jewishDate.getJewishDayOfMonth(),
                                        )
                                      : '${gregorianDate.day}',
                                  style: TextStyle(
                                    color: isSelected
                                        ? cs.onPrimaryContainer
                                        : cs.onSurface,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: primaryFontSize,
                                  ),
                                ),
                                if ((state.calendarType ==
                                            CalendarType.hebrew ||
                                        state.calendarType ==
                                            CalendarType.combined) &&
                                    jewishDate.isJewishLeapYear() &&
                                    (jewishDate.getJewishMonth() == 12 ||
                                        jewishDate.getJewishMonth() == 13) &&
                                    jewishDate.getJewishDayOfMonth() == 1)
                                  Text(
                                    getHebrewMonthNameFor(jewishDate),
                                    style: TextStyle(
                                      fontSize: monthLabelFontSize,
                                      color: isSelected
                                          ? cs.onPrimaryContainer
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: compactCell ? 2 : 6),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: DayExtras(
                              jewishCalendar: jewishCalendar,
                              date: gregorianDate,
                              maxVisibleItems: veryCompactCell
                                  ? 0
                                  : (compactCell ? 1 : 2),
                              compact: compactCell,
                              additionalInfoLines: additionalInfoLines,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
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
  final JewishCalendar jewishCalendar;
  final DateTime date;
  final int maxVisibleItems;
  final bool compact;
  final List<String> additionalInfoLines;

  const DayExtras({
    super.key,
    required this.jewishCalendar,
    required this.date,
    this.maxVisibleItems = 2,
    this.compact = false,
    this.additionalInfoLines = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (maxVisibleItems <= 0) {
      return const SizedBox.shrink();
    }

    final cubit = context.read<CalendarCubit>();
    final events = cubit.eventsForDate(date);
    final List<Widget> lines = [];
    final jewishEvents = _calcJewishEvents(jewishCalendar);
    final visibleItems = <Widget>[];

    for (final e in jewishEvents.take(maxVisibleItems)) {
      visibleItems.add(
        Text(
          e,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 10 : 11,
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final brightness = Theme.of(context).brightness;
    var remainingSlots = maxVisibleItems - visibleItems.length;
    for (final e in events.take(remainingSlots.clamp(0, maxVisibleItems))) {
      final dotColor =
          CalendarEventColors.colorForIndex(e.displayColorIndex, brightness) ??
          Theme.of(context).colorScheme.onSurfaceVariant;
      visibleItems.add(
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '• ',
                style: TextStyle(color: dotColor),
              ),
              TextSpan(text: e.title),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 9 : 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    remainingSlots = maxVisibleItems - visibleItems.length;
    for (final info in additionalInfoLines.take(
      remainingSlots.clamp(0, maxVisibleItems),
    )) {
      visibleItems.add(
        Text(
          info,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 9 : 10,
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    lines.addAll(visibleItems);
    return Column(mainAxisSize: MainAxisSize.min, children: lines);
  }

  static String _numberToHebrewLetter(int n) {
    const letters = ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח'];
    if (n > 0 && n <= letters.length) return letters[n - 1];
    return '';
  }

  // משותף לכל התאים: formatYomTov/formatParsha מקבלים את היומן כארגומנט
  // ואינם שומרים מצב. אין לשנות עליו שדות — זה ישפיע על כל הלוח.
  static final HebrewDateFormatter _hdf = HebrewDateFormatter()
    ..hebrewFormat = true;

  static List<String> _calcJewishEvents(JewishCalendar jc) {
    final List<String> l = [];

    final yomTov = _hdf.formatYomTov(jc);
    if (yomTov.isNotEmpty) {
      l.addAll(yomTov.split(',').map((e) => e.trim()));
    }

    if (jc.getDayOfWeek() == 7) {
      final parsha = _hdf.formatParsha(jc);
      if (parsha.isNotEmpty) l.add(parsha);
    }

    if (jc.isRoshChodesh() && !l.contains('ראש חודש')) l.add('ר"ח');

    final yomTovIndex = jc.getYomTovIndex();

    if (yomTovIndex == JewishCalendar.CHOL_HAMOED_SUCCOS ||
        yomTovIndex == JewishCalendar.CHOL_HAMOED_PESACH) {
      l.removeWhere((e) => e.contains('חול המועד'));
      final dayOfCholHamoed = jc.getJewishDayOfMonth() - 15;
      final cholHamoedName = yomTovIndex == JewishCalendar.CHOL_HAMOED_PESACH
          ? 'פסח'
          : 'סוכות';
      l.add('${_numberToHebrewLetter(dayOfCholHamoed)} דחוה"מ $cholHamoedName');
    }

    if (yomTovIndex == JewishCalendar.PESACH) {
      final dayOfMonth = jc.getJewishDayOfMonth();
      if (dayOfMonth == 21) {
        l.removeWhere((e) => e == 'פסח');
        l.add('שביעי של פסח');
      }
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
