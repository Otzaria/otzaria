import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';

void main() {
  group('Commentary Grouping Tests', () {
    test('Groups consecutive links from same book', () {
      // יצירת קישורים מאותו ספר ברצף
      final links = [
        Link(
          heRef: 'פירוש א',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 1,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש ב',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 2,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש ג',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 3,
          connectionType: 'commentary',
        ),
      ];

      final groups = groupConsecutiveLinksForTesting(links);

      // צריך להיות רק קבוצה אחת
      expect(groups.length, 1);
      expect(groups[0].links.length, 3);
    });

    test('Separates non-consecutive links from different books', () {
      // יצירת קישורים מספרים שונים
      final links = [
        Link(
          heRef: 'פירוש א',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 1,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש ב',
          index1: 1,
          path2: '/books/commentary2.txt',
          index2: 1,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש ג',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 2,
          connectionType: 'commentary',
        ),
      ];

      final groups = groupConsecutiveLinksForTesting(links);

      // צריך להיות 3 קבוצות - כל קישור מספר אחר או לא רצוף
      expect(groups.length, 3);
      expect(groups[0].links.length, 1);
      expect(groups[1].links.length, 1);
      expect(groups[2].links.length, 1);
    });

    test('Groups only consecutive segments from same book', () {
      // יצירת קישורים שבהם יש רצף ואז הפרדה ואז רצף נוסף
      final links = [
        Link(
          heRef: 'פירוש א1',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 1,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש א2',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 2,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש ב',
          index1: 1,
          path2: '/books/commentary2.txt',
          index2: 1,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש א3',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 3,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש א4',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 4,
          connectionType: 'commentary',
        ),
      ];

      final groups = groupConsecutiveLinksForTesting(links);

      // צריך להיות 3 קבוצות:
      // 1. commentary1: פריטים 1-2
      // 2. commentary2: פריט 1
      // 3. commentary1: פריטים 3-4
      expect(groups.length, 3);
      expect(groups[0].links.length, 2);
      expect(groups[1].links.length, 1);
      expect(groups[2].links.length, 2);
    });

    test('Handles empty list', () {
      final links = <Link>[];
      final groups = groupConsecutiveLinksForTesting(links);
      expect(groups.length, 0);
    });

    test('Handles single link', () {
      final links = [
        Link(
          heRef: 'פירוש א',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 1,
          connectionType: 'commentary',
        ),
      ];

      final groups = groupConsecutiveLinksForTesting(links);
      expect(groups.length, 1);
      expect(groups[0].links.length, 1);
    });

    test('"הערות על XX" ממוינת מיד אחרי XX, גם כשא"ב היה מקדים אותה', () {
      // מטמון דורות ריק => כל הספרים בדור "שאר מפרשים", כך שהמיון נקבע לפי
      // העיגון בלבד. באלפבית "הערות" (ה) קודם ל"חברותא" (ח) — כאן זה מתהפך.
      CommentaryService.clearEraCache();
      Link linkFor(String title, int index2) => Link(
        heRef: title,
        index1: 1,
        path2: title,
        index2: index2,
        connectionType: 'COMMENTARY',
      );

      final sorted = CommentaryService.sortLinksByEraSync([
        linkFor('הערות על חברותא על ברכות', 1),
        linkFor('אבן עזרא', 1),
        linkFor('חברותא על ברכות', 1),
      ]);

      expect(sorted.map((l) => l.heRef).toList(), [
        'אבן עזרא',
        'חברותא על ברכות',
        'הערות על חברותא על ברכות',
      ]);
    });

    test('ספר-הערות שבסיסו נעדר ממוין לפי שמו-שלו', () {
      CommentaryService.clearEraCache();
      Link linkFor(String title) => Link(
        heRef: title,
        index1: 1,
        path2: title,
        index2: 1,
        connectionType: 'COMMENTARY',
      );

      // "חברותא על ברכות" נעדר => ההערות נופלות חזרה למיון א"ב (ה' לפני ט').
      final sorted = CommentaryService.sortLinksByEraSync([
        linkFor('טור'),
        linkFor('הערות על חברותא על ברכות'),
      ]);

      expect(sorted.map((l) => l.heRef).toList(), [
        'הערות על חברותא על ברכות',
        'טור',
      ]);
    });

    test('קישור לספר הבסיס (SOURCE) עומד בראש, לפני דור ואלפבית (#4170)', () {
      CommentaryService.clearEraCache();
      addTearDown(CommentaryService.clearEraCache);
      CommentaryService.seedEraCache(const {
        'עירובין': CommentaryEra.chazal,
        'רש"י על עירובין': CommentaryEra.rishonim,
        'שולחן ערוך, אורח חיים': CommentaryEra.acharonim,
      });
      Link linkFor(String title, String type) => Link(
        heRef: title,
        index1: 1,
        path2: title,
        index2: 1,
        connectionType: type,
      );

      final sorted = CommentaryService.sortLinksByEraSync([
        linkFor('רש"י על עירובין', 'REFERENCE'),
        linkFor('שולחן ערוך, אורח חיים', 'SOURCE'),
        linkFor('עירובין', 'OTHER'),
      ]);

      expect(sorted.map((l) => l.heRef).toList(), [
        'שולחן ערוך, אורח חיים',
        'עירובין',
        'רש"י על עירובין',
      ]);
    });

    group('כמה קישורי SOURCE', () {
      setUp(CommentaryService.clearEraCache);
      tearDown(CommentaryService.clearEraCache);

      Link linkFor(
        String title,
        int provenance, {
        String type = 'SOURCE',
        int line = 1,
      }) => Link(
        heRef: title,
        index1: 1,
        path2: title,
        index2: line,
        connectionType: type,
        baseProvenance: provenance,
      );

      test('הבסיס המוצהר קודם לציטוט הפוך באותו דור (#4170)', () {
        CommentaryService.seedEraCache(const {
          'בן איש חי': CommentaryEra.acharonim,
          'שולחן ערוך, אורח חיים': CommentaryEra.acharonim,
          'קיצור שלחן ערוך': CommentaryEra.acharonim,
        });
        final input = [
          linkFor('בן איש חי', 0),
          linkFor('שולחן ערוך, אורח חיים', 2),
          linkFor('קיצור שלחן ערוך', 0, type: 'OTHER'),
        ];

        expect(
          CommentaryService.sortLinksByEraSync(input).map((l) => l.path2),
          ['שולחן ערוך, אורח חיים', 'בן איש חי', 'קיצור שלחן ערוך'],
        );
        expect(input.first.path2, 'בן איש חי');
      });

      test('מקור מוצהר קודם למשוער וללטרלי בלי לשנות סוגים אחרים', () {
        CommentaryService.seedEraCache(const {
          'תורה': CommentaryEra.torahShebichtav,
          'בבלי': CommentaryEra.chazal,
          'רמב"ם': CommentaryEra.rishonim,
          'שו"ע': CommentaryEra.acharonim,
        });
        final expected = [
          linkFor('שו"ע', 2),
          linkFor('רמב"ם', 1, type: 'source'),
          linkFor('בבלי', 0),
          linkFor('תורה', 0, type: 'REFERENCE'),
          linkFor('שו"ע', 2, type: 'COMMENTARY'),
        ];

        for (var shift = 0; shift < expected.length; shift++) {
          final rotated = [
            ...expected.skip(shift),
            ...expected.take(shift),
          ];
          for (final input in [rotated, rotated.reversed.toList()]) {
            expect(CommentaryService.sortLinksByEraSync(input), expected);
          }
        }
      });

      test('בשוויון מהימנות נשמרים דור, שם ומיקום', () {
        CommentaryService.seedEraCache(const {
          'אבן עזרא': CommentaryEra.rishonim,
          'תוספות': CommentaryEra.rishonim,
          'שולחן ערוך': CommentaryEra.acharonim,
        });
        for (final provenance in [0, 1, 2]) {
          final expected = [
            linkFor('אבן עזרא', provenance, line: 2),
            linkFor('אבן עזרא', provenance, line: 7),
            linkFor('תוספות', provenance),
            linkFor('שולחן ערוך', provenance),
          ];
          expect(
            CommentaryService.sortLinksByEraSync(expected.reversed.toList()),
            expected,
          );
        }
      });
    });

    test(
      'sortGroupsByEraSync: קבוצת "הערות על XX" ממוינת מיד אחרי קבוצת XX',
      () async {
        // אין DB => כל הספרים בדור "שאר מפרשים", כך שהמיון נקבע לפי העיגון
        // בלבד. באלפבית "הערות" (ה) קודם ל"חברותא" (ח) — כאן זה מתהפך.
        LinkGroup groupFor(String title) => LinkGroup(
          bookTitle: title,
          links: [
            Link(
              heRef: title,
              index1: 1,
              path2: title,
              index2: 1,
              connectionType: 'COMMENTARY',
            ),
          ],
        );

        final sorted = CommentaryService.sortGroupsByEraSync([
          groupFor('הערות על חברותא על ברכות'),
          groupFor('אבן עזרא'),
          groupFor('חברותא על ברכות'),
        ]);

        expect(sorted.map((g) => g.bookTitle).toList(), [
          'אבן עזרא',
          'חברותא על ברכות',
          'הערות על חברותא על ברכות',
        ]);
      },
    );

    test(
      'sortGroupsByEraSync: קבוצת-הערות שבסיסה נעדר ממוינת לפי שמה-שלה',
      () async {
        LinkGroup groupFor(String title) => LinkGroup(
          bookTitle: title,
          links: [
            Link(
              heRef: title,
              index1: 1,
              path2: title,
              index2: 1,
              connectionType: 'COMMENTARY',
            ),
          ],
        );

        // "חברותא על ברכות" נעדר => ההערות נופלות חזרה למיון א"ב (ה' לפני ט').
        final sorted = CommentaryService.sortGroupsByEraSync([
          groupFor('טור'),
          groupFor('הערות על חברותא על ברכות'),
        ]);

        expect(sorted.map((g) => g.bookTitle).toList(), [
          'הערות על חברותא על ברכות',
          'טור',
        ]);
      },
    );

    test('Async grouping returns the same grouping result', () async {
      final links = [
        Link(
          heRef: 'פירוש א',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 1,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש ב',
          index1: 1,
          path2: '/books/commentary1.txt',
          index2: 2,
          connectionType: 'commentary',
        ),
        Link(
          heRef: 'פירוש ג',
          index1: 1,
          path2: '/books/commentary2.txt',
          index2: 1,
          connectionType: 'commentary',
        ),
      ];

      final groups = await CommentaryService.groupConsecutiveLinksAsync(links);

      expect(groups.length, 2);
      expect(groups[0].bookTitle, 'commentary1');
      expect(groups[0].links.length, 2);
      expect(groups[1].bookTitle, 'commentary2');
      expect(groups[1].links.length, 1);
    });
  });
}

// פונקציה עוזרת לבדיקות - חושפת את הפונקציה הפרטית
List<CommentaryGroup> groupConsecutiveLinksForTesting(List<Link> links) {
  // מכיוון שהפונקציה היא פרטית, נשתמש בה דרך wrapper
  // או נעתיק את הלוגיקה לצורך הבדיקה
  if (links.isEmpty) return [];

  final groups = <CommentaryGroup>[];
  String? currentTitle;
  List<Link> currentGroup = [];

  for (final link in links) {
    // מחלץ את שם הספר מה-path
    final title = link.path2.split('/').last.replaceAll('.txt', '');

    if (currentTitle == null || currentTitle != title) {
      if (currentGroup.isNotEmpty) {
        groups.add(
          CommentaryGroup(
            bookTitle: currentTitle!,
            links: List.from(currentGroup),
          ),
        );
      }
      currentTitle = title;
      currentGroup = [link];
    } else {
      currentGroup.add(link);
    }
  }

  if (currentGroup.isNotEmpty) {
    groups.add(
      CommentaryGroup(
        bookTitle: currentTitle!,
        links: List.from(currentGroup),
      ),
    );
  }

  return groups;
}
