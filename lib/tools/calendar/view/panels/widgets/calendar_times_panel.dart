import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/settings_card.dart';
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
      child: SettingsCard(
        title: 'זמני היום',
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppTokens.radiusMD),
                border: Border.all(
                  color: theme.colorScheme.primary,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _buildTimesGrid(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: _buildDafYomiButtons(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTimesGrid(BuildContext context) {
    final filteredTimesList = buildCalendarTimeEntries(widget.state);
    final scheme = Theme.of(context).colorScheme;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: filteredTimesList.length,
      itemBuilder: (context, index) {
        final timeData = filteredTimesList[index];
        final timeId = timeData.id;
        final timeName = timeData.name;
        final timeLabel = timeData.time;
        final existingAlert = widget.state.zmanAlerts[timeId];
        final hasAlert = existingAlert != null;
        final isSpecialTime = timeData.isSpecial;
        final bgColor = hasAlert
            ? scheme.errorContainer
            : isSpecialTime
                ? scheme.tertiaryContainer
                : scheme.surfaceContainerHighest;
        final border = hasAlert
            ? Border.all(color: scheme.error, width: 1)
            : isSpecialTime
                ? Border.all(color: scheme.tertiary, width: 1)
                : null;
        final titleColor = hasAlert
            ? scheme.onErrorContainer
            : isSpecialTime
                ? scheme.onTertiaryContainer
                : scheme.onSurfaceVariant;
        final timeColor = hasAlert
            ? scheme.onErrorContainer
            : isSpecialTime
                ? scheme.onTertiaryContainer
                : scheme.onSurface;

        return LayoutBuilder(builder: (context, itemConstraints) {
          final isCompact =
              itemConstraints.maxHeight < 44 || itemConstraints.maxWidth < 110;
          final titleFontSize = isCompact ? 10.0 : 12.0;
          final timeFontSize = isCompact ? 12.0 : 14.0;
          final pad = isCompact ? 4.0 : 8.0;
          final menuSize = isCompact ? 14.0 : 18.0;
          final menuIconSize = isCompact ? 12.0 : 16.0;

          return Container(
            padding: EdgeInsets.all(pad),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: border,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: isCompact
                  ? MainAxisAlignment.spaceBetween
                  : MainAxisAlignment.center,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        timeName,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w500,
                          color: titleColor,
                          height: isCompact ? 1.2 : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    PopupMenuButton<ZmanMenuAction>(
                      tooltip: '',
                      padding: EdgeInsets.zero,
                      child: SizedBox.square(
                        dimension: menuSize,
                        child: Center(
                          child: Icon(
                            FluentIcons.more_vertical_24_regular,
                            color: titleColor,
                            size: menuIconSize,
                          ),
                        ),
                      ),
                      itemBuilder: (_) => [
                        PopupMenuItem<ZmanMenuAction>(
                          value: ZmanMenuAction.toggle,
                          child: Text(hasAlert
                              ? 'מופעלת התראה לזמן זה'
                              : 'הפעל התראה לזמן זה'),
                        ),
                      ],
                      onSelected: (_) async {
                        final cubit = context.read<CalendarCubit>();
                        if (timeLabel == '--:--') {
                          UiSnack.showError(
                              'לא ניתן להפעיל התראה לזמן לא זמין');
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
                  ],
                ),
                if (!isCompact) const SizedBox(height: 2),
                Text(
                  timeLabel,
                  style: TextStyle(
                    fontSize: timeFontSize,
                    fontWeight: FontWeight.bold,
                    color: timeColor,
                    height: isCompact ? 1.0 : null,
                  ),
                ),
              ],
            ),
          );
        });
      },
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

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () =>
                openDafYomiBook(context, bavliTractate, ' $dafLabel.'),
            icon: const Icon(FluentIcons.book_24_regular),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'דף היומי בבלי',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text('$bavliTractate $dafLabel',
                    style: const TextStyle(fontSize: 10)),
              ],
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            ),
          ),
        ),
      ],
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
