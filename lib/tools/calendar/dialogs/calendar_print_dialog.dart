import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/misc/keyboard_dialog_navigation.dart';

/// דיאלוג לקביעת טווח ההדפסה של לוח השנה.
class CalendarPrintDialog extends StatefulWidget {
  final CalendarView calendarView;
  final ShortcutActivator? closeShortcut;

  const CalendarPrintDialog({
    super.key,
    required this.calendarView,
    this.closeShortcut,
  });

  @override
  State<CalendarPrintDialog> createState() => _CalendarPrintDialogState();
}

class _CalendarPrintDialogState extends State<CalendarPrintDialog>
    with DialogNavigationMixin {
  int _count = 1;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // שנה עברית מעוברת = 13 חודשים וטווח כולל (אייר–אייר) = 14, לכן שנתיים.
    // שבועות: שנה מעוברת ארוכה = 385 ימים = 55 שבועות. ימים: שני חודשים מלאים.
    final (
      String periodName,
      String periodNamePlural,
      int maxCount,
    ) = switch (widget.calendarView) {
      CalendarView.month => ('חודש', 'חודשים', 24),
      CalendarView.week => ('שבוע', 'שבועות', 55),
      CalendarView.day => ('יום', 'ימים', 62),
    };

    final dialog = AlertDialog(
      backgroundColor: cs.surfaceContainerHigh,
      title: const AppDialogTitle(
        'הגדרות הדפסה',
        icon: FluentIcons.print_24_regular,
      ),
      content: SizedBox(
        width: math.min(400.0, MediaQuery.sizeOf(context).width - 112),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('בחר כמה $periodNamePlural להדפיס:'),
            const SizedBox(height: AppTokens.spaceMD),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceMD,
                vertical: AppTokens.spaceSM,
              ),
              decoration: BoxDecoration(
                color: AppSurfaces.card(context),
                borderRadius: AppTokens.borderRadiusAll,
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      autofocus: true,
                      value: _count.toDouble(),
                      min: 1,
                      max: maxCount.toDouble(),
                      divisions: maxCount - 1,
                      label: _count.toString(),
                      onChanged: (v) => setState(() => _count = v.round()),
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceSM),
                  // הערך הנבחר כתג קבוע ברוחבו: הטקסט משתנה בין "חודש" ל"חודשים".
                  Container(
                    constraints: const BoxConstraints(minWidth: 88),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spaceMD,
                      vertical: AppTokens.spaceSM,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: AppTokens.borderRadiusAll,
                    ),
                    child: Text(
                      _count == 1
                          ? '$_count $periodName'
                          : '$_count $periodNamePlural',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTokens.spaceSM),
            Row(
              children: [
                Icon(
                  FluentIcons.info_24_regular,
                  size: AppTokens.fontLG,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: AppTokens.spaceSM),
                Expanded(
                  child: Text(
                    'טווח: ${_count == 1 ? periodName : '$_count $periodNamePlural'} החל מהתאריך הנוכחי',
                    style: TextStyle(
                      fontSize: AppTokens.fontSM,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
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
          text: 'הדפס',
          onPressed: () => Navigator.of(context).pop(_count),
        ),
      ],
    );

    Widget result = dialog;
    if (widget.closeShortcut != null) {
      result = CallbackShortcuts(
        bindings: {
          widget.closeShortcut!: () => Navigator.of(context).pop(),
        },
        child: result,
      );
    }

    return buildKeyboardNavigator(
      onConfirm: () => Navigator.of(context).pop(_count),
      onCancel: () => Navigator.of(context).pop(),
      child: result,
    );
  }
}

/// מציג את דיאלוג ההדפסה ומחזיר את כמות היחידות להדפסה.
Future<int?> showCalendarPrintDialog({
  required BuildContext context,
  required CalendarView calendarView,
  ShortcutActivator? closeShortcut,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => CalendarPrintDialog(
      calendarView: calendarView,
      closeShortcut: closeShortcut,
    ),
  );
}
