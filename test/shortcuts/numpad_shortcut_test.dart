import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';

KeyDownEvent _keyDown(LogicalKeyboardKey key, PhysicalKeyboardKey physical) =>
    KeyDownEvent(
      physicalKey: physical,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ShortcutHelper.isMacForTesting = false;
    ShortcutHelper.isWindowsForTesting = false;
  });
  tearDown(() {
    ShortcutHelper.isMacForTesting = null;
    ShortcutHelper.isWindowsForTesting = null;
  });

  group('מקש + כמקש ראשי', () {
    test('ctrl++ מנורמל ל-token plus במקום להישבר על המפריד', () {
      expect(ShortcutHelper.normalizeShortcut('ctrl++'), 'ctrl+plus');
      expect(ShortcutHelper.normalizeShortcut('+'), 'plus');
      expect(ShortcutHelper.isRecognized('ctrl++'), isTrue);
    });

    test('הקלטת מקש + מלוח הספרות נשמרת בשם ולא בתו', () {
      final shortcut = ShortcutHelper.formatKeysToShortcut({
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.numpadAdd,
      });
      expect(shortcut, 'ctrl+numpadadd');
      expect(ShortcutHelper.isRecognized(shortcut), isTrue);
    });

    test('תצוגה ידידותית למקשי לוח הספרות', () {
      expect(
        ShortcutHelper.formatShortcutForDisplay('ctrl+numpadadd'),
        'CTRL + Numpad +‎',
      );
      expect(
        ShortcutHelper.formatShortcutForDisplay('ctrl+numpad5'),
        'CTRL + Numpad 5',
      );
    });
  });

  group('מקבילות לוח הספרות', () {
    test('קיצור בשורה הראשית נתפס גם מלוח הספרות', () {
      expect(
        ShortcutHelper.matchesShortcut(
          _keyDown(LogicalKeyboardKey.numpadAdd, PhysicalKeyboardKey.numpadAdd),
          'ctrl+equal',
          isControlPressed: true,
        ),
        isTrue,
      );
      expect(
        ShortcutHelper.matchesShortcut(
          _keyDown(
            LogicalKeyboardKey.numpadSubtract,
            PhysicalKeyboardKey.numpadSubtract,
          ),
          'ctrl+minus',
          isControlPressed: true,
        ),
        isTrue,
      );
      expect(
        ShortcutHelper.matchesShortcut(
          _keyDown(LogicalKeyboardKey.numpad0, PhysicalKeyboardKey.numpad0),
          'ctrl+0',
          isControlPressed: true,
        ),
        isTrue,
      );
    });

    test('קיצור שהוקלט על לוח הספרות נשאר ייחודי לו', () {
      expect(
        ShortcutHelper.matchesShortcut(
          _keyDown(LogicalKeyboardKey.equal, PhysicalKeyboardKey.equal),
          'ctrl+numpadadd',
          isControlPressed: true,
        ),
        isFalse,
      );
    });

    test('ctrl+equal נתפס גם ממקש + הלוגי שפריסות מסוימות מדווחות', () {
      expect(
        ShortcutHelper.matchesShortcut(
          _keyDown(LogicalKeyboardKey.add, PhysicalKeyboardKey.equal),
          'ctrl+equal',
          isControlPressed: true,
        ),
        isTrue,
      );
    });

    test('ctrl+equal נתפס מ-Ctrl++ במקלדת הראשית', () {
      expect(
        ShortcutHelper.matchesShortcut(
          _keyDown(LogicalKeyboardKey.equal, PhysicalKeyboardKey.equal),
          'ctrl+equal',
          isControlPressed: true,
          isShiftPressed: true,
        ),
        isTrue,
      );
    });

    test('ctrl++ שנשמר נתפס מ-Ctrl++ במקלדת הראשית', () {
      expect(
        ShortcutHelper.matchesShortcut(
          _keyDown(LogicalKeyboardKey.equal, PhysicalKeyboardKey.equal),
          'ctrl++',
          isControlPressed: true,
          isShiftPressed: true,
        ),
        isTrue,
      );
    });

    test('activatorsFromShortcut מוסיף מפעיל למקבילים', () {
      expect(ShortcutHelper.activatorsFromShortcut('ctrl+equal'), hasLength(3));
      expect(ShortcutHelper.activatorsFromShortcut('ctrl+f'), hasLength(1));
    });
  });

  group('קיצורי הזום', () {
    test('רשומים עם ברירות מחדל', () {
      expect(
        ShortcutValidator.shortcutKeys,
        containsAll([
          ShortcutValidator.zoomInKey,
          ShortcutValidator.zoomOutKey,
          ShortcutValidator.zoomResetKey,
        ]),
      );
      expect(
        ShortcutValidator.defaultShortcuts[ShortcutValidator.zoomInKey],
        'ctrl+equal',
      );
      expect(
        ShortcutValidator.defaultShortcuts[ShortcutValidator.zoomOutKey],
        'ctrl+minus',
      );
      expect(
        ShortcutValidator.defaultShortcuts[ShortcutValidator.zoomResetKey],
        'ctrl+0',
      );
    });

    test('לכל קיצורי ברירת המחדל יש שם תצוגה וערך ייחודי', () {
      final used = <String, String>{};
      for (final entry in ShortcutValidator.defaultShortcuts.entries) {
        if (entry.value.isEmpty) continue;
        expect(
          ShortcutValidator.shortcutNames[entry.key],
          isNotNull,
          reason: entry.key,
        );
        expect(
          used.containsKey(entry.value),
          isFalse,
          reason: '${entry.value}: ${used[entry.value]} מול ${entry.key}',
        );
        used[entry.value] = entry.key;
      }
    });
  });
}
