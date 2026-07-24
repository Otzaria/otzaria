import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/direct_link_menu_entries.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildDirectLinkContextMenuEntries', () {
    test('ללא טקסט מסומן — 2 פריטים פעילים', () {
      final entries = buildDirectLinkContextMenuEntries(
        bookId: 42,
        index: 7,
        selectedText: null,
      );

      expect(entries.length, 2, reason: 'מקטע/הדגשת מקטע');
      for (final e in entries) {
        expect(e.enabled, isTrue);
        expect(e.onTap, isNotNull);
        expect(e.icon, FluentIcons.link_24_regular);
        expect(e.label, isNotNull);
      }
    });

    test('טקסט מסומן ריק/רווחים — עדיין 2 פריטים', () {
      for (final empty in ['', '   ', '\t\n']) {
        final entries = buildDirectLinkContextMenuEntries(
          bookId: 1,
          index: 0,
          selectedText: empty,
        );
        expect(entries.length, 2, reason: 'selectedText="$empty"');
      }
    });

    test('טקסט מסומן לא ריק — 3 פריטים והאחרון להדגשת טקסט', () {
      final entries = buildDirectLinkContextMenuEntries(
        bookId: 1,
        index: 0,
        selectedText: 'בראשית',
      );

      expect(entries.length, 3);
      expect(entries.last.label, contains('הדגשת הטקסט'));
      expect(entries.last.enabled, isTrue);
      expect(entries.last.onTap, isNotNull);
    });

    test('label של כל פריט ברור ומתאר את הפעולה', () {
      final entries = buildDirectLinkContextMenuEntries(
        bookId: 1,
        index: 5,
        selectedText: 'טקסט',
      );

      expect(entries[0].label, contains('למקטע'));
      expect(entries[1].label, contains('הדגשת המקטע'));
      expect(entries[2].label, contains('הדגשת הטקסט'));
    });

    test('הקשה על פריט מעתיקה את הקישור הנכון ללוח', () async {
      String? capturedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              capturedText = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });

      try {
        final entries = buildDirectLinkContextMenuEntries(
          bookId: 42,
          index: 7,
          selectedText: null,
        );

        // פריט 0 — קישור למקטע
        entries[0].onTap!();
        await Future<void>.delayed(Duration.zero);
        expect(capturedText, 'otzaria://open/book/42?index=7');

        // פריט 1 — קישור עם הדגשת מקטע
        entries[1].onTap!();
        await Future<void>.delayed(Duration.zero);
        expect(capturedText, 'otzaria://open/book/42?index=7&mark');
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      }
    });

    test('פריט הדגשת טקסט מעתיק קישור עם ?m= מקודד', () async {
      String? capturedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              capturedText = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });

      try {
        final entries = buildDirectLinkContextMenuEntries(
          bookId: 1,
          index: 3,
          selectedText: 'בראשית',
        );

        entries.last.onTap!();
        await Future<void>.delayed(Duration.zero);

        expect(capturedText, isNotNull);
        expect(capturedText, startsWith('otzaria://open/book/1?index=3&m='));
        // הטקסט העברי צריך להיות URL-encoded ולא לעבור בגלוי.
        expect(capturedText, isNot(contains('בראשית')));
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      }
    });
  });
}
