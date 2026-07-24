import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/printing/printing_helpers.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('resolveInitialPdfPrintPage', () {
    test('מחזירה את אותו עמוד בתצוגה רגילה', () {
      expect(
        resolveInitialPdfPrintPage(
          currentPage: 5,
          layoutMode: PdfLayoutMode.regularView,
        ),
        5,
      );
    });

    test('מנרמלת עמוד אי זוגי לתחילת spread במצב ספר', () {
      expect(
        resolveInitialPdfPrintPage(
          currentPage: 5,
          layoutMode: PdfLayoutMode.bookView,
        ),
        4,
      );
    });

    test('משאירה את עמוד 1 ללא שינוי במצב ספר', () {
      expect(
        resolveInitialPdfPrintPage(
          currentPage: 1,
          layoutMode: PdfLayoutMode.bookView,
        ),
        1,
      );
    });
  });

  group('shouldShowOpenPdfCommentaryPaneEntry', () {
    test('מחזירה true כשיש מפרשים נבחרים וטאב המפרשים אינו פעיל', () {
      expect(
        shouldShowOpenPdfCommentaryPaneEntry(
          hasSelectedCommentators: true,
          isCommentatorsTabActive: false,
        ),
        isTrue,
      );
    });

    test('מחזירה false כשאין מפרשים נבחרים', () {
      expect(
        shouldShowOpenPdfCommentaryPaneEntry(
          hasSelectedCommentators: false,
          isCommentatorsTabActive: false,
        ),
        isFalse,
      );
    });

    test('מחזירה false כשטאב המפרשים כבר פעיל', () {
      expect(
        shouldShowOpenPdfCommentaryPaneEntry(
          hasSelectedCommentators: true,
          isCommentatorsTabActive: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldShowSelectPdfCommentatorsEntry', () {
    test('מחזירה true כשטאב המפרשים אינו פעיל', () {
      expect(
        shouldShowSelectPdfCommentatorsEntry(
          isCommentatorsTabActive: false,
        ),
        isTrue,
      );
    });

    test('מחזירה false כשטאב המפרשים פעיל', () {
      expect(
        shouldShowSelectPdfCommentatorsEntry(
          isCommentatorsTabActive: true,
        ),
        isFalse,
      );
    });

    test(
      'מציגה גם בלי מפרשים נבחרים — בניגוד ל-shouldShowOpenPdfCommentaryPaneEntry',
      () {
        // הפריט הזה לא תלוי ב-hasSelectedCommentators, כדי לאפשר בחירה ראשונית
        // גם כשהבחירה ריקה (תיקון עקביות מול מסך הטקסט).
        expect(
          shouldShowOpenPdfCommentaryPaneEntry(
            hasSelectedCommentators: false,
            isCommentatorsTabActive: false,
          ),
          isFalse,
        );
        expect(
          shouldShowSelectPdfCommentatorsEntry(
            isCommentatorsTabActive: false,
          ),
          isTrue,
        );
      },
    );
  });

  group('shouldShowOpenPdfLinksPaneEntry', () {
    test('מחזירה true כשיש קישורים רלוונטיים וטאב הקישורים אינו פעיל', () {
      expect(
        shouldShowOpenPdfLinksPaneEntry(
          hasRelevantLinks: true,
          isLinksTabActive: false,
        ),
        isTrue,
      );
    });

    test('מחזירה false כשאין קישורים רלוונטיים', () {
      expect(
        shouldShowOpenPdfLinksPaneEntry(
          hasRelevantLinks: false,
          isLinksTabActive: false,
        ),
        isFalse,
      );
    });

    test('מחזירה false כשטאב הקישורים כבר פעיל', () {
      expect(
        shouldShowOpenPdfLinksPaneEntry(
          hasRelevantLinks: true,
          isLinksTabActive: true,
        ),
        isFalse,
      );
    });
  });

  group('buildPdfLinksContextMenuEntry', () {
    Link makeLink({
      String heRef = 'בראשית א:א',
      String path2 = 'C:/otzaria/Otzaria/library/ספר היעד.txt',
      int index2 = 1,
      String connectionType = 'link',
    }) => Link(
      heRef: heRef,
      index1: 1,
      path2: path2,
      index2: index2,
      connectionType: connectionType,
    );

    test('משתמש ב-childrenBuilder עצל ולא ב-children מיידיים', () {
      // רגרסיה: לפני התיקון התת-תפריט נבנה upfront ועיכב את פתיחת התפריט
      // הראשי בגלל FutureBuilders של link.displayReference של כל קישור.
      // ראה את התיקון המקביל בספרי טקסט (commit e20533698).
      final entry = buildPdfLinksContextMenuEntry(
        relevantLinks: [makeLink()],
        showOpenLinksPaneEntry: false,
        onOpenLinksPane: () {},
        onOpenLink: (_) {},
      );

      expect(
        entry.childrenBuilder,
        isNotNull,
        reason:
            'התת-תפריט חייב להיבנות בעצלתיים (childrenBuilder), אחרת '
            'הזמן של פתיחת התפריט הראשי תלוי בכל הקישורים בעמוד',
      );
      expect(
        entry.children,
        isNull,
        reason:
            'children מיידיים מאלצים בנייה upfront של כל פריטי הקישורים '
            'כולל ה-FutureBuilders של displayReference',
      );
    });

    test('הפריט "קישורים" מושבת כשאין קישורים רלוונטיים', () {
      final entry = buildPdfLinksContextMenuEntry(
        relevantLinks: const [],
        showOpenLinksPaneEntry: false,
        onOpenLinksPane: () {},
        onOpenLink: (_) {},
      );

      expect(entry.label, 'קישורים');
      expect(entry.enabled, isFalse);
    });

    test('הפריט "קישורים" פעיל כשיש קישורים רלוונטיים', () {
      final entry = buildPdfLinksContextMenuEntry(
        relevantLinks: [makeLink()],
        showOpenLinksPaneEntry: false,
        onOpenLinksPane: () {},
        onOpenLink: (_) {},
      );

      expect(entry.enabled, isTrue);
    });

    test(
      'childrenBuilder מחזיר פריט "פתח חלונית" + divider כש-showOpenLinksPaneEntry=true',
      () {
        final entry = buildPdfLinksContextMenuEntry(
          relevantLinks: [makeLink()],
          showOpenLinksPaneEntry: true,
          onOpenLinksPane: () {},
          onOpenLink: (_) {},
        );

        final children = entry.childrenBuilder!();

        expect(children, hasLength(3));
        expect(children[0].label, 'פתח קישורים בחלונית צד');
        expect(children[1].isDivider, isTrue);
        expect(children[2].isDivider, isFalse);
      },
    );

    test(
      'childrenBuilder ללא פריט "פתח חלונית" כש-showOpenLinksPaneEntry=false',
      () {
        final entry = buildPdfLinksContextMenuEntry(
          relevantLinks: [
            makeLink(),
            makeLink(heRef: 'בראשית א:ב', index2: 2),
          ],
          showOpenLinksPaneEntry: false,
          onOpenLinksPane: () {},
          onOpenLink: (_) {},
        );

        final children = entry.childrenBuilder!();

        expect(children, hasLength(2));
        expect(
          children.any((e) => e.label == 'פתח קישורים בחלונית צד'),
          isFalse,
        );
        expect(children.every((e) => !e.isDivider), isTrue);
      },
    );

    test('onOpenLinksPane מופעל בלחיצה על פריט "פתח חלונית"', () {
      var paneOpened = 0;
      final entry = buildPdfLinksContextMenuEntry(
        relevantLinks: [makeLink()],
        showOpenLinksPaneEntry: true,
        onOpenLinksPane: () => paneOpened++,
        onOpenLink: (_) {},
      );

      entry.childrenBuilder!()[0].onTap!();

      expect(paneOpened, 1);
    });

    test('onOpenLink מופעל עם הקישור הנכון בלחיצה על פריט קישור', () {
      final link1 = makeLink(heRef: 'בראשית א:א', index2: 1);
      final link2 = makeLink(heRef: 'בראשית א:ב', index2: 2);
      final clicked = <Link>[];

      final entry = buildPdfLinksContextMenuEntry(
        relevantLinks: [link1, link2],
        showOpenLinksPaneEntry: false,
        onOpenLinksPane: () {},
        onOpenLink: clicked.add,
      );

      final children = entry.childrenBuilder!();
      children[1].onTap!();

      expect(clicked, [link2]);
    });
  });

  group('תרחישים חוצי-טאב בחלונית הצד', () {
    test('"פתח מפרשים" מוצגת כשהחלונית פתוחה על טאב הקישורים', () {
      expect(
        shouldShowOpenPdfCommentaryPaneEntry(
          hasSelectedCommentators: true,
          isCommentatorsTabActive: false,
        ),
        isTrue,
      );
    });

    test('"פתח קישורים" מוצגת כשהחלונית פתוחה על טאב המפרשים', () {
      expect(
        shouldShowOpenPdfLinksPaneEntry(
          hasRelevantLinks: true,
          isLinksTabActive: false,
        ),
        isTrue,
      );
    });

    test('"פתח מפרשים" אינה תלויה ברלוונטיות לעמוד, רק בנבחרים בספר', () {
      expect(
        shouldShowOpenPdfCommentaryPaneEntry(
          hasSelectedCommentators: true,
          isCommentatorsTabActive: false,
        ),
        isTrue,
      );
      expect(
        shouldShowOpenPdfCommentaryPaneEntry(
          hasSelectedCommentators: false,
          isCommentatorsTabActive: false,
        ),
        isFalse,
      );
    });
  });

  group('buildGroupedCommentatorEntries', () {
    final groups = [
      const CommentatorGroup(title: 'ראשונים', commentators: ['רש"י', 'רמב"ן']),
      const CommentatorGroup(
        title: 'אחרונים',
        commentators: ['מצודת דוד', 'מלבי"ם'],
      ),
      const CommentatorGroup(title: 'שאר מפרשים', commentators: ['מפרש פלוני']),
    ];

    test('מוסיף פריט "הצג את כל <תקופה>" לכל קבוצה לא-ריקה', () {
      final entries = buildGroupedCommentatorEntries(
        relevantCommentators: const ['רש"י', 'רמב"ן', 'מצודת דוד', 'מלבי"ם'],
        commentatorGroups: groups,
        activeCommentators: const <String>{},
        onToggleCommentator: (_) {},
        onToggleAll: (_) {},
      );

      final labels = entries.map((e) => e.label).toList();
      expect(labels, contains('הצג את כל ראשונים'));
      expect(labels, contains('הצג את כל אחרונים'));
      // הכותרת מופיעה לפני המפרשים הבודדים של אותה קבוצה
      expect(
        labels.indexOf('הצג את כל ראשונים'),
        lessThan(labels.indexOf('רש"י')),
      );
    });

    test('פריט הקבוצה מסומן כשכל מפרשי הקבוצה הרלוונטיים פעילים', () {
      final entries = buildGroupedCommentatorEntries(
        relevantCommentators: const ['רש"י', 'רמב"ן', 'מצודת דוד'],
        commentatorGroups: groups,
        activeCommentators: const {'רש"י', 'רמב"ן'},
        onToggleCommentator: (_) {},
        onToggleAll: (_) {},
      );

      final rishonim = entries.firstWhere(
        (e) => e.label == 'הצג את כל ראשונים',
      );
      final acharonim = entries.firstWhere(
        (e) => e.label == 'הצג את כל אחרונים',
      );
      expect(rishonim.isSelected, isTrue);
      expect(acharonim.isSelected, isFalse);
    });

    test('לחיצה על "הצג את כל <תקופה>" מעבירה את מפרשי הקבוצה הרלוונטיים', () {
      List<String>? toggled;
      final entries = buildGroupedCommentatorEntries(
        // רק רש"י רלוונטי לדף מתוך הראשונים
        relevantCommentators: const ['רש"י', 'מצודת דוד'],
        commentatorGroups: groups,
        activeCommentators: const <String>{},
        onToggleCommentator: (_) {},
        onToggleAll: (list) => toggled = list,
      );

      entries.firstWhere((e) => e.label == 'הצג את כל ראשונים').onTap!();

      // רק המפרשים הרלוונטיים לדף, לא כל הקבוצה
      expect(toggled, ['רש"י']);
    });

    test('קבוצה בלי מפרשים רלוונטיים אינה יוצרת פריט כותרת', () {
      final entries = buildGroupedCommentatorEntries(
        relevantCommentators: const ['רש"י'], // אין אחרונים רלוונטיים
        commentatorGroups: groups,
        activeCommentators: const <String>{},
        onToggleCommentator: (_) {},
        onToggleAll: (_) {},
      );

      final labels = entries.map((e) => e.label).toList();
      expect(labels, contains('הצג את כל ראשונים'));
      expect(labels, isNot(contains('הצג את כל אחרונים')));
    });

    test('מפרשים שאינם משויכים לאף קבוצה מוצגים ללא כותרת', () {
      final entries = buildGroupedCommentatorEntries(
        relevantCommentators: const ['רש"י', 'מפרש לא ידוע'],
        commentatorGroups: groups,
        activeCommentators: const <String>{},
        onToggleCommentator: (_) {},
        onToggleAll: (_) {},
      );

      final labels = entries.map((e) => e.label).toList();
      expect(labels, contains('מפרש לא ידוע'));
      // אין כותרת "הצג את כל" עבור מפרש שלא קוטלג
      expect(
        labels.any(
          (l) => l != null && l.contains('מפרש לא ידוע') && l.startsWith('הצג'),
        ),
        isFalse,
      );
    });

    test('בלי קבוצות — מציג את המפרשים בלבד ללא כותרות', () {
      final entries = buildGroupedCommentatorEntries(
        relevantCommentators: const ['רש"י', 'רמב"ן'],
        commentatorGroups: const [],
        activeCommentators: const <String>{},
        onToggleCommentator: (_) {},
        onToggleAll: (_) {},
      );

      final labels = entries.map((e) => e.label).toList();
      expect(labels, ['רש"י', 'רמב"ן']);
      expect(
        labels.any((l) => l != null && l.startsWith('הצג את כל')),
        isFalse,
      );
    });
  });

  group('shouldRecomputeLineRangeOnLayoutModeChange', () {
    // רגרסיה: טווח השורות (currentTextLineNumber/End) שמזין את רשימת המפרשים
    // תלוי במצב התצוגה — בתצוגת ספר הוא מכסה ספירייד של שני עמודים, וברגילה
    // עמוד יחיד. לפני התיקון מעבר בין המצבים לא חישב מחדש את הטווח, ולכן
    // רשימת המפרשים נשארה תקועה על הטווח של המצב הקודם.
    test('מעבר מתצוגה רגילה לתצוגת ספר מחייב חישוב מחדש', () {
      expect(
        shouldRecomputeLineRangeOnLayoutModeChange(
          PdfLayoutMode.regularView,
          PdfLayoutMode.bookView,
        ),
        isTrue,
      );
    });

    test('מעבר מתצוגת ספר לתצוגה רגילה מחייב חישוב מחדש', () {
      expect(
        shouldRecomputeLineRangeOnLayoutModeChange(
          PdfLayoutMode.bookView,
          PdfLayoutMode.regularView,
        ),
        isTrue,
      );
    });

    test('אותו מצב — לא מחשב מחדש', () {
      expect(
        shouldRecomputeLineRangeOnLayoutModeChange(
          PdfLayoutMode.bookView,
          PdfLayoutMode.bookView,
        ),
        isFalse,
      );
      expect(
        shouldRecomputeLineRangeOnLayoutModeChange(
          PdfLayoutMode.regularView,
          PdfLayoutMode.regularView,
        ),
        isFalse,
      );
    });

    test('baseline ראשון (previous=null) לא מחשב מחדש', () {
      // הצפייה הראשונה ב-state רק רושמת את המצב הנוכחי, בלי לטרגר חישוב
      // מיותר שמתנגש בנתיב הטעינה הרגיל.
      expect(
        shouldRecomputeLineRangeOnLayoutModeChange(
          null,
          PdfLayoutMode.bookView,
        ),
        isFalse,
      );
      expect(
        shouldRecomputeLineRangeOnLayoutModeChange(
          null,
          PdfLayoutMode.regularView,
        ),
        isFalse,
      );
    });
  });

  group('resolveReadyPdfPageNumber', () {
    test('מחזירה את מספר העמוד כש-ה-controller מוכן', () {
      expect(
        resolveReadyPdfPageNumber(
          isReady: true,
          readPageNumber: () => 7,
        ),
        7,
      );
    });

    test('מחזירה null כשהעמוד הנוכחי עדיין לא ידוע למרות שמוכן', () {
      expect(
        resolveReadyPdfPageNumber(
          isReady: true,
          readPageNumber: () => null,
        ),
        isNull,
      );
    });

    test('לא ניגשת ל-pageNumber ומחזירה null כש-ה-controller אינו מוכן', () {
      // רגרסיה: הגישה ל-controller.pageNumber משתמשת ב-null check operator
      // פנימי של pdfrx (_state!), שקורס אם ה-PdfViewer התנתק במהלך await
      // ב-onViewerReady. ההגנה חייבת למנוע את הקריאה כשאינו מוכן.
      var pageNumberAccessed = false;
      final result = resolveReadyPdfPageNumber(
        isReady: false,
        readPageNumber: () {
          pageNumberAccessed = true;
          throw StateError('Null check operator used on a null value');
        },
      );
      expect(result, isNull);
      expect(pageNumberAccessed, isFalse);
    });
  });
}
