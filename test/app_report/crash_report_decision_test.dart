import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

CrashCandidate _candidate({CrashSignature? signature}) => CrashCandidate(
  previousSession: SessionLock(
    pid: 1,
    version: '0.9.98',
    startedAt: DateTime.utc(2026, 9, 16),
  ),
  entries: const [],
  signature: signature,
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
