import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/book_source.dart';
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
        expect(e.icon, isNotNull);
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

  testWidgets('קישור ארוך מעתיק את הטקסט ומציע קישור למקטע לבחירה', (
    tester,
  ) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
    );

    final selection = List.filled(15, 'בראשית').join(' ');
    final entries = buildDirectLinkContextMenuEntries(
      bookId: 42,
      index: 7,
      source: BookSource.attached('library'),
      selectedText: selection,
    );
    entries.last.onTap!();
    await tester.pumpAndSettle();
    final precise = Uri.parse(copied!).queryParameters;
    expect(precise, {'source': 'db:library', 'index': '7', 'm': selection});

    await tester.tap(find.text(CommonMessages.copyShortSectionMarkLink));
    await tester.pumpAndSettle();
    final short = Uri.parse(copied!).queryParameters;
    expect(short, {'source': 'db:library', 'index': '7', 'mark': ''});
    UiSnack.hide();
    await tester.pumpAndSettle();
  });

  group('buildCopyDirectLinkEntry', () {
    test('opens the direct links as its submenu', () {
      final entry = buildCopyDirectLinkEntry(
        bookId: 7,
        index: 3,
        selectedText: 'שלום',
      );

      expect(entry.label, 'העתק קישור ישיר');
      expect(
        entry.childrenBuilder!().map((e) => e.label),
        buildDirectLinkContextMenuEntries(
          bookId: 7,
          index: 3,
          selectedText: 'שלום',
        ).map((e) => e.label),
      );
    });
  });
}
