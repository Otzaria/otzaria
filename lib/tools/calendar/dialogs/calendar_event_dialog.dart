import 'dart:io';
import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/tools/calendar/dialogs/jump_to_date_dialog.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_date_picker_panel.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/theme/calendar_event_colors.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  קבועים ופונקציות עזר
// ═══════════════════════════════════════════════════════════════════════════

const int _kCustomSentinel = -1;

// (דקות, תווית) — אפשרויות הבסיס
const List<(int, String)> _kBaseNotifOptions = [
  (0, 'בזמן האירוע'),
  (60, 'שעה לפני'),
  (120, 'שעתיים לפני'),
  (1440, 'יום לפני'),
  (10080, 'שבוע לפני'),
];

String _formatNotificationMinutes(int minutes) {
  if (minutes <= 0) return 'בזמן האירוע';
  if (minutes < 60) return '$minutes דקות';
  if (minutes < 1440) {
    final h = minutes ~/ 60;
    final rem = minutes % 60;
    return rem == 0 ? '$h שעות' : '$h שעות ו-$rem דקות';
  }
  if (minutes < 10080) return '${minutes ~/ 1440} ימים';
  return '${minutes ~/ 10080} שבועות';
}

String _notificationSubtitle(int minutes) {
  if (minutes == 0) return 'ההתראה תופיע בדיוק בזמן האירוע';
  final baseLabel = _kBaseNotifOptions
      .where((o) => o.$1 == minutes)
      .map((o) => o.$2)
      .firstOrNull;
  if (baseLabel != null) return 'ההתראה תופיע $baseLabel מועד האירוע';
  return 'ההתראה תופיע ${_formatNotificationMinutes(minutes)} לפני מועד האירוע';
}

int _toMinutes(int qty, String unit) => switch (unit) {
      'שעות' => qty * 60,
      'ימים' => qty * 1440,
      'שבועות' => qty * 10080,
      _ => qty, // דקות
    };

// ═══════════════════════════════════════════════════════════════════════════
//  CalendarEventDialogResult
// ═══════════════════════════════════════════════════════════════════════════

/// תוצאות דיאלוג האירוע בלוח השנה.
class CalendarEventDialogResult {
  final String title;
  final String description;
  final DateTime selectedDate;
  final RecurrenceType recurrenceType;
  final int? recurringYears;
  final TimeOfDay? eventTime;
  final int notificationMinutes;
  final DateTime? endGregorianDate;
  final int? colorIndex;

  const CalendarEventDialogResult({
    required this.title,
    required this.description,
    required this.selectedDate,
    required this.recurrenceType,
    required this.recurringYears,
    required this.eventTime,
    required this.notificationMinutes,
    required this.endGregorianDate,
    required this.colorIndex,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
//  CalendarEventDialog
// ═══════════════════════════════════════════════════════════════════════════

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
  // ── Controllers & FocusNodes ─────────────────────────────────────────────
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _yearsController;
  late final TextEditingController _dateController;
  late final FocusNode _dateFocusNode;

  // ── State ─────────────────────────────────────────────────────────────────
  late DateTime _selectedDate;
  late JewishDate _selectedJewishDate;
  // מצב הלוח (עברי/לועזי) בתפריט/דיאלוג בחירת התאריך
  late bool _dateShowHebrew;

  late bool _recurForever;
  late RecurrenceType _selectedRecurrenceType;
  TimeOfDay? _selectedTime;
  late int _notificationMinutes;
  // מונע דריסת ברירת מחדל חכמה כשהמשתמש בחר ידנית
  bool _userOverrodeNotification = false;
  DateTime? _selectedEndDate;
  int? _selectedColorIndex;

  @override
  void initState() {
    super.initState();
    final ev = widget.existingEvent;

    _titleController = TextEditingController(text: ev?.title);
    _descriptionController = TextEditingController(text: ev?.description);
    _yearsController = TextEditingController(
      text: ev?.recurringYears?.toString() ?? '',
    );

    _selectedDate = ev?.baseGregorianDate ??
        (widget.specificDate ?? widget.state.selectedGregorianDate);
    _selectedJewishDate = JewishDate.fromDateTime(_selectedDate);

    _selectedRecurrenceType = ev?.recurrenceType ?? RecurrenceType.none;
    _recurForever = ev?.recurringYears == null;
    _selectedTime = ev?.eventTime;
    _selectedEndDate = ev?.endGregorianDate;
    _selectedColorIndex = ev?.colorIndex;

    _dateShowHebrew = calendarDefaultShowHebrew(widget.state.calendarType);
    _dateController =
        TextEditingController(text: _formatPrimaryDate(_selectedDate));
    _dateFocusNode = FocusNode();

    _notificationMinutes = _smartDefaultNotification();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _yearsController.dispose();
    _dateController.dispose();
    _dateFocusNode.dispose();
    super.dispose();
  }

  // ── ברירת מחדל חכמה לזמן התראה ──────────────────────────────────────────

  int _smartDefaultNotification() {
    if (_selectedRecurrenceType != RecurrenceType.none) {
      return switch (_selectedRecurrenceType) {
        RecurrenceType.annualHebrew || RecurrenceType.annualGregorian => 1440,
        RecurrenceType.monthlyHebrew || RecurrenceType.monthlyGregorian => 60,
        _ => widget.state.calendarNotificationTime,
      };
    }
    final sixMonthsFromNow = DateTime.now().add(const Duration(days: 183));
    if (_selectedDate.isAfter(sixMonthsFromNow)) return 1440;
    return widget.state.calendarNotificationTime;
  }

  // ── כמה דקות עד האירוע (לסינון אפשרויות) ────────────────────────────────

  int _minutesUntilEvent() {
    // אירוע חוזר — תמיד יש מועדים עתידיים, אין צורך בסינון
    if (_selectedRecurrenceType != RecurrenceType.none) return 999999;
    final eventDateTime = _selectedTime != null
        ? DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            _selectedTime!.hour,
            _selectedTime!.minute,
          )
        : DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            23,
            59,
          );
    return eventDateTime.difference(DateTime.now()).inMinutes;
  }

  // ── תיאור מצב החזרה ───────────────────────────────────────────────────────

  String _recurrenceSubtitle(RecurrenceType type) {
    return switch (type) {
      RecurrenceType.none => 'אירוע חד-פעמי',
      RecurrenceType.weekly => 'חוזר כל שבוע',
      RecurrenceType.monthlyHebrew => 'חוזר כל חודש עברי',
      RecurrenceType.monthlyGregorian => 'חוזר כל חודש לועזי',
      RecurrenceType.annualHebrew => 'חוזר כל שנה עברית',
      RecurrenceType.annualGregorian => 'חוזר כל שנה לועזית',
    };
  }

  // ── בניית רשימת אפשרויות ההתראה ─────────────────────────────────────────

  List<AppMenuEntry<int>> _buildNotificationEntries() {
    final gapMinutes = _minutesUntilEvent();
    final entries = <AppMenuEntry<int>>[];
    var currentValueIncluded = false;

    for (final (value, label) in _kBaseNotifOptions) {
      if (gapMinutes > value) {
        entries.add(AppMenuEntry<int>(value: value, label: label));
        if (value == _notificationMinutes) currentValueIncluded = true;
      }
    }

    // תמיד כלול את הערך הנוכחי גם אם סונן
    if (!currentValueIncluded) {
      final baseLabel = _kBaseNotifOptions
          .where((o) => o.$1 == _notificationMinutes)
          .map((o) => o.$2)
          .firstOrNull;
      final label =
          baseLabel ?? _formatNotificationMinutes(_notificationMinutes);
      entries.insert(
          0, AppMenuEntry<int>(value: _notificationMinutes, label: label));
    }

    entries.add(const AppMenuEntry<int>(
        value: _kCustomSentinel, label: 'התאמה אישית...'));
    return entries;
  }

  // ── שינוי תאריך ──────────────────────────────────────────────────────────

  void _onDateChanged(DateTime date) {
    setState(() {
      _selectedDate = date;
      _selectedJewishDate = JewishDate.fromDateTime(date);
      if (!_userOverrodeNotification) {
        _notificationMinutes = _smartDefaultNotification();
      }
    });
    if (!_dateFocusNode.hasFocus) {
      _dateController.text = _formatPrimaryDate(date);
    }
  }

  // הלוח הראשי לפי ההגדרות: משולב/עברי → עברי, לועזי → לועזי.
  bool get _primaryIsHebrew =>
      widget.state.calendarType != CalendarType.gregorian;

  /// תאריך ראשי לשדה: יום + חודש, ושנה רק אם היא שונה מהשנה הנוכחית.
  String _formatPrimaryDate(DateTime date) {
    final now = DateTime.now();
    if (_primaryIsHebrew) {
      final jd = JewishDate.fromDateTime(date);
      final nowJd = JewishDate.fromDateTime(now);
      final base =
          '${formatHebrewDay(jd.getJewishDayOfMonth())} ${getHebrewMonthNameFor(jd)}';
      return jd.getJewishYear() == nowJd.getJewishYear()
          ? base
          : '$base ${formatHebrewYear(jd.getJewishYear())}';
    }
    final base = '${date.day} ${getGregorianMonthName(date.month)}';
    return date.year == now.year ? base : '$base ${date.year}';
  }

  /// תת-כותרת: התאריך בלוח המשני (ההפוך מהראשי) + שעת האירוע.
  String _startSubtitle() {
    final String secondary;
    if (_primaryIsHebrew) {
      secondary =
          '${_selectedDate.day} ${getGregorianMonthName(_selectedDate.month)} ${_selectedDate.year}';
    } else {
      final jd = _selectedJewishDate;
      secondary =
          '${formatHebrewDay(jd.getJewishDayOfMonth())} ${getHebrewMonthNameFor(jd)} ${formatHebrewYear(jd.getJewishYear())}';
    }
    final t = _selectedTime;
    if (t == null) return secondary;
    return '$secondary · '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  // ── תאריך ────────────────────────────────────────────────────────────────

  /// מעדכן חי את התאריך לפי טקסט שהוקלד בשדה החיפוש (בלי לעצב מחדש את השדה).
  void _onDateSearchChanged(String value) {
    final parsed = parseCalendarDate(
      value.trim(),
      currentJewishYear: _selectedJewishDate.getJewishYear(),
    );
    if (parsed == null || !isJumpToDateInRange(parsed)) return;
    _onDateChanged(parsed);
  }

  /// מאשר תאריך שהוקלד. מחזיר true אם הפירוש הצליח (לסגירת התפריט).
  bool _applyTypedDate(String value) {
    final parsed = parseCalendarDate(
      value.trim(),
      currentJewishYear: _selectedJewishDate.getJewishYear(),
    );
    if (parsed == null) {
      UiSnack.showError('לא הצלחנו לפרש את התאריך.');
      return false;
    }
    if (!isJumpToDateInRange(parsed)) {
      UiSnack.showError('התאריך מחוץ לטווח הנתמך.');
      return false;
    }
    _onDatePicked(parsed);
    return true;
  }

  void _onDatePicked(DateTime date) {
    _onDateChanged(date);
    _dateController.text = _formatPrimaryDate(date);
  }

  /// מובייל: דיאלוג בורר התאריך.
  Future<void> _pickDateWithDialog() async {
    DateTime tempDate = _selectedDate;
    bool showHebrew = calendarDefaultShowHebrew(widget.state.calendarType);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInnerState) => AppDialog.twoActions(
          title: Row(
            children: [
              const Expanded(child: Text('בחירת תאריך')),
              CalendarTypeToggleButton(
                showHebrew: showHebrew,
                onPressed: () => setInnerState(() => showHebrew = !showHebrew),
              ),
            ],
          ),
          content: '',
          handleEnterKey: false,
          cancelText: 'ביטול',
          confirmText: 'אישור',
          customContent: SizedBox(
            width: 340,
            child: CalendarDatePickerPanel(
              selectedDate: tempDate,
              currentDate: DateTime.now(),
              firstDate: kJumpToDateFirstDate,
              lastDate: kJumpToDateLastDate,
              showHebrew: showHebrew,
              bodyHeight: 290,
              onDateChanged: (d) => setInnerState(() => tempDate = d),
            ),
          ),
        ),
      ),
    );
    if (confirmed == true && mounted) _onDatePicked(tempDate);
  }

  // ── שעה ──────────────────────────────────────────────────────────────────

  /// תווית לכפתור השעה: 'כל היום' או HH:MM.
  String _formatTimeLabel() =>
      _selectedTime == null ? 'כל היום' : _formatTimeValue();

  /// HH:MM של השעה הנבחרת (ריק אם אין).
  String _formatTimeValue() {
    final t = _selectedTime;
    if (t == null) return '';
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  void _setTime(TimeOfDay time) {
    setState(() => _selectedTime = time);
  }

  void _setAllDay() {
    setState(() => _selectedTime = null);
  }

  /// מובייל: בורר השעה הסטנדרטי (showTimePicker).
  Future<void> _pickTimeWithDialog() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (time == null || !mounted) return;
    _setTime(time);
  }

  // ── שינוי סוג חזרה ───────────────────────────────────────────────────────

  void _onRecurrenceTypeChanged(RecurrenceType type) {
    setState(() {
      _selectedRecurrenceType = type;
      if (!_userOverrodeNotification) {
        _notificationMinutes = _smartDefaultNotification();
      }
    });
  }

  // ── דיאלוג התראה מותאם אישית ─────────────────────────────────────────────

  Future<void> _showCustomNotificationDialog() async {
    int qty = 1;
    String unit = 'ימים';
    final quantityCtrl = TextEditingController(text: '1');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInnerState) => AppDialog.twoActions(
          title: 'זמן התראה מותאם אישית',
          content: '',
          handleEnterKey: false,
          cancelText: 'ביטול',
          confirmText: 'אישור',
          customContent: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('בחר כמה זמן לפני האירוע להציג את ההתראה:'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: RtlTextField(
                      controller: quantityCtrl,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: 'כמות',
                        border: OutlineInputBorder(),
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      onChanged: (v) =>
                          setInnerState(() => qty = int.tryParse(v) ?? 0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: AppDropdownField<String>(
                      value: unit,
                      decoration: const InputDecoration(
                        labelText: 'יחידת זמן',
                        border: OutlineInputBorder(),
                      ),
                      entries: const [
                        AppMenuEntry(value: 'דקות', label: 'דקות'),
                        AppMenuEntry(value: 'שעות', label: 'שעות'),
                        AppMenuEntry(value: 'ימים', label: 'ימים'),
                        AppMenuEntry(value: 'שבועות', label: 'שבועות'),
                      ],
                      onSelected: (v) =>
                          setInnerState(() => unit = v ?? 'ימים'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (qty > 0)
                Text(
                  'ההתראה תופיע $qty $unit לפני מועד האירוע',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    if (qty <= 0) {
      UiSnack.showError('יש להזין כמות חיובית.');
      return;
    }

    final rawMinutes = _toMinutes(qty, unit);

    // תקרה של 3 חודשים
    const maxAllowedMinutes = 3 * 30 * 24 * 60;
    if (rawMinutes > maxAllowedMinutes) {
      UiSnack.showError('ניתן להגדיר לכל היותר 3 חודשים לפני האירוע.');
      return;
    }

    if (_selectedRecurrenceType == RecurrenceType.none &&
        rawMinutes > _minutesUntilEvent()) {
      UiSnack.showError('זמן ההתראה חייב להיות לפני מועד האירוע.');
      return;
    }

    setState(() {
      _notificationMinutes = rawMinutes;
      _userOverrodeNotification = true;
    });
  }

  // ── שליחה ────────────────────────────────────────────────────────────────

  void _submit() {
    if (_titleController.text.trim().isEmpty) {
      UiSnack.showError('יש למלא כותרת לאירוע.');
      return;
    }

    int? recurringYears;
    if (_selectedRecurrenceType != RecurrenceType.none && !_recurForever) {
      recurringYears = int.tryParse(_yearsController.text.trim());
      if (recurringYears == null || recurringYears <= 0) {
        UiSnack.showError('יש להזין מספר שנים חיובי עבור אירוע חוזר.');
        return;
      }
    }

    final isRecurring = _selectedRecurrenceType != RecurrenceType.none;
    // תאריך סיום זמין רק לאירוע חד-פעמי; טווח של יום בודד נשמר כ-null
    DateTime? endDate;
    if (!isRecurring && _selectedEndDate != null) {
      final start =
          DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final end = DateTime(_selectedEndDate!.year, _selectedEndDate!.month,
          _selectedEndDate!.day);
      if (end.isBefore(start)) {
        UiSnack.showError('תאריך הסיום חייב להיות אחרי תאריך ההתחלה.');
        return;
      }
      endDate = end.isAfter(start) ? end : null;
    }

    Navigator.of(context).pop(
      CalendarEventDialogResult(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        selectedDate: _selectedDate,
        recurrenceType: _selectedRecurrenceType,
        recurringYears: recurringYears,
        eventTime: _selectedTime,
        notificationMinutes: _notificationMinutes,
        endGregorianDate: endDate,
        colorIndex: _selectedColorIndex,
      ),
    );
  }

  Future<void> _pickEndDate() async {
    final start =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedEndDate ?? start,
      firstDate: start,
      lastDate: DateTime(start.year + 10),
    );
    if (picked != null) {
      setState(() => _selectedEndDate = picked);
    }
  }

  Widget _buildColorPicker() {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'צבע האירוע',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            children: [
              _ColorSwatch(
                color: null,
                selected: _selectedColorIndex == null,
                tooltip: 'ללא צבע',
                onTap: () => setState(() => _selectedColorIndex = null),
              ),
              for (int i = 0; i < CalendarEventColors.count; i++)
                _ColorSwatch(
                  color: CalendarEventColors.colorForIndex(i, brightness),
                  selected: _selectedColorIndex == i,
                  tooltip: CalendarEventColors.nameOf(i),
                  onTap: () => setState(() => _selectedColorIndex = i),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── כפתורי/תפריטי תאריך ושעה ─────────────────────────────────────────────

  Widget _pickerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: 12,
            end: trailing == null ? 12 : 4,
            top: 8,
            bottom: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
              if (trailing != null) ...[const SizedBox(width: 4), trailing],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateField() {
    if (!_isDesktop) {
      return _pickerButton(
        icon: FluentIcons.calendar_24_regular,
        label: _formatPrimaryDate(_selectedDate),
        onTap: _pickDateWithDialog,
      );
    }
    return _AnchoredMenu(
      popupWidth: 320,
      onEnter: () => _applyTypedDate(_dateController.text),
      onOpened: () {
        _dateController.text = _formatPrimaryDate(_selectedDate);
        _dateFocusNode.requestFocus();
        _dateController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _dateController.text.length,
        );
      },
      buttonBuilder: (ctx, open) => _pickerButton(
        icon: FluentIcons.calendar_24_regular,
        label: _formatPrimaryDate(_selectedDate),
        onTap: open,
      ),
      popupBuilder: (ctx, close) => _buildDatePopup(close),
    );
  }

  Widget _buildDatePopup(VoidCallback close) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'בחירת תאריך',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              CalendarTypeToggleButton(
                showHebrew: _dateShowHebrew,
                onPressed: () =>
                    setState(() => _dateShowHebrew = !_dateShowHebrew),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RtlTextField(
            controller: _dateController,
            focusNode: _dateFocusNode,
            decoration: const InputDecoration(
              labelText: 'חיפוש תאריך',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: _onDateSearchChanged,
          ),
          const SizedBox(height: 8),
          CalendarDatePickerPanel(
            selectedDate: _selectedDate,
            currentDate: DateTime.now(),
            firstDate: kJumpToDateFirstDate,
            lastDate: kJumpToDateLastDate,
            showHebrew: _dateShowHebrew,
            bodyHeight: 270,
            onDateChanged: _onDatePicked,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeField() {
    // מובייל: בורר מגע נטיבי; ✕ מסיר את השעה.
    if (!_isDesktop) {
      final trailing = _selectedTime != null
          ? IconButton(
              icon: Icon(FluentIcons.dismiss_24_regular, size: 18),
              tooltip: 'כל היום',
              visualDensity: VisualDensity.compact,
              onPressed: _setAllDay,
            )
          : null;
      return _pickerButton(
        icon: FluentIcons.clock_24_regular,
        label: _formatTimeLabel(),
        onTap: _pickTimeWithDialog,
        trailing: trailing,
      );
    }
    // דסקטופ: ללא שעה — צ'יפ "הוספת שעה"; עם שעה — עורך HH∶MM מוטבע.
    if (_selectedTime == null) {
      return _pickerButton(
        icon: FluentIcons.clock_24_regular,
        label: 'הוספת שעה',
        onTap: () => _setTime(TimeOfDay.now()),
      );
    }
    return _InlineTimeEditor(
      value: _selectedTime!,
      onChanged: _setTime,
      onClear: _setAllDay,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.existingEvent != null;
    final isRecurring = _selectedRecurrenceType != RecurrenceType.none;

    return AppCustomContentDialog(
      title: isEditMode ? 'ערוך אירוע' : 'צור אירוע חדש',
      onConfirm: _submit,
      handleEnterKey: true,
      actions: [
        ActionButton.neutral(
          text: 'ביטול',
          onPressed: () => Navigator.of(context).pop(),
        ),
        ActionButton.recommended(
          text: isEditMode ? 'שמור שינויים' : 'צור',
          onPressed: _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsCard(
            title: 'פרטי האירוע',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: RtlTextField(
                  controller: _titleController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'כותרת האירוע',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: UnderlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: RtlTextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'תיאור (לא חובה)',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: UnderlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ),
              _buildColorPicker(),
            ],
          ),
          SettingsCard(
            title: 'מועד האירוע',
            children: [
              // תחילת האירוע — תאריך + שעה מאוחדים.
              // מיקום הכפתורים והגלישה שלהם מנוהלים ע"י SettingsActionTile.
              SettingsActionTile.text(
                icon: FluentIcons.calendar_24_regular,
                title: 'תחילת האירוע',
                subtitle: _startSubtitle(),
                actions: [
                  _buildDateField(),
                  _buildTimeField(),
                ],
              ),

              // תאריך סיום — רק לאירוע חד-פעמי (אירוע חוזר אינו תומך בטווח ימים)
              if (!isRecurring)
                SettingsActionTile.text(
                  icon: FluentIcons.calendar_arrow_right_24_regular,
                  title: 'תאריך סיום',
                  subtitle: _selectedEndDate != null
                      ? 'סיום: ${_selectedEndDate!.day}/${_selectedEndDate!.month}/${_selectedEndDate!.year}'
                      : 'אירוע של יום אחד',
                  actions: [
                    if (_selectedEndDate != null)
                      _pickerButton(
                        icon: FluentIcons.dismiss_24_regular,
                        label: 'נקה',
                        onTap: () => setState(() => _selectedEndDate = null),
                      ),
                    _pickerButton(
                      icon: FluentIcons.calendar_24_regular,
                      label: 'בחר',
                      onTap: _pickEndDate,
                    ),
                  ],
                ),

              // חזרה — DropDown כולל "ללא חזרה" כברירת מחדל
              SettingsActionTile.dropdownTile<RecurrenceType>(
                icon: FluentIcons.arrow_repeat_all_24_regular,
                title: 'חזרה',
                subtitle: _recurrenceSubtitle(_selectedRecurrenceType),
                value: _selectedRecurrenceType,
                entries: [
                  const AppMenuEntry(
                      value: RecurrenceType.none, label: 'ללא חזרה'),
                  const AppMenuEntry(
                      value: RecurrenceType.weekly, label: 'שבועי'),
                  AppMenuEntry(
                    value: RecurrenceType.monthlyHebrew,
                    label:
                        'חודשי עברי (יום ${formatHebrewDay(_selectedJewishDate.getJewishDayOfMonth())} בחודש)',
                  ),
                  AppMenuEntry(
                    value: RecurrenceType.monthlyGregorian,
                    label: 'חודשי לועזי (יום ${_selectedDate.day} לחודש)',
                  ),
                  AppMenuEntry(
                    value: RecurrenceType.annualHebrew,
                    label:
                        'שנתי עברי (${formatHebrewDay(_selectedJewishDate.getJewishDayOfMonth())} ${getHebrewMonthNameFor(_selectedJewishDate)})',
                  ),
                  AppMenuEntry(
                    value: RecurrenceType.annualGregorian,
                    label:
                        'שנתי לועזי (${_selectedDate.day}/${_selectedDate.month})',
                  ),
                ],
                onSelected: (value) {
                  if (value != null) _onRecurrenceTypeChanged(value);
                },
              ),
              if (isRecurring) ...[
                CheckboxListTile(
                  title: const Text('חזרה ללא הגבלה (תמיד)'),
                  value: _recurForever,
                  onChanged: (value) {
                    setState(() {
                      _recurForever = value ?? true;
                      if (_recurForever) _yearsController.clear();
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (!_recurForever)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: RtlTextField(
                      controller: _yearsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'חזור למשך (שנים)',
                        hintText: 'לדוגמה: 5',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: UnderlineInputBorder(),
                      ),
                    ),
                  ),
              ],
            ],
          ),
          SettingsCard(
            title: 'מועד ההתראה',
            children: [
              SettingsActionTile.dropdownTile<int>(
                icon: FluentIcons.alert_24_regular,
                title: 'מועד ההתראה',
                subtitle: _notificationSubtitle(_notificationMinutes),
                value: _notificationMinutes,
                entries: _buildNotificationEntries(),
                onSelected: (value) {
                  if (value == null) return;
                  if (value == _kCustomSentinel) {
                    _showCustomNotificationDialog();
                    return;
                  }
                  setState(() {
                    _notificationMinutes = value;
                    _userOverrodeNotification = true;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// עיגול בחירת צבע יחיד בבורר הצבעים.
class _ColorSwatch extends StatelessWidget {
  final Color? color;
  final bool selected;
  final String? tooltip;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        // ריפוד סביב העיגול הנראה — מטרת לחיצה של 48dp לפחות
        child: Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color ?? cs.surfaceContainerHighest,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: color == null
              ? Icon(
                  FluentIcons.line_horizontal_1_24_regular,
                  size: 16,
                  color: cs.onSurfaceVariant,
                )
              : null,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _EventDateField — שדה תאריך M3: הקלדה חופשית + כפתור בורר תאריך
// ═══════════════════════════════════════════════════════════════════════════

/// תפריט מעוגן (desktop): כפתור שפותח תוכן מותאם מתחתיו — כמו תפריט.
/// נסגר בלחיצה מחוץ לו או ב-Escape (לא בעת מעבר פוקוס פנימי).
class _AnchoredMenu extends StatefulWidget {
  final double popupWidth;
  final VoidCallback? onOpened;

  /// נקרא בהקשת Enter בתוך התפריט. מחזיר true → התפריט נסגר.
  /// מיירט את Enter לפני navigator הדיאלוג כדי שלא יישלח הטופס בטעות.
  final bool Function()? onEnter;
  final Widget Function(BuildContext context, VoidCallback open) buttonBuilder;
  final Widget Function(BuildContext context, VoidCallback close) popupBuilder;

  const _AnchoredMenu({
    required this.popupWidth,
    required this.buttonBuilder,
    required this.popupBuilder,
    this.onOpened,
    this.onEnter,
  });

  @override
  State<_AnchoredMenu> createState() => _AnchoredMenuState();
}

class _AnchoredMenuState extends State<_AnchoredMenu> {
  final GlobalKey _buttonKey = GlobalKey();
  final OverlayPortalController _controller = OverlayPortalController();

  void _open() {
    if (_controller.isShowing) return;
    _controller.show();
    // onOpened נדחה לפוסט-פריים כדי שתוכן ה-overlay (השדה) כבר יהיה בנוי.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onOpened?.call();
    });
  }

  void _close() {
    if (_controller.isShowing) _controller.hide();
  }

  void _onEnter() {
    if (widget.onEnter?.call() ?? false) _close();
  }

  Widget _buildOverlay(BuildContext ctx) {
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || overlay == null || !overlay.hasSize) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    final target = box.localToGlobal(Offset.zero, ancestor: overlay);
    final overlaySize = overlay.size;

    const gap = 4.0;
    const margin = 8.0;
    final width = math.min(widget.popupWidth, overlaySize.width - 2 * margin);
    // יישור קצה התפריט לקצה הכפתור (בכיוון הקריאה) כך שהתפריט נפרש לתוך הדיאלוג,
    // עם הצמדה לגבולות המסך.
    final maxLeft = math.max(margin, overlaySize.width - width - margin);
    final left = target.dx.clamp(margin, maxLeft).toDouble();

    // פתיחה למטה אם יש מקום, אחרת למעלה — כמו כל תפריט.
    final spaceBelow =
        overlaySize.height - (target.dy + box.size.height) - gap - margin;
    final spaceAbove = target.dy - gap - margin;
    final openDown = spaceBelow >= spaceAbove;
    final maxHeight =
        (openDown ? spaceBelow : spaceAbove).clamp(120.0, overlaySize.height);

    final popup = Material(
      elevation: 8,
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _close,
                const SingleActivator(LogicalKeyboardKey.enter): _onEnter,
                const SingleActivator(LogicalKeyboardKey.numpadEnter): _onEnter,
              },
              child: widget.popupBuilder(ctx, _close),
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _close,
          ),
        ),
        Positioned(
          left: left,
          top: openDown ? target.dy + box.size.height + gap : null,
          bottom: openDown ? null : overlaySize.height - (target.dy - gap),
          child: popup,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: _buildOverlay,
      child: KeyedSubtree(
        key: _buttonKey,
        child: widget.buttonBuilder(context, _open),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  _InlineTimeEditor — עורך שעה מוטבע (desktop)
// ═══════════════════════════════════════════════════════════════════════════

/// שני תאי HH∶MM ללא סמן: הקלדת ספרה משנה את התא הממוקד (שתי ספרות → מעבר
/// אוטומטי לדקות), חיצים/Backspace לניווט ולעריכה, ✕ מנקה חזרה ל"כל היום".
class _InlineTimeEditor extends StatefulWidget {
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;
  final VoidCallback onClear;

  const _InlineTimeEditor({
    required this.value,
    required this.onChanged,
    required this.onClear,
  });

  @override
  State<_InlineTimeEditor> createState() => _InlineTimeEditorState();
}

class _InlineTimeEditorState extends State<_InlineTimeEditor> {
  final FocusNode _hourNode = FocusNode(debugLabel: 'hour');
  final FocusNode _minuteNode = FocusNode(debugLabel: 'minute');
  // האם הספרה הבאה מצטרפת לספרה שהוקלדה זה עתה (תא בן שתי ספרות).
  bool _combine = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hourNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _hourNode.dispose();
    _minuteNode.dispose();
    super.dispose();
  }

  int get _hour => widget.value.hour;
  int get _minute => widget.value.minute;

  void _setHour(int h) => widget.onChanged(TimeOfDay(hour: h, minute: _minute));
  void _setMinute(int m) => widget.onChanged(TimeOfDay(hour: _hour, minute: m));

  void _focusHour() {
    _combine = false;
    _hourNode.requestFocus();
  }

  void _focusMinute() {
    _combine = false;
    _minuteNode.requestFocus();
  }

  int? _digitOf(KeyEvent event) {
    final n = LogicalKeyboardKey.digit0.keyId;
    final id = event.logicalKey.keyId;
    if (id >= n && id <= n + 9) return id - n;
    final np = LogicalKeyboardKey.numpad0.keyId;
    if (id >= np && id <= np + 9) return id - np;
    return null;
  }

  KeyEventResult _onHourKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final digit = _digitOf(event);
    if (digit != null) {
      if (_combine) {
        final combined = _hour * 10 + digit;
        _setHour(combined > 23 ? digit : combined);
        _focusMinute();
      } else {
        _setHour(digit);
        // ספרה 0-2 עשויה לקבל ספרה שנייה; 3-9 היא שעה שלמה → מעבר לדקות.
        if (digit <= 2) {
          _combine = true;
        } else {
          _focusMinute();
        }
      }
      return KeyEventResult.handled;
    }
    return _handleNav(event, isHour: true);
  }

  KeyEventResult _onMinuteKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final digit = _digitOf(event);
    if (digit != null) {
      if (_combine) {
        final combined = _minute * 10 + digit;
        _setMinute(combined > 59 ? digit : combined);
        _combine = false;
      } else {
        _setMinute(digit);
        _combine = digit <= 5;
      }
      return KeyEventResult.handled;
    }
    return _handleNav(event, isHour: false);
  }

  KeyEventResult _handleNav(KeyEvent event, {required bool isHour}) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      if (isHour) _focusMinute();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (!isHour) _focusHour();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final delta = key == LogicalKeyboardKey.arrowUp ? 1 : -1;
      if (isHour) {
        _setHour((_hour + delta + 24) % 24);
      } else {
        _setMinute((_minute + delta + 60) % 60);
      }
      _combine = false;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      isHour ? _setHour(0) : _setMinute(0);
      _combine = false;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // שעה היא תוכן מספרי LTR — HH משמאל, MM מימין.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
              start: 8, end: 4, top: 4, bottom: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _segment(const Key('time-hour'), _hourNode, _hour, _onHourKey),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(':',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
              ),
              _segment(
                  const Key('time-minute'), _minuteNode, _minute, _onMinuteKey),
              IconButton(
                icon: Icon(FluentIcons.dismiss_24_regular, size: 18),
                tooltip: 'כל היום',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onClear,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment(
    Key key,
    FocusNode node,
    int value,
    KeyEventResult Function(FocusNode, KeyEvent) onKey,
  ) {
    final cs = Theme.of(context).colorScheme;
    final focused = node.hasFocus;
    return Focus(
      focusNode: node,
      onKeyEvent: onKey,
      onFocusChange: (hasFocus) {
        if (hasFocus) _combine = false;
        setState(() {});
      },
      child: GestureDetector(
        key: key,
        onTap: () {
          _combine = false;
          node.requestFocus();
        },
        child: Container(
          width: 40,
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused ? cs.primaryContainer : cs.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: focused ? cs.onPrimaryContainer : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  showCalendarEventDialog
// ═══════════════════════════════════════════════════════════════════════════

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
