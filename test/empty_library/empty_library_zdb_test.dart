import 'dart:convert';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/sqlite/library_vfs.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/library_update/services/library_zdb_install.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../helpers/memory_settings_cache.dart';
import '../helpers/zdb_fixture.dart';

/// התקנה ראשונה וייבוא של ספריית seforim.zdb.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory library;
  late String releaseZdb;

  setUpAll(() => expect(ensureLibraryVfs(), isTrue));

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('empty_library_zdb_test_');
    library = Directory(path.join(tmp.path, 'library'))..createSync();
    releaseZdb = path.join(tmp.path, 'seforim-schema6.zdb');
    await writeFixtureZdb(releaseZdb, version: 4, marker: 'release');
    await Settings.init(cacheProvider: MemorySettingsCache());
    await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<EmptyLibraryState> finalState(EmptyLibraryBloc bloc) => bloc.stream
      .firstWhere(
        (s) => s is EmptyLibraryDirectorySelected || s is EmptyLibraryError,
      )
      .timeout(const Duration(seconds: 20));

  group('parseLatestDatabaseAsset', () {
    test('zdb עם מניפסט עדיף על seforim.db.zst', () {
      final asset = EmptyLibraryBloc.parseLatestDatabaseAsset({
        'assets': [
          {'name': 'seforim.db.zst', 'browser_download_url': 'https://x/l'},
          {
            'name': 'seforim-schema6.zdb',
            'browser_download_url': 'https://x/z',
          },
          {
            'name': 'seforim-schema6.zdb.manifest.json',
            'browser_download_url': 'https://x/m',
          },
          {
            'name': 'seforim-schema99.zdb',
            'browser_download_url': 'https://x/n',
          },
        ],
      });
      expect(asset!.assetName, 'seforim-schema6.zdb');
      expect(asset.isZdb, isTrue);
      expect(asset.manifestUrl, 'https://x/m');
    });

    test('zdb בלי מניפסט אינו מוצע', () {
      final asset = EmptyLibraryBloc.parseLatestDatabaseAsset({
        'assets': [
          {
            'name': 'seforim-schema6.zdb',
            'browser_download_url': 'https://x/z',
          },
          {'name': 'seforim.db.zst', 'browser_download_url': 'https://x/l'},
        ],
      });
      expect(asset!.assetName, 'seforim.db.zst');
      expect(asset.manifestUrl, isNull);
    });
  });

  group('ImportLibraryFolderRequested', () {
    test('seforim-schema6.zdb עם מניפסט מחליף seforim.db קיים', () async {
      final source = Directory(path.join(tmp.path, 'source'))..createSync();
      final sourceZdb = path.join(source.path, 'seforim-schema6.zdb');
      File(releaseZdb).copySync(sourceZdb);
      File('$sourceZdb.manifest.json').writeAsStringSync(
        jsonEncode(fixtureManifestJsonFor(sourceZdb, dbVersion: 4)),
      );
      final legacy = path.join(
        library.path,
        DatabaseConstants.databaseFileName,
      );
      writeFixtureLibraryDb(legacy, version: 1, schemaVersion: 5);

      final bloc = EmptyLibraryBloc();
      addTearDown(bloc.close);
      final done = finalState(bloc);
      bloc.add(
        ImportLibraryFolderRequested(
          sourceFolder: source.path,
          targetPath: library.path,
        ),
      );
      expect(await done, isA<EmptyLibraryDirectorySelected>());

      final zdb = LibraryZdbFiles.zdbPathIn(library.path);
      expect(readFixtureLibrary(zdb).marker, 'release');
      expect(File(legacy).existsSync(), isFalse);
      expect(File(sourceZdb).existsSync(), isTrue);
    });

    test('seforim.zdb עם overlay מאוחד לבסיס אחד ביעד', () async {
      final source = Directory(path.join(tmp.path, 'source'))..createSync();
      final sourceZdb = path.join(
        source.path,
        DatabaseConstants.zdbDatabaseFileName,
      );
      await writeFixtureZdb(sourceZdb, version: 4, marker: 'with-overlay');
      growZdbOverlay(sourceZdb);
      final download = LibraryZdbFiles.downloadPathFor(
        LibraryZdbFiles.zdbPathIn(library.path),
      );
      File(download).writeAsStringSync('resumable');

      final bloc = EmptyLibraryBloc();
      addTearDown(bloc.close);
      final done = finalState(bloc);
      bloc.add(
        ImportLibraryFolderRequested(
          sourceFolder: source.path,
          targetPath: library.path,
        ),
      );
      expect(await done, isA<EmptyLibraryDirectorySelected>());

      final zdb = LibraryZdbFiles.zdbPathIn(library.path);
      expect(File('$zdb-zovl').existsSync(), isFalse);
      expect(readFixtureLibrary(zdb).marker, 'with-overlay');
      for (final leftover in ['.import', '.import-zovl', '.import.new']) {
        expect(File('$zdb$leftover').existsSync(), isFalse, reason: leftover);
      }
      // ההורדה של העדכון נשארה כפי שהייתה: הייבוא לא משתמש בשם שלה.
      expect(
        File(LibraryZdbFiles.downloadPathFor(zdb)).readAsStringSync(),
        'resumable',
      );
      expect(
        File('${LibraryZdbFiles.downloadPathFor(zdb)}-zovl').existsSync(),
        isFalse,
      );
    });

    test('zdb שאינו תואם למניפסט נדחה, והיעד לא נגע', () async {
      final source = Directory(path.join(tmp.path, 'source'))..createSync();
      final sourceZdb = path.join(source.path, 'seforim-schema6.zdb');
      File(releaseZdb).copySync(sourceZdb);
      File('$sourceZdb.manifest.json').writeAsStringSync(
        jsonEncode(fixtureManifestJsonFor(sourceZdb, dbVersion: 5)),
      );
      final legacy = path.join(
        library.path,
        DatabaseConstants.databaseFileName,
      );
      writeFixtureLibraryDb(legacy, version: 1, schemaVersion: 5);

      final bloc = EmptyLibraryBloc();
      addTearDown(bloc.close);
      final done = finalState(bloc);
      bloc.add(
        ImportLibraryFolderRequested(
          sourceFolder: source.path,
          targetPath: library.path,
        ),
      );
      expect(await done, isA<EmptyLibraryError>());
      expect(
        File(LibraryZdbFiles.zdbPathIn(library.path)).existsSync(),
        isFalse,
      );
      expect(File(legacy).existsSync(), isTrue);
    });
  });

  test('ImportLibraryArchiveRequested: קובץ seforim.zdb בודד מותקן', () async {
    final bundle = Directory(path.join(tmp.path, 'bundle'))..createSync();
    final bundleZdb = path.join(
      bundle.path,
      DatabaseConstants.zdbDatabaseFileName,
    );
    File(releaseZdb).copySync(bundleZdb);
    final legacy = path.join(library.path, DatabaseConstants.databaseFileName);
    writeFixtureLibraryDb(legacy, version: 1, schemaVersion: 5);

    final bloc = EmptyLibraryBloc();
    addTearDown(bloc.close);
    final done = finalState(bloc);
    bloc.add(
      ImportLibraryArchiveRequested(
        archivePath: bundleZdb,
        targetPath: library.path,
      ),
    );
    expect(await done, isA<EmptyLibraryDirectorySelected>());

    final zdb = LibraryZdbFiles.zdbPathIn(library.path);
    expect(readFixtureLibrary(zdb).marker, 'release');
    expect(File(legacy).existsSync(), isFalse);
    expect(File(LibraryZdbFiles.downloadPathFor(zdb)).existsSync(), isFalse);
    expect(
      Settings.getValue<String>(SettingsRepository.keyLibraryPath),
      library.path,
    );
  });

  test('ImportLibraryArchiveRequested: zdb פגום נדחה והיעד לא נגע', () async {
    final bogus = path.join(tmp.path, DatabaseConstants.zdbDatabaseFileName);
    File(bogus).writeAsBytesSync(List.filled(8192, 3));
    final legacy = path.join(library.path, DatabaseConstants.databaseFileName);
    writeFixtureLibraryDb(legacy, version: 1, schemaVersion: 5);

    final bloc = EmptyLibraryBloc();
    addTearDown(bloc.close);
    final done = finalState(bloc);
    bloc.add(
      ImportLibraryArchiveRequested(
        archivePath: bogus,
        targetPath: library.path,
      ),
    );
    expect(await done, isA<EmptyLibraryError>());
    expect(File(LibraryZdbFiles.zdbPathIn(library.path)).existsSync(), isFalse);
    expect(File(legacy).existsSync(), isTrue);
  });

  test('seforim.db שיובא לספריית zdb מחליף אותה ברזולבר', () async {
    final zdb = LibraryZdbFiles.zdbPathIn(library.path);
    await writeFixtureZdb(zdb, version: 4);
    growZdbOverlay(zdb);
    final source = Directory(path.join(tmp.path, 'source'))..createSync();
    writeFixtureLibraryDb(
      path.join(source.path, DatabaseConstants.databaseFileName),
      version: 9,
      schemaVersion: 5,
      marker: 'plain',
    );

    final bloc = EmptyLibraryBloc();
    addTearDown(bloc.close);
    final done = finalState(bloc);
    bloc.add(
      ImportLibraryFolderRequested(
        sourceFolder: source.path,
        targetPath: library.path,
      ),
    );
    expect(await done, isA<EmptyLibraryDirectorySelected>());
    expect(File(zdb).existsSync(), isFalse);
    expect(File('$zdb-zovl').existsSync(), isFalse);
    expect(
      DatabaseConstants.resolveLibraryDbPath(library.path),
      path.join(library.path, DatabaseConstants.databaseFileName),
    );
  });

  test('promoteStagedImport: zdb מה-ZIP מותקן ולא מוחלף ב-rename', () async {
    final zdb = LibraryZdbFiles.zdbPathIn(library.path);
    await writeFixtureZdb(zdb, version: 1, marker: 'old');
    growZdbOverlay(zdb);
    final staging = Directory(EmptyLibraryBloc.stagingDirFor(library.path))
      ..createSync();
    File(releaseZdb).copySync(
      path.join(staging.path, DatabaseConstants.zdbDatabaseFileName),
    );

    await EmptyLibraryBloc.promoteStagedImport(staging.path, library.path);

    expect(File('$zdb-zovl').existsSync(), isFalse);
    expect(readFixtureLibrary(zdb).marker, 'release');
  });

  test('בעלייה: גיבוי seforim.db יתום אינו מוחזר לספריית zdb', () async {
    final zdb = LibraryZdbFiles.zdbPathIn(library.path);
    await writeFixtureZdb(zdb, version: 4);
    final tempRoot = Directory(path.join(tmp.path, 'temp'))..createSync();
    EmptyLibraryBloc.tempRootOverride = tempRoot.path;
    addTearDown(() => EmptyLibraryBloc.tempRootOverride = null);
    final backup = Directory(EmptyLibraryBloc.dbBackupDirPath)..createSync();
    File(
      path.join(backup.path, DatabaseConstants.databaseFileName),
    ).writeAsStringSync('orphan');

    await EmptyLibraryBloc.recoverOrphanedDbBackup(library.path);

    expect(
      File(
        path.join(library.path, DatabaseConstants.databaseFileName),
      ).existsSync(),
      isFalse,
    );
    expect(backup.existsSync(), isFalse);
  });
}
