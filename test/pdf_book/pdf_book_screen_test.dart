import 'package:flutter/foundation.dart';
import 'package:otzaria/text_book/utils/reader_menu_entries.dart';
import 'package:otzaria/book_common/utils/commentators_menu.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/printing/printing_helpers.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

import '../helpers/memory_settings_cache.dart';

// The PDF page menu decides its pane entries by the shared rules, called
// with these arguments; the tests below pin that combination.
bool shouldShowOpenPdfCommentaryPaneEntry({
  required bool hasSelectedCommentators,
  required bool isCommentatorsTabActive,
}) => shouldShowOpenCommentatorsPaneEntry(
  hasSelectedCommentators: hasSelectedCommentators,
  showCommentaryAsExpansionTiles: false,
  isCommentatorsTabActive: isCommentatorsTabActive,
);

bool shouldShowSelectPdfCommentatorsEntry({
  required bool isCommentatorsTabActive,
}) => shouldShowSelectCommentatorsEntry(
  hasOpenCommentatorsPaneWithFilterCallback: true,
  isCommentatorsTabActive: isCommentatorsTabActive,
);

bool shouldShowOpenPdfLinksPaneEntry({
  required bool hasRelevantLinks,
  required bool isLinksTabActive,
}) => shouldShowOpenLinksPaneEntry(
  hasLinks: hasRelevantLinks,
  isLinksTabActive: isLinksTabActive,
);

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

    test('במצב ספר ללא עמוד שער — מנרמלת לתחילת זוג אי-זוגי', () {
      expect(
        resolveInitialPdfPrintPage(
          currentPage: 4,
          layoutMode: PdfLayoutMode.bookViewNoCover,
        ),
        3,
      );
      expect(
        resolveInitialPdfPrintPage(
          currentPage: 5,
          layoutMode: PdfLayoutMode.bookViewNoCover,
        ),
        5,
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

  group('pdfQueuedPageTurnDuration', () {
    const single = Duration(milliseconds: 500);

    test('בלי תור — משך דפדוף מלא', () {
      expect(pdfQueuedPageTurnDuration(single, 0), single);
    });

    test('דפדופים ממתינים חולקים את משך הדפדוף הבודד', () {
      expect(
        pdfQueuedPageTurnDuration(single, 4),
        const Duration(milliseconds: 100),
      );
      // ארבעה ממתינים: 125+167+250+500 ≈ 1 שנ' במקום 2 שנ' בקצב מלא.
      final backlog = [3, 2, 1, 0].fold<Duration>(
        Duration.zero,
        (sum, pending) => sum + pdfQueuedPageTurnDuration(single, pending),
      );
      expect(backlog.inMilliseconds, lessThan(4 * single.inMilliseconds));
      expect(
        pdfQueuedPageTurnDuration(single, 3),
        lessThan(pdfQueuedPageTurnDuration(single, 1)),
      );
    });

    test('ערך שלילי מטופל כתור ריק', () {
      expect(pdfQueuedPageTurnDuration(single, -2), single);
    });
  });

  group('shouldDropPendingPageTurns', () {
    test('מחזירה true כשהתור מכיל דפדוף בכיוון ההפוך', () {
      expect(
        shouldDropPendingPageTurns(
          pendingDirections: ['next', 'next'],
          incomingDirection: 'previous',
        ),
        isTrue,
      );
    });

    test('מחזירה false כשכל הממתינים באותו כיוון', () {
      expect(
        shouldDropPendingPageTurns(
          pendingDirections: ['next', 'next'],
          incomingDirection: 'next',
        ),
        isFalse,
      );
    });

    test('מחזירה false על תור ריק', () {
      expect(
        shouldDropPendingPageTurns(
          pendingDirections: <String>[],
          incomingDirection: 'previous',
        ),
        isFalse,
      );
    });

    test('תור מעורב — מספיק ממתין הפוך אחד כדי לרוקן', () {
      expect(
        shouldDropPendingPageTurns(
          pendingDirections: ['previous', 'next'],
          incomingDirection: 'next',
        ),
        isTrue,
      );
    });
  });

  group('shouldShowSelectPdfCommentatorsEntry', () {
    test('מחזירה true כשטאב המפרשים אינו פעיל', () {
      expect(
        shouldShowSelectPdfCommentatorsEntry(isCommentatorsTabActive: false),
        isTrue,
      );
    });

    test('מחזירה false כשטאב המפרשים פעיל', () {
      expect(
        shouldShowSelectPdfCommentatorsEntry(isCommentatorsTabActive: true),
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
          shouldShowSelectPdfCommentatorsEntry(isCommentatorsTabActive: false),
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
        resolveReadyPdfPageNumber(isReady: true, readPageNumber: () => 7),
        7,
      );
    });

    test('מחזירה null כשהעמוד הנוכחי עדיין לא ידוע למרות שמוכן', () {
      expect(
        resolveReadyPdfPageNumber(isReady: true, readPageNumber: () => null),
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

  group('העתקת טקסט מסומן בתפריט ההקשר של PDF (issue #1420)', () {
    // התפריט הזה מחליף את התפריט המובנה של pdfrx, שהציע "העתק" על בחירה.
    // בלעדיו אין בדסקטופ שום מסלול עכבר להעתקה מתוך PDF.
    List<AppContextMenuEntry> buildMenu({
      required bool hasTextSelection,
      String? selectedText,
      bool? canCopySelection,
      VoidCallback? onCopySelection,
      VoidCallback? onSearchAllBooks,
    }) {
      return buildPdfContextMenuEntries(
        commentatorChildren: const [],
        hasRelevantCommentators: false,
        canSelectCommentators: false,
        linksEntry: buildPdfLinksContextMenuEntry(
          relevantLinks: const [],
          showOpenLinksPaneEntry: false,
          onOpenLinksPane: () {},
          onOpenLink: (_) {},
        ),
        hasTextSelection: hasTextSelection,
        selection: selectedText == null
            ? null
            : ReaderMenuSelection(selectedText),
        canCopySelection: canCopySelection ?? hasTextSelection,
        onSearchInBook: () {},
        onSearchAllBooks: onSearchAllBooks ?? () {},
        onCopySelection: onCopySelection ?? () {},
        onAddBookmark: () {},
        onAddNote: () {},
      );
    }

    AppContextMenuIconAction copyActionOf(List<AppContextMenuEntry> menu) {
      final iconRow = menu.firstWhere(
        (entry) => entry.iconRowActions != null,
        orElse: () => throw StateError('אין שורת אייקונים בתפריט ההקשר של PDF'),
      );
      return iconRow.iconRowActions!.firstWhere(
        (action) => action.label == 'העתקה',
        orElse: () => throw StateError('אין פעולת "העתקה" בשורת האייקונים'),
      );
    }

    test('יש פעולת "העתקה", והיא פעילה כשיש טקסט מסומן', () {
      expect(copyActionOf(buildMenu(hasTextSelection: true)).enabled, isTrue);
    });

    test('פעולת "העתקה" מנוטרלת כשאין טקסט מסומן', () {
      expect(copyActionOf(buildMenu(hasTextSelection: false)).enabled, isFalse);
    });

    test('פעולת "העתקה" מנוטרלת כשהמסמך אוסר העתקה', () {
      expect(
        copyActionOf(
          buildMenu(hasTextSelection: true, canCopySelection: false),
        ).enabled,
        isFalse,
      );
    });

    test('"חיפוש" בשורת האייקונים מחפש בכל הספרים, כמו בתצוגת הטקסט', () {
      final menu = buildMenu(hasTextSelection: true);
      final search = menu
          .firstWhere((entry) => entry.iconRowActions != null)
          .iconRowActions!
          .first;

      expect(search.label, 'חיפוש');
      expect(search.tooltip, 'חיפוש בכל הספרים');
      expect(
        buildMenu(hasTextSelection: true, selectedText: 'בראשית\nברא')
            .firstWhere((entry) => entry.iconRowActions != null)
            .iconRowActions!
            .first
            .tooltip,
        'חיפוש "בראשית ברא" בכל הספרים',
        reason: 'כשהטקסט המסומן כבר טעון, הרמז מצטט אותו כמו בתצוגת הטקסט',
      );
      expect(
        menu.where((entry) => entry.label == 'חיפוש בספר'),
        hasLength(1),
        reason: 'החיפוש בתוך הספר נבדל בשמו מהחיפוש בכל הספרים',
      );
    });

    test('חיפוש זמין בזמן טעינת הבחירה ומנוטרל בלי טקסט לחיפוש', () {
      AppContextMenuIconAction search({
        required bool hasSelection,
        String? selectedText,
      }) => buildMenu(
        hasTextSelection: hasSelection,
        selectedText: selectedText,
      ).first.iconRowActions!.first;

      expect(search(hasSelection: false).enabled, isFalse);
      expect(search(hasSelection: true).enabled, isTrue);
      expect(
        search(hasSelection: true, selectedText: '  \n ').enabled,
        isFalse,
      );
      expect(search(hasSelection: true, selectedText: 'שלום').enabled, isTrue);
    });

    test('לחיצה על חיפוש בכל הספרים מפעילה את הפעולה המתאימה', () {
      var searched = false;
      final menu = buildMenu(
        hasTextSelection: true,
        selectedText: 'בראשית',
        onSearchAllBooks: () => searched = true,
      );
      menu.first.iconRowActions!.first.onTap!();
      expect(searched, isTrue);
    });

    test('לחיצה על "העתקה" מפעילה את העתקת הבחירה', () {
      var copied = false;
      final menu = buildMenu(
        hasTextSelection: true,
        onCopySelection: () => copied = true,
      );

      copyActionOf(menu).onTap!();

      expect(copied, isTrue);
    });

    test('"הוסף הערה אישית" נשאר זמין — עבר לשורת האייקונים', () {
      final menu = buildMenu(hasTextSelection: false);
      final iconRow = menu.firstWhere((entry) => entry.iconRowActions != null);

      expect(
        iconRow.iconRowActions!.map((action) => action.label),
        containsAll(<String>['חיפוש', 'העתקה', 'הערה']),
      );
      expect(
        menu.any((entry) => entry.label == 'הוסף הערה אישית'),
        isFalse,
        reason: 'הפריט עבר לשורת האייקונים ואסור שיופיע פעמיים',
      );
    });
  });
}
