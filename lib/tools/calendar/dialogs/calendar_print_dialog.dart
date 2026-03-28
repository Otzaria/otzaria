import 'package:flutter/material.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_state.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';

/// דיאלוג לקביעת טווח ההדפסה של לוח השנה.
class CalendarPrintDialog extends StatefulWidget {
  final CalendarView calendarView;

  const CalendarPrintDialog({
    super.key,
    required this.calendarView,
  });

  @override
  State<CalendarPrintDialog> createState() => _CalendarPrintDialogState();
}

class _CalendarPrintDialogState extends State<CalendarPrintDialog> {
  int _count = 1;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (String periodName, String periodNamePlural, int maxCount) =
        switch (widget.calendarView) {
      CalendarView.month => ('חודש', 'חודשים', 12),
      CalendarView.week => ('שבוע', 'שבועות', 52),
    };

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: cs.surfaceContainerHigh,
        title: const Text('הגדרות הדפסה'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('בחר כמה $periodNamePlural להדפיס:'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _count.toDouble(),
                      min: 1,
                      max: maxCount.toDouble(),
                      divisions: maxCount - 1,
                      label: _count.toString(),
                      onChanged: (v) => setState(() => _count = v.round()),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 100,
                    child: Text(
                      _count == 1
                          ? '$_count $periodName'
                          : '$_count $periodNamePlural',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'טווח: ${_count == 1 ? periodName : '$_count $periodNamePlural'} החל מהתאריך הנוכחי',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
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
            text: 'הדפס',
            onPressed: () => Navigator.of(context).pop(_count),
          ),
        ],
      ),
    );
  }
}

/// מציג את דיאלוג ההדפסה ומחזיר את כמות היחידות להדפסה.
Future<int?> showCalendarPrintDialog({
  required BuildContext context,
  required CalendarView calendarView,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => CalendarPrintDialog(calendarView: calendarView),
  );
}
