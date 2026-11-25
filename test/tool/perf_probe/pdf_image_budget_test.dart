import 'package:test/test.dart';

import '../../../tool/perf_probe/src/pdf_image_budget.dart';

void main() {
  Map<String, dynamic> snapshot() => {
    ...pdfImageBudgetObservationIdentity,
    'maximumBytes': 100,
    'retainedBytes': 40,
    'pendingBytes': 30,
    'speculativePendingBytes': 20,
    'estimatedBytes': 70,
    'processPeakEstimatedBytes': 90,
  };

  test(
    'missing snapshots are unavailable and explicit zeros remain samples',
    () {
      expect(parsePdfImageBudgetSnapshot(null, context: 'test'), isNull);
      final empty = {
        ...pdfImageBudgetObservationIdentity,
        for (final key in pdfImageBudgetByteKeys) key: 0,
      };
      expect(parsePdfImageBudgetSnapshot(empty, context: 'test'), empty);
    },
  );

  test('visible pinned work may exceed the desired maximum', () {
    final overBudget = snapshot()..['maximumBytes'] = 50;
    expect(
      parsePdfImageBudgetSnapshot(overBudget, context: 'test'),
      overBudget,
    );
  });

  for (final change in <String, Object?>{
    'schemaVersion': 2,
    'source': 'RSS',
    'scope': 'all-processes',
    'unit': 'measured-native-bytes',
    'peakScope': 'current-phase',
    'maximumBytes': null,
    'retainedBytes': -1,
    'pendingBytes': 30.0,
    'speculativePendingBytes': 31,
    'estimatedBytes': 71,
    'processPeakEstimatedBytes': 69,
  }.entries) {
    test('rejects incompatible or inconsistent ${change.key}', () {
      final invalid = snapshot()..[change.key] = change.value;
      expect(
        () => parsePdfImageBudgetSnapshot(invalid, context: 'test'),
        throwsFormatException,
      );
    });
  }

  test('a numeric version alias cannot bypass identity validation', () {
    final invalid = snapshot()..['schemaVersion'] = 1.0;
    expect(
      () => parsePdfImageBudgetSnapshot(invalid, context: 'test'),
      throwsFormatException,
    );
    expect(
      () => parsePdfImageBudgetSnapshot([], context: 'test'),
      throwsFormatException,
    );
  });
}
