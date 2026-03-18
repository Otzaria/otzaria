import 'package:flutter/material.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

/// דיאלוג מעבר לתאריך בלוח השנה.
class JumpToDateDialog extends StatefulWidget {
  final DateTime? Function(String input) parseInputDate;

  const JumpToDateDialog({
    super.key,
    required this.parseInputDate,
  });

  @override
  State<JumpToDateDialog> createState() => _JumpToDateDialogState();
}

class _JumpToDateDialogState extends State<JumpToDateDialog> {
  late DateTime _selectedDate;
  late final TextEditingController _dateController;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _dateController = TextEditingController();
  }

  @override
  void dispose() {
    _dateController.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _dateController.text;
    final dateToJump =
        text.isNotEmpty ? widget.parseInputDate(text) : _selectedDate;

    if (dateToJump == null) {
      UiSnack.showError('לא הצלחנו לפרש את התאריך.');
      return;
    }

    Navigator.of(context).pop(dateToJump);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: const Text('מעבר לתאריך'),
        content: SizedBox(
          width: 350,
          height: 450,
          child: Column(
            children: [
              RtlTextField(
                controller: _dateController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'הזן תאריך',
                  hintText: 'דוגמאות: 15/3/2025, כ״ה אדר תשפ״ה',
                  border: OutlineInputBorder(),
                  helperText: 'ניתן להזין תאריך לועזי (יום/חודש/שנה) או עברי',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const Text(
                'או בחר בלוח השנה:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: CalendarDatePicker(
                  initialDate: _selectedDate,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2100),
                  onDateChanged: (date) {
                    setState(() {
                      _selectedDate = date;
                      _dateController.text =
                          '${date.day}/${date.month}/${date.year}';
                    });
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
            text: 'פתח',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

/// מציג את דיאלוג המעבר לתאריך ומחזיר את התאריך שנבחר.
Future<DateTime?> showJumpToDateDialog({
  required BuildContext context,
  required DateTime? Function(String input) parseInputDate,
}) {
  return showDialog<DateTime?>(
    context: context,
    builder: (_) => JumpToDateDialog(
      parseInputDate: parseInputDate,
    ),
  );
}
