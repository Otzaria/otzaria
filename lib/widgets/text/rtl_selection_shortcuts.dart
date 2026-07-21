import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// דגל "priming" פעיל: בזמן שהוא true, שינויי הבחירה הם זמניים (פקודות-הכנה
/// לנעילת קצה ה-focus) ואין לעבד אותם ב-`onSelectionChanged` של האפליקציה
/// (שמירת טקסט/סנכרון/prefetch). מטפלי הבחירה בודקים אותו ויוצאים מוקדם.
bool rtlSelectionPriming = false;

// --- מעקב כיוון גרירת הבחירה (לזיהוי קצה ה-focus) ---
// `selectionEndpoints` הציבורי ממיין לפי Y, ולכן בבחירה רב-שורתית אי אפשר
// לדעת מתוכו מי ה-base ומי ה-extent (כיוון הגרירה). לכן עוקבים אחר היסטוריית
// הטקסט הנבחר: הצד שבו הבחירה גדלה/התכווצה הוא קצה ה-focus.
String? _rtlLastSel;
bool? _rtlReversed; // האם ה-focus גדל בקצה ה*סוף* של המחרוזת (offset גבוה).

/// הסקת כיוון הגרירה האחרון: true = ה-focus בקצה הסוף (offset גבוה),
/// false = ה-focus בקצה ההתחלה (offset נמוך), null = לא ידוע.
bool? get rtlInferredReversed => _rtlReversed;

/// מעדכן את ה-tracker לפי שינוי בחירה אמיתי (לא priming).
void trackRtlSelection(String? text) {
  if (rtlSelectionPriming) return;
  final t = text ?? '';
  final last = _rtlLastSel ?? '';
  if (t.isEmpty) {
    _rtlLastSel = '';
    _rtlReversed = null;
    return;
  }
  if (last.isEmpty || t == last) {
    _rtlLastSel = t;
    return;
  }
  if (t.length > last.length) {
    if (t.startsWith(last)) {
      _rtlReversed = true; // גדל בסוף
    } else if (t.endsWith(last)) {
      _rtlReversed = false; // גדל בהתחלה
    } else {
      _rtlReversed = null;
    }
  } else if (last.length > t.length) {
    if (last.startsWith(t)) {
      _rtlReversed = true; // התכווץ מהסוף → focus בסוף
    } else if (last.endsWith(t)) {
      _rtlReversed = false; // התכווץ מההתחלה → focus בהתחלה
    } else {
      _rtlReversed = null;
    }
  } else {
    _rtlReversed = null;
  }
  _rtlLastSel = t;
}

// זהות אזור הבחירה (SelectableRegionState) האחרון שעליו פעל ה-Action. ה-tracker
// הוא גלובלי, ולכן כיוון גרירה שנשאר מאזור אחד עלול לזהם בחירה רב-שורתית באזור
// אחר. שומרים הפניה חלשה (לא מעכבים GC) ומאפסים את ה-tracker כשהאזור משתנה.
WeakReference<Object>? _rtlLastRegion;

/// מאפס את ה-tracker אם אזור הבחירה הממוקד שונה מהאזור הקודם — מונע זליגת
/// כיוון גרירה בין SelectionArea-ים שונים.
void _resetRtlTrackerIfRegionChanged(Object region) {
  if (!identical(_rtlLastRegion?.target, region)) {
    _rtlReversed = null;
    _rtlLastSel = null;
    _rtlLastRegion = WeakReference<Object>(region);
  }
}

/// Intent ביניים: בקשת הרחבת בחירה לפי הכיוון ה*פיזי* של מקש החץ
/// (שמאל/ימין), לפני הכרעת הכיוון הלוגי (`forward`).
@immutable
class _PhysicalExtendSelectionIntent extends Intent {
  const _PhysicalExtendSelectionIntent({
    required this.physicalLeft,
    required this.word,
    this.collapse = false,
  });

  /// האם נלחץ חץ שמאל (אחרת — חץ ימין).
  final bool physicalLeft;

  /// האם זו פעולה ברמת מילה (Ctrl/Alt+חץ) ולא ברמת תו.
  final bool word;

  /// true = הזזת סמן בלי Shift (הבחירה מתכווצת), false = הרחבת בחירה.
  final bool collapse;
}

/// מתקן את כיוון מקשי Shift+חץ בבחירת טקסט RTL.
///
/// רקע: ב-`SelectableRegion` של Flutter מקשי החצים אינם מתחשבים בכיווניות
/// (flutter/flutter#78660 ואחרים). מיירטים Shift+חץ (הרחבת בחירה) וגם
/// Ctrl/Alt+חץ בלי Shift (הזזת סמן מילה). ב-LTR ה-widget שקוף.
class RtlSelectionShortcuts extends StatelessWidget {
  const RtlSelectionShortcuts({super.key, required this.child});

  final Widget child;

  static const Map<ShortcutActivator, Intent> _charShortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
            _PhysicalExtendSelectionIntent(physicalLeft: true, word: false),
        SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
            _PhysicalExtendSelectionIntent(physicalLeft: false, word: false),
      };

  // רמת מילה: Ctrl ב-Windows/Linux, Alt ב-macOS/iOS — תואם למיפוי הפלטפורמה
  // של Flutter (ב-Windows/Linux Alt+חץ שמור לקפיצת שורה ואסור לדרוס אותו).
  static const Map<ShortcutActivator, Intent>
  _ctrlWordShortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true, control: true):
        _PhysicalExtendSelectionIntent(physicalLeft: true, word: true),
    SingleActivator(LogicalKeyboardKey.arrowRight, shift: true, control: true):
        _PhysicalExtendSelectionIntent(physicalLeft: false, word: true),
    SingleActivator(
      LogicalKeyboardKey.arrowLeft,
      control: true,
    ): _PhysicalExtendSelectionIntent(
      physicalLeft: true,
      word: true,
      collapse: true,
    ),
    SingleActivator(
      LogicalKeyboardKey.arrowRight,
      control: true,
    ): _PhysicalExtendSelectionIntent(
      physicalLeft: false,
      word: true,
      collapse: true,
    ),
  };

  static const Map<ShortcutActivator, Intent> _altWordShortcuts =
      <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true, alt: true):
            _PhysicalExtendSelectionIntent(physicalLeft: true, word: true),
        SingleActivator(LogicalKeyboardKey.arrowRight, shift: true, alt: true):
            _PhysicalExtendSelectionIntent(physicalLeft: false, word: true),
        SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          alt: true,
        ): _PhysicalExtendSelectionIntent(
          physicalLeft: true,
          word: true,
          collapse: true,
        ),
        SingleActivator(
          LogicalKeyboardKey.arrowRight,
          alt: true,
        ): _PhysicalExtendSelectionIntent(
          physicalLeft: false,
          word: true,
          collapse: true,
        ),
      };

  static final Map<ShortcutActivator, Intent> _shortcuts =
      <ShortcutActivator, Intent>{
        ..._charShortcuts,
        ...(defaultTargetPlatform == TargetPlatform.macOS ||
                defaultTargetPlatform == TargetPlatform.iOS
            ? _altWordShortcuts
            : _ctrlWordShortcuts),
      };

  @override
  Widget build(BuildContext context) {
    // קיצור-דרך: בתת-עץ LTR לחלוטין אין צורך להתקין Shortcuts. ההכרעה
    // הסופית לכל לחיצה נעשית לפי כיווניות ה*יעד הממוקד* (ראו ה-Action), כך
    // שאזור LTR מקונן בתוך wrapper RTL לא יקבל לוגיקת RTL.
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

class _PhysicalExtendSelectionAction
    extends Action<_PhysicalExtendSelectionIntent> {
  /// סימון "טיפלנו": מוחזר כאשר ניגשנו ליעד בחירה אמיתי (שדה קלט או
  /// SelectableRegion), גם אם הפעולה הפנימית החזירה null. מאפשר ל-
  /// [toKeyEventResult] להבדיל בין "טיפלנו" (בלע את המקש) לבין "אין יעד"
  /// (משחרר את המקש להמשך טיפול במעלה העץ).
  static const Object _handled = Object();

  @override
  Object? invoke(_PhysicalExtendSelectionIntent intent) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) {
      return null;
    }

    // ההכרעה לפי כיווניות ה*יעד הממוקד*, לא לפי מיקום ה-wrapper. אזור LTR
    // מקונן בתוך wrapper RTL לא יקבל לוגיקת RTL — נשחרר את המקש לברירת המחדל.
    if (Directionality.maybeOf(focusContext) != TextDirection.rtl) {
      return null;
    }

    // --- שדה קלט (EditableText/Quill) ---
    // ברמת תו Flutter כבר מהפך נכון לפי כיווניות → כיוון לוגי מקורי. ברמת
    // מילה Flutter אינו מהפך (באג) → מהפכים.
    if (_isTextInputContext(focusContext)) {
      final forward = intent.word ? intent.physicalLeft : !intent.physicalLeft;
      _dispatch(
        focusContext,
        word: intent.word,
        forward: forward,
        collapse: intent.collapse,
      );
      return _handled;
    }

    final state = focusContext.findAncestorStateOfType<SelectableRegionState>();
    if (state == null) {
      // אין EditableText ואין SelectableRegion — אין מה להרחיב; אל תבלע את
      // המקש (כדי לא לחסום גלילה/קיצורים אחרים במעלה העץ).
      return null;
    }

    // ב-SelectableRegion אין סמן — הפריימוורק מתעלם מ-collapseSelection
    // והפעולה תמיד מרחיבה, ולכן ממשיכים למסלול ה-priming הרגיל.

    // איפוס ה-tracker הגלובלי בעת מעבר בין אזורי בחירה — כיוון גרירה שנשאר
    // מאזור קודם לא יזהם בחירה רב-שורתית באזור הנוכחי.
    _resetRtlTrackerIfRegionChanged(state);

    final geo = _selectionGeometry(state);
    if (geo == null) {
      // יש SelectableRegion אך אין בחירה פעילה — היפוך פשוט.
      _dispatch(focusContext, word: intent.word, forward: intent.physicalLeft);
      return _handled;
    }

    // --- SelectableRegion: priming ---
    // צריך "לנעול" קודם את קצה ה-focus (extent), ואז להזיז אותו בכיוון הויזואלי.
    // הפריימוורק קובע isEnd = forward != isReversed, כאשר isReversed גאומטרי:
    // בשורה-אחת לפי X, ברב-שורתי לפי Y. כדי לנעול את ה-extent צריך
    // forward = !isReversed.
    //
    // [myReversed] = האם ה-focus בקצה הסוף של המחרוזת (offset גבוה).
    // הקשר ל-isReversed הגאומטרי: בשורה-אחת isReversed==myReversed; ברב-שורתי
    // isReversed==!myReversed (כי שם ההכרעה לפי Y).
    //
    // בשורה-אחת מעדיפים את הגאומטריה ה**מקומית** של האזור הנוכחי
    // (`geo.reversed`) — אמינה ולא מושפעת ממצב גלובלי של אזור אחר. רק
    // ברב-שורתי, שם `selectionEndpoints` ממיין לפי Y ומאבד את כיוון הגרירה,
    // נופלים ל-tracker הגלובלי (שאופס לעיל אם האזור התחלף).
    final bool myReversed;
    if (geo.multiLine) {
      myReversed = rtlInferredReversed ?? true;
    } else {
      myReversed = geo.reversed;
    }
    final frameworkReversed = geo.multiLine ? !myReversed : myReversed;
    final lockForward = !frameworkReversed;

    rtlSelectionPriming = true;
    _dispatch(focusContext, word: false, forward: lockForward); // נעילת extent
    _dispatch(focusContext, word: false, forward: !lockForward); // שחזור
    rtlSelectionPriming = false;
    _dispatch(focusContext, word: intent.word, forward: intent.physicalLeft);
    return _handled;
  }

  @override
  KeyEventResult toKeyEventResult(
    _PhysicalExtendSelectionIntent intent,
    Object? invokeResult,
  ) {
    // בלע את המקש רק אם באמת טיפלנו ביעד בחירה; אחרת השאר ignored כדי
    // ש-Shortcuts/ברירת המחדל במעלה העץ יוכלו לטפל בו.
    return identical(invokeResult, _handled)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  Object? _dispatch(
    BuildContext context, {
    required bool word,
    required bool forward,
    bool collapse = false,
  }) {
    final Intent intent = word
        ? ExtendSelectionToNextWordBoundaryIntent(
            forward: forward,
            collapseSelection: collapse,
          )
        : ExtendSelectionByCharacterIntent(
            forward: forward,
            collapseSelection: collapse,
          );
    return Actions.maybeInvoke(context, intent);
  }

  /// גאומטריית הבחירה הנוכחית ב-[SelectableRegion] הממוקד, מתוך
  /// [SelectableRegionState.selectionEndpoints] (getter ציבורי המחזיר
  /// `[base, extent]` — ממוין רק לפי Y).
  ///
  /// - [multiLine]: הקצוות בגבהים שונים (הפרש Y משמעותי).
  /// - [reversed]: בשורה-אחת, האם ה-base נמצא ימינה מה-extent (גרירה "קדימה",
  ///   מהסוף להתחלה). נגזר מהשוואת X של שני הקצוות (שב-single-line נשמרים
  ///   בסדר base→extent). חסר משמעות ב-multiLine (ה-getter ממיין לפי Y).
  ///
  /// מחזיר null כשאין בחירה פעילה או שאי אפשר לקבוע.
  ({bool multiLine, bool reversed})? _selectionGeometry(
    SelectableRegionState state,
  ) {
    try {
      final points = state.selectionEndpoints;
      if (points.length < 2) return null;
      final base = points.first.point;
      final extent = points.last.point;
      if ((base.dy - extent.dy).abs() > 1.0) {
        return (multiLine: true, reversed: false);
      }
      return (multiLine: false, reversed: base.dx > extent.dx);
    } catch (_) {
      // selectionEndpoints זורק כשאין בחירה פעילה.
      return null;
    }
  }
}

bool _isTextInputContext(BuildContext context) {
  if (context.widget is EditableText) return true;
  var found = false;
  context.visitAncestorElements((element) {
    if (element.widget is EditableText) {
      found = true;
      return false;
    }
    final name = element.widget.runtimeType.toString();
    if (name.contains('RawEditor') || name.contains('QuillEditor')) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}
