import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';

void main() {
  group('PdfBookSearchView.missingFromIndexNotice', () {
    const path = r'C:\books\pdf\ספר.pdf';

    test('מחזיר את ההודעה כשהאינדקס נטען והספר אינו בו', () {
      expect(
        PdfBookSearchView.missingFromIndexNotice(
          indexedFilePath: path,
          indexInitialized: true,
          indexedFilePaths: {r'C:\books\pdf\אחר.pdf'},
        ),
        PdfMessages.bookNotInSearchIndex,
      );
    });

    test('לא מחזיר הודעה כשהספר נמצא באינדקס', () {
      expect(
        PdfBookSearchView.missingFromIndexNotice(
          indexedFilePath: path,
          indexInitialized: true,
          indexedFilePaths: {path},
        ),
        isNull,
      );
    });

    test('לא מסיק "חסר" לפני שקריאת מצב האינדקס הסתיימה', () {
      expect(
        PdfBookSearchView.missingFromIndexNotice(
          indexedFilePath: path,
          indexInitialized: false,
          indexedFilePaths: const {},
        ),
        isNull,
      );
    });

    test('לא מחזיר הודעה כשאין מפתח אינדקס לספר', () {
      for (final missingPath in [null, '']) {
        expect(
          PdfBookSearchView.missingFromIndexNotice(
            indexedFilePath: missingPath,
            indexInitialized: true,
            indexedFilePaths: const {},
          ),
          isNull,
        );
      }
    });

    test('מסכת מצורפת נמצאת באינדקס לפי המזהה היציב ולא לפי הנתיב', () {
      const stableKey = 'ext:talmud-pdf:ברכות';
      expect(
        PdfBookSearchView.missingFromIndexNotice(
          indexedFilePath: IndexingRepository.indexedPdfFilePath(
            externalLibraryId:
                DatabaseConstants.talmudBavliPdfExternalLibraryId('ברכות'),
            filePath: r'C:\otzaria\תלמוד בבלי\ברכות.pdf',
          ),
          indexInitialized: true,
          indexedFilePaths: const {stableKey},
        ),
        isNull,
        reason: 'השוואה לנתיב המוחלט הייתה מציגה "הספר אינו באינדקס"',
      );
    });
  });
}
