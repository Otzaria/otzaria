import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/scan_result.dart';

void main() {
  group('ScanResult', () {
    test('empty result is successful and has no changes', () {
      const result = ScanResult();
      expect(result.isSuccess, isTrue);
      expect(result.hasPartialFailure, isFalse);
      expect(result.hasChanges, isFalse);
      expect(result.addedBooks, 0);
      expect(result.updatedBooks, 0);
      expect(result.failedBooks, 0);
    });

    test('added and updated books count as changes', () {
      const added = ScanResult(addedBooks: 2);
      const updated = ScanResult(updatedBooks: 3);
      expect(added.hasChanges, isTrue);
      expect(updated.hasChanges, isTrue);
      expect(added.isSuccess, isTrue);
    });

    test('partial failures differ from fatal scan errors', () {
      const partial = ScanResult(addedBooks: 1, failedBooks: 2);
      const fatal = ScanResult(
        fatalError: 'isolate failed',
        failedBooks: 2,
      );

      expect(partial.isSuccess, isTrue);
      expect(partial.hasPartialFailure, isTrue);
      expect(fatal.isSuccess, isFalse);
      expect(fatal.hasPartialFailure, isFalse);
      expect(fatal.hasChanges, isFalse);
    });

    test('retains detailed failures and updated book IDs', () {
      const result = ScanResult(
        failedDetails: [('ספר א', 'conversion failed')],
        updatedBookIds: [7, 9],
      );
      expect(result.failedDetails, [('ספר א', 'conversion failed')]);
      expect(result.updatedBookIds, [7, 9]);
    });
  });
}
