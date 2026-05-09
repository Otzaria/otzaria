import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/printing/printing_helpers.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

void main() {
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
    test('מחזירה true רק כשיש מפרשים רלוונטיים והחלונית סגורה', () {
      expect(
        shouldShowOpenPdfCommentaryPaneEntry(
          hasRelevantCommentators: true,
          isPaneOpen: false,
        ),
        isTrue,
      );
    });

    test('מחזירה false כשאין מפרשים רלוונטיים', () {
      expect(
        shouldShowOpenPdfCommentaryPaneEntry(
          hasRelevantCommentators: false,
          isPaneOpen: false,
        ),
        isFalse,
      );
    });

    test('מחזירה false כשהחלונית כבר פתוחה', () {
      expect(
        shouldShowOpenPdfCommentaryPaneEntry(
          hasRelevantCommentators: true,
          isPaneOpen: true,
        ),
        isFalse,
      );
    });
  });

  group('shouldShowOpenPdfLinksPaneEntry', () {
    test('מחזירה true רק כשיש קישורים רלוונטיים והחלונית סגורה', () {
      expect(
        shouldShowOpenPdfLinksPaneEntry(
          hasRelevantLinks: true,
          isPaneOpen: false,
        ),
        isTrue,
      );
    });

    test('מחזירה false כשאין קישורים רלוונטיים', () {
      expect(
        shouldShowOpenPdfLinksPaneEntry(
          hasRelevantLinks: false,
          isPaneOpen: false,
        ),
        isFalse,
      );
    });

    test('מחזירה false כשהחלונית כבר פתוחה', () {
      expect(
        shouldShowOpenPdfLinksPaneEntry(
          hasRelevantLinks: true,
          isPaneOpen: true,
        ),
        isFalse,
      );
    });
  });
}
