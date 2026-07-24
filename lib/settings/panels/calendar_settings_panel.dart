import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/tools/calendar/models/calendar_location.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
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
      keywords: [
        'לוח שנה',
        'זמנים',
        'מיקום גיאוגרפי',
        'עיר',
        'ירושלים',
        'תל אביב',
        'חיפה',
      ],
    ),
    SettingsSearchEntry(
      id: 'tools.calendar.type',
      title: 'סוג לוח שנה',
      subtitle: 'עברי / לועזי / משולב',
      tab: SettingsTab.tools,
      cardId: 'tools.calendar',
      keywords: ['לוח שנה', 'עברי', 'לועזי', 'גרגוריאני', 'משולב'],
    ),
    SettingsSearchEntry(
      id: 'tools.calendar.times',
      title: 'הצגת זמנים',
      subtitle: 'אילו זמנים יוצגו בלוח השנה',
      tab: SettingsTab.tools,
      cardId: 'tools.calendar',
      keywords: [
        'לוח שנה',
        'זמנים',
        'הנץ',
        'שקיעה',
        'מנחה',
        'מעריב',
        'שחרית',
      ],
    ),
    SettingsSearchEntry(
      id: 'tools.calendar.day_change',
      title: 'מעבר יום',
      subtitle: 'בחירת השעה בה מתחלף היום בלוח השנה',
      tab: SettingsTab.tools,
      cardId: 'tools.calendar',
      keywords: ['לוח שנה', 'מעבר יום', 'שקיעה', 'חצות', 'שעה'],
    ),
    SettingsSearchEntry(
      id: 'tools.calendar.candle_minutes',
      title: 'דקות הדלקת נרות',
      subtitle: 'מספר דקות לפני שקיעה להדלקת נרות',
      tab: SettingsTab.tools,
      cardId: 'tools.calendar',
      keywords: ['שבת', 'נרות', 'הדלקה', 'דקות'],
    ),
    SettingsSearchEntry(
      id: 'tools.calendar.notifications',
      title: 'מצב התראות על אירועים',
      subtitle: 'צליל / שקט / כבוי',
      tab: SettingsTab.tools,
      cardId: 'tools.calendar',
      keywords: [
        'לוח שנה',
        'התראות',
        'אירועים',
        'תזכורת',
        'צליל',
        'שקט',
        'כבוי',
        'מופעל',
        'לא מופעל',
      ],
    ),
    SettingsSearchEntry(
      id: 'tools.calendar.google_calendar',
      title: 'לוח שנה של Google',
      subtitle: 'סנכרן אירועים עם Google Calendar',
      tab: SettingsTab.tools,
      cardId: 'tools.calendar',
      keywords: [
        'google',
        'גוגל',
        'סנכרון',
        'אירועים',
        'מופעל',
        'לא מופעל',
      ],
    ),
  ];

  @override
  State<CalendarSettingsTab> createState() => _CalendarSettingsTabState();
}

class _CalendarSettingsTabState extends State<CalendarSettingsTab> {
  final List<String> _cityNames = getCalendarCityNames();

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
            SettingsCard(
              cardId: 'tools.calendar',
              title: 'לוח שנה',
              children: [
                // סוג לוח
                SettingsActionTile.segmentedTile<CalendarType>(
                  title: 'סוג לוח שנה',
                  options: const [
                    SegmentOption(
                      value: CalendarType.hebrew,
                      label: 'עברי',
                      icon: FluentIcons.calendar_rtl_24_regular,
                      subtitle: 'יוצג לוח השנה העברי בלבד',
                    ),
                    SegmentOption(
                      value: CalendarType.combined,
                      label: 'משולב',
                      icon: FluentIcons.calendar_multiple_24_regular,
                      subtitle: 'יוצגו תאריכים מהלוח העברי והלועזי יחד',
                    ),
                    SegmentOption(
                      value: CalendarType.gregorian,
                      label: 'לועזי',
                      icon: FluentIcons.calendar_ltr_24_regular,
                      subtitle: 'יוצג לוח השנה הלועזי בלבד',
                    ),
                  ],
                  currentValue: state.calendarType,
                  onChanged: (value) {
                    context.read<CalendarCubit>().changeCalendarType(value);
                  },
                ),
                SettingsActionTile.dropdownTile<CalendarDayTransition>(
                  icon: FluentIcons.weather_sunny_low_24_regular,
                  title: 'מעבר יום',
                  value: state.dayTransition,
                  entries: const [
                    AppMenuEntry(
                      value: CalendarDayTransition.sunset,
                      label: 'שקיעה',
                      subtitle: 'היום בלוח יתחלף בזמן השקיעה של העיר הנבחרת',
                    ),
                    AppMenuEntry(
                      value: CalendarDayTransition.tzais,
                      label: 'צאה"כ',
                      subtitle: 'היום בלוח יתחלף בצאת הכוכבים של העיר הנבחרת',
                    ),
                    AppMenuEntry(
                      value: CalendarDayTransition.rabbeinuTam,
                      label: 'רבינו תם',
                      subtitle: 'היום בלוח יתחלף בצאת הכוכבים לרבינו תם',
                    ),
                    AppMenuEntry(
                      value: CalendarDayTransition.midnight,
                      label: '12 בלילה',
                      subtitle: 'היום בלוח יתחלף בשעה 12 בלילה',
                    ),
                  ],
                  onSelected: (value) {
                    if (value != null) {
                      context.read<CalendarCubit>().changeCalendarDayTransition(
                        value,
                      );
                    }
                  },
                ),
                // עיר
                SettingsActionTile.dropdownTile<String>(
                  icon: FluentIcons.location_24_regular,
                  title: 'עיר נבחרת',
                  subtitle: 'בחירת עיר לחישובי זמני היום והלוח',
                  value: state.selectedCity,
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

            kSettingsCardSpacing,

            // ── אירועים ותזכורות: התראות + Google Calendar ──
            SettingsCard(
              title: 'אירועים ותזכורות',
              children: [
                SettingsActionTile.segmentedTile<CalendarNotificationMode>(
                  title: 'התראות',
                  options: const [
                    SegmentOption(
                      value: CalendarNotificationMode.sound,
                      label: 'צליל',
                      icon: FluentIcons.alert_urgent_24_regular,
                      subtitle: 'הצג התראות על המסך והשמע את צליל המערכת',
                    ),
                    SegmentOption(
                      value: CalendarNotificationMode.silent,
                      label: 'שקט',
                      icon: FluentIcons.alert_24_regular,
                      subtitle: 'הצג התראות על המסך ללא השמעת צליל',
                    ),
                    SegmentOption(
                      value: CalendarNotificationMode.off,
                      label: 'כבוי',
                      icon: FluentIcons.alert_off_24_regular,
                      subtitle: 'אל תציג התראות עבור אירועים בלוח השנה',
                    ),
                  ],
                  currentValue: state.notificationMode,
                  onChanged: (mode) {
                    context
                        .read<CalendarCubit>()
                        .changeCalendarNotificationMode(mode);
                  },
                ),

                // ── לוח שנה גוגל ──
                SettingsActionTile.switchTile(
                  icon: FluentIcons.calendar_sync_24_regular,
                  title: 'לוח שנה של Google',
                  subtitle: isOfflineMode
                      ? 'מושבת במצב מנותק'
                      : 'סנכרן אירועים עם Google Calendar',
                  value: state.googleCalendarEnabled,
                  enabled: !isOfflineMode,
                  onChanged: (value) {
                    context.read<CalendarCubit>().setGoogleCalendarEnabled(
                      value,
                    );
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
                            child: ActionButton.recommended(
                              text: 'התחברות לחשבון',
                              icon: FluentIcons.person_accounts_24_regular,
                              isLoading: state.googleCalendarSyncInProgress,
                              onPressed: () async {
                                final cubit = context.read<CalendarCubit>();
                                final success = await cubit
                                    .connectGoogleCalendar();
                                if (!context.mounted) return;
                                if (success) {
                                  final calendars = await cubit
                                      .getAvailableCalendars();
                                  if (!context.mounted) return;
                                  final selected =
                                      await _showCalendarMultiSelectionDialog<
                                        String
                                      >(
                                        context: context,
                                        title: 'בחר לוחות שנה',
                                        items: calendars
                                            .map(
                                              (cal) =>
                                                  _CalendarMultiSelectionItem<
                                                    String
                                                  >(
                                                    label: cal.name,
                                                    value: cal.id,
                                                    subtitle: cal.isPrimary
                                                        ? 'לוח שנה ראשי'
                                                        : null,
                                                  ),
                                            )
                                            .toList(),
                                        initialSelectedValues:
                                            state.googleCalendarSelectedIds,
                                        searchHint: 'חפש לוח שנה...',
                                        emptyMessage: 'לא נמצאו לוחות שנה',
                                      );
                                  if (selected != null && selected.isNotEmpty) {
                                    cubit.updateGoogleCalendarSelectedIds(
                                      selected,
                                    );
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
                                child: ActionButton.neutral(
                                  text:
                                      'לוחות שנה (${state.googleCalendarSelectedIds.length})',
                                  icon: FluentIcons.calendar_24_regular,
                                  onPressed: () async {
                                    final cubit = context.read<CalendarCubit>();
                                    final calendars = await cubit
                                        .getAvailableCalendars();
                                    if (!context.mounted) return;
                                    if (calendars.isEmpty) {
                                      UiSnack.show(
                                        SettingsMessages.noCalendarsFound,
                                      );
                                      return;
                                    }
                                    final selected =
                                        await _showCalendarMultiSelectionDialog<
                                          String
                                        >(
                                          context: context,
                                          title: 'בחר לוחות שנה',
                                          items: calendars
                                              .map(
                                                (cal) =>
                                                    _CalendarMultiSelectionItem<
                                                      String
                                                    >(
                                                      label: cal.name,
                                                      value: cal.id,
                                                      subtitle: cal.isPrimary
                                                          ? 'לוח שנה ראשי'
                                                          : null,
                                                    ),
                                              )
                                              .toList(),
                                          initialSelectedValues:
                                              state.googleCalendarSelectedIds,
                                          searchHint: 'חפש לוח שנה...',
                                          emptyMessage: 'לא נמצאו לוחות שנה',
                                        );
                                    if (selected != null &&
                                        selected.isNotEmpty) {
                                      cubit.updateGoogleCalendarSelectedIds(
                                        selected,
                                      );
                                      cubit.syncGoogleCalendar(
                                        interactive: false,
                                      );
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              ActionButton.recommended(
                                text: 'סנכרן',
                                icon: FluentIcons.arrow_sync_24_regular,
                                isLoading: state.googleCalendarSyncInProgress,
                                onPressed: () => context
                                    .read<CalendarCubit>()
                                    .syncGoogleCalendar(interactive: true),
                              ),
                              const SizedBox(width: 8),
                              ActionButton.neutral(
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
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
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
      title: Text(widget.title),
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
                      ),
                    )
                  : filteredItems.isEmpty
                  ? const Center(
                      child: Text(
                        'לא נמצאו תוצאות',
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        final isSelected = selectedValues.contains(item.value);

                        return CheckboxListTile(
                          title: Text(
                            item.label,
                          ),
                          subtitle: item.subtitle != null
                              ? Text(
                                  item.subtitle!,
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
        ActionButton.neutral(
          text: 'ביטול',
          onPressed: () => Navigator.of(context).pop(),
        ),
        ActionButton.recommended(
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
