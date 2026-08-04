import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/view/sibling_commentaries_menu.dart';

Link _sourceLink({
  int index1 = 5,
  String path2 = 'ברכות',
  int baseProvenance = 0,
}) => Link(
  heRef: 'ברכות ד ב',
  index1: index1,
  path2: path2,
  index2: 10,
  connectionType: LinkTypes.source,
  targetCategoryId: 3,
  targetFileType: 'text',
  baseProvenance: baseProvenance,
);

Link _commentaryLink(String title) => Link(
  heRef: title,
  index1: 5,
  path2: title,
  index2: 2,
  connectionType: LinkTypes.commentary,
  targetCategoryId: 4,
  targetFileType: 'text',
);

void main() {
  group('SiblingCommentariesController', () {
    test('sourceLinkForLine מאתר את קישור ה-SOURCE של השורה', () {
      final c = SiblingCommentariesController(loadSiblings: (_) async => []);
      final linksByLine = {
        5: [_commentaryLink('רש"י'), _sourceLink()],
      };
      expect(
        c.sourceLinkForLine(linksByLine, 5)?.connectionType,
        LinkTypes.source,
      );
      expect(c.sourceLinkForLine(linksByLine, 6), isNull);
      c.dispose();
    });

    test('sourceLinkForLine מעדיף את יחס הבסיס המוצהר על ציטוט לטרלי', () {
      final c = SiblingCommentariesController(loadSiblings: (_) async => []);
      // סדר הקישורים בשורה אלפביתי לפי path2, ולכן הציטוט הלטרלי קודם.
      final linksByLine = {
        5: [
          _sourceLink(path2: 'אוצר לעזי רש"י'),
          _sourceLink(path2: 'בבא קמא', baseProvenance: 2),
        ],
      };
      expect(c.sourceLinkForLine(linksByLine, 5)?.path2, 'בבא קמא');
      c.dispose();
    });

    test('sourceLinkForLine שומר על הראשון כשה-provenance שווה', () {
      final c = SiblingCommentariesController(loadSiblings: (_) async => []);
      final linksByLine = {
        5: [
          _sourceLink(path2: 'ברכות', baseProvenance: 2),
          _sourceLink(path2: 'שבת', baseProvenance: 2),
        ],
      };
      expect(c.sourceLinkForLine(linksByLine, 5)?.path2, 'ברכות');
      c.dispose();
    });

    test('sourceLinkForLine מחזיר null כשבשורה אין קישור SOURCE', () {
      final c = SiblingCommentariesController(loadSiblings: (_) async => []);
      final linksByLine = {
        5: [_commentaryLink('רש"י')],
      };
      expect(c.sourceLinkForLine(linksByLine, 5), isNull);
      c.dispose();
    });

    test('buildEntry מחזיר null כשאין קישור מקור', () {
      final c = SiblingCommentariesController(loadSiblings: (_) async => []);
      expect(
        c.buildEntry(lineIndex: 1, sourceLink: null, onNavigate: (_) {}),
        isNull,
      );
      c.dispose();
    });

    test('buildEntry בונה תווית "מפרשים נוספים על ..." עם תת-תפריט', () {
      final c = SiblingCommentariesController(loadSiblings: (_) async => []);
      final entry = c.buildEntry(
        lineIndex: 1,
        sourceLink: _sourceLink(),
        onNavigate: (_) {},
      );
      expect(entry, isNotNull);
      expect(entry!.label, startsWith('מפרשים נוספים על'));
      expect(entry.childrenBuilder, isNotNull);
      expect(entry.childrenRefreshStream, isNotNull);
      c.dispose();
    });

    test(
      'childrenBuilder: placeholder בטעינה, ואז המפרשים (בלי טעינה כפולה)',
      () async {
        var loadCount = 0;
        final c = SiblingCommentariesController(
          loadSiblings: (_) async {
            loadCount++;
            return [_commentaryLink('ריטב"א'), _commentaryLink('רא"ש')];
          },
        );
        final entry = c.buildEntry(
          lineIndex: 1,
          sourceLink: _sourceLink(),
          onNavigate: (_) {},
        )!;

        final loading = entry.childrenBuilder!();
        expect(loading.length, 1);
        expect(loading.first.enabled, isFalse);

        await Future<void>.delayed(const Duration(milliseconds: 10));

        final loaded = entry.childrenBuilder!();
        expect(loaded.length, 2);
        expect(loadCount, 1);
        c.dispose();
      },
    );

    test('childrenBuilder מציג "אין מפרשים נוספים" כשאין תוצאות', () async {
      final c = SiblingCommentariesController(loadSiblings: (_) async => []);
      final entry = c.buildEntry(
        lineIndex: 2,
        sourceLink: _sourceLink(),
        onNavigate: (_) {},
      )!;

      entry.childrenBuilder!();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final result = entry.childrenBuilder!();
      expect(result.length, 1);
      expect(result.first.label, 'אין מפרשים נוספים');
      expect(result.first.enabled, isFalse);
      c.dispose();
    });

    test('טעינה שהתחילה לפני clear() לא כותבת תוצאות ישנות למטמון', () async {
      final gate = Completer<List<Link>>();
      final c = SiblingCommentariesController(loadSiblings: (_) => gate.future);
      final entry = c.buildEntry(
        lineIndex: 1,
        sourceLink: _sourceLink(),
        onNavigate: (_) {},
      )!;

      entry.childrenBuilder!(); // מתחיל טעינה (Future תלוי)
      c.clear(); // מעבר ספר באמצע הטעינה
      gate.complete([_commentaryLink('ריטב"א')]); // הטעינה הישנה מסתיימת
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // הקריאה הבאה מתחילה טעינה חדשה (המטמון לא זוהם ע"י התוצאה הישנה).
      final result = entry.childrenBuilder!();
      expect(result.length, 1);
      expect(result.first.enabled, isFalse); // "טוען מפרשים…"
      c.dispose();
    });

    test('clear מנקה את המטמון וגורם לטעינה מחדש', () async {
      var loadCount = 0;
      final c = SiblingCommentariesController(
        loadSiblings: (_) async {
          loadCount++;
          return [_commentaryLink('ריטב"א')];
        },
      );
      final entry = c.buildEntry(
        lineIndex: 1,
        sourceLink: _sourceLink(),
        onNavigate: (_) {},
      )!;

      entry.childrenBuilder!();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(loadCount, 1);

      c.clear();
      entry.childrenBuilder!();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(loadCount, 2);
      c.dispose();
    });
  });
}
