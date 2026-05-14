import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:otzaria/shortcuts/key_map.dart';

/// פונקציות עזר לטיפול בקיצורי מקשים.
///
/// מסתמך על [KeyMap] כמקור-האמת היחיד למיפוי שמות מקשים ← [LogicalKeyboardKey].
/// לכל הוספה/שינוי של מקש יש לעדכן רק את [KeyMap].
class ShortcutHelper {
  ShortcutHelper._();

  // ─── modifiers ────────────────────────────────────────────────────────────────
  static const _modifiers = {'ctrl', 'control', 'shift', 'alt', 'meta'};

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
    final requiresCtrl = parts.contains('ctrl') || parts.contains('control');
    final requiresShift = parts.contains('shift');
    final requiresAlt = parts.contains('alt');
    final requiresMeta = parts.contains('meta');

    // בדיקת modifiers
    final controlPressed =
        isControlPressed ?? HardwareKeyboard.instance.isControlPressed;
    final shiftPressed =
        isShiftPressed ?? HardwareKeyboard.instance.isShiftPressed;
    final altPressed = isAltPressed ?? HardwareKeyboard.instance.isAltPressed;
    final metaPressed =
        isMetaPressed ?? HardwareKeyboard.instance.isMetaPressed;

    if (requiresCtrl != controlPressed) {
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
              PhysicalKeyboardKey.keyA.usbHidUsage + letterOffset);
    }

    // חיפוש ב-KeyMap (ספרות, מקשים מיוחדים, חצים, F-keys וכו׳)
    final expectedKey = KeyMap.keyFor(mainKey);
    return expectedKey != null && event.logicalKey == expectedKey;
  }

  /// ממיר קבוצה של [LogicalKeyboardKey] למחרוזת קיצור (כגון `'ctrl+shift+f'`).
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
  static String formatShortcutForDisplay(String shortcut) {
    return shortcut
        .replaceAll('ctrl+', 'CTRL + ')
        .replaceAll('shift+', 'SHIFT + ')
        .replaceAll('alt+', 'ALT + ')
        .replaceAll('meta+', 'WIN + ')
        .toUpperCase();
  }

  /// ממיר מחרוזת קיצור (כגון `'ctrl+f'`) ל-[ShortcutActivator].
  ///
  /// מחזיר [SingleActivator] עם modifiers מתאימים.
  /// אם המחרוזת אינה ניתנת לניתוח, מחזיר `null`.
  static ShortcutActivator? activatorFromShortcut(String shortcut) {
    final parts = shortcut.toLowerCase().split('+');
    final hasCtrl = parts.contains('ctrl') || parts.contains('control');
    final hasShift = parts.contains('shift');
    final hasAlt = parts.contains('alt');
    final hasMeta = parts.contains('meta');

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
      control: hasCtrl,
      shift: hasShift,
      alt: hasAlt,
      meta: hasMeta,
    );
  }
}
