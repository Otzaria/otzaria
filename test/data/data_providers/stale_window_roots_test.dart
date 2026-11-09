import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dataRoot;

  setUp(() {
    dataRoot = Directory.systemTemp.createTempSync('window-roots');
    AppPaths.debugOverrideDataRootPath(dataRoot.path);
    pendingStaleRootsDeletion = null;
  });

  tearDown(() {
    AppPaths.debugOverrideDataRootPath(null);
    dataRoot.deleteSync(recursive: true);
  });

  Directory windows() => Directory(p.join(dataRoot.path, windowRootsDirName));

  test('stale roots are moved aside at once and deleted afterwards', () async {
    File(p.join(windows().path, 'slot-1', 'app_preferences.hive'))
      ..createSync(recursive: true)
      ..writeAsStringSync('stale');

    await deleteStaleWindowRoots();
    expect(windows().existsSync(), isFalse);

    // A window opened while the deletion runs keeps its new folder.
    final fresh = Directory(p.join(windows().path, 'slot-2'))
      ..createSync(recursive: true);
    await pendingStaleRootsDeletion;

    expect(fresh.existsSync(), isTrue);
    expect(dataRoot.listSync().map((e) => p.basename(e.path)), [
      windowRootsDirName,
    ]);
  });

  test('folders left by an unfinished deletion are removed too', () async {
    Directory(
      p.join(dataRoot.path, '$windowRootsDirName.stale-1'),
    ).createSync();

    await deleteStaleWindowRoots();
    await pendingStaleRootsDeletion;

    expect(dataRoot.listSync(), isEmpty);
  });

  test(
    'model-A leftovers go; the main window data stays (multiview upgrade)',
    () async {
      File p0(String rel) => File(p.join(dataRoot.path, rel));
      final mainBox = p0('app_preferences.hive')..writeAsStringSync('main');
      final userState = p0('user_state.db')..writeAsStringSync('sessions');
      for (final slot in [2, 3, 4]) {
        for (final name in [
          'app_preferences.hive',
          'app_preferences.lock',
          'pdfium-window-$slot.dll',
        ]) {
          p0(p.join(windowRootsDirName, 'slot-$slot', name))
            ..createSync(recursive: true)
            ..writeAsStringSync('stale');
        }
      }

      await deleteStaleWindowRoots();
      await pendingStaleRootsDeletion;

      expect(windows().existsSync(), isFalse);
      expect(mainBox.readAsStringSync(), 'main');
      expect(userState.readAsStringSync(), 'sessions');
      expect(
        dataRoot.listSync().map((e) => p.basename(e.path)).toSet(),
        {'app_preferences.hive', 'user_state.db'},
      );
    },
  );

  test(
    'a root still in use is left alone, without failing startup',
    () async {
      final dll = File(
        p.join(windows().path, 'slot-2', 'pdfium-window-2.dll'),
      )..createSync(recursive: true);
      final handle = dll.openSync(mode: FileMode.append);
      try {
        await deleteStaleWindowRoots();
        await pendingStaleRootsDeletion;
        expect(dll.existsSync(), isTrue);
      } finally {
        handle.closeSync();
      }
    },
    skip: Platform.isWindows ? false : 'רק ב-Windows קובץ פתוח חוסם שינוי שם',
  );

  test(
    'a reused PID stale folder does not prevent cleanup of the window root',
    () async {
      final staleWithReusedPid = Directory(
        p.join(dataRoot.path, '$windowRootsDirName.stale-$pid'),
      )..createSync(recursive: true);
      File(
        p.join(staleWithReusedPid.path, 'leftover'),
      ).writeAsStringSync('stale');
      final oldHiveFile =
          File(p.join(windows().path, 'slot-1', 'app_preferences.hive'))
            ..createSync(recursive: true)
            ..writeAsStringSync('old');

      await deleteStaleWindowRoots();
      expect(windows().existsSync(), isFalse);

      final fresh = Directory(p.join(windows().path, 'slot-2'))
        ..createSync(recursive: true);
      await pendingStaleRootsDeletion;

      expect(staleWithReusedPid.existsSync(), isFalse);
      expect(oldHiveFile.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(dataRoot.listSync().map((e) => p.basename(e.path)), [
        windowRootsDirName,
      ]);
    },
  );
}
