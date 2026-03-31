import 'package:flutter/material.dart';
import 'package:flutter_spinbox/flutter_spinbox.dart';

enum ZmanMenuAction { toggle }

class ZmanAlertDialogResult {
  final int minutesBefore;
  final bool cancelAlert;

  const ZmanAlertDialogResult({
    required this.minutesBefore,
    required this.cancelAlert,
  });
}

/// דיאלוג הגדרת התראה לזמן הלכתי
class ZmanAlertDialog extends StatefulWidget {
  final String zmanName;
  final String timeLabel;
  final int initialMinutesBefore;
  final bool isEnabled;

  const ZmanAlertDialog({
    super.key,
    required this.zmanName,
    required this.timeLabel,
    required this.initialMinutesBefore,
    required this.isEnabled,
  });

  @override
  State<ZmanAlertDialog> createState() => _ZmanAlertDialogState();
}

class _ZmanAlertDialogState extends State<ZmanAlertDialog> {
  late int hours;
  late int minutes;

  @override
  void initState() {
    super.initState();
    final total = widget.initialMinutesBefore;
    hours = total ~/ 60;
    minutes = total % 60;
  }

  int get totalMinutes => (hours * 60) + minutes;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.zmanName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'כמה זמן לפני זמן ${widget.zmanName} ברצונך לקבל התראה?',
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 8),
          Text(
            'הזמן: ${widget.timeLabel}',
            style: Theme.of(context).textTheme.bodySmall,
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SpinBox(
                  min: 0,
                  max: 23,
                  value: hours.toDouble(),
                  decimals: 0,
                  step: 1,
                  decoration: const InputDecoration(labelText: 'שעות'),
                  onChanged: (v) => setState(() => hours = v.toInt()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SpinBox(
                  min: 0,
                  max: 59,
                  value: minutes.toDouble(),
                  decimals: 0,
                  step: 1,
                  decoration: const InputDecoration(labelText: 'דקות'),
                  onChanged: (v) => setState(() => minutes = v.toInt()),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (widget.isEnabled)
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              const ZmanAlertDialogResult(minutesBefore: 0, cancelAlert: true),
            ),
            child: const Text('בטל התראה'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            ZmanAlertDialogResult(
              minutesBefore: totalMinutes,
              cancelAlert: false,
            ),
          ),
          child: Text(widget.isEnabled ? 'עדכן' : 'הפעל'),
        ),
      ],
    );
  }
}

/// עוזר להצגת הדיאלוג
Future<ZmanAlertDialogResult?> showZmanAlertDialog(
  BuildContext context, {
  required String zmanName,
  required String timeLabel,
  required int initialMinutesBefore,
  required bool isEnabled,
}) {
  return showDialog<ZmanAlertDialogResult>(
    context: context,
    builder: (_) => ZmanAlertDialog(
      zmanName: zmanName,
      timeLabel: timeLabel,
      initialMinutesBefore: initialMinutesBefore,
      isEnabled: isEnabled,
    ),
  );
}
