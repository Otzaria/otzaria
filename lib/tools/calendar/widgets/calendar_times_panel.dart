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
import 'package:otzaria/tools/calendar/helpers/daf_yomi_navigation.dart';
import 'package:otzaria/tools/calendar/helpers/zmanim_helpers.dart'
    as zmanim_helpers;
import 'package:otzaria/tools/calendar/dialogs/calendar_zman_alert_dialog.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:timezone/timezone.dart' as tz;

class CalendarTimeEntry {
  final String id;
  final String name;
  final String time;
  final bool isHolidaySpecial;
  final bool isComposite;
  final String? trailingLabel;
  final String? leadingLabel;
  final List<CalendarTimeAlertOption> alertOptions;

  const CalendarTimeEntry({
    required this.id,
    required this.name,
    required this.time,
    required this.isHolidaySpecial,
    this.isComposite = false,
    this.trailingLabel,
    this.leadingLabel,
    this.alertOptions = const [],
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

class _CalendarTimeDefinition {
  final String id;
  final String name;

  const _CalendarTimeDefinition({
    required this.id,
    required this.name,
  });
}

const List<_CalendarTimeDefinition> _kBaseTimeDefinitions = [
  _CalendarTimeDefinition(id: 'alos', name: 'עלות השחר'),
  _CalendarTimeDefinition(
    id: 'alos16point1Degrees',
    name: 'עלוה"ש (72 דק\') במע\'',
  ),
  _CalendarTimeDefinition(
    id: 'alos19point8Degrees',
    name: 'עלוה"ש (90 דק\') במע\'',
  ),
  _CalendarTimeDefinition(id: 'sunrise', name: 'זריחה'),
  _CalendarTimeDefinition(id: 'sofZmanShmaMGA', name: 'סוף זמן ק"ש - מג"א'),
  _CalendarTimeDefinition(id: 'sofZmanShmaGRA', name: 'סוף זמן ק"ש - גר"א'),
  _CalendarTimeDefinition(
    id: 'sofZmanTfilaMGA',
    name: 'סוף זמן תפילה - מג"א',
  ),
  _CalendarTimeDefinition(
    id: 'sofZmanTfilaGRA',
    name: 'סוף זמן תפילה - גר"א',
  ),
  _CalendarTimeDefinition(id: 'chatzos', name: 'חצות היום'),
  _CalendarTimeDefinition(id: 'chatzosLayla', name: 'חצות לילה'),
  _CalendarTimeDefinition(id: 'minchaGedola', name: 'מנחה גדולה'),
  _CalendarTimeDefinition(id: 'minchaKetana', name: 'מנחה קטנה'),
  _CalendarTimeDefinition(id: 'plagHamincha', name: 'פלג המנחה'),
  _CalendarTimeDefinition(id: 'sunset', name: 'שקיעה'),
  _CalendarTimeDefinition(id: 'sunsetRT', name: 'צאת הכוכבים לרבנו תם'),
  _CalendarTimeDefinition(id: 'tzais', name: 'צאת הכוכבים'),
];

const List<_CalendarTimeDefinition> _kConditionalTimeDefinitions = [
  _CalendarTimeDefinition(id: 'candleLighting', name: 'הדלקת נרות'),
  _CalendarTimeDefinition(id: 'shabbosExit1', name: 'מוצאי שבת/חג'),
  _CalendarTimeDefinition(id: 'shabbosExit2', name: 'מוצאי שבת/חג לחזו"א'),
  _CalendarTimeDefinition(id: 'omerCounting', name: 'ספירת העומר'),
  _CalendarTimeDefinition(
    id: 'sofZmanAchilasChametzMGA',
    name: 'סוף זמן אכילת חמץ - מג"א',
  ),
  _CalendarTimeDefinition(
    id: 'sofZmanAchilasChametzGRA',
    name: 'סוף זמן אכילת חמץ - גר"א',
  ),
  _CalendarTimeDefinition(
    id: 'sofZmanBiurChametzMGA',
    name: 'סוף זמן ביעור חמץ - מג"א',
  ),
  _CalendarTimeDefinition(
    id: 'sofZmanBiurChametzGRA',
    name: 'סוף זמן ביעור חמץ - גר"א',
  ),
  _CalendarTimeDefinition(id: 'fastStart', name: 'תחילת התענית'),
  _CalendarTimeDefinition(id: 'fastEnd', name: 'סיום התענית'),
  _CalendarTimeDefinition(
    id: 'kidushLevanaEarliest',
    name: 'קידוש לבנה מוקדם',
  ),
  _CalendarTimeDefinition(
    id: 'kidushLevanaLatest',
    name: 'קידוש לבנה מאוחר',
  ),
  _CalendarTimeDefinition(
    id: 'tchilasKidushLevana',
    name: 'תחילת זמן קידוש לבנה',
  ),
  _CalendarTimeDefinition(
    id: 'sofZmanKidushLevana',
    name: 'סוף זמן קידוש לבנה',
  ),
];

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

  static const Set<String> _holidaySpecialIds = {
    'candleLighting',
    'shabbosExitComposite',
  };


  List<CalendarTimeEntry> _buildCalendarTimeEntries(CalendarState state) {
    final dailyTimes = state.dailyTimes;
    final entries = <CalendarTimeEntry>[];
    final alosCard = _buildCompositeAlosEntry(dailyTimes);
    if (alosCard != null) {
      entries.add(alosCard);
    }
    final shabbosExitCard = _buildCompositeShabbosExitEntry(dailyTimes);
    if (shabbosExitCard != null) {
      entries.add(shabbosExitCard);
    }

    final definitions = <_CalendarTimeDefinition>[
      ..._kBaseTimeDefinitions,
      ..._kConditionalTimeDefinitions,
    ].where((definition) =>
        definition.id != 'alos' &&
        definition.id != 'alos16point1Degrees' &&
        definition.id != 'alos19point8Degrees' &&
        definition.id != 'omerCounting' &&
        definition.id != 'shabbosExit1' &&
        definition.id != 'shabbosExit2');

    entries.addAll(
      definitions
          .map(
            (definition) => CalendarTimeEntry(
              id: definition.id,
              name: definition.name,
              time: dailyTimes[definition.id] ?? '',
              isHolidaySpecial: _isHolidaySpecialTimeId(definition.id),
            ),
          )
          .where((entry) => entry.time.isNotEmpty),
    );

    entries.sort((a, b) {
      // חצות לילה תמיד בסוף
      if (a.id == 'chatzosLayla') return 1;
      if (b.id == 'chatzosLayla') return -1;
      return a.time.compareTo(b.time);
    });
    return entries;
  }

  bool _isHolidaySpecialTimeId(String timeId) {
    return _holidaySpecialIds.contains(timeId);
  }

  CalendarTimeEntry? _buildCompositeAlosEntry(Map<String, String> dailyTimes) {
    final alos90 = dailyTimes['alos19point8Degrees'];
    final alos72 = dailyTimes['alos16point1Degrees'];
    final regularAlos = dailyTimes['alos'];

    if ((alos90 == null || alos90.isEmpty) &&
        (alos72 == null || alos72.isEmpty) &&
        (regularAlos == null || regularAlos.isEmpty)) {
      return null;
    }

    final sortTime = alos72?.isNotEmpty == true
        ? alos72!
        : (alos90?.isNotEmpty == true ? alos90! : regularAlos ?? '');

    return CalendarTimeEntry(
      id: 'alosComposite',
      name: 'עלות השחר (מעלות)',
      time: sortTime,
      isHolidaySpecial: false,
      isComposite: true,
      trailingLabel: alos90?.isNotEmpty == true
          ? '90 דק׳ $alos90'
          : (regularAlos?.isNotEmpty == true ? 'רגיל $regularAlos' : null),
      leadingLabel: alos72?.isNotEmpty == true ? '72 דק׳ $alos72' : null,
      alertOptions: [
        if (alos72?.isNotEmpty == true)
          CalendarTimeAlertOption(
            id: 'alos16point1Degrees',
            name: 'עלות השחר 72 דק׳',
            time: alos72!,
          ),
        if (alos90?.isNotEmpty == true)
          CalendarTimeAlertOption(
            id: 'alos19point8Degrees',
            name: 'עלות השחר 90 דק׳',
            time: alos90!,
          ),
      ],
    );
  }

  CalendarTimeEntry? _buildCompositeShabbosExitEntry(
    Map<String, String> dailyTimes,
  ) {
    final regularExit = dailyTimes['shabbosExit1'];
    final chazonIshExit = dailyTimes['shabbosExit2'];
    if ((regularExit == null || regularExit.isEmpty) &&
        (chazonIshExit == null || chazonIshExit.isEmpty)) {
      return null;
    }

    final sortTime =
        regularExit?.isNotEmpty == true ? regularExit! : chazonIshExit ?? '';

    return CalendarTimeEntry(
      id: 'shabbosExitComposite',
      name: 'מוצאי שבת/חג',
      time: sortTime,
      isHolidaySpecial: true,
      isComposite: true,
      trailingLabel:
          regularExit?.isNotEmpty == true ? 'רגיל $regularExit' : null,
      leadingLabel:
          chazonIshExit?.isNotEmpty == true ? 'חזו"א $chazonIshExit' : null,
      alertOptions: [
        if (regularExit?.isNotEmpty == true)
          CalendarTimeAlertOption(
            id: 'shabbosExit1',
            name: 'מוצאי שבת/חג',
            time: regularExit!,
          ),
        if (chazonIshExit?.isNotEmpty == true)
          CalendarTimeAlertOption(
            id: 'shabbosExit2',
            name: 'מוצאי שבת/חג חזו"א',
            time: chazonIshExit!,
          ),
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                const Spacer(),
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
                const SizedBox(height: 4),
                Text(
                  "שים לב! הזמנים שונים מהותית מהלוח 'עיתים לבינה'!",
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: theme.textTheme.bodySmall,
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
    required CrossAxisAlignment textAlignment,
    required bool alignToStart,
    required ZmanAlertPreference? existingAlert,
    required VoidCallback onPressed,
  }) {
    final hasAlert = existingAlert != null;
    final segmentAlignment = alignToStart
        ? AlignmentDirectional.centerStart
        : AlignmentDirectional.centerEnd;
    final control = Align(
      alignment: segmentAlignment,
      child: _AlertControl(
        hasAlert: hasAlert,
        existingAlert: existingAlert,
        tooltip: _tooltipForAlert(existingAlert, 'הפעל התראה'),
        foregroundColor: textColor,
        onPressed: onPressed,
        menuEntries: const [],
        onOptionSelected: (_) {},
      ),
    );

    final labelValue = _CompositeLabelValue(
      text: text,
      textColor: textColor,
      crossAxisAlignment: textAlignment,
    );

    return Align(
      alignment: segmentAlignment,
      child: Row(
        textDirection: TextDirection.rtl,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        // alignToStart=true (90 דק') → אייקון ימין, טקסט שמאל
        // alignToStart=false (72 דק') → טקסט ימין, אייקון שמאל
        children: alignToStart
            ? [control, const SizedBox(width: 6), labelValue]
            : [labelValue, const SizedBox(width: 6), control],
      ),
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
      child: SizedBox(
        height: 118,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final nameStyle =
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: _titleFontSizeFor(timeData),
                            color: primaryTextColor,
                          );
                  return FittedBox(
                    alignment: Alignment.center,
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: Align(
                        alignment: Alignment.center,
                        child: _OverflowAwareTooltipText(
                          text: timeData.name,
                          style: nameStyle,
                          maxLines: 2,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const Spacer(),
              // כרטיס composite עם 2 אפשרויות התראה — אייקון ליד כל שעה
              if (timeData.isComposite && timeData.alertOptions.length >= 2)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (timeData.trailingLabel != null) ...[
                      Expanded(
                        child: _buildCompositeSegment(
                          context: context,
                          text: timeData.trailingLabel!,
                          textColor: secondaryTextColor,
                          textAlignment: CrossAxisAlignment.end,
                          alignToStart: true,
                          existingAlert:
                              zmanAlerts[timeData.alertOptions[0].id],
                          onPressed: () => _openAlertDialogForOption(
                            context,
                            timeData.alertOptions[0],
                          ),
                        ),
                      ),
                    ],
                    if (timeData.trailingLabel != null &&
                        timeData.leadingLabel != null)
                      const SizedBox(width: 8),
                    if (timeData.leadingLabel != null) ...[
                      Expanded(
                        child: _buildCompositeSegment(
                          context: context,
                          text: timeData.leadingLabel!,
                          textColor: secondaryTextColor,
                          textAlignment: CrossAxisAlignment.start,
                          alignToStart: false,
                          existingAlert:
                              zmanAlerts[timeData.alertOptions[1].id],
                          onPressed: () => _openAlertDialogForOption(
                            context,
                            timeData.alertOptions[1],
                          ),
                        ),
                      ),
                    ],
                  ],
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                    ),
                                  ),
                              ],
                            )
                          : Text(
                              timeData.time,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: secondaryTextColor,
                                  ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    _AlertControl(
                      hasAlert: hasAlert,
                      existingAlert: existingAlert,
                      tooltip: hasAlert
                          ? _tooltipForAlert(existingAlert, 'הפעל התראה לזמן זה')
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
            emphasis: ToolbarActionButtonEmphasis.subtle,
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
  final CrossAxisAlignment crossAxisAlignment;

  const _CompositeLabelValue({
    required this.text,
    required this.textColor,
    required this.crossAxisAlignment,
  });

  @override
  Widget build(BuildContext context) {
    final lastSpace = text.lastIndexOf(' ');
    final title = lastSpace == -1 ? text : text.substring(0, lastSpace);
    final value = lastSpace == -1 ? '' : text.substring(lastSpace + 1);
    final alignment = crossAxisAlignment == CrossAxisAlignment.end
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart;

    return Align(
      alignment: alignment,
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
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
          const SizedBox(height: 2),
          FittedBox(
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
        ],
      ),
    );
  }
}
