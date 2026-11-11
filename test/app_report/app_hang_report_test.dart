import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/repository/error_log_blocks.dart';
import 'package:otzaria/app_report/services/android_anr_source.dart';
import 'package:otzaria/app_report/services/app_hang_report.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/app_report/services/crash_report_flow.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;

import 'app_report_test_fakes.dart';

/// רשומה בפורמט שכותב windows/runner/hang_monitor.cpp.
String hangEntry(DateTime at, {List<String>? frames}) =>
    '\n=== App hang ${at.toIso8601String()} ===\n'
    'Version: 0.9.98\n'
    'Message: AppHang: UI thread not responding\n'
    'Detected: 61234ms after launch\n'
    'Memory: private 812MB, working set 640MB; system available '
    '1210/8079MB (load 85%), commit available 2048/12175MB\n'
    'Stack (module+RVA):\n'
    '${(frames ?? const ['ntdll.dll+0x9f4e4', 'win32u.dll+0x1234', 'KERNELBASE.dll+0x55', '0x1f8e8b92bbc', 'otzaria.exe+0x1a2b', 'flutter_windows.dll+0x81bb05', 'flutter_windows.dll+0x10', 'flutter_windows.dll+0x20']).map((f) => '  $f').join('\n')}\n';

/// התקיעה של #4858: AV ב-flutter_windows.dll, ומטפל Sentry שנתקע בחריגה מקוננת.
String stuckInHandlerEntry(
  DateTime at, {
  String message = 'AppHang: UI thread stuck in exception handler',
}) =>
    '\n=== App hang ${at.toIso8601String()} ===\n'
    'Version: 0.9.98+99802\n'
    'Message: $message\n'
    'Detected: 9195879ms after launch\n'
    'Dart build-id: e2afd1836a21b5000e7d82caed166b98\n'
    'Stack (module+RVA):\n'
    '  ntdll.dll+0x1384\n'
    '  KERNELBASE.dll+0x10938c\n'
    '  sentry.dll+0x3fc58\n'
    '  ntdll.dll+0x1137e8\n'
    '  ucrtbase.dll+0x20314\n'
    '  sentry.dll+0x230a8\n'
    '  KERNELBASE.dll+0x189ce8\n'
    '  ntdll.dll+0x168154\n'
    '  flutter_windows.dll+0xdc5d6c\n'
    '  app.so+0x226b07c\n'
    '--- Native exception 1/2, thread 7044, 9480ms before detection ---\n'
    'Code: 0xc0000005 EXCEPTION_ACCESS_VIOLATION\n'
    'Address: flutter_windows.dll+0xdc5d6c\n'
    'Access: read 0x10\n'
    'Stack (module+RVA):\n'
    '  flutter_windows.dll+0xdc5d6c\n'
    '  flutter_windows.dll+0x3e5ac\n'
    '  app.so+0x226b07c\n'
    '--- Native exception 2/2, thread 7044, 9479ms before detection ---\n'
    'Code: 0xc0000374 STATUS_HEAP_CORRUPTION\n'
    'Address: ntdll.dll+0x1137e8\n'
    'Stack (module+RVA):\n'
    '  ntdll.dll+0x1137e8\n'
    '  sentry.dll+0x230a8\n';

String recoveredEntry(DateTime at, {int ms = 7400}) =>
    '\n=== App hang recovered ${at.toIso8601String()} ===\n'
    'Duration: ${ms}ms\n';

void main() {
  group('ErrorLogBlock — תקיעה', () {
    test('מזהה תקיעה ושחרור, וחתימה בלי פריימים של מערכת ההפעלה', () {
      final blocks = parseErrorLogBlocks(
        hangEntry(DateTime.utc(2026, 10, 18, 10)) +
            recoveredEntry(DateTime.utc(2026, 10, 18, 10, 0, 8)),
      );
      expect(blocks, hasLength(2));
      expect(blocks.first.isAppHang, isTrue);
      expect(blocks.first.isAppHangRecovered, isFalse);
      expect(blocks.first.isCrashEvidence, isFalse);
      expect(blocks.last.isAppHang, isFalse);
      expect(blocks.last.isAppHangRecovered, isTrue);

      final signature = blocks.first.signature;
      expect(signature.exceptionType, 'AppHang');
      expect(signature.frames, [
        'otzaria.exe+0x1a2b',
        'flutter_windows.dll+0x81bb05',
        'flutter_windows.dll+0x10',
      ]);
    });

    test('עצירה של כל התהליך אינה תקיעה ואינה ראיה לקריסה', () {
      final blocks = parseErrorLogBlocks(
        '\n=== Process stall ${DateTime.utc(2026, 11, 3, 12, 24, 31).toIso8601String()} ===\n'
        'Gap: 296114ms\n',
      );
      expect(blocks.single.title, 'Process stall');
      expect(blocks.single.isAppHang, isFalse);
      expect(blocks.single.isAppHangRecovered, isFalse);
      expect(blocks.single.isStartupStall, isFalse);
      expect(blocks.single.isCrashEvidence, isFalse);
    });

    test('חתימה יציבה בין תקיעות באותו מקום, גם כשההמתנה במערכת שונה', () {
      final a = parseErrorLogBlocks(
        hangEntry(DateTime.utc(2026, 10, 18, 10)),
      ).single.signature;
      final b = parseErrorLogBlocks(
        hangEntry(
          DateTime.utc(2026, 10, 19, 11),
          frames: const [
            'NTDLL.DLL+0xaaaa',
            'user32.dll+0x77',
            'otzaria.exe+0x1a2b',
            'flutter_windows.dll+0x81bb05',
            'flutter_windows.dll+0x10',
          ],
        ),
      ).single.signature;
      expect(b.hash, a.hash);
    });

    // כניסת המנוע ל-Dart (DartEntry::InvokeFunction/InvokeCallable/InvokeClosure)
    // ב-Flutter 3.47.2, מתחת לכל קוד Dart של פריים (#3123).
    const engineEntry = [
      'flutter_windows.dll+0x7fa88b',
      'flutter_windows.dll+0x7faf5f',
      'flutter_windows.dll+0x7fb3ff',
    ];

    test('תקיעה בקוד Dart: החתימה מפריימי app.so, לא מכניסת המנוע', () {
      CrashSignature signatureOf(List<String> dart) => parseErrorLogBlocks(
        hangEntry(
          DateTime.utc(2026, 10, 23),
          frames: [...dart, ...engineEntry],
        ),
      ).single.signature;

      final unmount = signatureOf(const [
        'app.so+0x7d7af8',
        'app.so+0x7d7b53',
        'app.so+0xee04964',
        'app.so+0x7d7b0f',
      ]);
      final layout = signatureOf(const [
        'app.so+0x2776fd9',
        'app.so+0x2777c82',
      ]);

      // הפריים העליון הוא PC של קוד רץ ולכן נשמט.
      expect(unmount.frames, [
        'app.so+0x7d7b53 app.so+0xee04964 app.so+0x7d7b0f',
      ]);
      expect(layout.frames, ['app.so+0x2777c82']);
      expect(unmount.hash, isNot(layout.hash));
    });

    test('נייטיב שנקרא מ-Dart: החתימה מאתר הקריאה ב-app.so', () {
      final signature = parseErrorLogBlocks(
        hangEntry(
          DateTime.utc(2026, 10, 21),
          frames: const [
            'ntdll.dll+0x2b89a',
            'flutter_windows.dll+0xfe5604',
            'flutter_windows.dll+0xc584e',
            'app.so+0x272b96e',
            ...engineEntry,
          ],
        ),
      ).single.signature;
      expect(signature.frames, ['app.so+0x272b96e']);
    });

    test('זהות הבנייה ודגימות נוספות אינן משנות את החתימה', () {
      final plain = parseErrorLogBlocks(
        hangEntry(DateTime.utc(2026, 10, 23), frames: const ['app.so+0x10']),
      ).single;
      final withIdentity =
          hangEntry(
            DateTime.utc(2026, 10, 23),
            frames: const ['app.so+0x10'],
          ).replaceFirst(
            'Stack (module+RVA):',
            'Build commit: 0d6049857abc-dirty\n'
                'Dart build-id: 3f4de71d7b1eccf7d1d9594e1c03aad2\n'
                'Module PDB: dwrite.dll dwrite.pdb 3F2A0B1C4D5E6F708192A3B4C5D6E7F81\n'
                'Stack (module+RVA):',
          );
      final rich = parseErrorLogBlocks(
        '$withIdentity'
        '--- Sample 1, 8000ms into the hang ---\n'
        'Stack (module+RVA):\n'
        '  app.so+0x99\n',
      ).single;
      expect(rich.exceptionMessage, plain.exceptionMessage);
      expect(rich.signature, plain.signature);
    });

    test('מחסנית של מערכת ההפעלה בלבד — נשארים הפריימים המקוריים', () {
      final signature = parseErrorLogBlocks(
        hangEntry(
          DateTime.utc(2026, 10, 18, 10),
          frames: const ['ntdll.dll+0x1', 'user32.dll+0x2'],
        ),
      ).single.signature;
      expect(signature.frames, ['ntdll.dll+0x1', 'user32.dll+0x2']);
    });
  });

  group('ErrorLogBlock — תקיעה בתוך מטפל חריגות', () {
    final at = DateTime.utc(2026, 11, 9, 16, 6, 21);

    test('החתימה מהחריגה המקורית, כמו ב-minidump, ולא מ-sentry.dll', () {
      final block = parseErrorLogBlocks(stuckInHandlerEntry(at)).single;
      expect(block.isAppHang, isTrue);
      expect(block.isStuckInExceptionHandler, isTrue);
      expect(
        block.signature.exceptionType,
        '0xc0000005 flutter_windows.dll+0xdc5d6c',
      );
      expect(block.signature.frames, ['flutter_windows.dll+0xdc5d6c']);
      expect(block.stackText, contains('sentry.dll+0x3fc58'));
      expect(block.stackText, isNot(contains('Native exception')));
    });

    test('חריגה שאינה בתוך מטפל — נשארת חתימת תקיעה', () {
      final block = parseErrorLogBlocks(
        stuckInHandlerEntry(
          at,
          message: 'AppHang: UI thread not responding after native exception',
        ),
      ).single;
      expect(block.isStuckInExceptionHandler, isFalse);
      expect(block.signature.exceptionType, 'AppHang');
    });

    test('כתובת בלי מודול — רק קוד החריגה', () {
      final block = parseErrorLogBlocks(
        stuckInHandlerEntry(at).replaceFirst(
          'Address: flutter_windows.dll+0xdc5d6c',
          'Address: 0x1f8e8b92bbc',
        ),
      ).single;
      expect(block.signature.exceptionType, '0xc0000005');
      expect(block.signature.frames, isEmpty);
    });
  });

  group('UncleanExitDetector — תקיעה', () {
    late Directory tmp;
    late Directory logs;
    final previousStart = DateTime.utc(2026, 10, 1, 8);
    final thisStart = DateTime.utc(2026, 10, 2, 8);

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('otzaria_app_hang_');
      logs = Directory(p.join(tmp.path, 'logs'))..createSync();
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    UncleanExitDetector detector({DateTime? processStartedAt}) =>
        UncleanExitDetector(
          logsDirectory: logs.path,
          sentryDatabaseDirs: [p.join(tmp.path, '.sentry-native')],
          isProcessAlive: (_) => false,
          currentPid: 2000,
          processStartedAt: processStartedAt ?? thisStart,
        );

    void writeLock() =>
        File(
          p.join(logs.path, UncleanExitDetector.lockFileName),
        ).writeAsStringSync(
          jsonEncode({
            'pid': 1000,
            'version': '0.9.98',
            'startedAt': previousStart.toIso8601String(),
          }),
        );

    void writeErrors(String content) =>
        File(p.join(logs.path, 'errors.txt')).writeAsStringSync(content);

    test('תקיעה שלא השתחררה בהפעלה הקודמת → מועמד מסוג תקיעה', () async {
      writeLock();
      writeErrors(hangEntry(previousStart.add(const Duration(hours: 1))));
      final candidate = await detector().detectPreviousCrash();
      expect(candidate, isNotNull);
      expect(candidate!.isHang, isTrue);
      expect(candidate.hangDuration, isNull);
      expect(candidate.signature!.exceptionType, 'AppHang');
      expect(candidate.previousSession!.pid, 1000);
      expect(candidate.occurredInPreviousRun, isTrue);
      expect(CrashReportDecision.titleFor(candidate), 'התוכנה נתקעה');
      expect(
        CrashReportDecision.reportTypeFor(candidate),
        AppReportType.performance,
      );
    });

    test('תקיעה בתוך מטפל חריגות שלא השתחררה → מועמד מסוג קריסה', () async {
      writeLock();
      writeErrors(
        stuckInHandlerEntry(previousStart.add(const Duration(hours: 1))),
      );
      final candidate = await detector().detectPreviousCrash();
      expect(candidate!.isHang, isFalse);
      expect(
        candidate.signature!.exceptionType,
        '0xc0000005 flutter_windows.dll+0xdc5d6c',
      );
      expect(
        CrashReportDecision.titleFor(candidate),
        '0xc0000005 flutter_windows.dll+0xdc5d6c',
      );
      expect(CrashReportDecision.reportTypeFor(candidate), AppReportType.crash);
    });

    test('תקיעה שהשתחררה כבר דווחה — אינה ראיה בהפעלה הבאה', () async {
      writeLock();
      final at = previousStart.add(const Duration(hours: 1));
      writeErrors(
        hangEntry(at) + recoveredEntry(at.add(const Duration(seconds: 8))),
      );
      expect(await detector().detectPreviousCrash(), isNull);
    });

    test('שגיאה אחרי תקיעה שהשתחררה — קריסה רגילה', () async {
      writeLock();
      final at = previousStart.add(const Duration(hours: 1));
      final errorAt = at.add(const Duration(minutes: 1)).toIso8601String();
      writeErrors(
        '${hangEntry(at)}${recoveredEntry(at.add(const Duration(seconds: 8)))}'
        '\n=== FlutterError $errorAt ===\n'
        'Exception: StateError: Bad state\n',
      );
      final candidate = await detector().detectPreviousCrash();
      expect(candidate!.isHang, isFalse);
      expect(candidate.signature!.exceptionType, 'StateError');
    });

    test('detectRecoveredHang: התקיעה האחרונה של התהליך הנוכחי', () async {
      writeErrors(
        hangEntry(previousStart.add(const Duration(hours: 1))) +
            hangEntry(
              thisStart.add(const Duration(minutes: 5)),
              frames: const ['otzaria.exe+0x99'],
            ) +
            recoveredEntry(
              thisStart.add(const Duration(minutes: 5, seconds: 7)),
            ),
      );
      final candidate = await detector().detectRecoveredHang(
        duration: const Duration(milliseconds: 7400),
      );
      expect(candidate!.isHang, isTrue);
      expect(candidate.previousSession, isNull);
      expect(candidate.occurredInPreviousRun, isFalse);
      expect(candidate.signature!.frames, ['otzaria.exe+0x99']);
      expect(CrashReportDecision.titleFor(candidate), 'התוכנה נתקעה (7 שניות)');
    });

    test('detectRecoveredHang: בתוך מטפל חריגות — נשארת חתימת תקיעה', () async {
      final at = thisStart.add(const Duration(minutes: 5));
      writeErrors(
        stuckInHandlerEntry(at) +
            recoveredEntry(at.add(const Duration(seconds: 7))),
      );
      final candidate = await detector().detectRecoveredHang(
        duration: const Duration(milliseconds: 7400),
      );
      expect(candidate!.isHang, isTrue);
      expect(candidate.signature!.exceptionType, 'AppHang');
      expect(
        candidate.signature!.frames.join(' '),
        isNot(contains('flutter_windows.dll+0xdc5d6c')),
      );
    });

    test(
      'detectRecoveredHang: בלי רשומה של התהליך הנוכחי — אין מועמד',
      () async {
        writeErrors(hangEntry(previousStart.add(const Duration(hours: 1))));
        expect(
          await detector().detectRecoveredHang(duration: Duration.zero),
          isNull,
        );
      },
    );
  });

  group('CrashReportFlow — תקיעה', () {
    late Directory tmp;
    late AutoCrashReportThrottle throttle;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('otzaria_hang_flow_');
      throttle = AutoCrashReportThrottle(
        filePath: p.join(tmp.path, 'throttle.json'),
        clock: () => DateTime.utc(2026, 10, 18, 10),
      );
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    const signature = CrashSignature(
      exceptionType: 'AppHang',
      frames: ['otzaria.exe+0x1a2b'],
    );

    CrashReportFlow flow(
      FakeAppReportService service, {
      AppCrashReportMode mode = AppCrashReportMode.always,
      Future<bool> Function(CrashCandidate)? showPrompt,
    }) => CrashReportFlow(
      showPrompt: showPrompt ?? (_) async => true,
      service: service,
      collector: FakeAppReportCollector(),
      redactor: AppReportRedactor(environment: const {}),
      throttle: throttle,
      readMode: () => mode,
      savedEmail: () => '',
      appVersion: '0.9.98',
      clock: () => DateTime.utc(2026, 10, 18, 10),
    );

    test(
      'always: נשלח כבעיית ביצועים, auto_crash, עם הפרטים באבחון הפרטי',
      () async {
        final service = FakeAppReportService();
        final outcome = await flow(service).handle(
          const CrashCandidate.hang(
            signature: signature,
            hangDuration: Duration(seconds: 12),
            details: 'ANR: main thread blocked',
          ),
        );
        expect(outcome, CrashReportOutcome.sentAutomatically);
        final report = service.sent.single;
        expect(report.type, AppReportType.performance);
        expect(report.trigger, AppReportTrigger.autoCrash);
        expect(report.title, 'התוכנה נתקעה (12 שניות)');
        expect(report.description, isEmpty);
        expect(report.diagnostics?['hangDetails'], 'ANR: main thread blocked');
        expect(report.signature, signature);
      },
    );

    test('ANR של אנדרואיד: בלי משך, מגבלה לפי hash החתימה', () async {
      final service = FakeAppReportService();
      final anr = CrashCandidate.hang(
        signature: anrSignatureFromTrace(
          '  at org.otzaria.otzaria.FolderImportChannel.copyTree(F.kt:1)\n',
        ),
        details: anrDetails(
          timestamp: DateTime.utc(2026, 10, 18),
          mainThreadTrace: 'at org.otzaria.X(X.kt:1)',
        ),
      );
      await flow(service).handle(anr);
      final report = service.sent.single;
      expect(report.type, AppReportType.performance);
      expect(report.title, CrashReportDecision.hangTitle);
      expect(report.signature!.exceptionType, 'ANR');
      expect(report.description, isEmpty);
      expect(report.diagnostics?['hangDetails'], contains('Android ANR'));
      expect(
        CrashReportDecision.throttleKeyFor(anr),
        anr.signature!.hash,
      );
    });

    test('always: אותה חתימה פעם שנייה נחסמת במגבלה', () async {
      final service = FakeAppReportService();
      const hang = CrashCandidate.hang(signature: signature);
      await flow(service).handle(hang);
      expect(
        await flow(service).handle(hang),
        CrashReportOutcome.throttled,
      );
      expect(service.sent, hasLength(1));
    });

    test('תקיעה בלי חתימה — מפתח מגבלה נפרד מקריסה בלי חתימה', () {
      expect(
        CrashReportDecision.throttleKeyFor(
          const CrashCandidate.hang(signature: null),
        ),
        CrashReportDecision.hangTitle,
      );
    });

    test('ask: הצעה אחת לכל היותר בהפעלה; שלא הוצגה — ננסה שוב', () async {
      AppHangReport.resetSessionForTesting();
      addTearDown(AppHangReport.resetSessionForTesting);
      const hang = CrashCandidate.hang(signature: signature);
      var shown = 0;
      var navigatorReady = false;
      Future<bool> show(CrashCandidate _) async {
        if (!navigatorReady) return false;
        shown++;
        return true;
      }

      expect(
        await AppHangReport.promptOncePerSession(hang, show: show),
        isFalse,
      );
      navigatorReady = true;
      expect(
        await AppHangReport.promptOncePerSession(hang, show: show),
        isTrue,
      );
      expect(
        await AppHangReport.promptOncePerSession(hang, show: show),
        isFalse,
      );
      expect(shown, 1);

      final outcome = await flow(
        FakeAppReportService(),
        mode: AppCrashReportMode.ask,
        showPrompt: (c) => AppHangReport.promptOncePerSession(c, show: show),
      ).handle(hang);
      expect(outcome, CrashReportOutcome.ignored);
      expect(shown, 1);
    });

    test('AppHangReport: never — אינו קורא את הלוג', () async {
      var detected = false;
      await AppHangReport.onRecovered(
        const {'durationMs': 7000},
        readMode: () => AppCrashReportMode.never,
        detect: (_) async {
          detected = true;
          return null;
        },
      );
      expect(detected, isFalse);
    });

    test('AppHangReport: מעביר את המשך מהנייטיב ל-flow', () async {
      final service = FakeAppReportService();
      Duration? received;
      await AppHangReport.onRecovered(
        const {'durationMs': 9100},
        readMode: () => AppCrashReportMode.always,
        detect: (duration) async {
          received = duration;
          return CrashCandidate.hang(
            signature: signature,
            hangDuration: duration,
          );
        },
        flow: flow(service),
      );
      expect(received, const Duration(milliseconds: 9100));
      expect(service.sent.single.title, 'התוכנה נתקעה (9 שניות)');
    });
  });
}
