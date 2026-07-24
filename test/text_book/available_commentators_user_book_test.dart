import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration_models;
import 'package:otzaria/migration/models/category.dart' as migration_models;
import 'package:otzaria/migration/models/line.dart' as migration_models;
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:path/path.dart' as path;
import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  // רגרסיה: ספרים אישיים הציגו מפרשים של בראשית כי dbBook.id מ-user_books.db
  // (שמתחיל מ-1) שימש לשאילתה ב-seforim.db, שבו id=1 הוא בראשית.
  group('getAvailableCommentators — ספרים אישיים', () {
    late Directory tempDir;
    late MyDatabase seforimDb;
    late SeforimRepository seforimRepo;
    late TextBookRepository repository;
    late int bereshitCategoryId;
    late int bereshitId;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'otzaria-commentators-test-',
      );
      seforimDb = MyDatabase.withPath(path.join(tempDir.path, 'seforim.db'));
      seforimRepo = SeforimRepository(seforimDb);
      await seforimRepo.ensureInitialized();

      // שתול ב-seforim.db: קטגוריה "תנ"ך" + ספר "בראשית" + שורה + מפרש "רש"י"
      bereshitCategoryId = await seforimRepo.insertCategory(
        const migration_models.Category(title: 'תנ"ך', level: 0),
      );
      final sourceId = await seforimRepo.insertSource('official', 1);

      bereshitId = await seforimRepo.insertBook(
        migration_models.Book(
          categoryId: bereshitCategoryId,
          sourceId: sourceId,
          title: 'בראשית',
          fileType: 'txt',
        ),
      );

      final rashiId = await seforimRepo.insertBook(
        migration_models.Book(
          categoryId: bereshitCategoryId,
          sourceId: sourceId,
          title: 'רש"י על בראשית',
          fileType: 'txt',
        ),
      );

      final sourceLineId = await seforimRepo.insertLine(
        migration_models.Line(
          bookId: bereshitId,
          lineIndex: 0,
          content: 'בראשית ברא',
        ),
      );
      final targetLineId = await seforimRepo.insertLine(
        migration_models.Line(
          bookId: rashiId,
          lineIndex: 0,
          content: 'פירוש רש"י',
        ),
      );

      // יש לוודא שסוג הקישור 'COMMENTARY' (אותיות גדולות, כפי שנוצר ב-initializeConnectionTypes)
      // קיים ב-cache לפני הכנסת הקישור, כדי שהשאילתה selectCommentatorsByBook תמצאו.
      final commentaryTypeId = await seforimRepo.getOrCreateConnectionType(
        'COMMENTARY',
      );
      final db = await seforimDb.database;
      db.execute(
        'INSERT INTO link (sourceBookId, targetBookId, sourceLineId, targetLineId, connectionTypeId) '
        'VALUES (?, ?, ?, ?, ?)',
        [bereshitId, rashiId, sourceLineId, targetLineId, commentaryTypeId],
      );

      final provider = SqliteDataProvider.withRepository(seforimRepo);
      repository = TextBookRepository(
        fileSystem: FileSystemData.instance,
        sqliteProvider: provider,
      );
    });

    tearDown(() async {
      seforimDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'ספר אישי עם categoryId=1 מחזיר ריק — לא המפרשים של ספר 1 ב-seforim.db',
      () async {
        // ספר אישי: categoryId=1 ב-user_books.db — אותו ID כמו בראשית ב-seforim.db.
        // ללא התיקון, הקריאה ל-seforim.db עם id=1 תחזיר את מפרשי בראשית.
        final userBook = TextBook(
          title: 'הספר שלי',
          isUserBook: true,
          categoryId: 1,
        );

        final commentators = await repository.getAvailableCommentators(
          userBook,
        );

        expect(
          commentators,
          isEmpty,
          reason: 'ספר אישי לא צריך להחזיר מפרשים מ-seforim.db',
        );
      },
    );

    test(
      'ספר רשמי שנמצא ב-DB מחזיר את המפרשים שלו',
      () async {
        final officialBook = TextBook(
          title: 'בראשית',
          isUserBook: false,
          categoryId: bereshitCategoryId,
          fileType: 'txt',
        );

        final commentators = await repository.getAvailableCommentators(
          officialBook,
        );

        expect(
          commentators,
          contains('רש"י על בראשית'),
          reason: 'ספר רשמי צריך להחזיר את מפרשיו מה-DB',
        );
      },
    );

    test(
      'ספר גדול (מעל 100 שורות): מפרש עם פחות מ-10 קישורים מסומן כנדיר',
      () async {
        await seforimRepo.updateBookTotalLines(bereshitId, 500);

        final officialBook = TextBook(
          title: 'בראשית',
          isUserBook: false,
          categoryId: bereshitCategoryId,
          fileType: 'txt',
        );

        final result = await repository.getCommentatorsWithRarity(officialBook);

        expect(
          result.all,
          contains('רש"י על בראשית'),
          reason: 'המפרש עדיין זמין (יוצג פר-שורה)',
        );
        expect(
          result.rare,
          contains('רש"י על בראשית'),
          reason: 'קישור בודד (<10) בספר מעל 100 שורות — נדיר',
        );
      },
    );

    test(
      'ספר קטן (עד 100 שורות): אין מפרשים נדירים',
      () async {
        await seforimRepo.updateBookTotalLines(bereshitId, 50);

        final officialBook = TextBook(
          title: 'בראשית',
          isUserBook: false,
          categoryId: bereshitCategoryId,
          fileType: 'txt',
        );

        final result = await repository.getCommentatorsWithRarity(officialBook);

        expect(result.rare, isEmpty);
      },
    );
  });
}
