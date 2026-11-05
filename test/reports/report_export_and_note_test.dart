import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/reports/repository/report_draft_store.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;

import 'reporting_test_pump.dart';

// Independent QA probes. Exercise the public backup and dialog entry points;
// do not substitute the implementations' private filtering helpers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('report_qa_export_');
    Hive.init(temp.path);
    await Hive.openBox<dynamic>(HiveCache.keyName);
    RunnerWindowChannel.debugSupportedOverride = false;
    AppPaths.debugOverrideDataRootPath(temp.path);
    UserStateDatabase.instance.overridePath(p.join(temp.path, 'user_state.db'));
    await Settings.init(cacheProvider: HiveCache());
    await Settings.setValue<String>(
      SettingsRepository.keyBackupPath,
      p.join(temp.path, 'backups'),
    );
    await Settings.setValue<String>(
      SettingsRepository.keyDatabasesPath,
      p.join(temp.path, 'databases'),
    );
    await Settings.setValue<String>(
      SettingsRepository.keyFontFamily,
      'candara',
    );
    await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, true);
  });

  tearDown(() async {
    await PersonalNotesDatabase.instance.close();
    PluginSystemDatabase.instance.resetForTests();
    UserStateDatabase.instance.close();
    await Hive.close();
    RunnerWindowChannel.debugSupportedOverride = null;
    AppPaths.debugOverrideDataRootPath(null);
    await temp.delete(recursive: true);
  });

  test(
    'actual portable backup includes legacy + explicit v2 queue but no local drafts',
    () async {
      final store = PendingReportStore.instance;
      final drafts = ReportDraftStore.instance;
      const draftSecret = 'LOCAL_DRAFT_SENTINEL_never_export_20261105';
      final attachmentSecret = base64Encode(
        utf8.encode('PRIVATE_DRAFT_IMAGE_BYTES'),
      );
      final newReport = AppReport(
        reportId: '00000000-0000-4000-8000-000000000002',
        type: AppReportType.bug,
        trigger: AppReportTrigger.manual,
        reporterEmail: 'qa@example.com',
        title: 'Intentional queue handoff',
        description: 'This report is ready for transfer.',
        createdAt: DateTime.utc(2026, 11, 5),
        appVersion: 'qa-final-head',
        platform: 'linux',
        osVersion: 'Linux QA',
        errorLog: 'x' * 250001,
      );
      final legacy =
          newReport
              .copyWith(
                reportId: '00000000-0000-4000-8000-000000000001',
                title: 'Existing legacy pending report',
              )
              .toJson()
            ..remove('schema');
      await store.add(AppReportService.legacyPendingKind, legacy);
      // Explicit public action to prepare the new report for transfer.
      final service = AppReportService();
      await service.queueReport(newReport);
      // Recreate a legacy row after queue preparation, as an older process could.
      await store.add(AppReportService.legacyPendingKind, {
        ...legacy,
        'reportId': '00000000-0000-4000-8000-000000000003',
      });
      await drafts.write(
        id: 'draft-book-local',
        kind: ReportDraftStore.bookKind,
        title: draftSecret,
        payload: {
          'form': {'details': draftSecret},
        },
        revision: 0,
        attachments: {
          'images': [
            {'data': attachmentSecret},
          ],
        },
      );
      await drafts.write(
        id: 'draft-app-local',
        kind: ReportDraftStore.appKind,
        title: draftSecret,
        payload: {'description': draftSecret},
        revision: 0,
        attachments: {
          'errorLog': draftSecret,
          'diagnostics': {'local': draftSecret},
        },
      );
      await store.add(AppReportService.draftKind, {'title': draftSecret});

      final result = await BackupService.createBackup(
        includeSettings: true,
        includeBookmarks: false,
        includeHistory: false,
        includeNotes: false,
        includeWorkspaces: false,
        includeShamorZachor: false,
        includePlugins: false,
      );
      final raw = await File(result.path).readAsString();
      expect(raw, isNot(contains(draftSecret)));
      expect(raw, isNot(contains(attachmentSecret)));
      expect(raw, isNot(contains('report_drafts')));
      expect(raw, isNot(contains('report_draft_attachments')));
      final exported = jsonDecode(raw) as Map<String, dynamic>;
      expect(
        exported['version'],
        '3.0',
        reason:
            'An older restorer must reject v2 app reports before placing them in its legacy transport queue.',
      );
      final fixture = File('build/reporting_qa/app-report-backup-schema2.json');
      await fixture.parent.create(recursive: true);
      await fixture.writeAsString(raw);
      final queues = exported['reportQueues'] as Map<String, dynamic>;
      final appQueue =
          queues[AppReportService.queueBoxName] as Map<String, dynamic>;
      final legacyPending = (appQueue['pending'] as List)
          .cast<Map<String, dynamic>>();
      final currentPending = (appQueue['pendingV2'] as List)
          .cast<Map<String, dynamic>>();
      expect(legacyPending, hasLength(2));
      expect(legacyPending.every((r) => (r['schema'] ?? 1) == 1), isTrue);
      expect(currentPending, [newReport.toJson()]);
      final pending = [...legacyPending, ...currentPending];
      expect(pending, hasLength(3));
      expect(
        pending.singleWhere((r) => r['reportId'] == newReport.reportId),
        newReport.toJson(),
      );
      expect(
        pending.singleWhere((r) => r['reportId'] == legacy['reportId']),
        legacy,
      );
      expect(await drafts.list(), hasLength(2));
      expect((await drafts.read('draft-book-local'))!.attachments['images'], [
        {'data': attachmentSecret},
      ]);
      expect(
        await store.listByKind(AppReportService.legacyPendingKind),
        isEmpty,
      );
      expect(
        await store.listByKind(AppReportService.pendingKind),
        hasLength(3),
      );

      // The only transferred item is the actual exported JSON, restored into a
      // separate database to model a second computer, not a reset of the same list.
      UserStateDatabase.instance.close();
      UserStateDatabase.instance.overridePath(
        p.join(temp.path, 'receiving_user_state.db'),
      );
      await BackupService.restoreFromBackup(result.path);
      expect(await drafts.list(), isEmpty);
      expect(await store.listByKind(AppReportService.draftKind), isEmpty);
      final restored = await service.getPendingReports();
      expect(restored, hasLength(3));
      expect(
        restored.singleWhere((r) => r.reportId == newReport.reportId).schema,
        2,
      );
      expect(
        restored.singleWhere((r) => r.reportId == newReport.reportId).errorLog,
        newReport.errorLog,
      );
      expect(
        restored.singleWhere((r) => r.reportId == legacy['reportId']).schema,
        1,
      );
      expect(
        restored
            .singleWhere((r) => r.reportId == newReport.reportId)
            .toApiPayload(),
        newReport.toApiPayload(),
      );

      // A backup containing only the old schema remains usable by old clients.
      // Export it through the same public entry point for the pinned legacy probe.
      final currentRow = (await store.listByKind(
        AppReportService.pendingKind,
      )).singleWhere((row) => row.payload['reportId'] == newReport.reportId);
      await store.deleteIds([currentRow.id]);
      final legacyOnlyResult = await BackupService.createBackup(
        includeSettings: true,
        includeBookmarks: false,
        includeHistory: false,
        includeNotes: false,
        includeWorkspaces: false,
        includeShamorZachor: false,
        includePlugins: false,
      );
      final legacyOnlyRaw = await File(legacyOnlyResult.path).readAsString();
      final legacyOnly = jsonDecode(legacyOnlyRaw) as Map<String, dynamic>;
      expect(legacyOnly['version'], '2.0');
      final legacyOnlyQueue =
          (legacyOnly['reportQueues'] as Map)[AppReportService.queueBoxName]
              as Map;
      expect(legacyOnlyQueue['pending'], unorderedEquals(legacyPending));
      expect(legacyOnlyQueue['pendingV2'] ?? const [], isEmpty);
      await File(
        'build/reporting_qa/app-report-backup-legacy-only.json',
      ).writeAsString(legacyOnlyRaw);
    },
  );

  testWidgets(
    'actual note report entry preserves literal markup in selection and durable target',
    (tester) async {
      const selected = 'כתיב <b> מילולי &amp; וגם < 7 > 3';
      const noteContext = 'הערת שוליים 2 (שורה 8):\nלפני $selected אחרי';
      late BuildContext openContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                openContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      Future<void>? reporting;
      await tester.runAsync(() async {
        reporting = ErrorReportHelper.showErrorReportDialog(
          context: openContext,
          selectedText: selected,
          state: null,
          fontSize: 18,
          bookTitle: 'ספר הערות QA',
          reportBook: TextBook(title: 'ספר הערות QA'),
          savedSelectedIndex: 7,
          reportContent: const ['שורת האב שאין לדווח עליה'],
          reportNote: noteContext,
        );
      });
      await waitForReportDialog(
        tester,
        dialog: find.byType(TabbedReportDialog),
      );
      await waitForBookReportMetadata(
        tester,
        dialog: find.byType(TabbedReportDialog),
      );
      expect(find.byType(TabbedReportDialog), findsOneWidget);
      final dialog = tester.widget<TabbedReportDialog>(
        find.byType(TabbedReportDialog),
      );
      expect(dialog.selectedText, selected);
      expect(dialog.selectionSource, noteContext);
      expect(
        dialog.correctionTemplate,
        isNull,
        reason: 'A note must never produce a correction for its parent row.',
      );
      final draft = dialog.draft!;
      expect(draft.target['selectedText'], selected);
      expect(draft.target['reportNote'], noteContext);
      expect(draft.target['contextText'], noteContext);
      expect(draft.target['lineNumber'], 8);
      await tester.enterText(
        find.byKey(const ValueKey('report-details-field')),
        'פירוט טעות בהערה',
      );
      await tester.pump();
      await reportIo(tester, draft.flush);
      final record = await reportIo(
        tester,
        () => ReportDraftStore.instance.read(draft.id),
      );
      expect(record!.payload['target'], draft.target);
      expect((record.payload['target'] as Map)['selectedText'], selected);

      await tester.ensureVisible(
        find.byKey(const ValueKey('book-report-save-draft')),
      );
      await tester.tap(find.byKey(const ValueKey('book-report-save-draft')));
      await finishReportDialog(
        tester,
        dialog: find.byType(TabbedReportDialog),
        reporting: reporting!,
      );
      final saved = await reportIo(
        tester,
        () => ReportDraftStore.instance.read(draft.id),
      );
      expect((saved!.payload['target'] as Map)['selectedText'], selected);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
