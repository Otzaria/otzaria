import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// חוזה המקלדת של דיאלוג (DESIGN_SYSTEM §3.1):
/// - Escape סוגר דרך [Navigator.maybePop], ולכן עובר בשומר שינויים שלא נשמרו
///   ([DialogDismissGuard]) גם כשהלחיצה בחוץ חסומה.
/// - Enter בשדה טקסט חד־שורתי מפעיל את [onConfirm]. על כפתור או פריט ממוקד
///   Enter מפעיל אותו, ובשדה רב־שורתי מוסיף שורה.
/// - Enter כשאין רכיב ממוקד שמגיב לו מפעיל את [onConfirm], כמו כפתור ברירת מחדל.
/// - חיצים לא נבלעים.
class DialogKeyboardNavigator extends StatelessWidget {
  final Widget child;
  final VoidCallback? onConfirm;

  /// האם Enter מפעיל את [onConfirm]. false משאיר את Enter לרכיב הממוקד בלבד.
  final bool handleEnterKey;

  /// התוצאה שהדיאלוג מחזיר כשנסגר ב-Escape.
  final Object? dismissResult;

  const DialogKeyboardNavigator({
    super.key,
    required this.child,
    this.onConfirm,
    this.handleEnterKey = true,
    this.dismissResult,
  });

  static bool _isEnter(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;

  KeyEventResult _handleEnter() {
    final focused = primaryFocus?.context;
    if (focused == null) return KeyEventResult.ignored;
    final editable = focused.findAncestorWidgetOfExactType<EditableText>();
    if (editable != null) {
      if (editable.maxLines != 1) return KeyEventResult.ignored;
    } else if (Actions.maybeFind<ActivateIntent>(
          focused,
        )?.isEnabled(const ActivateIntent()) ??
        false) {
      return KeyEventResult.ignored;
    }
    if (!handleEnterKey || onConfirm == null) return KeyEventResult.ignored;
    onConfirm!();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) => Navigator.of(context).maybePop(dismissResult),
        ),
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent || !_isEnter(event.logicalKey)) {
            return KeyEventResult.ignored;
          }
          return _handleEnter();
        },
        child: child,
      ),
    );
  }
}
