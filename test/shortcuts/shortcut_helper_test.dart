import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // כברירת מחדל קובעים פלטפורמה שאינה Mac, כך שהקבוצות הבודקות סמנטיקת Control
  // לא תלויות בפלטפורמת הריצה (ב-macOS `ctrl` מתורגם ל-Meta). הקבוצה הייעודית
  // ל-macOS שלהלן עושה override ל-true ב-setUp שלה.
  setUp(() => ShortcutHelper.isMacForTesting = false);
  tearDown(() => ShortcutHelper.isMacForTesting = null);

  group('ShortcutHelper.matchesShortcut', () {
    test('מזהה meta רק כש-meta לחוץ', () {
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyV,
        logicalKey: LogicalKeyboardKey.keyV,
        character: 'v',
        timeStamp: Duration.zero,
      );

      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'meta+v',
          isMetaPressed: false,
        ),
        isFalse,
      );

      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'meta+v',
          isMetaPressed: true,
        ),
        isTrue,
      );
    });

    test('מזהה ctrl+f לפי physical key גם כשהתו הוא עברי', () {
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyF,
        logicalKey: const LogicalKeyboardKey(0x2000000f3),
        character: 'כ',
        timeStamp: Duration.zero,
      );

      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'ctrl+f',
          isControlPressed: true,
        ),
        isTrue,
      );
    });

    test('לא מזהה ctrl+f אם נלחץ physical key אחר', () {
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyP,
        logicalKey: const LogicalKeyboardKey(0x2000000dd),
        character: 'פ',
        timeStamp: Duration.zero,
      );

      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'ctrl+f',
          isControlPressed: true,
        ),
        isFalse,
      );
    });
  });

  // ─── התנהגות ייחודית ל-macOS: ה-token `ctrl` מתורגם ל-Command (Meta) ────────
  group('ShortcutHelper על macOS — ctrl מתורגם ל-Meta', () {
    setUp(() {
      ShortcutHelper.isMacForTesting = true;
    });
    tearDown(() {
      ShortcutHelper.isMacForTesting = null;
    });

    test('matchesShortcut: ctrl+f נחשב מתאים כש-Meta לחוץ (לא Control)', () {
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyF,
        logicalKey: LogicalKeyboardKey.keyF,
        character: 'f',
        timeStamp: Duration.zero,
      );

      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'ctrl+f',
          isControlPressed: false,
          isMetaPressed: true,
        ),
        isTrue,
      );
    });

    test('matchesShortcut: ctrl+f לא מתאים כש-Control פיזי לחוץ בלי Cmd', () {
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyF,
        logicalKey: LogicalKeyboardKey.keyF,
        character: 'f',
        timeStamp: Duration.zero,
      );

      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'ctrl+f',
          isControlPressed: true,
          isMetaPressed: false,
        ),
        isFalse,
      );
    });

    test('matchesShortcut: ctrl+f מתאים גם כשControl+Cmd לחוצים יחד ב-Mac', () {
      // ב-Mac מצב מקש Control הפיזי נחשב "don't care" — Cmd לבדה מספיקה.
      // כך נמנע מצב שבו Control אקראי שובר את הקיצור.
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyF,
        logicalKey: LogicalKeyboardKey.keyF,
        character: 'f',
        timeStamp: Duration.zero,
      );

      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'ctrl+f',
          isControlPressed: true,
          isMetaPressed: true,
        ),
        isTrue,
      );
    });

    test('matchesShortcut: meta+f בקיצור שמור עובד כ-Cmd+F ב-Mac', () {
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyF,
        logicalKey: LogicalKeyboardKey.keyF,
        character: 'f',
        timeStamp: Duration.zero,
      );

      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'meta+f',
          isControlPressed: false,
          isMetaPressed: true,
        ),
        isTrue,
      );
    });

    test('formatKeysToShortcut: לחיצת Meta נשמרת בפורמט הקנוני "ctrl+X"', () {
      final shortcut = ShortcutHelper.formatKeysToShortcut({
        LogicalKeyboardKey.meta,
        LogicalKeyboardKey.keyL,
      });
      expect(shortcut, 'ctrl+l');
    });

    test('formatKeysToShortcut: Ctrl+Cmd יחד מתאחדים ל-ctrl יחיד ב-Mac', () {
      final shortcut = ShortcutHelper.formatKeysToShortcut({
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.meta,
        LogicalKeyboardKey.keyL,
      });
      expect(shortcut, 'ctrl+l');
    });

    test('formatShortcutForDisplay: meta+f מוצג כ-⌘ + F ב-Mac (לא ⌃)', () {
      // עקבי עם matchesShortcut: `meta+X` בקיצור שמור פירושו Cmd ב-Mac,
      // לכן התצוגה חייבת להיות ⌘ ולא ⌃ (שייצג Control).
      final display = ShortcutHelper.formatShortcutForDisplay('meta+f');
      expect(display, '⌘ + F');
    });

    test('formatShortcutForDisplay: ctrl+f מוצג כ-⌘ + F ב-Mac', () {
      final display = ShortcutHelper.formatShortcutForDisplay('ctrl+f');
      expect(display, '⌘ + F');
    });

    test('formatShortcutForDisplay: ctrl+shift+f מוצג כ-⌘ + ⇧ + F ב-Mac', () {
      final display = ShortcutHelper.formatShortcutForDisplay('ctrl+shift+f');
      expect(display, '⌘ + ⇧ + F');
    });

    test('activatorFromShortcut: ctrl+f ממופה ל-meta:true ב-Mac', () {
      final activator =
          ShortcutHelper.activatorFromShortcut('ctrl+f')! as SingleActivator;
      expect(activator.meta, isTrue);
      expect(activator.control, isFalse);
      expect(activator.trigger, LogicalKeyboardKey.keyF);
    });
  });

  group('ShortcutHelper בפלטפורמות שאינן Mac — ctrl נשאר Control', () {
    setUp(() {
      ShortcutHelper.isMacForTesting = false;
    });
    tearDown(() {
      ShortcutHelper.isMacForTesting = null;
    });

    test('formatShortcutForDisplay: ctrl+f מוצג כ-CTRL + F', () {
      final display = ShortcutHelper.formatShortcutForDisplay('ctrl+f');
      expect(display, 'CTRL + F');
    });

    test(
      'formatShortcutForDisplay: מקשי ניווט מוצגים כסמלים/תוויות קריאות',
      () {
        expect(
          ShortcutHelper.formatShortcutForDisplay('alt+arrowup'),
          'ALT + ↑',
        );
        expect(
          ShortcutHelper.formatShortcutForDisplay('alt+arrowdown'),
          'ALT + ↓',
        );
        expect(
          ShortcutHelper.formatShortcutForDisplay('alt+pageup'),
          'ALT + Page Up',
        );
        expect(
          ShortcutHelper.formatShortcutForDisplay('alt+pagedown'),
          'ALT + Page Down',
        );
      },
    );

    test('activatorFromShortcut: ctrl+f ממופה ל-control:true', () {
      final activator =
          ShortcutHelper.activatorFromShortcut('ctrl+f')! as SingleActivator;
      expect(activator.control, isTrue);
      expect(activator.meta, isFalse);
    });
  });

  group('ShortcutHelper.isRecognized', () {
    test('קיצורים תקינים מזוהים', () {
      const valid = [
        'ctrl+f',
        'ctrl+shift+f',
        'ctrl+alt+shift+z',
        'f11',
        'escape',
        'alt+arrowup',
        'alt+pagedown',
        'ctrl+comma',
        'ctrl+3',
        'meta+l',
        'CTRL+SHIFT+F',
      ];
      for (final shortcut in valid) {
        expect(
          ShortcutHelper.isRecognized(shortcut),
          isTrue,
          reason: '$shortcut אמור להיות מוכר',
        );
      }
    });

    test('כל ברירות המחדל של האפליקציה מזוהות', () {
      for (final entry in ShortcutValidator.defaultShortcuts.entries) {
        expect(
          ShortcutHelper.isRecognized(entry.value),
          isTrue,
          reason: 'ברירת המחדל של ${entry.key} (${entry.value}) אינה מוכרת',
        );
      }
    });

    test('קיצור ריק נחשב תקין — פעולה ללא קיצור', () {
      expect(ShortcutHelper.isRecognized(''), isTrue);
    });

    test('קיצור עם תו לא-לטיני אינו מוכר', () {
      const broken = [
        'ctrl+shift+כ',
        'ctrl+ע',
        'alt+ש',
        'ф',
        'ctrl+shift+ب',
      ];
      for (final shortcut in broken) {
        expect(
          ShortcutHelper.isRecognized(shortcut),
          isFalse,
          reason: '$shortcut אינו אמור להיות מוכר',
        );
      }
    });

    test('קיצור עם modifiers בלבד או מקש חסר אינו מוכר', () {
      expect(ShortcutHelper.isRecognized('ctrl'), isFalse);
      expect(ShortcutHelper.isRecognized('ctrl+shift'), isFalse);
      expect(ShortcutHelper.isRecognized('ctrl+shift+'), isFalse);
    });

    test('קיצור עם שם מקש שאינו ב-KeyMap אינו מוכר', () {
      expect(ShortcutHelper.isRecognized('ctrl+capslock'), isFalse);
      expect(ShortcutHelper.isRecognized('f13'), isFalse);
    });

    test('כל קיצור מוכר שאינו ריק ניתן גם להמרה ל-ShortcutActivator', () {
      for (final shortcut in ['ctrl+f', 'f11', 'alt+arrowup', 'ctrl+comma']) {
        expect(ShortcutHelper.isRecognized(shortcut), isTrue);
        expect(ShortcutHelper.activatorFromShortcut(shortcut), isNotNull);
      }
    });
  });

  group('ShortcutHelper.logicalKeyToStore', () {
    test('כל 26 מקשי האותיות מנורמלים לאות הלטינית לפי מיקומם הפיזי', () {
      for (var offset = 0; offset < 26; offset++) {
        final letter = String.fromCharCode('a'.codeUnitAt(0) + offset);
        final event = nonLatinLetterEvent(
          PhysicalKeyboardKey(
            PhysicalKeyboardKey.keyA.usbHidUsage + offset,
          ),
        );

        expect(
          ShortcutHelper.logicalKeyToStore(event),
          LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + offset),
          reason: 'מקש פיזי במיקום $offset אמור להישמר כ-$letter',
        );
        expect(
          ShortcutHelper.getKeyLabel(ShortcutHelper.logicalKeyToStore(event)),
          letter,
        );
      }
    });

    test('מקש אות בפריסה עברית נשמר כאות לטינית לפי מיקומו הפיזי', () {
      expect(
        ShortcutHelper.logicalKeyToStore(
          hebrewLetterEvent(PhysicalKeyboardKey.keyF, 0x2000000f3),
        ),
        LogicalKeyboardKey.keyF,
      );
      expect(
        ShortcutHelper.logicalKeyToStore(
          hebrewLetterEvent(PhysicalKeyboardKey.keyZ, 0x2000000d6),
        ),
        LogicalKeyboardKey.keyZ,
      );
    });

    test('מקש אות בפריסה לטינית נשמר כמו שהוא (ללא שינוי התנהגות)', () {
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyF,
        logicalKey: LogicalKeyboardKey.keyF,
        character: 'f',
        timeStamp: Duration.zero,
      );
      expect(ShortcutHelper.logicalKeyToStore(event), LogicalKeyboardKey.keyF);
    });

    test('מקשים שאינם אות נשמרים לפי logicalKey כרגיל', () {
      final nonLetterKeys = <PhysicalKeyboardKey, LogicalKeyboardKey>{
        PhysicalKeyboardKey.f8: LogicalKeyboardKey.f8,
        PhysicalKeyboardKey.digit3: LogicalKeyboardKey.digit3,
        PhysicalKeyboardKey.arrowUp: LogicalKeyboardKey.arrowUp,
        PhysicalKeyboardKey.pageDown: LogicalKeyboardKey.pageDown,
        PhysicalKeyboardKey.comma: LogicalKeyboardKey.comma,
        PhysicalKeyboardKey.space: LogicalKeyboardKey.space,
        PhysicalKeyboardKey.escape: LogicalKeyboardKey.escape,
        PhysicalKeyboardKey.numpad5: LogicalKeyboardKey.numpad5,
        PhysicalKeyboardKey.home: LogicalKeyboardKey.home,
      };

      for (final entry in nonLetterKeys.entries) {
        final event = KeyDownEvent(
          physicalKey: entry.key,
          logicalKey: entry.value,
          timeStamp: Duration.zero,
        );
        expect(
          ShortcutHelper.logicalKeyToStore(event),
          entry.value,
          reason: '${entry.key.debugName} אינו מקש אות ואינו אמור להשתנות',
        );
      }
    });

    test('מקשי modifier נשמרים כמו שהם', () {
      final modifiers = <PhysicalKeyboardKey, LogicalKeyboardKey>{
        PhysicalKeyboardKey.controlLeft: LogicalKeyboardKey.controlLeft,
        PhysicalKeyboardKey.shiftLeft: LogicalKeyboardKey.shiftLeft,
        PhysicalKeyboardKey.altLeft: LogicalKeyboardKey.altLeft,
        PhysicalKeyboardKey.metaLeft: LogicalKeyboardKey.metaLeft,
      };

      for (final entry in modifiers.entries) {
        final event = KeyDownEvent(
          physicalKey: entry.key,
          logicalKey: entry.value,
          timeStamp: Duration.zero,
        );
        expect(ShortcutHelper.logicalKeyToStore(event), entry.value);
      }
    });
  });

  // הרגרסיה שהתיקון סוגר: הקלטה בפריסה לא-לטינית שמרה את התו המקומי,
  // ואילו matchesShortcut משווה physicalKey — כך שהקיצור לא נתפס לעולם.
  group('הקלטה → שמירה → זיהוי בפריסה לא-לטינית', () {
    String recordShortcut(Set<LogicalKeyboardKey> modifiers, KeyEvent event) =>
        ShortcutHelper.formatKeysToShortcut({
          ...modifiers,
          ShortcutHelper.logicalKeyToStore(event),
        });

    test(
      'ctrl+shift+G שהוקלט בעברית נשמר קנוני ונתפס על ידי matchesShortcut',
      () {
        final event = hebrewLetterEvent(PhysicalKeyboardKey.keyG, 0x2000000e2);

        final shortcut = recordShortcut({
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
        }, event);

        expect(shortcut, 'ctrl+shift+g');
        expect(
          ShortcutHelper.matchesShortcut(
            event,
            shortcut,
            isControlPressed: true,
            isShiftPressed: true,
          ),
          isTrue,
        );
      },
    );

    test('הקיצור שנשמר זהה בין הקלטה בעברית להקלטה באנגלית', () {
      final hebrew = recordShortcut(
        {LogicalKeyboardKey.control},
        hebrewLetterEvent(PhysicalKeyboardKey.keyK, 0x2000000dc),
      );
      final latin = recordShortcut(
        {LogicalKeyboardKey.control},
        {
          KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.keyK,
            logicalKey: LogicalKeyboardKey.keyK,
            character: 'k',
            timeStamp: Duration.zero,
          ),
        }.first,
      );

      expect(hebrew, latin);
      expect(hebrew, 'ctrl+k');
    });

    test('קיצור שהוקלט בעברית נתפס גם כשהמשתמש מחליף לפריסה לטינית', () {
      final shortcut = recordShortcut(
        {LogicalKeyboardKey.control, LogicalKeyboardKey.shift},
        hebrewLetterEvent(PhysicalKeyboardKey.keyD, 0x2000000d2),
      );

      final latinEvent = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyD,
        logicalKey: LogicalKeyboardKey.keyD,
        character: 'D',
        timeStamp: Duration.zero,
      );

      expect(shortcut, 'ctrl+shift+d');
      expect(
        ShortcutHelper.matchesShortcut(
          latinEvent,
          shortcut,
          isControlPressed: true,
          isShiftPressed: true,
        ),
        isTrue,
      );
    });

    test('כל שילובי ה-modifiers נשמרים ונתפסים בפריסה עברית', () {
      final combinations =
          <(Set<LogicalKeyboardKey>, String, bool, bool, bool)>[
            ({LogicalKeyboardKey.control}, 'ctrl+m', true, false, false),
            (
              {LogicalKeyboardKey.control, LogicalKeyboardKey.shift},
              'ctrl+shift+m',
              true,
              true,
              false,
            ),
            ({LogicalKeyboardKey.alt}, 'alt+m', false, false, true),
            (
              {LogicalKeyboardKey.control, LogicalKeyboardKey.alt},
              'ctrl+alt+m',
              true,
              false,
              true,
            ),
          ];

      final event = hebrewLetterEvent(PhysicalKeyboardKey.keyM, 0x2000000e6);

      for (final (modifiers, expected, ctrl, shift, alt) in combinations) {
        final shortcut = recordShortcut(modifiers, event);
        expect(shortcut, expected);
        expect(
          ShortcutHelper.matchesShortcut(
            event,
            shortcut,
            isControlPressed: ctrl,
            isShiftPressed: shift,
            isAltPressed: alt,
          ),
          isTrue,
          reason: '$expected אמור להיתפס בפריסה עברית',
        );
      }
    });

    test('קיצור שנשמר עם תו לא-לטיני אינו נתפס — לכן ההקלטה חייבת לנרמל', () {
      final event = hebrewLetterEvent(PhysicalKeyboardKey.keyF, 0x2000000f3);

      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'ctrl+shift+כ',
          isControlPressed: true,
          isShiftPressed: true,
        ),
        isFalse,
      );
    });

    test('קיצור ריק או מודיפיירים בלבד אינם נתפסים', () {
      final event = hebrewLetterEvent(PhysicalKeyboardKey.keyF, 0x2000000f3);

      expect(
        ShortcutHelper.matchesShortcut(event, '', isControlPressed: true),
        isFalse,
      );
      expect(
        ShortcutHelper.matchesShortcut(
          event,
          'ctrl+shift',
          isControlPressed: true,
          isShiftPressed: true,
        ),
        isFalse,
      );
    });
  });
}

/// אירוע מקש אות בפריסה עברית: `physicalKey` תקין, `logicalKey` הוא התו העברי
/// שאינו ניתן להשוואה — בדיוק כפי ש-Flutter מדווח ב-Windows.
KeyDownEvent hebrewLetterEvent(
  PhysicalKeyboardKey physicalKey,
  int hebrewKeyId,
) => KeyDownEvent(
  physicalKey: physicalKey,
  logicalKey: LogicalKeyboardKey(hebrewKeyId),
  timeStamp: Duration.zero,
);

/// אירוע מקש אות בפריסה לא-לטינית שרירותית, כש-`logicalKey` נגזר מ-usbHidUsage
/// ולכן אינו אחת מאותיות a–z המוכרות.
KeyDownEvent nonLatinLetterEvent(PhysicalKeyboardKey physicalKey) =>
    KeyDownEvent(
      physicalKey: physicalKey,
      logicalKey: LogicalKeyboardKey(0x200000000 + physicalKey.usbHidUsage),
      timeStamp: Duration.zero,
    );
