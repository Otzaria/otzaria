import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/widgets/text/text_input_context.dart';

/// Intent ביניים פנימי: בקשת הרחבת בחירה לפי הכיוון ה*פיזי* של מקש החץ
/// (שמאל/ימין), עוד לפני שמחליטים על הכיוון הלוגי (`forward`).
@immutable
class _PhysicalExtendSelectionIntent extends Intent {
  const _PhysicalExtendSelectionIntent({
    required this.physicalLeft,
    required this.word,
  });

  /// האם נלחץ חץ שמאל (אחרת — חץ ימין).
  final bool physicalLeft;

  /// האם זו הרחבה ברמת מילה (Ctrl/Alt+Shift+חץ) ולא ברמת תו.
  final bool word;
}

/// מתקן את כיוון מקשי Shift+חץ בבחירת טקסט מימין-לשמאל (RTL).
///
/// ## הבעיה
/// שורה של באגים ידועים ופתוחים ב-Flutter עצמו
/// (https://github.com/flutter/flutter/issues/78660,
///  https://github.com/flutter/flutter/issues/127783,
///  https://github.com/flutter/flutter/issues/144271):
/// מקשי Shift+חץ אמורים להרחיב את הבחירה לפי הכיוון ה*פיזי* של המקש, אך
/// ב-RTL Flutter מתבלבל בין הכיוון הפיזי ללוגי. שני ביטויים לבעיה:
///   1. ב-[SelectableRegion] (בחירת טקסט בספרים) Flutter כלל אינו מתחשב
///      בכיווניות — כל מקשי החצים (תו ומילה) פועלים הפוך.
///   2. ב-[EditableText] (שדות קלט) Flutter מתקן את הכיוון ברמת תו אך לא ברמת
///      מילה — ולכן בחירת מילה (Ctrl/Alt+Shift+חץ) יוצאת הפוכה.
///
/// ## הפתרון
/// כל עוד הבאגים לא תוקנו ב-Flutter, עוטפים את היישום ברמה אחת גבוהה ומיירטים
/// את Shift+חץ. ה-[Action] שולח את ה-Intent עם הכיוון הנכון לפי היעד שבפוקוס
/// (ראה [_PhysicalExtendSelectionAction.invoke]). הטיפול מאחד את שני הביטויים
/// לכלל אחד: כמעט תמיד הכיוון הפיזי הוא הנכון, פרט לבחירה ברמת תו בשדה קלט,
/// שבה Flutter כבר מתקן לבד.
///
/// מיירטים אך ורק Shift+חץ (לא חיצים רגילים), כך שאין התנגשות עם ניווט מקלדת.
/// ההחלטה אם לתקן מתקבלת לפי הכיווניות של היעד שבפוקוס, ולכן אזורי LTR בתוך
/// האפליקציה נשארים עם התנהגות ברירת המחדל של Flutter.
class RtlSelectionShortcuts extends StatelessWidget {
  const RtlSelectionShortcuts({super.key, required this.child});

  final Widget child;

  static const Map<ShortcutActivator, Intent> _shortcuts =
      <ShortcutActivator, Intent>{
    // בחירה ברמת תו (Shift+חץ)
    SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
        _PhysicalExtendSelectionIntent(physicalLeft: true, word: false),
    SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
        _PhysicalExtendSelectionIntent(physicalLeft: false, word: false),
    // בחירה ברמת מילה (Ctrl+Shift+חץ — Windows/Linux)
    SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true, control: true):
        _PhysicalExtendSelectionIntent(physicalLeft: true, word: true),
    SingleActivator(LogicalKeyboardKey.arrowRight, shift: true, control: true):
        _PhysicalExtendSelectionIntent(physicalLeft: false, word: true),
    // בחירה ברמת מילה (Alt+Shift+חץ — macOS)
    SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true, alt: true):
        _PhysicalExtendSelectionIntent(physicalLeft: true, word: true),
    SingleActivator(LogicalKeyboardKey.arrowRight, shift: true, alt: true):
        _PhysicalExtendSelectionIntent(physicalLeft: false, word: true),
  };

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          _PhysicalExtendSelectionIntent: _PhysicalExtendSelectionAction(),
        },
        child: child,
      ),
    );
  }
}

/// ממיר בקשת חץ פיזית ל-Intent בחירה אמיתי, עם הכיוון הנכון לפי סוג היעד
/// שבפוקוס (שדה קלט מול אזור בחירה).
class _PhysicalExtendSelectionAction
    extends Action<_PhysicalExtendSelectionIntent> {
  @override
  Object? invoke(_PhysicalExtendSelectionIntent intent) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) {
      return null;
    }

    if (Directionality.maybeOf(focusContext) != TextDirection.rtl) {
      return false;
    }

    final inTextInput = isTextInputContext(focusContext);

    // ב-RTL חץ שמאל פיזי = כיוון "קדימה" (downstream) בזרימת הטקסט, וזה גם
    // ה-forward הנכון כמעט בכל המקרים:
    //   * SelectableRegion (בחירה בספרים) — Flutter כלל אינו מתחשב בכיווניות.
    //   * שדה קלט ברמת מילה — Flutter אינו מהפך כאן את הכיוון (באג flutter#78660
    //     / #127783), כך שבחירת המילה יוצאת הפוכה ללא התיקון.
    // היוצא-דופן היחיד: בחירה ברמת תו בשדה קלט — שם Flutter כבר מהפך את הכיוון
    // נכון לפי הכיווניות, ולכן מעבירים דווקא את הכיוון הלוגי המקורי.
    final bool textFieldCharacter = inTextInput && !intent.word;
    final bool forward =
        textFieldCharacter ? !intent.physicalLeft : intent.physicalLeft;

    final Intent realIntent = intent.word
        ? ExtendSelectionToNextWordBoundaryIntent(
            forward: forward,
            collapseSelection: false,
          )
        : ExtendSelectionByCharacterIntent(
            forward: forward,
            collapseSelection: false,
          );

    final action = Actions.maybeFind<Intent>(
      focusContext,
      intent: realIntent,
    );
    if (action == null) {
      return false;
    }

    final (enabled, _) = Actions.of(focusContext).invokeActionIfEnabled(
      action,
      realIntent,
      focusContext,
    );
    return enabled;
  }

  @override
  KeyEventResult toKeyEventResult(
    _PhysicalExtendSelectionIntent intent,
    Object? invokeResult,
  ) {
    return invokeResult == true
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }
}
