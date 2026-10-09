import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/widgets/text/rtl_selection_shortcuts.dart';

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
        CopySelectionTextIntent: FormattedCopyAction(onCopy),
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

/// האם [intent] הוא ווריאנט הגזירה (Ctrl+X) על טקסט שאינו ניתן לעריכה.
///
/// Flutter ממפה Ctrl+X לאותו [CopySelectionTextIntent] של Ctrl+C, עם
/// `collapseSelection`. בטקסט לקריאה בלבד אין מה לגזור, ובליעת המקש חוסמת
/// קיצור גלובלי שהמשתמש הגדיר על Ctrl+X (issue #1037).
bool isReadOnlyCutIntent(CopySelectionTextIntent intent) {
  if (!intent.collapseSelection) return false;
  final focusContext = FocusManager.instance.primaryFocus?.context;
  return focusContext == null || !isTextInputContext(focusContext);
}

/// מפעיל [onCopy] על [CopySelectionTextIntent], למעט גזירה בטקסט לקריאה בלבד
/// (ראו [isReadOnlyCutIntent]) — שם הפעולה מושבתת והמקש משוחרר להמשך טיפול.
class FormattedCopyAction extends Action<CopySelectionTextIntent> {
  FormattedCopyAction(this.onCopy);

  final VoidCallback onCopy;

  @override
  bool isEnabled(CopySelectionTextIntent intent) =>
      !isReadOnlyCutIntent(intent);

  @override
  Object? invoke(CopySelectionTextIntent intent) {
    onCopy();
    return null;
  }
}

/// משחרר את Ctrl+X מעל [SelectionArea] לקריאה בלבד: מבטל רק את ווריאנט
/// הגזירה, ומעביר כל שאר [CopySelectionTextIntent] לפעולת ברירת המחדל.
///
/// יש למקם אותו *מעל* ה-SelectionArea — מנגנון ה-override מאתר override רק
/// כלפי מעלה בעץ. אין צורך בו מתחת ל-[SelectionCopyShortcuts], שכבר מטפל בכך.
class SelectionCutFallthrough extends StatelessWidget {
  const SelectionCutFallthrough({
    super.key,
    required this.child,
    this.copyOverride,
  });

  final Widget child;

  /// מטפל בהעתקה במקום ברירת המחדל; מחזיר false כדי להשאיר אותה לברירת המחדל.
  final bool Function()? copyOverride;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        CopySelectionTextIntent: _CutFallthroughAction(copyOverride),
      },
      child: child,
    );
  }
}

class _CutFallthroughAction extends Action<CopySelectionTextIntent> {
  _CutFallthroughAction(this.copyOverride);

  final bool Function()? copyOverride;

  @override
  bool get isActionEnabled => callingAction?.isActionEnabled ?? true;

  @override
  bool isEnabled(CopySelectionTextIntent intent) {
    if (isReadOnlyCutIntent(intent)) return false;
    return callingAction?.isEnabled(intent) ?? true;
  }

  @override
  Object? invoke(CopySelectionTextIntent intent) {
    if (copyOverride?.call() ?? false) return null;
    return callingAction?.invoke(intent);
  }
}
