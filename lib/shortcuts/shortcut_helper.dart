import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/shortcuts/key_map.dart';

/// פונקציות עזר לטיפול בקיצורי מקשים.
///
/// מסתמך על [KeyMap] כמקור-האמת היחיד למיפוי שמות מקשים ← [LogicalKeyboardKey].
/// לכל הוספה/שינוי של מקש יש לעדכן רק את [KeyMap].
///
/// **התאמה ל-macOS:** הקיצורים נשמרים בפורמט קנוני (`ctrl+X`) על כל
/// הפלטפורמות, אבל ב-Mac ה-token `ctrl` מתורגם ל-Command (Meta) הן בבדיקה
/// (`matchesShortcut`) והן בתצוגה (`formatShortcutForDisplay`), בהתאם
/// למוסכמת מקלדת Mac. כך ההגדרות נשארות עקביות בין מערכות הפעלה.
class ShortcutHelper {
  ShortcutHelper._();

  // ─── modifiers ────────────────────────────────────────────────────────────────
  static const _modifiers = {'ctrl', 'control', 'shift', 'alt', 'meta'};

  /// האם הפלטפורמה הנוכחית היא macOS — מחושב פעם אחת לבדיקות מהירות.
  /// ב-Web מחזיר false (אין `Platform.isMacOS`).
  static bool get _isMac => !kIsWeb && Platform.isMacOS;

  /// במקלדת Mac המוסכמה היא Command, לכן ה-token הקנוני `ctrl` בקיצור
  /// נבדק/מוצג כ-Meta. שאר הפלטפורמות משתמשות ב-Control כרגיל.
  ///
  /// `null` = השתמש בערך המחושב מ-[Platform.isMacOS] (ברירת המחדל בייצור).
  /// `true` / `false` = override בבדיקות יחידה כדי לבדוק שני המסלולים בלי
  /// תלות בפלטפורמת הריצה.
  @visibleForTesting
  static bool? isMacForTesting;

  static bool get _treatCtrlAsMeta => isMacForTesting ?? _isMac;

  /// בודק אם האירוע [event] תואם להגדרת הקיצור [shortcutSetting].
  ///
  /// [shortcutSetting] הוא מחרוזת כגון `'ctrl+shift+f'`, `'f11'`, `'ctrl+comma'`.
  /// הפרמטרים האופציונליים מאפשרים בדיקות יחידה מבלי להסתמך על מצב חומרה אמיתי.
  static bool matchesShortcut(
    KeyEvent event,
    String shortcutSetting, {
    bool? isControlPressed,
    bool? isShiftPressed,
    bool? isAltPressed,
    bool? isMetaPressed,
  }) {
    if (event is! KeyDownEvent) return false;

    final parts = shortcutSetting.toLowerCase().split('+');
    final hasCtrlToken = parts.contains('ctrl') || parts.contains('control');
    final hasMetaToken = parts.contains('meta');
    final requiresShift = parts.contains('shift');
    final requiresAlt = parts.contains('alt');

    // ב-Mac גם `ctrl` וגם `meta` בקיצור שמור משויכים לפעולת Command. מצב
    // מקש Control הפיזי לא נבדק כלל — מאחד את הסמנטיקה ומונע אי-עקביות
    // בקיצור `ctrl+meta+X` (שאם נבדק כפשוטו היה נשבר).
    final requiresCtrl = _treatCtrlAsMeta ? null : hasCtrlToken;
    final requiresMeta = _treatCtrlAsMeta
        ? (hasMetaToken || hasCtrlToken)
        : hasMetaToken;

    // בדיקת modifiers
    final controlPressed =
        isControlPressed ?? HardwareKeyboard.instance.isControlPressed;
    final shiftPressed =
        isShiftPressed ?? HardwareKeyboard.instance.isShiftPressed;
    final altPressed = isAltPressed ?? HardwareKeyboard.instance.isAltPressed;
    final metaPressed =
        isMetaPressed ?? HardwareKeyboard.instance.isMetaPressed;

    if (requiresCtrl != null && requiresCtrl != controlPressed) {
      return false;
    }
    if (requiresShift != shiftPressed) {
      return false;
    }
    if (requiresAlt != altPressed) return false;
    if (requiresMeta != metaPressed) return false;

    // מציאת המקש הראשי (לא modifier)
    final mainKey = parts.where((p) => !_modifiers.contains(p)).firstOrNull;
    if (mainKey == null) return false;

    // אות יחידה (a–z) — בודקים לפי physicalKey כדי לתמוך
    // בפריסות מקלדת לא-לטיניות (כגון עברית) שבהן logicalKey שונה.
    if (mainKey.length == 1 &&
        mainKey.codeUnitAt(0) >= 97 &&
        mainKey.codeUnitAt(0) <= 122) {
      final letterOffset = mainKey.codeUnitAt(0) - 97;
      return event.physicalKey ==
          PhysicalKeyboardKey(
            PhysicalKeyboardKey.keyA.usbHidUsage + letterOffset,
          );
    }

    // חיפוש ב-KeyMap (ספרות, מקשים מיוחדים, חצים, F-keys וכו׳)
    final expectedKey = KeyMap.keyFor(mainKey);
    return expectedKey != null && event.logicalKey == expectedKey;
  }

  /// האם [shortcut] ניתן לזיהוי בפועל — כלומר המקש הראשי שבו מוכר ל-
  /// [matchesShortcut]. קיצור ריק תקין (פעולה ללא קיצור).
  ///
  /// קיצור שהוקלט בפריסה לא-לטינית לפני שההקלטה נורמלה נשמר עם התו המקומי
  /// (`ctrl+shift+כ`) ולכן לעולם אינו נתפס — כזה מוחזר כאן כלא-מוכר.
  static bool isRecognized(String shortcut) {
    if (shortcut.isEmpty) return true;

    final parts = shortcut.toLowerCase().split('+');
    final mainKey = parts.where((p) => !_modifiers.contains(p)).firstOrNull;
    if (mainKey == null) return false;

    if (mainKey.length == 1 &&
        mainKey.codeUnitAt(0) >= 97 &&
        mainKey.codeUnitAt(0) <= 122) {
      return true;
    }

    return KeyMap.keyFor(mainKey) != null;
  }

  /// מחזיר את המקש הלוגי שיש לשמור עבור [event].
  ///
  /// בפריסה לא-לטינית `logicalKey` של מקש אות הוא התו המקומי (למשל `'כ'`),
  /// שאינו ניתן להשוואה ב-[matchesShortcut] — לכן מקשי אות מתורגמים למקש
  /// הלטיני לפי מיקומם הפיזי, בסימטריה מלאה לבדיקת ה-physicalKey שם.
  static LogicalKeyboardKey logicalKeyToStore(KeyEvent event) {
    final letterOffset =
        event.physicalKey.usbHidUsage - PhysicalKeyboardKey.keyA.usbHidUsage;
    if (letterOffset >= 0 && letterOffset <= 25) {
      return LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + letterOffset);
    }
    return event.logicalKey;
  }

  /// ממיר קבוצה של [LogicalKeyboardKey] למחרוזת קיצור (כגון `'ctrl+shift+f'`).
  ///
  /// ב-Mac, לחיצה על מקש Command נשמרת כ-`ctrl` בפורמט הקנוני, כך שאותו
  /// קיצור עובד בכל הפלטפורמות. אם המשתמש לוחץ במפורש גם על Control וגם
  /// על Command (תרחיש נדיר), שני ה-tokens נשמרים בנפרד (`ctrl+meta+X`).
  static String formatKeysToShortcut(Set<LogicalKeyboardKey> keys) {
    if (keys.isEmpty) return '';

    final List<String> parts = [];
    bool hasCtrl = false;
    bool hasShift = false;
    bool hasAlt = false;
    bool hasMeta = false;
    String? mainKey;

    for (final key in keys) {
      if (key == LogicalKeyboardKey.control ||
          key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight) {
        hasCtrl = true;
      } else if (key == LogicalKeyboardKey.shift ||
          key == LogicalKeyboardKey.shiftLeft ||
          key == LogicalKeyboardKey.shiftRight) {
        hasShift = true;
      } else if (key == LogicalKeyboardKey.alt ||
          key == LogicalKeyboardKey.altLeft ||
          key == LogicalKeyboardKey.altRight) {
        hasAlt = true;
      } else if (key == LogicalKeyboardKey.meta ||
          key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight) {
        hasMeta = true;
      } else {
        mainKey = getKeyLabel(key);
      }
    }

    // ב-Mac גם Cmd וגם Control מתורגמים לאותו token קנוני `ctrl`. זה שומר
    // על תאימות בין-פלטפורמות (אותו `ctrl+f` עובד בכל מערכת) ומונע יצירת
    // `ctrl+meta+X` משעמם — שתי הצורות נחשבות שוות-ערך ב-Mac.
    if (_treatCtrlAsMeta && (hasMeta || hasCtrl)) {
      hasCtrl = true;
      hasMeta = false;
    }

    if (hasCtrl) parts.add('ctrl');
    if (hasShift) parts.add('shift');
    if (hasAlt) parts.add('alt');
    if (hasMeta) parts.add('meta');
    if (mainKey != null) parts.add(mainKey);

    return parts.join('+');
  }

  /// מחזיר את שם המחרוזת של [key] לצורכי שמירה/ניתוח.
  ///
  /// עבור אותיות מחזיר תו בודד (e.g. `'f'`).
  /// עבור שאר המקשים מסתמך על [KeyMap.labelFor].
  static String getKeyLabel(LogicalKeyboardKey key) {
    // אותיות (a–z / A–Z)
    final label = key.keyLabel;
    if (label.length == 1 && label.toLowerCase() != label.toUpperCase()) {
      return label.toLowerCase();
    }

    // חיפוש ב-KeyMap
    return KeyMap.labelFor(key) ?? label.toLowerCase();
  }

  /// מעצב את [shortcut] לתצוגה ידידותית (`'ctrl+f'` → `'CTRL + F'`).
  ///
  /// ב-macOS גם `ctrl` וגם `meta` מוצגים כ-`⌘` — שניהם משויכים לפעולת
  /// Command בפועל (ראה [matchesShortcut] ו-[activatorFromShortcut]), ולכן
  /// המוצג חייב להיות עקבי עם ההתנהגות. `alt` מוצג כ-`⌥`, `shift` כ-`⇧`.
  /// בשאר הפלטפורמות נשמרת התצוגה הקלאסית `CTRL + X`.
  static String formatShortcutForDisplay(String shortcut) {
    final String formatted;
    if (_treatCtrlAsMeta) {
      formatted = shortcut
          .replaceAll('ctrl+', '⌘ + ')
          .replaceAll('control+', '⌘ + ')
          .replaceAll('meta+', '⌘ + ')
          .replaceAll('shift+', '⇧ + ')
          .replaceAll('alt+', '⌥ + ')
          .toUpperCase();
    } else {
      formatted = shortcut
          .replaceAll('ctrl+', 'CTRL + ')
          .replaceAll('shift+', 'SHIFT + ')
          .replaceAll('alt+', 'ALT + ')
          .replaceAll('meta+', 'WIN + ')
          .toUpperCase();
    }
    return _prettifyKeyTokens(formatted);
  }

  /// ממיר שמות מקשי ניווט מילוליים (אחרי uppercase) לסמלים/תוויות קריאות,
  /// כדי שקיצור כמו `alt+arrowup` יוצג כ-`ALT + ↑` ולא `ALT + ARROWUP`.
  static String _prettifyKeyTokens(String display) => display
      .replaceAll('ARROWUP', '↑')
      .replaceAll('ARROWDOWN', '↓')
      .replaceAll('ARROWLEFT', '←')
      .replaceAll('ARROWRIGHT', '→')
      .replaceAll('PAGEUP', 'Page Up')
      .replaceAll('PAGEDOWN', 'Page Down');

  /// ממיר מחרוזת קיצור (כגון `'ctrl+f'`) ל-[ShortcutActivator].
  ///
  /// מחזיר [SingleActivator] עם modifiers מתאימים.
  /// אם המחרוזת אינה ניתנת לניתוח, מחזיר `null`.
  ///
  /// ב-Mac ה-token `ctrl` ממופה ל-`meta: true` כדי שמתפעלי קיצור (Flutter
  /// `Shortcuts` widget) יזהו לחיצת Command.
  static ShortcutActivator? activatorFromShortcut(String shortcut) {
    final parts = shortcut.toLowerCase().split('+');
    final hasCtrlToken = parts.contains('ctrl') || parts.contains('control');
    final hasMetaToken = parts.contains('meta');
    final hasShift = parts.contains('shift');
    final hasAlt = parts.contains('alt');

    final bool useControl;
    final bool useMeta;
    if (_treatCtrlAsMeta) {
      useControl = false;
      useMeta = hasCtrlToken || hasMetaToken;
    } else {
      useControl = hasCtrlToken;
      useMeta = hasMetaToken;
    }

    final mainKeyName = parts.where((p) => !_modifiers.contains(p)).firstOrNull;
    if (mainKeyName == null) return null;

    LogicalKeyboardKey? logicalKey;
    if (mainKeyName.length == 1) {
      final code = mainKeyName.codeUnitAt(0);
      if (code >= 97 && code <= 122) {
        logicalKey = LogicalKeyboardKey(0x00000061 + (code - 97));
      }
    }
    logicalKey ??= KeyMap.keyFor(mainKeyName);
    if (logicalKey == null) return null;

    return SingleActivator(
      logicalKey,
      control: useControl,
      shift: hasShift,
      alt: hasAlt,
      meta: useMeta,
    );
  }
}
