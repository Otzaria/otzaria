import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/settings/l10n/chrome_directionality.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';

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
      jc.isErevYomTov() ||
      jc.isTaanis() ||
      jc.isRoshChodesh()) {
    return AppSurfaces.calendarSpecialDay(Theme.of(context).colorScheme);
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
              ? AppSurfaces.calendarToday(cs)
              : baseCellColor);
      final tintedBackground = (isHovered || isToday)
          ? Color.alphaBlend(AppSurfaces.calendarDayTint(cs), baseBackground)
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
                  final primaryFontSize =
                      state.calendarType == CalendarType.combined
                      ? (compactCell ? 11.0 : 12.0)
                      : (compactCell ? 12.0 : 14.0);
                  final secondaryFontSize = compactCell ? 9.0 : 10.0;
                  final monthLabelFontSize = compactCell ? 7.0 : 8.0;
                  final hebrewIsPrimary =
                      state.calendarType != CalendarType.gregorian;
                  final showGregorian =
                      state.calendarType != CalendarType.hebrew;
                  final primaryStyle = TextStyle(
                    color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: primaryFontSize,
                  );

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
                        // התאריך העברי תמיד בימין התא והלועזי בשמאלו, בלי
                        // קשר לכיוון הטקסט; ההגדרה קובעת רק איזה מהם ראשי.
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showGregorian)
                                Text(
                                  '${gregorianDate.day}',
                                  style: hebrewIsPrimary
                                      ? TextStyle(
                                          color: isSelected
                                              ? cs.onPrimaryContainer
                                                    .withValues(alpha: 0.85)
                                              : cs.onSurfaceVariant,
                                          fontSize: secondaryFontSize,
                                        )
                                      : primaryStyle,
                                ),
                              const Spacer(),
                              if (hebrewIsPrimary)
                                ContentDirectionality(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        formatHebrewDay(
                                          jewishDate.getJewishDayOfMonth(),
                                        ),
                                        style: primaryStyle,
                                      ),
                                      if (jewishDate.isJewishLeapYear() &&
                                          (jewishDate.getJewishMonth() == 12 ||
                                              jewishDate.getJewishMonth() ==
                                                  13) &&
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
                                ),
                            ],
                          ),
                        ),
                        SizedBox(height: compactCell ? 2 : 6),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, extrasConstraints) => Align(
                              alignment: AlignmentDirectional.topStart,
                              child: DayExtras(
                                jewishCalendar: jewishCalendar,
                                date: gregorianDate,
                                maxVisibleItems: DayExtras.linesThatFit(
                                  context,
                                  extrasConstraints.maxHeight,
                                  compact: compactCell,
                                ),
                                compact: compactCell,
                                additionalInfoLines: additionalInfoLines,
                                isSelected: isSelected,
                              ),
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

  /// האם התא נבחר, ולכן התוכן משתמש ב-onPrimaryContainer.
  final bool isSelected;

  const DayExtras({
    super.key,
    required this.jewishCalendar,
    required this.date,
    this.maxVisibleItems = 2,
    this.compact = false,
    this.additionalInfoLines = const [],
    this.isSelected = false,
  });

  /// כמה שורות פריטים נכנסות בגובה [height], לפי הגופן והגדלת הטקסט בפועל.
  static int linesThatFit(
    BuildContext context,
    double height, {
    required bool compact,
  }) {
    if (!height.isFinite) return 2;
    final painter = TextPainter(
      text: const TextSpan(text: 'א'),
      strutStyle: _lineStrut(context, compact),
      textDirection: TextDirection.rtl,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final lineHeight = painter.height;
    painter.dispose();
    return (height / lineHeight).floor();
  }

  // גובה שורה קבוע בתא: גופני fallback (עברית לצד ספרות/לטינית) לא יגדילו
  // שורה מעבר למה ש-linesThatFit מדד.
  static StrutStyle _lineStrut(BuildContext context, bool compact) =>
      StrutStyle.fromTextStyle(
        DefaultTextStyle.of(context).style.merge(
          TextStyle(fontSize: compact ? 10 : 11, fontWeight: FontWeight.w500),
        ),
        forceStrutHeight: true,
      );

  @override
  Widget build(BuildContext context) {
    if (maxVisibleItems <= 0) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final events = context.read<CalendarCubit>().eventsForDate(date);
    final strut = _lineStrut(context, compact);
    final jewishEvents = _calcJewishEvents(jewishCalendar);

    // inDialog: שורה מלאה בחלונית "כל הפריטים", בלי קיצור ובלי צבעי בחירה.
    final items = <Widget Function(bool inDialog)>[
      for (final e in jewishEvents)
        (inDialog) => Text(
          e,
          maxLines: inDialog ? null : 1,
          overflow: inDialog ? null : TextOverflow.ellipsis,
          strutStyle: inDialog ? null : strut,
          style: TextStyle(
            fontSize: inDialog ? 14 : (compact ? 10 : 11),
            color: isSelected && !inDialog
                ? cs.onPrimaryContainer
                : cs.onSurface,
            fontWeight: FontWeight.w500,
          ),
        ),
      for (final e in events)
        (inDialog) => Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '• ',
                style: TextStyle(
                  color: isSelected && !inDialog
                      ? cs.onPrimaryContainer
                      : CalendarEventColors.colorForIndex(
                              e.displayColorIndex,
                              brightness,
                            ) ??
                            cs.onSurfaceVariant,
                ),
              ),
              TextSpan(text: e.title),
            ],
          ),
          maxLines: inDialog ? null : 1,
          overflow: inDialog ? null : TextOverflow.ellipsis,
          strutStyle: inDialog ? null : strut,
          style: TextStyle(
            fontSize: inDialog ? 14 : (compact ? 9 : 10),
            color: isSelected && !inDialog
                ? cs.onPrimaryContainer
                : cs.onSurfaceVariant,
          ),
        ),
      for (final info in additionalInfoLines)
        (inDialog) {
          final style = TextStyle(
            fontSize: inDialog ? 14 : (compact ? 9 : 10),
            color: isSelected && !inDialog ? cs.onPrimaryContainer : cs.primary,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          );
          final lastSpace = info.lastIndexOf(' ');
          if (inDialog || lastSpace == -1) {
            return Text(
              info,
              maxLines: inDialog ? null : 1,
              overflow: inDialog ? null : TextOverflow.ellipsis,
              strutStyle: inDialog ? null : strut,
              style: style,
            );
          }
          // "זריחה 06:08": השם בתחילת השורה והשעה בסופה, בספרות ברוחב קבוע
          // — כך השעות של כל השורות בתא עומדות זו מתחת לזו.
          // בתא צר מאוד (שעון 12 שעות, הגדלת טקסט) השעה נחתכת במקום לגלוש.
          return LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: Text(
                    info.substring(0, lastSpace),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    strutStyle: strut,
                    style: style,
                  ),
                ),
                const SizedBox(width: AppTokens.spaceXS),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: (constraints.maxWidth - AppTokens.spaceXS).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: Text(
                    info.substring(lastSpace + 1),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    strutStyle: strut,
                    style: style,
                  ),
                ),
              ],
            ),
          );
        },
    ];

    final showMore = items.length > maxVisibleItems;
    Widget buildLines(bool moreTakesRow) {
      final itemRows = maxVisibleItems - (moreTakesRow ? 1 : 0);
      // משאירים שורה לאירוע משתמש מתוך השורות הפנויות לפריטים.
      final shownJewish = (itemRows - (events.isEmpty ? 0 : 1)).clamp(
        0,
        jewishEvents.length,
      );
      final lines = [
        for (final item in items.take(shownJewish)) item(false),
        for (final item
            in items
                .skip(jewishEvents.length)
                .take(
                  itemRows - shownJewish,
                ))
          item(false),
      ];
      if (showMore) {
        final moreLabel = _MoreItemsLabel(
          hiddenCount: items.length - lines.length,
          compact: compact,
          isSelected: isSelected,
          strut: strut,
          onTap: () => _showAllItems(context, items),
        );
        if (moreTakesRow) {
          lines.add(
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: moreLabel,
            ),
          );
        } else {
          lines.last = Row(
            children: [
              Expanded(child: lines.last),
              moreLabel,
            ],
          );
        }
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: lines,
      );
    }

    if (!showMore) return buildLines(false);
    final minRowWidth = MediaQuery.textScalerOf(context).scale(44);
    return LayoutBuilder(
      builder: (context, constraints) =>
          buildLines(constraints.maxWidth < minRowWidth),
    );
  }

  void _showAllItems(
    BuildContext context,
    List<Widget Function(bool inDialog)> items,
  ) {
    showDialogUntilTornDown<void>(
      context: context,
      builder: (dialogContext) => AppDialogFrame(
        title: 'כל הפריטים ביום',
        subtitle: formatEventDate(date),
        icon: FluentIcons.calendar_24_regular,
        size: AppDialogSize.small,
        scrollable: true,
        actions: [
          ActionButton.recommended(
            text: 'סגור',
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: item(true),
              ),
          ],
        ),
      ),
    );
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
      final dayOfCholHamoed =
          jc.getJewishDayOfMonth() - (jc.inIsrael ? 15 : 16);
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

    if (yomTovIndex == JewishCalendar.HOSHANA_RABBA) {
      l.add("${jc.inIsrael ? 'ו' : 'ה'}' דחוה\"מ");
    }

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
  final _addButtonFocus = FocusNode();
  bool _isHovered = false;
  Widget? _addButton;
  ColorScheme? _addButtonScheme;

  @override
  void initState() {
    super.initState();
    _addButtonFocus.addListener(_handleAddButtonFocus);
  }

  void _handleAddButtonFocus() => setState(() {});

  @override
  void dispose() {
    _addButtonFocus.dispose();
    super.dispose();
  }

  // אותו מופע בין בנייה לבנייה: בבחירת יום ובריחוף כל התאים נבנים מחדש,
  // ועדכון 42 הכפתורים הנסתרים היה רוב הזמן.
  Widget _buildAddButton(ColorScheme cs) {
    if (_addButton != null && _addButtonScheme == cs) return _addButton!;
    _addButtonScheme = cs;
    return _addButton = TooltipTheme(
      data: TooltipTheme.of(context).copyWith(verticalOffset: -40.0),
      child: IconButton.filled(
        tooltip: 'צור אירוע',
        focusNode: _addButtonFocus,
        icon: const Icon(FluentIcons.add_24_regular, size: AppTokens.iconSM),
        onPressed: () => widget.onAdd(),
        style: IconButton.styleFrom(
          minimumSize: const Size(24, 24),
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: AppTokens.roundedShape,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showButton = _isHovered || _addButtonFocus.hasFocus;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Listener(
            onPointerDown: (_) => setState(() => _isHovered = true),
            child: widget.builder(_isHovered),
          ),
          AnimatedOpacity(
            opacity: showButton ? 1.0 : 0.0,
            duration: AppMotion.duration(context, AppTokens.animPanelOpacity),
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: IgnorePointer(
                ignoring: !showButton,
                child: _buildAddButton(cs),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// סימון "+N" לפריטים שלא נכנסו בתא; לחיצה פותחת את כל פריטי היום.
class _MoreItemsLabel extends StatelessWidget {
  final int hiddenCount;
  final bool compact;
  final bool isSelected;
  final StrutStyle strut;
  final VoidCallback onTap;

  const _MoreItemsLabel({
    required this.hiddenCount,
    required this.compact,
    required this.isSelected,
    required this.strut,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'עוד $hiddenCount — הצגת כל הפריטים',
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppTokens.borderRadiusAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.space2XS,
            ),
            child: Text(
              '+$hiddenCount',
              strutStyle: strut,
              style: TextStyle(
                fontSize: compact ? 9 : 10,
                fontWeight: FontWeight.w700,
                color: isSelected ? cs.onPrimaryContainer : cs.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
