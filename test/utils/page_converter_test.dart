import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/file/page_converter.dart';
import 'package:otzaria/utils/file/page_map_builder.dart';
import 'package:pdfrx/pdfrx.dart';

PdfOutlineNode node(
  String title,
  int? page, {
  List<PdfOutlineNode> children = const [],
}) {
  return PdfOutlineNode(
    title: title,
    dest: page == null ? null : PdfDest(page, PdfDestCommand.fit, null),
    children: children,
  );
}

void main() {
  group('collectPdfAnchors', () {
    test('אוסף עוגנים מעץ מקונן עם נתיב מלא', () {
      final outline = [
        node(
          'ברכות',
          1,
          children: [
            node('ב.', 2),
            node('ג.', 3),
          ],
        ),
      ];

      final anchors = collectPdfAnchors(outline);

      expect(anchors, hasLength(3));
      expect(anchors[0], (page: 1, ref: 'ברכות'));
      expect(anchors[1], (page: 2, ref: 'ברכות/ב.'));
      expect(anchors[2], (page: 3, ref: 'ברכות/ג.'));
    });

    test('הכותרות עוברות נרמול (רווחים כפולים וסימני פיסוק)', () {
      final anchors = collectPdfAnchors([node('  פרק   א!  ', 5)]);

      expect(anchors.single.ref, 'פרק א');
    });

    test('צומת ללא יעד מדולג יחד עם תת-העץ שלו', () {
      final outline = [
        node('שער', null, children: [node('פנימי', 7)]),
        node('תוכן', 2),
      ];

      final anchors = collectPdfAnchors(outline);

      expect(anchors, hasLength(1));
      expect(anchors.single.page, 2);
    });

    test('מספר עמוד לא חוקי (0 או שלילי) מדולג', () {
      final anchors = collectPdfAnchors([node('ריק', 0), node('תקין', 4)]);

      expect(anchors.single.page, 4);
    });

    test('רשימה ריקה מחזירה רשימה ריקה', () {
      expect(collectPdfAnchors(const []), isEmpty);
    });
  });

  group('collectTextAnchors', () {
    test('אוסף עוגנים מתוכן עניינים מקונן עם נתיב מלא', () {
      final root = TocEntry(text: 'ברכות', index: 0);
      root.children = [
        TocEntry(text: 'ב.', index: 5, level: 2, parent: root),
        TocEntry(text: 'ג.', index: 12, level: 2, parent: root),
      ];

      final anchors = collectTextAnchors([root]);

      expect(anchors, hasLength(3));
      expect(anchors[0], (index: 0, ref: 'ברכות'));
      expect(anchors[1], (index: 5, ref: 'ברכות/ב.'));
      expect(anchors[2], (index: 12, ref: 'ברכות/ג.'));
    });

    test('טקסט הכניסה עובר נרמול וקיצוץ רווחים', () {
      final anchors = collectTextAnchors([
        TocEntry(text: ' פרק   א ', index: 3),
      ]);

      expect(anchors.single.ref, 'פרק א');
    });

    test('רשימה ריקה מחזירה רשימה ריקה', () {
      expect(collectTextAnchors(const []), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // השרשרת המלאה שהאפליקציה מריצה: outline → TOC → מפת עמודים.
  // ---------------------------------------------------------------------------
  group('שרשרת מלאה — מסכת גמרא', () {
    /// עץ ה-outline של מסכת בבלי: צומת שורש ותחתיו כל הדפים.
    List<PdfOutlineNode> talmudOutline() => [
      node(
        'ברכות',
        1,
        children: [
          node('דף ב.', 1),
          node('דף ב:', 2),
          node('דף ג.', 3),
        ],
      ),
    ];

    test('מהדורות תואמות — מפה אמינה מלאה', () {
      final root = TocEntry(text: 'ברכות', index: 0);
      root.children = [
        TocEntry(text: 'דף ב.', index: 1, level: 2, parent: root),
        TocEntry(text: 'דף ב:', index: 16, level: 2, parent: root),
        TocEntry(text: 'דף ג.', index: 36, level: 2, parent: root),
      ];

      final map = buildPageMapFromAnchors(
        collectPdfAnchors(talmudOutline()),
        collectTextAnchors([root]),
      );

      expect(map.hasReliableAnchors, isTrue);
      expect(map.pdfPages, [1, 2, 3]);
      expect(map.textIndices, [0, 16, 36]);
      expect(map.textToPdf(16), 2);
      expect(map.pdfToText(3), 36);
    });

    test('מהדורת טקסט בכתיב שונה — נגשרת ואינה נופלת לתחילת הספר', () {
      // "תלמוד בבלי - ברכות" / "פרק ראשון - מאימתי" / "דף ב - א"
      final root = TocEntry(text: 'תלמוד בבלי - ברכות', index: 0);
      final chapter = TocEntry(
        text: 'פרק ראשון - מאימתי',
        index: 1,
        level: 2,
        parent: root,
      );
      chapter.children = [
        TocEntry(text: 'דף ב - א', index: 2, level: 3, parent: chapter),
        TocEntry(text: 'דף ב - ב', index: 13, level: 3, parent: chapter),
        TocEntry(text: 'דף ג - א', index: 19, level: 3, parent: chapter),
      ];
      root.children = [chapter];

      final map = buildPageMapFromAnchors(
        collectPdfAnchors(talmudOutline()),
        collectTextAnchors([root]),
      );

      expect(map.hasReliableAnchors, isTrue);
      expect(map.pdfPages, [1, 2, 3]);
      expect(map.textIndices, [2, 13, 19]);
    });

    test('PDF ללא סימניות — מפה לא אמינה, ואינה נשמרת כמצב תקין', () {
      final root = TocEntry(text: 'ברכות', index: 0);
      root.children = [
        TocEntry(text: 'דף ב.', index: 1, level: 2, parent: root),
      ];

      final map = buildPageMapFromAnchors(
        collectPdfAnchors(const []),
        collectTextAnchors([root]),
      );

      expect(map.pdfPages, isEmpty);
      expect(map.hasReliableAnchors, isFalse);
      expect(map.textToPdf(0), isNull);
      expect(map.pdfToText(1), isNull);
    });
  });
}
