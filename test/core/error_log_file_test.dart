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
}
