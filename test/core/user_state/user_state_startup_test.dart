import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/main.dart' as app;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final database = UserStateDatabase.instance;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('otzaria_user_state_startup_');
    AppPaths.debugOverrideDataRootPath(tmp.path);
    database.overridePath('${tmp.path}/user_state.db');
    MultiWindowService.debugSupportedOverride = false;
    WindowRole.isSecondary = false;
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.close();
    await pendingStaleRootsDeletion;
    database.close();
    MultiWindowService.debugSupportedOverride = null;
    AppPaths.debugOverrideDataRootPath(null);
    tmp.deleteSync(recursive: true);
  });

  for (final hasSavedSession in [false, true]) {
    test(
      'אתחול משאיר Hive ישן ללא שינוי (${hasSavedSession ? 'מסד קיים' : 'מסד חדש'})',
      () async {
        final legacyFiles = <String, List<int>>{};
        for (final name in [
          'history',
          'bookmarks',
          'workspaces',
          'tabs',
          'error_reports_queue',
          'plugin_reports_queue',
        ]) {
          final box = await Hive.openBox<dynamic>(name);
          final key = switch (name) {
            'tabs' => 'key-tabs',
            'error_reports_queue' ||
            'plugin_reports_queue' => 'pending_reports',
            _ => 'legacy',
          };
          await box.put(key, [
            {'title': 'ישן'},
          ]);
          await box.close();
          final path = '${tmp.path}/$name.hive';
          legacyFiles[path] = await File(path).readAsBytes();
        }
        if (hasSavedSession) {
          await WindowSessionStore.instance.save(
            1,
            tabsJson: '[{"title":"נשמר"}]',
            currentIndex: 2,
          );
          await WindowSessionStore.instance.saveActiveWorkspace(1, 'w1');
        }
        database.close();

        await app.initHive();
        await app.initHive();

        expect(database.openDatabase, isNotNull);
        expect(database.openDatabase!.select('SELECT * FROM lists'), isEmpty);
        expect(
          database.openDatabase!.select('SELECT * FROM pending_reports'),
          isEmpty,
        );
        final session = await WindowSessionStore.instance.load(1);
        if (hasSavedSession) {
          expect(session!.tabsJson, '[{"title":"נשמר"}]');
          expect(session.currentIndex, 2);
          expect(session.activeWorkspaceId, 'w1');
        } else {
          expect(session, isNull);
        }
        for (final entry in legacyFiles.entries) {
          expect(await File(entry.key).readAsBytes(), entry.value);
          expect(File('${entry.key}.migrated').existsSync(), isFalse);
          expect(File('${entry.key}.failed').existsSync(), isFalse);
        }
      },
    );
  }
}
