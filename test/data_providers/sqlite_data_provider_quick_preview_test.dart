import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/migration/models/line.dart' as migration_models;
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../test_helpers/memory_cache_provider.dart';

/// ספר עם `totalLines == 0` (למשל קובץ חיצוני שההמרה שלו נכשלה) הפך את הגבול
/// העליון של ה-clamp ל-`-1`, ו-`clamp(0, -1)` זורק `ArgumentError`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SqliteDataProvider.getBookQuickPreview', () {
    late Directory tempDir;
    late MyDatabase seforimDb;
    late SeforimRepository seforimRepo;
    late int categoryId;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-quick-preview-');
      final libraryPath = path.join(tempDir.path, 'library');
      final dataRootPath = path.join(tempDir.path, 'data_root');
      await Directory(libraryPath).create(recursive: true);

      await Settings.init(cacheProvider: MemoryCacheProvider());
      AppPaths.debugOverrideDataRootPath(dataRootPath);
      await UserBooksDatabaseHolder.instance.close();

      await Settings.setValue<String>(
        SettingsRepository.keyLibraryPath,
        libraryPath,
      );
      await Settings.setValue<String>(
        SettingsRepository.keyLibraryFolderName,
        '',
      );
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        '',
      );

      final dbPath = path.join(libraryPath, DatabaseConstants.databaseFileName);
      seforimDb = MyDatabase.withPath(dbPath);
      seforimRepo = SeforimRepository(seforimDb);
      await seforimRepo.ensureInitialized();
      categoryId = await seforimRepo.insertCategory(
        const migration_models.Category(title: 'שורש'),
      );

      await SqliteDataProvider.instance.dispose();
      await SqliteDataProvider.instance.initialize();
    });

    tearDown(() async {
      await SqliteDataProvider.instance.dispose();
      await UserBooksDatabaseHolder.instance.close();
      seforimDb.close();
      AppPaths.debugOverrideDataRootPath(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<void> insertBook(String title, List<String> lines) async {
      final sourceId = await seforimRepo.insertSource('test::$title', -1);
      final bookId = await seforimRepo.insertBook(
        migration_models.Book(
          categoryId: categoryId,
          sourceId: sourceId,
          title: title,
          fileType: 'txt',
          totalLines: lines.length,
        ),
      );
      if (lines.isEmpty) return;
      await seforimRepo.insertLinesBatch([
        for (var i = 0; i < lines.length; i++)
          migration_models.Line(
            bookId: bookId,
            lineIndex: i,
            content: lines[i],
          ),
      ]);
      await seforimRepo.updateBookTotalLines(bookId, lines.length);
    }

    /// ה-catch של המתודה מחזיר null גם על חריגה, ולכן null לבדו אינו מבחין
    /// בין "אין תוכן" לבין זריקה. הלוג הוא הראיה היחידה.
    Future<({String? preview, List<String> failures})> previewWithLog(
      String title,
      int currentLine,
    ) async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        final preview = await SqliteDataProvider.instance.getBookQuickPreview(
          title,
          currentLine,
          categoryId: categoryId,
        );
        return (
          preview: preview,
          failures: logs
              .where((l) => l.contains('getBookQuickPreview failed'))
              .toList(),
        );
      } finally {
        debugPrint = originalDebugPrint;
      }
    }

    group('ספרים ללא תוכן', () {
      test('totalLines=0 מחזיר null ולא זורק ArgumentError', () async {
        await insertBook('ספר ריק', const []);

        final result = await previewWithLog('ספר ריק', 0);

        expect(result.preview, isNull);
        expect(
          result.failures,
          isEmpty,
          reason: 'clamp(0, totalLines - 1) על ספר ריק זורק ArgumentError',
        );
      });

      test('totalLines=0 עם מיקום גבוה אינו זורק', () async {
        await insertBook('ריק גבוה', const []);

        final result = await previewWithLog('ריק גבוה', 500);

        expect(result.preview, isNull);
        expect(result.failures, isEmpty);
      });

      test('ספר שאינו קיים מחזיר null ללא שגיאה', () async {
        final result = await previewWithLog('אין ספר כזה', 0);

        expect(result.preview, isNull);
        expect(result.failures, isEmpty);
      });
    });

    group('ספרים עם תוכן', () {
      test('מחזיר את הטקסט סביב המיקום', () async {
        await insertBook('ספר מלא', const ['שורה א', 'שורה ב', 'שורה ג']);

        final result = await previewWithLog('ספר מלא', 1);

        expect(result.preview, isNotNull);
        expect(result.preview, contains('שורה ב'));
        expect(result.failures, isEmpty);
      });

      test('שורה בודדת (totalLines=1) — הקצה של clamp(0, 0)', () async {
        await insertBook('שורה אחת', const ['היחידה']);

        final result = await previewWithLog('שורה אחת', 0);

        expect(result.preview, contains('היחידה'));
        expect(result.failures, isEmpty);
      });

      test('מיקום מעבר לסוף הספר נחתך לסוף ואינו זורק', () async {
        await insertBook('קצר', const ['ראשונה', 'שנייה']);

        final result = await previewWithLog('קצר', 9999);

        expect(result.preview, contains('שנייה'));
        expect(result.failures, isEmpty);
      });

      test('מיקום שלילי נחתך לאפס ואינו זורק', () async {
        await insertBook('שלילי', const ['ראשונה', 'שנייה']);

        final result = await previewWithLog('שלילי', -50);

        expect(result.preview, contains('ראשונה'));
        expect(result.failures, isEmpty);
      });

      test('בספר ארוך נחתך חלון סביב המיקום ולא כל הספר', () async {
        await insertBook('ארוך', [for (var i = 0; i < 100; i++) 'שורה $i']);

        final result = await previewWithLog('ארוך', 50);

        expect(result.preview, contains('שורה 50'));
        expect(result.preview, contains('שורה 40'));
        expect(result.preview, contains('שורה 60'));
        expect(result.preview, isNot(contains('שורה 0\n')));
        expect(result.preview, isNot(contains('שורה 99')));
        expect(result.failures, isEmpty);
      });

      test('מיקום 0 בספר ארוך מתחיל מתחילת הספר', () async {
        await insertBook('מהתחלה', [for (var i = 0; i < 40; i++) 'שורה $i']);

        final result = await previewWithLog('מהתחלה', 0);

        expect(result.preview, contains('שורה 0'));
        expect(result.preview, contains('שורה 10'));
        expect(result.failures, isEmpty);
      });
    });
  });
}
