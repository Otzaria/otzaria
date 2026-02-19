import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/navigation/calendar_cubit.dart';
import 'package:otzaria/settings/settings_repository.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:otzaria/widgets/dialogs.dart';
import 'package:otzaria/settings/settings_card.dart';

/// טאב הגדרות לוח שנה
class CalendarSettingsTab extends StatefulWidget {
  const CalendarSettingsTab({super.key});

  @override
  State<CalendarSettingsTab> createState() => _CalendarSettingsTabState();
}

class _CalendarSettingsTabState extends State<CalendarSettingsTab> {
  CalendarCubit? _localCubit;
  bool _isCubitLocal = false;
  bool _showCitySearch = false;

  @override
  void initState() {
    super.initState();
    _initCubit();
  }

  void _initCubit() {
    try {
      // ננסה לקרוא מה-context
      _localCubit = context.read<CalendarCubit>();
    } catch (e) {
      // אם אין CalendarCubit זמין, ניצור חדש
      final settingsRepository = SettingsRepository();
      _localCubit = CalendarCubit(settingsRepository: settingsRepository);
      _isCubitLocal = true;
    }
  }

  @override
  void dispose() {
    // נסגור רק אם יצרנו את ה-cubit בעצמנו
    if (_isCubitLocal) {
      _localCubit?.close();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ננסה לקבל את ה-cubit מה-context, אם לא קיים נשתמש בלוקלי
    CalendarCubit cubit;
    try {
      cubit = context.read<CalendarCubit>();
    } catch (e) {
      cubit = _localCubit!;
    }

    return BlocProvider.value(
      value: cubit,
      child: BlocBuilder<CalendarCubit, CalendarState>(
        builder: (context, state) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // סוג לוח
                SettingsCard(
                  title: 'סוג לוח',
                  children: [
                    RadioGroup<CalendarType>(
                      groupValue: state.calendarType,
                      onChanged: (value) {
                        if (value != null) {
                          cubit.changeCalendarType(value);
                        }
                      },
                      child: Column(
                        children: [
                          RadioListTile<CalendarType>(
                            title: const Text('לוח עברי',
                                style: TextStyle(fontSize: 16)),
                            value: CalendarType.hebrew,
                          ),
                          RadioListTile<CalendarType>(
                            title: const Text('לוח לועזי',
                                style: TextStyle(fontSize: 16)),
                            value: CalendarType.gregorian,
                          ),
                          RadioListTile<CalendarType>(
                            title: const Text('לוח משולב',
                                style: TextStyle(fontSize: 16)),
                            value: CalendarType.combined,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // בחירת עיר
                SettingsCard(
                  title: 'עיר',
                  children: [
                    ListTile(
                      leading: const Icon(FluentIcons.location_24_regular),
                      title: const Text('עיר נבחרת',
                          style: TextStyle(fontSize: 16)),
                      subtitle: Text(state.selectedCity,
                          style: const TextStyle(fontSize: 13)),
                      trailing: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _showCitySearch = !_showCitySearch;
                          });
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('שנה'),
                            const SizedBox(width: 8),
                            Icon(
                              _showCitySearch
                                  ? FluentIcons.chevron_up_24_regular
                                  : FluentIcons.chevron_down_24_regular,
                              size: 20,
                            ),
                          ],
                        ),
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
                                  cubit.changeCity(city);
                                  setState(() {
                                    _showCitySearch = false;
                                  });
                                },
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // התראות
                SettingsCard(
                  title: 'התראות',
                  children: [
                    SwitchListTile(
                      secondary: const Icon(FluentIcons.alert_24_regular),
                      title: const Text('הפעל התראות על אירועים',
                          style: TextStyle(fontSize: 16)),
                      value: state.calendarNotificationsEnabled,
                      onChanged: (value) {
                        cubit.changeCalendarNotificationsEnabled(value);
                      },
                    ),
                    if (state.calendarNotificationsEnabled) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.only(right: 16.0, left: 16.0),
                        child: SwitchListTile(
                          title: const Text('השמע צליל בהתראה',
                              style: TextStyle(fontSize: 16)),
                          value: state.calendarNotificationSound,
                          onChanged: (value) {
                            cubit.changeCalendarNotificationSound(value);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: DropdownButtonFormField<int>(
                          decoration: const InputDecoration(
                            labelText: 'זמן תזכורת לפני האירוע',
                            border: OutlineInputBorder(),
                          ),
                          initialValue: state.calendarNotificationTime,
                          items: const [
                            DropdownMenuItem(value: 60, child: Text('שעה')),
                            DropdownMenuItem(
                                value: 720, child: Text('12 שעות')),
                            DropdownMenuItem(value: 1440, child: Text('יום')),
                            DropdownMenuItem(
                                value: 2880, child: Text('יומיים')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              cubit.changeCalendarNotificationTime(value);
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 16),

                SettingsCard(
                  title: 'Google Calendar',
                  children: [
                    SwitchListTile(
                      secondary: const Icon(FluentIcons.arrow_sync_24_regular),
                      title: const Text('הפעל סנכרון עם Google Calendar',
                          style: TextStyle(fontSize: 16)),
                      value: state.googleCalendarEnabled,
                      onChanged: (value) {
                        cubit.setGoogleCalendarEnabled(value);
                      },
                    ),
                    if (state.googleCalendarEnabled) ...[
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            ElevatedButton.icon(
                              onPressed: state.googleCalendarConnected
                                  ? () async {
                                      final calendars =
                                          await cubit.getAvailableCalendars();
                                      if (!context.mounted) return;

                                      if (calendars.isEmpty) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'לא נמצאו לוחות שנה. נסה להתחבר מחדש.'),
                                          ),
                                        );
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
                                    }
                                  : null,
                              icon: const Icon(FluentIcons.calendar_24_regular),
                              label: Text(
                                  'בחר לוחות שנה (${state.googleCalendarSelectedIds.length})'),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  onPressed: state.googleCalendarSyncInProgress
                                      ? null
                                      : () async {
                                          if (state.googleCalendarConnected) {
                                            cubit.syncGoogleCalendar(
                                                interactive: true);
                                          } else {
                                            // Connect and wait for completion
                                            final success = await cubit
                                                .connectGoogleCalendar();
                                            if (!context.mounted) return;

                                            if (success) {
                                              // Connection successful, show calendar selection
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
                                                        MultiSelectionItem<
                                                            String>(
                                                          label: cal.name,
                                                          value: cal.id,
                                                          subtitle: cal
                                                                  .isPrimary
                                                              ? 'לוח שנה ראשי'
                                                              : null,
                                                        ))
                                                    .toList(),
                                                initialSelectedValues: state
                                                    .googleCalendarSelectedIds,
                                                searchHint: 'חפש לוח שנה...',
                                                emptyMessage:
                                                    'לא נמצאו לוחות שנה',
                                              );
                                              if (selected != null &&
                                                  selected.isNotEmpty) {
                                                cubit
                                                    .updateGoogleCalendarSelectedIds(
                                                        selected);
                                              }
                                            }
                                          }
                                        },
                                  icon: state.googleCalendarSyncInProgress
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          FluentIcons.arrow_sync_24_regular,
                                          size: 16,
                                        ),
                                  label: Text(state.googleCalendarConnected
                                      ? 'סנכרן עכשיו'
                                      : 'התחבר ל-Google'),
                                ),
                                const SizedBox(width: 8),
                                if (state.googleCalendarConnected)
                                  TextButton(
                                    onPressed: () =>
                                        cubit.disconnectGoogleCalendar(),
                                    child: const Text('התנתק'),
                                  ),
                              ],
                            ),
                            if (state.googleCalendarLastSync != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  'סנכרון אחרון: ${state.googleCalendarLastSync}',
                                  style: TextStyle(
                                    fontSize: 12,
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
                                    fontSize: 12,
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
      ),
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
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
              fontSize: 16,
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
    if (items.isNotEmpty) {
      items.removeLast();
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: RtlTextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'הקלד שם עיר...',
                prefixIcon: Icon(FluentIcons.search_24_regular),
                border: OutlineInputBorder(),
                isDense: true,
              ),
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
