import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

CrashCandidate _candidate({
  CrashSignature? signature,
  CrashSignature? minidumpSignature,
}) => CrashCandidate(
  previousSession: SessionLock(
    pid: 1,
    version: '0.9.98',
    startedAt: DateTime.utc(2026, 9, 16),
  ),
  entries: const [],
  signature: signature,
  minidumpSignature: minidumpSignature,
  hasStartupStall: false,
  hasMinidump: signature == null,
);

void main() {
  group('CrashReportDecision.decide — מצב × מועמד × מגבלה', () {
    final cases = <(AppCrashReportMode, bool, bool, CrashReportAction)>[
      (AppCrashReportMode.never, true, true, CrashReportAction.none),
      (AppCrashReportMode.never, true, false, CrashReportAction.none),
      (AppCrashReportMode.ask, true, true, CrashReportAction.prompt),
      // ההצעה למשתמש אינה כפופה למגבלה — הוא מחליט בעצמו.
      (AppCrashReportMode.ask, true, false, CrashReportAction.prompt),
      (
        AppCrashReportMode.always,
        true,
        true,
        CrashReportAction.sendAutomatically,
      ),
      (AppCrashReportMode.always, true, false, CrashReportAction.none),
      (AppCrashReportMode.ask, false, true, CrashReportAction.none),
      (AppCrashReportMode.always, false, true, CrashReportAction.none),
    ];
    for (final (mode, hasCandidate, throttleAllows, expected) in cases) {
      test(
        '${mode.name} / מועמד=$hasCandidate / מגבלה=$throttleAllows → ${expected.name}',
        () {
          expect(
            CrashReportDecision.decide(
              mode: mode,
              candidate: hasCandidate ? _candidate() : null,
              throttleAllows: throttleAllows,
            ),
            expected,
          );
        },
      );
    }
  });

  group('התקנה ניידת: רק ראיה לכשל בקריאת דף → המלצה לכונן מהיר', () {
    const inPageError = CrashSignature(
      exceptionType: '0xc0000006 sqlite3.dll+0x154bc6',
      frames: ['sqlite3.dll+0x154bc6'],
    );
    const accessViolation = CrashSignature(
      exceptionType: '0xc0000005 app.so+0x10',
      frames: ['app.so+0x10'],
    );
    const hang = CrashCandidate.hang(
      signature: CrashSignature(
        exceptionType: 'AppHang',
        frames: ['app.so+0x1234', 'flutter_windows.dll+0x5678'],
      ),
    );

    CrashReportAction decide(
      AppCrashReportMode mode,
      CrashCandidate candidate, {
      bool isPortable = true,
      bool throttleAllows = true,
    }) => CrashReportDecision.decide(
      mode: mode,
      candidate: candidate,
      throttleAllows: throttleAllows,
      isPortable: isPortable,
    );

    test('ask ו-always: לא שואל ולא שולח, אלא ממליץ', () {
      for (final mode in [AppCrashReportMode.ask, AppCrashReportMode.always]) {
        expect(
          decide(
            mode,
            _candidate(
              signature: accessViolation,
              minidumpSignature: inPageError,
            ),
          ),
          CrashReportAction.suggestFasterDrive,
        );
        expect(
          decide(mode, _candidate(signature: inPageError)),
          CrashReportAction.suggestFasterDrive,
        );
      }
    });

    test('קריסה אחרת מדווחת כרגיל', () {
      expect(
        decide(
          AppCrashReportMode.always,
          _candidate(signature: accessViolation),
        ),
        CrashReportAction.sendAutomatically,
      );
      expect(
        decide(AppCrashReportMode.ask, _candidate(signature: accessViolation)),
        CrashReportAction.prompt,
      );
    });

    test('never: גם ההמלצה לא מוצגת', () {
      expect(
        decide(AppCrashReportMode.never, _candidate(signature: inPageError)),
        CrashReportAction.none,
      );
    });

    for (final isPortable in [false, true]) {
      for (final mode in AppCrashReportMode.values) {
        for (final throttleAllows in [false, true]) {
          test('תקיעה: נייד=$isPortable / $mode / מגבלה=$throttleAllows', () {
            final expected = switch (mode) {
              AppCrashReportMode.never => CrashReportAction.none,
              AppCrashReportMode.ask => CrashReportAction.prompt,
              AppCrashReportMode.always =>
                throttleAllows
                    ? CrashReportAction.sendAutomatically
                    : CrashReportAction.none,
            };
            for (final candidate in [
              hang,
              const CrashCandidate.hang(signature: null),
            ]) {
              expect(
                decide(
                  mode,
                  candidate,
                  isPortable: isPortable,
                  throttleAllows: throttleAllows,
                ),
                expected,
              );
            }
          });
        }
      }
    }

    test('התקנה רגילה: כשל בקריאת דף מדווח כרגיל', () {
      expect(
        decide(
          AppCrashReportMode.always,
          _candidate(signature: inPageError),
          isPortable: false,
        ),
        CrashReportAction.sendAutomatically,
      );
    });
  });

  test('parse: ערך לא מוכר נופל ל-ask', () {
    expect(AppCrashReportMode.parse('always'), AppCrashReportMode.always);
    expect(AppCrashReportMode.parse('never'), AppCrashReportMode.never);
    expect(AppCrashReportMode.parse(null), AppCrashReportMode.ask);
    expect(AppCrashReportMode.parse('x'), AppCrashReportMode.ask);
  });

  test('titleFor: סוג החריגה מהחתימה, ובלעדיה הנוסח הכללי', () {
    const sig = CrashSignature(exceptionType: 'StateError', frames: []);
    expect(
      CrashReportDecision.titleFor(_candidate(signature: sig)),
      'StateError',
    );
    expect(
      CrashReportDecision.titleFor(_candidate()),
      CrashReportDecision.fallbackTitle,
    );
    const blank = CrashSignature(exceptionType: '  ', frames: []);
    expect(
      CrashReportDecision.titleFor(_candidate(signature: blank)),
      CrashReportDecision.fallbackTitle,
    );
  });

  test('throttleKeyFor: hash החתימה, ובלעדיה הכותרת הכללית', () {
    const sig = CrashSignature(exceptionType: 'StateError', frames: ['a']);
    expect(
      CrashReportDecision.throttleKeyFor(_candidate(signature: sig)),
      sig.hash,
    );
    expect(
      CrashReportDecision.throttleKeyFor(_candidate()),
      CrashReportDecision.fallbackTitle,
    );
  });
}
