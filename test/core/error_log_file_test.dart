import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:path/path.dart' as p;

import 'dart:io';

void main() {
  test('resolvePath uses LocalAppData on Windows', () {
    final path = ErrorLogFile.resolvePath(
      platform: ErrorLogPlatform.windows,
      environment: {
        'LOCALAPPDATA': r'C:\Users\tester\AppData\Local',
      },
      tempPath: r'C:\Temp',
    );

    expect(
      path,
      p.join(r'C:\Users\tester\AppData\Local', 'logs', 'errors.txt'),
    );
  });

  test('resolvePath falls back to temp when no writable home is available', () {
    final path = ErrorLogFile.resolvePath(
      platform: ErrorLogPlatform.other,
      environment: const {},
      tempPath: r'C:\Temp',
    );

    expect(path, p.join(r'C:\Temp', 'logs', 'errors.txt'));
  });

  test(
    'formatEntry includes version, details and stack trace when provided',
    () {
      ErrorLogFile.setAppVersion('1.2.3+45');

      final entry = ErrorLogFile.formatEntry(
        title: 'FlutterError',
        error: 'boom',
        stackTrace: StackTrace.fromString('stack-line'),
        timestamp: DateTime.utc(2026, 4, 15, 12, 0, 0),
        details: const {
          'Context': 'while testing',
        },
      );

      expect(entry, contains('2026-04-15T12:00:00.000Z'));
      expect(entry, contains('Version: 1.2.3+45'));
      expect(entry, contains('FlutterError'));
      expect(entry, contains('boom'));
      expect(entry, contains('Context: while testing'));
      expect(entry, contains('Stack:'));
      expect(entry, contains('stack-line'));
    },
  );

  test('ensureExists creates the log file in the writable fallback path', () {
    final tempDir = Directory.systemTemp.createTempSync(
      'otzaria_error_log_test_',
    );

    try {
      final logPath = ErrorLogFile.resolvePath(
        platform: ErrorLogPlatform.other,
        environment: const {},
        tempPath: tempDir.path,
      );

      ErrorLogFile.ensureExists(
        platform: ErrorLogPlatform.other,
        environment: const {},
        tempPath: tempDir.path,
      );

      expect(File(logPath).existsSync(), isTrue);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('appendInBackground', () {
    late Directory tempDir;
    late File logFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('otzaria_error_log_bg_');
      logFile = ErrorLogFile.resolveFile(
        platform: ErrorLogPlatform.other,
        environment: const {},
        tempPath: tempDir.path,
      );
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    void background(String title) => ErrorLogFile.appendInBackground(
      title: title,
      error: 'boom',
      platform: ErrorLogPlatform.other,
      environment: const {},
      tempPath: tempDir.path,
    );

    test('אינו כותב בזמן הקריאה, והרשומה בקובץ אחרי flushPending', () async {
      background('Background entry');
      expect(logFile.existsSync(), isFalse);

      await ErrorLogFile.flushPending(timeout: const Duration(seconds: 30));
      final content = logFile.readAsStringSync();
      expect(content, contains('=== Background entry'));
      expect(content, contains('Exception: boom'));
    });

    test('append סינכרוני כותב גם את רשומות התור בלי לאבד אף אחת', () async {
      background('Queued one');
      background('Queued two');
      ErrorLogFile.append(
        title: 'Sync entry',
        error: 'crash',
        platform: ErrorLogPlatform.other,
        environment: const {},
        tempPath: tempDir.path,
      );

      // רשומה שעוד לא יצאה לכתיבה כבר בקובץ, לפני כל המתנה.
      expect(logFile.readAsStringSync(), contains('=== Queued two'));

      await ErrorLogFile.flushPending(timeout: const Duration(seconds: 30));
      final content = logFile.readAsStringSync();
      // הרשומה שכבר יצאה לכתיבה ברקע עשויה להופיע פעמיים, אבל לא להיעלם.
      expect('=== Queued one'.allMatches(content), isNotEmpty);
      for (final title in ['Queued two', 'Sync entry']) {
        expect('=== $title'.allMatches(content), hasLength(1), reason: title);
      }
    });

    test('כתיבת רקע שנפתחה לפני append אינה דורסת את הרשומה שלו', () async {
      for (var i = 0; i < 20; i++) {
        background('Background $i');
        // נותנים לכתיבת הרקע להגיע לפתיחת הקובץ לפני הכתיבה הסינכרונית.
        await Future<void>.delayed(Duration(microseconds: i * 50));
        ErrorLogFile.append(
          title: 'Sync $i',
          error: 'crash',
          platform: ErrorLogPlatform.other,
          environment: const {},
          tempPath: tempDir.path,
        );
        await ErrorLogFile.flushPending(timeout: const Duration(seconds: 30));
      }
      final content = logFile.readAsStringSync();
      for (var i = 0; i < 20; i++) {
        expect(content, contains('=== Sync $i '));
        expect(content, contains('=== Background $i '));
      }
    });

    test('כשל בכתיבה ברקע אינו זורק ואינו עוצר את הרשומות שאחריו', () async {
      File(p.join(tempDir.path, 'logs')).writeAsStringSync('not a dir');
      final otherDir = Directory.systemTemp.createTempSync('otzaria_bg_ok_');
      addTearDown(() => otherDir.deleteSync(recursive: true));

      background('Fails');
      ErrorLogFile.appendInBackground(
        title: 'Succeeds',
        error: 'ok',
        platform: ErrorLogPlatform.other,
        environment: const {},
        tempPath: otherDir.path,
      );
      await ErrorLogFile.flushPending(timeout: const Duration(seconds: 30));

      final written = File(
        p.join(otherDir.path, 'logs', ErrorLogFile.fileName),
      );
      expect(written.readAsStringSync(), contains('=== Succeeds'));
    });

    test('flushPending בלי רשומות מסתיים מיד', () async {
      await ErrorLogFile.flushPending(timeout: const Duration(seconds: 30));
    });
  });
}
