import 'dart:convert';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(null);
    AppPaths.debugOverrideResolvedExecutable(null);
    AppPaths.debugOverrideDocumentsRootPath(null);
  });

  tearDown(() async {
    AppPaths.debugOverrideDataRootPath(null);
    AppPaths.debugOverrideResolvedExecutable(null);
    AppPaths.debugOverrideDocumentsRootPath(null);
    Settings.clearCache();
  });

  group('רישום נתיב הספרייה עבור ה-uninstaller (issue #1020)', () {
    test(
      'הנתיב הפעיל נכתב לקובץ, עם BOM שמאפשר קריאת עברית ב-Inno',
      () async {
        final dataRoot = await Directory.systemTemp.createTemp('otzaria_rec_');
        addTearDown(() async {
          if (await dataRoot.exists()) await dataRoot.delete(recursive: true);
        });
        AppPaths.debugOverrideDataRootPath(dataRoot.path);

        final library = p.join(dataRoot.path, 'ספרים');
        await Directory(library).create(recursive: true);
        await Settings.setValue(SettingsRepository.keyLibraryPath, library);

        await AppPaths.recordLibraryPathForUninstaller();

        final record = File(
          p.join(dataRoot.path, AppPaths.libraryPathRecordFileName),
        );
        expect(await record.exists(), isTrue);
        final bytes = await record.readAsBytes();
        expect(
          bytes.take(3),
          [0xEF, 0xBB, 0xBF],
          reason: 'בלי BOM, LoadStringsFromFile קורא ANSI ושובר נתיב בעברית',
        );
        expect(utf8.decode(bytes.skip(3).toList()), library);
      },
      skip: !Platform.isWindows,
    );
  });

  group('AppPaths backup paths', () {
    Future<({Directory dataRoot, Directory documents})> setUpRoots() async {
      final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
      final documents = await Directory.systemTemp.createTemp('otzaria_docs_');

      addTearDown(() async {
        if (await dataRoot.exists()) await dataRoot.delete(recursive: true);
        if (await documents.exists()) await documents.delete(recursive: true);
      });

      AppPaths.debugOverrideDataRootPath(dataRoot.path);
      AppPaths.debugOverrideDocumentsRootPath(documents.path);
      return (dataRoot: dataRoot, documents: documents);
    }

    test('ברירת המחדל היא תיקיית הגיבויים תחת מסמכי המשתמש', () async {
      final roots = await setUpRoots();

      expect(
        await AppPaths.getDefaultBackupPath(),
        p.join(roots.documents.path, 'אוצריא - גיבויים'),
      );
    });

    test('גיבויים קיימים בנתיב הישן מועברים לתיקיית המסמכים', () async {
      final roots = await setUpRoots();
      final legacyBackups = Directory(p.join(roots.dataRoot.path, 'backups'));
      await legacyBackups.create(recursive: true);
      await File(
        p.join(legacyBackups.path, 'otzaria_backup_20250101_120000.zip'),
      ).writeAsString('archive');
      // המחסן חייב לנוע יחד עם המניפסטים, אחרת הגיבויים מאבדים את ה-blobs.
      final legacyBlob = File(
        p.join(legacyBackups.path, 'store', 'objects', 'ab', 'abcd'),
      );
      await legacyBlob.parent.create(recursive: true);
      await legacyBlob.writeAsString('blob');

      final resolved = await AppPaths.getDefaultBackupPath();

      expect(resolved, p.join(roots.documents.path, 'אוצריא - גיבויים'));
      expect(
        await File(
          p.join(resolved, 'otzaria_backup_20250101_120000.zip'),
        ).readAsString(),
        'archive',
      );
      expect(
        await File(
          p.join(resolved, 'store', 'objects', 'ab', 'abcd'),
        ).readAsString(),
        'blob',
      );
      expect(await legacyBackups.exists(), isFalse);
    });

    test('כשל rename חוצה כוננים מעתיק דרך staging ומנקה את המקור', () async {
      final roots = await setUpRoots();
      final legacy = Directory(p.join(roots.dataRoot.path, 'backups'));
      final target = p.join(roots.documents.path, 'אוצריא - גיבויים');
      await legacy.create(recursive: true);
      await File(p.join(legacy.path, 'old.zip')).writeAsString('archive');

      final staleStaging = Directory('$target.migrating');
      await staleStaging.create(recursive: true);
      await File(p.join(staleStaging.path, 'partial')).writeAsString('partial');

      final resolved = await AppPaths.debugMigrateLegacyBackups(
        from: legacy.path,
        to: target,
        moveLegacyDirectory: (_, _) async {
          throw const FileSystemException('Cross-device link');
        },
      );

      expect(resolved, target);
      expect(await legacy.exists(), isFalse);
      expect(await staleStaging.exists(), isFalse);
      expect(await File(p.join(target, 'old.zip')).readAsString(), 'archive');
      expect(
        await File(
          p.join(target, '.otzaria-legacy-migration-complete'),
        ).exists(),
        isFalse,
      );
    });

    test('כשל בהעתקת fallback משאיר את המקור ומנקה staging חלקי', () async {
      final roots = await setUpRoots();
      final legacy = Directory(p.join(roots.dataRoot.path, 'backups'));
      final target = p.join(roots.documents.path, 'אוצריא - גיבויים');
      await legacy.create(recursive: true);
      final sourceFile = File(p.join(legacy.path, 'old.zip'));
      await sourceFile.writeAsString('archive');

      final resolved = await AppPaths.debugMigrateLegacyBackups(
        from: legacy.path,
        to: target,
        moveLegacyDirectory: (_, _) async {
          throw const FileSystemException('Cross-device link');
        },
        copyLegacyDirectory: (_, staging) async {
          await staging.create(recursive: true);
          await File(p.join(staging.path, 'partial')).writeAsString('partial');
          throw const FileSystemException('Disk full');
        },
      );

      expect(resolved, legacy.path);
      expect(await sourceFile.readAsString(), 'archive');
      expect(await Directory(target).exists(), isFalse);
      expect(await Directory('$target.migrating').exists(), isFalse);
    });

    test('כשל ניקוי אחרי פרסום היעד אינו מחזיר נתיב מקור חלקי', () async {
      final roots = await setUpRoots();
      final legacy = Directory(p.join(roots.dataRoot.path, 'backups'));
      final target = p.join(roots.documents.path, 'אוצריא - גיבויים');
      await legacy.create(recursive: true);
      await File(p.join(legacy.path, 'old.zip')).writeAsString('archive');

      final firstResolved = await AppPaths.debugMigrateLegacyBackups(
        from: legacy.path,
        to: target,
        moveLegacyDirectory: (_, _) async {
          throw const FileSystemException('Cross-device link');
        },
        deleteLegacyDirectory: (_) async {
          throw const FileSystemException('File is locked');
        },
      );

      expect(firstResolved, target);
      expect(await legacy.exists(), isTrue);
      expect(await File(p.join(target, 'old.zip')).readAsString(), 'archive');
      final marker = File(
        p.join(target, '.otzaria-legacy-migration-complete'),
      );
      expect(await marker.exists(), isTrue);

      // בהפעלה הבאה ה-marker מכריע שהיעד השלם הוא מקור האמת.
      final recovered = await AppPaths.debugMigrateLegacyBackups(
        from: legacy.path,
        to: target,
      );
      expect(recovered, target);
      expect(await legacy.exists(), isFalse);
      expect(await marker.exists(), isFalse);
    });

    test(
      'קישור סימבולי במקור מבטל את ההעברה ואינו נמחק',
      () async {
        final roots = await setUpRoots();
        final legacy = Directory(p.join(roots.dataRoot.path, 'backups'));
        final target = p.join(roots.documents.path, 'אוצריא - גיבויים');
        await legacy.create(recursive: true);
        final external = File(p.join(roots.dataRoot.path, 'external.zip'));
        await external.writeAsString('outside');
        final link = Link(p.join(legacy.path, 'linked.zip'));
        await link.create(external.path);

        final resolved = await AppPaths.debugMigrateLegacyBackups(
          from: legacy.path,
          to: target,
        );

        expect(resolved, legacy.path);
        expect(await link.exists(), isTrue);
        expect(await external.readAsString(), 'outside');
        expect(await Directory(target).exists(), isFalse);
      },
      skip: Platform.isWindows,
    );

    test('יעד שאינו ריק — נשארים בנתיב הישן ולא מזיזים דבר', () async {
      final roots = await setUpRoots();
      final legacyBackups = Directory(p.join(roots.dataRoot.path, 'backups'));
      await legacyBackups.create(recursive: true);
      await File(p.join(legacyBackups.path, 'old.zip')).writeAsString('old');

      final documentsBackups = Directory(
        p.join(roots.documents.path, 'אוצריא - גיבויים'),
      );
      await documentsBackups.create(recursive: true);
      await File(p.join(documentsBackups.path, 'new.zip')).writeAsString('new');

      // מיזוג שתי התיקיות אינו בתחום ההעברה; החזרת היעד הייתה מסתירה את
      // הגיבויים הישנים מהמסך.
      expect(await AppPaths.getDefaultBackupPath(), legacyBackups.path);
      expect(
        await File(p.join(legacyBackups.path, 'old.zip')).readAsString(),
        'old',
      );
      expect(
        await File(p.join(documentsBackups.path, 'new.zip')).readAsString(),
        'new',
      );
    });

    test('נתיב גיבוי מותאם אישית — ההעברה אינה רצה כלל', () async {
      // רגרסיה: העברת התיקייה הישנה כשהמשתמש בחר בה במפורש הייתה מרוקנת את
      // הנתיב ש-getBackupPath ממשיך להחזיר, וכל הגיבויים היו נעלמים מהמסך.
      final roots = await setUpRoots();
      final legacyBackups = Directory(p.join(roots.dataRoot.path, 'backups'));
      await legacyBackups.create(recursive: true);
      await File(p.join(legacyBackups.path, 'old.zip')).writeAsString('old');

      await Settings.setValue(
        SettingsRepository.keyBackupPath,
        legacyBackups.path,
      );

      expect(
        await AppPaths.getDefaultBackupPath(),
        p.join(roots.documents.path, 'אוצריא - גיבויים'),
      );
      expect(await AppPaths.getBackupPath(), legacyBackups.path);
      expect(
        await File(p.join(legacyBackups.path, 'old.zip')).readAsString(),
        'old',
      );
    });

    test('תיקייה ישנה ריקה לא מונעת מעבר למסמכי המשתמש', () async {
      final roots = await setUpRoots();
      await Directory(p.join(roots.dataRoot.path, 'backups')).create();

      expect(
        await AppPaths.getDefaultBackupPath(),
        p.join(roots.documents.path, 'אוצריא - גיבויים'),
      );
    });

    test('ללא תיקיית מסמכים — נפילה חזרה לתיקיית הנתונים', () async {
      final roots = await setUpRoots();
      AppPaths.debugOverrideDocumentsRootPath('');

      expect(
        await AppPaths.getDefaultBackupPath(),
        p.join(roots.dataRoot.path, 'backups'),
      );
    });

    test('מצב נייד — הגיבויים נשארים תחת תיקיית הנתונים', () async {
      final exeRoot = await Directory.systemTemp.createTemp('otzaria_exe_');
      final documents = await Directory.systemTemp.createTemp('otzaria_docs_');

      addTearDown(() async {
        if (await exeRoot.exists()) await exeRoot.delete(recursive: true);
        if (await documents.exists()) await documents.delete(recursive: true);
      });

      final exePath = p.join(exeRoot.path, 'otzaria.exe');
      await File(exePath).writeAsString('fake exe');
      await File(
        p.join(exeRoot.path, AppPaths.portableMarkerFileName),
      ).writeAsString('');

      AppPaths.debugOverrideResolvedExecutable(exePath);
      AppPaths.debugOverrideDocumentsRootPath(documents.path);

      expect(
        await AppPaths.getDefaultBackupPath(),
        p.join(exeRoot.path, 'otzaria_data', 'backups'),
      );
    });

    test('נתיב מותאם אישית בהגדרות גובר על ברירת המחדל', () async {
      final roots = await setUpRoots();
      final custom = p.join(roots.documents.path, 'custom_backups');
      await Settings.setValue(SettingsRepository.keyBackupPath, custom);

      expect(await AppPaths.getBackupPath(), custom);
    });
  });

  group('AppPaths index paths', () {
    test('getIndexPath מעדיף legacy index תחת data root אם הוא קיים', () async {
      final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
      final libraryRoot = await Directory.systemTemp.createTemp(
        'otzaria_library_',
      );
      final legacyIndex = Directory(p.join(dataRoot.path, 'index'));
      await legacyIndex.create(recursive: true);

      addTearDown(() async {
        if (await dataRoot.exists()) {
          await dataRoot.delete(recursive: true);
        }
        if (await libraryRoot.exists()) {
          await libraryRoot.delete(recursive: true);
        }
      });

      AppPaths.debugOverrideDataRootPath(dataRoot.path);
      await Settings.setValue(
        SettingsRepository.keyLibraryPath,
        p.join(libraryRoot.path, 'books'),
      );

      expect(await AppPaths.getIndexPath(), legacyIndex.path);
    });

    test('getIndexPath מעדיף אינדקס מוכן הצמוד לספרייה', () async {
      final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
      final libraryRoot = await Directory.systemTemp.createTemp(
        'otzaria_library_',
      );
      final legacyIndex = Directory(p.join(dataRoot.path, 'index'));
      final adjacentIndex = Directory(p.join(libraryRoot.path, 'index'));
      await legacyIndex.create(recursive: true);
      await adjacentIndex.create(recursive: true);
      await File(
        p.join(adjacentIndex.path, AppPaths.prebuiltIndexMarkerFileName),
      ).writeAsString('');

      addTearDown(() async {
        if (await dataRoot.exists()) {
          await dataRoot.delete(recursive: true);
        }
        if (await libraryRoot.exists()) {
          await libraryRoot.delete(recursive: true);
        }
      });

      AppPaths.debugOverrideDataRootPath(dataRoot.path);
      await Settings.setValue(
        SettingsRepository.keyLibraryPath,
        p.join(libraryRoot.path, 'books'),
      );

      expect(await AppPaths.getIndexPath(), adjacentIndex.path);
    });

    test('getDatabasesPath מעדיף נתיב שמור מפורש', () async {
      final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
      final databasesRoot = await Directory.systemTemp.createTemp(
        'otzaria_databases_',
      );

      addTearDown(() async {
        if (await dataRoot.exists()) {
          await dataRoot.delete(recursive: true);
        }
        if (await databasesRoot.exists()) {
          await databasesRoot.delete(recursive: true);
        }
      });

      AppPaths.debugOverrideDataRootPath(dataRoot.path);
      await Settings.setValue(
        SettingsRepository.keyDatabasesPath,
        databasesRoot.path,
      );

      expect(await AppPaths.getDatabasesPath(), databasesRoot.path);
    });

    test(
      'getDatabasesPath מעדיף legacy databases תחת data root אם הוא קיים',
      () async {
        final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
        final libraryRoot = await Directory.systemTemp.createTemp(
          'otzaria_library_',
        );
        final legacyDatabases = Directory(p.join(dataRoot.path, 'databases'));
        await legacyDatabases.create(recursive: true);

        addTearDown(() async {
          if (await dataRoot.exists()) {
            await dataRoot.delete(recursive: true);
          }
          if (await libraryRoot.exists()) {
            await libraryRoot.delete(recursive: true);
          }
        });

        AppPaths.debugOverrideDataRootPath(dataRoot.path);
        await Settings.setValue(
          SettingsRepository.keyLibraryPath,
          p.join(libraryRoot.path, 'books'),
        );

        expect(await AppPaths.getDatabasesPath(), legacyDatabases.path);
      },
    );

    test('getDatabasesPath ממקם התקנה חדשה ליד תיקיית הספרייה', () async {
      final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
      final libraryRoot = await Directory.systemTemp.createTemp(
        'otzaria_library_',
      );

      addTearDown(() async {
        if (await dataRoot.exists()) {
          await dataRoot.delete(recursive: true);
        }
        if (await libraryRoot.exists()) {
          await libraryRoot.delete(recursive: true);
        }
      });

      AppPaths.debugOverrideDataRootPath(dataRoot.path);
      await Settings.setValue(
        SettingsRepository.keyLibraryPath,
        p.join(libraryRoot.path, 'books'),
      );

      expect(
        await AppPaths.getDatabasesPath(),
        p.join(libraryRoot.path, 'databases'),
      );
    });

    test('AppPaths bundled library — Linux mzhה bundle אם יש marker', () async {
      if (!Platform.isLinux) {
        return;
      }
      final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
      final bundleRoot = await Directory.systemTemp.createTemp(
        'otzaria_bundle_',
      );

      addTearDown(() async {
        AppPaths.debugOverrideResolvedExecutable(null);
        if (await dataRoot.exists()) {
          await dataRoot.delete(recursive: true);
        }
        if (await bundleRoot.exists()) {
          await bundleRoot.delete(recursive: true);
        }
      });

      // מבנה Linux FULL bundle:
      //   bundle/app/otzaria
      //   bundle/אוצריא/seforim.db
      //   bundle/אוצריא/.otzaria_bundled_library
      final appDir = Directory(p.join(bundleRoot.path, 'app'));
      await appDir.create(recursive: true);
      final exePath = p.join(appDir.path, 'otzaria');
      await File(exePath).writeAsString('fake elf');

      final libDir = Directory(p.join(bundleRoot.path, 'אוצריא'));
      await libDir.create(recursive: true);
      await File(p.join(libDir.path, 'seforim.db')).writeAsString('db');
      await File(
        p.join(libDir.path, '.otzaria_bundled_library'),
      ).writeAsString('');

      AppPaths.debugOverrideDataRootPath(dataRoot.path);
      AppPaths.debugOverrideResolvedExecutable(exePath);

      expect(await AppPaths.getDefaultLibraryPath(), libDir.path);
    });

    test('AppPaths bundled library — Linux לא מזהה ללא קובץ marker', () async {
      if (!Platform.isLinux) {
        return;
      }
      final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
      final bundleRoot = await Directory.systemTemp.createTemp(
        'otzaria_bundle_',
      );

      addTearDown(() async {
        AppPaths.debugOverrideResolvedExecutable(null);
        if (await dataRoot.exists()) {
          await dataRoot.delete(recursive: true);
        }
        if (await bundleRoot.exists()) {
          await bundleRoot.delete(recursive: true);
        }
      });

      final appDir = Directory(p.join(bundleRoot.path, 'app'));
      await appDir.create(recursive: true);
      final exePath = p.join(appDir.path, 'otzaria');
      await File(exePath).writeAsString('fake elf');

      final libDir = Directory(p.join(bundleRoot.path, 'אוצריא'));
      await libDir.create(recursive: true);
      await File(p.join(libDir.path, 'seforim.db')).writeAsString('db');
      // אין marker — לא אמור להיתפס כ-bundle.

      AppPaths.debugOverrideDataRootPath(dataRoot.path);
      AppPaths.debugOverrideResolvedExecutable(exePath);

      expect(
        await AppPaths.getDefaultLibraryPath(),
        p.join(dataRoot.path, 'books'),
      );
    });

    test('AppPaths bundled library — macOS מזהה bundle אם יש marker', () async {
      if (!Platform.isMacOS) {
        return;
      }
      final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
      final bundleRoot = await Directory.systemTemp.createTemp(
        'otzaria_bundle_',
      );

      addTearDown(() async {
        AppPaths.debugOverrideResolvedExecutable(null);
        if (await dataRoot.exists()) {
          await dataRoot.delete(recursive: true);
        }
        if (await bundleRoot.exists()) {
          await bundleRoot.delete(recursive: true);
        }
      });

      // מבנה macOS FULL bundle:
      //   bundle/אוצריא.app/Contents/MacOS/אוצריא
      //   bundle/אוצריא/seforim.db
      //   bundle/אוצריא/.otzaria_bundled_library
      final macOsDir = Directory(
        p.join(bundleRoot.path, 'אוצריא.app', 'Contents', 'MacOS'),
      );
      await macOsDir.create(recursive: true);
      final exePath = p.join(macOsDir.path, 'אוצריא');
      await File(exePath).writeAsString('fake mach-o');

      final libDir = Directory(p.join(bundleRoot.path, 'אוצריא'));
      await libDir.create(recursive: true);
      await File(p.join(libDir.path, 'seforim.db')).writeAsString('db');
      await File(
        p.join(libDir.path, '.otzaria_bundled_library'),
      ).writeAsString('');

      AppPaths.debugOverrideDataRootPath(dataRoot.path);
      AppPaths.debugOverrideResolvedExecutable(exePath);

      expect(await AppPaths.getDefaultLibraryPath(), libDir.path);
    });

    test(
      'AppPaths bundled library — bundle מכבד בחירה ידנית תקפה של המשתמש',
      () async {
        if (!Platform.isLinux && !Platform.isMacOS) {
          return;
        }
        final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
        final bundleRoot = await Directory.systemTemp.createTemp(
          'otzaria_bundle_',
        );
        // תיקייה ידנית של המשתמש: יש בה DB אמיתי אבל אין marker של FULL bundle.
        final userLibrary = await Directory.systemTemp.createTemp(
          'otzaria_userlib_',
        );

        addTearDown(() async {
          AppPaths.debugOverrideResolvedExecutable(null);
          if (await dataRoot.exists()) {
            await dataRoot.delete(recursive: true);
          }
          if (await bundleRoot.exists()) {
            await bundleRoot.delete(recursive: true);
          }
          if (await userLibrary.exists()) {
            await userLibrary.delete(recursive: true);
          }
        });

        // bundle תקף ליד ה-executable.
        String exePath;
        if (Platform.isLinux) {
          final appDir = Directory(p.join(bundleRoot.path, 'app'));
          await appDir.create(recursive: true);
          exePath = p.join(appDir.path, 'otzaria');
        } else {
          final macOsDir = Directory(
            p.join(bundleRoot.path, 'אוצריא.app', 'Contents', 'MacOS'),
          );
          await macOsDir.create(recursive: true);
          exePath = p.join(macOsDir.path, 'אוצריא');
        }
        await File(exePath).writeAsString('fake exe');

        final libDir = Directory(p.join(bundleRoot.path, 'אוצריא'));
        await libDir.create(recursive: true);
        await File(p.join(libDir.path, 'seforim.db')).writeAsString('db');
        await File(
          p.join(libDir.path, '.otzaria_bundled_library'),
        ).writeAsString('');

        // בחירה ידנית של המשתמש: תיקייה אחרת תקפה (יש בה DB, אין marker).
        await File(p.join(userLibrary.path, 'seforim.db')).writeAsString('db');

        AppPaths.debugOverrideDataRootPath(dataRoot.path);
        AppPaths.debugOverrideResolvedExecutable(exePath);
        await Settings.setValue(
          SettingsRepository.keyLibraryPath,
          userLibrary.path,
        );

        // הבחירה הידנית מנצחת — ה-bundle לא דורס אותה.
        expect(await AppPaths.getLibraryPath(), userLibrary.path);
        expect(
          Settings.getValue<String>(SettingsRepository.keyLibraryPath),
          userLibrary.path,
        );
      },
    );

    test(
      'AppPaths bundled library — bundle מכבד בחירה ידנית עם keyLibraryFolderName',
      () async {
        // תצורת משתמש חוקית: keyLibraryPath מצביע על תיקיית בסיס,
        // ו-keyLibraryFolderName מצביע על תת-תיקייה שמכילה את ה-DB.
        // ראה DatabaseConstants._buildDbPath.
        if (!Platform.isLinux && !Platform.isMacOS) {
          return;
        }
        final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
        final bundleRoot = await Directory.systemTemp.createTemp(
          'otzaria_bundle_',
        );
        final userBase = await Directory.systemTemp.createTemp('otzaria_base_');

        addTearDown(() async {
          AppPaths.debugOverrideResolvedExecutable(null);
          if (await dataRoot.exists()) {
            await dataRoot.delete(recursive: true);
          }
          if (await bundleRoot.exists()) {
            await bundleRoot.delete(recursive: true);
          }
          if (await userBase.exists()) {
            await userBase.delete(recursive: true);
          }
        });

        // bundle תקף ליד ה-executable.
        String exePath;
        if (Platform.isLinux) {
          final appDir = Directory(p.join(bundleRoot.path, 'app'));
          await appDir.create(recursive: true);
          exePath = p.join(appDir.path, 'otzaria');
        } else {
          final macOsDir = Directory(
            p.join(bundleRoot.path, 'אוצריא.app', 'Contents', 'MacOS'),
          );
          await macOsDir.create(recursive: true);
          exePath = p.join(macOsDir.path, 'אוצריא');
        }
        await File(exePath).writeAsString('fake exe');

        final libDir = Directory(p.join(bundleRoot.path, 'אוצריא'));
        await libDir.create(recursive: true);
        await File(p.join(libDir.path, 'seforim.db')).writeAsString('db');
        await File(
          p.join(libDir.path, '.otzaria_bundled_library'),
        ).writeAsString('');

        // הבחירה הידנית: DB יושב בתת-תיקייה Otzaria תחת ה-base.
        final userDbDir = Directory(p.join(userBase.path, 'Otzaria'));
        await userDbDir.create(recursive: true);
        await File(p.join(userDbDir.path, 'seforim.db')).writeAsString('db');

        AppPaths.debugOverrideDataRootPath(dataRoot.path);
        AppPaths.debugOverrideResolvedExecutable(exePath);
        await Settings.setValue(
          SettingsRepository.keyLibraryPath,
          userBase.path,
        );
        await Settings.setValue(
          SettingsRepository.keyLibraryFolderName,
          'Otzaria',
        );

        // הבחירה הידנית עם תת-תיקייה חוקית מנצחת — ה-bundle לא דורס.
        expect(await AppPaths.getLibraryPath(), userBase.path);
        expect(
          Settings.getValue<String>(SettingsRepository.keyLibraryPath),
          userBase.path,
        );
        expect(
          Settings.getValue<String>(SettingsRepository.keyLibraryFolderName),
          'Otzaria',
        );
      },
    );

    test(
      'AppPaths bundled library — מאפס keyLibraryFolderName stale גם כש-keyLibraryPath כבר שווה ל-bundle',
      () async {
        // תרחיש: בריצה קודמת נשמר keyLibraryPath = bundle path, אבל
        // keyLibraryFolderName נשאר מערך ישן (למשל 'Otzaria') בעקבות migration
        // או baug. בלי איפוס מפורש, DatabaseConstants יחשב bundle/Otzaria/seforim.db
        // וייכשל. הקוד חייב לאפס את ה-folderName גם כש-currentPath == bundled.
        if (!Platform.isLinux && !Platform.isMacOS) {
          return;
        }
        final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
        final bundleRoot = await Directory.systemTemp.createTemp(
          'otzaria_bundle_',
        );

        addTearDown(() async {
          AppPaths.debugOverrideResolvedExecutable(null);
          if (await dataRoot.exists()) {
            await dataRoot.delete(recursive: true);
          }
          if (await bundleRoot.exists()) {
            await bundleRoot.delete(recursive: true);
          }
        });

        String exePath;
        if (Platform.isLinux) {
          final appDir = Directory(p.join(bundleRoot.path, 'app'));
          await appDir.create(recursive: true);
          exePath = p.join(appDir.path, 'otzaria');
        } else {
          final macOsDir = Directory(
            p.join(bundleRoot.path, 'אוצריא.app', 'Contents', 'MacOS'),
          );
          await macOsDir.create(recursive: true);
          exePath = p.join(macOsDir.path, 'אוצריא');
        }
        await File(exePath).writeAsString('fake exe');

        final libDir = Directory(p.join(bundleRoot.path, 'אוצריא'));
        await libDir.create(recursive: true);
        await File(p.join(libDir.path, 'seforim.db')).writeAsString('db');
        await File(
          p.join(libDir.path, '.otzaria_bundled_library'),
        ).writeAsString('');

        AppPaths.debugOverrideDataRootPath(dataRoot.path);
        AppPaths.debugOverrideResolvedExecutable(exePath);
        // נתיב כבר שמור משווה ל-bundle, אבל folderName stale.
        await Settings.setValue(SettingsRepository.keyLibraryPath, libDir.path);
        await Settings.setValue(
          SettingsRepository.keyLibraryFolderName,
          'Otzaria',
        );

        expect(await AppPaths.getLibraryPath(), libDir.path);
        // ה-folderName אופס אוטומטית — קריאה ישירה ל-Settings תחזיר נתיב נכון.
        expect(
          Settings.getValue<String>(SettingsRepository.keyLibraryFolderName),
          '',
        );
      },
    );

    test(
      'AppPaths bundled library — bundle דורס keyLibraryPath שמור שאינו תקף (stale)',
      () async {
        if (!Platform.isLinux && !Platform.isMacOS) {
          return;
        }
        final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
        final bundleRoot = await Directory.systemTemp.createTemp(
          'otzaria_bundle_',
        );
        final staleBundle = await Directory.systemTemp.createTemp(
          'otzaria_stalebundle_',
        );

        addTearDown(() async {
          AppPaths.debugOverrideResolvedExecutable(null);
          if (await dataRoot.exists()) {
            await dataRoot.delete(recursive: true);
          }
          if (await bundleRoot.exists()) {
            await bundleRoot.delete(recursive: true);
          }
          if (await staleBundle.exists()) {
            await staleBundle.delete(recursive: true);
          }
        });

        // הכן bundle תקף ליד ה-executable.
        String exePath;
        if (Platform.isLinux) {
          final appDir = Directory(p.join(bundleRoot.path, 'app'));
          await appDir.create(recursive: true);
          exePath = p.join(appDir.path, 'otzaria');
        } else {
          final macOsDir = Directory(
            p.join(bundleRoot.path, 'אוצריא.app', 'Contents', 'MacOS'),
          );
          await macOsDir.create(recursive: true);
          exePath = p.join(macOsDir.path, 'אוצריא');
        }
        await File(exePath).writeAsString('fake exe');

        final libDir = Directory(p.join(bundleRoot.path, 'אוצריא'));
        await libDir.create(recursive: true);
        await File(p.join(libDir.path, 'seforim.db')).writeAsString('db');
        await File(
          p.join(libDir.path, '.otzaria_bundled_library'),
        ).writeAsString('');

        AppPaths.debugOverrideDataRootPath(dataRoot.path);
        AppPaths.debugOverrideResolvedExecutable(exePath);
        // נתיב ישן שנשמר מ-bundle אחר — אמור להידרס לטובת ה-bundle הנוכחי.
        await Settings.setValue(
          SettingsRepository.keyLibraryPath,
          staleBundle.path,
        );
        await Settings.setValue(
          SettingsRepository.keyLibraryFolderName,
          'something-else',
        );

        expect(await AppPaths.getLibraryPath(), libDir.path);
        // ה-settings התעדכן כדי ש-DatabaseConstants.getDatabasePath יקבל
        // את הנתיב הנכון בקריאה ישירה.
        expect(
          Settings.getValue<String>(SettingsRepository.keyLibraryPath),
          libDir.path,
        );
        expect(
          Settings.getValue<String>(SettingsRepository.keyLibraryFolderName),
          '',
        );
      },
    );

    test(
      'AppPaths bundled library — keyLibraryPath שמור מנצח כש-executable אינו מ-bundle',
      () async {
        // כשאין marker ליד ה-executable (הפעלה רגילה, לא מ-FULL bundle),
        // הבחירה הידנית של המשתמש ב-settings מנצחת תמיד.
        final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
        final userLibrary = await Directory.systemTemp.createTemp(
          'otzaria_userlib_',
        );
        final standaloneExeDir = await Directory.systemTemp.createTemp(
          'otzaria_standalone_',
        );

        addTearDown(() async {
          AppPaths.debugOverrideResolvedExecutable(null);
          if (await dataRoot.exists()) {
            await dataRoot.delete(recursive: true);
          }
          if (await userLibrary.exists()) {
            await userLibrary.delete(recursive: true);
          }
          if (await standaloneExeDir.exists()) {
            await standaloneExeDir.delete(recursive: true);
          }
        });

        // executable שרץ לבד, ללא תיקיית "אוצריא" ליד עם marker.
        final exePath = p.join(standaloneExeDir.path, 'otzaria');
        await File(exePath).writeAsString('fake exe');

        AppPaths.debugOverrideDataRootPath(dataRoot.path);
        AppPaths.debugOverrideResolvedExecutable(exePath);
        await Settings.setValue(
          SettingsRepository.keyLibraryPath,
          userLibrary.path,
        );

        expect(await AppPaths.getLibraryPath(), userLibrary.path);
      },
    );

    test(
      'AppPaths bundled library — Windows לא רץ גם אם marker קיים',
      () async {
        if (!Platform.isWindows) {
          return;
        }
        final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
        final bundleRoot = await Directory.systemTemp.createTemp(
          'otzaria_bundle_',
        );

        addTearDown(() async {
          AppPaths.debugOverrideResolvedExecutable(null);
          if (await dataRoot.exists()) {
            await dataRoot.delete(recursive: true);
          }
          if (await bundleRoot.exists()) {
            await bundleRoot.delete(recursive: true);
          }
        });

        // מבנה bundle "אילו" היה Linux:
        final exePath = p.join(bundleRoot.path, 'app', 'otzaria.exe');
        await Directory(p.dirname(exePath)).create(recursive: true);
        await File(exePath).writeAsString('fake pe');

        final libDir = Directory(p.join(bundleRoot.path, 'אוצריא'));
        await libDir.create(recursive: true);
        await File(p.join(libDir.path, 'seforim.db')).writeAsString('db');
        await File(
          p.join(libDir.path, '.otzaria_bundled_library'),
        ).writeAsString('');

        AppPaths.debugOverrideDataRootPath(dataRoot.path);
        AppPaths.debugOverrideResolvedExecutable(exePath);

        // ב-Windows: ה-installer של FULL מטפל בנתיב — אין זיהוי מובנה,
        // והברירת מחדל היא תיקיית data root הסטנדרטית.
        expect(
          await AppPaths.getDefaultLibraryPath(),
          p.join(dataRoot.path, 'books'),
        );
      },
    );

    test(
      'מצב נייד — portable.marker ליד ה-EXE מפנה את dataRoot ליד ה-EXE',
      () async {
        final exeRoot = await Directory.systemTemp.createTemp('otzaria_exe_');

        addTearDown(() async {
          if (await exeRoot.exists()) {
            await exeRoot.delete(recursive: true);
          }
        });

        final exePath = p.join(exeRoot.path, 'otzaria.exe');
        await File(exePath).writeAsString('fake exe');
        await File(
          p.join(exeRoot.path, AppPaths.portableMarkerFileName),
        ).writeAsString('');

        AppPaths.debugOverrideResolvedExecutable(exePath);

        expect(AppPaths.isPortable, isTrue);
        expect(
          await AppPaths.getDataRootPath(),
          p.join(exeRoot.path, 'otzaria_data'),
        );
        expect(await AppPaths.detectInstallMode(), InstallMode.perUser);
      },
    );

    test('מצב נייד — ללא marker הזיהוי כבוי', () async {
      final exeRoot = await Directory.systemTemp.createTemp('otzaria_exe_');

      addTearDown(() async {
        if (await exeRoot.exists()) {
          await exeRoot.delete(recursive: true);
        }
      });

      final exePath = p.join(exeRoot.path, 'otzaria.exe');
      await File(exePath).writeAsString('fake exe');

      AppPaths.debugOverrideResolvedExecutable(exePath);

      expect(AppPaths.isPortable, isFalse);
    });

    test('מצב נייד — marker גובר על system_install.marker', () async {
      if (!Platform.isWindows) {
        return;
      }
      final exeRoot = await Directory.systemTemp.createTemp('otzaria_exe_');

      addTearDown(() async {
        if (await exeRoot.exists()) {
          await exeRoot.delete(recursive: true);
        }
      });

      final exePath = p.join(exeRoot.path, 'otzaria.exe');
      await File(exePath).writeAsString('fake exe');
      await File(
        p.join(exeRoot.path, AppPaths.portableMarkerFileName),
      ).writeAsString('');
      await File(
        p.join(exeRoot.path, 'system_install.marker'),
      ).writeAsString('');

      AppPaths.debugOverrideResolvedExecutable(exePath);

      // detectInstallMode בודק את system_install.marker דרך
      // Platform.resolvedExecutable האמיתי, אבל מצב נייד חייב לנצח קודם.
      expect(await AppPaths.detectInstallMode(), InstallMode.perUser);
    });

    test('setAndroidLibraryRoot שומר את שורש הספרייה לבחירת המשתמש', () async {
      const sdRoot = '/storage/ABCD-1234/Android/data/pkg/files';
      await AppPaths.setAndroidLibraryRoot(sdRoot);

      expect(
        Settings.getValue<String>(SettingsRepository.keyAndroidLibraryRoot),
        sdRoot,
      );
    });

    test('setAndroidLibraryRoot עם null מנקה את המפתח לאחסון פנימי', () async {
      await AppPaths.setAndroidLibraryRoot('/some/sd/path');
      await AppPaths.setAndroidLibraryRoot(null);
      expect(
        Settings.getValue<String>(SettingsRepository.keyAndroidLibraryRoot),
        '',
      );
    });

    test(
      'getDefaultLibraryPath מתעלם מ-override של Android כשלא רצים על Android',
      () async {
        // ה-override תקף רק ב-Android; על מארח אחר הוא לא משנה את ברירת המחדל.
        if (Platform.isAndroid) return;
        final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
        addTearDown(() async {
          if (await dataRoot.exists()) {
            await dataRoot.delete(recursive: true);
          }
        });

        AppPaths.debugOverrideDataRootPath(dataRoot.path);
        await AppPaths.setAndroidLibraryRoot('/storage/ABCD-1234/x');

        expect(
          await AppPaths.getDefaultLibraryPath(),
          p.join(dataRoot.path, 'books'),
        );
      },
    );

    test(
      'getStaleDefaultIndexPaths מחזיר נתיבים מנורמלים וללא הנתיב הפעיל',
      () async {
        final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
        final libraryRoot = await Directory.systemTemp.createTemp(
          'otzaria_library_',
        );

        addTearDown(() async {
          if (await dataRoot.exists()) {
            await dataRoot.delete(recursive: true);
          }
          if (await libraryRoot.exists()) {
            await libraryRoot.delete(recursive: true);
          }
        });

        AppPaths.debugOverrideDataRootPath(dataRoot.path);
        await Settings.setValue(
          SettingsRepository.keyLibraryPath,
          p.join(libraryRoot.path, 'books'),
        );
        await Settings.setValue(
          SettingsRepository.keyIndexPath,
          p.join(dataRoot.path, 'nested', '..', 'index'),
        );

        final stalePaths = await AppPaths.getStaleDefaultIndexPaths();

        expect(
          stalePaths,
          isNot(contains(p.normalize(p.join(dataRoot.path, 'index')))),
        );
        expect(
          stalePaths,
          contains(p.normalize(p.join(libraryRoot.path, 'index'))),
        );
        expect(stalePaths, everyElement(isNot(contains('..'))));
        expect(
          stalePaths,
          everyElement(
            predicate<String>((path) {
              return path == p.normalize(path);
            }, 'normalized path'),
          ),
        );
        expect(
          stalePaths.toSet().length,
          stalePaths.length,
          reason: 'נתיבי stale צריכים להיות מנורמלים וללא כפילויות.',
        );
      },
    );
  });

  group('AppPaths זיהוי מצב התקנה — Windows', () {
    /// מכין תיקיית EXE זמנית ומכוון אליה את AppPaths.
    Future<Directory> stageExe({bool systemInstallMarker = false}) async {
      final exeRoot = await Directory.systemTemp.createTemp('otzaria_exe_');
      addTearDown(() async {
        if (await exeRoot.exists()) {
          await exeRoot.delete(recursive: true);
        }
      });

      final exePath = p.join(exeRoot.path, 'otzaria.exe');
      await File(exePath).writeAsString('fake pe');
      if (systemInstallMarker) {
        await File(
          p.join(exeRoot.path, 'system_install.marker'),
        ).writeAsString('[Install]\nMode=Admin\n');
      }
      AppPaths.debugOverrideResolvedExecutable(exePath);
      return exeRoot;
    }

    String programDataBooks() => p.join(
      Platform.environment['ProgramData'] ?? r'C:\ProgramData',
      'otzaria',
      'books',
    );

    Future<Directory> stageDataRoot() async {
      final dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
      addTearDown(() async {
        if (await dataRoot.exists()) {
          await dataRoot.delete(recursive: true);
        }
      });
      AppPaths.debugOverrideDataRootPath(dataRoot.path);
      return dataRoot;
    }

    test('system_install.marker ליד ה-EXE מזוהה כהתקנה מערכתית', () async {
      if (!Platform.isWindows) return;
      await stageExe(systemInstallMarker: true);

      expect(await AppPaths.detectInstallMode(), InstallMode.systemWide);
    });

    test('ללא marker ומחוץ ל-Program Files — התקנת משתמש', () async {
      if (!Platform.isWindows) return;
      await stageExe();

      expect(await AppPaths.detectInstallMode(), InstallMode.perUser);
    });

    test('התקנה מערכתית — ברירת המחדל של הספרייה ב-ProgramData', () async {
      if (!Platform.isWindows) return;
      await stageDataRoot();
      await stageExe(systemInstallMarker: true);

      expect(await AppPaths.getDefaultLibraryPath(), programDataBooks());
    });

    test('התקנת משתמש — ברירת המחדל של הספרייה תחת data root', () async {
      if (!Platform.isWindows) return;
      final dataRoot = await stageDataRoot();
      await stageExe();

      expect(
        await AppPaths.getDefaultLibraryPath(),
        p.join(dataRoot.path, 'books'),
      );
    });

    test('מחיקת המסמן מחזירה את ברירת המחדל ל-data root', () async {
      // המתקין מוחק את המסמן במעבר להתקנת משתמש; בלי המחיקה ברירת המחדל
      // נשארת ב-ProgramData בעוד הספרייה מחולצת ל-AppData.
      if (!Platform.isWindows) return;
      final dataRoot = await stageDataRoot();
      final exeRoot = await stageExe(systemInstallMarker: true);

      expect(await AppPaths.getDefaultLibraryPath(), programDataBooks());

      await File(p.join(exeRoot.path, 'system_install.marker')).delete();

      expect(await AppPaths.detectInstallMode(), InstallMode.perUser);
      expect(
        await AppPaths.getDefaultLibraryPath(),
        p.join(dataRoot.path, 'books'),
      );
    });

    test('מצב נייד מנצח את המסמן גם בברירת המחדל של הספרייה', () async {
      if (!Platform.isWindows) return;
      final exeRoot = await stageExe(systemInstallMarker: true);
      await File(
        p.join(exeRoot.path, AppPaths.portableMarkerFileName),
      ).writeAsString('');
      // הכתיבה נעשתה אחרי הכיוונון — מרעננים את זיהוי המצב הנייד.
      AppPaths.debugOverrideResolvedExecutable(
        p.join(exeRoot.path, 'otzaria.exe'),
      );
      AppPaths.debugOverrideDataRootPath(null);

      expect(await AppPaths.detectInstallMode(), InstallMode.perUser);
      expect(
        await AppPaths.getDefaultLibraryPath(),
        p.join(exeRoot.path, 'otzaria_data', 'books'),
      );
    });

    // מנגנון העדכון גוזר מהערך הזה את דגלי המתקין השקט — זיהוי לפי נתיב
    // בלבד פספס התקנות מנהל בנתיבי legacy ויצר התקנה כפולה (issue #886).
    test(
      'isWindowsSystemInstall — המסמן מזוהה גם מחוץ ל-Program Files',
      () async {
        if (!Platform.isWindows) return;
        await stageExe(systemInstallMarker: true);

        expect(AppPaths.isWindowsSystemInstall, isTrue);
      },
    );

    test(
      'isWindowsSystemInstall — ללא מסמן ומחוץ ל-Program Files: false',
      () async {
        if (!Platform.isWindows) return;
        await stageExe();

        expect(AppPaths.isWindowsSystemInstall, isFalse);
      },
    );

    test('isWindowsSystemInstall — מצב נייד גובר על המסמן', () async {
      if (!Platform.isWindows) return;
      final exeRoot = await stageExe(systemInstallMarker: true);
      await File(
        p.join(exeRoot.path, AppPaths.portableMarkerFileName),
      ).writeAsString('');
      // הכתיבה נעשתה אחרי הכיוונון — מרעננים את זיהוי המצב הנייד.
      AppPaths.debugOverrideResolvedExecutable(
        p.join(exeRoot.path, 'otzaria.exe'),
      );

      expect(AppPaths.isWindowsSystemInstall, isFalse);
    });
  });

  group('AppPaths.libraryRootOf', () {
    test('נתיב שמסתיים ב-books מחזיר את תיקיית האב', () {
      final root = p.join(Directory.systemTemp.path, 'otzaria_root');
      expect(AppPaths.libraryRootOf(p.join(root, 'books')), root);
    });

    test('הזיהוי אינו רגיש לאותיות גדולות', () {
      final root = p.join(Directory.systemTemp.path, 'otzaria_root');
      expect(AppPaths.libraryRootOf(p.join(root, 'BOOKS')), root);
    });

    test('נתיב שאינו books מחזיר את עצמו', () {
      final bundle = p.join(Directory.systemTemp.path, 'bundle', 'אוצריא');
      expect(AppPaths.libraryRootOf(bundle), bundle);
    });
  });

  group('אנדרואיד: האינדקס נשאר באחסון הפנימי (issue #1126)', () {
    late Directory dataRoot;
    late Directory sdRoot;

    setUp(() async {
      dataRoot = await Directory.systemTemp.createTemp('otzaria_data_');
      sdRoot = await Directory.systemTemp.createTemp('otzaria_sd_');
      AppPaths.debugOverrideDataRootPath(dataRoot.path);
      AppPaths.debugIsAndroidOverride = true;
      await Settings.setValue(
        SettingsRepository.keyLibraryPath,
        p.join(sdRoot.path, 'books'),
      );
    });

    tearDown(() async {
      AppPaths.debugIsAndroidOverride = null;
      await Settings.setValue(SettingsRepository.keyIndexPath, '');
      for (final dir in [dataRoot, sdRoot]) {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    test('ספרייה על כרטיס SD: ברירת המחדל של האינדקס פנימית', () async {
      expect(await AppPaths.getIndexPath(), p.join(dataRoot.path, 'index'));
    });

    test('נתיב אינדקס שמור על הכרטיס נדחה ומתנקה', () async {
      final sdIndex = p.join(sdRoot.path, 'index');
      await Settings.setValue(SettingsRepository.keyIndexPath, sdIndex);

      expect(await AppPaths.getIndexPath(), p.join(dataRoot.path, 'index'));
      expect(
        Settings.getValue<String>(SettingsRepository.keyIndexPath),
        isEmpty,
      );
    });

    test('נתיב אינדקס שמור תחת האחסון הפנימי נשמר', () async {
      final internal = p.join(dataRoot.path, 'my_index');
      await Settings.setValue(SettingsRepository.keyIndexPath, internal);

      expect(await AppPaths.getIndexPath(), internal);
    });

    test('שלא באנדרואיד: האינדקס ליד הספרייה כמו קודם', () async {
      AppPaths.debugIsAndroidOverride = false;

      expect(await AppPaths.getIndexPath(), p.join(sdRoot.path, 'index'));
    });
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
