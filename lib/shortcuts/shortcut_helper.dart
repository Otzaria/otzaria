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

  /// override לבדיקת דיווח AltGr הייחודי ל-Windows.
  @visibleForTesting
  static bool? isWindowsForTesting;

  static bool get _treatCtrlAsMeta => isMacForTesting ?? _isMac;

  /// האם ה-token הקנוני `ctrl` מתנהג כ-Command — כלומר הקיצורים
  /// נפתרים לפי מוסכמת מקלדת Mac.
  static bool get usesMacModifiers => _treatCtrlAsMeta;
  static bool get _treatRightAltAsAltGr =>
      isWindowsForTesting ?? (!kIsWeb && Platform.isWindows);

  /// האם לחוץ Alt רגיל או AltGr, גם כשהמערכת מדווחת עליו כ-AltGraph.
  static bool get isAltModifierPressed {
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isAltPressed || _isAltGrPressed(keyboard);
  }

  /// האם Ctrl (או Cmd ב-Mac) לחוץ כ-modifier נקי — ללא Alt/AltGr.
  /// AltGr בפריסה לא-לטינית מדווח כ-Ctrl+Alt, ובלעדי השלילה קיצורי Ctrl
  /// קבועים היו נתפסים בהקלדת תווים מיוחדים.
  static bool get isPlainCtrlOrCmdPressed {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed || _isAltGrPressed(keyboard)) return false;
    return keyboard.isControlPressed ||
        (_treatCtrlAsMeta && keyboard.isMetaPressed);
  }

  static bool _isAltGrPressed(HardwareKeyboard keyboard) =>
      keyboard.isLogicalKeyPressed(LogicalKeyboardKey.altGraph) ||
      (_treatRightAltAsAltGr &&
          keyboard.isPhysicalKeyPressed(PhysicalKeyboardKey.altRight));

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
    bool? isAltGrPressed,
    bool? isMetaPressed,
  }) {
    if (event is! KeyDownEvent) return false;

    final normalized = normalizeShortcut(shortcutSetting);
    if (normalized == null || normalized.isEmpty) return false;
    final parts = normalized.split('+');
    final hasCtrlToken = parts.contains('ctrl') || parts.contains('control');
    final hasMetaToken = parts.contains('meta');
    final requiresShift = parts.contains('shift');
    final requiresAlt = parts.contains('alt');
    final mainKey = parts.where((p) => !_modifiers.contains(p)).firstOrNull;
    if (mainKey == null) return false;

    // ב-Mac גם `ctrl` וגם `meta` בקיצור שמור משויכים לפעולת Command. מצב
    // מקש Control הפיזי לא נבדק כלל — מאחד את הסמנטיקה ומונע אי-עקביות
    // בקיצור `ctrl+meta+X` (שאם נבדק כפשוטו היה נשבר).
    final requiresCtrl = _treatCtrlAsMeta ? null : hasCtrlToken;
    final requiresMeta = _treatCtrlAsMeta
        ? (hasMetaToken || hasCtrlToken)
        : hasMetaToken;

    // בדיקת modifiers
    final keyboard = HardwareKeyboard.instance;
    final controlPressed = isControlPressed ?? keyboard.isControlPressed;
    final shiftPressed = isShiftPressed ?? keyboard.isShiftPressed;
    final altPressed = isAltPressed ?? keyboard.isAltPressed;
    final altGrPressed = isAltGrPressed ?? _isAltGrPressed(keyboard);
    final effectiveAltPressed = altPressed || altGrPressed;
    final metaPressed = isMetaPressed ?? keyboard.isMetaPressed;

    // AltGr עשוי להוסיף Control סינתטי; מדכאים אותו תמיד כדי שהאירוע לא
    // יתאים בו-זמנית גם ל-alt וגם ל-ctrl+alt.
    final effectiveControlPressed = altGrPressed ? false : controlPressed;

    if (requiresCtrl != null && requiresCtrl != effectiveControlPressed) {
      return false;
    }
    // '+' בשורה הראשית נשלח כ-Shift+Equal; קיצור שמור של + או = מקבל אותו.
    final isShiftedPrimaryPlus =
        shiftPressed &&
        event.physicalKey == PhysicalKeyboardKey.equal &&
        (mainKey == 'equal' || mainKey == 'plus');
    if (requiresShift != shiftPressed && !isShiftedPrimaryPlus) {
      return false;
    }
    if (requiresAlt != effectiveAltPressed) return false;
    if (requiresMeta != metaPressed) return false;

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
    if (expectedKey == null) return false;
    if (event.logicalKey == expectedKey) return true;
    if (KeyMap.equivalentKeysFor(mainKey).contains(event.logicalKey)) {
      return true;
    }

    // פריסה לא-לטינית מדווחת על מקשי הסימנים והספרות תו מקומי (ב-macOS
    // בפריסה עברית מקש הפסיק הוא 'ת'), שאינו ניתן להשוואה לשם המקש — כמו
    // באותיות, המיקום הפיזי מכריע (issue #1411). תו שהוא בעצמו מקש מוכר
    // (פריסה לטינית שמזיזה סימנים) נשאר מזוהה לפי התו בלבד.
    return isLayoutSpecificKey(event.logicalKey) &&
        event.physicalKey == KeyMap.physicalKeyFor(mainKey);
  }

  /// האם [key] הוא תו מקומי לא-מוכר ש-macOS מדווח עבור מקש סימן או ספרה.
  /// רק במצב החריג הזה המיקום הפיזי מזהה את הקיצור.
  static bool isLayoutSpecificKey(LogicalKeyboardKey key) {
    if (!_treatCtrlAsMeta) return false;
    final id = key.keyId;
    if (id >= 0x61 && id <= 0x7a) return false; // a–z
    return KeyMap.labelFor(key) == null;
  }

  /// האם [shortcut] ניתן לזיהוי בפועל — כלומר המקש הראשי שבו מוכר ל-
  /// [matchesShortcut]. קיצור ריק תקין (פעולה ללא קיצור).
  ///
  /// קיצור שהוקלט בפריסה לא-לטינית לפני שההקלטה נורמלה נשמר עם התו המקומי
  /// (`ctrl+shift+כ`) ולכן לעולם אינו נתפס — כזה מוחזר כאן כלא-מוכר.
  static bool isRecognized(String shortcut) =>
      normalizeShortcut(shortcut) != null;

  /// האם [shortcut] הוא מקש תו יחיד ללא modifiers.
  static bool isUnmodifiedCharacterShortcut(String shortcut) {
    final normalized = normalizeShortcut(shortcut);
    if (normalized == null || normalized.isEmpty || normalized.contains('+')) {
      return false;
    }
    return RegExp(r'^[a-z0-9]$').hasMatch(normalized) ||
        const {
          'backslash',
          'backquote',
          'bracketleft',
          'bracketright',
          'comma',
          'equal',
          'minus',
          'period',
          'plus',
          'quote',
          'semicolon',
          'slash',
          'space',
        }.contains(normalized);
  }

  /// מנרמל קיצור לפורמט הקנוני או מחזיר `null` כשהתחביר אינו חד-משמעי.
  ///
  /// בדיוק מקש ראשי אחד מותר, וכל modifier מופיע לכל היותר פעם אחת. כך
  /// קיצור שמאוחסן/מושווה תמיד מתאר בדיוק את אותו אירוע מקלדת שהוא תופס.
  static String? normalizeShortcut(String shortcut) {
    final value = _plusKeyToToken(shortcut.trim());
    if (value.isEmpty) return '';

    final parts = value.toLowerCase().split('+');
    if (parts.any((part) => part.isEmpty)) return null;

    final ctrlLikeCount = parts
        .where((part) => part == 'ctrl' || part == 'control')
        .length;
    final metaCount = parts.where((part) => part == 'meta').length;
    if (ctrlLikeCount > 1 || metaCount > 1) return null;

    String? mainKey;
    final modifiers = <String>{};
    for (final part in parts) {
      final modifier = part == 'control' || (_treatCtrlAsMeta && part == 'meta')
          ? 'ctrl'
          : part;
      if (_modifiers.contains(part)) {
        if (!modifiers.add(modifier) &&
            !(_treatCtrlAsMeta &&
                modifier == 'ctrl' &&
                ctrlLikeCount == 1 &&
                metaCount == 1)) {
          return null;
        }
      } else if (mainKey == null) {
        mainKey = part;
      } else {
        return null;
      }
    }
    if (mainKey == null || !_isKnownMainKey(mainKey)) return null;

    return [
      for (final modifier in const ['ctrl', 'shift', 'alt', 'meta'])
        if (modifiers.contains(modifier)) modifier,
      mainKey,
    ].join('+');
  }

  /// ממיר מקש '+' שנכתב כתו גולמי ל-token `plus`, כדי שלא יתנגש במפריד
  /// של פורמט הקיצורים (`ctrl++` → `ctrl+plus`).
  static String _plusKeyToToken(String value) {
    if (value == '+') return 'plus';
    if (value.endsWith('++')) {
      return '${value.substring(0, value.length - 2)}+plus';
    }
    return value;
  }

  static bool _isKnownMainKey(String mainKey) {
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
    // מקש סימן/ספרה שהפריסה המקומית מדווחת עליו תו לא-מוכר (למשל 'ת' על מקש
    // הפסיק ב-macOS בעברית) נשמר לפי מיקומו הפיזי — כפי ש-[matchesShortcut]
    // מזהה אותו (issue #1411).
    if (isLayoutSpecificKey(event.logicalKey)) {
      final byPosition = KeyMap.keyForPhysical(event.physicalKey);
      if (byPosition != null) return byPosition;
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
    final hasAltGr =
        keys.contains(LogicalKeyboardKey.altGraph) ||
        (_treatRightAltAsAltGr && keys.contains(LogicalKeyboardKey.altRight));

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
          key == LogicalKeyboardKey.altRight ||
          key == LogicalKeyboardKey.altGraph) {
        hasAlt = true;
      } else if (key == LogicalKeyboardKey.meta ||
          key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight) {
        hasMeta = true;
      } else {
        mainKey = getKeyLabel(key);
      }
    }

    if (hasAltGr) hasCtrl = false;

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
      .replaceAll('PAGEDOWN', 'Page Down')
      .replaceAll('NUMPADADD', 'Numpad +')
      .replaceAll('NUMPADSUBTRACT', 'Numpad -')
      .replaceAll('NUMPADMULTIPLY', 'Numpad *')
      .replaceAll('NUMPADDIVIDE', 'Numpad /')
      .replaceAll('NUMPADDECIMAL', 'Numpad .')
      .replaceAll('NUMPADENTER', 'Numpad Enter')
      .replaceAllMapped(
        RegExp(r'NUMPAD(\d)'),
        (match) => 'Numpad ${match[1]}',
      )
      .replaceAll('PLUS', '+')
      .replaceAll('MINUS', '-')
      .replaceAll('EQUAL', '=')
      .replaceAll('COMMA', ',')
      .replaceAll('ENTER', 'Enter');

  /// ממיר מחרוזת קיצור (כגון `'ctrl+f'`) ל-[ShortcutActivator].
  ///
  /// מחזיר מפעיל קיצור עם modifiers מתאימים.
  /// אם המחרוזת אינה ניתנת לניתוח, מחזיר `null`.
  ///
  /// ב-Mac ה-token `ctrl` ממופה ל-`meta: true` כדי שמתפעלי קיצור (Flutter
  /// `Shortcuts` widget) יזהו לחיצת Command, אלא אם [mapCtrlToMeta] הוא false.
  /// כל המפעילים שיש לרשום עבור [shortcut]: הצירוף עצמו, ובנוסף המקשים
  /// המקבילים (לוח הספרות) — בסימטריה ל-[matchesShortcut].
  static List<ShortcutActivator> activatorsFromShortcut(
    String shortcut, {
    bool mapCtrlToMeta = true,
  }) {
    final primary = activatorFromShortcut(
      shortcut,
      mapCtrlToMeta: mapCtrlToMeta,
    );
    if (primary == null) return const [];

    final parts = normalizeShortcut(shortcut)!.split('+');
    final mainKey = parts.where((p) => !_modifiers.contains(p)).firstOrNull;
    if (mainKey == null) return [primary];

    final modifiers = parts.where(_modifiers.contains);
    return [
      primary,
      for (final equivalent in KeyMap.equivalentKeysFor(mainKey))
        ?activatorFromShortcut(
          [...modifiers, ?KeyMap.labelFor(equivalent)].join('+'),
          mapCtrlToMeta: mapCtrlToMeta,
        ),
    ];
  }

  static ShortcutActivator? activatorFromShortcut(
    String shortcut, {
    bool mapCtrlToMeta = true,
  }) {
    final normalized = normalizeShortcut(shortcut);
    if (normalized == null || normalized.isEmpty) return null;
    final parts = normalized.split('+');
    final hasCtrlToken = parts.contains('ctrl') || parts.contains('control');
    final hasMetaToken = parts.contains('meta');
    final hasShift = parts.contains('shift');
    final hasAlt = parts.contains('alt');

    final bool useControl;
    final bool useMeta;
    final treatCtrlAsMeta = mapCtrlToMeta && _treatCtrlAsMeta;
    if (treatCtrlAsMeta) {
      useControl = false;
      useMeta = hasCtrlToken || hasMetaToken;
    } else {
      useControl = hasCtrlToken;
      useMeta = hasMetaToken;
    }

    final mainKeyName = parts.where((p) => !_modifiers.contains(p)).firstOrNull;
    if (mainKeyName == null) return null;

    LogicalKeyboardKey? logicalKey;
    PhysicalKeyboardKey? physicalTrigger;
    if (mainKeyName.length == 1) {
      final code = mainKeyName.codeUnitAt(0);
      if (code >= 97 && code <= 122) {
        final offset = code - 97;
        logicalKey = LogicalKeyboardKey(0x00000061 + offset);
        physicalTrigger = PhysicalKeyboardKey(
          PhysicalKeyboardKey.keyA.usbHidUsage + offset,
        );
      }
    }
    logicalKey ??= KeyMap.keyFor(mainKeyName);
    if (logicalKey == null) return null;

    if (hasAlt) {
      return _AltAwareShortcutActivator(
        logicalKey,
        physicalTrigger: physicalTrigger,
        control: useControl,
        shift: hasShift,
        meta: useMeta,
      );
    }

    return SingleActivator(
      logicalKey,
      control: useControl,
      shift: hasShift,
      meta: useMeta,
    );
  }
}

class _AltAwareShortcutActivator extends ShortcutActivator {
  const _AltAwareShortcutActivator(
    this.trigger, {
    required this.physicalTrigger,
    required this.control,
    required this.shift,
    required this.meta,
  });

  final LogicalKeyboardKey trigger;
  final PhysicalKeyboardKey? physicalTrigger;
  final bool control;
  final bool shift;
  final bool meta;

  @override
  Iterable<LogicalKeyboardKey>? get triggers =>
      physicalTrigger != null ? null : [trigger];

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final altGrPressed = ShortcutHelper._isAltGrPressed(state);
    final effectiveControlPressed = altGrPressed
        ? false
        : state.isControlPressed;
    if (control != effectiveControlPressed ||
        shift != state.isShiftPressed ||
        !(state.isAltPressed || altGrPressed) ||
        meta != state.isMetaPressed) {
      return false;
    }

    return physicalTrigger != null
        ? event.physicalKey == physicalTrigger
        : event.logicalKey == trigger;
  }

  @override
  String debugDescribeKeys() {
    final modifiers = <String>[
      if (control) 'ctrl',
      if (shift) 'shift',
      'alt',
      if (meta) 'meta',
    ];
    return [...modifiers, ShortcutHelper.getKeyLabel(trigger)].join('+');
  }

  @override
  bool operator ==(Object other) =>
      other is _AltAwareShortcutActivator &&
      other.trigger == trigger &&
      other.physicalTrigger == physicalTrigger &&
      other.control == control &&
      other.shift == shift &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(
    trigger,
    physicalTrigger,
    control,
    shift,
    meta,
  );
}
