import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';

void main() {
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
}
