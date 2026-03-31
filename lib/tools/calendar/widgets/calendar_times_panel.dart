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

  const CalendarTimeEntry({
    required this.id,
    required this.name,
    required this.time,
    required this.isHolidaySpecial,
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
    'shabbosExit1',
    'shabbosExit2',
    'omerCounting',
  };

  List<CalendarTimeEntry> _buildCalendarTimeEntries(CalendarState state) {
    final dailyTimes = state.dailyTimes;
    final definitions = <_CalendarTimeDefinition>[
      ..._kBaseTimeDefinitions,
      ..._kConditionalTimeDefinitions,
    ];

    return definitions
        .map(
          (definition) => CalendarTimeEntry(
            id: definition.id,
            name: definition.name,
            time: dailyTimes[definition.id] ?? '',
            isHolidaySpecial: _isHolidaySpecialTimeId(definition.id),
          ),
        )
        .where((entry) => entry.time.isNotEmpty)
        .toList();
  }

  bool _isHolidaySpecialTimeId(String timeId) {
    return _holidaySpecialIds.contains(timeId);
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
        final isSingleColumn = constraints.maxWidth < 360;
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
            ? scheme.tertiaryContainer.withValues(alpha: 0.55)
            : AppSurfaces.card(context);
    final borderColor = hasAlert
        ? scheme.error.withValues(alpha: 0.35)
        : timeData.isHolidaySpecial
            ? scheme.tertiary.withValues(alpha: 0.35)
            : scheme.outlineVariant;

    return Card(
      elevation: 0,
      color: bgColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    timeData.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: hasAlert
                              ? scheme.onErrorContainer
                              : timeData.isHolidaySpecial
                                  ? scheme.onTertiaryContainer
                                  : scheme.onSurface,
                        ),
                  ),
                ),
                ToolbarActionButton(
                  tooltip:
                      hasAlert ? 'מופעלת התראה לזמן זה' : 'הפעל התראה לזמן זה',
                  icon: FluentIcons.more_vertical_24_regular,
                  onPressed: onAlertPressed,
                  selected: hasAlert,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              timeData.time,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: hasAlert
                        ? scheme.onErrorContainer
                        : timeData.isHolidaySpecial
                            ? scheme.onTertiaryContainer
                            : scheme.onSurfaceVariant,
                  ),
            ),
            if (hasAlert) ...[
              const SizedBox(height: 6),
              Text(
                'התראה ${existingAlert!.minutesBefore} דק׳ לפני',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
