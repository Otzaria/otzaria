import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/navigation/calendar_cubit.dart';
import 'package:otzaria/settings/settings_repository.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:otzaria/widgets/dialogs.dart';

/// פונקציה גלובלית להצגת דיאלוג הגדרות לוח שנה
/// ניתן לקרוא לה מכל מקום באפליקציה
void showCalendarSettingsDialog(BuildContext context,
    {CalendarCubit? calendarCubit}) {
  // אם נמסר Cubit במפורש נשתמש בו, אחרת ננסה לקרוא מה-context
  CalendarCubit? existingCubit = calendarCubit;
  bool shouldCloseAfter = false;

  if (existingCubit == null) {
    try {
      existingCubit = context.read<CalendarCubit>();
    } catch (e) {
      // אם אין CalendarCubit זמין, ניצור חדש
      final settingsRepository = SettingsRepository();
      existingCubit = CalendarCubit(settingsRepository: settingsRepository);
      shouldCloseAfter = true;
    }
  }

  final cubit = existingCubit;

  showDialog(
    context: context,
    builder: (dialogContext) {
      return BlocProvider.value(
        value: cubit,
        child: _CalendarSettingsDialog(calendarCubit: cubit),
      );
    },
  ).then((_) {
    if (shouldCloseAfter) {
      cubit.close();
    }
  });
}

/// דיאלוג הגדרות לוח שנה עם אפשרות להרחבה לבחירת עיר
class _CalendarSettingsDialog extends StatefulWidget {
  final CalendarCubit calendarCubit;

  const _CalendarSettingsDialog({required this.calendarCubit});

  @override
  State<_CalendarSettingsDialog> createState() =>
      _CalendarSettingsDialogState();
}

class _CalendarSettingsDialogState extends State<_CalendarSettingsDialog> {
  bool _showCitySearch = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalendarCubit, CalendarState>(
      bloc: widget.calendarCubit,
      builder: (context, state) {
        return AlertDialog(
          title: const Text('הגדרות לוח שנה'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'סוג לוח:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  RadioGroup<CalendarType>(
                    groupValue: state.calendarType,
                    onChanged: (value) {
                      if (value != null) {
                        widget.calendarCubit.changeCalendarType(value);
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        RadioListTile<CalendarType>(
                          title: Text('לוח עברי'),
                          value: CalendarType.hebrew,
                        ),
                        RadioListTile<CalendarType>(
                          title: Text('לוח לועזי'),
                          value: CalendarType.gregorian,
                        ),
                        RadioListTile<CalendarType>(
                          title: Text('לוח משולב'),
                          value: CalendarType.combined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'עיר:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _showCitySearch = !_showCitySearch;
                          });
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(state.selectedCity),
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
                    ],
                  ),
                  // הרחבה לחיפוש עיר
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: _showCitySearch
                        ? Column(
                            children: [
                              const SizedBox(height: 16),
                              _CitySearchWidget(
                                currentCity: state.selectedCity,
                                onCitySelected: (city) {
                                  widget.calendarCubit.changeCity(city);
                                  setState(() {
                                    _showCitySearch = false;
                                  });
                                },
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'התראות:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SwitchListTile(
                    title: const Text('הפעל התראות על אירועים'),
                    value: state.calendarNotificationsEnabled,
                    onChanged: (value) {
                      widget.calendarCubit
                          .changeCalendarNotificationsEnabled(value);
                    },
                  ),
                  if (state.calendarNotificationsEnabled)
                    Padding(
                      padding: const EdgeInsets.only(right: 16.0, left: 16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SwitchListTile(
                            title: const Text('השמע צליל בהתראה'),
                            value: state.calendarNotificationSound,
                            onChanged: (value) {
                              widget.calendarCubit
                                  .changeCalendarNotificationSound(value);
                            },
                          ),
                          DropdownButtonFormField<int>(
                            decoration: const InputDecoration(
                              labelText: 'זמן תזכורת לפני האירוע',
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
                                widget.calendarCubit
                                    .changeCalendarNotificationTime(value);
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final notificationService =
                                  widget.calendarCubit.notificationService;
                              await notificationService.sendTestNotification();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('התראת בדיקה נשלחה'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(FluentIcons.alert_24_regular),
                            label: const Text('שלח התראת בדיקה'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Google Calendar:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SwitchListTile(
                    title: const Text('הפעל סנכרון עם Google Calendar'),
                    value: state.googleCalendarEnabled,
                    onChanged: (value) {
                      widget.calendarCubit.setGoogleCalendarEnabled(value);
                    },
                  ),
                  if (state.googleCalendarEnabled) ...[
                    ElevatedButton.icon(
                      onPressed: state.googleCalendarConnected
                          ? () async {
                              final calendars = await widget.calendarCubit
                                  .getAvailableCalendars();
                              if (!context.mounted) return;

                              if (calendars.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'לא נמצאו לוחות שנה. נסה להתחבר מחדש.'),
                                  ),
                                );
                                return;
                              }

                              final selected =
                                  await showMultiSelectionDialog<String>(
                                context: context,
                                title: 'בחר לוחות שנה',
                                items: calendars
                                    .map((cal) => MultiSelectionItem<String>(
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

                              if (selected != null && selected.isNotEmpty) {
                                widget.calendarCubit
                                    .updateGoogleCalendarSelectedIds(selected);
                                widget.calendarCubit
                                    .syncGoogleCalendar(interactive: false);
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
                                    widget.calendarCubit
                                        .syncGoogleCalendar(interactive: true);
                                  } else {
                                    // Connect and wait for completion
                                    final success = await widget.calendarCubit
                                        .connectGoogleCalendar();
                                    if (!context.mounted) return;

                                    if (success) {
                                      // Connection successful, show calendar selection
                                      final calendars = await widget
                                          .calendarCubit
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
                                        widget.calendarCubit
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
                                widget.calendarCubit.disconnectGoogleCalendar(),
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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
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
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('סגור'),
            ),
          ],
        );
      },
    );
  }
}

/// Widget לחיפוש ובחירת עיר (מוטמע בתוך הדיאלוג)
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
            onTap: () {
              widget.onCitySelected(city);
            },
            dense: true,
          ),
        );
      });
      items.add(const Divider());
    });
    if (items.isNotEmpty) {
      items.removeLast(); // Remove last divider
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
