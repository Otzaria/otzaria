import 'package:flutter/widgets.dart' show ShortcutActivator, SingleActivator;
import 'package:flutter/services.dart';
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
    final metaPressed = isMetaPressed ?? HardwareKeyboard.instance.isMetaPressed;

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

    // אות יחידה (a–z)
    final pressedKeyLabel = event.logicalKey.keyLabel.toLowerCase();
    if (mainKey.length == 1 &&
        mainKey.codeUnitAt(0) >= 97 &&
        mainKey.codeUnitAt(0) <= 122) {
      return pressedKeyLabel == mainKey;
    }

    // חיפוש ב-KeyMap (ספרות, מקשים מיוחדים, חצים, F-keys וכו׳)
    final expectedKey = KeyMap.keyFor(mainKey);
    return expectedKey != null && event.logicalKey == expectedKey;
  }

  /// ממיר מחרוזת קיצור (כגון `'ctrl+f'`) ל-[SingleActivator].
  static ShortcutActivator? activatorFromShortcut(String shortcutSetting) {
    final parts = shortcutSetting.toLowerCase().split('+');
    final requiresCtrl = parts.contains('ctrl') || parts.contains('control');
    final requiresShift = parts.contains('shift');
    final requiresAlt = parts.contains('alt');
    final requiresMeta = parts.contains('meta');

    final mainKeyLabel = parts.where((p) => !_modifiers.contains(p)).firstOrNull;
    if (mainKeyLabel == null || mainKeyLabel.isEmpty) {
      return null;
    }

    final mainKey = KeyMap.keyFor(mainKeyLabel.trim());
    if (mainKey == null) {
      return null;
    }

    return SingleActivator(
      mainKey,
      control: requiresCtrl,
      shift: requiresShift,
      alt: requiresAlt,
      meta: requiresMeta,
    );
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
}
