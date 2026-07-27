import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart'
    show clearCommentatorOrderCache, hasTopic, isEraTableLoaded, splitByEra;
import 'package:path/path.dart' as p;

import '../test_helpers/memory_cache_provider.dart';

/// מיון קבוצות המפרשים חייב להישען על אותו מטמון דורות כמו כל שאר המיונים
/// באפליקציה: טעינה מרוכזת אחת, סמנטיקת ריבוי-דורות אחת, וכולל ספרי משתמש.
///
/// ה-provider פותח את seforim.db read-only וממיר WAL→DELETE בעצמו. המרה בזמן
/// קריאה מתחרה בקובץ ה--wal ומחזירה עמודים ישנים תחת עומס, ולכן כל טסט כאן
/// מייצב את הקובץ ב-[_settleForReadOnly] לפני שה-provider נוגע בו.
Future<void> _settleForReadOnly(MyDatabase db) async {
  final raw = await db.database;
  raw.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  raw.execute('PRAGMA journal_mode=DELETE');
}

LinkGroup _group(String title) => LinkGroup(
  bookTitle: title,
  links: [
    Link(
      heRef: title,
      index1: 1,
      path2: title,
      index2: 1,
      connectionType: 'COMMENTARY',
    ),
  ],
);

List<String> _titles(List<LinkGroup> groups) =>
    groups.map((g) => g.bookTitle).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sortGroupsByEraSync — מיון מהמטמון בלבד', () {
    setUp(CommentaryService.clearEraCache);
    tearDown(CommentaryService.clearEraCache);

    test('הדור קובע לפני האלפבית', () {
      CommentaryService.seedEraCache(const {
        'אבן עזרא': CommentaryEra.acharonim,
        'תוספות': CommentaryEra.rishonim,
      });

      expect(
        _titles(
          CommentaryService.sortGroupsByEraSync([
            _group('אבן עזרא'),
            _group('תוספות'),
          ]),
        ),
        ['תוספות', 'אבן עזרא'],
      );
    });

    test('ספר שאינו במטמון נופל לסוף כ"שאר מפרשים"', () {
      CommentaryService.seedEraCache(const {'תוספות': CommentaryEra.rishonim});

      expect(
        _titles(
          CommentaryService.sortGroupsByEraSync([
            _group('אבן עזרא'),
            _group('תוספות'),
          ]),
        ),
        ['תוספות', 'אבן עזרא'],
      );
    });

    test('"הערות על XX" יורש את דורו של XX ובא מיד אחריו', () {
      // דורו-שלו של ספר ההערות (מחברי זמננו) נזנח לטובת דור העוגן.
      CommentaryService.seedEraCache(const {
        'רש"י': CommentaryEra.rishonim,
        'הערות על רש"י': CommentaryEra.modern,
        'אבן עזרא': CommentaryEra.acharonim,
      });

      expect(
        _titles(
          CommentaryService.sortGroupsByEraSync([
            _group('אבן עזרא'),
            _group('הערות על רש"י'),
            _group('רש"י'),
          ]),
        ),
        ['רש"י', 'הערות על רש"י', 'אבן עזרא'],
      );
    });

    test('ספר-הערות שבסיסו נעדר ממוין לפי דורו-שלו', () {
      CommentaryService.seedEraCache(const {
        'הערות על רש"י': CommentaryEra.chazal,
        'אבן עזרא': CommentaryEra.acharonim,
      });

      expect(
        _titles(
          CommentaryService.sortGroupsByEraSync([
            _group('אבן עזרא'),
            _group('הערות על רש"י'),
          ]),
        ),
        ['הערות על רש"י', 'אבן עזרא'],
      );
    });

    test('באותו דור המיון אלפביתי', () {
      CommentaryService.seedEraCache(const {
        'תוספות': CommentaryEra.rishonim,
        'אבן עזרא': CommentaryEra.rishonim,
      });

      expect(
        _titles(
          CommentaryService.sortGroupsByEraSync([
            _group('תוספות'),
            _group('אבן עזרא'),
          ]),
        ),
        ['אבן עזרא', 'תוספות'],
      );
    });

    test('קבוצה בודדת ורשימה ריקה מוחזרות כמו שהן', () {
      final single = [_group('רש"י')];
      final empty = <LinkGroup>[];

      expect(CommentaryService.sortGroupsByEraSync(single), same(single));
      expect(CommentaryService.sortGroupsByEraSync(empty), same(empty));
    });

    test('הרשימה שנמסרה אינה משתנה במקום', () {
      CommentaryService.seedEraCache(const {'תוספות': CommentaryEra.rishonim});
      final input = [_group('אבן עזרא'), _group('תוספות')];

      CommentaryService.sortGroupsByEraSync(input);

      expect(_titles(input), ['אבן עזרא', 'תוספות']);
    });
  });

  group('sortGroupsByEra — מטמון חם אינו נדרש ל-DB', () {
    setUp(CommentaryService.clearEraCache);
    tearDown(CommentaryService.clearEraCache);

    test('כל הכותרות במטמון => מיון לפי דור גם בלי DB', () async {
      CommentaryService.seedEraCache(const {
        'תוספות': CommentaryEra.rishonim,
        'אבן עזרא': CommentaryEra.acharonim,
      });

      final sorted = await CommentaryService.sortGroupsByEra([
        _group('אבן עזרא'),
        _group('תוספות'),
      ]);

      expect(
        _titles(sorted),
        ['תוספות', 'אבן עזרא'],
        reason: 'המיון נשען על המטמון בלבד ואינו דורש שאילתה',
      );
    });

    test('קבוצה בודדת מוחזרת כמו שהיא', () async {
      final single = [_group('רש"י')];
      expect(await CommentaryService.sortGroupsByEra(single), same(single));
    });
  });

  group('sortGroupsByEra מול DB אמיתי', () {
    late Directory tempDir;
    late String dbPath;

    // עוקף את ה-provider כדי לשנות את ה-DB "מאחורי" המטמון.
    Future<void> mutate(String sql) async {
      await SqliteDataProvider.instance.dispose();
      final db = MyDatabase.withPath(dbPath);
      (await db.database).execute(sql);
      await _settleForReadOnly(db);
      db.close();
    }

    setUp(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      tempDir = await Directory.systemTemp.createTemp('otzaria-group-era-');
      dbPath = p.join(tempDir.path, 'seforim.db');

      final seforimDb = MyDatabase.withPath(dbPath);
      final repo = SeforimRepository(seforimDb);
      await repo.ensureInitialized();

      final catId = await repo.insertCategory(const Category(title: 'ק'));
      final srcId = await repo.insertSource('s', -1);
      final rambamId = await repo.insertBook(
        Book(
          id: 0,
          categoryId: catId,
          sourceId: srcId,
          title: 'רמב"ם',
          fileType: 'txt',
        ),
      );
      final chatamId = await repo.insertBook(
        Book(
          id: 0,
          categoryId: catId,
          sourceId: srcId,
          title: 'חתם סופר',
          fileType: 'txt',
        ),
      );

      final db = await seforimDb.database;
      db.execute(
        "INSERT INTO generation (id, name) VALUES (1, 'ראשונים'), (2, 'אחרונים')",
      );
      db.execute(
        'INSERT INTO book_generation (bookId, generationId) VALUES (?, 1)',
        [rambamId],
      );
      db.execute(
        'INSERT INTO book_generation (bookId, generationId) VALUES (?, 2)',
        [chatamId],
      );

      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        dbPath,
      );
      if (SqliteDataProvider.instance.isInitialized) {
        await SqliteDataProvider.instance.dispose();
      }
      await _settleForReadOnly(seforimDb);
      seforimDb.close();
      CommentaryService.clearEraCache();
    });

    tearDown(() async {
      CommentaryService.clearEraCache();
      await SqliteDataProvider.instance.dispose();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('הדור נקרא מה-DB: ראשונים לפני אחרונים', () async {
      final sorted = await CommentaryService.sortGroupsByEra([
        _group('חתם סופר'),
        _group('רמב"ם'),
      ]);

      expect(_titles(sorted), ['רמב"ם', 'חתם סופר']);
    });

    test('ספר המתויג לשני דורות ממוין לפי המוקדם שבהם', () async {
      await mutate(
        "INSERT INTO book_generation (bookId, generationId) "
        "SELECT id, 1 FROM book WHERE title = 'חתם סופר'",
      );

      final sorted = await CommentaryService.sortGroupsByEra([
        _group('רמב"ם'),
        _group('חתם סופר'),
      ]);

      expect(
        _titles(sorted),
        ['חתם סופר', 'רמב"ם'],
        reason: 'שני הספרים ראשונים => אלפביתי; ח לפני ר',
      );
    });

    test('שינוי ב-DB אינו נקרא מחדש לכל קבוצה', () async {
      await CommentaryService.sortGroupsByEra([
        _group('חתם סופר'),
        _group('רמב"ם'),
      ]);

      await mutate(
        'UPDATE book_generation SET generationId = 2 WHERE bookId = '
        '(SELECT id FROM book WHERE title = \'רמב"ם\')',
      );

      final sorted = await CommentaryService.sortGroupsByEra([
        _group('חתם סופר'),
        _group('רמב"ם'),
      ]);

      expect(
        _titles(sorted),
        ['רמב"ם', 'חתם סופר'],
        reason: 'המטמון חם — אין שאילתה חיה לכל קבוצה בכל דפדוף',
      );
    });

    test('clearEraCache מנקה גם את מטמון המקור, ולכן הסדר מתרענן', () async {
      await CommentaryService.sortGroupsByEra([
        _group('חתם סופר'),
        _group('רמב"ם'),
      ]);

      await mutate(
        'UPDATE book_generation SET generationId = 2 WHERE bookId = '
        '(SELECT id FROM book WHERE title = \'רמב"ם\')',
      );
      CommentaryService.clearEraCache();

      final sorted = await CommentaryService.sortGroupsByEra([
        _group('חתם סופר'),
        _group('רמב"ם'),
      ]);

      expect(
        _titles(sorted),
        ['חתם סופר', 'רמב"ם'],
        reason: 'ניקוי מטמון הדורות חייב לנקות גם את המקור שממנו הוא נגזר',
      );
    });

    // הופך את ה-DB ללא-זמין, כמו בעדכון ספרייה או DB נעול בעלייה.
    Future<void> detachDb() async {
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        p.join(tempDir.path, 'missing.db'),
      );
      await SqliteDataProvider.instance.dispose();
      clearCommentatorOrderCache();
    }

    Future<void> attachDb() async {
      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        dbPath,
      );
      await SqliteDataProvider.instance.dispose();
      clearCommentatorOrderCache();
    }

    test('כשל בטעינת טבלת הדורות אינו מקבע סיווג שגוי במטמון', () async {
      await detachDb();
      await CommentaryService.preloadEras(const ['רמב"ם']);
      expect(isEraTableLoaded, isFalse);

      await attachDb();
      await CommentaryService.preloadEras(const ['רמב"ם']);

      expect(
        CommentaryService.getCachedBookEra('רמב"ם'),
        CommentaryEra.rishonim,
        reason: 'סיווג מכשל זמני נשמר במטמון ומנע ניסיון נוסף',
      );
    });

    test('hasTopic אינו זורק כשטבלת הדורות לא נטענה', () async {
      await detachDb();

      expect(await hasTopic('רמב"ם', 'ראשונים'), isFalse);
      expect(await hasTopic('רמב"ם', 'מפרשים נוספים'), isTrue);
    });

    test('כשל חולף נבדק שוב ברגע שה-DB חוזר להיות זמין', () async {
      await detachDb();
      await splitByEra(const ['רמב"ם']);
      expect(isEraTableLoaded, isFalse);

      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        dbPath,
      );
      await SqliteDataProvider.instance.dispose();
      await SqliteDataProvider.instance.initialize();

      final byEra = await splitByEra(const ['רמב"ם']);

      expect(
        byEra['ראשונים'],
        contains('רמב"ם'),
        reason: 'ניסיון חוזר חייב להתרחש בלי ניקוי מטמון יזום',
      );
    });
  });

  group('דור ספר-משתמש נכלל במיון הקבוצות', () {
    late Directory tempDir;

    setUp(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      tempDir = await Directory.systemTemp.createTemp(
        'otzaria-group-era-user-',
      );
      final dbPath = p.join(tempDir.path, 'seforim.db');

      final seforimDb = MyDatabase.withPath(dbPath);
      final repo = SeforimRepository(seforimDb);
      await repo.ensureInitialized();
      final catId = await repo.insertCategory(const Category(title: 'ק'));
      final srcId = await repo.insertSource('s', -1);
      final rambamId = await repo.insertBook(
        Book(
          id: 0,
          categoryId: catId,
          sourceId: srcId,
          title: 'רמב"ם',
          fileType: 'txt',
        ),
      );
      final db = await seforimDb.database;
      db.execute("INSERT INTO generation (id, name) VALUES (2, 'אחרונים')");
      db.execute(
        'INSERT INTO book_generation (bookId, generationId) VALUES (?, 2)',
        [rambamId],
      );
      await _settleForReadOnly(seforimDb);
      seforimDb.close();

      await Settings.setValue<String>(
        SettingsRepository.keyDbEffectivePath,
        dbPath,
      );
      await Settings.setValue<String>(
        SettingsRepository.keyDatabasesPath,
        tempDir.path,
      );
      await UserBooksDatabaseHolder.instance.close();
      if (SqliteDataProvider.instance.isInitialized) {
        await SqliteDataProvider.instance.dispose();
      }

      final userRepo = await UserBooksDatabaseHolder.instance.repository;
      final userCatId = await userRepo.insertCategory(
        const Category(title: 'ספרים אישיים'),
      );
      final userSrcId = await userRepo.insertSource('user', -20);
      final userBookId = await userRepo.insertBook(
        Book(
          id: 0,
          categoryId: userCatId,
          sourceId: userSrcId,
          title: 'תוספות אישיים',
          fileType: 'txt',
        ),
      );
      final userDb = await userRepo.database.database;
      userDb.execute("INSERT INTO generation (id, name) VALUES (1, 'ראשונים')");
      userDb.execute(
        'INSERT INTO book_generation (bookId, generationId) VALUES (?, 1)',
        [userBookId],
      );

      CommentaryService.clearEraCache();
    });

    tearDown(() async {
      CommentaryService.clearEraCache();
      await UserBooksDatabaseHolder.instance.close();
      await SqliteDataProvider.instance.dispose();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('מפרש-משתמש ממוין לפי דורו ולא נדחק ל"שאר מפרשים"', () async {
      final sorted = await CommentaryService.sortGroupsByEra([
        _group('רמב"ם'),
        _group('תוספות אישיים'),
      ]);

      expect(
        _titles(sorted),
        ['תוספות אישיים', 'רמב"ם'],
        reason: 'הדור של ספר משתמש חי ב-user_books.db וחייב להיכלל במיון',
      );
    });
  });
}
