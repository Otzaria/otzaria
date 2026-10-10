import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/text_display/view/copy_as_menu.dart';

void main() {
  group('buildCopyAsMenuEntries — אייקונים', () {
    test('לכל וריאציה אייקון משלה', () {
      final entries = buildCopyAsMenuEntries(
        base: const TextDisplayProfile(),
        hasSelection: true,
        onCopy: (_) {},
      );

      final icons = entries.map((entry) => entry.icon).toList();
      expect(icons.toSet().length, icons.length);
    });

    // הדדופ מפיל וריאציה שהפרופיל שלה זהה לקודמתה. כשהפיסוק כבר מוסר
    // ב-base, "בלי ניקוד וטעמים" ו"בלי ניקוד, טעמים ופיסוק" מתלכדות — ואסור
    // שהשורה ששורדת תישא אייקון שמבטיח פיסוק.
    test('פיסוק מוסר ב-base — השורה ששורדת אינה מבטיחה פיסוק', () {
      final entries = buildCopyAsMenuEntries(
        base: const TextDisplayProfile(punctuation: MarkVisibility.hide),
        hasSelection: true,
        onCopy: (_) {},
      );

      final labels = entries.map((entry) => entry.label).toList();
      // הדדופ הפיל את "בלי ניקוד, טעמים ופיסוק" — הפרופיל שלה זהה.
      expect(labels, contains('בלי ניקוד וטעמים'));
      expect(labels, isNot(contains('בלי ניקוד, טעמים ופיסוק')));

      // והשורה ששרדה נושאת את המחיקה הסתמית ולא את המחק: המחק הוא
      // האייקון שמבטיח הסרת פיסוק, והפיסוק כאן רק *יורש* מ-base.
      final survivor = entries.firstWhere(
        (entry) => entry.label == 'בלי ניקוד וטעמים',
      );
      expect(survivor.icon, OtzariaIcons.alef_delete_24_filled);
    });
  });

  group('buildCopyAsMenuEntry', () {
    test('is disabled without a selection', () {
      for (final text in [null, '', '  ']) {
        final entry = buildCopyAsMenuEntry(
          base: const TextDisplayProfile(),
          selectedText: text,
          onCopy: (_) {},
        );
        expect(entry.label, 'העתק כ...');
        expect(entry.enabled, isFalse);
        expect(entry.children!.every((child) => !child.enabled), isTrue);
      }
    });

    test('copies the selection with the chosen variant', () {
      final copied = <TextDisplayProfile>[];
      final entry = buildCopyAsMenuEntry(
        base: const TextDisplayProfile(),
        selectedText: 'שלום',
        onCopy: copied.add,
      );

      expect(entry.enabled, isTrue);
      entry.children!.first.onTap!();
      expect(copied, [const TextDisplayProfile()]);
    });
  });
}
