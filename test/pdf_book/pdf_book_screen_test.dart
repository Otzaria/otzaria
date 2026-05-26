import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/printing/printing_helpers.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

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
    });
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
    }) =>
        Link(
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

      expect(entry.childrenBuilder, isNotNull,
          reason: 'התת-תפריט חייב להיבנות בעצלתיים (childrenBuilder), אחרת '
              'הזמן של פתיחת התפריט הראשי תלוי בכל הקישורים בעמוד');
      expect(entry.children, isNull,
          reason: 'children מיידיים מאלצים בנייה upfront של כל פריטי הקישורים '
              'כולל ה-FutureBuilders של displayReference');
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
    });

    test(
        'childrenBuilder ללא פריט "פתח חלונית" כש-showOpenLinksPaneEntry=false',
        () {
      final entry = buildPdfLinksContextMenuEntry(
        relevantLinks: [makeLink(), makeLink(heRef: 'בראשית א:ב', index2: 2)],
        showOpenLinksPaneEntry: false,
        onOpenLinksPane: () {},
        onOpenLink: (_) {},
      );

      final children = entry.childrenBuilder!();

      expect(children, hasLength(2));
      expect(children.any((e) => e.label == 'פתח קישורים בחלונית צד'), isFalse);
      expect(children.every((e) => !e.isDivider), isTrue);
    });

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
}
