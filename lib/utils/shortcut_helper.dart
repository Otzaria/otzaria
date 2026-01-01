import 'package:flutter/services.dart';

/// Helper functions for keyboard shortcut matching
class ShortcutHelper {
  /// בודק אם הקיצור שנלחץ תואם להגדרה
  static bool matchesShortcut(KeyEvent event, String shortcutSetting) {
    if (event is! KeyDownEvent) return false;

    final parts = shortcutSetting.toLowerCase().split('+');
    final requiresCtrl = parts.contains('ctrl') || parts.contains('control');
    final requiresShift = parts.contains('shift');
    final requiresAlt = parts.contains('alt');

    // בדיקת modifiers
    if (requiresCtrl != HardwareKeyboard.instance.isControlPressed) {
      return false;
    }
    if (requiresShift != HardwareKeyboard.instance.isShiftPressed) {
      return false;
    }
    if (requiresAlt != HardwareKeyboard.instance.isAltPressed) return false;

    // מציאת המקש הראשי (לא modifier)
    final mainKey = parts
        .where((p) =>
            p != 'ctrl' &&
            p != 'control' &&
            p != 'shift' &&
            p != 'alt' &&
            p != 'meta')
        .firstOrNull;

    if (mainKey == null) return false;

    // מיפוי שם המקש ל-LogicalKeyboardKey
    final pressedKeyLabel = event.logicalKey.keyLabel.toLowerCase();

    // בדיקת אותיות
    if (mainKey.length == 1 &&
        mainKey.codeUnitAt(0) >= 97 &&
        mainKey.codeUnitAt(0) <= 122) {
      return pressedKeyLabel == mainKey;
    }

    // בדיקת מספרים
    if (mainKey.length == 1 &&
        mainKey.codeUnitAt(0) >= 48 &&
        mainKey.codeUnitAt(0) <= 57) {
      return event.logicalKey == _digitKeyFromChar(mainKey);
    }

    // בדיקת מקשים מיוחדים
    return _matchesSpecialKey(event.logicalKey, mainKey);
  }

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
        // מקש ראשי
        mainKey = getKeyLabel(key);
      }
    }

    // בניית המחרוזת לפי סדר: ctrl, shift, alt, meta, mainKey
    if (hasCtrl) parts.add('ctrl');
    if (hasShift) parts.add('shift');
    if (hasAlt) parts.add('alt');
    if (hasMeta) parts.add('meta');
    if (mainKey != null) parts.add(mainKey);

    return parts.join('+');
  }

  static String getKeyLabel(LogicalKeyboardKey key) {
    // אותיות
    if (key.keyLabel.length == 1 &&
        key.keyLabel.toLowerCase() != key.keyLabel.toUpperCase()) {
      return key.keyLabel.toLowerCase();
    }

    // מספרים
    if (key == LogicalKeyboardKey.digit0) return '0';
    if (key == LogicalKeyboardKey.digit1) return '1';
    if (key == LogicalKeyboardKey.digit2) return '2';
    if (key == LogicalKeyboardKey.digit3) return '3';
    if (key == LogicalKeyboardKey.digit4) return '4';
    if (key == LogicalKeyboardKey.digit5) return '5';
    if (key == LogicalKeyboardKey.digit6) return '6';
    if (key == LogicalKeyboardKey.digit7) return '7';
    if (key == LogicalKeyboardKey.digit8) return '8';
    if (key == LogicalKeyboardKey.digit9) return '9';

    // מקשים מיוחדים
    if (key == LogicalKeyboardKey.comma) return 'comma';
    if (key == LogicalKeyboardKey.period) return 'period';
    if (key == LogicalKeyboardKey.slash) return 'slash';
    if (key == LogicalKeyboardKey.backslash) return 'backslash';
    if (key == LogicalKeyboardKey.semicolon) return 'semicolon';
    if (key == LogicalKeyboardKey.quote) return 'quote';
    if (key == LogicalKeyboardKey.bracketLeft) return 'bracketleft';
    if (key == LogicalKeyboardKey.bracketRight) return 'bracketright';
    if (key == LogicalKeyboardKey.minus) return 'minus';
    if (key == LogicalKeyboardKey.equal) return 'equal';
    if (key == LogicalKeyboardKey.space) return 'space';
    if (key == LogicalKeyboardKey.tab) return 'tab';
    if (key == LogicalKeyboardKey.enter) return 'enter';
    if (key == LogicalKeyboardKey.backspace) return 'backspace';
    if (key == LogicalKeyboardKey.delete) return 'delete';
    if (key == LogicalKeyboardKey.escape) return 'escape';
    if (key == LogicalKeyboardKey.arrowUp) return 'arrowup';
    if (key == LogicalKeyboardKey.arrowDown) return 'arrowdown';
    if (key == LogicalKeyboardKey.arrowLeft) return 'arrowleft';
    if (key == LogicalKeyboardKey.arrowRight) return 'arrowright';
    if (key == LogicalKeyboardKey.home) return 'home';
    if (key == LogicalKeyboardKey.end) return 'end';
    if (key == LogicalKeyboardKey.pageUp) return 'pageup';
    if (key == LogicalKeyboardKey.pageDown) return 'pagedown';

    // F keys
    if (key == LogicalKeyboardKey.f1) return 'f1';
    if (key == LogicalKeyboardKey.f2) return 'f2';
    if (key == LogicalKeyboardKey.f3) return 'f3';
    if (key == LogicalKeyboardKey.f4) return 'f4';
    if (key == LogicalKeyboardKey.f5) return 'f5';
    if (key == LogicalKeyboardKey.f6) return 'f6';
    if (key == LogicalKeyboardKey.f7) return 'f7';
    if (key == LogicalKeyboardKey.f8) return 'f8';
    if (key == LogicalKeyboardKey.f9) return 'f9';
    if (key == LogicalKeyboardKey.f10) return 'f10';
    if (key == LogicalKeyboardKey.f11) return 'f11';
    if (key == LogicalKeyboardKey.f12) return 'f12';

    return key.keyLabel.toLowerCase();
  }

  static String formatShortcutForDisplay(String shortcut) {
    return shortcut
        .replaceAll('ctrl+', 'CTRL + ')
        .replaceAll('shift+', 'SHIFT + ')
        .replaceAll('alt+', 'ALT + ')
        .replaceAll('meta+', 'WIN + ')
        .toUpperCase();
  }

  static LogicalKeyboardKey? _digitKeyFromChar(String digit) {
    switch (digit) {
      case '0':
        return LogicalKeyboardKey.digit0;
      case '1':
        return LogicalKeyboardKey.digit1;
      case '2':
        return LogicalKeyboardKey.digit2;
      case '3':
        return LogicalKeyboardKey.digit3;
      case '4':
        return LogicalKeyboardKey.digit4;
      case '5':
        return LogicalKeyboardKey.digit5;
      case '6':
        return LogicalKeyboardKey.digit6;
      case '7':
        return LogicalKeyboardKey.digit7;
      case '8':
        return LogicalKeyboardKey.digit8;
      case '9':
        return LogicalKeyboardKey.digit9;
      default:
        return null;
    }
  }

  static bool _matchesSpecialKey(LogicalKeyboardKey key, String keyName) {
    switch (keyName) {
      case 'comma':
        return key == LogicalKeyboardKey.comma;
      case 'period':
        return key == LogicalKeyboardKey.period;
      case 'slash':
        return key == LogicalKeyboardKey.slash;
      case 'semicolon':
        return key == LogicalKeyboardKey.semicolon;
      case 'quote':
        return key == LogicalKeyboardKey.quote;
      case 'bracketleft':
        return key == LogicalKeyboardKey.bracketLeft;
      case 'bracketright':
        return key == LogicalKeyboardKey.bracketRight;
      case 'minus':
        return key == LogicalKeyboardKey.minus;
      case 'equal':
        return key == LogicalKeyboardKey.equal;
      case 'space':
        return key == LogicalKeyboardKey.space;
      case 'tab':
        return key == LogicalKeyboardKey.tab;
      case 'enter':
        return key == LogicalKeyboardKey.enter;
      case 'escape':
        return key == LogicalKeyboardKey.escape;
      case 'f1':
        return key == LogicalKeyboardKey.f1;
      case 'f2':
        return key == LogicalKeyboardKey.f2;
      case 'f3':
        return key == LogicalKeyboardKey.f3;
      case 'f4':
        return key == LogicalKeyboardKey.f4;
      case 'f5':
        return key == LogicalKeyboardKey.f5;
      case 'f6':
        return key == LogicalKeyboardKey.f6;
      case 'f7':
        return key == LogicalKeyboardKey.f7;
      case 'f8':
        return key == LogicalKeyboardKey.f8;
      case 'f9':
        return key == LogicalKeyboardKey.f9;
      case 'f10':
        return key == LogicalKeyboardKey.f10;
      case 'f11':
        return key == LogicalKeyboardKey.f11;
      case 'f12':
        return key == LogicalKeyboardKey.f12;
      default:
        return false;
    }
  }
}
