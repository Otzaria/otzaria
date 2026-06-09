import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// תוצאות דיאלוג האירוע בלוח השנה.
class CalendarEventDialogResult {
  final String title;
  final String description;
  final RecurrenceType recurrenceType;
  final int? recurringYears;
  final TimeOfDay? eventTime;

  const CalendarEventDialogResult({
    required this.title,
    required this.description,
    required this.recurrenceType,
    required this.recurringYears,
    required this.eventTime,
  });
}

/// דיאלוג יצירה/עריכה של אירוע לוח שנה.
class CalendarEventDialog extends StatefulWidget {
  final CalendarState state;
  final CustomEvent? existingEvent;
  final DateTime? specificDate;

  const CalendarEventDialog({
    super.key,
    required this.state,
    this.existingEvent,
    this.specificDate,
  });

  @override
  State<CalendarEventDialog> createState() => _CalendarEventDialogState();
}

class _CalendarEventDialogState extends State<CalendarEventDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _yearsController;
  late final DateTime _displayedGregorianDate;
  late final JewishDate _displayedJewishDate;

  late bool _isRecurring;
  late bool _recurForever;
  late RecurrenceType _selectedRecurrenceType;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    final existingEvent = widget.existingEvent;
    _titleController = TextEditingController(text: existingEvent?.title);
    _descriptionController =
        TextEditingController(text: existingEvent?.description);
    _yearsController = TextEditingController(
      text: existingEvent?.recurringYears?.toString() ?? '',
    );
    _isRecurring = (existingEvent?.recurrenceType ?? RecurrenceType.none) !=
        RecurrenceType.none;
    _selectedRecurrenceType = _isRecurring
        ? existingEvent!.recurrenceType
        : RecurrenceType.annualHebrew;
    _recurForever = existingEvent?.recurringYears == null;
    _selectedTime = existingEvent?.eventTime;
    _displayedGregorianDate = existingEvent != null
        ? existingEvent.baseGregorianDate
        : (widget.specificDate ?? widget.state.selectedGregorianDate);
    _displayedJewishDate = JewishDate.fromDateTime(_displayedGregorianDate);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _yearsController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_titleController.text.trim().isEmpty) {
      UiSnack.showError('יש למלא כותרת לאירוע.');
      return;
    }

    int? recurringYears;
    if (_isRecurring && !_recurForever) {
      recurringYears = int.tryParse(_yearsController.text.trim());
      if (recurringYears == null || recurringYears <= 0) {
        UiSnack.showError('יש להזין מספר שנים חיובי עבור אירוע חוזר.');
        return;
      }
    }

    Navigator.of(context).pop(
      CalendarEventDialogResult(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        recurrenceType:
            _isRecurring ? _selectedRecurrenceType : RecurrenceType.none,
        recurringYears: recurringYears,
        eventTime: _selectedTime,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.existingEvent != null;
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(isEditMode ? 'ערוך אירוע' : 'צור אירוע חדש'),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RtlTextField(
                  controller: _titleController,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'כותרת האירוע',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                RtlTextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'תיאור (אופציונלי)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppTokens.radiusMD),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'תאריך לועזי: ${_displayedGregorianDate.day}/${_displayedGregorianDate.month}/${_displayedGregorianDate.year}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        textDirection: TextDirection.rtl,
                      ),
                      Text(
                        'תאריך עברי: ${formatHebrewDay(_displayedJewishDate.getJewishDayOfMonth())} ${getHebrewMonthNameFor(_displayedJewishDate)} ${formatHebrewYear(_displayedJewishDate.getJewishYear())}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        textDirection: TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('שעת האירוע (אופציונלי)'),
                  subtitle: Text(
                    _selectedTime != null
                        ? 'שעה: ${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}'
                        : 'לא נבחרה שעה',
                    textDirection: TextDirection.rtl,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_selectedTime != null)
                        IconButton(
                          icon: const Icon(FluentIcons.dismiss_24_regular),
                          onPressed: () => setState(() => _selectedTime = null),
                          tooltip: 'נקה שעה',
                        ),
                      IconButton(
                        icon: const Icon(FluentIcons.clock_24_regular),
                        onPressed: () async {
                          final time = await showTimePicker(
                            context: context,
                            initialTime: _selectedTime ?? TimeOfDay.now(),
                            builder: (context, child) => Directionality(
                              textDirection: TextDirection.rtl,
                              child: child!,
                            ),
                          );
                          if (time != null) {
                            setState(() => _selectedTime = time);
                          }
                        },
                        tooltip: 'בחר שעה',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('אירוע חוזר'),
                  value: _isRecurring,
                  onChanged: (value) => setState(() => _isRecurring = value),
                ),
                if (_isRecurring) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      children: [
                        AppDropdownField<RecurrenceType>(
                          value: _selectedRecurrenceType,
                          decoration: const InputDecoration(
                            labelText: 'חזור לפי',
                            border: OutlineInputBorder(),
                          ),
                          entries: [
                            const AppMenuEntry(
                              value: RecurrenceType.weekly,
                              label: 'שבועי',
                            ),
                            AppMenuEntry(
                              value: RecurrenceType.monthlyHebrew,
                              label:
                                  'חודשי עברי (יום ${formatHebrewDay(_displayedJewishDate.getJewishDayOfMonth())})',
                            ),
                            AppMenuEntry(
                              value: RecurrenceType.monthlyGregorian,
                              label:
                                  'חודשי לועזי (יום ${_displayedGregorianDate.day})',
                            ),
                            AppMenuEntry(
                              value: RecurrenceType.annualHebrew,
                              label:
                                  'שנתי עברי (${formatHebrewDay(_displayedJewishDate.getJewishDayOfMonth())} ${getHebrewMonthNameFor(_displayedJewishDate)})',
                            ),
                            AppMenuEntry(
                              value: RecurrenceType.annualGregorian,
                              label:
                                  'שנתי לועזי (${_displayedGregorianDate.day}/${_displayedGregorianDate.month})',
                            ),
                          ],
                          onSelected: (value) => setState(() =>
                              _selectedRecurrenceType =
                                  value ?? RecurrenceType.annualHebrew),
                        ),
                        const SizedBox(height: 16),
                        CheckboxListTile(
                          title: const Text('חזרה ללא הגבלה (תמיד)'),
                          value: _recurForever,
                          onChanged: (value) {
                            setState(() {
                              _recurForever = value ?? true;
                              if (_recurForever) {
                                _yearsController.clear();
                              }
                            });
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 8),
                        RtlTextField(
                          controller: _yearsController,
                          keyboardType: TextInputType.number,
                          enabled: !_recurForever,
                          decoration: InputDecoration(
                            labelText: 'חזור למשך (שנים)',
                            hintText: 'לדוגמה: 5',
                            border: const OutlineInputBorder(),
                            filled: _recurForever,
                            fillColor: _recurForever
                                ? cs.onSurface.withValues(alpha: 0.08)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          NeutralActionButton(
            text: 'ביטול',
            onPressed: () => Navigator.of(context).pop(),
          ),
          RecommendedActionButton(
            text: isEditMode ? 'שמור שינויים' : 'צור',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

/// מציג את דיאלוג האירוע בלוח השנה.
Future<CalendarEventDialogResult?> showCalendarEventDialog({
  required BuildContext context,
  required CalendarState state,
  CustomEvent? existingEvent,
  DateTime? specificDate,
}) {
  return showDialog<CalendarEventDialogResult>(
    context: context,
    builder: (_) => CalendarEventDialog(
      state: state,
      existingEvent: existingEvent,
      specificDate: specificDate,
    ),
  );
}
