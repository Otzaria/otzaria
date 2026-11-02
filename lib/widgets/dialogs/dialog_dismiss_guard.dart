import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';

/// שומר אחד לכל דרכי היציאה מדיאלוג שעוברות ב-[Navigator.maybePop]: X,
/// ביטול, Escape, לחיצה בחוץ וחזרה. כש-[canDismiss] false היציאה חסומה (תהליך
/// פעיל); כש-[isDirty] true נשאלת קודם שאלת אישור. אישור הדיאלוג סוגר
/// ב-[Navigator.pop] ישיר ולא עובר כאן.
class DialogDismissGuard extends StatelessWidget {
  const DialogDismissGuard({
    super.key,
    required this.child,
    this.isDirty = false,
    this.canDismiss = true,
    this.onDismissRequest,
  });

  /// כמו הבנאי, כשמצב השינויים מגיע כ-[ValueListenable] ולא בבנייה מחדש.
  static Widget listenable({
    required ValueListenable<bool>? isDirty,
    bool canDismiss = true,
    VoidCallback? onDismissRequest,
    required Widget child,
  }) {
    if (isDirty == null) {
      return DialogDismissGuard(
        canDismiss: canDismiss,
        onDismissRequest: onDismissRequest,
        child: child,
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: isDirty,
      builder: (_, dirty, child) => DialogDismissGuard(
        isDirty: dirty,
        canDismiss: canDismiss,
        child: child!,
      ),
      child: child,
    );
  }

  final Widget child;

  /// גם קיצורי הניווט, שסוגרים דיאלוגים לפני מעבר, נעצרים כשהוא true.
  final bool isDirty;

  final bool canDismiss;

  /// במקום הסגירה: היציאה קוראת לו, והקורא סוגר ב-[Navigator.pop] — לטופס
  /// ששואל שאלת סגירה משלו.
  final VoidCallback? onDismissRequest;

  Future<void> _onBlockedPop(BuildContext context, Object? result) async {
    if (!canDismiss) return;
    if (onDismissRequest != null) {
      onDismissRequest!();
      return;
    }
    if (isDirty && await confirmDiscardChanges(context) != true) return;
    if (context.mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: canDismiss && !isDirty && onDismissRequest == null,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _onBlockedPop(context, result);
    },
    child: child,
  );
}

/// שאלת הסגירה של טופס עם שינויים שלא נשמרו. true = לסגור בלי לשמור.
Future<bool?> confirmDiscardChanges(BuildContext context) => showWarningDialog(
  context: context,
  title: context.settingsText('לסגור בלי לשמור?'),
  content: context.settingsText('השינויים שלא נשמרו יאבדו.'),
  cancelText: context.settingsText('המשך לערוך'),
  confirmText: context.settingsText('סגור בלי לשמור'),
);
