import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // קיבוע הפלטפורמה מונע תלות במערכת שמריצה את הטסטים; הקבוצה הייעודית
  // ל-macOS דורסת את הערך לפי הצורך.
  setUp(() {
    ShortcutHelper.isMacForTesting = false;
    ShortcutHelper.isWindowsForTesting = false;
  });
  tearDown(() {
    ShortcutHelper.isMacForTesting = null;
    ShortcutHelper.isWindowsForTesting = null;
  });

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

    test('normalizeShortcut מאחד ctrl ו-meta ל-Cmd יחיד', () {
      expect(ShortcutHelper.normalizeShortcut('meta+l'), 'ctrl+l');
      expect(ShortcutHelper.normalizeShortcut('ctrl+meta+l'), 'ctrl+l');
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

    test('activatorFromShortcut יכול לשמר Control פיזי ב-Mac', () {
      final activator =
          ShortcutHelper.activatorFromShortcut(
                'ctrl+f',
                mapCtrlToMeta: false,
              )!
              as SingleActivator;
      expect(activator.control, isTrue);
      expect(activator.meta, isFalse);
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
          'ALT + ↑‎',
        );
        expect(
          ShortcutHelper.formatShortcutForDisplay('alt+arrowdown'),
          'ALT + ↓‎',
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

    test('קיצור עם modifier כפול או יותר ממקש ראשי אינו מוכר', () {
      for (final shortcut in ['ctrl+ctrl+l', 'ctrl+l+x', 'ctrl+control+l']) {
        expect(ShortcutHelper.isRecognized(shortcut), isFalse);
      }
    });

    test('normalizeShortcut מאחד אותיות גדולות וסדר modifiers', () {
      expect(
        ShortcutHelper.normalizeShortcut('SHIFT+CTRL+L'),
        'ctrl+shift+l',
      );
      expect(ShortcutHelper.normalizeShortcut('CONTROL+L'), 'ctrl+l');
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
  group('AltGr ו-AltGraph', () {
    final arrowUp = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.arrowUp,
      logicalKey: LogicalKeyboardKey.arrowUp,
      timeStamp: Duration.zero,
    );

    test('קיצור alt בלבד מותאם גם כשה-Ctrl מגיע מ-AltGr', () {
      expect(
        ShortcutHelper.matchesShortcut(
          arrowUp,
          'alt+arrowup',
          isControlPressed: true,
          isShiftPressed: false,
          isAltPressed: true,
          isAltGrPressed: true,
          isMetaPressed: false,
        ),
        isTrue,
      );
    });

    test('AltGraph מובחן נחשב alt גם כש-isAltPressed הוא false', () {
      expect(
        ShortcutHelper.matchesShortcut(
          arrowUp,
          'alt+arrowup',
          isControlPressed: false,
          isShiftPressed: false,
          isAltPressed: false,
          isAltGrPressed: true,
          isMetaPressed: false,
        ),
        isTrue,
      );
    });

    test('Ctrl+Alt רגיל אינו מותאם לקיצור alt בלבד', () {
      expect(
        ShortcutHelper.matchesShortcut(
          arrowUp,
          'alt+arrowup',
          isControlPressed: true,
          isShiftPressed: false,
          isAltPressed: true,
          isAltGrPressed: false,
          isMetaPressed: false,
        ),
        isFalse,
      );
      expect(
        ShortcutHelper.matchesShortcut(
          arrowUp,
          'ctrl+alt+arrowup',
          isControlPressed: true,
          isShiftPressed: false,
          isAltPressed: true,
          isAltGrPressed: false,
          isMetaPressed: false,
        ),
        isTrue,
      );
    });

    test('קיצור alt בלבד ממשיך להיות מותאם ללחיצת Alt רגילה', () {
      expect(
        ShortcutHelper.matchesShortcut(
          arrowUp,
          'alt+arrowup',
          isControlPressed: false,
          isShiftPressed: false,
          isAltPressed: true,
          isAltGrPressed: false,
          isMetaPressed: false,
        ),
        isTrue,
      );
    });

    test('Ctrl בלי Alt אינו נחשב AltGr ואינו מותאם לקיצור alt', () {
      expect(
        ShortcutHelper.matchesShortcut(
          arrowUp,
          'alt+arrowup',
          isControlPressed: true,
          isShiftPressed: false,
          isAltPressed: false,
          isAltGrPressed: false,
          isMetaPressed: false,
        ),
        isFalse,
      );
    });

    test('קיצור שדורש ctrl במפורש אינו מושפע מההקלה', () {
      expect(
        ShortcutHelper.matchesShortcut(
          arrowUp,
          'ctrl+arrowup',
          isControlPressed: true,
          isShiftPressed: false,
          isAltPressed: false,
          isAltGrPressed: false,
          isMetaPressed: false,
        ),
        isTrue,
      );
      expect(
        ShortcutHelper.matchesShortcut(
          arrowUp,
          'ctrl+arrowup',
          isControlPressed: false,
          isShiftPressed: false,
          isAltPressed: true,
          isAltGrPressed: false,
          isMetaPressed: false,
        ),
        isFalse,
      );
    });

    test('AltGr אינו מפעיל קיצור ctrl בלבד', () {
      expect(
        ShortcutHelper.matchesShortcut(
          arrowUp,
          'ctrl+arrowup',
          isControlPressed: true,
          isShiftPressed: false,
          isAltPressed: true,
          isAltGrPressed: true,
          isMetaPressed: false,
        ),
        isFalse,
      );
    });

    test('AltGr אינו מפעיל קיצור ctrl+alt', () {
      expect(
        ShortcutHelper.matchesShortcut(
          arrowUp,
          'ctrl+alt+arrowup',
          isControlPressed: true,
          isShiftPressed: false,
          isAltPressed: true,
          isAltGrPressed: true,
          isMetaPressed: false,
        ),
        isFalse,
      );
    });

    test('AltGraph נשמר כ-alt בעת הקלטת קיצור', () {
      expect(
        ShortcutHelper.formatKeysToShortcut({
          LogicalKeyboardKey.altGraph,
          LogicalKeyboardKey.arrowUp,
        }),
        'alt+arrowup',
      );
    });

    test('AltGr של Windows אינו שומר את Control הסינתטי', () {
      ShortcutHelper.isWindowsForTesting = true;

      expect(
        ShortcutHelper.formatKeysToShortcut({
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.altRight,
          LogicalKeyboardKey.arrowUp,
        }),
        'alt+arrowup',
      );
    });

    test('Ctrl+Alt שמאלי נשמר כ-ctrl+alt', () {
      ShortcutHelper.isWindowsForTesting = true;

      expect(
        ShortcutHelper.formatKeysToShortcut({
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.altLeft,
          LogicalKeyboardKey.arrowUp,
        }),
        'ctrl+alt+arrowup',
      );
    });

    testWidgets('ShortcutActivator מפעיל alt בקלט AltGr של Windows', (
      tester,
    ) async {
      ShortcutHelper.isWindowsForTesting = true;
      var calls = 0;
      final activator = ShortcutHelper.activatorFromShortcut('alt+arrowup')!;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CallbackShortcuts(
            bindings: {activator: () => calls++},
            child: const Focus(
              autofocus: true,
              child: SizedBox(width: 1, height: 1),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.altRight,
        physicalKey: PhysicalKeyboardKey.altRight,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.altRight,
        physicalKey: PhysicalKeyboardKey.altRight,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(calls, 1);
    });

    test('ShortcutActivator מקבל alt בקלט AltGraph של Linux', () {
      final activator = ShortcutHelper.activatorFromShortcut('alt+arrowup')!;
      final keyboard = HardwareKeyboard();
      keyboard.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.altRight,
          logicalKey: LogicalKeyboardKey.altGraph,
          timeStamp: Duration.zero,
        ),
      );
      final arrowUp = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowUp,
        logicalKey: LogicalKeyboardKey.arrowUp,
        timeStamp: Duration.zero,
      );
      keyboard.handleKeyEvent(arrowUp);

      expect(activator.accepts(arrowUp, keyboard), isTrue);
    });

    test('ShortcutActivator משמר חזרה בהחזקת קיצור alt', () {
      final activator = ShortcutHelper.activatorFromShortcut('alt+arrowup')!;
      final keyboard = HardwareKeyboard();
      keyboard.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.altRight,
          logicalKey: LogicalKeyboardKey.altGraph,
          timeStamp: Duration.zero,
        ),
      );
      keyboard.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.arrowUp,
          logicalKey: LogicalKeyboardKey.arrowUp,
          timeStamp: Duration.zero,
        ),
      );
      final repeat = KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.arrowUp,
        logicalKey: LogicalKeyboardKey.arrowUp,
        timeStamp: Duration.zero,
      );

      expect(activator.accepts(repeat, keyboard), isTrue);
    });

    test('ShortcutActivator משווה קיצורים לפי ערכים מנורמלים', () {
      expect(
        ShortcutHelper.activatorFromShortcut('ALT+F'),
        ShortcutHelper.activatorFromShortcut('alt+f'),
      );
      expect(
        ShortcutHelper.activatorFromShortcut('control+alt+f'),
        ShortcutHelper.activatorFromShortcut('ctrl+alt+f'),
      );
    });

    test('AltRight פיזי רגיל אינו AltGr מחוץ ל-Windows', () {
      final altActivator = ShortcutHelper.activatorFromShortcut('alt+arrowup')!;
      final ctrlAltActivator = ShortcutHelper.activatorFromShortcut(
        'ctrl+alt+arrowup',
      )!;
      final keyboard = HardwareKeyboard();
      keyboard.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.controlLeft,
          logicalKey: LogicalKeyboardKey.controlLeft,
          timeStamp: Duration.zero,
        ),
      );
      keyboard.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.altRight,
          logicalKey: LogicalKeyboardKey.altRight,
          timeStamp: Duration.zero,
        ),
      );
      final arrowUp = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.arrowUp,
        logicalKey: LogicalKeyboardKey.arrowUp,
        timeStamp: Duration.zero,
      );
      keyboard.handleKeyEvent(arrowUp);

      expect(altActivator.accepts(arrowUp, keyboard), isFalse);
      expect(ctrlAltActivator.accepts(arrowUp, keyboard), isTrue);
    });
  });

  group('ShortcutHelper.isPlainCtrlOrCmdPressed', () {
    testWidgets('Ctrl לבדו נחשב לחוץ', (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(ShortcutHelper.isPlainCtrlOrCmdPressed, isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(ShortcutHelper.isPlainCtrlOrCmdPressed, isFalse);
    });

    testWidgets('AltGr של Windows (Ctrl סינתטי + AltRight) נשלל', (
      tester,
    ) async {
      ShortcutHelper.isWindowsForTesting = true;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.altRight,
        physicalKey: PhysicalKeyboardKey.altRight,
      );
      expect(ShortcutHelper.isPlainCtrlOrCmdPressed, isFalse);

      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.altRight,
        physicalKey: PhysicalKeyboardKey.altRight,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('Ctrl+Alt שמאלי נשלל אף הוא', (tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      expect(ShortcutHelper.isPlainCtrlOrCmdPressed, isFalse);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('ב-Mac גם Cmd נחשב', (tester) async {
      ShortcutHelper.isMacForTesting = true;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      expect(ShortcutHelper.isPlainCtrlOrCmdPressed, isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
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
