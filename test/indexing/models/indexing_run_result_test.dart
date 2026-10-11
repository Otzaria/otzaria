import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';

void main() {
  group('IndexingFailureKind', () {
    test('כשלי סיסמה ו-PDF לא נתמך הם קבועים', () {
      expect(IndexingFailureKind.passwordProtected.isRetryable, isFalse);
      expect(IndexingFailureKind.pdfUnsupported.isRetryable, isFalse);
    });

    test('כשל הרשאה אינו נכנס ללולאת ניסיון אוטומטית', () {
      expect(IndexingFailureKind.permissionDenied.isRetryable, isFalse);
    });

    test('timeout, כתיבת מנוע וכשל לא ידוע ניתנים לניסיון חוזר', () {
      expect(IndexingFailureKind.timeout.isRetryable, isTrue);
      expect(IndexingFailureKind.engineWrite.isRetryable, isTrue);
      expect(IndexingFailureKind.unknown.isRetryable, isTrue);
    });

    test('PDF חלקי הוא אזהרה ואינו כשל שחוסם השלמה', () {
      expect(IndexingFailureKind.partialPdf.preventedIndexing, isFalse);
      expect(IndexingFailureKind.partialPdf.isRetryable, isFalse);
    });
  });

  group('IndexingRunResult', () {
    const permanent = IndexingFailure(
      bookTitle: 'מוגן',
      bookPath: r'C:\books\protected.pdf',
      kind: IndexingFailureKind.passwordProtected,
      error: 'password required',
    );
    const retryable = IndexingFailure(
      bookTitle: 'כשל מנוע',
      bookPath: r'C:\books\engine.pdf',
      kind: IndexingFailureKind.engineWrite,
      error: 'write failed',
    );
    const partial = IndexingFailure(
      bookTitle: 'חלקי',
      bookPath: r'C:\books\partial.pdf',
      kind: IndexingFailureKind.partialPdf,
      error: '2 pages dropped',
    );

    test('תוצאה נקייה אינה מכילה כשלים', () {
      const result = IndexingRunResult.completed(
        processedBooks: 4,
        totalBooks: 4,
        indexedBooks: 4,
      );

      expect(result.completed, isTrue);
      expect(result.isClean, isTrue);
      expect(result.retryableFailures, isEmpty);
      expect(result.blockingFailureCount, 0);
    });

    test('מפרידה בין כשל חוסם, אזהרה וכשל זמני', () {
      const result = IndexingRunResult.completed(
        processedBooks: 3,
        totalBooks: 3,
        indexedBooks: 1,
        failures: [permanent, retryable, partial],
      );

      expect(result.isClean, isFalse);
      expect(result.blockingFailureCount, 2);
      expect(result.warningCount, 1);
      expect(result.retryableFailures, [retryable]);
    });

    test('תוצאה מבוטלת אינה completed גם ללא כשלים', () {
      const result = IndexingRunResult.cancelled(
        processedBooks: 2,
        totalBooks: 5,
        indexedBooks: 2,
      );

      expect(result.completed, isFalse);
      expect(result.cancelled, isTrue);
      expect(result.isClean, isFalse);
    });

    test('שוויון כולל את פרטי הכשלים והמונה', () {
      const first = IndexingRunResult.completed(
        processedBooks: 1,
        totalBooks: 1,
        indexedBooks: 0,
        failures: [permanent],
      );
      const same = IndexingRunResult.completed(
        processedBooks: 1,
        totalBooks: 1,
        indexedBooks: 0,
        failures: [permanent],
      );
      const different = IndexingRunResult.completed(
        processedBooks: 1,
        totalBooks: 1,
        indexedBooks: 1,
        failures: [permanent],
      );

      expect(first, same);
      expect(first, isNot(different));
    });
  });
}
