import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/indexing/models/indexing_run_result.dart';
import 'package:otzaria/indexing/services/indexing_failure_reporter.dart';

void main() {
  const failures = [
    IndexingFailure(
      bookTitle: 'מוגן',
      bookPath: r'C:\books\locked.pdf',
      kind: IndexingFailureKind.passwordProtected,
      error: 'No password supplied',
      stackTrace: 'stack line 1\nstack line 2',
    ),
    IndexingFailure(
      bookTitle: 'חלקי',
      bookPath: r'C:\books\partial.pdf',
      kind: IndexingFailureKind.partialPdf,
      error: '3 pages dropped',
    ),
    IndexingFailure(
      bookTitle: 'כשל מנוע',
      bookPath: r'C:\books\engine.pdf',
      kind: IndexingFailureKind.engineWrite,
      error: 'write failed',
    ),
  ];

  const result = IndexingRunResult.completed(
    processedBooks: 10,
    totalBooks: 10,
    indexedBooks: 8,
    failures: failures,
  );

  test('הדוח כולל סיכום מלא של הריצה', () {
    final report = IndexingFailureReporter.formatReport(
      result,
      timestamp: DateTime.utc(2026, 8, 5, 12, 30),
      version: '1.2.3+4',
    );

    expect(report, contains('2026-08-05T12:30:00.000Z'));
    expect(report, contains('Version: 1.2.3+4'));
    expect(report, contains('Completed: true'));
    expect(report, contains('Processed: 10/10'));
    expect(report, contains('Indexed: 8'));
    expect(report, contains('Failures: 3'));
    expect(report, contains('Retryable: 1'));
    expect(report, contains('Warnings: 1'));
  });

  test('הדוח אינו משמיט אף ספר, נתיב, סוג כשל או stack trace', () {
    final report = IndexingFailureReporter.formatReport(result);

    for (final failure in failures) {
      expect(report, contains(failure.bookTitle));
      expect(report, contains(failure.bookPath));
      expect(report, contains(failure.kind.name));
      expect(report, contains(failure.error));
    }
    expect(report, contains('stack line 1\nstack line 2'));
    expect(RegExp(r'--- Failure \d+ ---').allMatches(report), hasLength(3));
  });

  test('כתיבה מוסיפה את הדוח ל-errors.txt', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'otzaria-indexing-report-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    IndexingFailureReporter.writeForTesting(
      result,
      tempPath: tempDir.path,
      timestamp: DateTime.utc(2026),
      version: 'test',
    );

    final file = ErrorLogFile.resolveFile(
      environment: const {},
      platform: ErrorLogPlatform.other,
      tempPath: tempDir.path,
    );
    expect(file.existsSync(), isTrue);
    final contents = file.readAsStringSync();
    expect(contents, contains('Indexing failures'));
    expect(contents, contains(r'C:\books\locked.pdf'));
    expect(contents, contains('Version: test'));
  });

  test('תוצאה נקייה אינה יוצרת קובץ לוג', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'otzaria-indexing-clean-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    IndexingFailureReporter.writeForTesting(
      const IndexingRunResult.completed(
        processedBooks: 2,
        totalBooks: 2,
        indexedBooks: 2,
      ),
      tempPath: tempDir.path,
    );

    expect(
      ErrorLogFile.resolveFile(
        environment: const {},
        platform: ErrorLogPlatform.other,
        tempPath: tempDir.path,
      ).existsSync(),
      false,
    );
  });

  test('ריצה נקייה שחרגה מסף העלייה האיטית נרשמת עם משכה', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'otzaria-indexing-slow-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));

    IndexingFailureReporter.writeForTesting(
      const IndexingRunResult.completed(
        processedBooks: 8124,
        totalBooks: 8124,
        indexedBooks: 39,
      ),
      tempPath: tempDir.path,
      elapsed: const Duration(minutes: 3),
    );

    final contents = ErrorLogFile.resolveFile(
      environment: const {},
      platform: ErrorLogPlatform.other,
      tempPath: tempDir.path,
    ).readAsStringSync();
    expect(contents, contains('=== Indexing run '));
    expect(contents, isNot(contains('Indexing failures')));
    expect(contents, contains('Duration: 180s'));
    expect(contents, contains('Processed: 8124/8124'));
  });
}
