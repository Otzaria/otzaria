import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_event.dart';
import 'package:otzaria/app_report/bloc/app_report_state.dart';
import 'package:otzaria/app_report/models/app_report.dart';
import 'package:otzaria/app_report/models/app_report_image.dart';
import 'package:otzaria/app_report/models/crash_signature.dart';
import 'package:otzaria/app_report/repository/app_report_redactor.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../app_report_test_fakes.dart';

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

  final redactor = AppReportRedactor(
    environment: const {'USERPROFILE': r'C:\Users\dani', 'USERNAME': 'dani'},
  );

  AppReportBloc build({
    AppReportTrigger trigger = AppReportTrigger.manual,
    FakeAppReportService? service,
    FakeAppReportCollector? collector,
    String? initialEmail,
    CrashSignature? signature,
    AppReportType initialType = AppReportType.bug,
    String initialTitle = '',
  }) => AppReportBloc(
    trigger: trigger,
    service: service ?? FakeAppReportService(),
    collector: collector ?? FakeAppReportCollector(),
    redactor: redactor,
    initialEmail: initialEmail,
    signature: signature,
    initialType: initialType,
    initialTitle: initialTitle,
    appVersion: '0.9.98',
    clock: () => DateTime.utc(2026, 9, 17),
  );

  blocTest<AppReportBloc, AppReportState>(
    'איסוף הצרופות מעביר לטופס עם הצרופות והמייל השמור',
    setUp: () => Settings.setValue<String>(
      SettingsRepository.keyErrorReportSenderEmail,
      'me@x.com',
    ),
    build: build,
    act: (bloc) => bloc.add(const AppReportAttachmentsRequested()),
    expect: () => [
      isA<AppReportEditing>()
          .having((s) => s.email, 'email', 'me@x.com')
          .having((s) => s.diagnostics, 'diagnostics', {'appInfo': 'x'})
          .having((s) => s.errorLog, 'errorLog', contains('boom'))
          .having((s) => s.includeDiagnostics, 'includeDiagnostics', true),
    ],
  );

  blocTest<AppReportBloc, AppReportState>(
    'צירוף תמונות מעדכן את רשימת התמונות בטופס',
    build: build,
    act: (bloc) => bloc
      ..add(const AppReportAttachmentsRequested())
      ..add(
        AppReportImagesChanged([
          AppReportImage(
            bytes: Uint8List(3),
            fileName: 'shot.png',
            mimeType: 'image/png',
          ),
        ]),
      ),
    skip: 1,
    expect: () => [
      isA<AppReportEditing>().having(
        (s) => s.images.map((i) => i.fileName),
        'images',
        ['shot.png'],
      ),
    ],
  );

  blocTest<AppReportBloc, AppReportState>(
    'כשל באיסוף אינו חוסם את הטופס — הצרופות ריקות',
    build: () => build(collector: FakeAppReportCollector(fail: true)),
    act: (bloc) => bloc.add(const AppReportAttachmentsRequested()),
    expect: () => [
      isA<AppReportEditing>()
          .having((s) => s.diagnostics, 'diagnostics', isNull)
          .having((s) => s.errorLog, 'errorLog', isNull),
    ],
  );

  blocTest<AppReportBloc, AppReportState>(
    'דיווח ידני בלי מייל נדחה מקומית עם invalidField=reporterEmail',
    build: build,
    act: (bloc) => bloc
      ..add(const AppReportAttachmentsRequested())
      ..add(const AppReportTitleChanged('כותרת'))
      ..add(const AppReportDescriptionChanged('תיאור'))
      ..add(const AppReportSubmitted()),
    skip: 3,
    expect: () => [
      isA<AppReportEditing>()
          .having((s) => s.invalidField, 'invalidField', 'reporterEmail')
          .having((s) => s.isSending, 'isSending', false),
    ],
  );

  blocTest<AppReportBloc, AppReportState>(
    'הקלדה בשדה שנכשל מנקה את invalidField',
    build: build,
    seed: () => const AppReportEditing(
      type: AppReportType.bug,
      title: 'כותרת',
      description: '',
      steps: '',
      email: '',
      invalidField: 'description',
    ),
    act: (bloc) => bloc.add(const AppReportDescriptionChanged('תיאור')),
    expect: () => [
      isA<AppReportEditing>().having(
        (s) => s.invalidField,
        'invalidField',
        isNull,
      ),
    ],
  );

  group('שליחה', () {
    late FakeAppReportService service;

    blocTest<AppReportBloc, AppReportState>(
      'דיווח ידני תקין: sending → finished, המייל נשמר, הטקסטים מוסתרים',
      setUp: () => service = FakeAppReportService(),
      build: () => build(service: service),
      act: (bloc) => bloc
        ..add(const AppReportAttachmentsRequested())
        ..add(const AppReportTitleChanged(r'נפל ב-C:\Users\dani\x'))
        ..add(const AppReportDescriptionChanged('תיאור'))
        ..add(const AppReportStepsChanged('שלב'))
        ..add(const AppReportEmailChanged('me@x.com'))
        ..add(const AppReportSubmitted()),
      skip: 5,
      expect: () => [
        isA<AppReportEditing>().having((s) => s.isSending, 'sending', true),
        isA<AppReportEditing>()
            .having((s) => s.isFinished, 'finished', true)
            .having((s) => s.result?.issueNumber, 'issueNumber', 42),
      ],
      verify: (_) {
        final report = service.sent.single;
        expect(report.trigger, AppReportTrigger.manual);
        expect(report.title, r'נפל ב-%USERPROFILE%\x');
        expect(report.reporterEmail, 'me@x.com');
        expect(report.stepsToReproduce, 'שלב');
        expect(report.appVersion, '0.9.98');
        expect(report.diagnostics, isNotNull);
        expect(report.errorLog, isNotNull);
        expect(
          Settings.getValue<String>(
            SettingsRepository.keyErrorReportSenderEmail,
          ),
          'me@x.com',
        );
      },
    );

    blocTest<AppReportBloc, AppReportState>(
      'החרגת הצרופות משמיטה אותן מהדיווח',
      setUp: () => service = FakeAppReportService(),
      build: () => build(service: service),
      act: (bloc) => bloc
        ..add(const AppReportAttachmentsRequested())
        ..add(const AppReportTitleChanged('כותרת'))
        ..add(const AppReportDescriptionChanged('תיאור'))
        ..add(const AppReportEmailChanged('me@x.com'))
        ..add(const AppReportDiagnosticsToggled(false))
        ..add(const AppReportErrorLogToggled(false))
        ..add(const AppReportSubmitted()),
      verify: (_) {
        final report = service.sent.single;
        expect(report.diagnostics, isNull);
        expect(report.errorLog, isNull);
      },
    );

    blocTest<AppReportBloc, AppReportState>(
      'אחרי קריסה: בלי מייל ובלי תיאור עדיין נשלח, עם החתימה והכותרת',
      setUp: () => service = FakeAppReportService(),
      build: () => build(
        service: service,
        trigger: AppReportTrigger.crashPrompt,
        initialType: AppReportType.crash,
        initialTitle: 'StateError',
        signature: const CrashSignature(
          exceptionType: 'StateError',
          frames: ['main.dart'],
        ),
      ),
      act: (bloc) => bloc
        ..add(const AppReportAttachmentsRequested())
        ..add(const AppReportSubmitted()),
      verify: (_) {
        final report = service.sent.single;
        expect(report.type, AppReportType.crash);
        expect(report.trigger, AppReportTrigger.crashPrompt);
        expect(report.title, 'StateError');
        expect(report.signature?.exceptionType, 'StateError');
        expect(report.reporterEmail, '');
        expect(
          Settings.getValue<String>(
            SettingsRepository.keyErrorReportSenderEmail,
          ),
          '',
        );
      },
    );

    blocTest<AppReportBloc, AppReportState>(
      'אחרי קריסה: מייל לא תקין נדחה מקומית',
      build: () => build(trigger: AppReportTrigger.crashPrompt),
      act: (bloc) => bloc
        ..add(const AppReportAttachmentsRequested())
        ..add(const AppReportTitleChanged('קריסה'))
        ..add(const AppReportEmailChanged('לא-מייל'))
        ..add(const AppReportSubmitted()),
      skip: 3,
      expect: () => [
        isA<AppReportEditing>().having(
          (s) => s.invalidField,
          'invalidField',
          'reporterEmail',
        ),
      ],
    );

    blocTest<AppReportBloc, AppReportState>(
      'תוצאת כשל מהשירות מגיעה למצב finished',
      build: () => build(
        service: FakeAppReportService(
          respond: (r) => AppReportDeliveryResult(
            status: AppReportDeliveryStatus.failed,
            report: r,
            failureReason: AppReportFailureReason.rejected,
            rejectedField: 'title',
          ),
        ),
      ),
      act: (bloc) => bloc
        ..add(const AppReportAttachmentsRequested())
        ..add(const AppReportTitleChanged('כותרת'))
        ..add(const AppReportDescriptionChanged('תיאור'))
        ..add(const AppReportEmailChanged('me@x.com'))
        ..add(const AppReportSubmitted()),
      skip: 5,
      expect: () => [
        isA<AppReportEditing>()
            .having((s) => s.result?.isFailed, 'failed', true)
            .having((s) => s.result?.rejectedField, 'field', 'title'),
      ],
    );
  });
}
