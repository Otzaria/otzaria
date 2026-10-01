import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/library_messages.dart';
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

    test('seforim.zdb חי עדיף על seforim.db.zst ישן באותה תיקייה', () async {
      final source = Directory(path.join(tmp.path, 'source'))..createSync();
      await writeFixtureZdb(
        path.join(source.path, DatabaseConstants.zdbDatabaseFileName),
        version: 7,
        marker: 'live-zdb',
      );
      File(
        path.join(source.path, DatabaseConstants.databaseArchiveFileName),
      ).writeAsStringSync('old archive');
      final bloc = EmptyLibraryBloc(
        extractCompressedDatabase: (archive, out, _) async =>
            fail('ה-zst הישן אינו נבחר'),
      );
      addTearDown(bloc.close);
      final done = finalState(bloc);
      bloc.add(
        ImportLibraryFolderRequested(
          sourceFolder: source.path,
          targetPath: library.path,
        ),
      );
      expect(await done, isA<EmptyLibraryDirectorySelected>());
      final active = DatabaseConstants.resolveLibraryDbPath(library.path);
      expect(readFixtureLibrary(active).marker, 'live-zdb');
    });

    test(
      'seforim.zdb שעודכן מאז עדיף על ארכיון seforim-schema6.zdb ישן',
      () async {
        final source = Directory(path.join(tmp.path, 'source'))..createSync();
        await writeFixtureZdb(
          path.join(source.path, 'seforim-schema6.zdb'),
          version: 2,
          marker: 'stale-archive',
        );
        await writeFixtureZdb(
          path.join(source.path, DatabaseConstants.zdbDatabaseFileName),
          version: 7,
          marker: 'live-zdb',
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
        final active = DatabaseConstants.resolveLibraryDbPath(library.path);
        expect(readFixtureLibrary(active), (version: 7, marker: 'live-zdb'));
      },
    );

    test('ארכיון חדש מ-seforim.zdb שבאותה תיקייה נבחר', () async {
      final source = Directory(path.join(tmp.path, 'source'))..createSync();
      await writeFixtureZdb(
        path.join(source.path, 'seforim-schema6.zdb'),
        version: 9,
        marker: 'new-archive',
      );
      await writeFixtureZdb(
        path.join(source.path, DatabaseConstants.zdbDatabaseFileName),
        version: 7,
        marker: 'old-live',
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
      final active = DatabaseConstants.resolveLibraryDbPath(library.path);
      expect(readFixtureLibrary(active).marker, 'new-archive');
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

  group('חבילת FULL של אנדרואיד בשני קבצים', () {
    /// zip שטוח של הקבצים הנלווים בלבד, כמו otzaria-android-full.zip.
    String sideFilesZip({String? nestedDbFrom}) {
      final archive = Archive()
        ..addFile(
          ArchiveFile.bytes(
            DatabaseConstants.externalCatalogDatabaseFileName,
            utf8.encode('catalog'),
          ),
        )
        ..addFile(ArchiveFile.bytes('lexical.db', utf8.encode('lexical')))
        ..addFile(ArchiveFile.bytes('lexical.db.version', utf8.encode('v1')))
        ..addFile(
          ArchiveFile.bytes(
            '${DatabaseConstants.talmudBavliFolderName}/a.pdf',
            utf8.encode('pdf'),
          ),
        );
      if (nestedDbFrom != null) {
        archive.addFile(
          ArchiveFile.bytes(
            'otzaria-android-full/library_db/otzaria-android-library.zdb',
            File(nestedDbFrom).readAsBytesSync(),
          ),
        );
      }
      final zip = path.join(tmp.path, 'otzaria-android-full.zip');
      File(zip).writeAsBytesSync(ZipEncoder().encode(archive));
      return zip;
    }

    Future<EmptyLibraryState> importArchive(String archive) async {
      final bloc = EmptyLibraryBloc(
        extractCompressedDatabase: (archivePath, output, _) async =>
            writeFixtureLibraryDb(
              output,
              version: 5,
              schemaVersion: 5,
              marker: 'from-zst',
            ),
      );
      addTearDown(bloc.close);
      final done = bloc.stream
          .firstWhere(
            (s) =>
                s is EmptyLibraryDirectorySelected ||
                s is EmptyLibraryAwaitingDatabase ||
                s is EmptyLibraryError,
          )
          .timeout(const Duration(seconds: 20));
      bloc.add(
        ImportLibraryArchiveRequested(
          archivePath: archive,
          targetPath: library.path,
        ),
      );
      return done;
    }

    String androidZdb() {
      final file = path.join(tmp.path, 'otzaria-android-library.zdb');
      File(releaseZdb).copySync(file);
      return file;
    }

    void expectSideFiles() {
      for (final name in [
        DatabaseConstants.externalCatalogDatabaseFileName,
        'lexical.db',
        'lexical.db.version',
        path.join(DatabaseConstants.talmudBavliFolderName, 'a.pdf'),
      ]) {
        expect(
          File(path.join(library.path, name)).existsSync(),
          isTrue,
          reason: name,
        );
      }
    }

    test('zip בלי DB: הקבצים נשמרים, הספרייה נקבעת, ונדרש קובץ ה-DB', () async {
      final state = await importArchive(sideFilesZip());

      expect(state, isA<EmptyLibraryAwaitingDatabase>());
      expect(
        (state as EmptyLibraryAwaitingDatabase).message,
        LibraryMessages.archiveImportedAwaitingDatabase,
      );
      expect(state.selectedPath, library.path);
      expectSideFiles();
      expect(
        Settings.getValue<String>(SettingsRepository.keyLibraryPath),
        library.path,
      );
      // בלי DB הספרייה אינה תקינה: לא ברזולבר ולא ב-libraryDbExistsIn.
      expect(await DatabaseConstants.libraryDbExistsIn(library.path), isFalse);
      expect(
        File(DatabaseConstants.resolveLibraryDbPath(library.path)).existsSync(),
        isFalse,
      );
    });

    test('zip ואז zdb בשם שרירותי: ספרייה שלמה באותו יעד', () async {
      expect(
        await importArchive(sideFilesZip()),
        isA<EmptyLibraryAwaitingDatabase>(),
      );
      final state = await importArchive(androidZdb());

      expect(state, isA<EmptyLibraryDirectorySelected>());
      expect(state.selectedPath, library.path);
      expectSideFiles();
      final active = DatabaseConstants.resolveLibraryDbPath(library.path);
      expect(path.basename(active), DatabaseConstants.zdbDatabaseFileName);
      expect(readFixtureLibrary(active).marker, 'release');
    });

    test('zdb ואז zip: הקבצים הנלווים מתווספים, וה-zdb נשאר', () async {
      expect(
        await importArchive(androidZdb()),
        isA<EmptyLibraryDirectorySelected>(),
      );
      final state = await importArchive(sideFilesZip());

      expect(state, isA<EmptyLibraryDirectorySelected>());
      expectSideFiles();
      final active = DatabaseConstants.resolveLibraryDbPath(library.path);
      expect(readFixtureLibrary(active).marker, 'release');
    });

    test('db.zst בשם שרירותי נפרס ל-seforim.db', () async {
      final zst = path.join(tmp.path, 'otzaria-android-library.db.zst');
      File(zst).writeAsStringSync('compressed');
      final state = await importArchive(zst);

      expect(state, isA<EmptyLibraryDirectorySelected>());
      final active = DatabaseConstants.resolveLibraryDbPath(library.path);
      expect(path.basename(active), DatabaseConstants.databaseFileName);
      expect(readFixtureLibrary(active).marker, 'from-zst');
    });

    test('מניפסט ליד zdb בשם שרירותי נבדק (ונדחה כשאינו תואם)', () async {
      final zdb = androidZdb();
      File('$zdb.manifest.json').writeAsStringSync(
        jsonEncode(fixtureManifestJsonFor(zdb, dbVersion: 99)),
      );
      final state = await importArchive(zdb);

      expect(state, isA<EmptyLibraryError>());
      expect(await DatabaseConstants.libraryDbExistsIn(library.path), isFalse);
    });

    test(
      'zip עם seforim.zdb וקטלוג otzar-HB_catalog.db.zst בשורש מתקבל',
      () async {
        final zip = path.join(tmp.path, 'bundle.zip');
        File(zip).writeAsBytesSync(
          ZipEncoder().encode(
            Archive()
              ..addFile(
                ArchiveFile.bytes(
                  DatabaseConstants.zdbDatabaseFileName,
                  File(releaseZdb).readAsBytesSync(),
                ),
              )
              ..addFile(
                ArchiveFile.bytes(
                  DatabaseConstants.externalCatalogArchiveFileName,
                  utf8.encode('catalog archive'),
                ),
              ),
          ),
        );
        final state = await importArchive(zip);

        expect(state, isA<EmptyLibraryDirectorySelected>());
        expect(
          readFixtureLibrary(
            DatabaseConstants.resolveLibraryDbPath(library.path),
          ).marker,
          'release',
        );
      },
    );

    test('ארכיון DB ראשי בשורש ה-zip נדחה גם הוא', () async {
      for (final name in ['otzaria-android-library.zdb', 'seforim.db.zst']) {
        expect(
          await EmptyLibraryBloc.hasNestedLibraryDatabase(
            (Directory(path.join(tmp.path, 'stage-$name'))..createSync()).path,
          ),
          isFalse,
        );
        final stage = path.join(tmp.path, 'stage-$name');
        File(path.join(stage, name)).writeAsStringSync('db');
        expect(
          await EmptyLibraryBloc.hasNestedLibraryDatabase(stage),
          isTrue,
          reason: name,
        );
      }
    });

    test('מבנה מקונן ישן נכשל בהודעה ברורה, בלי להתקין חלקית', () async {
      final state = await importArchive(sideFilesZip(nestedDbFrom: releaseZdb));

      expect(state, isA<EmptyLibraryError>());
      expect(
        state.errorMessage,
        contains(LibraryMessages.archiveNestedDatabaseUnsupported),
      );
      expect(library.listSync(), isEmpty);
      expect(
        Settings.getValue<String>(SettingsRepository.keyLibraryPath),
        isNot(library.path),
      );
    });
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

  test(
    'promoteStagedImport: seforim.db בלבד מה-ZIP מחליף ספריית zdb',
    () async {
      final zdb = LibraryZdbFiles.zdbPathIn(library.path);
      await writeFixtureZdb(zdb, version: 1, marker: 'old-zdb');
      growZdbOverlay(zdb);
      final staging = Directory(EmptyLibraryBloc.stagingDirFor(library.path))
        ..createSync();
      writeFixtureLibraryDb(
        path.join(staging.path, DatabaseConstants.databaseFileName),
        version: 9,
        schemaVersion: 5,
        marker: 'imported-plain',
      );

      await EmptyLibraryBloc.promoteStagedImport(staging.path, library.path);

      final active = DatabaseConstants.resolveLibraryDbPath(library.path);
      expect(path.basename(active), DatabaseConstants.databaseFileName);
      expect(readFixtureLibrary(active).marker, 'imported-plain');
      expect(File('$zdb-zovl').existsSync(), isFalse);
      // ניקוי העלייה מוחק seforim.db רק כשיש zdb — כאן אין.
      await cleanUpZdbLeftovers(library.path);
      expect(File(active).existsSync(), isTrue);
    },
  );

  test('copyLibraryDbFile: בסיס חדש מעל בסיס עם overlay נשאר קריא', () async {
    final internal = Directory(path.join(tmp.path, 'internal'))..createSync();
    final internalZdb = path.join(internal.path, 'seforim.zdb');
    await writeFixtureZdb(internalZdb, version: 1, marker: 'old-internal');
    growZdbOverlay(internalZdb);

    await EmptyLibraryBloc.copyLibraryDbFile(releaseZdb, internalZdb);

    expect(readFixtureLibrary(internalZdb).marker, 'release');
    expect(File('$internalZdb-zovl').existsSync(), isFalse);
    expect(File('$internalZdb.copying').existsSync(), isFalse);

    // מקור עם overlay: שניהם מועתקים, והתוכן הוא של המקור כולו.
    final source = path.join(tmp.path, 'with-overlay.zdb');
    await writeFixtureZdb(source, version: 4, marker: 'source-overlay');
    growZdbOverlay(source);
    await EmptyLibraryBloc.copyLibraryDbFile(source, internalZdb);
    expect(readFixtureLibrary(internalZdb).marker, 'source-overlay');
    expect(File('$internalZdb-zovl').existsSync(), isTrue);
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
