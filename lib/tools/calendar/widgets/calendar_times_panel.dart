import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart'
    hide cityCoordinates;
import 'package:otzaria/tools/calendar/models/calendar_location.dart';
import 'package:otzaria/tools/calendar/models/zman_definition.dart';
import 'package:otzaria/tools/calendar/helpers/daf_yomi_navigation.dart';
import 'package:otzaria/tools/calendar/helpers/molad_helpers.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart'
    as zmanim_helpers;
import 'package:otzaria/tools/calendar/dialogs/calendar_zman_alert_dialog.dart';
import 'package:otzaria/tools/calendar/dialogs/zmanim_settings_dialog.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
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
    final jewishCalendar =
        JewishCalendar.fromDateTime(state.selectedGregorianDate);
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
    return entries;
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
        final replacementIndex =
            remaining.indexWhere((entry) => entry.isComposite == false);
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
    _cityNames = cityCoordinates.values.expand((cities) => cities.keys).toList()
      ..sort();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final omerInfo = _buildOmerInfo(widget.state.selectedGregorianDate);
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.only(top: 8, bottom: 8, end: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                ToolbarActionButton(
                  tooltip: 'זמנים נוספים',
                  icon: FluentIcons.list_24_regular,
                  compact: true,
                  onPressed: () => showZmanimSettingsDialog(context),
                ),
                _CityDropdown(
                  cityName: widget.state.selectedCity,
                  cityNames: _cityNames,
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
                            size: 18,
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
    );
  }

  Widget _buildTimesGrid(BuildContext context) {
    final filteredTimesList = _buildCalendarTimeEntries(widget.state);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSingleColumn = constraints.maxWidth < 290;
        final columnCount = isSingleColumn ? 1 : 2;
        final spacing = 8.0;
        final arrangedTimesList =
            _arrangeEntriesForGrid(filteredTimesList, columnCount);
        final itemWidth =
            (constraints.maxWidth - (spacing * (columnCount - 1))) /
                columnCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final timeData in arrangedTimesList)
              SizedBox(
                width: timeData.isComposite && columnCount == 2
                    ? itemWidth * 2 + spacing
                    : itemWidth,
                child: _ZmanCard(
                  timeData: timeData,
                  zmanAlerts: widget.state.zmanAlerts,
                  onAlertPressed: () async {
                    final timeId = timeData.id;
                    final timeName = timeData.name;
                    final timeLabel = timeData.time;
                    final existingAlert = widget.state.zmanAlerts[timeId];
                    final hasAlert = existingAlert != null;
                    final cubit = context.read<CalendarCubit>();
                    if (timeLabel == '--:--') {
                      UiSnack.showError('לא ניתן להפעיל התראה לזמן לא זמין');
                      return;
                    }
                    final result = await showZmanAlertDialog(
                      context,
                      zmanName: timeName,
                      timeLabel: timeLabel,
                      initialMinutesBefore: existingAlert?.minutesBefore ?? 5,
                      isEnabled: hasAlert,
                    );
                    if (result == null) return;
                    if (result.cancelAlert) {
                      _runZmanAlertOp(
                        cubit.cancelZmanAlertPreference(timeId: timeId),
                      );
                      return;
                    }
                    _runZmanAlertOp(cubit.setZmanAlertPreference(
                      timeId: timeId,
                      displayName: timeName,
                      minutesBefore: result.minutesBefore,
                    ));
                  },
                ),
              ),
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
    final jewishCalendar =
        JewishCalendar.fromDateTime(widget.state.selectedGregorianDate);
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

    return RecommendedActionButton(
      text: _buildDafYomiButtonText(bavliTractate, dafLabel),
      icon: FluentIcons.book_24_regular,
      onPressed: bavliTractate == 'לא זמין'
          ? () => UiSnack.showError('הדף היומי לא זמין לתאריך זה')
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
        : SvgPicture.asset(
            'assets/icon/mount_sinai_tablets.svg',
            width: 20,
            height: 20,
            colorFilter: ColorFilter.mode(cs.onPrimary, BlendMode.srcIn),
          );

    return RecommendedActionButton(
      text: text,
      iconWidget: iconWidget,
      textAlign: TextAlign.center,
      onPressed: () async {
        final timeLabel = _resolveOmerAlertTimeLabel();
        if (timeLabel == '--:--') {
          UiSnack.showError('לא ניתן להפעיל התראה לספירת העומר ביום זה');
          return;
        }
        final result = await showZmanAlertDialog(
          context,
          zmanName: 'ספירת העומר',
          timeLabel: timeLabel,
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
        _runZmanAlertOp(cubit.setZmanAlertPreference(
          timeId: 'omerCounting',
          displayName: 'ספירת העומר',
          minutesBefore: result.minutesBefore,
        ));
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
      width: 180,
      child: AppDropdownField<String>(
        value: cityName,
        enableSearch: true,
        decoration: const InputDecoration(
          labelText: 'עיר',
          border: OutlineInputBorder(),
          isDense: true,
        ),
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
  unawaited(future.catchError((Object error, StackTrace stackTrace) {
    debugPrint('ZmanAlert op failed: $error\n$stackTrace');
    UiSnack.showError('שגיאה בעדכון ההתראה');
  }));
}

String _formatAlertMinutes(int minutes) {
  if (minutes < 60) return "$minutes דק'";
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (mins == 0) return hours == 1 ? 'שעה' : '$hours שעות';
  return hours == 1 ? "שעה ו$mins דק'" : "$hours שעות ו$mins דק'";
}

class _ZmanCard extends StatelessWidget {
  final CalendarTimeEntry timeData;
  final Map<String, ZmanAlertPreference?> zmanAlerts;
  final VoidCallback onAlertPressed;

  const _ZmanCard({
    required this.timeData,
    required this.zmanAlerts,
    required this.onAlertPressed,
  });

  ZmanAlertPreference? get _existingAlert {
    final direct = zmanAlerts[timeData.id];
    if (direct != null) return direct;
    for (final option in timeData.alertOptions) {
      final a = zmanAlerts[option.id];
      if (a != null) return a;
    }
    return null;
  }

  String _tooltipForAlert(ZmanAlertPreference? alert, String fallback) {
    if (alert == null) return fallback;
    return 'התראה פעילה ל${_formatAlertMinutes(alert.minutesBefore)} לפני הזמן';
  }

  Widget _buildCompositeSegment({
    required BuildContext context,
    required String text,
    required Color textColor,
    required bool titleAtStart,
    required ZmanAlertPreference? existingAlert,
    required VoidCallback onPressed,
  }) {
    final hasAlert = existingAlert != null;
    final control = _AlertControl(
      hasAlert: hasAlert,
      existingAlert: existingAlert,
      tooltip: _tooltipForAlert(existingAlert, 'הפעל התראה'),
      foregroundColor: textColor,
      onPressed: onPressed,
      menuEntries: const [],
      onOptionSelected: (_) {},
    );

    // הזמן עצמו ממורכז בחצי הכרטיס; שם הזמן (הכותרת) נשאר בקצה החיצוני
    // של הקטע. כל קטע תופס את כל רוחב חצי הכרטיס, ובו הכותרת/הזמן ומקש
    // ההתראה מוצבים זה לצד זה.
    return Row(
      textDirection: TextDirection.rtl,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: _CompositeLabelValue(
            text: text,
            textColor: textColor,
            titleAtStart: titleAtStart,
          ),
        ),
        const SizedBox(width: 6),
        control,
      ],
    );
  }

  /// בונה שורת composite עם 2 ערכים והתראה צמודה לכל ערך.
  Widget _buildAlertedCompositeRow({
    required BuildContext context,
    required String? trailingLabel,
    required String? leadingLabel,
    required List<CalendarTimeAlertOption> alertOptions,
    required Color textColor,
  }) {
    // כשרק אחד מבני-הזוג זמין (השני לא רלוונטי היום), alertOptions מכיל
    // אפשרות אחת בלבד — ואז גם הצד הקיים (trailing או leading) חייב
    // להשתמש ב-alertOptions[0]. רק כששניהם קיימים leading משתמש ב-[1].
    final hasTrailing = trailingLabel != null && alertOptions.isNotEmpty;
    final hasLeading = leadingLabel != null &&
        (hasTrailing ? alertOptions.length >= 2 : alertOptions.isNotEmpty);
    final leadingIndex = hasTrailing ? 1 : 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (hasTrailing)
          Expanded(
            child: _buildCompositeSegment(
              context: context,
              text: trailingLabel,
              textColor: textColor,
              titleAtStart: true,
              existingAlert: zmanAlerts[alertOptions[0].id],
              onPressed: () =>
                  _openAlertDialogForOption(context, alertOptions[0]),
            ),
          ),
        if (hasTrailing && hasLeading) const SizedBox(width: 8),
        if (hasLeading)
          Expanded(
            child: _buildCompositeSegment(
              context: context,
              text: leadingLabel,
              textColor: textColor,
              titleAtStart: false,
              existingAlert: zmanAlerts[alertOptions[leadingIndex].id],
              onPressed: () => _openAlertDialogForOption(
                  context, alertOptions[leadingIndex]),
            ),
          ),
      ],
    );
  }

  double _titleFontSizeFor(CalendarTimeEntry entry) {
    final base = entry.name.length > 28
        ? 11.0
        : entry.name.length > 20
            ? 12.0
            : entry.name.length > 16
                ? 13.0
                : 14.0;
    return base + 1;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final existingAlert = _existingAlert;
    final hasAlert = existingAlert != null;
    final bgColor = timeData.isHolidaySpecial
        ? scheme.secondaryContainer.withValues(alpha: isDark ? 0.82 : 0.55)
        : AppSurfaces.card(context);
    final primaryTextColor = timeData.isHolidaySpecial
        ? scheme.onSecondaryContainer
        : scheme.onSurface;
    final secondaryTextColor = timeData.isHolidaySpecial
        ? scheme.onSecondaryContainer.withValues(alpha: isDark ? 0.94 : 0.78)
        : scheme.onSurfaceVariant;

    return Card(
      elevation: 0,
      color: bgColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
      ),
      // minHeight במקום height קבוע: כרטיסי composite עם שתי אפשרויות התראה
      // צריכים ~133px (Row של שני _buildCompositeSegment עם כפתור התראה),
      // ולכן height: 118 גרם ל-overflow של 11-15px בתחתית. הגבלה מינימלית
      // שומרת על אחידות חזותית עבור הכרטיסים הרגילים ומאפשרת לכרטיסים
      // עם תוכן עשיר לגדול כדי הצורך.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 118),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Builder(
                builder: (context) {
                  final nameStyle =
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: _titleFontSizeFor(timeData),
                            color: primaryTextColor,
                          );
                  // כרטיס בודד עם תת-כותרת: שורת כותרת + שורת פירוט קטנה.
                  final showSubtitle =
                      !timeData.isComposite && timeData.subtitle.isNotEmpty;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          alignment: Alignment.center,
                          fit: BoxFit.scaleDown,
                          child: _OverflowAwareTooltipText(
                            text: timeData.name,
                            style: nameStyle,
                            maxLines: 2,
                          ),
                        ),
                      ),
                      if (showSubtitle)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            timeData.subtitle,
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontSize: 11,
                                      color: secondaryTextColor,
                                    ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              // כרטיס composite עם 2 אפשרויות התראה — אייקון ליד כל שעה
              if (timeData.isComposite && timeData.alertOptions.length >= 2)
                _buildAlertedCompositeRow(
                  context: context,
                  trailingLabel: timeData.trailingLabel,
                  leadingLabel: timeData.leadingLabel,
                  alertOptions: timeData.alertOptions,
                  textColor: secondaryTextColor,
                )
              else
                // כרטיס רגיל או composite ללא 2 אפשרויות — אייקון אחד בסוף
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: timeData.isComposite
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (timeData.trailingLabel != null)
                                  Expanded(
                                    child: _CompositeLabelValue(
                                      text: timeData.trailingLabel!,
                                      textColor: secondaryTextColor,
                                      titleAtStart: true,
                                    ),
                                  ),
                                if (timeData.trailingLabel != null &&
                                    timeData.leadingLabel != null)
                                  const SizedBox(width: 12),
                                if (timeData.leadingLabel != null)
                                  Expanded(
                                    child: _CompositeLabelValue(
                                      text: timeData.leadingLabel!,
                                      textColor: secondaryTextColor,
                                      titleAtStart: false,
                                    ),
                                  ),
                              ],
                            )
                          : Text(
                              timeData.time,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: secondaryTextColor,
                                  ),
                            ),
                    ),
                    if (timeData.canAlert) ...[
                      const SizedBox(width: 8),
                      _AlertControl(
                        hasAlert: hasAlert,
                        existingAlert: existingAlert,
                        tooltip: hasAlert
                            ? _tooltipForAlert(
                                existingAlert, 'הפעל התראה לזמן זה')
                            : timeData.alertOptions.isEmpty
                                ? 'הפעל התראה לזמן זה'
                                : 'בחר זמן להתראה',
                        foregroundColor: primaryTextColor,
                        onPressed: onAlertPressed,
                        menuEntries: timeData.alertOptions,
                        onOptionSelected: (option) =>
                            _openAlertDialogForOption(context, option),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAlertDialogForOption(
    BuildContext context,
    CalendarTimeAlertOption option,
  ) async {
    final cubit = context.read<CalendarCubit>();
    final existingAlert = cubit.state.zmanAlerts[option.id];
    final result = await showZmanAlertDialog(
      context,
      zmanName: option.name,
      timeLabel: option.time,
      initialMinutesBefore: existingAlert?.minutesBefore ?? 5,
      isEnabled: existingAlert != null,
    );
    if (result == null) return;
    if (result.cancelAlert) {
      _runZmanAlertOp(cubit.cancelZmanAlertPreference(timeId: option.id));
      return;
    }
    _runZmanAlertOp(cubit.setZmanAlertPreference(
      timeId: option.id,
      displayName: option.name,
      minutesBefore: result.minutesBefore,
    ));
  }
}

class _AlertControl extends StatelessWidget {
  final bool hasAlert;
  final ZmanAlertPreference? existingAlert;
  final String tooltip;
  final Color foregroundColor;
  final VoidCallback onPressed;
  final List<CalendarTimeAlertOption> menuEntries;
  final ValueChanged<CalendarTimeAlertOption> onOptionSelected;
  const _AlertControl({
    required this.hasAlert,
    required this.existingAlert,
    required this.tooltip,
    required this.foregroundColor,
    required this.onPressed,
    required this.menuEntries,
    required this.onOptionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final iconData =
        hasAlert ? FluentIcons.alert_24_filled : FluentIcons.alert_24_regular;
    final minutesBefore = existingAlert?.minutesBefore;

    final action = menuEntries.isEmpty
        ? ToolbarActionButton(
            tooltip: tooltip,
            icon: iconData,
            onPressed: onPressed,
            selected: hasAlert,
            compact: true,
          )
        : AppPopupMenuButton<CalendarTimeAlertOption>(
            tooltip: tooltip,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            icon: Icon(
              iconData,
              size: 20,
              color: hasAlert
                  ? Theme.of(context).colorScheme.primary
                  : foregroundColor,
            ),
            entries: [
              for (final option in menuEntries)
                AppMenuEntry<CalendarTimeAlertOption>(
                  value: option,
                  label: option.name,
                  trailing: Text(
                    option.time,
                    textDirection: TextDirection.rtl,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
            onSelected: onOptionSelected,
          );

    // הטקסט תמיד תופס מקום (Opacity במקום if) — מצב פעיל לא משנה את גובה הווידג'ט
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Opacity(
          opacity: minutesBefore != null ? 1.0 : 0.0,
          child: Text(
            minutesBefore != null ? _formatAlertMinutes(minutesBefore) : '',
            textDirection: TextDirection.rtl,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: foregroundColor,
                  fontSize: 11,
                ),
          ),
        ),
        const SizedBox(height: 4),
        action,
      ],
    );
  }
}

bool _textOverflows({
  required BuildContext context,
  required String text,
  required TextStyle style,
  required int maxLines,
  required double maxWidth,
  required TextDirection textDirection,
  required TextAlign textAlign,
}) {
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: maxLines,
    ellipsis: '…',
    textDirection: textDirection,
    textAlign: textAlign,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: maxWidth);

  return textPainter.didExceedMaxLines;
}

class _OverflowAwareTooltipText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;

  const _OverflowAwareTooltipText({
    required this.text,
    this.style,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = style ?? DefaultTextStyle.of(context).style;

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasOverflow = constraints.maxWidth.isFinite &&
            constraints.maxWidth > 0 &&
            _textOverflows(
              context: context,
              text: text,
              style: resolvedStyle,
              maxLines: maxLines,
              maxWidth: constraints.maxWidth,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
            );

        final child = Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
          style: resolvedStyle,
        );

        if (!hasOverflow) {
          return child;
        }

        final scheme = Theme.of(context).colorScheme;
        return Tooltip(
          message: text,
          waitDuration: const Duration(milliseconds: 300),
          textAlign: TextAlign.right,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          margin: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.65),
            ),
          ),
          child: child,
        );
      },
    );
  }
}

class _CompositeLabelValue extends StatelessWidget {
  final String text;
  final Color textColor;

  /// כשערכו true (קטע ימני ב-RTL) הכותרת מיושרת לקצה ההתחלה (ימין);
  /// כשערכו false (קטע שמאלי) — לקצה הסוף (שמאל). הזמן עצמו תמיד ממורכז.
  final bool titleAtStart;

  const _CompositeLabelValue({
    required this.text,
    required this.textColor,
    this.titleAtStart = true,
  });

  @override
  Widget build(BuildContext context) {
    final lastSpace = text.lastIndexOf(' ');
    final title = lastSpace == -1 ? text : text.substring(0, lastSpace);
    final value = lastSpace == -1 ? '' : text.substring(lastSpace + 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: titleAtStart
              ? AlignmentDirectional.centerStart
              : AlignmentDirectional.centerEnd,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    fontSize: 11,
                  ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    fontSize: 12,
                  ),
            ),
          ),
        ),
      ],
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
      radius: AppTokens.radiusMD,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // כותרת ממורכזת כמו ב-_ZmanCard
          SizedBox(
            width: double.infinity,
            child: Text(
              'מולד ${info.monthName} — ${_moladReasonLabel(info.reason)}',
              textDirection: TextDirection.rtl,
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
            textDirection: TextDirection.rtl,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            info.announcementText,
            textDirection: TextDirection.rtl,
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
            textDirection: TextDirection.rtl,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${info.visibleDayName} ${info.visibleHebrewDate} '
            'בשעה ${info.visibleTimeFormatted}',
            textDirection: TextDirection.rtl,
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
