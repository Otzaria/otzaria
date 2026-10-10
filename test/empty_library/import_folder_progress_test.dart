import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/empty_library/services/library_package/library_source.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../test_helpers/memory_cache_provider.dart';

/// issue #1334 — בייבוא seforim.db לא-דחוס מסך ההתקדמות הציג 0% לכל אורך
/// ההעתקה: הקובץ הועתק ב-File.copy בלי דיווח ביניים.
void main() {
  test('ייבוא seforim.db רגיל מדווח התקדמות ביניים (issue #1334)', () async {
    final srcDir = await Directory.systemTemp.createTemp('otzaria-1334-src-');
    final targetDir = await Directory.systemTemp.createTemp(
      'otzaria-1334-dst-',
    );
    addTearDown(() async {
      for (final d in [srcDir, targetDir]) {
        if (await d.exists()) await d.delete(recursive: true);
      }
    });
    // גדול דיו לכמה צעדי דיווח (ההעתקה מדווחת כל כמה מגה-בייט).
    final db = File(path.join(srcDir.path, DatabaseConstants.databaseFileName));
    final raf = await db.open(mode: FileMode.write);
    await raf.truncate(24 << 20);
    await raf.close();

    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
    final bloc = EmptyLibraryBloc();
    addTearDown(bloc.close);

    final progressValues = <double>[];
    final sub = bloc.stream.listen((s) {
      if (s is EmptyLibraryExtracting) progressValues.add(s.progress);
    });
    addTearDown(sub.cancel);
    final selected = bloc.stream
        .where((s) => s is EmptyLibraryDirectorySelected)
        .first;

    bloc.add(
      ImportLibraryFolderRequested(
        assets: await scanRawLibraryAssets(DirectoryPackageFolder(srcDir.path)),
        targetPath: targetDir.path,
      ),
    );
    await selected.timeout(const Duration(seconds: 20));

    expect(
      progressValues.any((p) => p > 0 && p < 1),
      isTrue,
      reason: 'צפויה התקדמות ביניים, נמדד: $progressValues',
    );
    expect(progressValues.last, 1.0);
  });
}
