import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_event.dart';
import 'package:otzaria/app_report/bloc/app_report_state.dart';
import 'package:otzaria/app_report/models/app_report_draft.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

import '../app_report/app_report_test_fakes.dart';
import '../test_helpers/memory_cache_provider.dart';

class _ControlledService extends FakeAppReportService {
  _ControlledService({super.respond});
  Completer<void>? pendingWrite;
  final started = Completer<void>();
  int writes = 0;
  int deleteFailures = 0;

  @override
  Future<void> saveDraft(AppReportDraft value) async {
    writes++;
    if (!started.isCompleted) started.complete();
    await pendingWrite?.future;
    await super.saveDraft(value);
  }

  @override
  Future<void> deleteDraft() async {
    if (deleteFailures > 0) {
      deleteFailures--;
      throw StateError('disk unavailable');
    }
    await super.deleteDraft();
  }
}

class _CountingRedactor extends AppReportRedactor {
  _CountingRedactor() : super(environment: const {});
  int calls = 0;
  @override
  Object? redactJson(Object? value) {
    calls++;
    return value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => Settings.init(cacheProvider: MemoryCacheProvider()));
  setUp(() async {
    await Settings.setValue<String>(
      SettingsRepository.keyErrorReportSenderEmail,
      '',
    );
  });

  Future<AppReportBloc> open(_ControlledService service) async {
    final bloc = AppReportBloc(
      trigger: AppReportTrigger.manual,
      service: service,
      collector: FakeAppReportCollector(),
      redactor: AppReportRedactor(environment: const {}),
      autosaveDelay: const Duration(days: 1),
      appVersion: 'test',
    );
    bloc.add(const AppReportAttachmentsRequested());
    await bloc.stream.firstWhere((state) => state is AppReportEditing);
    return bloc;
  }

  Future<void> change(
    AppReportBloc bloc,
    AppReportEvent event,
    bool Function(AppReportEditing) match,
  ) async {
    final next = bloc.stream.firstWhere(
      (state) => state is AppReportEditing && match(state),
    );
    bloc.add(event);
    await next;
  }

  Future<void> fill(AppReportBloc bloc) async {
    await change(
      bloc,
      const AppReportTitleChanged('title'),
      (s) => s.title == 'title',
    );
    await change(
      bloc,
      const AppReportDescriptionChanged('description'),
      (s) => s.description == 'description',
    );
    await change(
      bloc,
      const AppReportEmailChanged('a@b.com'),
      (s) => s.email == 'a@b.com',
    );
  }

  test(
    'leaving an invalid partial report saves raw content without email validation',
    () async {
      final service = _ControlledService();
      final bloc = await open(service);
      await change(
        bloc,
        const AppReportDescriptionChanged('unfinished'),
        (s) => s.description == 'unfinished',
      );
      await change(
        bloc,
        const AppReportEmailChanged('unfinished@'),
        (s) => s.email == 'unfinished@',
      );
      await change(bloc, const AppReportDraftSaved(), (s) => s.draftSaved);
      expect(service.draft!.email, 'unfinished@');
      expect(service.draft!.title, isEmpty);
      expect(service.draft!.description, 'unfinished');
      expect(service.sent, isEmpty);
      expect(service.queued, isEmpty);
      await bloc.close();
    },
  );

  test(
    'a queued submit callback after leaving cannot send the saved draft',
    () async {
      final service = _ControlledService();
      final bloc = await open(service);
      await fill(bloc);
      await change(bloc, const AppReportDraftSaved(), (s) => s.draftSaved);
      bloc.add(const AppReportSubmitted());
      await pumpEventQueue();
      expect(service.sent, isEmpty);
      expect(service.queued, isEmpty);
      expect(service.draft!.description, 'description');
      await bloc.close();
    },
  );

  test('closing an untouched form does not create a draft', () async {
    final service = _ControlledService();
    final bloc = await open(service);
    await bloc.close();
    expect(service.writes, 0);
    expect(service.draft, isNull);
  });

  for (final discard in [false, true]) {
    test(
      'late autosave cannot recreate a ${discard ? 'discarded' : 'sent'} draft',
      () async {
        final service = _ControlledService()..pendingWrite = Completer<void>();
        final bloc = await open(service);
        await fill(bloc);
        bloc.add(const AppReportAutosaveRequested(0));
        await service.started.future;
        final finished = bloc.stream.firstWhere(
          (s) =>
              s is AppReportEditing &&
              (discard ? s.draftDiscarded : s.isFinished),
        );
        bloc.add(
          discard
              ? const AppReportDraftDiscarded()
              : const AppReportSubmitted(),
        );
        await pumpEventQueue();
        service.pendingWrite!.complete();
        await finished;
        final count = service.writes;
        bloc.add(const AppReportAutosaveRequested(0));
        bloc.add(const AppReportDescriptionChanged('late callback'));
        await pumpEventQueue();
        await bloc.close();
        expect(service.draft, isNull);
        expect(service.writes, count);
        expect(service.sent, hasLength(discard ? 0 : 1));
      },
    );
  }

  test(
    'intentional queue handoff ends the draft without calling send',
    () async {
      final service = _ControlledService();
      final bloc = await open(service);
      await fill(bloc);
      await change(
        bloc,
        const AppReportSubmitted(queueOnly: true),
        (s) => s.isFinished,
      );
      expect(service.queued, hasLength(1));
      expect(service.sent, isEmpty);
      expect(service.draft, isNull);
      await bloc.close();
    },
  );

  test('a failed delivery retains the complete editable draft', () async {
    final service = _ControlledService(
      respond: (report) => AppReportDeliveryResult(
        status: AppReportDeliveryStatus.failed,
        report: report,
        failureReason: AppReportFailureReason.rejected,
      ),
    );
    final bloc = await open(service);
    await fill(bloc);
    await change(
      bloc,
      const AppReportSubmitted(),
      (s) => s.invalidField == 'delivery',
    );
    expect(service.draft!.description, 'description');
    expect(service.draft!.diagnostics, {'appInfo': 'x'});
    expect((bloc.state as AppReportEditing).isFinished, isFalse);
    await bloc.close();
  });

  test(
    'retrying cleanup after confirmed delivery never sends a second report',
    () async {
      final service = _ControlledService()..deleteFailures = 1;
      final bloc = await open(service);
      await fill(bloc);
      await change(
        bloc,
        const AppReportSubmitted(),
        (s) => s.invalidField == 'draftFinalize',
      );
      expect(service.sent, hasLength(1));
      expect(service.draft, isNotNull);
      await change(bloc, const AppReportSubmitted(), (s) => s.isFinished);
      expect(service.sent, hasLength(1));
      expect(service.draft, isNull);
      await bloc.close();
    },
  );
  test(
    'attachment budget reuses encoding across keystrokes and refreshes for inclusion changes',
    () async {
      final redactor = _CountingRedactor();
      final bloc = AppReportBloc(
        trigger: AppReportTrigger.manual,
        service: _ControlledService(),
        collector: FakeAppReportCollector(),
        redactor: redactor,
      );
      final form = AppReportEditing(
        type: AppReportType.bug,
        title: '',
        description: '',
        steps: '',
        email: '',
        diagnostics: {'large': 'a' * (1024 * 1024)},
        errorLog: 'log',
      );
      final bytes = bloc.otherAttachmentBytes(form);
      final calls = redactor.calls;
      for (var index = 0; index < 100; index++) {
        expect(
          bloc.otherAttachmentBytes(form.copyWith(title: '$index')),
          bytes,
        );
      }
      expect(redactor.calls, calls);
      expect(
        bloc.otherAttachmentBytes(form.copyWith(includeErrorLog: false)),
        lessThan(bytes),
      );
      expect(redactor.calls, greaterThan(calls));
      await bloc.close();
    },
  );
}
