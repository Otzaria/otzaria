import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/utils/daf_yomi_navigator.dart';
import 'package:otzaria/tools/calendar/view/panels/logic/calendar_times_panel_logic.dart';
import 'package:otzaria/tools/calendar/view/widgets/calendar_zman_alert_dialog.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';

/// פאנל זמני היום.
class CalendarTimesPanel extends StatefulWidget {
  final CalendarState state;
  final VoidCallback onCityPressed;
  final Future<void> Function(BuildContext context)
      onOpenCalendarCalculationPage;

  const CalendarTimesPanel({
    super.key,
    required this.state,
    required this.onCityPressed,
    required this.onOpenCalendarCalculationPage,
  });

  @override
  State<CalendarTimesPanel> createState() => _CalendarTimesPanelState();
}

class _CalendarTimesPanelState extends State<CalendarTimesPanel> {
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
                _CityButton(
                  cityName: widget.state.selectedCity,
                  onPressed: widget.onCityPressed,
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
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
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
    final filteredTimesList = buildCalendarTimeEntries(widget.state);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final timeData in filteredTimesList)
          _ZmanCard(
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
                initialMinutesBefore: existingAlert?.minutesBefore ?? 60,
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
      ],
    );
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
    final dafLabel = HebrewDateFormatter()
        .formatHebrewNumber(bavliDaf)
        .replaceAll('״', '')
        .replaceAll('׳', '');

    return RecommendedActionButton(
      text: 'דף היומי בבלי',
      icon: FluentIcons.book_24_regular,
      onPressed: () => openDafYomiBook(context, bavliTractate, ' $dafLabel.'),
    );
  }
}

class _CityButton extends StatelessWidget {
  final String cityName;
  final VoidCallback onPressed;

  const _CityButton({
    required this.cityName,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return NeutralActionButton(
      text: cityName,
      icon: FluentIcons.chevron_down_24_regular,
      onPressed: onPressed,
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
        : timeData.isSpecial
            ? scheme.tertiaryContainer.withValues(alpha: 0.55)
            : scheme.surfaceContainerHighest;
    final borderColor = hasAlert
        ? scheme.error.withValues(alpha: 0.35)
        : timeData.isSpecial
            ? scheme.tertiary.withValues(alpha: 0.35)
            : scheme.outlineVariant;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 240),
      child: Card(
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
                                : timeData.isSpecial
                                    ? scheme.onTertiaryContainer
                                    : scheme.onSurface,
                          ),
                    ),
                  ),
                  ToolbarActionButton(
                    tooltip: hasAlert
                        ? 'מופעלת התראה לזמן זה'
                        : 'הפעל התראה לזמן זה',
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
                          : timeData.isSpecial
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
      ),
    );
  }
}
