import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';

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
}
