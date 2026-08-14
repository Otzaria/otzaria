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

    test('buildEntries מחזיר רשימה ריקה כשאין קישור מקור', () {
      final c = SiblingCommentariesController(loadSiblings: (_) async => []);
      expect(
        c.buildEntries(lineIndex: 1, sourceLink: null, onNavigate: (_) {}),
        isEmpty,
      );
      c.dispose();
    });

    test('buildEntries בונה "מפרשים נוספים על ..." ושורת הספר המקורי', () {
      final c = SiblingCommentariesController(loadSiblings: (_) async => []);
      final entries = c.buildEntries(
        lineIndex: 1,
        sourceLink: _sourceLink(),
        onNavigate: (_) {},
      );
      expect(entries.length, 2);

      // הראשון: תת-התפריט "מפרשים נוספים על ..."
      final siblings = entries[0];
      expect(siblings.label, startsWith('מפרשים נוספים על'));
      expect(siblings.childrenBuilder, isNotNull);
      expect(siblings.childrenRefreshStream, isNotNull);

      // השני: שורת הספר המקורי שפותחת את המקור במיקום הנוכחי.
      final original = entries[1];
      expect(original.label, contains('ברכות'));
      expect(original.onTap, isNotNull);
      c.dispose();
    });

    test('שורת הספר המקורי מנווטת לקישור המקור בעת לחיצה', () {
      final c = SiblingCommentariesController(loadSiblings: (_) async => []);
      Link? navigated;
      final entries = c.buildEntries(
        lineIndex: 1,
        sourceLink: _sourceLink(),
        onNavigate: (link) => navigated = link,
      );
      entries[1].onTap!();
      expect(navigated, isNotNull);
      expect(navigated!.connectionType, LinkTypes.source);
      expect(navigated!.path2, 'ברכות');
      expect(navigated!.index2, 10);
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
        final entry = c.buildEntries(
          lineIndex: 1,
          sourceLink: _sourceLink(),
          onNavigate: (_) {},
        )[0];

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
      final entry = c.buildEntries(
        lineIndex: 2,
        sourceLink: _sourceLink(),
        onNavigate: (_) {},
      )[0];

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
      final entry = c.buildEntries(
        lineIndex: 1,
        sourceLink: _sourceLink(),
        onNavigate: (_) {},
      )[0];

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
      final entry = c.buildEntries(
        lineIndex: 1,
        sourceLink: _sourceLink(),
        onNavigate: (_) {},
      )[0];

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
