import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';

Link _link({
  required int index1,
  required String path2,
  required String connectionType,
}) {
  return Link(
    heRef: 'א',
    index1: index1,
    path2: path2,
    index2: 1,
    connectionType: connectionType,
  );
}

void main() {
  group('aggregateLinkTargetsFromLinks — סיווג יעדים מרשימת קישורים', () {
    test('מפרשים נספרים פר-כותרת, יעדים אחרים נאספים בנפרד', () {
      final aggregation = aggregateLinkTargetsFromLinks([
        _link(
          index1: 10,
          path2: 'רש"י על בראשית',
          connectionType: 'COMMENTARY',
        ),
        _link(
          index1: 25,
          path2: 'רש"י על בראשית',
          connectionType: 'COMMENTARY',
        ),
        _link(index1: 12, path2: 'תרגום אונקלוס', connectionType: 'TARGUM'),
        _link(index1: 40, path2: 'ילקוט שמעוני', connectionType: 'reference'),
        _link(index1: 7, path2: 'מדרש רבה', connectionType: 'SOURCE'),
      ]);

      expect(aggregation.commentators, {'רש"י על בראשית', 'תרגום אונקלוס'});
      expect(aggregation.linkCountByTitle['רש"י על בראשית'], 2);
      expect(aggregation.linkCountByTitle['תרגום אונקלוס'], 1);
      expect(aggregation.nonCommentaryTitles, {'ילקוט שמעוני', 'מדרש רבה'});
      expect(aggregation.maxSourceLine, 40);
    });

    test('רשימה ריקה (חלון בלי קישורים) — תוצאה ריקה בלי קריסה', () {
      final aggregation = aggregateLinkTargetsFromLinks(const []);
      expect(aggregation.commentators, isEmpty);
      expect(aggregation.nonCommentaryTitles, isEmpty);
      expect(aggregation.maxSourceLine, 0);
    });
  });

  group('aggregateLinkTargetsFromSummary — סיווג יעדים מסיכום המסד', () {
    test('ספירות מפרשים נלקחות מהסיכום, SOURCE לא נכנס לספירה', () {
      final aggregation = aggregateLinkTargetsFromSummary(
        const [
          LinkTargetSummary(
            targetTitle: 'רש"י על בראשית',
            connectionType: 'COMMENTARY',
            linkCount: 120,
          ),
          LinkTargetSummary(
            targetTitle: 'ילקוט שמעוני',
            connectionType: 'reference',
            linkCount: 3,
          ),
          // שורת inverse: הספירה שלה לא משפיעה על סיווג "מפרש נדיר" —
          // SOURCE אינו סוג תלוי-טקסט, והכותרת נאספת רק ל-preload דורות.
          LinkTargetSummary(
            targetTitle: 'מדרש רבה',
            connectionType: 'SOURCE',
            linkCount: 1,
          ),
        ],
        500,
      );

      expect(aggregation.commentators, {'רש"י על בראשית'});
      expect(aggregation.linkCountByTitle['רש"י על בראשית'], 120);
      expect(aggregation.linkCountByTitle.containsKey('מדרש רבה'), isFalse);
      expect(aggregation.nonCommentaryTitles, {'ילקוט שמעוני', 'מדרש רבה'});
      expect(aggregation.maxSourceLine, 500);
    });
  });

  test('שקילות: סיכום ורשימת קישורים מסווגים אותם נתונים לוגיים זהה', () {
    // אותו ספר: 2 קישורי רש"י, קישור הפניה אחד, קישור SOURCE אחד.
    final fromLinks = aggregateLinkTargetsFromLinks([
      _link(index1: 10, path2: 'רש"י על בראשית', connectionType: 'COMMENTARY'),
      _link(index1: 25, path2: 'רש"י על בראשית', connectionType: 'COMMENTARY'),
      _link(index1: 40, path2: 'ילקוט שמעוני', connectionType: 'reference'),
      _link(index1: 7, path2: 'מדרש רבה', connectionType: 'SOURCE'),
    ]);
    final fromSummary = aggregateLinkTargetsFromSummary(
      const [
        LinkTargetSummary(
          targetTitle: 'רש"י על בראשית',
          connectionType: 'COMMENTARY',
          linkCount: 2,
        ),
        LinkTargetSummary(
          targetTitle: 'ילקוט שמעוני',
          connectionType: 'reference',
          linkCount: 1,
        ),
        LinkTargetSummary(
          targetTitle: 'מדרש רבה',
          connectionType: 'SOURCE',
          linkCount: 1,
        ),
      ],
      40,
    );

    expect(fromSummary.commentators, fromLinks.commentators);
    expect(fromSummary.linkCountByTitle, fromLinks.linkCountByTitle);
    expect(fromSummary.nonCommentaryTitles, fromLinks.nonCommentaryTitles);
    expect(fromSummary.maxSourceLine, fromLinks.maxSourceLine);
  });
}
