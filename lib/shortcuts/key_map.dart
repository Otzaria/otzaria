import 'package:flutter/services.dart';

/// מיפוי מרכזי בין שמות מקשים (מחרוזות) ל-[LogicalKeyboardKey].
///
/// משמש כמקור-האמת היחיד לכל ה-utils העוסקים בקיצורי מקשים:
/// - [ShortcutHelper.matchesShortcut] – ניתוח מחרוזת קיצור והשוואה לאירוע
/// - [ShortcutHelper.getKeyLabel]     – LogicalKeyboardKey → שם מחרוזת
/// - [ShortcutHelper.formatKeysToShortcut] – Set של LogicalKeyboardKey → מחרוזת
///
/// **הרחבה:** להוסיף מקש חדש יש לרשום אותו **כאן בלבד** –
/// כל שאר הקוד יקבל אוטומטית תמיכה בו (התאמה + תצוגה).
class KeyMap {
  KeyMap._();

  static const Map<String, LogicalKeyboardKey> nameToKey = {
    // ─── אותיות ────────────────────────────────────────────────────────────────
    'a': LogicalKeyboardKey.keyA,
    'b': LogicalKeyboardKey.keyB,
    'c': LogicalKeyboardKey.keyC,
    'd': LogicalKeyboardKey.keyD,
    'e': LogicalKeyboardKey.keyE,
    'f': LogicalKeyboardKey.keyF,
    'g': LogicalKeyboardKey.keyG,
    'h': LogicalKeyboardKey.keyH,
    'i': LogicalKeyboardKey.keyI,
    'j': LogicalKeyboardKey.keyJ,
    'k': LogicalKeyboardKey.keyK,
    'l': LogicalKeyboardKey.keyL,
    'm': LogicalKeyboardKey.keyM,
    'n': LogicalKeyboardKey.keyN,
    'o': LogicalKeyboardKey.keyO,
    'p': LogicalKeyboardKey.keyP,
    'q': LogicalKeyboardKey.keyQ,
    'r': LogicalKeyboardKey.keyR,
    's': LogicalKeyboardKey.keyS,
    't': LogicalKeyboardKey.keyT,
    'u': LogicalKeyboardKey.keyU,
    'v': LogicalKeyboardKey.keyV,
    'w': LogicalKeyboardKey.keyW,
    'x': LogicalKeyboardKey.keyX,
    'y': LogicalKeyboardKey.keyY,
    'z': LogicalKeyboardKey.keyZ,

    // ─── מקשי ספרות ────────────────────────────────────────────────────────────
    '0': LogicalKeyboardKey.digit0,
    '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2,
    '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4,
    '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6,
    '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8,
    '9': LogicalKeyboardKey.digit9,

    // ─── סימנים ─────────────────────────────────────────────────────────────────
    'comma': LogicalKeyboardKey.comma,
    'period': LogicalKeyboardKey.period,
    'slash': LogicalKeyboardKey.slash,
    'backslash': LogicalKeyboardKey.backslash,
    'semicolon': LogicalKeyboardKey.semicolon,
    'quote': LogicalKeyboardKey.quote,
    'bracketleft': LogicalKeyboardKey.bracketLeft,
    'bracketright': LogicalKeyboardKey.bracketRight,
    'minus': LogicalKeyboardKey.minus,
    'equal': LogicalKeyboardKey.equal,
    'backquote': LogicalKeyboardKey.backquote,

    // ─── מקשים מיוחדים ──────────────────────────────────────────────────────────
    'space': LogicalKeyboardKey.space,
    'tab': LogicalKeyboardKey.tab,
    'enter': LogicalKeyboardKey.enter,
    'backspace': LogicalKeyboardKey.backspace,
    'delete': LogicalKeyboardKey.delete,
    'escape': LogicalKeyboardKey.escape,
    'insert': LogicalKeyboardKey.insert,

    // ─── ניווט ──────────────────────────────────────────────────────────────────
    'arrowup': LogicalKeyboardKey.arrowUp,
    'arrowdown': LogicalKeyboardKey.arrowDown,
    'arrowleft': LogicalKeyboardKey.arrowLeft,
    'arrowright': LogicalKeyboardKey.arrowRight,
    'home': LogicalKeyboardKey.home,
    'end': LogicalKeyboardKey.end,
    'pageup': LogicalKeyboardKey.pageUp,
    'pagedown': LogicalKeyboardKey.pageDown,

    // ─── מקשי F ─────────────────────────────────────────────────────────────────
    'f1': LogicalKeyboardKey.f1,
    'f2': LogicalKeyboardKey.f2,
    'f3': LogicalKeyboardKey.f3,
    'f4': LogicalKeyboardKey.f4,
    'f5': LogicalKeyboardKey.f5,
    'f6': LogicalKeyboardKey.f6,
    'f7': LogicalKeyboardKey.f7,
    'f8': LogicalKeyboardKey.f8,
    'f9': LogicalKeyboardKey.f9,
    'f10': LogicalKeyboardKey.f10,
    'f11': LogicalKeyboardKey.f11,
    'f12': LogicalKeyboardKey.f12,
  };

  /// מיפוי הפוך: [LogicalKeyboardKey] → שם מחרוזת.
  /// נבנה אוטומטית מ-[nameToKey] – אין צורך לעדכן ידנית.
  static final Map<LogicalKeyboardKey, String> keyToName = {
    for (final e in nameToKey.entries) e.value: e.key,
  };

  /// מחזיר את שם המחרוזת של [key], או `null` אם אינו ברשימה.
  static String? labelFor(LogicalKeyboardKey key) => keyToName[key];

  /// מחזיר את [LogicalKeyboardKey] המתאים לשם [name] (case-insensitive),
  /// או `null` אם השם אינו מוכר.
  static LogicalKeyboardKey? keyFor(String name) =>
      nameToKey[name.toLowerCase()];
}
