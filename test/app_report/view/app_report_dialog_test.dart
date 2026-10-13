import 'package:flutter/material.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/models/app_report_draft.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/view/app_report_dialog.dart';
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
      SettingsRepository.keyErrorReportSenderEmail,
      '',
    );
  });

  late FakeAppReportService service;
  AppReportDeliveryResult? popped;

  Future<void> pumpDialog(
    WidgetTester tester, {
    FakeAppReportService? withService,
    FakeAppReportCollector? collector,
  }) async {
    service = withService ?? FakeAppReportService();
    popped = null;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  popped = await showAppReportDialog(
                    context,
                    createBloc: () => AppReportBloc(
                      trigger: AppReportTrigger.manual,
                      service: service,
                      collector: collector ?? FakeAppReportCollector(),
                      redactor: AppReportRedactor(environment: const {}),
                      appVersion: '0.9.98',
                    ),
                  );
                },
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

  Future<void> fill(WidgetTester tester, {String email = 'me@x.com'}) async {
    await tester.enterText(
      find.byKey(const ValueKey('app-report-title')),
      'כותרת',
    );
    await tester.enterText(
      find.byKey(const ValueKey('app-report-description')),
      'תיאור',
    );
    if (email.isNotEmpty) {
      await tester.enterText(
        find.byKey(const ValueKey('app-report-email')),
        email,
      );
    }
    await tester.pump();
  }

  Future<void> send(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('app-report-send')));
    await tester.tap(find.byKey(const ValueKey('app-report-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testSnack('הטופס מוצג עם ארבעת הסוגים והמייל השמור', (tester) async {
    await Settings.setValue<String>(
      SettingsRepository.keyErrorReportSenderEmail,
      'saved@x.com',
    );
    await pumpDialog(tester);

    expect(find.text('דיווח על תקלה בתוכנה'), findsOneWidget);
    for (final type in AppReportType.values) {
      expect(find.text(appReportTypeLabel(type)), findsOneWidget);
    }
    expect(find.text('saved@x.com'), findsOneWidget);
  });

  testSnack('בלי מייל — הדיווח נדחה מקומית ולא נשלח', (tester) async {
    await pumpDialog(tester);
    await fill(tester, email: '');
    await send(tester);

    expect(service.sent, isEmpty);
    expect(find.text(ReportMessages.appReportEmailRequired), findsOneWidget);
    expect(find.byType(AppReportDialog), findsOneWidget);
  });

  testSnack('שליחה תקינה: נשלח, נסגר ומוצגת הודעת הצלחה עם מספר הדיווח', (
    tester,
  ) async {
    await pumpDialog(tester);
    await fill(tester);
    await send(tester);

    expect(service.sent, hasLength(1));
    expect(service.sent.single.reporterEmail, 'me@x.com');
    expect(find.byType(AppReportDialog), findsNothing);
    expect(popped?.issueNumber, 42);
    expect(find.text(ReportMessages.appReportSent(42)), findsOneWidget);
  });

  testSnack('שמירת טיוטה סוגרת את הטופס בלי לשלוח', (tester) async {
    await pumpDialog(tester);
    await fill(tester);
    await tester.tap(find.byKey(const ValueKey('app-report-save-draft')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.sent, isEmpty);
    expect(service.draft?.title, 'כותרת');
    expect(service.draft?.description, 'תיאור');
    expect(find.byType(AppReportDialog), findsNothing);
    expect(popped, isNull);
    expect(find.text(ReportMessages.appReportDraftSaved), findsOneWidget);
  });

  testSnack('טיוטה שמורה ממלאת את השדות, ומחיקתה מנקה אותם', (tester) async {
    await pumpDialog(
      tester,
      withService: FakeAppReportService(
        draft: const AppReportDraft(
          type: AppReportType.bug,
          title: 'כותרת שמורה',
          description: 'תיאור שמור',
          steps: 'שלב שמור',
          email: 'me@x.com',
        ),
      ),
    );

    expect(find.text('הטופס נטען מטיוטה שמורה'), findsOneWidget);
    expect(find.text('כותרת שמורה'), findsOneWidget);
    expect(find.text('תיאור שמור'), findsOneWidget);
    expect(find.text('שלב שמור'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-report-discard-draft')));
    await tester.pump();

    expect(service.draft, isNull);
    expect(find.text('הטופס נטען מטיוטה שמורה'), findsNothing);
    expect(find.text('תיאור שמור'), findsNothing);
    expect(find.text('me@x.com'), findsOneWidget);
  });

  testSnack('ביטול תיבות הסימון משמיט את הצרופות מהדיווח', (tester) async {
    await pumpDialog(tester);
    await fill(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('app-report-include-diagnostics')),
    );
    await tester.tap(
      find.byKey(const ValueKey('app-report-include-diagnostics')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('app-report-include-error-log')),
    );
    await tester.pump();
    await send(tester);

    final report = service.sent.single;
    expect(report.diagnostics, isNull);
    expect(report.errorLog, isNull);
  });

  testSnack('תצוגה מקדימה נפתחת ומציגה את ה-JSON והלוג', (tester) async {
    await pumpDialog(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('app-report-toggle-preview')),
    );
    await tester.tap(find.byKey(const ValueKey('app-report-toggle-preview')));
    await tester.pump();

    expect(find.text('diagnostics.json'), findsOneWidget);
    expect(find.text('errors.txt'), findsOneWidget);
    expect(find.textContaining('"appInfo"'), findsOneWidget);
  });

  testSnack('צורף לדיווח קיים — הודעת merged', (tester) async {
    await pumpDialog(
      tester,
      withService: FakeAppReportService(
        respond: (r) => AppReportDeliveryResult(
          status: AppReportDeliveryStatus.sent,
          report: r.copyWith(issueNumber: 7, merged: true),
        ),
      ),
    );
    await fill(tester);
    await send(tester);
    expect(find.text(ReportMessages.appReportMerged(7)), findsOneWidget);
  });

  testSnack('נשמר בתור — הודעת queued', (tester) async {
    await pumpDialog(
      tester,
      withService: FakeAppReportService(
        respond: (r) => AppReportDeliveryResult(
          status: AppReportDeliveryStatus.queued,
          report: r,
        ),
      ),
    );
    await fill(tester);
    await send(tester);
    expect(find.text(ReportMessages.appReportQueued), findsOneWidget);
  });

  testSnack('נדחה בשרת — הודעת שגיאה עם השדה', (tester) async {
    await pumpDialog(
      tester,
      withService: FakeAppReportService(
        respond: (r) => AppReportDeliveryResult(
          status: AppReportDeliveryStatus.failed,
          report: r,
          failureReason: AppReportFailureReason.rejected,
          rejectedField: 'title',
        ),
      ),
    );
    await fill(tester);
    await send(tester);
    expect(
      find.text(ReportMessages.appReportRejected('title')),
      findsOneWidget,
    );
  });

  testSnack('ביטול סוגר בלי לשלוח', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.text('ביטול'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AppReportDialog), findsNothing);
    expect(service.sent, isEmpty);
    expect(popped, isNull);
  });
}
