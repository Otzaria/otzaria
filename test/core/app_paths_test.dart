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
  });

  tearDown(() async {
    AppPaths.debugOverrideDataRootPath(null);
    AppPaths.debugOverrideResolvedExecutable(null);
    Settings.clearCache();
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
