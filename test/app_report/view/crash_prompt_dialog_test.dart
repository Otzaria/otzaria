import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/app_report/view/crash_prompt_dialog.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../app_report_test_fakes.dart';

/// כמו testWidgets, אך מנקה בסוף את הודעת UiSnack — הטיימר שלה נשאר תלוי
/// אחרת ומכשיל את הבדיקה.
void testSnack(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    await body(tester);
    UiSnack.hide();
    await tester.pump(const Duration(seconds: 5));
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    await Settings.setValue<String>(
      SettingsRepository.keySettingsLanguage,
      'he',
    );
    await Settings.setValue<String>(
      SettingsRepository.keyErrorReportSenderEmail,
      '',
    );
    await Settings.setValue<String>(
      SettingsRepository.keyAppCrashReportMode,
      'ask',
    );
  });

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

  late FakeAppReportService service;
  final savedModes = <AppCrashReportMode>[];

  Future<void> pumpDialog(
    WidgetTester tester, {
    CrashSignature? sig = signature,
    CrashCandidate? custom,
  }) async {
    service = FakeAppReportService();
    savedModes.clear();
    final c = custom ?? candidate(sig: sig);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showCrashPromptDialog(
                  context,
                  candidate: c,
                  saveMode: (mode) async => savedModes.add(mode),
                  createBloc: () => AppReportBloc(
                    trigger: AppReportTrigger.crashPrompt,
                    initialType: CrashReportDecision.reportTypeFor(c),
                    initialTitle: CrashReportDecision.titleFor(c),
                    signature: c.signature,
                    details: c.details ?? '',
                    service: service,
                    collector: FakeAppReportCollector(),
                    redactor: AppReportRedactor(environment: const {}),
                    appVersion: '0.9.98',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testSnack('שליחה בלי תיאור ובלי מייל: נשלח crash_prompt עם החתימה', (
    tester,
  ) async {
    await pumpDialog(tester);
    expect(find.text(CrashPromptDialog.title), findsOneWidget);

    await tapKey(tester, 'crash-prompt-send');

    final report = service.sent.single;
    expect(report.trigger, AppReportTrigger.crashPrompt);
    expect(report.type, AppReportType.crash);
    expect(report.title, 'StateError');
    expect(report.signature, signature);
    expect(report.reporterEmail, '');
    expect(find.byType(CrashPromptDialog), findsNothing);
    expect(find.text(ReportMessages.appReportSent(42)), findsOneWidget);
    expect(savedModes, isEmpty);
  });

  group('תקיעה', () {
    const hangSignature = CrashSignature(
      exceptionType: 'AppHang',
      frames: ['otzaria.exe+0x1234'],
    );
    const hang = CrashCandidate.hang(
      signature: hangSignature,
      hangDuration: Duration(milliseconds: 7400),
      details: 'main thread stack',
    );

    testSnack('נוסח תקיעה, ונשלח כבעיית ביצועים עם משך בכותרת', (
      tester,
    ) async {
      await pumpDialog(tester, custom: hang);
      expect(find.text(CrashPromptDialog.hangTitle), findsOneWidget);
      // תקיעה בזמן ריצה: עכשיו, עם המשך שנמדד.
      expect(find.textContaining('בהפעלה הקודמת'), findsNothing);
      expect(
        find.textContaining('התוכנה הפסיקה להגיב למשך 7 שניות.'),
        findsOneWidget,
      );
      expect(find.text(CrashPromptDialog.title), findsNothing);
      expect(
        find.text('מה עשית לפני שהתוכנה נתקעה? (לא חובה)'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('crash-prompt-description')),
        'גללתי',
      );
      await tapKey(tester, 'crash-prompt-send');

      final report = service.sent.single;
      expect(report.trigger, AppReportTrigger.crashPrompt);
      expect(report.type, AppReportType.performance);
      expect(report.title, 'התוכנה נתקעה (7 שניות)');
      expect(report.description, 'גללתי');
      expect(report.diagnostics?['hangDetails'], 'main thread stack');
      expect(report.signature, hangSignature);
    });

    testSnack('מחסנית ANR נראית בתצוגה המקדימה ונשלחת רק בהסכמה לאבחון', (
      tester,
    ) async {
      await pumpDialog(tester, custom: hang);
      await tapKey(tester, 'app-report-toggle-preview');
      expect(find.textContaining('main thread stack'), findsOneWidget);
      await tapKey(tester, 'app-report-include-diagnostics');
      await tapKey(tester, 'app-report-include-error-log');
      await tapKey(tester, 'crash-prompt-send');
      final report = service.sent.single;
      expect(report.description, isEmpty);
      expect(report.diagnostics, isNull);
      expect(report.errorLog, isNull);
      expect(
        report.toApiPayload().toString(),
        isNot(contains('main thread stack')),
      );
    });

    testSnack('ANR / תקיעה מההפעלה הקודמת: נוסח של הפעלה קודמת', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        custom: const CrashCandidate.hang(
          signature: hangSignature,
          details: 'Android ANR',
          occurredInPreviousRun: true,
        ),
      );
      expect(find.text(CrashPromptDialog.hangTitle), findsOneWidget);
      expect(
        find.textContaining('בהפעלה הקודמת התוכנה הפסיקה להגיב.'),
        findsOneWidget,
      );
      expect(find.textContaining('למשך'), findsNothing);
    });

    testWidgets('הצעה אינה נפתחת מעל הצעה פתוחה', (tester) async {
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
      );
      final gate = Completer<void>();
      var shows = 0;
      Future<void> show(BuildContext _, CrashCandidate _) {
        shows++;
        return gate.future;
      }

      final first = showCrashPromptOnNavigator(hang, show: show);
      expect(await showCrashPromptOnNavigator(hang, show: show), isFalse);
      gate.complete();
      expect(await first, isTrue);
      expect(await showCrashPromptOnNavigator(hang, show: show), isTrue);
      expect(shows, 2);
    });

    testSnack('אל תשלח: הודעת התקיעה', (tester) async {
      await pumpDialog(tester, custom: hang);
      await tapKey(tester, 'crash-prompt-dismiss');
      expect(service.sent, isEmpty);
      expect(find.text(ReportMessages.appReportDraftDiscarded), findsOneWidget);
    });
  });

  testSnack('בלי חתימה — הכותרת הכללית', (tester) async {
    await pumpDialog(tester, sig: null);
    await tapKey(tester, 'crash-prompt-send');
    expect(service.sent.single.title, CrashReportDecision.fallbackTitle);
  });

  testSnack('מייל לא תקין נדחה מקומית', (tester) async {
    await pumpDialog(tester);
    await tester.enterText(
      find.byKey(const ValueKey('crash-prompt-email')),
      'לא-מייל',
    );
    await tapKey(tester, 'crash-prompt-send');
    expect(service.sent, isEmpty);
    expect(find.byType(CrashPromptDialog), findsOneWidget);
  });

  testSnack('ביטול הצרופות משמיט אותן', (tester) async {
    await pumpDialog(tester);
    await tapKey(tester, 'app-report-include-diagnostics');
    await tapKey(tester, 'app-report-include-error-log');
    await tapKey(tester, 'crash-prompt-send');
    expect(service.sent.single.diagnostics, isNull);
    expect(service.sent.single.errorLog, isNull);
  });

  testSnack('"תמיד לשלוח אוטומטית" + שליחה: נשלח ונשמר always', (
    tester,
  ) async {
    await pumpDialog(tester);
    await tester.ensureVisible(find.text('תמיד לשלוח אוטומטית'));
    await tester.tap(find.text('תמיד לשלוח אוטומטית'));
    await tester.pump();
    await tapKey(tester, 'crash-prompt-send');
    expect(service.sent, hasLength(1));
    expect(savedModes, [AppCrashReportMode.always]);
  });

  testSnack('"אל תשאל שוב" + אל תשלח: לא נשלח ונשמר never', (tester) async {
    await pumpDialog(tester);
    await tester.ensureVisible(find.text('אל תשאל שוב'));
    await tester.tap(find.text('אל תשאל שוב'));
    await tester.pump();
    await tapKey(tester, 'crash-prompt-dismiss');
    expect(service.sent, isEmpty);
    expect(savedModes, [AppCrashReportMode.never]);
    expect(find.byType(CrashPromptDialog), findsNothing);
    expect(find.text(ReportMessages.appReportDraftDiscarded), findsOneWidget);
  });

  testSnack('בלי saveMode — הבחירה נכתבת להגדרות', (tester) async {
    service = FakeAppReportService();
    final c = candidate();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCrashPromptDialog(
              context,
              candidate: c,
              createBloc: () => AppReportBloc(
                trigger: AppReportTrigger.crashPrompt,
                service: service,
                collector: FakeAppReportCollector(),
                redactor: AppReportRedactor(environment: const {}),
                appVersion: '0.9.98',
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('אל תשאל שוב'));
    await tester.tap(find.text('אל תשאל שוב'));
    await tester.pump();
    await tapKey(tester, 'crash-prompt-dismiss');
    expect(
      Settings.getValue<String>(SettingsRepository.keyAppCrashReportMode),
      'never',
    );
  });

  test('קריסה מהפעלה קודמת: הדוח בלי הקשר החלון; תקיעה נוכחית: איתו', () {
    expect(
      CrashPromptDialog.collectorFor(candidate()).includesCurrentContext,
      isFalse,
    );
    expect(
      CrashPromptDialog.collectorFor(
        const CrashCandidate.hang(signature: signature),
      ).includesCurrentContext,
      isTrue,
    );
  });
}
