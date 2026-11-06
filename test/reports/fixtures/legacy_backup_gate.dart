import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/services/backup/backup_maintenance.dart';
import 'package:otzaria/settings/services/backup/backup_merge.dart';
import 'package:otzaria/settings/services/backup/backup_store.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:path/path.dart' as p;

// CI copies this probe into the pinned legacy client checkout. Its production
// backup writers, restorer and storage constants are never replaced by doubles.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late String fixturePath;
  late String legacyFixturePath;

  setUpAll(() {
    fixturePath = Platform.environment['REPORT_QA_BACKUP_FIXTURE']!;
    legacyFixturePath =
        Platform.environment['REPORT_QA_LEGACY_BACKUP_FIXTURE']!;
    expect(File(fixturePath).existsSync(), isTrue);
    expect(File(legacyFixturePath).existsSync(), isTrue);
    expect(
      AppReportService.pendingKind,
      'app_reports_queue/pending_reports',
      reason: 'This probe must run against the actual legacy client.',
    );
  });

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('qa_legacy_backup_gate_');
    Hive.init(temp.path);
    await Hive.openBox<dynamic>(HiveCache.keyName);
    RunnerWindowChannel.debugSupportedOverride = false;
    AppPaths.debugOverrideDataRootPath(temp.path);
    UserStateDatabase.instance.overridePath(p.join(temp.path, 'user_state.db'));
    await Settings.init(cacheProvider: HiveCache());
    await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, true);
    await Settings.setValue<String>(
      SettingsRepository.keyBackupPath,
      p.join(temp.path, 'backups'),
    );
    await Settings.setValue<String>(
      SettingsRepository.keyDatabasesPath,
      p.join(temp.path, 'databases'),
    );
  });

  tearDown(() async {
    await AppReportService.suspendAutomaticFlush();
    await PersonalNotesDatabase.instance.close();
    PluginSystemDatabase.instance.resetForTests();
    UserStateDatabase.instance.close();
    await Hive.close();
    RunnerWindowChannel.debugSupportedOverride = null;
    AppPaths.debugOverrideDataRootPath(null);
    await temp.delete(recursive: true);
  });

  test(
    'the legacy restorer rejects the actual new backup before changing SQLite',
    () async {
      final backup = jsonDecode(await File(fixturePath).readAsString()) as Map;
      expect(backup['version'], '3.0');
      const local = {
        'reportId': 'existing-local-report',
        'title': 'Keep this queue entry',
      };
      final store = PendingReportStore.instance;
      await store.add(AppReportService.pendingKind, local);
      final before = await store.listByKind(AppReportService.pendingKind);

      await expectLater(
        BackupService.restoreFromBackup(fixturePath),
        throwsA(
          predicate(
            (Object error) => error.toString().contains('גרסת גיבוי לא נתמכת'),
          ),
        ),
      );

      final after = await store.listByKind(AppReportService.pendingKind);
      expect(after, hasLength(1));
      expect(after.single.id, before.single.id);
      expect(after.single.payload, local);
      expect(
        await store.listByKind('app_reports_queue/pending_reports_v2'),
        isEmpty,
      );
    },
  );

  for (final rewrite in ['merge-as-newer', 'merge-as-older', 'convert']) {
    test('legacy $rewrite cannot place schema2 into its old send queue', () async {
      final original = await File(fixturePath).readAsString();
      final exported = jsonDecode(original) as Map<String, dynamic>;
      final originalQueue =
          (exported['reportQueues'] as Map)[AppReportService.queueBoxName]
              as Map;
      final originalCurrent = List<Object?>.from(
        originalQueue['pendingV2'] as List,
      );
      expect(originalCurrent, hasLength(1));
      expect((originalCurrent.single as Map)['schema'], 2);
      expect(
        ((originalCurrent.single as Map)['errorLog'] as String).length,
        250001,
      );

      late Map<String, dynamic> rewritten;
      if (rewrite == 'convert') {
        rewritten = exported;
        // The old converter resets the version even for an empty plugin list.
        rewritten['plugins'] = <Object?>[];
        await BackupMaintenance.convertManifestToRefs(
          rewritten,
          BackupStore.forBackupDir(temp.path),
        );
      } else {
        final stamp = DateTime.utc(2026, 11, 5);
        rewritten = BackupMerge.merge(
          rewrite == 'merge-as-older' ? exported : <String, dynamic>{},
          rewrite == 'merge-as-newer' ? exported : <String, dynamic>{},
          olderTimestamp: stamp.subtract(const Duration(days: 1)),
          newerTimestamp: stamp,
          now: stamp,
        );
      }
      expect(
        rewritten['version'],
        '2.0',
        reason:
            'This must exercise the actual old writer that resets the version.',
      );
      final rewrittenQueue =
          (rewritten['reportQueues'] as Map)[AppReportService.queueBoxName]
              as Map;
      expect(rewrittenQueue['pendingV2'], originalCurrent);
      final legacy = List<Object?>.from(rewrittenQueue['pending'] as List);
      expect(legacy, hasLength(2));
      expect(legacy.every((row) => ((row as Map)['schema'] ?? 1) == 1), isTrue);

      // Keep receiving settings local. The actual exported report queues remain
      // intact and are interpreted by the old production BackupService.
      rewritten['settings'] = <String, dynamic>{};
      rewritten['perBookSettings'] = <String, dynamic>{};
      rewritten.remove('userBooks');
      final rewrittenFile = File(p.join(temp.path, '$rewrite.json'));
      final serialized = jsonEncode(rewritten);
      await rewrittenFile.writeAsString(serialized);
      await BackupService.restoreFromBackup(rewrittenFile.path);

      final rows = await PendingReportStore.instance.listByKind(
        AppReportService.pendingKind,
      );
      expect(rows.map((row) => row.payload), unorderedEquals(legacy));
      expect(rows.any((row) => row.payload['schema'] == 2), isFalse);
      expect(
        await PendingReportStore.instance.listByKind(
          'app_reports_queue/pending_reports_v2',
        ),
        isEmpty,
      );
      expect(
        await rewrittenFile.readAsString(),
        serialized,
        reason:
            'The schema2 report remains intact in the backup for a supported reader.',
      );
      expect(await File(fixturePath).readAsString(), original);
    });
  }

  test(
    'the actual new legacy-only backup remains restorable by the old client',
    () async {
      final exported =
          jsonDecode(await File(legacyFixturePath).readAsString())
              as Map<String, dynamic>;
      expect(exported['version'], '2.0');
      final queue =
          (exported['reportQueues'] as Map)[AppReportService.queueBoxName]
              as Map;
      final legacy = List<Object?>.from(queue['pending'] as List);
      expect(legacy, hasLength(2));
      expect(queue['pendingV2'] ?? const [], isEmpty);
      exported['settings'] = <String, dynamic>{};
      exported['perBookSettings'] = <String, dynamic>{};
      exported.remove('userBooks');
      final receivingFile = File(p.join(temp.path, 'legacy-only.json'));
      await receivingFile.writeAsString(jsonEncode(exported));

      await BackupService.restoreFromBackup(receivingFile.path);

      final rows = await PendingReportStore.instance.listByKind(
        AppReportService.pendingKind,
      );
      expect(rows.map((row) => row.payload), unorderedEquals(legacy));
      expect(rows.every((row) => (row.payload['schema'] ?? 1) == 1), isTrue);
    },
  );
}
