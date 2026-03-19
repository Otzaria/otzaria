import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/widgets/otzaria_search_field.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/models/city_coordinates.dart';
import 'package:otzaria/widgets/dialogs.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/widgets/custom_ui_components.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/app_menu.dart';

/// טאב הגדרות לוח שנה
class CalendarSettingsTab extends StatefulWidget {
  const CalendarSettingsTab({super.key});

  @override
  State<CalendarSettingsTab> createState() => _CalendarSettingsTabState();
}

class _CalendarSettingsTabState extends State<CalendarSettingsTab> {
  bool _showCitySearch = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalendarCubit, CalendarState>(
      builder: (context, state) {
        final isOfflineMode =
            context.watch<SettingsBloc>().state.isOfflineMode;
        // [הוסר] SingleChildScrollView — ToolsSettingsTab גולל את כולם
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── לוח שנה: סוג לוח + עיר באותו מקטע ──
              SettingsCard(
                title: 'לוח שנה',
                children: [
                  // סוג לוח
                  SegmentedSettingsTile<CalendarType>(
                    icon: FluentIcons.calendar_24_regular,
                    title: 'סוג לוח שנה',
                    subtitle: state.calendarType == CalendarType.hebrew
                        ? 'יוצג לוח השנה היהודי בלבד'
                        : state.calendarType == CalendarType.gregorian
                            ? 'יוצג לוח השנה הלועזי בלבד'
                            : 'יוצגו תאריכים מהלוח העברי והלועזי יחד',
                    options: const [
                      SegmentOption(value: CalendarType.hebrew, label: 'עברי'),
                      SegmentOption(
                          value: CalendarType.combined, label: 'משולב'),
                      SegmentOption(
                          value: CalendarType.gregorian, label: 'לועזי'),
                    ],
                    currentValue: state.calendarType,
                    onChanged: (value) {
                      context.read<CalendarCubit>().changeCalendarType(value);
                    },
                  ),
                  // עיר
                  ListTile(
                    leading: const Icon(FluentIcons.location_24_regular),
                    title: const Text('עיר נבחרת', style: kSettingsTitleStyle),
                    trailing: NeutralActionButton(
                      text: state.selectedCity,
                      icon: _showCitySearch
                          ? FluentIcons.chevron_up_24_regular
                          : FluentIcons.chevron_down_24_regular,
                      onPressed: () {
                        setState(() {
                          _showCitySearch = !_showCitySearch;
                        });
                      },
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: _showCitySearch
                        ? Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: _CitySearchWidget(
                              currentCity: state.selectedCity,
                              onCitySelected: (city) {
                                context.read<CalendarCubit>().changeCity(city);
                                setState(() => _showCitySearch = false);
                              },
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),

              kSettingsCardSpacing,

              // ── אירועים ותזכורות: התראות + Google Calendar ──
              SettingsCard(
                title: 'אירועים ותזכורות',
                children: [
                  // הפעל התראות
                  SwitchSettingsTile(
                    leading: const Icon(FluentIcons.alert_24_regular),
                    title: const Text('הפעל התראות על אירועים',
                        style: kSettingsTitleStyle),
                    value: state.calendarNotificationsEnabled,
                    onChanged: (value) {
                      context
                          .read<CalendarCubit>()
                          .changeCalendarNotificationsEnabled(value);
                    },
                  ),
                  if (state.calendarNotificationsEnabled) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 16.0, left: 16.0),
                      child: SwitchSettingsTile(
                        title: const Text('השמע צליל בהתראה',
                            style: kSettingsTitleStyle),
                        value: state.calendarNotificationSound,
                        onChanged: (value) {
                          context
                              .read<CalendarCubit>()
                              .changeCalendarNotificationSound(value);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: AppDropdownField<int>(
                        value: state.calendarNotificationTime,
                        decoration: const InputDecoration(
                          labelText: 'זמן תזכורת לפני האירוע',
                          border: OutlineInputBorder(),
                        ),
                        entries: const [
                          AppMenuEntry(value: 60, label: 'שעה'),
                          AppMenuEntry(value: 720, label: '12 שעות'),
                          AppMenuEntry(value: 1440, label: 'יום'),
                          AppMenuEntry(value: 2880, label: 'יומיים'),
                        ],
                        onSelected: (value) {
                          if (value != null) {
                            context
                                .read<CalendarCubit>()
                                .changeCalendarNotificationTime(value);
                          }
                        },
                      ),
                    ),
                  ],

                  // ── לוח שנה גוגל ──
                  SwitchSettingsTile(
                    leading: const Icon(FluentIcons.arrow_sync_24_regular),
                    title: const Text('לוח שנה של Google',
                        style: kSettingsTitleStyle),
                    subtitle: Text(
                        isOfflineMode
                            ? 'מושבת במצב מנותק'
                            : 'סנכרון אירועים עם Google Calendar',
                        style: kSettingsSubtitleStyle),
                    value: state.googleCalendarEnabled,
                    enabled: !isOfflineMode,
                    onChanged: (value) {
                      context
                          .read<CalendarCubit>()
                          .setGoogleCalendarEnabled(value);
                    },
                  ),

                  if (state.googleCalendarEnabled && !isOfflineMode) ...[
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // כפתור "התחברות לחשבון" / מצב מחובר
                          if (!state.googleCalendarConnected) ...[
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: state.googleCalendarSyncInProgress
                                    ? null
                                    : () async {
                                        final cubit =
                                            context.read<CalendarCubit>();
                                        final success =
                                            await cubit.connectGoogleCalendar();
                                        if (!context.mounted) return;
                                        if (success) {
                                          final calendars = await cubit
                                              .getAvailableCalendars();
                                          if (!context.mounted) return;
                                          final selected =
                                              await showMultiSelectionDialog<
                                                  String>(
                                            context: context,
                                            title: 'בחר לוחות שנה',
                                            items: calendars
                                                .map((cal) =>
                                                    MultiSelectionItem<String>(
                                                      label: cal.name,
                                                      value: cal.id,
                                                      subtitle: cal.isPrimary
                                                          ? 'לוח שנה ראשי'
                                                          : null,
                                                    ))
                                                .toList(),
                                            initialSelectedValues:
                                                state.googleCalendarSelectedIds,
                                            searchHint: 'חפש לוח שנה...',
                                            emptyMessage: 'לא נמצאו לוחות שנה',
                                          );
                                          if (selected != null &&
                                              selected.isNotEmpty) {
                                            cubit
                                                .updateGoogleCalendarSelectedIds(
                                                    selected);
                                          }
                                        }
                                      },
                                icon: state.googleCalendarSyncInProgress
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(
                                        FluentIcons.person_accounts_24_regular,
                                        size: 18),
                                label: const Text('התחברות לחשבון'),
                              ),
                            ),
                          ] else ...[
                            // מחובר — הצג אפשרויות
                            Row(
                              children: [
                                Expanded(
                                  child: NeutralActionButton(
                                    text:
                                        'לוחות שנה (${state.googleCalendarSelectedIds.length})',
                                    icon: FluentIcons.calendar_24_regular,
                                    onPressed: () async {
                                      final cubit =
                                          context.read<CalendarCubit>();
                                      final calendars =
                                          await cubit.getAvailableCalendars();
                                      if (!context.mounted) return;
                                      if (calendars.isEmpty) {
                                        UiSnack.show(
                                            'לא נמצאו לוחות שנה. נסה להתחבר מחדש.');
                                        return;
                                      }
                                      final selected =
                                          await showMultiSelectionDialog<
                                              String>(
                                        context: context,
                                        title: 'בחר לוחות שנה',
                                        items: calendars
                                            .map((cal) =>
                                                MultiSelectionItem<String>(
                                                  label: cal.name,
                                                  value: cal.id,
                                                  subtitle: cal.isPrimary
                                                      ? 'לוח שנה ראשי'
                                                      : null,
                                                ))
                                            .toList(),
                                        initialSelectedValues:
                                            state.googleCalendarSelectedIds,
                                        searchHint: 'חפש לוח שנה...',
                                        emptyMessage: 'לא נמצאו לוחות שנה',
                                      );
                                      if (selected != null &&
                                          selected.isNotEmpty) {
                                        cubit.updateGoogleCalendarSelectedIds(
                                            selected);
                                        cubit.syncGoogleCalendar(
                                            interactive: false);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                RecommendedActionButton(
                                  text: 'סנכרן',
                                  icon: FluentIcons.arrow_sync_24_regular,
                                  isLoading: state.googleCalendarSyncInProgress,
                                  onPressed: () => context
                                      .read<CalendarCubit>()
                                      .syncGoogleCalendar(interactive: true),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () => context
                                      .read<CalendarCubit>()
                                      .disconnectGoogleCalendar(),
                                  child: const Text('התנתק'),
                                ),
                              ],
                            ),
                          ],

                          // מידע נוסף
                          if (state.googleCalendarLastSync != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                'סנכרון אחרון: ${state.googleCalendarLastSync}',
                                style: TextStyle(
                                  fontSize: AppTokens.fontSM,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          if (state.googleCalendarSyncError != null &&
                              state.googleCalendarSyncError!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                state.googleCalendarSyncError!,
                                style: TextStyle(
                                  fontSize: AppTokens.fontSM,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Widget לחיפוש ובחירת עיר
class _CitySearchWidget extends StatefulWidget {
  final String currentCity;
  final ValueChanged<String> onCitySelected;

  const _CitySearchWidget({
    required this.currentCity,
    required this.onCitySelected,
  });

  @override
  State<_CitySearchWidget> createState() => _CitySearchWidgetState();
}

class _CitySearchWidgetState extends State<_CitySearchWidget> {
  final TextEditingController _searchController = TextEditingController();
  late Map<String, Map<String, Map<String, dynamic>>> _filteredCities;

  @override
  void initState() {
    super.initState();
    _filteredCities = cityCoordinates;
    _searchController.addListener(_filterCities);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterCities);
    _searchController.dispose();
    super.dispose();
  }

  void _filterCities() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCities = cityCoordinates;
      } else {
        _filteredCities = {};
        cityCoordinates.forEach((country, cities) {
          final matchingCities = Map.fromEntries(cities.entries.where(
              (cityEntry) => cityEntry.key.toLowerCase().contains(query)));
          if (matchingCities.isNotEmpty) {
            _filteredCities[country] = matchingCities;
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = [];
    _filteredCities.forEach((country, cities) {
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: Text(
            country,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
              fontSize: AppTokens.fontLG,
            ),
          ),
        ),
      );
      cities.forEach((city, data) {
        items.add(
          ListTile(
            title: Text(city),
            onTap: () => widget.onCitySelected(city),
            dense: true,
          ),
        );
      });
      items.add(const Divider());
    });
    if (items.isNotEmpty) items.removeLast();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppTokens.radiusSM),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: OtzariaSearchField(
              controller: _searchController,
              hintText: 'הקלד שם עיר...',
              autofocus: true,
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 300,
            child: _filteredCities.isEmpty
                ? const Center(child: Text('לא נמצאו ערים'))
                : ListView(children: items),
          ),
        ],
      ),
    );
  }
}
