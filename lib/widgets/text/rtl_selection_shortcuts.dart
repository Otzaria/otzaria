import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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
/// זהו באג ידוע ופתוח ב-Flutter עצמו
/// (https://github.com/flutter/flutter/issues/78660,
///  https://github.com/flutter/flutter/issues/144271):
/// ב-[SelectableRegion] מקש Shift+חץ מרחיב/מצמצם את הבחירה לפי הכיוון הלוגי
/// (`forward`) של זרימת הטקסט, **בלי** להתחשב בכיווניות התצוגה. לכן בעברית
/// החצים פועלים הפוך — חץ ימינה מרחיב את הבחירה שמאלה, "כמו באנגלית".
/// לעומת זאת ב-[EditableText] (שדות קלט) Flutter כן מהפך את הכיוון לפי
/// הכיווניות, ולכן אסור לגעת בהם.
///
/// ## הפתרון
/// כל עוד הבאג לא תוקן ב-Flutter, עוטפים את היישום ברמה אחת גבוהה ומיירטים
/// את Shift+חץ. ה-[Action] בודק היכן נמצא הפוקוס:
///   * שדה קלט ([EditableText] / עורך Quill) → מעבירים את הכיוון הלוגי המקורי
///     (Flutter מטפל שם בכיווניות בעצמו) — שמירה על התנהגות תקינה.
///   * אחרת ([SelectableRegion]) → מהפכים את הכיוון לפי המקש הפיזי ומתקנים את
///     הבאג.
///
/// מיירטים אך ורק Shift+חץ (לא חיצים רגילים), כך שאין התנגשות עם ניווט מקלדת.
/// בכיווניות LTR ה-widget שקוף לחלוטין ומחזיר את הילד כמות שהוא.
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
    if (Directionality.maybeOf(context) != TextDirection.rtl) {
      return child;
    }
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

    final inTextInput = _isTextInputContext(focusContext);

    // ב-RTL חץ שמאל פיזי = כיוון "קדימה" (downstream) בזרימת הטקסט.
    // בשדה קלט Flutter כבר מהפך את forward לפי הכיווניות, לכן מעבירים את הכיוון
    // הלוגי המקורי (שמאל→false, ימין→true). ב-SelectableRegion אין היפוך
    // פנימי, לכן מעבירים את הכיוון הפיזי ההפוך (שמאל→true, ימין→false).
    final bool forward =
        inTextInput ? !intent.physicalLeft : intent.physicalLeft;

    final Intent realIntent = intent.word
        ? ExtendSelectionToNextWordBoundaryIntent(
            forward: forward,
            collapseSelection: false,
          )
        : ExtendSelectionByCharacterIntent(
            forward: forward,
            collapseSelection: false,
          );

    return Actions.maybeInvoke(focusContext, realIntent);
  }
}

/// בודק אם ה-context הממוקד שייך לשדה קלט טקסטואלי (כולל עורכי Quill),
/// שבהם Flutter כבר מטפל נכון בכיווניות RTL ואין להפוך את כיוון הבחירה.
bool _isTextInputContext(BuildContext context) {
  if (_isTextInputWidget(context.widget)) {
    return true;
  }
  // סריקת האבות מכסה גם את ה-EditableText העוטף (אם קיים), ולכן אין צורך
  // בקריאה נפרדת ל-findAncestorWidgetOfExactType.
  var found = false;
  context.visitAncestorElements((element) {
    if (_isTextInputWidget(element.widget)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

bool _isTextInputWidget(Widget widget) {
  // כל שדות הקלט הסטנדרטיים (TextField / RtlTextField / CupertinoTextField)
  // בנויים מעל EditableText, ולכן בדיקת `is` מכסה אותם בבטחה — גם ב-Release
  // Mode עם obfuscation, שם שמות מחלקות אינם אמינים.
  if (widget is EditableText) {
    return true;
  }
  // רשת ביטחון עבור עורכי Quill (חבילה חיצונית) שאינם נגזרים מ-EditableText.
  // בדיקת שם המחלקה כמחרוזת עלולה להיכשל תחת obfuscation — ולכן זו fallback
  // בלבד, ולא דרך הזיהוי העיקרית.
  final name = widget.runtimeType.toString();
  return name.contains('QuillRawEditor') ||
      name.contains('RawEditor') ||
      name.contains('QuillEditor');
}
