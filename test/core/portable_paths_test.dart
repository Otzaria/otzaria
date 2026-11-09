import 'dart:convert';
import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/attached_libraries_repository.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_probe.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/portable_paths.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:path/path.dart' as p;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory exeRoot;
  late String dataRoot;

  /// מקים "דיסק-און-קי" מדומה: EXE + portable.marker, ומפעיל את הזיהוי.
  Future<void> setUpPortableEnvironment() async {
    exeRoot = await Directory.systemTemp.createTemp('otzaria_portable_');
    final exePath = p.join(exeRoot.path, 'otzaria.exe');
    await File(exePath).writeAsString('fake exe');
    await File(
      p.join(exeRoot.path, AppPaths.portableMarkerFileName),
    ).writeAsString('');

    AppPaths.debugOverrideResolvedExecutable(exePath);
    dataRoot = await AppPaths.getDataRootPath();
    await Directory(dataRoot).create(recursive: true);
  }

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath(null);
    AppPaths.debugOverrideResolvedExecutable(null);
    await setUpPortableEnvironment();
    Hive.init(dataRoot);
  });

  tearDown(() async {
    await Hive.close();
    AppPaths.debugOverrideDataRootPath(null);
    AppPaths.debugOverrideResolvedExecutable(null);
    await Settings.clearCache();
    if (await exeRoot.exists()) {
      await exeRoot.delete(recursive: true);
    }
  });

  /// כותב את קובץ רשומת השורש כאילו הריצה הקודמת הייתה תחת [oldRoot].
  Future<void> writeRootRecord(String oldRoot) async {
    await File(
      p.join(dataRoot, '.otzaria_portable_root'),
    ).writeAsString(oldRoot, flush: true);
  }

  String rootRecordContent() =>
      File(p.join(dataRoot, '.otzaria_portable_root')).readAsStringSync();

  group('PortablePaths.migrateIfMoved', () {
    test('ריצה ראשונה — רק רושם את השורש הנוכחי ולא נוגע בנתונים', () async {
      await Settings.setValue(
        SettingsRepository.keyLibraryPath,
        p.join('somewhere', 'books'),
      );

      await PortablePaths.migrateIfMoved();

      expect(p.equals(rootRecordContent(), dataRoot), isTrue);
      expect(
        Settings.getValue<String>(SettingsRepository.keyLibraryPath),
        p.join('somewhere', 'books'),
      );
    });

    test('שורש זהה — לא משכתב דבר', () async {
      await writeRootRecord(dataRoot);
      final savedPath = p.join(dataRoot, 'books');
      await Settings.setValue(SettingsRepository.keyLibraryPath, savedPath);

      await PortablePaths.migrateIfMoved();

      expect(
        Settings.getValue<String>(SettingsRepository.keyLibraryPath),
        savedPath,
      );
    });

    test('שורש זז — משכתב את כל מפתחות הנתיבים ב-settings', () async {
      final oldRoot = p.join(Directory.systemTemp.path, 'old_stick', 'data');
      await writeRootRecord(oldRoot);

      await Settings.setValue(
        SettingsRepository.keyLibraryPath,
        p.join(oldRoot, 'books'),
      );
      await Settings.setValue(
        SettingsRepository.keyIndexPath,
        p.join(oldRoot, 'index'),
      );
      await Settings.setValue(
        SettingsRepository.keyDatabasesPath,
        p.join(oldRoot, 'databases'),
      );
      await Settings.setValue(
        SettingsRepository.keyBackupPath,
        p.join(oldRoot, 'backups'),
      );
      // נתיב שאינו תחת השורש הישן — חייב להישאר כמו שהוא.
      final unrelated = p.join('another', 'drive', 'books');
      await Settings.setValue(SettingsRepository.keyHebrewBooksPath, unrelated);

      await PortablePaths.migrateIfMoved();

      expect(
        Settings.getValue<String>(SettingsRepository.keyLibraryPath),
        p.join(dataRoot, 'books'),
      );
      expect(
        Settings.getValue<String>(SettingsRepository.keyIndexPath),
        p.join(dataRoot, 'index'),
      );
      expect(
        Settings.getValue<String>(SettingsRepository.keyDatabasesPath),
        p.join(dataRoot, 'databases'),
      );
      expect(
        Settings.getValue<String>(SettingsRepository.keyBackupPath),
        p.join(dataRoot, 'backups'),
      );
      expect(
        Settings.getValue<String>(SettingsRepository.keyHebrewBooksPath),
        unrelated,
      );
      expect(p.equals(rootRecordContent(), dataRoot), isTrue);
    });

    test('שורש זז — משכתב נתיבים בתוך Hive boxes (טאבים עם PdfBook)', () async {
      final oldRoot = p.join(Directory.systemTemp.path, 'old_stick', 'data');
      await writeRootRecord(oldRoot);

      final tabsBox = await Hive.openBox<dynamic>('tabs');
      await tabsBox.put('key-tabs', [
        {
          'type': 'PdfBookTab',
          'title': 'ספר',
          'book': {
            'title': 'ספר',
            'path': p.join(oldRoot, 'books', 'ספר.pdf'),
          },
          'pageNumber': 3,
        },
      ]);
      await tabsBox.put('key-current-tab', 0);

      await PortablePaths.migrateIfMoved();

      final rawTabs = tabsBox.get('key-tabs') as List;
      final book = (rawTabs.first as Map)['book'] as Map;
      expect(book['path'], p.join(dataRoot, 'books', 'ספר.pdf'));
      // ערכים שאינם נתיבים נשארים כמות שהם.
      expect((rawTabs.first as Map)['pageNumber'], 3);
      expect(tabsBox.get('key-current-tab'), 0);
    });

    test('שורש זז — prefix חלקי של תיקייה אחות לא משוכתב', () async {
      final oldRoot = p.join(Directory.systemTemp.path, 'old_stick', 'data');
      await writeRootRecord(oldRoot);

      // "data2" מתחיל ב-"data" אבל אינו יושב תחתיו.
      final sibling = '${oldRoot}2${p.separator}books';
      await Settings.setValue(SettingsRepository.keyLibraryPath, sibling);

      await PortablePaths.migrateIfMoved();

      expect(
        Settings.getValue<String>(SettingsRepository.keyLibraryPath),
        sibling,
      );
    });

    test('שורש זז — משכתב נתיבים בתיקיות מותאמות אישית (JSON)', () async {
      final oldRoot = p.join(Directory.systemTemp.path, 'old_stick', 'data');
      await writeRootRecord(oldRoot);

      await Settings.setValue(
        SettingsRepository.keyCustomFolders,
        jsonEncode([
          {
            'path': p.join(oldRoot, 'my_books'),
            'addToDatabase': true,
            'addedAt': '2026-01-01T00:00:00.000',
          },
        ]),
      );

      await PortablePaths.migrateIfMoved();

      final decoded =
          jsonDecode(
                Settings.getValue<String>(SettingsRepository.keyCustomFolders)!,
              )
              as List;
      expect(
        (decoded.first as Map)['path'],
        p.join(dataRoot, 'my_books'),
      );
      expect((decoded.first as Map)['addToDatabase'], isTrue);
    });

    test('כונן נייד שהחליף אות — מסד אישי מתיקיית מסדים נשאר זמין '
        '(issue #2479)', () async {
      await PortablePaths.migrateIfMoved();
      final folder = Directory(p.join(dataRoot, 'מסדים'))..createSync();
      final created = SeforimFixtureDb.create(
        folder,
        SeforimFixtureVariant.full,
      );
      File(created).renameSync(p.join(folder.path, 'ספרים.db'));
      Future<AttachedLibraryProbeResult> probe(String path) async =>
          AttachedLibraryProbe.probeSync(path);
      final before = AttachedLibraryRegistry(idleTimeout: null);
      await AttachedLibrariesRepository(
        registry: before,
        probe: probe,
      ).addFolder(folder.path);
      expect(before.libraries.single.isOk, isTrue);
      await before.closeAll();

      // אותה תיקייה ניידת, במחשב שבו הכונן קיבל אות אחרת.
      exeRoot = exeRoot.renameSync('${exeRoot.path}_E');
      AppPaths.debugOverrideDataRootPath(null);
      AppPaths.debugOverrideResolvedExecutable(
        p.join(exeRoot.path, 'otzaria.exe'),
      );
      dataRoot = await AppPaths.getDataRootPath();
      await PortablePaths.migrateIfMoved();

      final after = AttachedLibraryRegistry(idleTimeout: null);
      addTearDown(after.closeAll);
      final repository = AttachedLibrariesRepository(
        registry: after,
        probe: probe,
      );
      await repository.rescan();
      expect(after.libraries.single.status, AttachedLibraryStatus.ok);
      await repository.removeFolder(p.join(dataRoot, 'מסדים'));
      expect(after.libraries, isEmpty);
    });

    test('Windows: שינוי אות כונן באותיות שונות (case) עדיין מזוהה', () async {
      if (!Platform.isWindows) {
        return;
      }
      // אותו שורש ישן, אבל באות כונן קטנה — p.equals אמור להשוות נכון
      // ולכן לא תופעל מיגרציה (אין "תזוזה" אמיתית).
      final lowerCaseRoot =
          dataRoot.substring(0, 1).toLowerCase() + dataRoot.substring(1);
      await writeRootRecord(lowerCaseRoot);
      final savedPath = p.join(dataRoot, 'books');
      await Settings.setValue(SettingsRepository.keyLibraryPath, savedPath);

      await PortablePaths.migrateIfMoved();

      expect(
        Settings.getValue<String>(SettingsRepository.keyLibraryPath),
        savedPath,
      );
    });

    test('לא במצב נייד — לא עושה דבר ולא יוצר קובץ רשומה', () async {
      // מסירים את ה-marker ומאפסים את הקאש של הזיהוי.
      final exePath = p.join(exeRoot.path, 'otzaria.exe');
      await File(
        p.join(exeRoot.path, AppPaths.portableMarkerFileName),
      ).delete();
      AppPaths.debugOverrideResolvedExecutable(exePath);
      AppPaths.debugOverrideDataRootPath(dataRoot);

      await PortablePaths.migrateIfMoved();

      expect(
        File(p.join(dataRoot, '.otzaria_portable_root')).existsSync(),
        isFalse,
      );
    });
  });
}
