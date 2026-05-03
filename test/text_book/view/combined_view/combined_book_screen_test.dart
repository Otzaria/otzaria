import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';

void main() {
  group('buildCombinedViewContextMenuLinksForParagraph', () {
    test('מחזירה רק קישורים רגילים של הפסקה שנלחצה', () {
      final linksByLine = <int, List<Link>>{
        3: [
          Link(
            heRef: 'בראשית ג ב',
            index1: 3,
            path2: 'zfoo/zzz.txt',
            index2: 10,
            connectionType: 'REFERENCE',
          ),
          Link(
            heRef: 'בראשית ג',
            index1: 3,
            path2: 'foo/bar.txt',
            index2: 7,
            connectionType: 'REFERENCE',
          ),
          Link(
            heRef: 'רש"י על בראשית ג',
            index1: 3,
            path2: 'commentary/rashi.txt',
            index2: 7,
            connectionType: 'COMMENTARY',
          ),
          Link(
            heRef: 'בראשית ג inline',
            index1: 3,
            path2: 'foo/inline.txt',
            index2: 8,
            connectionType: 'REFERENCE',
            start: 1,
            end: 4,
          ),
        ],
        4: [
          Link(
            heRef: 'בראשית ד',
            index1: 4,
            path2: 'foo/other.txt',
            index2: 9,
            connectionType: 'REFERENCE',
          ),
        ],
      };

      final result = buildCombinedViewContextMenuLinksForParagraph(
        linksByLine: linksByLine,
        paragraphIndex: 2,
      );

      expect(result, hasLength(2));
      expect(result.map((link) => link.heRef), ['בראשית ג', 'בראשית ג ב']);
    });

    test('מחזירה רשימה ריקה כשאין קישורים לפסקה', () {
      final result = buildCombinedViewContextMenuLinksForParagraph(
        linksByLine: const <int, List<Link>>{},
        paragraphIndex: 10,
      );

      expect(result, isEmpty);
    });
  });

  group('shouldShowOpenCommentatorsPaneEntry', () {
    test('מחזירה true רק כשיש מפרשים, החלונית בצד, והיא סגורה', () {
      expect(
        shouldShowOpenCommentatorsPaneEntry(
          hasAvailableCommentators: true,
          showCommentaryAsExpansionTiles: false,
          isPaneOpen: false,
        ),
        isTrue,
      );
    });

    test('מחזירה false כשאין מפרשים זמינים', () {
      expect(
        shouldShowOpenCommentatorsPaneEntry(
          hasAvailableCommentators: false,
          showCommentaryAsExpansionTiles: false,
          isPaneOpen: false,
        ),
        isFalse,
      );
    });

    test('מחזירה false כשהמפרשים מוצגים כהרחבה מתחת לטקסט', () {
      expect(
        shouldShowOpenCommentatorsPaneEntry(
          hasAvailableCommentators: true,
          showCommentaryAsExpansionTiles: true,
          isPaneOpen: false,
        ),
        isFalse,
      );
    });

    test('מחזירה false כשהחלונית כבר פתוחה', () {
      expect(
        shouldShowOpenCommentatorsPaneEntry(
          hasAvailableCommentators: true,
          showCommentaryAsExpansionTiles: false,
          isPaneOpen: true,
        ),
        isFalse,
      );
    });
  });
}
