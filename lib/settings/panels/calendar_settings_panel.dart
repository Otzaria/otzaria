import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/search/settings_anchor.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/settings/settings_card.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

/// טאב הגדרות לוח שנה
class CalendarSettingsTab extends StatefulWidget {
  const CalendarSettingsTab({super.key});

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'tools.calendar.location',
      title: 'מיקום',
      subtitle: 'מיקום עבור חישובי לוח השנה',
      tab: SettingsTab.tools,
      cardId: 'tools.calendar',
      keywords: ['לוח שנה', 'זמנים', 'מיקום גיאוגרפי'],
    ),
    SettingsSearchEntry(
      id: 'tools.calendar.times',
      title: 'הצגת זמנים',
      subtitle: 'אילו זמנים יוצגו בלוח השנה',
      tab: SettingsTab.tools,
      cardId: 'tools.calendar',
      keywords: ['לוח שנה', 'זמנים'],
    ),
    SettingsSearchEntry(
      id: 'tools.calendar.candle_minutes',
      title: 'דקות הדלקת נרות',
      subtitle: 'מספר דקות לפני שקיעה להדלקת נרות',
      tab: SettingsTab.tools,
      cardId: 'tools.calendar',
      keywords: ['שבת', 'נרות'],
    ),
  ];

  @override
  State<CalendarSettingsTab> createState() => _CalendarSettingsTabState();
}

class _CalendarSettingsTabState extends State<CalendarSettingsTab> {
  final List<String> _cityNames =
      cityCoordinates.values.expand((cities) => cities.keys).toList()..sort();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CalendarCubit, CalendarState>(
      builder: (context, state) {
        final isOfflineMode = context.watch<SettingsBloc>().state.isOfflineMode;
        // [הוסר] SingleChildScrollView — ToolsSettingsTab גולל את כולם
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── לוח שנה: סוג לוח + עיר באותו מקטע ──
            SettingsAnchor(
              cardId: 'tools.calendar',
              child: SettingsCard(
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
                    SegmentOption(value: CalendarType.combined, label: 'משולב'),
                    SegmentOption(
                        value: CalendarType.gregorian, label: 'לועזי'),
                  ],
                  currentValue: state.calendarType,
                  onChanged: (value) {
                    context.read<CalendarCubit>().changeCalendarType(value);
                  },
                ),
                SegmentedSettingsTile<CalendarDayTransition>(
                  icon: FluentIcons.weather_sunny_low_24_regular,
                  title: 'מעבר יום',
                  subtitle: _calendarDayTransitionSubtitle(state.dayTransition),
                  options: const [
                    SegmentOption(
                      value: CalendarDayTransition.sunset,
                      label: 'שקיעה',
                    ),
                    SegmentOption(
                      value: CalendarDayTransition.tzais,
                      label: 'צאה"כ',
                    ),
                    SegmentOption(
                      value: CalendarDayTransition.rabbeinuTam,
                      label: 'רבינו תם',
                    ),
                    SegmentOption(
                      value: CalendarDayTransition.midnight,
                      label: '12 בלילה',
                    ),
                  ],
                  currentValue: state.dayTransition,
                  onChanged: (value) {
                    context
                        .read<CalendarCubit>()
                        .changeCalendarDayTransition(value);
                  },
                ),
                // עיר
                _buildResponsiveDropdownTile<String>(
                  icon: FluentIcons.location_24_regular,
                  title: 'עיר נבחרת',
                  subtitle: 'בחירת עיר לחישובי זמני היום והלוח',
                  value: state.selectedCity,
                  minFieldWidth: 220,
                  maxFieldWidth: 320,
                  enableSearch: true,
                  entries: _cityNames
                      .map(
                        (city) =>
                            AppMenuEntry<String>(value: city, label: city),
                      )
                      .toList(),
                  onSelected: (city) {
                    if (city == null || city == state.selectedCity) return;
                    context.read<CalendarCubit>().changeCity(city);
                  },
                ),
              ],
              ),
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
                  _buildResponsiveDropdownTile<int>(
                    icon: FluentIcons.alert_snooze_24_regular,
                    title: 'זמן תזכורת לפני האירוע',
                    subtitle: 'כמה זמן לפני תחילת האירוע תופיע התראה',
                    value: state.calendarNotificationTime,
                    minFieldWidth: 180,
                    maxFieldWidth: 240,
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
                            child: RecommendedActionButton(
                              text: 'התחברות לחשבון',
                              icon: FluentIcons.person_accounts_24_regular,
                              isLoading: state.googleCalendarSyncInProgress,
                              onPressed: () async {
                                final cubit = context.read<CalendarCubit>();
                                final success =
                                    await cubit.connectGoogleCalendar();
                                if (!context.mounted) return;
                                if (success) {
                                  final calendars =
                                      await cubit.getAvailableCalendars();
                                  if (!context.mounted) return;
                                  final selected =
                                      await _showCalendarMultiSelectionDialog<
                                          String>(
                                    context: context,
                                    title: 'בחר לוחות שנה',
                                    items: calendars
                                        .map((cal) =>
                                            _CalendarMultiSelectionItem<String>(
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
                                    cubit.updateGoogleCalendarSelectedIds(
                                        selected);
                                  }
                                }
                              },
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
                                    final cubit = context.read<CalendarCubit>();
                                    final calendars =
                                        await cubit.getAvailableCalendars();
                                    if (!context.mounted) return;
                                    if (calendars.isEmpty) {
                                      UiSnack.show(
                                          'לא נמצאו לוחות שנה. נסה להתחבר מחדש.');
                                      return;
                                    }
                                    final selected =
                                        await _showCalendarMultiSelectionDialog<
                                            String>(
                                      context: context,
                                      title: 'בחר לוחות שנה',
                                      items: calendars
                                          .map((cal) =>
                                              _CalendarMultiSelectionItem<
                                                  String>(
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
                              NeutralActionButton(
                                text: 'התנתק',
                                onPressed: () => context
                                    .read<CalendarCubit>()
                                    .disconnectGoogleCalendar(),
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
        );
      },
    );
  }

  Widget _buildResponsiveDropdownTile<T>({
    required IconData icon,
    required String title,
    required String subtitle,
    required T? value,
    required List<AppMenuEntry<T>> entries,
    required ValueChanged<T?> onSelected,
    bool enableSearch = false,
    double minFieldWidth = 220,
    double maxFieldWidth = 320,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 620;
          final fieldWidth = isCompact
              ? constraints.maxWidth
              : constraints.maxWidth.clamp(minFieldWidth, maxFieldWidth);

          final info = Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: kSettingsTitleStyle),
                      const SizedBox(height: 4),
                      Text(subtitle, style: kSettingsSubtitleStyle),
                    ],
                  ),
                ),
              ],
            ),
          );

          final field = SizedBox(
            width: fieldWidth,
            child: AppDropdownField<T>(
              value: value,
              enableSearch: enableSearch,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              entries: entries,
              onSelected: onSelected,
            ),
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [info]),
                const SizedBox(height: 12),
                field,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              info,
              const SizedBox(width: 16),
              Flexible(
                  child: Align(alignment: Alignment.centerLeft, child: field)),
            ],
          );
        },
      ),
    );
  }
}

String _calendarDayTransitionSubtitle(CalendarDayTransition transition) {
  switch (transition) {
    case CalendarDayTransition.sunset:
      return 'היום בלוח יתחלף בזמן השקיעה של העיר הנבחרת';
    case CalendarDayTransition.tzais:
      return 'היום בלוח יתחלף בצאת הכוכבים של העיר הנבחרת';
    case CalendarDayTransition.rabbeinuTam:
      return 'היום בלוח יתחלף בצאת הכוכבים לרבינו תם';
    case CalendarDayTransition.midnight:
      return 'היום בלוח יתחלף בשעה 12 בלילה';
  }
}

Future<List<T>?> _showCalendarMultiSelectionDialog<T>({
  required BuildContext context,
  required String title,
  required List<_CalendarMultiSelectionItem<T>> items,
  List<T> initialSelectedValues = const [],
  String searchHint = 'חיפוש...',
  String? emptyMessage,
  bool barrierDismissible = true,
}) {
  return showDialog<List<T>>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => _CalendarMultiSelectionDialog<T>(
      title: title,
      items: items,
      initialSelectedValues: initialSelectedValues,
      searchHint: searchHint,
      emptyMessage: emptyMessage,
    ),
  );
}

class _CalendarMultiSelectionDialog<T> extends StatefulWidget {
  final String title;
  final List<_CalendarMultiSelectionItem<T>> items;
  final List<T> initialSelectedValues;
  final String searchHint;
  final String? emptyMessage;

  const _CalendarMultiSelectionDialog({
    required this.title,
    required this.items,
    this.initialSelectedValues = const [],
    this.searchHint = 'חיפוש...',
    this.emptyMessage,
  });

  @override
  State<_CalendarMultiSelectionDialog<T>> createState() =>
      _CalendarMultiSelectionDialogState<T>();
}

class _CalendarMultiSelectionDialogState<T>
    extends State<_CalendarMultiSelectionDialog<T>> {
  late List<_CalendarMultiSelectionItem<T>> filteredItems;
  late Set<T> selectedValues;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    filteredItems = widget.items;
    selectedValues = Set.from(widget.initialSelectedValues);
    _searchController.addListener(_filterItems);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterItems() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        filteredItems = widget.items;
      } else {
        filteredItems = widget.items.where((item) {
          return item.label.toLowerCase().contains(query) ||
              item.searchValue.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      backgroundColor: cs.surfaceContainerHigh,
      title: Text(widget.title, textDirection: TextDirection.rtl),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            OtzariaSearchField(
              controller: _searchController,
              hintText: widget.searchHint,
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: widget.items.isEmpty
                  ? Center(
                      child: Text(
                        widget.emptyMessage ?? 'לא נמצאו פריטים',
                        style: TextStyle(color: cs.onSurfaceVariant),
                        textDirection: TextDirection.rtl,
                      ),
                    )
                  : filteredItems.isEmpty
                      ? const Center(
                          child: Text(
                            'לא נמצאו תוצאות',
                            textDirection: TextDirection.rtl,
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = filteredItems[index];
                            final isSelected =
                                selectedValues.contains(item.value);

                            return CheckboxListTile(
                              title: Text(
                                item.label,
                                textDirection: TextDirection.rtl,
                              ),
                              subtitle: item.subtitle != null
                                  ? Text(
                                      item.subtitle!,
                                      textDirection: TextDirection.rtl,
                                    )
                                  : null,
                              value: isSelected,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    selectedValues.add(item.value);
                                  } else {
                                    selectedValues.remove(item.value);
                                  }
                                });
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        NeutralActionButton(
          text: 'ביטול',
          onPressed: () => Navigator.of(context).pop(),
        ),
        RecommendedActionButton(
          text: 'אישור',
          onPressed: selectedValues.isEmpty
              ? () {}
              : () => Navigator.of(context).pop(selectedValues.toList()),
          isLoading: false,
        ),
      ],
    );
  }
}

class _CalendarMultiSelectionItem<T> {
  final String label;
  final String searchValue;
  final T value;
  final String? subtitle;

  const _CalendarMultiSelectionItem({
    required this.label,
    required this.value,
    String? searchValue,
    this.subtitle,
  }) : searchValue = searchValue ?? label;
}
