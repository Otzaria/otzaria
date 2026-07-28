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

    test('שורות סיכום כפולות לאותו מפרש מצטברות לספירה אחת', () {
      final aggregation = aggregateLinkTargetsFromSummary(
        const [
          LinkTargetSummary(
            targetTitle: 'רש"י על בראשית',
            connectionType: 'COMMENTARY',
            linkCount: 7,
          ),
          LinkTargetSummary(
            targetTitle: 'רש"י על בראשית',
            connectionType: 'COMMENTARY',
            linkCount: 5,
          ),
        ],
        80,
      );

      expect(aggregation.commentators, {'רש"י על בראשית'});
      expect(aggregation.linkCountByTitle, {'רש"י על בראשית': 12});
    });
  });

  group('aggregateLinkTargetsForCommentatorSelection — מקור הרשימה', () {
    test('חלון חלקי משתמש בסיכום ומציג גם מפרש שאינו בחלון הנוכחי', () {
      final aggregation = aggregateLinkTargetsForCommentatorSelection(
        linksAreComplete: false,
        links: [
          _link(
            index1: 2010,
            path2: 'רש"י על זבחים',
            connectionType: 'COMMENTARY',
          ),
        ],
        summaryTargets: const [
          LinkTargetSummary(
            targetTitle: 'רש"י על זבחים',
            connectionType: 'COMMENTARY',
            linkCount: 900,
          ),
          LinkTargetSummary(
            targetTitle: 'תוספות על זבחים',
            connectionType: 'COMMENTARY',
            linkCount: 750,
          ),
        ],
        summaryMaxSourceLine: 5000,
      );

      expect(aggregation.commentators, {
        'רש"י על זבחים',
        'תוספות על זבחים',
      });
      expect(aggregation.linkCountByTitle['תוספות על זבחים'], 750);
      expect(aggregation.maxSourceLine, 5000);
    });

    test('חלון ריק עדיין מקבל את כל המפרשים מהסיכום', () {
      final aggregation = aggregateLinkTargetsForCommentatorSelection(
        linksAreComplete: false,
        links: const [],
        summaryTargets: const [
          LinkTargetSummary(
            targetTitle: 'קרן אורה על זבחים',
            connectionType: 'COMMENTARY',
            linkCount: 42,
          ),
          LinkTargetSummary(
            targetTitle: 'שפת אמת על זבחים',
            connectionType: 'COMMENTARY',
            linkCount: 31,
          ),
        ],
        summaryMaxSourceLine: 4200,
      );

      expect(aggregation.commentators, {
        'קרן אורה על זבחים',
        'שפת אמת על זבחים',
      });
    });

    test('סיכום כלל־ספרי ריק הוא סמכותי ואינו מוחלף בחלון חלקי', () {
      final aggregation = aggregateLinkTargetsForCommentatorSelection(
        linksAreComplete: false,
        links: [
          _link(
            index1: 10,
            path2: 'מפרש מחלון ישן',
            connectionType: 'COMMENTARY',
          ),
        ],
        summaryTargets: const [],
        summaryMaxSourceLine: 100,
      );

      expect(aggregation.commentators, isEmpty);
      expect(aggregation.maxSourceLine, 100);
    });

    test('כשל בסיכום נופל בבטחה למפרשים שבחלון הטעון', () {
      final aggregation = aggregateLinkTargetsForCommentatorSelection(
        linksAreComplete: false,
        links: [
          _link(
            index1: 33,
            path2: 'רש"י על זבחים',
            connectionType: 'COMMENTARY',
          ),
        ],
      );

      expect(aggregation.commentators, {'רש"י על זבחים'});
      expect(aggregation.maxSourceLine, 33);
    });

    test('רשימת קישורים מלאה קודמת לסיכום ישן', () {
      final aggregation = aggregateLinkTargetsForCommentatorSelection(
        linksAreComplete: true,
        links: [
          _link(
            index1: 50,
            path2: 'רש"י על זבחים',
            connectionType: 'COMMENTARY',
          ),
          _link(
            index1: 80,
            path2: 'תוספות על זבחים',
            connectionType: 'COMMENTARY',
          ),
        ],
        summaryTargets: const [
          LinkTargetSummary(
            targetTitle: 'מפרש שאינו ברשימה המלאה',
            connectionType: 'COMMENTARY',
            linkCount: 1,
          ),
        ],
        summaryMaxSourceLine: 9999,
      );

      expect(aggregation.commentators, {
        'רש"י על זבחים',
        'תוספות על זבחים',
      });
      expect(
        aggregation.commentators,
        isNot(contains('מפרש שאינו ברשימה המלאה')),
      );
      expect(aggregation.maxSourceLine, 80);
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
