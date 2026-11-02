import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  });

  /// כמו הבנאי, כשמצב השינויים מגיע כ-[ValueListenable] ולא בבנייה מחדש.
  static Widget listenable({
    required ValueListenable<bool>? isDirty,
    bool canDismiss = true,
    required Widget child,
  }) {
    if (isDirty == null) {
      return DialogDismissGuard(canDismiss: canDismiss, child: child);
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

  Future<void> _onBlockedPop(BuildContext context, Object? result) async {
    if (!canDismiss) return;
    if (isDirty && await confirmDiscardChanges(context) != true) return;
    if (context.mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: canDismiss && !isDirty,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _onBlockedPop(context, result);
    },
    child: child,
  );
}

/// שאלת הסגירה של טופס עם שינויים שלא נשמרו. true = לסגור בלי לשמור.
Future<bool?> confirmDiscardChanges(BuildContext context) => showWarningDialog(
  context: context,
  title: 'לסגור בלי לשמור?',
  content: 'השינויים שלא נשמרו יאבדו.',
  cancelText: 'המשך לערוך',
  confirmText: 'סגור בלי לשמור',
);
