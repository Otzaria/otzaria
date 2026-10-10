import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/app_crash_session.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:path/path.dart' as p;

import 'minidump_fixture.dart';

void main() {
  late Directory tmp;
  late Directory logs;
  late Directory sentry;

  final previousStart = DateTime.utc(2026, 9, 16, 8);
  final thisStart = DateTime.utc(2026, 9, 17, 8);

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('otzaria_unclean_exit_');
    logs = Directory(p.join(tmp.path, 'logs'))..createSync();
    sentry = Directory(p.join(tmp.path, '.sentry-native'))..createSync();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  UncleanExitDetector detector({
    bool Function(int pid)? alive,
    int currentPid = 2000,
  }) => UncleanExitDetector(
    logsDirectory: logs.path,
    sentryDatabaseDirs: [sentry.path],
    isProcessAlive: alive ?? (_) => false,
    currentPid: currentPid,
    processStartedAt: thisStart,
  );

  void writeLock({int pid = 1000, DateTime? startedAt}) {
    File(p.join(logs.path, UncleanExitDetector.lockFileName)).writeAsStringSync(
      jsonEncode({
        'pid': pid,
        'version': '0.9.97',
        'startedAt': (startedAt ?? previousStart).toIso8601String(),
      }),
    );
  }

  void writeErrors(String content) =>
      File(p.join(logs.path, 'errors.txt')).writeAsStringSync(content);

  String entry(String title, DateTime at, {String body = ''}) =>
      '=== $title ${at.toIso8601String()} ===\n$body\n';

  test('startSession ו-markCleanExit כותבים ומוחקים את הנעילה', () async {
    final d = detector();
    await d.startSession(version: '0.9.98');
    final lock = SessionLock.tryParse(File(d.lockPath).readAsStringSync())!;
    expect(lock.pid, 2000);
    expect(lock.version, '0.9.98');
    expect(lock.startedAt, thisStart);

    await d.markCleanExit();
    expect(File(d.lockPath).existsSync(), isFalse);
    // מחיקה חוזרת אינה זורקת.
    await d.markCleanExit();
    d.markCleanExitSync();
  });

  test('בלי נעילה אין מועמד', () async {
    writeErrors(
      entry('Unhandled Error', previousStart.add(const Duration(hours: 1))),
    );
    expect(await detector().detectPreviousCrash(), isNull);
  });

  test('נעילה בלי ראיה לקריסה אינה מועמד', () async {
    writeLock();
    writeErrors(entry('Old', previousStart.subtract(const Duration(days: 1))));
    expect(await detector().detectPreviousCrash(), isNull);
  });

  test('תהליך שעדיין חי אינו קריסה', () async {
    writeLock();
    writeErrors(
      entry('Unhandled Error', previousStart.add(const Duration(hours: 1))),
    );
    expect(await detector(alive: (_) => true).detectPreviousCrash(), isNull);
  });

  test('אזהרה בלבד (Initialization Warning) אינה ראיה לקריסה', () async {
    writeLock();
    writeErrors(
      entry(
        'Initialization Warning',
        previousStart.add(const Duration(hours: 1)),
      ),
    );
    expect(await detector().detectPreviousCrash(), isNull);
  });

  test('נעילה של התהליך הנוכחי אינה קריסה', () async {
    writeLock(pid: 2000);
    writeErrors(
      entry('Unhandled Error', previousStart.add(const Duration(hours: 1))),
    );
    expect(await detector().detectPreviousCrash(), isNull);
  });

  test('רשומת שגיאה מאז תחילת ההפעלה הקודמת → מועמד עם חתימה', () async {
    writeLock();
    writeErrors(
      entry('Old', previousStart.subtract(const Duration(days: 1))) +
          entry(
            'FlutterError',
            previousStart.add(const Duration(hours: 2)),
            body:
                'Version: 0.9.97\nException: StateError: Bad state\n\nStack:\n'
                '#0      A.b (package:otzaria/a.dart:1:2)\n',
          ) +
          entry('Current run', thisStart.add(const Duration(minutes: 1))),
    );
    final candidate = await detector().detectPreviousCrash();
    expect(candidate, isNotNull);
    expect(candidate!.entries, hasLength(1));
    expect(candidate.signature!.exceptionType, 'StateError');
    expect(candidate.signature!.frames, ['A.b (package:otzaria/a.dart)']);
    expect(candidate.hasMinidump, isFalse);
    expect(candidate.previousSession.pid, 1000);
  });

  test(
    'רשומה שהתהליך הנוכחי כתב לפני הבדיקה (Slow startup) אינה ראיה',
    () async {
      final timeline = StartupTimeline(sink: (_) {})..start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final checkTime = DateTime.now();
      final processStart = AppCrashSession.processStartTime(
        timeline: timeline,
        now: checkTime,
      );
      expect(processStart.isBefore(checkTime), isTrue);

      writeLock(startedAt: checkTime.subtract(const Duration(hours: 1)));
      writeErrors(
        entry(
          'Slow startup',
          processStart.add(const Duration(milliseconds: 10)),
        ),
      );
      final candidate = await UncleanExitDetector(
        logsDirectory: logs.path,
        sentryDatabaseDirs: [sentry.path],
        isProcessAlive: (_) => false,
        currentPid: 2000,
        processStartedAt: processStart,
      ).detectPreviousCrash();
      expect(candidate, isNull);
    },
  );

  test('errors.txt ענק: נקרא רק הזנב, והרשומה האחרונה נמצאת', () async {
    writeLock();
    final old = entry(
      'Old',
      previousStart.subtract(const Duration(days: 1)),
      body: 'x' * (UncleanExitDetector.maxErrorLogReadBytes + 1000),
    );
    writeErrors(
      old +
          entry(
            'FlutterError',
            previousStart.add(const Duration(hours: 1)),
            body: 'Exception: StateError: Bad state\n',
          ),
    );
    final candidate = await detector().detectPreviousCrash();
    expect(candidate!.entries, hasLength(1));
    expect(candidate.signature!.exceptionType, 'StateError');
  });

  test('Startup stall מסומן', () async {
    writeLock();
    writeErrors(
      entry(
        'Startup stall',
        previousStart.add(const Duration(seconds: 5)),
        body:
            'Stack (module+RVA):\n  0x1f8e8b92bbc\n  flutter_windows.dll+0x81bb05\n',
      ),
    );
    final candidate = await detector().detectPreviousCrash();
    expect(candidate!.hasStartupStall, isTrue);
    expect(candidate.signature!.frames, ['flutter_windows.dll+0x81bb05']);
  });

  test('minidump של Sentry חדש מתחילת ההפעלה הוא ראיה מספקת', () async {
    writeLock(startedAt: DateTime.now().subtract(const Duration(minutes: 5)));
    Directory(p.join(sentry.path, 'reports')).createSync();
    File(p.join(sentry.path, 'reports', 'x.dmp')).writeAsStringSync('dump');
    final d = UncleanExitDetector(
      logsDirectory: logs.path,
      sentryDatabaseDirs: [sentry.path],
      isProcessAlive: (_) => false,
      currentPid: 2000,
      processStartedAt: DateTime.now().add(const Duration(minutes: 1)),
    );
    final candidate = await d.detectPreviousCrash();
    expect(candidate, isNotNull);
    expect(candidate!.hasMinidump, isTrue);
    expect(candidate.signature, isNull);
  });

  group('חתימה מ-minidump (issue #1978)', () {
    UncleanExitDetector freshDetector() => UncleanExitDetector(
      logsDirectory: logs.path,
      sentryDatabaseDirs: [sentry.path],
      isProcessAlive: (_) => false,
      currentPid: 2000,
      processStartedAt: DateTime.now().add(const Duration(minutes: 1)),
    );

    File dump(String name, {DateTime? modified, int code = 0xc0000005}) {
      final reports = Directory(p.join(sentry.path, 'reports'))
        ..createSync(recursive: true);
      final file = File(p.join(reports.path, name))
        ..writeAsBytesSync(buildMinidump(exceptionCode: code));
      if (modified != null) file.setLastModifiedSync(modified);
      return file;
    }

    test(
      'בלי ראיה של Dart — החתימה והכותרת מה-dump החדש ביותר (issue #1978)',
      () async {
        final now = DateTime.now();
        writeLock(startedAt: now.subtract(const Duration(minutes: 5)));
        dump(
          'old.dmp',
          modified: now.subtract(const Duration(minutes: 3)),
          code: 0x80000003,
        );
        dump('new.dmp', modified: now.subtract(const Duration(minutes: 1)));
        dump(
          'stale.dmp',
          modified: now.subtract(const Duration(days: 2)),
          code: 0xc00000fd,
        );

        final candidate = await freshDetector().detectPreviousCrash();
        expect(candidate!.hasMinidump, isTrue);
        expect(
          candidate.signature!.exceptionType,
          '0xc0000005 flutter_windows.dll+0x1e220',
        );
        expect(candidate.signature!.frames, ['flutter_windows.dll+0x1e220']);
        expect(p.basename(candidate.minidump!.path), 'new.dmp');
        expect(
          CrashReportDecision.titleFor(candidate),
          '0xc0000005 flutter_windows.dll+0x1e220',
        );
      },
    );

    test('ראיה של Dart גוברת על ה-dump (issue #1978)', () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(minutes: 5));
      writeLock(startedAt: start);
      writeErrors(
        entry(
          'Unhandled Error',
          start.add(const Duration(minutes: 1)),
          body:
              'Exception: StateError: Bad state\nStack:\n'
              '#0      A.b (package:otzaria/a.dart:1:2)\n',
        ),
      );
      dump('new.dmp');

      final candidate = await freshDetector().detectPreviousCrash();
      expect(candidate!.hasMinidump, isTrue);
      expect(candidate.signature!.exceptionType, 'StateError');
    });
  });

  test('בלי בדיקת תהליך: נעילה ישנה מתחילת התהליך נחשבת לא-חיה', () async {
    writeLock();
    writeErrors(
      entry('Unhandled Error', previousStart.add(const Duration(hours: 1))),
    );
    final candidate = await detector(
      alive: (_) => throw UnsupportedError('x'),
    ).detectPreviousCrash();
    expect(candidate, isNotNull);
  });

  test('נעילה פגומה מתעלמת', () async {
    File(
      p.join(logs.path, UncleanExitDetector.lockFileName),
    ).writeAsStringSync('{not json');
    expect(await detector().detectPreviousCrash(), isNull);
  });

  test('defaultIsProcessAlive: התהליך הנוכחי חי', () {
    if (!Platform.isWindows && !Platform.isLinux) return;
    expect(UncleanExitDetector.defaultIsProcessAlive(pid), isTrue);
  });

  group('AutoCrashReportThrottle', () {
    test('פעם אחת לחתימה בגרסה, ועד 3 ביום', () async {
      var now = DateTime(2026, 9, 17, 10);
      final throttle = AutoCrashReportThrottle(
        filePath: p.join(logs.path, 'throttle.json'),
        clock: () => now,
      );
      expect(
        await throttle.canReport(signatureHash: 'h1', appVersion: '1'),
        isTrue,
      );
      await throttle.recordReported(signatureHash: 'h1', appVersion: '1');
      expect(
        await throttle.canReport(signatureHash: 'h1', appVersion: '1'),
        isFalse,
      );
      expect(
        await throttle.canReport(signatureHash: 'h1', appVersion: '2'),
        isTrue,
      );

      await throttle.recordReported(signatureHash: 'h2', appVersion: '1');
      await throttle.recordReported(signatureHash: 'h3', appVersion: '1');
      expect(
        await throttle.canReport(signatureHash: 'h4', appVersion: '1'),
        isFalse,
      );

      now = now.add(const Duration(days: 1));
      expect(
        await throttle.canReport(signatureHash: 'h4', appVersion: '1'),
        isTrue,
      );
      expect(
        await throttle.canReport(signatureHash: 'h2', appVersion: '1'),
        isFalse,
      );
    });

    test('קובץ פגום מתנהג כריק', () async {
      final file = File(p.join(logs.path, 'throttle.json'))
        ..writeAsStringSync('garbage');
      final throttle = AutoCrashReportThrottle(filePath: file.path);
      expect(
        await throttle.canReport(signatureHash: 'h', appVersion: '1'),
        isTrue,
      );
    });
  });
}
