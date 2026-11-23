import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/models/calendar_location.dart';
import 'package:otzaria/tools/calendar/models/zman_definition.dart';
import 'package:otzaria/tools/calendar/helpers/daf_yomi_navigation.dart';
import 'package:otzaria/tools/calendar/helpers/molad_helpers.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart'
    as zmanim_helpers;
import 'package:otzaria/tools/calendar/dialogs/calendar_zman_alert_dialog.dart';
import 'package:otzaria/tools/calendar/dialogs/zmanim_settings_dialog.dart';
import 'package:otzaria/widgets/feedback/edge_scrollbar_behavior.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:timezone/timezone.dart' as tz;

class CalendarTimeEntry {
  final String id;
  final String name;

  /// תת-כותרת (פירוט השיטה) — מוצגת בשורה שנייה קטנה בכרטיס בודד.
  final String subtitle;
  final String time;
  final bool isHolidaySpecial;
  final bool isComposite;
  final String? trailingLabel;
  final String? leadingLabel;
  final List<CalendarTimeAlertOption> alertOptions;

  /// האם ניתן להפעיל התראה לזמן זה. זמנים המוצגים כתאריך עברי (קידוש
  /// לבנה) אינם זמני שעון נקודתיים ולכן לא ניתנים לתזמון — עבורם כפתור
  /// ההתראה אינו מוצג כלל.
  final bool canAlert;

  /// כרטיס מאוחד: כל הזמנים עם אותה כותרת (למשל כל שיטות "עלות השחר")
  /// מוצגים בכרטיס אחד, וכל אחד מהם הוא חלק בו. ריק בכרטיס רגיל.
  final List<CalendarTimeEntry> members;

  const CalendarTimeEntry({
    required this.id,
    required this.name,
    required this.time,
    required this.isHolidaySpecial,
    this.subtitle = '',
    this.isComposite = false,
    this.trailingLabel,
    this.leadingLabel,
    this.alertOptions = const [],
    this.canAlert = true,
    this.members = const [],
  });
}

class CalendarTimeAlertOption {
  final String id;
  final String name;
  final String time;

  const CalendarTimeAlertOption({
    required this.id,
    required this.name,
    required this.time,
  });
}

/// בונה כרטיס בודד מתוך הגדרת זמן, על בסיס הזמן שחושב ל-dailyTimes.
/// מחזיר null אם הזמן אינו זמין.
CalendarTimeEntry? entryFromZmanDefinition(
  ZmanDefinition def,
  Map<String, String> dailyTimes,
) {
  final time = dailyTimes[def.id];
  if (time == null || time.isEmpty) return null;
  // זמני תאריך עברי (קידוש לבנה) אינם ניתנים לתזמון התראה.
  final canAlert = !def.showHebrewDate;
  return CalendarTimeEntry(
    id: def.id,
    name: def.title,
    subtitle: def.subtitle,
    time: time,
    isHolidaySpecial: def.isHolidaySpecial,
    canAlert: canAlert,
    alertOptions: canAlert
        ? [CalendarTimeAlertOption(id: def.id, name: def.fullName, time: time)]
        : const [],
  );
}

/// בונה כרטיס composite מזיווג שתי הגדרות — תצוגת הלוח הראשי בלבד.
/// בטבלת "זמנים נוספים" כל הגדרה מופיעה בנפרד.
CalendarTimeEntry? _pairedEntry(
  ZmanDefinition a,
  ZmanDefinition b,
  Map<String, String> dailyTimes,
) {
  final rawA = dailyTimes[a.id];
  final rawB = dailyTimes[b.id];
  final ta = (rawA != null && rawA.isNotEmpty) ? rawA : null;
  final tb = (rawB != null && rawB.isNotEmpty) ? rawB : null;
  if (ta == null && tb == null) return null;

  final String sortTime;
  if (ta != null && tb != null) {
    sortTime = ta.compareTo(tb) < 0 ? ta : tb;
  } else {
    sortTime = ta ?? tb ?? '';
  }

  return CalendarTimeEntry(
    id: a.pairId ?? a.id,
    name: a.title,
    time: sortTime,
    isHolidaySpecial: a.isHolidaySpecial,
    isComposite: true,
    trailingLabel: ta != null ? '${a.pairLabel} $ta' : null,
    leadingLabel: tb != null ? '${b.pairLabel} $tb' : null,
    alertOptions: [
      if (ta != null)
        CalendarTimeAlertOption(id: a.id, name: a.fullName, time: ta),
      if (tb != null)
        CalendarTimeAlertOption(id: b.id, name: b.fullName, time: tb),
    ],
  );
}

/// פאנל זמני היום.
class CalendarTimesPanel extends StatefulWidget {
  final CalendarState state;
  final Future<void> Function(BuildContext context)
  onOpenCalendarCalculationPage;

  const CalendarTimesPanel({
    super.key,
    required this.state,
    required this.onOpenCalendarCalculationPage,
  });

  @override
  State<CalendarTimesPanel> createState() => _CalendarTimesPanelState();
}

class _CalendarTimesPanelState extends State<CalendarTimesPanel> {
  late final List<String> _cityNames;
  static const double _infoButtonWidth = 40;

  /// בונה את רשימת כרטיסי הזמנים להצגה — לפי רישום הזמנים המרכזי,
  /// מסונן לזמנים שהמשתמש הפעיל ושרלוונטיים ליום הנבחר.
  List<CalendarTimeEntry> _buildCalendarTimeEntries(CalendarState state) {
    final dailyTimes = state.dailyTimes;
    final jewishCalendar = JewishCalendar.fromDateTime(
      state.selectedGregorianDate,
    );
    jewishCalendar.inIsrael = state.inIsrael;

    // אוספים את ההגדרות המופעלות והרלוונטיות, בסדר הרישום.
    final visible = <ZmanDefinition>[];
    for (final def in zmanim_helpers.kZmanimRegistry) {
      if (!state.enabledZmanim.contains(def.id)) continue;
      if (def.isRelevant != null && !def.isRelevant!(jewishCalendar)) continue;
      visible.add(def);
    }

    // מזווגים בלוח שתי הגדרות מופעלות עם אותו pairId לכרטיס composite אחד.
    final entries = <CalendarTimeEntry>[];
    final consumed = <int>{};
    for (var i = 0; i < visible.length; i++) {
      if (consumed.contains(i)) continue;
      final def = visible[i];
      if (def.pairId != null) {
        final j = visible.indexWhere((d) => d.pairId == def.pairId, i + 1);
        if (j != -1) {
          consumed.add(j);
          final paired = _pairedEntry(def, visible[j], dailyTimes);
          if (paired != null) entries.add(paired);
          continue;
        }
      }
      final entry = entryFromZmanDefinition(def, dailyTimes);
      if (entry != null) entries.add(entry);
    }

    // סדר ההופעה הנוכחי (סדר הרישום) — שובר-שוויון יציב לזמנים שאינם
    // שעת-שעון (קידוש לבנה), שמחרוזת התצוגה שלהם אינה ברת-מיון כרונולוגי.
    final order = {for (final (i, e) in entries.indexed) e.id: i};
    entries.sort((a, b) {
      // חצות לילה תמיד בסוף
      if (a.id == 'chatzosLayla') return 1;
      if (b.id == 'chatzosLayla') return -1;
      final aClock = zmanim_helpers.isClockTime(a.time);
      final bClock = zmanim_helpers.isClockTime(b.time);
      if (aClock && bClock) return a.time.compareTo(b.time);
      // שעות-שעון ממוינות כרונולוגית ומופיעות לפני זמני תאריך עברי.
      if (aClock != bClock) return aClock ? -1 : 1;
      return (order[a.id] ?? 0).compareTo(order[b.id] ?? 0);
    });
    return _groupByName(entries);
  }

  /// מאחד כרטיסים עם אותה כותרת (למשל כל שיטות "עלות השחר") לכרטיס אחד,
  /// גם כשאינם זוג מוגדר ברישום. הכרטיס עומד במקום של הזמן המוקדם בקבוצה,
  /// כך שהסדר הכרונולוגי בין הכרטיסים נשמר.
  static List<CalendarTimeEntry> _groupByName(
    List<CalendarTimeEntry> entries,
  ) {
    final groups = <String, List<CalendarTimeEntry>>{};
    for (final entry in entries) {
      (groups[entry.name] ??= []).add(entry);
    }
    return [
      for (final group in groups.values)
        if (group.length == 1) group.single else _mergedEntry(group),
    ];
  }

  /// כרטיס אחד לכל הזמנים בקבוצה: הכותרת פעם אחת, וכל זמן הוא חלק בכרטיס.
  /// הכפולים (זוגות מהרישום) קודמים, כמו קודם, ואחריהם הבודדים לפי הזמן.
  static CalendarTimeEntry _mergedEntry(List<CalendarTimeEntry> group) {
    final members = [
      ...group.where((e) => e.isComposite),
      ...group.where((e) => !e.isComposite),
    ];
    return CalendarTimeEntry(
      id: 'group:${group.first.id}',
      name: group.first.name,
      time: group.first.time,
      isHolidaySpecial: group.any((e) => e.isHolidaySpecial),
      isComposite: true,
      alertOptions: [for (final e in members) ...e.alertOptions],
      canAlert: group.any((e) => e.canAlert),
      members: members,
    );
  }

  String? _buildOmerInfo(DateTime date) {
    final jewishCalendar = JewishCalendar.fromDateTime(date);
    final omerDay = jewishCalendar.getDayOfOmer();
    if (omerDay == -1) {
      return null;
    }
    return _buildOmerCountingText(omerDay);
  }

  String _resolveOmerAlertTimeLabel() {
    final selectedDate = widget.state.selectedGregorianDate;
    final todayDate = widget.state.todayGregorianDate;
    final cityData = getCityData(widget.state.selectedCity);
    if (cityData == null ||
        selectedDate.year != todayDate.year ||
        selectedDate.month != todayDate.month ||
        selectedDate.day != todayDate.day) {
      return widget.state.dailyTimes['omerCounting'] ?? '--:--';
    }

    final timeZoneId = cityData['timezone'] as String? ?? 'Asia/Jerusalem';
    final tzLocation = tz.getLocation(timeZoneId);
    final nowInCity = tz.TZDateTime.now(tzLocation);
    final currentCivilDate = DateTime(
      nowInCity.year,
      nowInCity.month,
      nowInCity.day,
    );
    final tonightTimes = zmanim_helpers.calculateDailyTimes(
      currentCivilDate,
      widget.state.selectedCity,
    );
    return tonightTimes['omerCounting'] ??
        widget.state.dailyTimes['omerCounting'] ??
        '--:--';
  }

  List<CalendarTimeEntry> _arrangeEntriesForGrid(
    List<CalendarTimeEntry> entries,
    int columnCount,
  ) {
    if (columnCount != 2) {
      return entries;
    }

    final arranged = <CalendarTimeEntry>[];
    final remaining = List<CalendarTimeEntry>.from(entries);
    int occupiedSlotsInRow = 0;

    while (remaining.isNotEmpty) {
      final current = remaining.removeAt(0);
      final currentWidth = current.isComposite ? 2 : 1;

      if (occupiedSlotsInRow == 1 && currentWidth == 2) {
        final replacementIndex = remaining.indexWhere(
          (entry) => entry.isComposite == false,
        );
        if (replacementIndex != -1) {
          final replacement = remaining.removeAt(replacementIndex);
          arranged.add(replacement);
          occupiedSlotsInRow = 0;
          remaining.insert(0, current);
          continue;
        }
      }

      arranged.add(current);
      occupiedSlotsInRow += currentWidth;
      if (occupiedSlotsInRow >= columnCount) {
        occupiedSlotsInRow = 0;
      }
    }

    return arranged;
  }

  String _buildOmerCountingText(int day) {
    final totalDaysText = _buildOmerDayCountText(day);
    final weeks = day ~/ 7;
    final extraDays = day % 7;

    if (weeks == 0) {
      return 'היום $totalDaysText בעומר';
    }

    final weeksText = _buildOmerWeekCountText(weeks);
    if (extraDays == 0) {
      return 'היום $totalDaysText שהם $weeksText בעומר';
    }

    final extraDaysText = _buildOmerDayCountText(extraDays);
    return 'היום $totalDaysText שהם $weeksText ו$extraDaysText בעומר';
  }

  String _buildOmerDayCountText(int day) {
    const ones = [
      '',
      'יום אחד',
      'שני ימים',
      'שלשה ימים',
      'ארבעה ימים',
      'חמשה ימים',
      'ששה ימים',
      'שבעה ימים',
      'שמונה ימים',
      'תשעה ימים',
      'עשרה ימים',
      'אחד עשר יום',
      'שנים עשר יום',
      'שלשה עשר יום',
      'ארבעה עשר יום',
      'חמשה עשר יום',
      'ששה עשר יום',
      'שבעה עשר יום',
      'שמונה עשר יום',
      'תשעה עשר יום',
    ];
    const tens = ['', '', 'עשרים', 'שלשים', 'ארבעים'];
    const onesSimple = [
      '',
      'אחד',
      'שנים',
      'שלשה',
      'ארבעה',
      'חמשה',
      'ששה',
      'שבעה',
      'שמונה',
      'תשעה',
    ];

    if (day <= 0 || day > 49) {
      return 'יום $day';
    }

    if (day < 20) {
      return ones[day];
    }

    final tensText = tens[day ~/ 10];
    final onesValue = day % 10;
    if (onesValue == 0) {
      return '$tensText יום';
    }

    return '${onesSimple[onesValue]} ו$tensText יום';
  }

  String _buildOmerWeekCountText(int weeks) {
    const oneToNine = [
      '',
      'אחד',
      'שני',
      'שלשה',
      'ארבעה',
      'חמשה',
      'ששה',
      'שבעה',
      'שמונה',
      'תשעה',
    ];

    if (weeks <= 0) {
      return '';
    }
    if (weeks == 1) {
      return 'שבוע אחד';
    }
    if (weeks == 2) {
      return 'שני שבועות';
    }

    return '${oneToNine[weeks]} שבועות';
  }

  @override
  void initState() {
    super.initState();
    _cityNames = getCalendarCityNames();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final omerInfo = _buildOmerInfo(widget.state.selectedGregorianDate);
    // פס הגלילה בימין, כמו בשאר האפליקציה — גם כשהחלונית משמאל לתוכן.
    // החלונית הרחבה מרופדת 16px, ולכן הפס לא נופל על ידית הגרירה.
    return ScrollConfiguration(
      behavior: const EdgeScrollbarBehavior.right(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              // בחירת העיר נמתחת לכל רוחב השורה, עד מקש הזמנים הנוספים
              child: Row(
                children: [
                  BarButton.icon(
                    tooltip: 'זמנים נוספים',
                    icon: OtzariaIcons.clock_add_24_regular,
                    // 24 ולא 20 כשאר הסרגל: השעון ב-clock_add אינו ממלא את
                    // הקנבס — הפלוס תופס את הפינה — ולכן הוא נקרא קטן
                    // משמעותית מאייקון פלואנט באותו גודל נומינלי.
                    iconSize: AppTokens.iconLG,
                    compact: true,
                    onPressed: () => showZmanimSettingsDialog(context),
                  ),
                  const SizedBox(width: AppTokens.spaceSM),
                  Expanded(
                    child: _CityDropdown(
                      cityName: widget.state.selectedCity,
                      cityNames: _cityNames,
                    ),
                  ),
                ],
              ),
            ),
            if (omerInfo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: _buildOmerButton(context, omerInfo),
                ),
              ),
            Builder(
              builder: (context) {
                final moladInfo = calculateMoladForDate(
                  widget.state.selectedGregorianDate,
                  widget.state.selectedCity,
                );
                if (moladInfo == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _MoladCard(info: moladInfo),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: _infoButtonWidth),
                      Expanded(
                        child: Center(
                          child: Text(
                            'אין לסמוך על הזמנים כלל!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: _infoButtonWidth,
                        child: Center(
                          child: IconButton(
                            tooltip: 'מידע על חישוב הזמנים',
                            onPressed: () =>
                                widget.onOpenCalendarCalculationPage(context),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: _infoButtonWidth,
                              height: _infoButtonWidth,
                            ),
                            icon: Icon(
                              FluentIcons.info_24_regular,
                              size: AppTokens.iconSM,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _buildTimesGrid(context),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _buildDafYomiButtons(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimesGrid(BuildContext context) {
    final filteredTimesList = _buildCalendarTimeEntries(widget.state);
    return LayoutBuilder(
      builder: (context, constraints) {
        const singleColumnBelow = 290.0;
        final isSingleColumn = constraints.maxWidth < singleColumnBelow;
        final columnCount = isSingleColumn ? 1 : 2;
        const spacing = AppTokens.spaceSM;
        final arrangedTimesList = _arrangeEntriesForGrid(
          filteredTimesList,
          columnCount,
        );
        // שורות במקום Wrap: שני כרטיסים באותה שורה מקבלים את אותו מבנה
        // (שורת פירוט / שורת התראה שמורה גם אם רק לאחד מהם יש), וכך הם
        // באותו גובה בלי מדידה מוקדמת (IntrinsicHeight).
        final rows = <List<CalendarTimeEntry>>[];
        for (final entry in arrangedTimesList) {
          final last = rows.isEmpty ? null : rows.last;
          final canJoin =
              columnCount == 2 &&
              !entry.isComposite &&
              last != null &&
              last.length == 1 &&
              !last.single.isComposite;
          if (canJoin) {
            last.add(entry);
          } else {
            rows.add([entry]);
          }
        }

        Widget card(CalendarTimeEntry entry, _ZmanRowLayout layout) =>
            _ZmanCard(
              timeData: entry,
              zmanAlerts: widget.state.zmanAlerts,
              twelveHourClock: widget.state.twelveHourClock,
              layout: layout,
            );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: spacing),
              Builder(
                builder: (context) {
                  final row = rows[i];
                  final layout = _ZmanRowLayout.of(
                    row,
                    widget.state.zmanAlerts,
                  );
                  if (row.length == 1 &&
                      (row.single.isComposite || columnCount == 1)) {
                    return card(row.single, layout);
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: card(row.first, layout)),
                      const SizedBox(width: spacing),
                      Expanded(
                        child: row.length == 2
                            ? card(row.last, layout)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }

  String _buildDafYomiButtonText(String tractate, String dafLabel) {
    final cleanLabel = dafLabel.trim().replaceAll('.', '');
    if (tractate == 'לא זמין' || cleanLabel.isEmpty) {
      return 'דף היומי בבלי';
    }
    return 'דף היומי: $tractate $cleanLabel';
  }

  String _buildDafNavigationTarget(String dafLabel) {
    final cleanLabel = dafLabel.trim().replaceAll('.', '');
    if (cleanLabel.isEmpty) {
      return '';
    }
    return ' $cleanLabel.';
  }

  Widget _buildDafYomiButtons(BuildContext context) {
    final jewishCalendar = JewishCalendar.fromDateTime(
      widget.state.selectedGregorianDate,
    );
    String bavliTractate;
    int bavliDaf;
    try {
      final daf = YomiCalculator.getDafYomiBavli(jewishCalendar);
      bavliTractate = daf.getMasechta();
      bavliDaf = daf.getDaf();
    } catch (_) {
      bavliTractate = 'לא זמין';
      bavliDaf = 0;
    }
    final dafLabel = bavliDaf > 0
        ? HebrewDateFormatter()
              .formatHebrewNumber(bavliDaf)
              .replaceAll('״', '')
              .replaceAll('׳', '')
        : '';

    return ActionButton.recommended(
      text: _buildDafYomiButtonText(bavliTractate, dafLabel),
      icon: OtzariaIcons.book_24_regular,
      onPressed: bavliTractate == 'לא זמין'
          ? () => UiSnack.showError(ToolsMessages.dafYomiUnavailableForDate)
          : () => openDafYomiBook(
              context,
              bavliTractate,
              _buildDafNavigationTarget(dafLabel),
            ),
    );
  }

  Widget _buildOmerButton(BuildContext context, String text) {
    final existingAlert = widget.state.zmanAlerts['omerCounting'];
    final cubit = context.read<CalendarCubit>();
    final cs = Theme.of(context).colorScheme;

    final iconWidget = existingAlert != null
        ? Icon(FluentIcons.alert_24_filled)
        : Icon(
            OtzariaIcons.mount_sinai_24_regular,
            size: AppTokens.iconMD,
            color: cs.onPrimary,
          );

    return ActionButton.recommended(
      text: text,
      iconWidget: iconWidget,
      textAlign: TextAlign.center,
      onPressed: () async {
        final timeLabel = _resolveOmerAlertTimeLabel();
        if (timeLabel == '--:--') {
          UiSnack.showError(ToolsMessages.omerAlertUnavailableToday);
          return;
        }
        final result = await showZmanAlertDialog(
          context,
          zmanName: 'ספירת העומר',
          timeLabel: zmanim_helpers.zmanTimeForDisplay(
            timeLabel,
            twelveHourClock: widget.state.twelveHourClock,
          ),
          initialMinutesBefore: existingAlert?.minutesBefore ?? 60,
          isEnabled: existingAlert != null,
        );
        if (result == null) return;
        if (result.cancelAlert) {
          _runZmanAlertOp(
            cubit.cancelZmanAlertPreference(timeId: 'omerCounting'),
          );
          return;
        }
        _runZmanAlertOp(
          cubit.setZmanAlertPreference(
            timeId: 'omerCounting',
            displayName: 'ספירת העומר',
            minutesBefore: result.minutesBefore,
          ),
        );
      },
    );
  }
}

class _CityDropdown extends StatelessWidget {
  final String cityName;
  final List<String> cityNames;

  const _CityDropdown({
    required this.cityName,
    required this.cityNames,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AppDropdownField<String>(
        value: cityName,
        enableSearch: true,
        semanticLabel: 'עיר',
        entries: cityNames
            .map((city) => AppMenuEntry<String>(value: city, label: city))
            .toList(),
        onSelected: (value) {
          if (value == null || value == cityName) return;
          context.read<CalendarCubit>().changeCity(value);
        },
      ),
    );
  }
}

/// מפעיל פעולת cubit ברקע (fire-and-forget) ומציג שגיאות דרך UiSnack
/// במקום לבלוע אותן בשקט. נדרש כי await ישיר גורם לקפיאת UI בזמן
/// שכלול ההתראות (חישוב זמנים יומי + תזמון notifications מערכת).
void _runZmanAlertOp(Future<void> future) {
  unawaited(
    future.catchError((Object error, StackTrace stackTrace) {
      debugPrint('ZmanAlert op failed: $error\n$stackTrace');
      UiSnack.showError(ToolsMessages.zmanAlertUpdateError);
    }),
  );
}

String _formatAlertMinutes(int minutes) {
  if (minutes < 60) return "$minutes דק'";
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (mins == 0) return hours == 1 ? 'שעה' : '$hours שעות';
  return hours == 1 ? "שעה ו$mins דק'" : "$hours שעות ו$mins דק'";
}

/// מה ששני כרטיסים באותה שורה בגריד חולקים, כדי שיהיו באותו גובה: אם
/// לאחד מהם יש התראה פעילה, שורת ההתראה נשמרת (שקופה) גם בשני.
class _ZmanRowLayout {
  final bool reserveAlertLine;

  /// האם לכרטיס כלשהו בשורה יש כותרת משנית. אם לא, כרטיס בלי כותרת משנית
  /// מוותר על השורה שלה כליל, והפעמון עובר לשורת השעה.
  final bool reserveLabelRow;

  const _ZmanRowLayout({
    required this.reserveAlertLine,
    required this.reserveLabelRow,
  });

  factory _ZmanRowLayout.of(
    List<CalendarTimeEntry> row,
    Map<String, ZmanAlertPreference?> alerts,
  ) {
    bool hasAlert(CalendarTimeEntry e) =>
        alerts[e.id] != null ||
        e.alertOptions.any((option) => alerts[option.id] != null);
    return _ZmanRowLayout(
      reserveAlertLine: row.any(hasAlert),
      reserveLabelRow: row.any(
        (e) => _ZmanCard._segmentsOf(e).any((s) => s.label.isNotEmpty),
      ),
    );
  }
}

/// חצי אחד בכרטיס כפול (למשל מג"א / גר"א): כותרת, שעה והתראה משלו.
class _ZmanSegment {
  final String label;
  final String time;
  final CalendarTimeAlertOption? alertOption;

  const _ZmanSegment({
    required this.label,
    required this.time,
    required this.alertOption,
  });

  /// התווית נבנית כ-"<כותרת> <שעה>" (`_pairedEntry`); מפרקים ברווח האחרון.
  factory _ZmanSegment.parse(String text, CalendarTimeAlertOption? option) {
    final lastSpace = text.lastIndexOf(' ');
    return _ZmanSegment(
      label: lastSpace == -1 ? '' : text.substring(0, lastSpace),
      time: lastSpace == -1 ? text : text.substring(lastSpace + 1),
      alertOption: option,
    );
  }
}

class _ZmanCardColors {
  final Color background;
  final Color primary;
  final Color secondary;
  final Color accent;

  const _ZmanCardColors({
    required this.background,
    required this.primary,
    required this.secondary,
    required this.accent,
  });
}

/// כרטיס של זמן אחד בחלונית הזמנים.
///
/// מבנה: שם הזמן (ופירוט השיטה) בראש, מקש ההתראה בפינה, והשעה עצמה
/// ממורכזת ובולטת מתחת. התראה פעילה: הפעמון מלא בצבע הראשי, ושורה קטנה
/// מתחת לשעה אומרת כמה זמן לפני. בכרטיס כפול שני חצאים, לכל אחד שעה
/// ופעמון משלו, וביניהם קו דק.
class _ZmanCard extends StatelessWidget {
  final CalendarTimeEntry timeData;
  final Map<String, ZmanAlertPreference?> zmanAlerts;
  final bool twelveHourClock;
  final _ZmanRowLayout layout;

  const _ZmanCard({
    required this.timeData,
    required this.zmanAlerts,
    required this.twelveHourClock,
    required this.layout,
  });

  /// גודל מקש הפעמון (AppIconButtonSize.small), לשמירת גובה גם בלעדיו.
  static const double _bellExtent = 32;

  /// גובה שורת הכותרת המשנית — נמוך מהפעמון, כדי שהכותרת תהיה צמודה לשעה.
  static const double _labelRowHeight = 20;

  /// גובה שורת השעה (titleMedium: 16 × גובה שורה 1.5).
  static const double _timeLineHeight = 24;

  /// רוחב מינימלי לחלק בכרטיס מאוחד: כותרת קצרה, פעמון ושעה בלי דחיסה.
  static const double _segmentMinWidth = 120;

  String _display(String text) => zmanim_helpers.zmanTimeForDisplay(
    text,
    twelveHourClock: twelveHourClock,
  );

  /// החצאים של כרטיס כפול. כשרק אחד מבני-הזוג קיים היום, alertOptions
  /// מכיל אפשרות אחת — והיא שייכת לחצי הקיים.
  List<_ZmanSegment> _segments() => _segmentsOf(timeData);

  static List<_ZmanSegment> _segmentsOf(CalendarTimeEntry timeData) {
    if (timeData.members.isNotEmpty) {
      return [for (final member in timeData.members) ..._segmentsOf(member)];
    }
    if (!timeData.isComposite) {
      return [
        _ZmanSegment(
          label: timeData.subtitle,
          time: timeData.time,
          alertOption: timeData.canAlert && timeData.alertOptions.length == 1
              ? timeData.alertOptions.single
              : null,
        ),
      ];
    }
    final labels = <String>[
      if (timeData.trailingLabel != null) timeData.trailingLabel!,
      if (timeData.leadingLabel != null) timeData.leadingLabel!,
    ];
    final options = timeData.canAlert
        ? timeData.alertOptions
        : const <CalendarTimeAlertOption>[];
    // `_pairedEntry` בונה את alertOptions באותו סדר ובאותה נוכחות כמו
    // התוויות, ולכן אפשרות i שייכת לחצי i — גם כשמוצג רק חצי אחד, והפעמון
    // שלו יושב תמיד בשורת הכותרת המשנית ולא ליד שם הזמן.
    return [
      for (var i = 0; i < labels.length; i++)
        _ZmanSegment.parse(
          labels[i],
          i < options.length ? options[i] : null,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final special = timeData.isHolidaySpecial;
    final colors = _ZmanCardColors(
      background: special
          ? AppSurfaces.calendarSpecialDayCard(scheme)
          : AppSurfaces.card(context),
      primary: special
          ? AppSurfaces.onCalendarSpecialDayCard(scheme)
          : scheme.onSurface,
      secondary: special
          ? AppSurfaces.onCalendarSpecialDayCardVariant(scheme)
          : scheme.onSurfaceVariant,
      accent: special
          ? AppSurfaces.onCalendarSpecialDayCard(scheme)
          : scheme.primary,
    );

    final Widget body;
    if (timeData.isComposite) {
      final segments = _segments();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // בכרטיס כפול הפעמונים תמיד בחצאים, לא ליד שם הזמן
          _header(context, colors),
          const SizedBox(height: AppTokens.spaceXS),
          // מספר החלקים בשורה לפי רוחב הכרטיס (1–3), כדי שחלק לא יימרח:
          // כל חלק לפחות _segmentMinWidth. מקום שנשאר ריק בשורה האחרונה
          // נשמר, כדי שהעמודות יישארו מיושרות — גם בין כרטיסים.
          LayoutBuilder(
            builder: (context, constraints) {
              const dividerSlot = AppTokens.spaceSM * 2 + AppTokens.borderThin;
              final columns =
                  ((constraints.maxWidth + dividerSlot) /
                          (_segmentMinWidth + dividerSlot))
                      .floor()
                      .clamp(1, 3);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var r = 0; r < segments.length; r += columns) ...[
                    // מרווח ברור בין שורות, כדי שהשעה לא תיצמד לכותרת שמתחתיה
                    if (r > 0) const SizedBox(height: AppTokens.spaceMD),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var c = 0; c < columns; c++) ...[
                          if (c > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTokens.spaceSM,
                              ),
                              child: SizedBox(
                                width: AppTokens.borderThin,
                                height: _bellExtent + AppTokens.spaceLG,
                                child: r + c < segments.length
                                    ? ColoredBox(
                                        color: AppSurfaces.subtleDivider(
                                          scheme,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          Expanded(
                            child: r + c < segments.length
                                ? _segment(context, segments[r + c], colors)
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      );
    } else {
      final option = timeData.canAlert && timeData.alertOptions.length == 1
          ? timeData.alertOptions.single
          : null;
      // כרטיס בודד בנוי כמו חצי של כרטיס כפול: שם הזמן למעלה, ומתחתיו
      // שורת הפירוט עם הפעמון, ואז השעה — כך הפעמון באותו מקום בשניהם.
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, colors),
          const SizedBox(height: AppTokens.spaceXS),
          _segment(
            context,
            _ZmanSegment(
              label: timeData.subtitle,
              time: timeData.time,
              alertOption: option,
            ),
            colors,
          ),
        ],
      );
    }

    return Material(
      color: colors.background,
      surfaceTintColor: Colors.transparent,
      shape: AppCard.shape(scheme),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: AppTokens.cardPadding, child: body),
    );
  }

  /// שם הזמן בראש הכרטיס. הפעמונים תמיד בשורת הפירוט שמתחתיו.
  ///
  /// תמיד בשורה אחת: שם ארוך מתכווץ במקום להישבר לשתי שורות, כדי שכל
  /// הכרטיסים יהיו באותו גובה ובאותו מבנה (אחרת הכרטיס השכן נשאר עם
  /// רווח ריק בתחתית).
  Widget _header(BuildContext context, _ZmanCardColors colors) {
    // כרטיס עם זמן אחד בלבד — כותרת קטנה יותר; כרטיס עם כמה זמנים — גדולה
    final textTheme = Theme.of(context).textTheme;
    final multiple = timeData.isComposite && _segments().length > 1;
    final style = (multiple ? textTheme.titleMedium : textTheme.bodyMedium)
        ?.copyWith(
          fontWeight: FontWeight.w600,
          color: colors.primary,
        );
    return Align(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(timeData.name, maxLines: 1, style: style),
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    _ZmanSegment segment,
    _ZmanCardColors colors,
  ) {
    final option = segment.alertOption;
    if (segment.label.isEmpty) {
      // בלי כותרת משנית: הפעמון עובר לשורת השעה, ולא נשארת שורה ריקה
      // שכל תוכנה הוא פעמון. השעה נשארת ממורכזת — מקום הפעמון שמור משני הצדדים.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // שומר גובה מול כרטיס שכן בשורה שיש לו כותרת משנית
          if (layout.reserveLabelRow)
            SizedBox(height: _reservedLabelHeight(context)),
          SizedBox(
            height: _bellExtent,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _bellExtent),
                  child: _timeText(context, segment.time, colors),
                ),
                if (option != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    // במרכוז מתמטי העינבל של הפעמון מגיע רק לאמצע הספרות
                    // (נבדק בעין במסך); מורידים כדי שתחתיתו תהיה בקו הספרות.
                    child: Transform.translate(
                      offset: const Offset(0, AppTokens.space2XS),
                      child: _bell(context, option, colors),
                    ),
                  ),
              ],
            ),
          ),
          if (layout.reserveAlertLine)
            _alertLine(
              context,
              option == null ? null : zmanAlerts[option.id],
              colors,
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // הכותרת המשנית ממורכזת לרוחב החלק, והפעמון בצד — עם מקום שמור
        // לפעמון משני הצדדים, כדי שהוא לא יזיז את הכותרת מהאמצע. השורה
        // נמוכה מהפעמון (_labelRowHeight), כדי שהכותרת תהיה קרובה לשעה;
        // הפעמון שומר על גודלו ובולט מעט מעל השורה ומתחתיה.
        SizedBox(
          height: _labelRowHeight,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _bellExtent),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    segment.label,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.secondary,
                    ),
                  ),
                ),
              ),
              if (option != null)
                // הפעמון בתחילת השורה — בצד ימין בעברית
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  // OverflowBox ממלא את כל הרוחב וממרכז כברירת מחדל — לכן
                  // היישור שלו חייב להיות לתחילת השורה, אחרת הפעמון על הכותרת
                  child: OverflowBox(
                    alignment: AlignmentDirectional.centerStart,
                    maxHeight: _bellExtent,
                    // במרכוז מתמטי הפעמון נראה גבוה מהכותרת המשנית (נבדק
                    // בעין במסך). מורידים אותו מעט כדי שייראה באותו קו.
                    child: Transform.translate(
                      offset: const Offset(0, AppTokens.space2XS),
                      child: _bell(context, option, colors),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _timeText(context, segment.time, colors),
        if (layout.reserveAlertLine)
          _alertLine(
            context,
            option == null ? null : zmanAlerts[option.id],
            colors,
          ),
      ],
    );
  }

  double _reservedLabelHeight(BuildContext context) {
    final fontSize = MediaQuery.textScalerOf(context).scale(AppTokens.fontLG);
    final timeLineHeight = (_timeLineHeight * fontSize / AppTokens.fontLG)
        .roundToDouble();
    return (_labelRowHeight + timeLineHeight - _bellExtent).clamp(
      0.0,
      double.infinity,
    );
  }

  Widget _timeText(BuildContext context, String time, _ZmanCardColors colors) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        _display(time),
        maxLines: 1,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: colors.primary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  /// "התראה 5 דק' לפני" — שקופה כשאין התראה, כדי לשמור גובה מול השכן.
  Widget _alertLine(
    BuildContext context,
    ZmanAlertPreference? alert,
    _ZmanCardColors colors,
  ) {
    return Opacity(
      opacity: alert == null ? 0 : 1,
      child: Text(
        alert == null
            ? ' '
            : 'התראה ${_formatAlertMinutes(alert.minutesBefore)} לפני',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colors.accent,
        ),
      ),
    );
  }

  Widget _bell(
    BuildContext context,
    CalendarTimeAlertOption option,
    _ZmanCardColors colors,
  ) {
    final alert = zmanAlerts[option.id];
    return AppIconButton(
      size: AppIconButtonSize.small,
      isSelected: alert != null,
      tooltip: alert != null
          ? 'התראה פעילה ל${_formatAlertMinutes(alert.minutesBefore)} לפני הזמן'
          : 'הפעל התראה לזמן זה',
      icon: Icon(
        alert != null
            ? FluentIcons.alert_24_filled
            : FluentIcons.alert_24_regular,
        color: alert != null ? colors.accent : colors.secondary,
      ),
      onPressed: () => _openAlertDialogForOption(context, option),
    );
  }

  Future<void> _openAlertDialogForOption(
    BuildContext context,
    CalendarTimeAlertOption option,
  ) async {
    if (option.time == '--:--') {
      UiSnack.showError(ToolsMessages.zmanAlertUnavailableTime);
      return;
    }
    final cubit = context.read<CalendarCubit>();
    final existingAlert = cubit.state.zmanAlerts[option.id];
    final result = await showZmanAlertDialog(
      context,
      zmanName: option.name,
      timeLabel: _display(option.time),
      initialMinutesBefore: existingAlert?.minutesBefore ?? 5,
      isEnabled: existingAlert != null,
    );
    if (result == null) return;
    if (result.cancelAlert) {
      _runZmanAlertOp(cubit.cancelZmanAlertPreference(timeId: option.id));
      return;
    }
    _runZmanAlertOp(
      cubit.setZmanAlertPreference(
        timeId: option.id,
        displayName: option.name,
        minutesBefore: result.minutesBefore,
      ),
    );
  }
}

String _moladReasonLabel(MoladDisplayReason reason) {
  switch (reason) {
    case MoladDisplayReason.shabbosMevorchim:
      return 'שבת מברכים';
    case MoladDisplayReason.roshChodesh:
      return 'ראש חודש';
    case MoladDisplayReason.moladDay:
      return 'יום המולד';
  }
}

class _MoladCard extends StatelessWidget {
  final MoladInfo info;
  const _MoladCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // כותרת ממורכזת כמו ב-_ZmanCard
          SizedBox(
            width: double.infinity,
            child: Text(
              'מולד ${info.monthName} — ${_moladReasonLabel(info.reason)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // קטע 1: המולד הממוצע (הנוסח שמכריזים).
          Text(
            'מולד כפי שנהוג להכריז',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            info.announcementText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          // קטע 2: המולד הנראה (אסטרונומי, זמן מקומי בעיר).
          Text(
            'מולד הנראה — ${info.cityName}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${info.visibleDayName} ${info.visibleHebrewDate} '
            'בשעה ${info.visibleTimeFormatted}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
