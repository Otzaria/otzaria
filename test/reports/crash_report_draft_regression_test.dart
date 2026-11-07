import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_event.dart';
import 'package:otzaria/app_report/bloc/app_report_state.dart';
import 'package:otzaria/app_report/models/app_report_draft.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/reports/repository/report_draft_store.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;

class _Collector extends AppReportCollector {
  @override
  Future<AppReportAttachments> collect() async => const AppReportAttachments(
    diagnostics: {'evidence': 'אבחון <b> &amp;'},
    errorLog: 'original crash log\n',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late String databasePath;
  const signature = CrashSignature(
    exceptionType: 'StateError',
    frames: ['reportCandidate (package:otzaria/main.dart)'],
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('crash_draft_regression_');
    databasePath = p.join(temp.path, 'user_state.db');
    Hive.init(temp.path);
    await Hive.openBox<dynamic>(HiveCache.keyName);
    RunnerWindowChannel.debugSupportedOverride = false;
    AppPaths.debugOverrideDataRootPath(temp.path);
    UserStateDatabase.instance.overridePath(databasePath);
    await Settings.init(cacheProvider: HiveCache());
    await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, false);
    await Settings.setValue<String>(
      SettingsRepository.keyErrorReportSenderEmail,
      '',
    );
  });

  tearDown(() async {
    await AppReportService.suspendAutomaticFlush();
    UserStateDatabase.instance.close();
    await Hive.close();
    RunnerWindowChannel.debugSupportedOverride = null;
    AppPaths.debugOverrideDataRootPath(null);
    await temp.delete(recursive: true);
  });

  Future<AppReportBloc> open({
    AppReportTrigger trigger = AppReportTrigger.manual,
    AppReportType type = AppReportType.bug,
    String title = '',
    CrashSignature? eventSignature,
    String details = '',
    File? dump,
    String? draftId,
  }) async {
    final bloc = AppReportBloc(
      trigger: trigger,
      initialType: type,
      initialTitle: title,
      signature: eventSignature,
      details: details,
      minidumpFile: dump,
      draftId: draftId,
      collector: _Collector(),
      service: AppReportService(),
      redactor: AppReportRedactor(environment: const {}),
      autosaveDelay: const Duration(days: 1),
      appVersion: 'qa',
    );
    addTearDown(() async {
      if (!bloc.isClosed) await bloc.close();
    });
    final ready = bloc.stream.firstWhere((s) => s is AppReportEditing);
    bloc.add(const AppReportAttachmentsRequested());
    await ready.timeout(const Duration(seconds: 10));
    return bloc;
  }

  Future<void> act(
    AppReportBloc bloc,
    AppReportEvent event,
    bool Function(AppReportEditing) done,
  ) async {
    final next = bloc.stream.firstWhere(
      (s) => s is AppReportEditing && done(s),
    );
    bloc.add(event);
    await next.timeout(const Duration(seconds: 10));
  }

  for (final explicitSave in [false, true]) {
    test('untouched manual form stays empty (save=$explicitSave)', () async {
      final bloc = await open();
      if (explicitSave) {
        await act(bloc, const AppReportDraftSaved(), (s) => s.draftSaved);
        expect((bloc.state as AppReportEditing).hasDraft, isFalse);
      }
      await bloc.close();
      expect(await ReportDraftStore.instance.list(), isEmpty);
    });
  }

  for (final hang in [false, true]) {
    test(
      '${hang ? 'hang' : 'crash'} saves unchanged evidence and resumes',
      () async {
        final dump = hang ? null : File(p.join(temp.path, 'event.dmp'));
        await dump?.writeAsBytes([0x4d, 0x44, 0x4d, 0x50, 1, 2, 3, 4]);
        final bloc = await open(
          trigger: AppReportTrigger.crashPrompt,
          type: hang ? AppReportType.performance : AppReportType.crash,
          title: hang ? 'אוצריא נתקעה' : 'אוצריא נסגרה באופן לא צפוי',
          eventSignature: signature,
          details: hang ? 'original hang stack' : '',
          dump: dump,
        );
        final initial = bloc.state as AppReportEditing;
        expect(initial.description, isEmpty);
        expect(initial.email, isEmpty);
        if (hang) {
          expect(initial.diagnostics?['hangDetails'], 'original hang stack');
        } else {
          expect(initial.minidump, isNotNull);
          expect(
            gzip.decode(initial.minidump!.gzipBytes),
            await dump!.readAsBytes(),
          );
        }
        await act(bloc, const AppReportDraftSaved(), (s) => s.draftSaved);
        expect((bloc.state as AppReportEditing).hasDraft, isTrue);
        await bloc.close();
        final saved = (await ReportDraftStore.instance.list()).single;
        final before = (await ReportDraftStore.instance.read(saved.id))!;
        UserStateDatabase.instance.close();
        UserStateDatabase.instance.overridePath(databasePath);
        final resumed = await open(draftId: saved.id);
        final form = resumed.state as AppReportEditing;
        expect(form.diagnostics, initial.diagnostics);
        expect(form.errorLog, initial.errorLog);
        expect(form.minidump?.toJson(), initial.minidump?.toJson());
        expect(resumed.buildReport(form).trigger, AppReportTrigger.crashPrompt);
        expect(resumed.buildReport(form).signature, signature);
        await act(resumed, const AppReportDraftSaved(), (s) => s.draftSaved);
        await resumed.close();
        final after = (await ReportDraftStore.instance.read(saved.id))!;
        expect(after.payload, before.payload);
        expect(after.attachments, before.attachments);
        expect(await AppReportService().getPendingReports(), isEmpty);
      },
    );
  }

  test(
    'resumed event is meaningful even without a title or changed fields',
    () async {
      final service = AppReportService();
      await service.saveDraft(
        const AppReportDraft(
          type: AppReportType.bug,
          title: '',
          description: '',
          steps: '',
          email: '',
          includeDiagnostics: true,
          includeErrorLog: true,
          trigger: AppReportTrigger.crashPrompt,
          signature: signature,
        ),
      );
      final record = (await ReportDraftStore.instance.list()).single;
      final bloc = await open(draftId: record.id);
      await act(bloc, const AppReportDraftSaved(), (s) => s.draftSaved);
      expect((bloc.state as AppReportEditing).hasDraft, isTrue);
      await bloc.close();
      expect(
        (await ReportDraftStore.instance.read(record.id))!.payload['signature'],
        signature.toJson(),
      );
    },
  );

  for (final discard in [false, true]) {
    test(
      'late crash autosave cannot undo ${discard ? 'discard' : 'queue'}',
      () async {
        final bloc = await open(
          trigger: AppReportTrigger.crashPrompt,
          type: AppReportType.crash,
          title: 'Crash evidence',
          eventSignature: signature,
        );
        await act(
          bloc,
          discard
              ? const AppReportDraftDiscarded()
              : const AppReportSubmitted(queueOnly: true),
          (s) => discard ? s.draftDiscarded : s.isFinished,
        );
        bloc.add(const AppReportAutosaveRequested(0));
        await pumpEventQueue();
        await bloc.close();
        expect(await ReportDraftStore.instance.list(), isEmpty);
        expect(
          await AppReportService().getPendingReports(),
          hasLength(discard ? 0 : 1),
        );
      },
    );
  }
}
