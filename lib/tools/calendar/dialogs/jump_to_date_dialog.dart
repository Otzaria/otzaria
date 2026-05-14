import 'package:flutter/material.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';

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

class JumpToDatePanel extends StatelessWidget {
  final DateTime selectedDate;
  final DateTime currentDate;
  final ValueChanged<DateTime> onDateChanged;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const JumpToDatePanel({
    super.key,
    required this.selectedDate,
    required this.currentDate,
    required this.onDateChanged,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(),
        const Text(
          'בחר תאריך בלוח השנה:',
          textDirection: TextDirection.rtl,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 320,
          child: CalendarDatePicker(
            key: ValueKey(clampJumpToDate(selectedDate)),
            initialDate: clampJumpToDate(selectedDate),
            currentDate: clampJumpToDate(currentDate),
            firstDate: kJumpToDateFirstDate,
            lastDate: kJumpToDateLastDate,
            onDateChanged: onDateChanged,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            NeutralActionButton(
              text: 'ביטול',
              onPressed: onCancel,
            ),
            const SizedBox(width: 8),
            RecommendedActionButton(
              text: 'פתח',
              onPressed: onConfirm,
            ),
          ],
        ),
      ],
    );
  }
}
