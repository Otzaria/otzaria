import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/tools/calendar/widgets/calendar_date_picker_panel.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

final DateTime kJumpToDateFirstDate = DateTime(1900);
final DateTime kJumpToDateLastDate = DateTime(2100);

DateTime clampJumpToDate(DateTime date) {
  if (date.isBefore(kJumpToDateFirstDate)) {
    return kJumpToDateFirstDate;
  }
  if (date.isAfter(kJumpToDateLastDate)) {
    return kJumpToDateLastDate;
  }
  return date;
}

bool isJumpToDateInRange(DateTime date) {
  return !date.isBefore(kJumpToDateFirstDate) &&
      !date.isAfter(kJumpToDateLastDate);
}

class JumpToDatePanel extends StatefulWidget {
  final DateTime selectedDate;
  final DateTime currentDate;
  final ValueChanged<DateTime> onDateChanged;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final bool showHebrew;

  const JumpToDatePanel({
    super.key,
    required this.selectedDate,
    required this.currentDate,
    required this.onDateChanged,
    required this.onCancel,
    required this.onConfirm,
    this.showHebrew = true,
  });

  @override
  State<JumpToDatePanel> createState() => _JumpToDatePanelState();
}

class _JumpToDatePanelState extends State<JumpToDatePanel> {
  // זמן ה-pointer-down האחרון על האזור
  DateTime? _lastPointerDownTime;
  Offset? _lastPointerDownPosition;
  // האם CalendarDatePicker קרא ל-onDateChanged מאז הלחיצה הקודמת —
  // רק אז זוהי לחיצה על תא תאריך (לא על חיצי ניווט)
  bool _dateSelectedSinceLastDown = false;

  void _handlePointerDown(PointerDownEvent event) {
    final now = DateTime.now();
    final last = _lastPointerDownTime;
    final lastPosition = _lastPointerDownPosition;
    final isNearLastPointerDown = lastPosition != null &&
        (event.position - lastPosition).distanceSquared <=
            kDoubleTapSlop * kDoubleTapSlop;
    if (last != null &&
        now.difference(last) < kDoubleTapTimeout &&
        isNearLastPointerDown &&
        _dateSelectedSinceLastDown) {
      _lastPointerDownTime = null;
      _lastPointerDownPosition = null;
      _dateSelectedSinceLastDown = false;
      widget.onConfirm();
    } else {
      _lastPointerDownTime = now;
      _lastPointerDownPosition = event.position;
      _dateSelectedSinceLastDown = false;
    }
  }

  void _onDateChanged(DateTime date) {
    // מסמן שתא תאריך נבחר — לא ניווט
    _dateSelectedSinceLastDown = true;
    widget.onDateChanged(date);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        Listener(
          onPointerDown: _handlePointerDown,
          child: CalendarDatePickerPanel(
            selectedDate: clampJumpToDate(widget.selectedDate),
            currentDate: clampJumpToDate(widget.currentDate),
            firstDate: kJumpToDateFirstDate,
            lastDate: kJumpToDateLastDate,
            showHebrew: widget.showHebrew,
            onDateChanged: _onDateChanged,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ActionButton.neutral(
              text: 'ביטול',
              onPressed: widget.onCancel,
            ),
            const SizedBox(width: 8),
            ActionButton.recommended(
              text: 'פתח',
              onPressed: widget.onConfirm,
            ),
          ],
        ),
      ],
    );
  }
}
