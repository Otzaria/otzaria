import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/models/app_report_draft.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/view/app_report_dialog.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/services/plugin_file_drop_service.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
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
  });

  late FakeAppReportService service;
  AppReportDeliveryResult? popped;

  Future<void> pumpDialog(
    WidgetTester tester, {
    FakeAppReportService? withService,
    FakeAppReportCollector? collector,
    SettingsLanguage language = SettingsLanguage.hebrew,
    WidgetBuilder Function(BuildContext, WidgetBuilder)? dialogBuilder,
  }) async {
    service = withService ?? FakeAppReportService();
    popped = null;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SettingsTextScope(
          language: language,
          child: Directionality(
            textDirection: language.textDirection,
            child: Builder(
              builder: (context) => Center(
                child: TextButton(
                  key: const ValueKey('report-opener'),
                  onPressed: () async {
                    popped = await showAppReportDialog(
                      context,
                      dialogBuilder: dialogBuilder,
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

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> send(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const ValueKey('app-report-send')));
    await tester.tap(find.byKey(const ValueKey('app-report-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testSnack('settings entry keeps English text menus inside the Hebrew app', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      language: SettingsLanguage.english,
      dialogBuilder: settingsDialogBuilder,
    );
    final reportContext = tester.element(find.byType(AppReportDialog));
    expect(Localizations.localeOf(reportContext).languageCode, 'en');
    expect(MaterialLocalizations.of(reportContext).copyButtonLabel, 'Copy');
    final opener = tester.element(
      find.byKey(const ValueKey('report-opener'), skipOffstage: false),
    );
    expect(Localizations.localeOf(opener), const Locale('he', 'IL'));
    for (final label in [
      'Report type',
      'Title',
      'What happened?',
      'Steps to reproduce (optional)',
      'Email address for replies',
      PluginFileDropService.isSupported
          ? 'Paste, drop, or click to choose an image'
          : 'Paste or click to choose an image',
      'Included with this report',
    ]) {
      final translated = find.text(label);
      expect(translated, findsOneWidget);
      await tester.ensureVisible(translated);
      await tester.pumpAndSettle();
      expect(translated.hitTestable(), findsOneWidget);
    }
    final title = find.byKey(const ValueKey('app-report-title'));
    await tester.ensureVisible(title);
    await tester.enterText(title, 'טקסט בעברית נשמר בדיוק');
    final field = tester.widget<EditableText>(
      find.descendant(of: title, matching: find.byType(EditableText)),
    );
    expect(field.controller.text, 'טקסט בעברית נשמר בדיוק');
    final discard = find.byKey(const ValueKey('app-report-discard'));
    expect(
      find.descendant(of: discard, matching: find.text('Discard draft')),
      findsOneWidget,
    );
    await tester.ensureVisible(discard);
    await tester.tap(discard);
    await tester.pumpAndSettle();
    expect(find.byType(AppReportDialog), findsNothing);
    expect(service.sent, isEmpty);
    expect(service.queued, isEmpty);
    expect(service.draft, isNull);
  });

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

  testSnack('השדות ממולאים במשטח הכרטיס, כמו בעריכת דיווח שמור (#3448)', (
    tester,
  ) async {
    await pumpDialog(tester);
    final fields = tester.widgetList<RtlTextField>(find.byType(RtlTextField));
    expect(fields, hasLength(4));
    final card = AppSurfaces.card(
      tester.element(find.byType(RtlTextField).first),
    );
    for (final field in fields) {
      expect(field.decoration?.filled, isTrue);
      expect(field.decoration?.fillColor, card);
    }
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
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.draft, isNull);
    expect(find.text('הטופס נטען מטיוטה שמורה'), findsNothing);
    expect(find.text('תיאור שמור'), findsNothing);
    expect(find.byType(AppReportDialog), findsNothing);
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

  for (final scenario in [
    (
      schema: 1,
      message: 'הדיווח נשמר בתור לשליחה. ניתן לנהל או לייצא אותו בהגדרות.',
    ),
    (schema: 2, message: ReportMessages.extendedReportQueued),
  ]) {
    testSnack('נשמר בתור — הודעת queued עבור schema ${scenario.schema}', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        withService: FakeAppReportService(
          respond: (r) => AppReportDeliveryResult(
            status: AppReportDeliveryStatus.queued,
            report: r.copyWith(schema: scenario.schema),
          ),
        ),
      );
      await fill(tester);
      await send(tester);
      expect(find.byType(AppReportDialog), findsNothing);
      expect(popped, isNotNull);
      expect(popped!.status, AppReportDeliveryStatus.queued);
      expect(service.sent.single.schema, AppReport.schemaVersion);
      expect(
        popped!.report.toJson(),
        service.sent.single.copyWith(schema: scenario.schema).toJson(),
      );
      expect(find.text(scenario.message), findsOneWidget);
    });
  }

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
      find.text(
        'השליחה לא הושלמה. התוכן נשאר בטיוטה וניתן לערוך אותו או לשמור בתור.',
      ),
      findsOneWidget,
    );
  });

  testSnack('עזיבה זמנית של טופס ריק סוגרת בלי לייצר טיוטה', (tester) async {
    await pumpDialog(tester);
    await tester.tap(find.byKey(const ValueKey('app-report-save-draft')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AppReportDialog), findsNothing);
    expect(service.sent, isEmpty);
    expect(popped, isNull);
  });

  for (final viaHeader in [true, false]) {
    testSnack(
      '${viaHeader ? 'X' : 'כפתור היציאה'} שומר את כל התוכן בלי לשלוח או לשאול',
      (tester) async {
        await pumpDialog(tester);
        await fill(tester);
        await tester.enterText(
          find.byKey(const ValueKey('app-report-steps')),
          'שלב ראשון\nשלב שני',
        );
        await tester.pump();

        final close = viaHeader
            ? find.byTooltip('סגור')
            : find.byKey(const ValueKey('app-report-save-draft'));
        await tester.ensureVisible(close);
        await tester.tap(close);
        await settle(tester);

        expect(find.text('לסגור בלי לשמור?'), findsNothing);
        expect(find.byType(AppReportDialog), findsNothing);
        expect(service.draft, isNotNull);
        expect(service.draft!.title, 'כותרת');
        expect(service.draft!.description, 'תיאור');
        expect(service.draft!.steps, 'שלב ראשון\nשלב שני');
        expect(service.draft!.email, 'me@x.com');
        expect(service.sent, isEmpty);
        expect(service.queued, isEmpty);
        expect(popped, isNull);
      },
    );
  }
}
