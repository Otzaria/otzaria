import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:path/path.dart' as p;

import '../test_helpers/memory_cache_provider.dart';

/// רגרסיה לתיקון האיטיות בקומיט 2f10b7662: splitByEra עברה מ-N*5 קריאות
/// hasTopic אסינכרוניות (await בלולאה) לטעינת cache פעם אחת + מיון סינכרוני
/// (_getTopicSync). הטסט מוודא שהמיון עדיין תואם את הנתונים ב-DB, ושה-cache
/// אכן משמש בקריאה חוזרת (לא נטען מחדש בכל קריאה).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase seforimDb;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria-split-era-');
    final dbPath = p.join(tempDir.path, 'seforim.db');
    seforimDb = MyDatabase.withPath(dbPath);
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
    final chinuchId = await repo.insertBook(
      Book(
        id: 0,
        categoryId: catId,
        sourceId: srcId,
        title: 'ספר החינוך',
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
      'INSERT INTO book_generation (bookId, generationId) VALUES (?, 1)',
      [chinuchId],
    );

    await Settings.setValue<String>(
      SettingsRepository.keyDbEffectivePath,
      dbPath,
    );
    clearCommentatorOrderCache();
    if (SqliteDataProvider.instance.isInitialized) {
      await SqliteDataProvider.instance.dispose();
    }
  });

  tearDown(() async {
    clearCommentatorOrderCache();
    await SqliteDataProvider.instance.dispose();
    seforimDb.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'ממיין ספרים תחת "ראשונים" לפי הדור ב-DB, וספר לא-מתויג ל"מפרשים נוספים"',
    () async {
      final result = await splitByEra(
        ['רמב"ם', 'ספר החינוך', 'ספר שאינו קיים ב-DB'],
      );

      expect(result['ראשונים'], containsAll(['רמב"ם', 'ספר החינוך']));
      expect(result['מפרשים נוספים'], contains('ספר שאינו קיים ב-DB'));
      // כל ספר משויך לקטגוריה אחת בדיוק - אין אובדן ואין שכפול
      final totalAssigned = result.values.fold<int>(
        0,
        (sum, list) => sum + list.length,
      );
      expect(totalAssigned, 3);
    },
  );

  test(
    'קריאה חוזרת עם אותו קלט משתמשת ב-cache ואינה קוראת שוב מה-DB',
    () async {
      final first = await splitByEra(['רמב"ם']);
      expect(first['ראשונים'], contains('רמב"ם'));

      // משנים את הדור ב-DB ישירות בלי לנקות את ה-cache - קריאה חוזרת אמורה
      // עדיין להחזיר את התוצאה הישנה, כי היא נטענת פעם אחת בלבד.
      final db = await seforimDb.database;
      db.execute(
        "UPDATE book_generation SET generationId = 2 WHERE bookId = "
        "(SELECT id FROM book WHERE title = 'רמב\"ם')",
      );

      final second = await splitByEra(['רמב"ם']);
      expect(
        second['ראשונים'],
        contains('רמב"ם'),
        reason: 'לא אמורה להיטען מחדש בלי clearCommentatorOrderCache',
      );

      // אחרי ניקוי מפורש ה-cache אכן נטען מחדש ומשקף את הנתון העדכני
      clearCommentatorOrderCache();
      final third = await splitByEra(['רמב"ם']);
      expect(third['אחרונים'], contains('רמב"ם'));
    },
  );
}
