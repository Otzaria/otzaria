import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/sqlite/library_vfs.dart';
import 'package:otzaria/library_update/services/library_zdb_install.dart';
import 'package:otzaria/library_update/services/update_sqlite_setup.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import '../helpers/zdb_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String zdbPath;

  setUpAll(() => expect(ensureLibraryVfs(), isTrue));

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('library_zdb_install_test_');
    zdbPath = p.join(tmp.path, 'candidate.zdb');
    await writeFixtureZdb(zdbPath, version: 7);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('verifyZdbCandidate', () {
    test('מועמד תואם למניפסט עובר, בלי להשאיר -zlck', () async {
      await verifyZdbCandidate(
        zdbPath,
        manifest: fixtureManifestFor(zdbPath, dbVersion: 7),
      );
      expect(File('$zdbPath-zlck').existsSync(), isFalse);
    });

    final cases = <String, FullDbManifest Function(String)>{
      'size': (z) => fixtureManifestFor(z, dbVersion: 7, size: 1),
      'fileUuid': (z) =>
          fixtureManifestFor(z, dbVersion: 7, fileUuid: '0' * 32),
      'contentXxh64': (z) =>
          fixtureManifestFor(z, dbVersion: 7, contentXxh64: '0' * 16),
      'logicalSize': (z) => fixtureManifestFor(z, dbVersion: 7, logicalSize: 1),
      'formatMajor': (z) => fixtureManifestFor(z, dbVersion: 7, formatMajor: 2),
      'dbVersion': (z) => fixtureManifestFor(z, dbVersion: 8),
      'dbSchemaVersion': (z) =>
          fixtureManifestFor(z, dbVersion: 7, dbSchemaVersion: 5),
    };
    for (final entry in cases.entries) {
      test('אי-התאמה ב-${entry.key} נדחית', () async {
        await expectLater(
          verifyZdbCandidate(zdbPath, manifest: entry.value(zdbPath)),
          throwsA(isA<LibraryZdbVerificationException>()),
        );
      });
    }

    test('קובץ שאינו zdb נדחה ב-LibraryZdbException', () async {
      final bogus = p.join(tmp.path, 'bogus.zdb');
      File(bogus).writeAsBytesSync(List.filled(8192, 7));
      await expectLater(
        verifyZdbCandidate(bogus),
        throwsA(isA<LibraryZdbException>()),
      );
    });

    test('מסד בסכמה חדשה מהנתמכת נדחה גם בלי מניפסט', () async {
      final newer = p.join(tmp.path, 'newer.zdb');
      await writeFixtureZdb(
        newer,
        version: 7,
        schemaVersion: DatabaseConstants.readableDbSchemaVersion + 1,
      );
      await expectLater(
        verifyZdbCandidate(newer),
        throwsA(isA<LibraryZdbVerificationException>()),
      );
    });
  });

  group('checkZdbManifestSupported', () {
    test('major אחר או סכמה חדשה נדחים לפני ההורדה', () {
      expect(
        () => checkZdbManifestSupported(
          fixtureManifestFor(zdbPath, dbVersion: 7, formatMajor: 2),
        ),
        throwsA(isA<LibraryZdbVerificationException>()),
      );
      expect(
        () => checkZdbManifestSupported(
          fixtureManifestFor(
            zdbPath,
            dbVersion: 7,
            dbSchemaVersion: DatabaseConstants.readableDbSchemaVersion + 1,
          ),
        ),
        throwsA(isA<LibraryZdbVerificationException>()),
      );
      checkZdbManifestSupported(fixtureManifestFor(zdbPath, dbVersion: 7));
    });
  });

  test('zdbOverlayRatio: 0 בלי overlay, ויחס הגדלים איתו', () async {
    expect(await zdbOverlayRatio(p.join(tmp.path, 'missing.zdb')), isNull);
    expect(await zdbOverlayRatio(zdbPath), 0);
    growZdbOverlay(zdbPath);
    final expected =
        File('$zdbPath-zovl').lengthSync() / File(zdbPath).lengthSync();
    expect(await zdbOverlayRatio(zdbPath), expected);
    expect(expected, greaterThan(kZdbOverlayRebaseRatio));
  });

  group('libraryDbLogicalSizeOf', () {
    test('zdb — הגודל הלוגי כולל overlay; מסד רגיל — גודל הקובץ', () {
      growZdbOverlay(zdbPath);
      final logical = libraryDbLogicalSizeOf(zdbPath);
      expect(logical, readLibraryZdbHeader(zdbPath).logicalSize);
      expect(logical, greaterThan(File(zdbPath).lengthSync()));

      final plain = p.join(tmp.path, 'plain.db');
      writeFixtureLibraryDb(plain, version: 1);
      expect(libraryDbLogicalSizeOf(plain), File(plain).lengthSync());
    });

    test('ה-applier של העדכון מקבל את הפונקציה, גם ב-mobile', () {
      for (final ram in [null, 1024, 16384]) {
        final applier = LibraryUpdateSqliteSetup.applierForPhysicalRam(ram);
        expect(applier.logicalSizeOf, isNotNull);
        expect(
          applier.logicalSizeOf!(zdbPath),
          libraryDbLogicalSizeOf(zdbPath),
        );
      }
    });
  });

  group('cleanUpZdbLeftovers', () {
    late String libraryZdb;
    setUp(() async {
      libraryZdb = LibraryZdbFiles.zdbPathIn(tmp.path);
      await writeFixtureZdb(libraryZdb, version: 7);
    });

    test('מוחק .new, .install והורדה בלי resume, ושומר -zlck', () async {
      for (final path in [
        LibraryZdbFiles.compactionTempFor(libraryZdb),
        LibraryZdbFiles.installTempFor(libraryZdb),
        LibraryZdbFiles.downloadPathFor(libraryZdb),
        '$libraryZdb-zlck',
      ]) {
        File(path).writeAsStringSync('x');
      }
      await cleanUpZdbLeftovers(tmp.path);
      expect(
        File(LibraryZdbFiles.compactionTempFor(libraryZdb)).existsSync(),
        isFalse,
      );
      expect(
        File(LibraryZdbFiles.installTempFor(libraryZdb)).existsSync(),
        isFalse,
      );
      expect(
        File(LibraryZdbFiles.downloadPathFor(libraryZdb)).existsSync(),
        isFalse,
      );
      expect(File('$libraryZdb-zlck').existsSync(), isTrue);
      expect(File(libraryZdb).existsSync(), isTrue);
    });

    test('לוואי של הורדה, ייבוא ודחיסה נמחקים; -zlck של הבסיס נשמר', () async {
      final download = LibraryZdbFiles.downloadPathFor(libraryZdb);
      final import = LibraryZdbFiles.importTempFor(libraryZdb);
      File(download).writeAsStringSync('partial');
      File(PatchDownloader.resumeSidecarPath(download)).writeAsStringSync('t');
      final leftovers = [
        for (final suffix in LibraryZdbFiles.candidateSidecarSuffixes) ...[
          '$download$suffix',
          '$import$suffix',
        ],
        import,
      ];
      for (final path in [...leftovers, '$libraryZdb-zlck']) {
        File(path).writeAsStringSync('x');
      }
      await cleanUpZdbLeftovers(tmp.path);
      for (final path in leftovers) {
        expect(File(path).existsSync(), isFalse, reason: path);
      }
      expect(File(download).existsSync(), isTrue);
      expect(File('$libraryZdb-zlck').existsSync(), isTrue);
    });

    test('הורדה עם קובץ resume נשמרת להמשך', () async {
      final download = LibraryZdbFiles.downloadPathFor(libraryZdb);
      File(download).writeAsStringSync('partial');
      File(PatchDownloader.resumeSidecarPath(download)).writeAsStringSync('t');
      await cleanUpZdbLeftovers(tmp.path);
      expect(File(download).existsSync(), isTrue);
    });

    test('seforim.db הישן נמחק רק כשיש zdb תקין', () async {
      final legacy = LibraryZdbFiles.legacyPathIn(tmp.path);
      for (final suffix in LibraryZdbFiles.legacySuffixes) {
        File('$legacy$suffix').writeAsStringSync('legacy');
      }
      await cleanUpZdbLeftovers(tmp.path);
      for (final suffix in LibraryZdbFiles.legacySuffixes) {
        expect(File('$legacy$suffix').existsSync(), isFalse, reason: suffix);
      }

      File(legacy).writeAsStringSync('legacy');
      File(libraryZdb).writeAsBytesSync(List.filled(8192, 1));
      await cleanUpZdbLeftovers(tmp.path);
      expect(File(legacy).existsSync(), isTrue);
    });
  });
}
