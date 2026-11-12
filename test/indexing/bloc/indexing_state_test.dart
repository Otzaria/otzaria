import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';

void main() {
  const failure = IndexingFailure(
    bookTitle: 'ספר',
    bookPath: 'ext:42',
    kind: IndexingFailureKind.passwordProtected,
    error: 'password',
  );
  const partial = IndexingFailure(
    bookTitle: 'ברכות',
    bookPath: 'ברכות.pdf',
    kind: IndexingFailureKind.partialPdf,
    error: '12 עמודים נשמטו',
  );

  group('IndexingComplete', () {
    test('ברירת המחדל נקייה', () {
      const state = IndexingComplete();

      expect(state.isClean, isTrue);
      expect(state.failures, isEmpty);
    });

    test('חושף השלמה עם כשלים', () {
      const state = IndexingComplete(failures: [failure]);

      expect(state.isClean, isFalse);
      expect(state.failureCount, 1);
    });

    test('אזהרת PDF חלקי אינה נספרת ככשל חוסם', () {
      const state = IndexingComplete(failures: [failure, partial, partial]);

      expect(state.isClean, isFalse);
      expect(state.blockingFailureCount, 1);
      expect(state.warningCount, 2);
    });

    test('הודעת הסיום נוקבת בשם הספר שלא אונדקס (issue #2363)', () {
      expect(
        LibraryMessages.indexingCompleted(const [partial, failure]),
        allOf(contains('"ספר" לא אונדקס'), isNot(contains('ext:42'))),
      );
      expect(
        LibraryMessages.indexingCompleted(const [partial]),
        contains('נשמטו עמודים'),
      );
    });

    test('השוויון משתנה כאשר רשימת הכשלים משתנה', () {
      expect(
        const IndexingComplete(),
        isNot(const IndexingComplete(failures: [failure])),
      );
    });
  });
}
