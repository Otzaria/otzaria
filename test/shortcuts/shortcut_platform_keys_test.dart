import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';

/// זיהוי "מקלדת בסגנון Mac" (macOS ו-iOS), תווית מקש meta לפי פלטפורמה,
/// ו-modifier של "Ctrl או Cmd" לקיצורי כרטיסיות וגלגלת.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ShortcutHelper.isMacForTesting = null;
    ShortcutHelper.isLinuxForTesting = null;
    ShortcutHelper.isWindowsForTesting = null;
  });

  group('isMacLikeOperatingSystem', () {
    test('macOS and iOS use Cmd as the regular key', () {
      expect(ShortcutHelper.isMacLikeOperatingSystem('macos'), isTrue);
      expect(ShortcutHelper.isMacLikeOperatingSystem('ios'), isTrue);
    });

    test('other systems do not', () {
      for (final os in ['windows', 'linux', 'android', 'fuchsia']) {
        expect(
          ShortcutHelper.isMacLikeOperatingSystem(os),
          isFalse,
          reason: os,
        );
      }
    });
  });

  group('formatShortcutForDisplay: meta label', () {
    test('Windows shows WIN', () {
      ShortcutHelper.isMacForTesting = false;
      ShortcutHelper.isLinuxForTesting = false;
      expect(
        ShortcutHelper.formatShortcutForDisplay('meta+e'),
        startsWith('WIN + E'),
      );
    });

    test('Linux shows SUPER', () {
      ShortcutHelper.isMacForTesting = false;
      ShortcutHelper.isLinuxForTesting = true;
      expect(
        ShortcutHelper.formatShortcutForDisplay('meta+e'),
        startsWith('SUPER + E'),
      );
    });

    test('Mac still shows the command symbol', () {
      ShortcutHelper.isMacForTesting = true;
      ShortcutHelper.isLinuxForTesting = false;
      expect(
        ShortcutHelper.formatShortcutForDisplay('meta+e'),
        startsWith('⌘ + E'),
      );
    });
  });

  group('isCtrlOrMacCmdOnly', () {
    Future<void> hold(
      List<LogicalKeyboardKey> keys,
      void Function() body,
    ) async {
      for (final k in keys) {
        await simulateKeyDownEvent(k);
      }
      try {
        body();
      } finally {
        for (final k in keys.reversed) {
          await simulateKeyUpEvent(k);
        }
      }
    }

    testWidgets('Mac accepts Ctrl or Cmd, not both, not neither', (_) async {
      ShortcutHelper.isMacForTesting = true;
      await hold([LogicalKeyboardKey.controlLeft], () {
        expect(ShortcutHelper.isCtrlOrMacCmdOnly, isTrue);
      });
      await hold([LogicalKeyboardKey.metaLeft], () {
        expect(ShortcutHelper.isCtrlOrMacCmdOnly, isTrue);
      });
      await hold(
        [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.metaLeft,
        ],
        () {
          expect(ShortcutHelper.isCtrlOrMacCmdOnly, isFalse);
        },
      );
      expect(ShortcutHelper.isCtrlOrMacCmdOnly, isFalse);
    });

    testWidgets('other platforms accept only Ctrl', (_) async {
      ShortcutHelper.isMacForTesting = false;
      await hold([LogicalKeyboardKey.controlLeft], () {
        expect(ShortcutHelper.isCtrlOrMacCmdOnly, isTrue);
      });
      await hold([LogicalKeyboardKey.metaLeft], () {
        expect(ShortcutHelper.isCtrlOrMacCmdOnly, isFalse);
      });
      await hold(
        [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.metaLeft,
        ],
        () {
          expect(ShortcutHelper.isCtrlOrMacCmdOnly, isFalse);
        },
      );
    });
  });
}
