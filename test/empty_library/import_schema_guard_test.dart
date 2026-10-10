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
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../test_helpers/memory_cache_provider.dart';

void _writeDb(String dbPath, {required int schema, required String marker}) {
  final db = sqlite3.sqlite3.open(dbPath);
  try {
    db.execute('CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)');
    db.execute("INSERT INTO schema_meta VALUES ('db_version', '30')");
    db.execute("INSERT INTO schema_meta VALUES ('db_schema_version', ?)", [
      '$schema',
    ]);
    db.execute('CREATE TABLE marker (v TEXT)');
    db.execute('INSERT INTO marker VALUES (?)', [marker]);
  } finally {
    db.close();
  }
}

String _marker(String dbPath) {
  final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
  try {
    return db.select('SELECT v FROM marker').first['v'] as String;
  } finally {
    db.close();
  }
}

void main() {
  late Directory srcDir;
  late Directory targetDir;

  setUp(() async {
    srcDir = await Directory.systemTemp.createTemp('otzaria-schema-src-');
    targetDir = await Directory.systemTemp.createTemp('otzaria-schema-dst-');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
  });

  tearDown(() async {
    for (final d in [srcDir, targetDir]) {
      if (await d.exists()) await d.delete(recursive: true);
    }
  });

  Future<EmptyLibraryState> import() async {
    final bloc = EmptyLibraryBloc();
    addTearDown(bloc.close);
    final done = bloc.stream
        .where(
          (s) => s is EmptyLibraryDirectorySelected || s is EmptyLibraryError,
        )
        .first;
    bloc.add(
      ImportLibraryFolderRequested(
        assets: await scanRawLibraryAssets(DirectoryPackageFolder(srcDir.path)),
        targetPath: targetDir.path,
      ),
    );
    return done.timeout(const Duration(seconds: 20));
  }

  test(
    'ייבוא ידני של seforim.db בסכמה חדשה נדחה והספרייה הקיימת נשמרת',
    () async {
      const name = DatabaseConstants.databaseFileName;
      _writeDb(
        path.join(srcDir.path, name),
        schema: DatabaseConstants.readableDbSchemaVersion + 1,
        marker: 'new',
      );
      _writeDb(
        path.join(targetDir.path, name),
        schema: DatabaseConstants.readableDbSchemaVersion,
        marker: 'existing',
      );

      final state = await import();

      expect(state, isA<EmptyLibraryError>());
      expect(
        (state as EmptyLibraryError).errorMessage,
        contains('נדרש עדכון של התוכנה'),
      );
      expect(_marker(path.join(targetDir.path, name)), 'existing');
    },
  );

  test('ייבוא ידני של seforim.db בסכמה הנתמכת עובר', () async {
    const name = DatabaseConstants.databaseFileName;
    _writeDb(
      path.join(srcDir.path, name),
      schema: DatabaseConstants.readableDbSchemaVersion,
      marker: 'new',
    );

    expect(await import(), isA<EmptyLibraryDirectorySelected>());
    expect(_marker(path.join(targetDir.path, name)), 'new');
  });
}
