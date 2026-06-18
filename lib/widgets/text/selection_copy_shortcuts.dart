import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// מיירט Ctrl+C / Cmd+C סביב [SelectionArea] ומפעיל [onCopy] במקום העתקת
/// ברירת המחדל של Flutter — כדי לקבל העתקה מעוצבת (עם כותרות) והודעת הצלחה,
/// בדיוק כמו דרך תפריט ההקשר.
///
/// יש למקם אותו *מעל* ה-SelectionArea (כהורה): ה-SelectableRegion מגדיר את
/// פעולת ההעתקה כ-overridable, ומנגנון ה-override מאתר override רק כלפי מעלה
/// בעץ. עטיפה מתחת ל-SelectionArea לא תיתפס.
class SelectionCopyShortcuts extends StatelessWidget {
  const SelectionCopyShortcuts({
    super.key,
    required this.onCopy,
    required this.child,
  });

  final VoidCallback onCopy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        // נשלח כש-ה-SelectableRegion הוא ה-primaryFocus (בחירה פעילה).
        CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
          onInvoke: (_) {
            onCopy();
            return null;
          },
        ),
        // נשלח כשהפוקוס במקום אחר בתת-העץ ולא ב-SelectableRegion.
        _CopyIntent: CallbackAction<_CopyIntent>(
          onInvoke: (_) {
            onCopy();
            return null;
          },
        ),
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.keyC, control: true):
              _CopyIntent(),
          SingleActivator(LogicalKeyboardKey.keyC, meta: true): _CopyIntent(),
        },
        child: child,
      ),
    );
  }
}

class _CopyIntent extends Intent {
  const _CopyIntent();
}
