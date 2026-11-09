import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/app_report/services/crash_report_flow.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;

import 'app_report_test_fakes.dart';

void main() {
  late Directory tmp;
  late AutoCrashReportThrottle throttle;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('otzaria_crash_flow_');
    throttle = AutoCrashReportThrottle(
      filePath: p.join(tmp.path, 'throttle.json'),
      clock: () => DateTime.utc(2026, 9, 17, 10),
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  const signature = CrashSignature(
    exceptionType: 'StateError',
    frames: ['main.dart'],
  );

  CrashCandidate candidate({CrashSignature? sig = signature}) => CrashCandidate(
    previousSession: SessionLock(
      pid: 1,
      version: '0.9.97',
      startedAt: DateTime.utc(2026, 9, 16),
    ),
    entries: const [],
    signature: sig,
    hasStartupStall: false,
    hasMinidump: sig == null,
  );

  CrashReportFlow flow({
    required AppCrashReportMode mode,
    FakeAppReportService? service,
    Future<bool> Function(CrashCandidate)? showPrompt,
    String savedEmail = '',
    bool? isPortable = false,
    void Function()? showFasterDriveHint,
  }) => CrashReportFlow(
    showPrompt: showPrompt ?? (_) async => true,
    service: service ?? FakeAppReportService(),
    collector: FakeAppReportCollector(),
    redactor: AppReportRedactor(environment: const {}),
    throttle: throttle,
    readMode: () => mode,
    savedEmail: () => savedEmail,
    appVersion: '0.9.98',
    clock: () => DateTime.utc(2026, 9, 17, 10),
    isPortable: isPortable == null ? null : () => isPortable,
    showFasterDriveHint: showFasterDriveHint ?? () {},
  );

  test('never: לא שולח ולא שואל', () async {
    final service = FakeAppReportService();
    var prompted = false;
    final outcome = await flow(
      mode: AppCrashReportMode.never,
      service: service,
      showPrompt: (_) async => prompted = true,
    ).handle(candidate());
    expect(outcome, CrashReportOutcome.ignored);
    expect(service.sent, isEmpty);
    expect(prompted, isFalse);
  });

  test('ask: מציג את ההצעה ולא שולח בעצמו', () async {
    final service = FakeAppReportService();
    CrashCandidate? shown;
    final outcome = await flow(
      mode: AppCrashReportMode.ask,
      service: service,
      showPrompt: (c) async {
        shown = c;
        return true;
      },
    ).handle(candidate());
    expect(outcome, CrashReportOutcome.prompted);
    expect(shown, isNotNull);
    expect(service.sent, isEmpty);
  });

  test('ask בלי Navigator: ההצעה לא הוצגה', () async {
    final outcome = await flow(
      mode: AppCrashReportMode.ask,
      showPrompt: (_) async => false,
    ).handle(candidate());
    expect(outcome, CrashReportOutcome.ignored);
  });

  test('always: שולח auto_crash עם המייל השמור, ורושם במגבלה', () async {
    final service = FakeAppReportService();
    final outcome = await flow(
      mode: AppCrashReportMode.always,
      service: service,
      savedEmail: 'me@x.com',
    ).handle(candidate());
    expect(outcome, CrashReportOutcome.sentAutomatically);

    final report = service.sent.single;
    expect(report.trigger, AppReportTrigger.autoCrash);
    expect(report.type, AppReportType.crash);
    expect(report.title, 'StateError');
    expect(report.reporterEmail, 'me@x.com');
    expect(report.signature, signature);
    expect(report.appVersion, '0.9.98');
    expect(report.diagnostics, isNotNull);
    expect(report.errorLog, contains('boom'));

    expect(
      await throttle.canReport(
        signatureHash: signature.hash,
        appVersion: '0.9.98',
      ),
      isFalse,
    );
  });

  test('always: אותה חתימה פעם שנייה נחסמת במגבלה', () async {
    final service = FakeAppReportService();
    await flow(
      mode: AppCrashReportMode.always,
      service: service,
    ).handle(candidate());
    final outcome = await flow(
      mode: AppCrashReportMode.always,
      service: service,
    ).handle(candidate());
    expect(outcome, CrashReportOutcome.throttled);
    expect(service.sent, hasLength(1));
  });

  test('always: קריסה בלי חתימה מקבלת את הכותרת הכללית', () async {
    final service = FakeAppReportService();
    await flow(
      mode: AppCrashReportMode.always,
      service: service,
    ).handle(candidate(sig: null));
    expect(service.sent.single.title, CrashReportDecision.fallbackTitle);
    expect(service.sent.single.signature, isNull);
  });

  test(
    'נייד: כשל בקריאת דף לא נשלח ולא נשאל — מוצגת המלצה לכונן מהיר',
    () async {
      for (final mode in [AppCrashReportMode.ask, AppCrashReportMode.always]) {
        final service = FakeAppReportService();
        var prompted = false;
        var hints = 0;
        final outcome =
            await flow(
              mode: mode,
              service: service,
              isPortable: true,
              showPrompt: (_) async => prompted = true,
              showFasterDriveHint: () => hints++,
            ).handle(
              candidate(
                sig: const CrashSignature(
                  exceptionType: '0xc0000006 sqlite3.dll+0x154bc6',
                  frames: ['sqlite3.dll+0x154bc6'],
                ),
              ),
            );
        expect(outcome, CrashReportOutcome.suggestedFasterDrive);
        expect(service.sent, isEmpty);
        expect(prompted, isFalse);
        expect(hints, 1);
      }
    },
  );

  for (final isPortable in [false, true]) {
    for (final mode in AppCrashReportMode.values) {
      test('תקיעת קוד: נייד=$isPortable / $mode', () async {
        final exe = File(p.join(tmp.path, 'otzaria.exe'))
          ..writeAsStringSync('');
        if (isPortable) {
          File(
            p.join(tmp.path, AppPaths.portableMarkerFileName),
          ).writeAsStringSync('');
        }
        AppPaths.debugOverrideResolvedExecutable(exe.path);
        addTearDown(() => AppPaths.debugOverrideResolvedExecutable(null));
        expect(AppPaths.isPortable, isPortable);
        const hang = CrashCandidate.hang(
          signature: CrashSignature(
            exceptionType: 'AppHang',
            frames: ['app.so+0x1234', 'flutter_windows.dll+0x5678'],
          ),
          hangDuration: Duration(seconds: 9),
          details: 'Dart stack in app.so',
        );
        final service = FakeAppReportService();
        var prompted = false;
        var hints = 0;
        final reporter = flow(
          mode: mode,
          service: service,
          isPortable: null,
          showPrompt: (_) async => prompted = true,
          showFasterDriveHint: () => hints++,
        );
        expect(await reporter.handle(hang), switch (mode) {
          AppCrashReportMode.never => CrashReportOutcome.ignored,
          AppCrashReportMode.ask => CrashReportOutcome.prompted,
          AppCrashReportMode.always => CrashReportOutcome.sentAutomatically,
        });
        expect(prompted, mode == AppCrashReportMode.ask);
        expect(hints, 0);
        expect(
          service.sent,
          hasLength(mode == AppCrashReportMode.always ? 1 : 0),
        );
        if (mode == AppCrashReportMode.always) {
          expect(service.sent.single.type, AppReportType.performance);
          expect(service.sent.single.diagnostics!['hangDetails'], hang.details);
          expect(await reporter.handle(hang), CrashReportOutcome.throttled);
          expect(service.sent, hasLength(1));
        }
      });
    }
  }
}
