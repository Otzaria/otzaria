import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/models/calendar_location.dart';
import 'package:otzaria/tools/calendar/helpers/daf_yomi_navigation.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_zman_alert_dialog.dart';
import 'package:otzaria/widgets/app_menu.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';

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
  _CalendarTimeDefinition(id: 'sunsetRT', name: 'שקיעה לרבנו תם'),
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

    entries.sort((a, b) => a.time.compareTo(b.time));
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

    final sortTime = regularExit?.isNotEmpty == true
        ? regularExit!
        : chazonIshExit ?? '';

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
    return 'היום $omerDay לעומר';
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(AppTokens.radiusMD),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'אין לסמוך על הזמנים כלל!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'שים לב! ',
                          style: TextStyle(fontSize: 12),
                        ),
                        WidgetSpan(
                          child: InkWell(
                            onTap: () =>
                                widget.onOpenCalendarCalculationPage(context),
                            child: Text(
                              'הזמנים שונים',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                        const TextSpan(
                          text: ' מהותית מהלוח \'עיתים לבינה\'!',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
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
        final itemWidth =
            (constraints.maxWidth - (spacing * (columnCount - 1))) /
                columnCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final timeData in filteredTimesList)
              SizedBox(
                width: itemWidth,
                child: _ZmanCard(
                  timeData: timeData,
                  existingAlert: widget.state.zmanAlerts[timeData.id],
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
                      initialMinutesBefore:
                          existingAlert?.minutesBefore ?? 60,
                      isEnabled: hasAlert,
                    );
                    if (result == null) return;
                    if (result.cancelAlert) {
                      await cubit.cancelZmanAlertPreference(timeId: timeId);
                      return;
                    }
                    await cubit.setZmanAlertPreference(
                      timeId: timeId,
                      displayName: timeName,
                      minutesBefore: result.minutesBefore,
                    );
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
    return RecommendedActionButton(
      text: text,
      icon: existingAlert != null
          ? FluentIcons.alert_24_filled
          : FluentIcons.number_row_24_regular,
      onPressed: () async {
        final timeLabel = widget.state.dailyTimes['omerCounting'] ?? '--:--';
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
          await cubit.cancelZmanAlertPreference(timeId: 'omerCounting');
          return;
        }
        await cubit.setZmanAlertPreference(
          timeId: 'omerCounting',
          displayName: 'ספירת העומר',
          minutesBefore: result.minutesBefore,
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
      width: 220,
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

class _ZmanCard extends StatelessWidget {
  final CalendarTimeEntry timeData;
  final ZmanAlertPreference? existingAlert;
  final VoidCallback onAlertPressed;

  const _ZmanCard({
    required this.timeData,
    required this.existingAlert,
    required this.onAlertPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasAlert = existingAlert != null;
    final bgColor = hasAlert
        ? scheme.errorContainer.withValues(alpha: 0.55)
        : timeData.isHolidaySpecial
            ? scheme.secondaryContainer.withValues(alpha: 0.55)
            : AppSurfaces.card(context);
    final borderColor = hasAlert
        ? scheme.error.withValues(alpha: 0.35)
        : timeData.isHolidaySpecial
            ? scheme.secondary.withValues(alpha: 0.35)
            : scheme.outlineVariant;

    return Card(
      elevation: 0,
      color: bgColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        side: BorderSide(color: borderColor),
      ),
      child: SizedBox(
        height: 112,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final titleFontSize = timeData.name.length > 28
                            ? 11.0
                            : timeData.name.length > 20
                                ? 12.0
                                : timeData.name.length > 16
                                    ? 13.0
                                    : 14.0;
                        final nameStyle = Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: titleFontSize,
                              color: hasAlert
                                  ? scheme.onErrorContainer
                                  : timeData.isHolidaySpecial
                                      ? scheme.onSecondaryContainer
                                      : scheme.onSurface,
                            );
                        return FittedBox(
                          alignment: AlignmentDirectional.centerStart,
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: constraints.maxWidth,
                            child: Text(
                              timeData.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.rtl,
                              style: nameStyle,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (timeData.alertOptions.isEmpty)
                    ToolbarActionButton(
                      tooltip: hasAlert
                          ? 'מופעלת התראה לזמן זה'
                          : 'הפעל התראה לזמן זה',
                      icon: FluentIcons.more_vertical_24_regular,
                      onPressed: onAlertPressed,
                      selected: hasAlert,
                    )
                  else
                    PopupMenuButton<CalendarTimeAlertOption>(
                      tooltip: hasAlert
                          ? 'מופעלת התראה לזמן זה'
                          : 'בחר זמן להתראה',
                      icon: Icon(
                        FluentIcons.more_vertical_24_regular,
                        size: 20,
                        color: hasAlert
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      ),
                      onSelected: (option) {
                        _openAlertDialogForOption(context, option);
                      },
                      itemBuilder: (context) => [
                        for (final option in timeData.alertOptions)
                          PopupMenuItem<CalendarTimeAlertOption>(
                            value: option,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  option.name,
                                  textDirection: TextDirection.rtl,
                                ),
                                Text(
                                  option.time,
                                  textDirection: TextDirection.rtl,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              const Spacer(),
              if (timeData.isComposite)
                Row(
                  children: [
                    if (timeData.trailingLabel != null)
                      Expanded(
                        child: _CompositeLabelValue(
                          text: timeData.trailingLabel!,
                          textColor: scheme.onSurfaceVariant,
                          crossAxisAlignment: CrossAxisAlignment.end,
                        ),
                      ),
                    if (timeData.trailingLabel != null &&
                        timeData.leadingLabel != null)
                      const SizedBox(width: 12),
                    if (timeData.leadingLabel != null)
                      Expanded(
                        child: _CompositeLabelValue(
                          text: timeData.leadingLabel!,
                          textColor: scheme.onSurfaceVariant,
                          crossAxisAlignment: CrossAxisAlignment.start,
                        ),
                      ),
                  ],
                )
              else
                Text(
                  timeData.time,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: hasAlert
                            ? scheme.onErrorContainer
                            : timeData.isHolidaySpecial
                                ? scheme.onSecondaryContainer
                                : scheme.onSurfaceVariant,
                      ),
                ),
              if (hasAlert) ...[
                const SizedBox(height: 4),
                Text(
                  'התראה ${existingAlert!.minutesBefore} דק׳ לפני',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                        fontSize: 11,
                      ),
                ),
              ],
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
      initialMinutesBefore: existingAlert?.minutesBefore ?? 60,
      isEnabled: existingAlert != null,
    );
    if (result == null) return;
    if (result.cancelAlert) {
      await cubit.cancelZmanAlertPreference(timeId: option.id);
      return;
    }
    await cubit.setZmanAlertPreference(
      timeId: option.id,
      displayName: option.name,
      minutesBefore: result.minutesBefore,
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
