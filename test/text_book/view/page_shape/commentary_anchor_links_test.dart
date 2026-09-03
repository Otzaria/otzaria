import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/view/page_shape/utils/commentary_anchor_links.dart';

Link _link({
  required int index1,
  String path2 = 'שער הציון',
  String connectionType = 'COMMENTARY',
  int? anchorStart,
}) {
  return Link(
    heRef: '$path2, לב, ה',
    index1: index1,
    path2: path2,
    index2: 1,
    connectionType: connectionType,
    anchorStart: anchorStart,
  );
}

void main() {
  group('commentaryAnchorTargetTitles', () {
    test('מחזיר יעדים תלויי-טקסט (COMMENTARY, SUPER_COMMENTARY), עם נרמול', () {
      const targets = [
        LinkTargetSummary(
          targetTitle: 'שער הציון',
          connectionType: 'COMMENTARY',
          linkCount: 17980,
        ),
        LinkTargetSummary(
          targetTitle: 'מפרש-על',
          connectionType: 'super_commentary',
          linkCount: 12,
        ),
        LinkTargetSummary(
          targetTitle: 'שולחן ערוך, אורח חיים',
          connectionType: 'REFERENCE',
          linkCount: 1461,
        ),
        LinkTargetSummary(
          targetTitle: 'בראשית',
          connectionType: 'LINKER',
          linkCount: 67,
        ),
      ];
      expect(commentaryAnchorTargetTitles(targets), {'שער הציון', 'מפרש-על'});
    });

    test('ריק כשאין יעדים תלויי-טקסט', () {
      const targets = [
        LinkTargetSummary(
          targetTitle: 'שולחן ערוך, יורה דעה',
          connectionType: 'OTHER',
          linkCount: 146,
        ),
      ];
      expect(commentaryAnchorTargetTitles(targets), isEmpty);
    });
  });

  group('filterCommentaryAnchorLinks', () {
    test('משאיר רק קישורים תלויי-טקסט שנושאים עוגן', () {
      final links = [
        _link(index1: 1, anchorStart: 4),
        _link(index1: 2), // בלי עוגן — אין היכן להציב סמן
        _link(index1: 3, connectionType: 'LINKER', anchorStart: 2),
        _link(index1: 4, connectionType: 'REFERENCE', anchorStart: 2),
        _link(index1: 5, connectionType: 'SUPER_COMMENTARY', anchorStart: 9),
      ];
      final filtered = filterCommentaryAnchorLinks(links);
      expect(filtered.map((link) => link.index1), [1, 5]);
    });
  });

  group('mergeAnchorLinksByLine', () {
    test('ממפה לפי index1 ואינו משנה את המפה הקיימת', () {
      final existing = {
        5: [_link(index1: 5, anchorStart: 0)],
      };
      final merged = mergeAnchorLinksByLine(existing, [
        _link(index1: 7, anchorStart: 1),
        _link(index1: 7, anchorStart: 9),
      ]);
      expect(merged.keys, containsAll([5, 7]));
      expect(merged[7], hasLength(2));
      expect(existing.keys, [5]);
    });

    test('שליפה חוזרת של שורה מחליפה אותה ואינה מכפילה סמנים', () {
      final existing = {
        7: [_link(index1: 7, anchorStart: 1)],
      };
      final merged = mergeAnchorLinksByLine(existing, [
        _link(index1: 7, anchorStart: 1),
      ]);
      expect(merged[7], hasLength(1));
    });

    test('שליפה ריקה מחזירה את המפה הקיימת עצמה', () {
      final existing = {
        5: [_link(index1: 5, anchorStart: 0)],
      };
      expect(
        identical(mergeAnchorLinksByLine(existing, const []), existing),
        isTrue,
      );
    });
  });
}
