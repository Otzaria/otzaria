import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// טבעת פוקוס המקלדת של כפתורים (DD-07): מסגרת primary בעובי
/// [AppTokens.focusRingWidth], במרחק [gap] מחוץ לכפתור.
///
/// הטבעת היא ה-`side` של צורת הכפתור עם `strokeAlign` מעבר ל-1, ולכן היא
/// מצוירת מחוץ לכפתור ולא משנה את גודלו ולא את הפריסה. היא נכנסת דרך ערכות
/// הנושא של הכפתורים ([buttonSide]), ולכן חלה גם על כפתור שקובע `shape` משלו.
///
/// ⚠️ כפתור שקובע `side` משלו (למשל OutlinedButton עם מסגרת מפורשת) דורס
/// את הטבעת, כי ערך של הווידג'ט קודם לערך של ערכת הנושא.
abstract final class AppFocusRing {
  /// המרווח בין הכפתור לטבעת. בלעדיו הטבעת נבלעת בכפתור בצבע primary.
  static const double gap = 2;

  /// המסגרת עצמה: מ-[gap] עד [gap] + [AppTokens.focusRingWidth] מחוץ לצורה.
  static BorderSide side(ColorScheme cs) => BorderSide(
    color: cs.primary,
    width: AppTokens.focusRingWidth,
    strokeAlign:
        BorderSide.strokeAlignOutside + 2 * gap / AppTokens.focusRingWidth,
  );

  /// ה-`side` של ערכות הנושא של הכפתורים. null = צד ברירת המחדל של הכפתור.
  ///
  /// ⚠️ [isKeyboardFocusVisible] נקרא בכל בנייה, גם בלי פוקוס: הקריאה
  /// הראשונה רושמת את המאזינים, והם צריכים להיות רשומים לפני ה-Tab הראשון.
  static WidgetStateProperty<BorderSide?> buttonSide(ColorScheme cs) =>
      WidgetStateProperty.resolveWith((states) {
        final keyboard = isKeyboardFocusVisible;
        return keyboard &&
                states.contains(WidgetState.focused) &&
                !states.contains(WidgetState.disabled)
            ? side(cs)
            : null;
      });

  /// האם האפליקציה במצב ניווט מקלדת: מאז לחיצת העכבר או המגע האחרונה נלחץ
  /// Tab או חץ ([_isNavigationKey]), ו-[FocusManager.highlightMode] הוא
  /// traditional.
  ///
  /// ⚠️ לא מספיק `highlightMode` לבדו: עכבר לא מחליף אותו, ובדסקטופ הוא
  /// traditional מההתחלה. כך כפתור עם autofocus בדיאלוג שנפתח בעכבר היה מקבל
  /// טבעת. גם הקשה אחרת לא מספיקה: דיאלוג שנפתח ב-Delete או בקיצור מקלדת
  /// נפתח בלי טבעת, עד ה-Tab או החץ הראשון.
  static bool get isKeyboardFocusVisible {
    _ensureListening();
    return _lastInputWasKey &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
  }

  static bool _lastInputWasKey = false;
  static FocusManager? _listeningOn;
  static bool _pointerRouteAdded = false;

  /// נרשם מחדש לכל [FocusManager] חדש: סביבת הבדיקות מחליפה אותו בין
  /// בדיקה לבדיקה ומוחקת את המאזינים.
  static void _ensureListening() {
    final manager = FocusManager.instance;
    if (identical(manager, _listeningOn)) return;
    _listeningOn = manager;
    _lastInputWasKey = false;
    manager.addEarlyKeyEventHandler(_onKey);
    if (!_pointerRouteAdded) {
      _pointerRouteAdded = true;
      GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    }
  }

  static KeyEventResult _onKey(KeyEvent event) {
    if (_isNavigationKey(event) && !_lastInputWasKey) {
      _lastInputWasKey = true;
      _rebuildFocusedButton();
    }
    return KeyEventResult.ignored;
  }

  /// הקשה שמזיזה את הפוקוס: Tab (גם Shift+Tab) או חץ. לא נחשבים:
  /// - כל מקש אחר, גם Enter, ‏Delete או Esc, ומקש שינוי לבדו;
  /// - קיצור עם Ctrl, Alt או Meta (Ctrl+Tab מחליף כרטיסייה, Alt+חץ מנווט);
  /// - הקשה מסונתזת, למשל זו ש-Windows שולח למקשים שעדיין לחוצים כשחוזרים
  ///   לחלון ב-Alt+Tab.
  static bool _isNavigationKey(KeyEvent event) {
    if (event is KeyUpEvent || event.synthesized) return false;
    if (!_navigationKeys.contains(event.logicalKey)) return false;
    final keyboard = HardwareKeyboard.instance;
    return !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed;
  }

  static final _navigationKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  static void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent || !_lastInputWasKey) return;
    _lastInputWasKey = false;
    _rebuildFocusedButton();
  }

  /// כניסה למצב המקלדת ויציאה ממנו גם כשהפוקוס נשאר במקומו (למשל לחיצה
  /// במקום ריק): הכפתור הממוקד לא נבנה מחדש בלי שינוי מצב, ולכן הטבעת שלו
  /// הייתה נשארת, או לא מופיעה.
  static void _rebuildFocusedButton() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || !context.mounted) return;
    context.visitAncestorElements((element) {
      if (element.widget is! ButtonStyleButton) return true;
      element.markNeedsBuild();
      return false;
    });
  }
}
