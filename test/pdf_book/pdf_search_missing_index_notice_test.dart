import 'package:otzaria/data/book_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/search/utils/in_book_index_notice.dart';

void main() {
  group('inBookMissingFromIndexNotice', () {
    const path = r'C:\books\pdf\ספר.pdf';

    test('מחזיר את ההודעה כשהאינדקס נטען והספר אינו בו', () {
      expect(
        inBookMissingFromIndexNotice(
          indexedFilePath: path,
          indexInitialized: true,
          indexedFilePaths: {r'C:\books\pdf\אחר.pdf'},
        ),
        LibraryMessages.bookNotInSearchIndex,
      );
    });

    test('ספר אישי שהוחרג במצב "בלי ספרים אישיים" — הודעה שמפנה להגדרה', () {
      expect(
        inBookMissingFromIndexNotice(
          indexedFilePath: path,
          indexInitialized: true,
          indexedFilePaths: const {},
          excludedByIndexMode: true,
        ),
        LibraryMessages.personalBookNotInSearchIndex,
      );
    });

    test('לא מחזיר הודעה כשהספר נמצא באינדקס', () {
      expect(
        inBookMissingFromIndexNotice(
          indexedFilePath: path,
          indexInitialized: true,
          indexedFilePaths: {path},
        ),
        isNull,
      );
    });

    test('לא מסיק "חסר" לפני שקריאת מצב האינדקס הסתיימה', () {
      expect(
        inBookMissingFromIndexNotice(
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
          inBookMissingFromIndexNotice(
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
        inBookMissingFromIndexNotice(
          indexedFilePath: BookIdentity.indexedPdfFilePath(
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
