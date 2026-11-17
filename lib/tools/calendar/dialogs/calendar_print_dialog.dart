import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/dialogs/calendar_print_zmanim_picker.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_print_options.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';

/// דיאלוג לקביעת טווח ההדפסה של לוח השנה.
class CalendarPrintDialog extends StatefulWidget {
  final CalendarView calendarView;
  final ShortcutActivator? closeShortcut;

  /// הזמנים שמופעלים בלוח (`CalendarState.enabledZmanim`): ברירת המחדל
  /// של הדפסת יום.
  final Set<String> enabledZmanim;

  const CalendarPrintDialog({
    super.key,
    required this.calendarView,
    this.closeShortcut,
    this.enabledZmanim = const {},
  });

  @override
  State<CalendarPrintDialog> createState() => _CalendarPrintDialogState();
}

class _CalendarPrintDialogState extends State<CalendarPrintDialog> {
  int _count = 1;

  /// זמני היום שנבחרו להדפסה; `null` = ברירת המחדל של התצוגה. נטען מההדפסה
  /// הקודמת.
  Set<String>? _zmanim = CalendarPrintZmanimStore.load();

  bool get _selectionFits {
    final max = maxPrintedZmanim(widget.calendarView);
    return max == null || (_zmanim?.length ?? 0) <= max;
  }

  Future<void> _confirm() async {
    await CalendarPrintZmanimStore.save(_zmanim);
    if (mounted) Navigator.of(context).pop(_count);
  }

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

    final theme = Theme.of(context);
    Widget result = AppDialogFrame(
      size: AppDialogSize.small,
      title: 'הגדרות הדפסה',
      icon: FluentIcons.print_24_regular,
      scrollable: true,
      onConfirm: _selectionFits ? _confirm : null,
      actions: [
        ActionButton.neutral(
          text: 'ביטול',
          onPressed: () => Navigator.of(context).pop(),
        ),
        ActionButton.recommended(
          text: 'הדפס',
          onPressed: _selectionFits ? _confirm : null,
        ),
      ],
      // סגנון הגוף של AlertDialog.
      child: DefaultTextStyle.merge(
        style:
            theme.dialogTheme.contentTextStyle ??
            theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
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
                  size: AppTokens.iconSM,
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
            const SizedBox(height: AppTokens.spaceMD),
            CalendarPrintZmanimPicker(
              view: widget.calendarView,
              defaultSelection: defaultPrintedZmanim(
                widget.calendarView,
                dayZmanim: widget.enabledZmanim,
              ),
              selection: _zmanim,
              onChanged: (value) => setState(() => _zmanim = value),
            ),
          ],
        ),
      ),
    );

    if (widget.closeShortcut != null) {
      result = CallbackShortcuts(
        bindings: {
          widget.closeShortcut!: () => Navigator.of(context).pop(),
        },
        child: result,
      );
    }

    return result;
  }
}

/// מציג את דיאלוג ההדפסה ומחזיר את כמות היחידות להדפסה.
Future<int?> showCalendarPrintDialog({
  required BuildContext context,
  required CalendarView calendarView,
  ShortcutActivator? closeShortcut,
  Set<String> enabledZmanim = const {},
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => CalendarPrintDialog(
      calendarView: calendarView,
      closeShortcut: closeShortcut,
      enabledZmanim: enabledZmanim,
    ),
  );
}
