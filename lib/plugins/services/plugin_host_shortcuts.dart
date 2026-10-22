import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/shortcuts/key_map.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';

/// קיצור של התוכנה שה-WebView של תוסף תופס ומעביר חזרה ל-Flutter.
///
/// [id] מזהה את הקיצור בשני הצדדים; [codes] הם ערכי `KeyboardEvent.code`
/// (פיזיים, ולכן בלתי-תלויים בפריסת המקלדת — כמו ההתאמה ב-[ShortcutHelper]).
/// דגלי ה-modifier כבר פתורים למקש הפיזי: ב-Mac ה-token `ctrl` נהיה [meta].
class PluginHostShortcut {
  final String id;
  final String mainKey;
  final List<String> codes;
  final bool ctrl;
  final bool shift;
  final bool alt;
  final bool meta;

  const PluginHostShortcut({
    required this.id,
    required this.mainKey,
    required this.codes,
    required this.ctrl,
    required this.shift,
    required this.alt,
    required this.meta,
  });

  Map<String, Object> toJson() => {
    'id': id,
    'codes': codes,
    'ctrl': ctrl,
    'shift': shift,
    'alt': alt,
    'meta': meta,
  };
}

/// קיצורי הניווט של התוכנה שנשארים פעילים גם כשלשונית תוסף מחזיקה את
/// המקלדת (issue #1241).
///
/// ה-WebView של תוסף מקבל את פוקוס המקלדת הנייטיבי, ו-Flutter אינו רואה אף
/// הקשה. הסקריפט המוזרק לתוסף תופס את הצירופים שברשימה כאן — לפי ההגדרה
/// הנוכחית של המשתמש, לא ברירת המחדל — ומעביר אותם חזרה; [dispatch] מזריק
/// אותם לצינור המקלדת של Flutter כאילו הוקשו במסך רגיל.
///
/// מועברים רק קיצורים שנצרכים גם כשתוסף פתוח (מעבר מסך, לשוניות, כלים).
/// לתוסף עדיפות: קיצור שטיפל בו, או שהוקש בשדה עריכה, נשאר שלו (#1336).
class PluginHostShortcuts {
  const PluginHostShortcuts._();

  /// מפתחות ההגדרות שערכן מועבר לתוסף.
  static const List<String> forwardedSettingKeys = [
    'key-shortcut-open-library-browser',
    'key-shortcut-open-find-ref',
    'key-shortcut-close-tab',
    'key-shortcut-close-all-tabs',
    'key-shortcut-restore-closed-tab',
    'key-shortcut-search-tabs',
    'key-shortcut-open-reading-screen',
    'key-shortcut-open-new-search',
    ShortcutValidator.openAdvancedSearchKey,
    ShortcutValidator.openNewWindowKey,
    'key-shortcut-open-settings',
    'key-shortcut-open-more',
    'key-shortcut-open-bookmarks',
    'key-shortcut-open-history',
    'key-shortcut-switch-workspace',
    'key-shortcut-open-tool-calendar',
    'key-shortcut-open-tool-shamor-zachor',
    'key-shortcut-open-tool-measurements',
    'key-shortcut-open-tool-notes',
    'key-shortcut-open-tool-gematria',
    'key-shortcut-open-tool-aramaic-dictionary',
    'key-shortcut-open-tool-acronyms-dictionary',
    'key-shortcut-open-tool-marker',
  ];

  /// קיצורים קבועים שאינם ניתנים להגדרה: מעבר בין לשוניות ומסך מלא.
  /// Ctrl כאן פיזי גם ב-Mac (Cmd+Tab שמור למערכת) — כמו ב-KeyboardShortcuts.
  static const List<String> fixedShortcuts = [
    'ctrl+tab',
    'ctrl+shift+tab',
    'ctrl+1',
    'ctrl+2',
    'ctrl+3',
    'ctrl+4',
    'ctrl+5',
    'ctrl+6',
    'ctrl+7',
    'ctrl+8',
    'ctrl+9',
    'f11',
  ];

  /// override לבדיקות: `null` = לפי הפלטפורמה.
  @visibleForTesting
  static bool? isMacForTesting;

  static bool get _treatCtrlAsMeta =>
      isMacForTesting ?? (!kIsWeb && Platform.isMacOS);

  /// בונה את הרשימה שתוזרק לתוסף מהגדרות המשתמש [shortcutSettings];
  /// ערך חסר נופל לברירת המחדל, וערך ריק או לא-מוכר מושמט.
  static List<PluginHostShortcut> build(Map<String, String> shortcutSettings) {
    final result = <PluginHostShortcut>[];
    for (final key in forwardedSettingKeys) {
      final value =
          shortcutSettings[key] ??
          ShortcutValidator.defaultShortcuts[key] ??
          '';
      final parsed = _parse(key, value, ctrlIsMeta: _treatCtrlAsMeta);
      if (parsed != null) result.add(parsed);
    }
    for (final shortcut in fixedShortcuts) {
      final parsed = _parse('fixed:$shortcut', shortcut, ctrlIsMeta: false);
      if (parsed != null) result.add(parsed);
    }
    return result;
  }

  static PluginHostShortcut? _parse(
    String id,
    String shortcut, {
    required bool ctrlIsMeta,
  }) {
    final normalized = ShortcutHelper.normalizeShortcut(shortcut);
    if (normalized == null || normalized.isEmpty) return null;
    final parts = normalized.split('+');
    final mainKey = parts
        .where((p) => !const {'ctrl', 'shift', 'alt', 'meta'}.contains(p))
        .firstOrNull;
    if (mainKey == null) return null;
    final codes = codesForToken(mainKey);
    if (codes == null) return null;
    final hasCtrl = parts.contains('ctrl');
    return PluginHostShortcut(
      id: id,
      mainKey: mainKey,
      codes: codes,
      ctrl: hasCtrl && !ctrlIsMeta,
      shift: parts.contains('shift'),
      alt: parts.contains('alt'),
      meta: parts.contains('meta') || (hasCtrl && ctrlIsMeta),
    );
  }

  /// ערכי `KeyboardEvent.code` שמייצגים את ה-token [mainKey] של קיצור.
  static List<String>? codesForToken(String mainKey) {
    if (_isLetter(mainKey)) return ['Key${mainKey.toUpperCase()}'];
    if (_isDigit(mainKey)) return ['Digit$mainKey', 'Numpad$mainKey'];
    final entry = _tokenKeys[mainKey];
    return entry == null ? null : [entry.code];
  }

  /// המקש הפיזי שמייצג את ה-token [mainKey].
  static PhysicalKeyboardKey? physicalKeyForToken(String mainKey) {
    if (_isLetter(mainKey)) {
      return PhysicalKeyboardKey(
        PhysicalKeyboardKey.keyA.usbHidUsage + (mainKey.codeUnitAt(0) - 97),
      );
    }
    if (_isDigit(mainKey)) {
      return mainKey == '0'
          ? PhysicalKeyboardKey.digit0
          : PhysicalKeyboardKey(
              PhysicalKeyboardKey.digit1.usbHidUsage +
                  (mainKey.codeUnitAt(0) - 49),
            );
    }
    return _tokenKeys[mainKey]?.physical;
  }

  static LogicalKeyboardKey? _logicalKeyForToken(String mainKey) {
    if (_isLetter(mainKey)) {
      return LogicalKeyboardKey(
        LogicalKeyboardKey.keyA.keyId + (mainKey.codeUnitAt(0) - 97),
      );
    }
    return KeyMap.keyFor(mainKey);
  }

  static bool _isLetter(String s) =>
      s.length == 1 && s.codeUnitAt(0) >= 97 && s.codeUnitAt(0) <= 122;
  static bool _isDigit(String s) =>
      s.length == 1 && s.codeUnitAt(0) >= 48 && s.codeUnitAt(0) <= 57;

  /// מזריק את [shortcut] לצינור המקלדת של Flutter: modifiers למטה, המקש
  /// למטה ולמעלה, modifiers למעלה. האירועים מסומנים `synthesized` ולכן
  /// מופצים מיד לעץ הפוקוס ול-late handlers.
  ///
  /// מחזיר האם המקש הראשי אכן שוגר.
  static bool dispatch(PluginHostShortcut shortcut) {
    final physical = physicalKeyForToken(shortcut.mainKey);
    final logical = _logicalKeyForToken(shortcut.mainKey);
    if (physical == null || logical == null) return false;
    // Tab של Ctrl+Tab שעבר לתוסף שוחרר בתוך ה-WebView, ו-Flutter עדיין רואה
    // אותו לחוץ. משחררים את הרישום המיושן, אחרת הקיצור נחסם לתמיד (#1349).
    final staleLogical = HardwareKeyboard.instance.lookUpLayout(physical);
    if (staleLogical != null) {
      _send(ui.KeyEventType.up, physical, staleLogical);
    }
    final pressed = HardwareKeyboard.instance.physicalKeysPressed;

    final modifiers = <(PhysicalKeyboardKey, LogicalKeyboardKey)>[
      if (shortcut.ctrl)
        (PhysicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlLeft),
      if (shortcut.shift)
        (PhysicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftLeft),
      if (shortcut.alt)
        (PhysicalKeyboardKey.altLeft, LogicalKeyboardKey.altLeft),
      if (shortcut.meta)
        (PhysicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaLeft),
    ].where((m) => !pressed.contains(m.$1)).toList();

    for (final m in modifiers) {
      _send(ui.KeyEventType.down, m.$1, m.$2);
    }
    _send(ui.KeyEventType.down, physical, logical);
    _send(ui.KeyEventType.up, physical, logical);
    for (final m in modifiers.reversed) {
      _send(ui.KeyEventType.up, m.$1, m.$2);
    }
    return true;
  }

  static void _send(
    ui.KeyEventType type,
    PhysicalKeyboardKey physical,
    LogicalKeyboardKey logical,
  ) {
    // FocusManager עדיין מקבל אירועים רק דרך keyMessageHandler של
    // KeyEventManager; HardwareKeyboard.handleKeyEvent לבדו לא מגיע לעץ הפוקוס.
    // ignore: deprecated_member_use
    ServicesBinding.instance.keyEventManager.handleKeyData(
      ui.KeyData(
        timeStamp: Duration(
          microseconds: DateTime.now().microsecondsSinceEpoch,
        ),
        type: type,
        physical: physical.usbHidUsage,
        logical: logical.keyId,
        character: null,
        synthesized: true,
      ),
    );
  }

  static const Map<String, ({String code, PhysicalKeyboardKey physical})>
  _tokenKeys = {
    'comma': (code: 'Comma', physical: PhysicalKeyboardKey.comma),
    'period': (code: 'Period', physical: PhysicalKeyboardKey.period),
    'slash': (code: 'Slash', physical: PhysicalKeyboardKey.slash),
    'backslash': (code: 'Backslash', physical: PhysicalKeyboardKey.backslash),
    'semicolon': (code: 'Semicolon', physical: PhysicalKeyboardKey.semicolon),
    'quote': (code: 'Quote', physical: PhysicalKeyboardKey.quote),
    'bracketleft': (
      code: 'BracketLeft',
      physical: PhysicalKeyboardKey.bracketLeft,
    ),
    'bracketright': (
      code: 'BracketRight',
      physical: PhysicalKeyboardKey.bracketRight,
    ),
    'minus': (code: 'Minus', physical: PhysicalKeyboardKey.minus),
    'equal': (code: 'Equal', physical: PhysicalKeyboardKey.equal),
    'plus': (code: 'Equal', physical: PhysicalKeyboardKey.equal),
    'backquote': (code: 'Backquote', physical: PhysicalKeyboardKey.backquote),
    'numpad0': (code: 'Numpad0', physical: PhysicalKeyboardKey.numpad0),
    'numpad1': (code: 'Numpad1', physical: PhysicalKeyboardKey.numpad1),
    'numpad2': (code: 'Numpad2', physical: PhysicalKeyboardKey.numpad2),
    'numpad3': (code: 'Numpad3', physical: PhysicalKeyboardKey.numpad3),
    'numpad4': (code: 'Numpad4', physical: PhysicalKeyboardKey.numpad4),
    'numpad5': (code: 'Numpad5', physical: PhysicalKeyboardKey.numpad5),
    'numpad6': (code: 'Numpad6', physical: PhysicalKeyboardKey.numpad6),
    'numpad7': (code: 'Numpad7', physical: PhysicalKeyboardKey.numpad7),
    'numpad8': (code: 'Numpad8', physical: PhysicalKeyboardKey.numpad8),
    'numpad9': (code: 'Numpad9', physical: PhysicalKeyboardKey.numpad9),
    'numpadadd': (code: 'NumpadAdd', physical: PhysicalKeyboardKey.numpadAdd),
    'numpadsubtract': (
      code: 'NumpadSubtract',
      physical: PhysicalKeyboardKey.numpadSubtract,
    ),
    'numpadmultiply': (
      code: 'NumpadMultiply',
      physical: PhysicalKeyboardKey.numpadMultiply,
    ),
    'numpaddivide': (
      code: 'NumpadDivide',
      physical: PhysicalKeyboardKey.numpadDivide,
    ),
    'numpaddecimal': (
      code: 'NumpadDecimal',
      physical: PhysicalKeyboardKey.numpadDecimal,
    ),
    'numpadenter': (
      code: 'NumpadEnter',
      physical: PhysicalKeyboardKey.numpadEnter,
    ),
    'space': (code: 'Space', physical: PhysicalKeyboardKey.space),
    'tab': (code: 'Tab', physical: PhysicalKeyboardKey.tab),
    'enter': (code: 'Enter', physical: PhysicalKeyboardKey.enter),
    'backspace': (code: 'Backspace', physical: PhysicalKeyboardKey.backspace),
    'delete': (code: 'Delete', physical: PhysicalKeyboardKey.delete),
    'escape': (code: 'Escape', physical: PhysicalKeyboardKey.escape),
    'insert': (code: 'Insert', physical: PhysicalKeyboardKey.insert),
    'arrowup': (code: 'ArrowUp', physical: PhysicalKeyboardKey.arrowUp),
    'arrowdown': (code: 'ArrowDown', physical: PhysicalKeyboardKey.arrowDown),
    'arrowleft': (code: 'ArrowLeft', physical: PhysicalKeyboardKey.arrowLeft),
    'arrowright': (
      code: 'ArrowRight',
      physical: PhysicalKeyboardKey.arrowRight,
    ),
    'home': (code: 'Home', physical: PhysicalKeyboardKey.home),
    'end': (code: 'End', physical: PhysicalKeyboardKey.end),
    'pageup': (code: 'PageUp', physical: PhysicalKeyboardKey.pageUp),
    'pagedown': (code: 'PageDown', physical: PhysicalKeyboardKey.pageDown),
    'f1': (code: 'F1', physical: PhysicalKeyboardKey.f1),
    'f2': (code: 'F2', physical: PhysicalKeyboardKey.f2),
    'f3': (code: 'F3', physical: PhysicalKeyboardKey.f3),
    'f4': (code: 'F4', physical: PhysicalKeyboardKey.f4),
    'f5': (code: 'F5', physical: PhysicalKeyboardKey.f5),
    'f6': (code: 'F6', physical: PhysicalKeyboardKey.f6),
    'f7': (code: 'F7', physical: PhysicalKeyboardKey.f7),
    'f8': (code: 'F8', physical: PhysicalKeyboardKey.f8),
    'f9': (code: 'F9', physical: PhysicalKeyboardKey.f9),
    'f10': (code: 'F10', physical: PhysicalKeyboardKey.f10),
    'f11': (code: 'F11', physical: PhysicalKeyboardKey.f11),
    'f12': (code: 'F12', physical: PhysicalKeyboardKey.f12),
  };
}
