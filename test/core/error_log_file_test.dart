import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win32;

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
      for (final title in ['Queued one', 'Queued two', 'Sync entry']) {
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

    test('כשל בכתיבה סינכרונית משאיר את הרשומה בתור', () async {
      final blocker = File(p.join(tempDir.path, 'logs'))
        ..writeAsStringSync('not a dir');
      background('Still queued');
      expect(
        () => ErrorLogFile.appendText(
          'Critical entry',
          platform: ErrorLogPlatform.other,
          environment: const {},
          tempPath: tempDir.path,
        ),
        throwsA(isA<FileSystemException>()),
      );
      blocker.deleteSync();
      await ErrorLogFile.flushPending(timeout: const Duration(seconds: 30));
      expect(logFile.readAsStringSync(), contains('=== Still queued'));
    });

    test('כותבים מ-isolates שונים משמרים כל רשומה בשלמותה', () async {
      final root = tempDir.path;
      final payload = 'שלום' * 1024;
      final workers = [
        for (var worker = 0; worker < 6; worker++)
          Isolate.run(() {
            for (var entry = 0; entry < 30; entry++) {
              ErrorLogFile.appendText(
                '$worker-$entry $payload\n',
                platform: ErrorLogPlatform.other,
                environment: const {},
                tempPath: root,
              );
            }
          }),
      ];
      for (var entry = 0; entry < 30; entry++) {
        background('Queued $entry');
      }
      await Future.wait([
        ...workers,
        ErrorLogFile.flushPending(timeout: const Duration(seconds: 30)),
      ]);

      final lines = logFile.readAsLinesSync();
      expect(
        [
          for (final line in lines)
            if (line.endsWith(' $payload'))
              line.substring(0, line.length - payload.length - 1),
        ],
        unorderedEquals([
          for (var worker = 0; worker < 6; worker++)
            for (var entry = 0; entry < 30; entry++) '$worker-$entry',
        ]),
      );
      for (var entry = 0; entry < 30; entry++) {
        expect(
          lines.where((line) => line.startsWith('=== Queued $entry ')),
          hasLength(1),
        );
      }
    });

    test('שותף לכתיבה עם handle של ה-watchdog ב-Windows', () async {
      logFile.parent.createSync(recursive: true);
      final handle = using(
        (arena) => win32.CreateFile(
          win32.PCWSTR(logFile.path.toNativeUtf16(allocator: arena)),
          win32.FILE_APPEND_DATA,
          win32.FILE_SHARE_READ | win32.FILE_SHARE_WRITE,
          null,
          win32.OPEN_ALWAYS,
          win32.FILE_ATTRIBUTE_NORMAL,
          null,
        ),
      );
      expect(handle.value, isNot(win32.INVALID_HANDLE_VALUE));
      try {
        background('Queued Windows entry');
        await ErrorLogFile.flushPending(timeout: const Duration(seconds: 30));
        using((arena) {
          final bytes = utf8.encode('=== App hang ===\n');
          final buffer = arena<Uint8>(bytes.length)
            ..asTypedList(bytes.length).setAll(0, bytes);
          final written = arena<Uint32>();
          final result = win32.WriteFile(
            handle.value,
            buffer,
            bytes.length,
            written,
            null,
          );
          expect(result.value, isTrue);
          expect(written.value, bytes.length);
        });
        expect(logFile.readAsStringSync(), contains('=== App hang ==='));
      } finally {
        win32.CloseHandle(handle.value);
      }
      expect(logFile.readAsStringSync(), contains('=== Queued Windows entry'));
    }, skip: !Platform.isWindows);

    test('כותב לנתיב Windows ארוך שמכיל עברית', () {
      final path = p.joinAll([
        tempDir.path,
        for (var i = 0; i < 12; i++) 'תיקיית-יומן-בדיקה-ארוכה-$i',
      ]);
      ErrorLogFile.appendText(
        'שלום\n',
        platform: ErrorLogPlatform.other,
        environment: const {},
        tempPath: path,
      );
      expect(
        File(p.join(path, 'logs', ErrorLogFile.fileName)).readAsStringSync(),
        'שלום\n',
      );
    }, skip: !Platform.isWindows);
  });
}
