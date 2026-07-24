import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/docx_text_cache_entry.dart';
import 'package:path/path.dart' as path;

/// בדיקות שכבת המטמון של תוכן docx (גישה B): שמירה, קריאה, וקריטית —
/// זיהוי-שינוי (קובץ שנערך אינו תקף, כדי שלא יוצג תוכן מיושן).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('docx-text-cache-');
    database = MyDatabase.withPath(path.join(tempDir.path, 'cache.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();
  });

  tearDown(() async {
    database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  DocxTextCacheEntry entry({
    String filePath = '/lib/ספר.docx',
    int fileSize = 1000,
    int lastModified = 5000,
    int converterVersion = 1,
    String text = '<h1>ספר</h1>\nתוכן',
  }) => DocxTextCacheEntry(
    filePath: filePath,
    fileSize: fileSize,
    lastModified: lastModified,
    converterVersion: converterVersion,
    text: text,
    createdAt: 1,
    accessedAt: 1,
  );

  group('DocxTextCache - שמירה וקריאה', () {
    test('רשומה שנשמרה נקראת חזרה עם אותו טקסט', () async {
      await repository.upsertDocxTextCacheEntry(entry());
      final got = await repository.getDocxTextCacheEntry('/lib/ספר.docx');
      expect(got, isNotNull);
      expect(got!.text, '<h1>ספר</h1>\nתוכן');
      expect(got.fileSize, 1000);
      expect(got.lastModified, 5000);
    });

    test('נתיב שלא נשמר מחזיר null', () async {
      final got = await repository.getDocxTextCacheEntry('/lib/אחר.docx');
      expect(got, isNull);
    });
  });

  group('DocxTextCache - זיהוי-שינוי (invalidation)', () {
    test('isValidFor תקף רק כשגודל, זמן-שינוי וגרסת-ממיר זהים', () async {
      await repository.upsertDocxTextCacheEntry(entry(converterVersion: 1));
      final got = (await repository.getDocxTextCacheEntry('/lib/ספר.docx'))!;

      expect(got.isValidFor(1000, 5000, 1), isTrue, reason: 'ללא שינוי → תקף');
      expect(
        got.isValidFor(1000, 9999, 1),
        isFalse,
        reason: 'זמן-שינוי שונה (הקובץ נערך) → לא תקף',
      );
      expect(
        got.isValidFor(2222, 5000, 1),
        isFalse,
        reason: 'גודל שונה → לא תקף',
      );
      expect(
        got.isValidFor(1000, 5000, 2),
        isFalse,
        reason: 'גרסת-ממיר חדשה (שודרג הממיר) → לא תקף, יומר מחדש',
      );
    });

    test(
      'עריכת הקובץ (upsert עם זמן/גודל חדשים) דורסת את התוכן הישן',
      () async {
        await repository.upsertDocxTextCacheEntry(
          entry(text: 'תוכן ישן', lastModified: 5000),
        );
        await repository.upsertDocxTextCacheEntry(
          entry(text: 'תוכן חדש', fileSize: 1500, lastModified: 8000),
        );

        final got = (await repository.getDocxTextCacheEntry('/lib/ספר.docx'))!;
        expect(got.text, 'תוכן חדש');
        expect(got.lastModified, 8000);
        expect(got.fileSize, 1500);
      },
    );

    test('מחיקת רשומה מסירה אותה מהמטמון', () async {
      await repository.upsertDocxTextCacheEntry(entry());
      await repository.deleteDocxTextCacheEntry('/lib/ספר.docx');
      final got = await repository.getDocxTextCacheEntry('/lib/ספר.docx');
      expect(got, isNull);
    });

    test(
      'שדרוג גרסת-ממיר דורס תוכן, ו-createdAt נשמר מהיצירה הראשונה',
      () async {
        await repository.upsertDocxTextCacheEntry(
          const DocxTextCacheEntry(
            filePath: '/x.docx',
            fileSize: 1,
            lastModified: 1,
            converterVersion: 1,
            text: 'ישן',
            createdAt: 111,
            accessedAt: 111,
          ),
        );
        // שדרוג הממיר (גרסה 2) + עדכון זמני הקובץ
        await repository.upsertDocxTextCacheEntry(
          const DocxTextCacheEntry(
            filePath: '/x.docx',
            fileSize: 2,
            lastModified: 2,
            converterVersion: 2,
            text: 'חדש',
            createdAt: 999,
            accessedAt: 999,
          ),
        );

        final got = (await repository.getDocxTextCacheEntry('/x.docx'))!;
        expect(got.text, 'חדש');
        expect(got.converterVersion, 2);
        expect(got.accessedAt, 999, reason: 'accessedAt מתעדכן');
        expect(
          got.createdAt,
          111,
          reason: 'createdAt נשמר מהיצירה הראשונה (לא נדרס)',
        );
      },
    );
  });

  group('DocxTextCache - ניקוי מטמון (TTL)', () {
    test('touch מעדכן את זמן-הגישה (כדי שספר בשימוש לא ייכחד)', () async {
      await repository.upsertDocxTextCacheEntry(
        entry(filePath: '/lib/ב.docx').copyWithAccessed(100),
      );
      await repository.touchDocxTextCacheEntry('/lib/ב.docx', 999999);
      final got = (await repository.getDocxTextCacheEntry('/lib/ב.docx'))!;
      expect(got.accessedAt, 999999);
    });

    test('prune מוחק רשומות ישנות ושומר רשומות שנגעו בהן לאחרונה', () async {
      await repository.upsertDocxTextCacheEntry(
        entry(filePath: '/lib/ישן.docx').copyWithAccessed(1000),
      );
      await repository.upsertDocxTextCacheEntry(
        entry(filePath: '/lib/חדש.docx').copyWithAccessed(50000),
      );

      // מוחק כל מה שנגעו בו לפני 10000
      await repository.pruneDocxTextCacheAccessedBefore(10000);

      expect(await repository.getDocxTextCacheEntry('/lib/ישן.docx'), isNull);
      expect(
        await repository.getDocxTextCacheEntry('/lib/חדש.docx'),
        isNotNull,
      );
    });
  });
}

extension on DocxTextCacheEntry {
  DocxTextCacheEntry copyWithAccessed(int accessedAt) => DocxTextCacheEntry(
    filePath: filePath,
    fileSize: fileSize,
    lastModified: lastModified,
    converterVersion: converterVersion,
    text: text,
    createdAt: createdAt,
    accessedAt: accessedAt,
  );
}
