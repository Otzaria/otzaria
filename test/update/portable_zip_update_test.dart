import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/update/differential/swap_plan.dart';
import 'package:otzaria/update/differential/update_engine.dart';
import 'package:path/path.dart' as p;

import '../../tool/updater/updater_swap.dart';

void main() {
  group('עדכון נייד ב-Windows מחבילת zip (issue #2009)', () {
    late Directory root;
    late Directory install;
    late Directory staging;
    late Directory work;

    void write(Directory dir, String path, String content) {
      final file = File(p.join(dir.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    String read(Directory dir, String path) =>
        File(p.join(dir.path, path)).readAsStringSync();

    setUp(() {
      root = Directory.systemTemp.createTempSync('otzaria_portable_2009_');
      install = Directory(p.join(root.path, 'Otzaria Portable'));
      staging = Directory(p.join(root.path, 'otzaria_update', 'otzaria'));
      work = Directory(p.join(root.path, 'otzaria_small_update'));

      write(install, 'otzaria.exe', 'old app');
      write(install, 'crashpad_handler.exe', 'old crashpad');
      write(install, 'data/app.so', 'old app.so');
      write(install, 'old_only.dll', 'old only');
      write(install, 'flutter_windows.dll', 'same engine');
      write(install, 'portable.marker', 'user marker');
      write(install, 'otzaria_data/notes.json', 'user notes');

      write(staging, 'otzaria.exe', 'new app');
      write(staging, 'crashpad_handler.exe', 'new crashpad');
      write(staging, 'otzaria_updater.exe', 'new updater');
      write(staging, 'zstd.exe', 'new zstd');
      write(staging, 'data/app.so', 'new app.so');
      write(staging, 'flutter_windows.dll', 'same engine');
      write(staging, 'portable.marker', '');
      write(staging, 'otzaria_data/notes.json', 'fresh empty data');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    Future<SwapPlan> buildPlan() => fullPackageSwapPlan(
      installRoot: install,
      stagingRoot: staging,
      backupRoot: Directory(p.join(work.path, kSwapBackupDirName)),
      platform: 'windows',
      architecture: 'x64',
      fromReleaseTag: '0.9.97',
      toReleaseTag: '0.9.98',
      relaunchExecutable: p.join(install.path, 'otzaria.exe'),
      waitForPid: 4242,
    );

    test('התוכנית כוללת רק קובצי אפליקציה שהשתנו, בלי נתוני משתמש '
        '(issue #2009)', () async {
      final plan = await buildPlan();

      expect(
        [for (final file in plan.files) file.path],
        [
          'crashpad_handler.exe',
          'data/app.so',
          'otzaria.exe',
          'otzaria_updater.exe',
          'zstd.exe',
        ],
      );
      expect(plan.removals, isEmpty);
      expect(plan.installRoot, install.absolute.path);
      expect(plan.stagingRoot, staging.absolute.path);
      expect(plan.relaunchExecutable, p.join(install.path, 'otzaria.exe'));
      expect(plan.waitForPid, 4242);
    });

    test('ההחלפה מעדכנת את התיקייה הניידת במקום ושומרת את נתוני המשתמש '
        '(issue #2009)', () async {
      final planFile = await writeSwapPlanFile(await buildPlan(), work);
      expect(
        p.equals(planFile.path, p.join(work.path, kSwapPlanFileName)),
        isTrue,
      );

      final result = applySwapPlan(
        SwapPlan.decode(planFile.readAsStringSync()),
      );

      expect(result.outcome, SwapOutcome.succeeded);
      expect(read(install, 'otzaria.exe'), 'new app');
      expect(read(install, 'crashpad_handler.exe'), 'new crashpad');
      expect(read(install, 'otzaria_updater.exe'), 'new updater');
      expect(read(install, 'data/app.so'), 'new app.so');
      expect(read(install, 'portable.marker'), 'user marker');
      expect(read(install, 'otzaria_data/notes.json'), 'user notes');
      expect(read(install, 'old_only.dll'), 'old only');
      expect(read(install, 'flutter_windows.dll'), 'same engine');
    });
  });
}
