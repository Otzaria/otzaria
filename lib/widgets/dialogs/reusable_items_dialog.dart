import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/layout/panel_scrollable_content.dart';
import 'package:otzaria/widgets/misc/keyboard_dialog_navigation.dart';

/// מיכל דיאלוג ראשי לתוכן מורכב — מסכים, רשימות, טפסים.
class AppCustomContentDialog extends StatefulWidget {
  final String title;
  final Widget child;

  /// תג אייקון בכותרת; בלעדיו הכותרת היא טקסט בלבד.
  final IconData? icon;

  /// כפתורי פעולה שיוצגו בשורה בתחתית הדיאלוג.
  /// הכנס [ActionButton.recommended] / [ActionButton.neutral] כסטנדרט.
  final List<Widget>? actions;

  /// נקרא בלחיצת Enter (כשהפוקוס לא בשדה טקסט).
  /// כשמוגדר null, Enter מושבת לחלוטין ללא קשר ל-[handleEnterKey].
  final VoidCallback? onConfirm;

  /// האם Enter יכול להפעיל [onConfirm]. ברירת מחדל: false.
  /// Enter פעיל בפועל רק כש-true **וגם** [onConfirm] אינו null.
  final bool handleEnterKey;

  /// האם לעטוף את [child] ב-[SingleChildScrollView] אוטומטית.
  /// false כשה-child מנהל scroll פנימי בעצמו (ListView, CustomScrollView וכד').
  final bool scrollable;

  /// האם ניתן לסגור דרך X, Escape או חזרה בזמן שהתוכן מבצע פעולה.
  final bool canDismiss;

  const AppCustomContentDialog({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.actions,
    this.onConfirm,
    this.handleEnterKey = false,
    this.scrollable = true,
    this.canDismiss = true,
  });

  @override
  State<AppCustomContentDialog> createState() => _AppCustomContentDialogState();
}

class _AppCustomContentDialogState extends State<AppCustomContentDialog>
    with DialogNavigationMixin {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // במסך צר (mobile) 95% — מונע קריסת שורות. ב-desktop 50%.
    final isNarrow = size.width < LayoutBreakpoints.compact;
    final width = isNarrow ? size.width * 0.95 : size.width * 0.5;

    // Enter פעיל רק כשגם handleEnterKey=true וגם onConfirm מוגדר.
    // אחרת — לחיצת Enter בשדה טקסט עלולה לסגור את הדיאלוג בטעות.
    final effectiveHandleEnterKey =
        widget.handleEnterKey && widget.onConfirm != null;

    final dialog = buildKeyboardNavigator(
      onConfirm: widget.onConfirm ?? () {},
      onCancel: () {
        if (widget.canDismiss) Navigator.of(context).pop();
      },
      handleEnterKey: effectiveHandleEnterKey,
      child: Dialog(
        insetPadding: const EdgeInsets.all(AppTokens.spaceMD),
        // בכהה רקע הלוח שחור, כמו הכיסוי שמאחורי הדיאלוג, והדיאלוג נבלע בו.
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surface
            : AppSurfaces.panelBackground(context),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: size.height * 0.8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogHeader(
                icon: widget.icon,
                title: widget.title,
                compact: true,
                fitTitle: true,
                closeEnabled: widget.canDismiss,
              ),
              const SizedBox(height: AppTokens.spaceMD),
              Expanded(
                child: widget.scrollable
                    // גובה הדיאלוג קבוע (80% מהמסך), כך שבחלון נמוך התוכן
                    // נחתך בלי סימן — פס גלילה קבוע הוא הרמז היחיד שיש המשך.
                    ? PanelScrollableContent(
                        thumbVisibility: true,
                        child: widget.child,
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTokens.spaceMD,
                        ),
                        child: widget.child,
                      ),
              ),
              if (widget.actions != null && widget.actions!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMD),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Wrap(
                      spacing: AppTokens.spaceSM,
                      runSpacing: AppTokens.spaceSM,
                      children: widget.actions!,
                    ),
                  ),
                )
              else
                const SizedBox(height: AppTokens.spaceMD),
            ],
          ),
        ),
      ),
    );
    return PopScope(canPop: widget.canDismiss, child: dialog);
  }
}
