import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_event.dart';
import 'package:otzaria/app_report/bloc/app_report_state.dart';
import 'package:otzaria/app_report/models/app_report_draft.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/view/widgets/app_report_images_section.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/reports/repository/report_draft_store.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/panels/app_reports_panel.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;

class _Collector extends AppReportCollector {
  @override
  Future<AppReportAttachments> collect() async => const AppReportAttachments(
    diagnostics: {'exact': 'אבחון 😀'}, errorLog: 'שורה מקורית <b> &amp;\n',
  );
}

class _CountingRedactor extends AppReportRedactor {
  _CountingRedactor() : super(environment: const {});
  int calls = 0;
  @override
  String redactText(String text) {
    calls++;
    return super.redactText(text);
  }
}

class _PausedQueueService extends AppReportService {
  _PausedQueueService({required super.client});
  final queued = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> queueReport(AppReport report) async {
    await super.queueReport(report);
    if (!queued.isCompleted) queued.complete();
    await release.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late String path;
  final image = AppReportImage(
    fileName: 'qa.gif', mimeType: 'image/gif',
    bytes: Uint8List.fromList([71, 73, 70, 56, 57, 97, 1, 0, 1, 0, 0, 0, 0, 59]),
  );
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qa_app_draft_database_');
    path = p.join(temp.path, 'user_state.db');
    Hive.init(temp.path);
    await Hive.openBox<dynamic>(HiveCache.keyName);
    RunnerWindowChannel.debugSupportedOverride = false;
    AppPaths.debugOverrideDataRootPath(temp.path);
    UserStateDatabase.instance.overridePath(path);
    await Settings.init(cacheProvider: HiveCache());
    await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, false);
    await Settings.setValue<bool>(SettingsRepository.keyQueueErrorReportsWhenOffline, true);
    await Settings.setValue<String>(SettingsRepository.keyErrorReportSenderEmail, '');
  });
  tearDown(() async {
    await AppReportService.suspendAutomaticFlush();
    UserStateDatabase.instance.close();
    await Hive.close();
    RunnerWindowChannel.debugSupportedOverride = null;
    AppPaths.debugOverrideDataRootPath(null);
    await temp.delete(recursive: true);
  });

  Future<AppReportBloc> open(AppReportService service) async {
    final bloc = AppReportBloc(
      trigger: AppReportTrigger.manual, service: service, collector: _Collector(),
      redactor: AppReportRedactor(environment: const {}), appVersion: 'qa',
      autosaveDelay: const Duration(days: 1), clock: () => DateTime.utc(2026, 11, 5),
    );
    final loaded = bloc.stream.firstWhere((s) => s is AppReportEditing);
    bloc.add(const AppReportAttachmentsRequested());
    await loaded;
    return bloc;
  }
  Future<void> change(AppReportBloc bloc, AppReportEvent event,
      bool Function(AppReportEditing) matches) async {
    final next = bloc.stream.firstWhere((s) => s is AppReportEditing && matches(s));
    bloc.add(event);
    await next.timeout(const Duration(seconds: 15));
  }
  Future<void> fill(AppReportBloc bloc) async {
    await change(bloc, const AppReportTitleChanged('כותרת מקורית'), (s) => s.title == 'כותרת מקורית');
    await change(bloc, const AppReportDescriptionChanged('פירוט הטעות'), (s) => s.description == 'פירוט הטעות');
    await change(bloc, const AppReportEmailChanged('qa@example.com'), (s) => s.email == 'qa@example.com');
    await change(bloc, AppReportImagesChanged([image]), (s) => s.images.length == 1);
  }

  test('untouched software form creates no database draft', () async {
    final bloc = await open(AppReportService());
    await bloc.close();
    expect(await ReportDraftStore.instance.list(), isEmpty);
  });

  test('invalid partial form survives real database close and reopen with raw attachments', () async {
    final bloc = await open(AppReportService());
    await change(bloc, const AppReportDescriptionChanged('לא גמור <b> &amp;'), (s) => s.description.isNotEmpty);
    await change(bloc, const AppReportEmailChanged('unfinished@'), (s) => s.email == 'unfinished@');
    await change(bloc, AppReportImagesChanged([image]), (s) => s.images.isNotEmpty);
    await change(bloc, const AppReportDiagnosticsToggled(false), (s) => !s.includeDiagnostics);
    await change(bloc, const AppReportDraftSaved(), (s) => s.draftSaved);
    await bloc.close();
    final saved = (await ReportDraftStore.instance.list()).single;
    final rawBefore = (await ReportDraftStore.instance.read(saved.id))!;
    UserStateDatabase.instance.close();
    UserStateDatabase.instance.overridePath(path);
    final resumed = await open(AppReportService());
    final state = resumed.state as AppReportEditing;
    expect(state.title, isEmpty);
    expect(state.email, 'unfinished@');
    expect(state.description, 'לא גמור <b> &amp;');
    expect(state.includeDiagnostics, isFalse);
    expect(state.diagnostics, {'exact': 'אבחון 😀'});
    expect(state.errorLog, 'שורה מקורית <b> &amp;\n');
    expect(state.images.single.toJson(), image.toJson());
    expect((await ReportDraftStore.instance.read(saved.id))!.attachments, rawBefore.attachments);
    expect(await AppReportService().getPendingReports(), isEmpty);
    await resumed.close();
  });

  test('text-only saves do not rewrite heavy attachment storage; remove and re-add remain durable', () async {
    final service = AppReportService();
    await service.loadDraft();
    final pictures = [image];
    const diagnostics = {'exact': 'אבחון 😀'};
    AppReportDraft draft(String title, List<AppReportImage> images) => AppReportDraft(
      type: AppReportType.bug, title: title, description: '', steps: '', email: '',
      images: images, diagnostics: diagnostics, errorLog: 'same log',
    );
    final db = await UserStateDatabase.instance.database;
    db.execute('CREATE TABLE qa_attachment_writes (count INTEGER NOT NULL)');
    db.execute('INSERT INTO qa_attachment_writes VALUES (0)');
    db.execute('CREATE TRIGGER qa_attachment_update AFTER UPDATE ON report_draft_attachments '
        'BEGIN UPDATE qa_attachment_writes SET count = count + 1; END');
    await service.saveDraft(draft('one', pictures));
    for (var i = 0; i < 12; i++) {
      await service.saveDraft(draft('edit $i', pictures));
    }
    expect(db.select('SELECT count FROM qa_attachment_writes').single['count'], 0);
    await service.saveDraft(draft('without image', const []));
    expect(db.select('SELECT count FROM qa_attachment_writes').single['count'], 1);
    await service.saveDraft(draft('image restored', pictures));
    expect(db.select('SELECT count FROM qa_attachment_writes').single['count'], 2);
    UserStateDatabase.instance.close();
    UserStateDatabase.instance.overridePath(path);
    final restored = await AppReportService().loadDraft();
    expect(restored!.title, 'image restored');
    expect(restored.images.single.toJson(), image.toJson());
  });

  test('schema2 rejection preserves the real draft and never sends a stripped second request', () async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{"error":"invalid request","field":"attachments.images"}', 422);
    });
    final service = AppReportService(client: client);
    final bloc = await open(service);
    await fill(bloc);
    await change(bloc, const AppReportSubmitted(), (s) => s.invalidField == 'delivery');
    expect(requests, hasLength(1));
    expect(requests.single['schema'], 2);
    final record = (await ReportDraftStore.instance.list()).single;
    final raw = (await ReportDraftStore.instance.read(record.id))!;
    expect(raw.attachments['images'], [image.toJson()]);
    expect(raw.payload['description'], 'פירוט הטעות');
    expect(await service.getPendingReports(), isEmpty);
    await bloc.close();
    client.close();
  });

  test('configured offline with queue disabled retains draft, explicit handoff ends it and stale saves stay ended', () async {
    await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, true);
    await Settings.setValue<bool>(SettingsRepository.keyQueueErrorReportsWhenOffline, false);
    var requests = 0;
    final client = MockClient((_) async { requests++; return http.Response('{}', 200); });
    final service = AppReportService(client: client);
    final bloc = await open(service);
    await fill(bloc);
    await change(bloc, const AppReportSubmitted(), (s) => s.invalidField == 'delivery');
    expect((bloc.state as AppReportEditing).result!.failureReason, AppReportFailureReason.offlineQueueDisabled);
    expect(await ReportDraftStore.instance.list(), hasLength(1));
    expect(await service.getPendingReports(), isEmpty);
    await change(bloc, const AppReportSubmitted(queueOnly: true), (s) => s.isFinished);
    bloc.add(const AppReportAutosaveRequested(0));
    bloc.add(const AppReportDescriptionChanged('late callback'));
    await pumpEventQueue();
    await bloc.close();
    expect(await ReportDraftStore.instance.list(), isEmpty);
    final pending = (await service.getPendingReports()).single;
    expect(pending.schema, 2);
    expect(pending.images.single.toJson(), image.toJson());
    expect(pending.description, 'פירוט הטעות');
    expect(requests, 0);
    client.close();
  });

  test('a simulated SocketException exercises actual service fallback to durable queue', () async {
    var requests = 0;
    final client = MockClient((_) async { requests++; throw const SocketException('no network'); });
    final service = AppReportService(client: client);
    final bloc = await open(service);
    await fill(bloc);
    await change(bloc, const AppReportSubmitted(), (s) => s.isFinished);
    expect((bloc.state as AppReportEditing).result!.status, AppReportDeliveryStatus.queued);
    expect((await service.getPendingReports()).single.images.single.toJson(), image.toJson());
    expect(await ReportDraftStore.instance.list(), isEmpty);
    expect(requests, 1);
    await bloc.close();
    client.close();
  });

  test('a delivered form can finish without deleting a newer draft from another window', () async {
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (!requestStarted.isCompleted) requestStarted.complete();
      await releaseResponse.future;
      return http.Response('{"success":true,"issueNumber":42}', 200);
    });
    final firstService = AppReportService(client: client);
    final bloc = await open(firstService);
    final opened = <AppReportBloc>[bloc];
    try {
      await fill(bloc);
      final deliveryFinished = bloc.stream.firstWhere(
        (state) => state is AppReportEditing &&
            (state.isFinished || state.invalidField == 'draftFinalize'),
      );
      bloc.add(const AppReportSubmitted());
      await requestStarted.future.timeout(const Duration(seconds: 15));

      final record = (await ReportDraftStore.instance.list()).single;
      final other = await open(AppReportService(client: client));
      opened.add(other);
      const newDescription = 'New work in a second window while the first sends';
      await change(other, const AppReportDescriptionChanged(newDescription),
          (state) => state.description == newDescription);
      await change(other, const AppReportDraftSaved(), (state) => state.draftSaved);
      await other.close();
      final newerRecord = (await ReportDraftStore.instance.read(record.id))!;
      expect(newerRecord.revision, greaterThan(record.revision));
      releaseResponse.complete();

      final finished = (await deliveryFinished.timeout(const Duration(seconds: 15)))
          as AppReportEditing;
      expect(finished.isFinished, isTrue,
          reason: 'Confirmed delivery must not trap the older form in a revision-conflict retry loop.');
      expect(finished.result!.status, AppReportDeliveryStatus.sent);
      bloc.add(const AppReportSubmitted());
      bloc.add(const AppReportAutosaveRequested(0));
      bloc.add(const AppReportDescriptionChanged('late first-window callback'));
      await pumpEventQueue();

      final preserved = (await ReportDraftStore.instance.read(record.id))!;
      expect(preserved.revision, newerRecord.revision);
      expect(preserved.payload, newerRecord.payload);
      expect(preserved.attachments, newerRecord.attachments);
      expect(requests, hasLength(1));
      expect(await firstService.getPendingReports(), isEmpty);
      expect((await firstService.getSentReports()).single.issueNumber, 42);

      // The preserved work is a distinct explicit report. Reusing the first
      // delivery identity would incorrectly return its old success and erase B.
      final resumed = await open(AppReportService(client: client));
      opened.add(resumed);
      expect((resumed.state as AppReportEditing).description, newDescription);
      await change(resumed, const AppReportSubmitted(), (state) => state.isFinished);
      expect(requests, hasLength(2));
      expect(requests.last['reportId'], isNot(requests.first['reportId']));
      expect(requests.last['description'], newDescription);
      expect(await ReportDraftStore.instance.list(), isEmpty);
    } finally {
      if (!releaseResponse.isCompleted) releaseResponse.complete();
      for (final form in opened.reversed) {
        if (!form.isClosed) await form.close();
      }
      client.close();
    }
  });

  test('two explicit queue handoffs preserve both revisions edited in separate forms', () async {
    final client = MockClient((_) async {
      fail('An explicit queue-only handoff must not attempt HTTP.');
    });
    final firstService = _PausedQueueService(client: client);
    final first = await open(firstService);
    final opened = <AppReportBloc>[first];
    try {
      await fill(first);
      final completed = first.stream.firstWhere(
        (state) => state is AppReportEditing &&
            (state.isFinished || state.invalidField == 'draftFinalize'),
      );
      first.add(const AppReportSubmitted(queueOnly: true));
      await firstService.queued.future.timeout(const Duration(seconds: 15));
      final queuedA = (await firstService.getPendingReports()).single;

      final other = await open(AppReportService(client: client));
      opened.add(other);
      const changed = 'A different description prepared after the first queue handoff';
      await change(other, const AppReportDescriptionChanged(changed),
          (state) => state.description == changed);
      await change(other, const AppReportDraftSaved(), (state) => state.draftSaved);
      await other.close();
      final newer = (await ReportDraftStore.instance.list()).single;
      firstService.release.complete();

      final finished = (await completed.timeout(const Duration(seconds: 15)))
          as AppReportEditing;
      expect(finished.isFinished, isTrue);
      expect(finished.result!.isQueued, isTrue);
      expect((await ReportDraftStore.instance.read(newer.id))!.revision, newer.revision);

      final resumed = await open(AppReportService(client: client));
      opened.add(resumed);
      await change(resumed, const AppReportSubmitted(queueOnly: true),
          (state) => state.isFinished);
      final pending = await firstService.getPendingReports();
      expect(pending, hasLength(2));
      expect(pending.map((report) => report.reportId).toSet(), hasLength(2));
      expect(pending.singleWhere((report) => report.reportId == queuedA.reportId).toJson(), queuedA.toJson());
      final queuedB = pending.singleWhere((report) => report.reportId != queuedA.reportId);
      expect(queuedB.description, changed);
      expect(queuedB.images.single.toJson(), image.toJson());
      expect(await ReportDraftStore.instance.list(), isEmpty);
      expect(await firstService.getSentReports(), isEmpty);
    } finally {
      if (!firstService.release.isCompleted) firstService.release.complete();
      for (final form in opened.reversed) {
        if (!form.isClosed) await form.close();
      }
      client.close();
    }
  });

  test('retry, no-op input and reopening preserve identity until report content changes', () async {
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{"error":"invalid","field":"attachments.images"}', 422);
    });
    final original = await open(AppReportService(client: client));
    final opened = <AppReportBloc>[original];
    Future<void> rejectedSubmit(AppReportBloc bloc) => change(
      bloc,
      const AppReportSubmitted(),
      (state) => !state.isSending && state.invalidField == 'delivery',
    );
    try {
      await fill(original);
      await rejectedSubmit(original);
      final originalId = requests.single['reportId'];
      // This clears validation UI but does not alter any report content.
      await change(original, const AppReportTitleChanged('כותרת מקורית'),
          (state) => state.invalidField == null);
      await rejectedSubmit(original);
      expect(requests, hasLength(2));
      expect(requests.last['reportId'], originalId);
      await change(original, const AppReportDraftSaved(), (state) => state.draftSaved);
      await original.close();

      final reopened = await open(AppReportService(client: client));
      opened.add(reopened);
      await rejectedSubmit(reopened);
      expect(requests, hasLength(3));
      expect(requests.last['reportId'], originalId);
      await change(reopened, const AppReportDescriptionChanged('Intentional changed content'),
          (state) => state.description == 'Intentional changed content');
      await rejectedSubmit(reopened);
      expect(requests, hasLength(4));
      expect(requests.last['reportId'], isNot(originalId));
      expect(requests.last['description'], 'Intentional changed content');
      expect(await ReportDraftStore.instance.list(), hasLength(1));
    } finally {
      for (final form in opened.reversed) {
        if (!form.isClosed) await form.close();
      }
      client.close();
    }
  });

  test('20 MiB attachment budget is cached across typed fields and recomputed for inclusion', () async {
    const size = 10 * 1024 * 1024;
    final diagnostics = {'data': 'x' * (size - utf8.encode(jsonEncode({'data': ''})).length)};
    final redactor = _CountingRedactor();
    final bloc = AppReportBloc(trigger: AppReportTrigger.manual, redactor: redactor);
    final form = AppReportEditing(
      type: AppReportType.bug, title: '', description: '', steps: '', email: '',
      diagnostics: diagnostics, errorLog: 'y' * size,
    );
    expect(bloc.otherAttachmentBytes(form), 20 * 1024 * 1024);
    final calls = redactor.calls;
    final watch = Stopwatch()..start();
    for (var i = 0; i < 100; i++) {
      expect(bloc.otherAttachmentBytes(form.copyWith(title: 'typed $i')), 20 * 1024 * 1024);
    }
    watch.stop();
    debugPrint('QA cached 100 title edits: ${watch.elapsedMicroseconds} microseconds');
    expect(redactor.calls, calls, reason: 'Typing must not rescan either 10 MiB attachment.');
    expect(bloc.otherAttachmentBytes(form.copyWith(includeErrorLog: false)), 10 * 1024 * 1024);
    expect(redactor.calls, greaterThan(calls));
    await bloc.close();
  });

  AppReport queuedReport(String id, {int schema = 2}) => AppReport(
    schema: schema,
    reportId: id,
    type: AppReportType.bug,
    trigger: AppReportTrigger.manual,
    title: 'כותרת מקורית $id',
    description: 'פירוט שאסור למחוק לאחר דחיית שרת',
    reporterEmail: 'qa@example.com',
    appVersion: 'qa',
    platform: 'linux',
    createdAt: DateTime.utc(2026, 11, 5),
    images: [image],
  );

  test('twenty permanent rejections cannot starve the next report after database restart', () async {
    final attempted = <String>[];
    final client = MockClient((request) async {
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      final id = payload['reportId'] as String;
      attempted.add(id);
      return id == 'valid-21'
          ? http.Response('{"success":true,"issueNumber":42}', 200)
          : http.Response('{"error":"invalid","field":"attachments.images"}', 422);
    });
    addTearDown(client.close);
    final first = AppReportService(client: client);
    final originals = <String, Map<String, dynamic>>{};
    for (var i = 0; i < 20; i++) {
      final report = queuedReport('rejected-$i');
      originals[report.reportId] = report.toJson();
      await first.queueReport(report);
    }
    await first.queueReport(queuedReport('valid-21'));
    expect(await first.flushPendingReports(), 0);
    expect(attempted, hasLength(20));
    expect(attempted, isNot(contains('valid-21')));
    expect(await first.getPendingReportsCount(), 21);

    UserStateDatabase.instance.close();
    UserStateDatabase.instance.overridePath(path);
    final reopened = AppReportService(client: client);
    attempted.clear();
    expect(await reopened.flushPendingReports(), 1);
    expect(attempted.first, 'valid-21');
    expect(attempted.length, lessThanOrEqualTo(20));
    final pending = await reopened.getPendingReports();
    expect(pending, hasLength(20));
    for (final report in pending) {
      expect(report.toJson(), originals[report.reportId]);
    }
    expect((await reopened.getSentReports()).single.reportId, 'valid-21');

    attempted.clear();
    expect(await reopened.flushPendingReports(), 0);
    expect(attempted.toSet(), originals.keys.toSet(),
        reason: 'The next bounded pass must wrap to retained reports.');
    expect(await reopened.getPendingReportsCount(), 20);
  });

  test('transient failure keeps its place for retry while permanent failures remain editable', () async {
    final attempted = <String>[];
    var recover = false;
    final client = MockClient((request) async {
      final id = (jsonDecode(request.body) as Map)['reportId'] as String;
      attempted.add(id);
      if (id == 'permanent') return http.Response('{}', 422);
      if (id == 'transient' && !recover) return http.Response('{}', 503);
      return http.Response('{"success":true}', 200);
    });
    addTearDown(client.close);
    final service = AppReportService(client: client);
    for (final id in ['permanent', 'transient', 'after-transient']) {
      await service.queueReport(queuedReport(id));
    }
    expect(await service.flushPendingReports(), 0);
    expect(attempted, ['permanent', 'transient']);
    expect(await service.getPendingReportsCount(), 3);

    UserStateDatabase.instance.close();
    UserStateDatabase.instance.overridePath(path);
    final reopened = AppReportService(client: client);
    recover = true;
    attempted.clear();
    expect(await reopened.flushPendingReports(), 2);
    expect(attempted, ['transient', 'after-transient']);
    expect((await reopened.getPendingReports()).single.reportId, 'permanent');
    expect((await reopened.getPendingReports()).single.images.single.toJson(), image.toJson());
  });

  testWidgets('editing a legacy queued report accepts 8 MiB as schema2 and restores it intact', (tester) async {
    final original = queuedReport('legacy-to-edit', schema: 1);
    await tester.runAsync(() => PendingReportStore.instance.add(
      AppReportService.legacyPendingKind, original.toJson(),
    ));
    AppReport? edited;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: AppReportEditFields(
        report: original,
        typeLabel: (type) => type.name,
        onChanged: (report) => edited = report,
      )),
    )));
    final section = tester.widget<AppReportImagesSection>(find.byType(AppReportImagesSection));
    final eightMiB = AppReportImage(
      fileName: 'eight-mib.gif', mimeType: 'image/gif',
      bytes: Uint8List(8 * 1024 * 1024),
    );
    final selected = mergeAppReportImages(const [], [eightMiB],
        otherAttachmentBytes: section.otherAttachmentBytes);
    expect(selected.rejection, isNull);
    section.onChanged(selected.images);
    expect(edited, isNotNull);
    expect(edited!.schema, 2);
    expect(edited!.validate(), isNull);
    expect(original.schema, 1);
    await tester.pumpWidget(const SizedBox());

    final updated = await tester.runAsync(() => AppReportService().updatePendingReport(edited!));
    expect(updated!.reportId, isNot(original.reportId));
    UserStateDatabase.instance.close();
    UserStateDatabase.instance.overridePath(path);
    final restored = (await tester.runAsync(() => AppReportService().getPendingReports()))!.single;
    expect(restored.schema, 2);
    expect(restored.images.single.bytes, eightMiB.bytes);
    expect(restored.validate(), isNull);
  });

  test('an unedited legacy queue migrates storage without changing its schema or payload', () async {
    final original = queuedReport('legacy-unchanged', schema: 1);
    await PendingReportStore.instance.add(AppReportService.legacyPendingKind, original.toJson());
    Map<String, dynamic>? posted;
    final client = MockClient((request) async {
      posted = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response('{"success":true}', 200);
    });
    addTearDown(client.close);
    final service = AppReportService(client: client);
    expect((await service.getPendingReports()).single.toJson(), original.toJson());
    expect(await service.flushPendingReports(), 1);
    expect(posted, original.toApiPayload());
    expect(posted!['schema'], 1);
    expect(await service.getPendingReports(), isEmpty);
  });
}
