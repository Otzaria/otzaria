import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/pdf_outline_cache_entry.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;
  late ReferenceBooksCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'reference-books-cache-persistent-',
    );
    database = MyDatabase.withPath(path.join(tempDir.path, 'test.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();

    cache = ReferenceBooksCache.instance;
    cache.clear();
    cache.pdfOutlineCacheRepositoryOverride = repository;
    cache.pdfFileMetadataProviderOverride = null;
    cache.nowProviderOverride = () => 123456789;
  });

  tearDown(() async {
    cache.clear();
    cache.pdfOutlineCacheRepositoryOverride = null;
    cache.pdfFileMetadataProviderOverride = null;
    cache.nowProviderOverride = null;
    database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PdfOutlineCacheEntry encode/decode', () {
    test('encode מייצר מעטפה עם שדה הגרסה הנוכחית', () {
      final json = PdfOutlineCacheEntry.encodeOutlineEntries(
        const [('ברכות', 'ברכות', 1)],
      );

      final decoded = jsonDecode(json);
      expect(decoded, isA<Map>());
      expect(
        (decoded as Map)['v'],
        equals(PdfOutlineCacheEntry.currentSchemaVersion),
      );
      expect(decoded['entries'], isA<List>());
    });

    test('decode של פורמט legacy (List ישנה ללא v) מחזיר פריטים', () {
      final legacyJson = jsonEncode([
        {'n': 'ברכות', 'o': 'ברכות', 'p': 1},
        {'n': 'פרק א', 'o': 'פרק א', 'p': 3},
      ]);

      final entries = PdfOutlineCacheEntry.decodeOutlineEntries(legacyJson);

      expect(
        entries,
        equals(const [
          ('ברכות', 'ברכות', 1),
          ('פרק א', 'פרק א', 3),
        ]),
      );
    });

    test('decode של JSON עם גרסה לא תואמת זורק FormatException', () {
      final futureJson = jsonEncode({
        'v': PdfOutlineCacheEntry.currentSchemaVersion + 1,
        'entries': [
          {'n': 'ברכות', 'o': 'ברכות', 'p': 1},
        ],
      });

      expect(
        () => PdfOutlineCacheEntry.decodeOutlineEntries(futureJson),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'מעטפה תקפה עם entries לא-רשימה נחשבת corruption וזורקת FormatException',
      () {
        final malformedJson = jsonEncode({
          'v': PdfOutlineCacheEntry.currentSchemaVersion,
          'entries': 'not-a-list',
        });

        expect(
          () => PdfOutlineCacheEntry.decodeOutlineEntries(malformedJson),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('payload עם top-level שאינו list או object זורק FormatException', () {
      expect(
        () => PdfOutlineCacheEntry.decodeOutlineEntries('"לא תקין"'),
        throwsA(isA<FormatException>()),
      );
    });

    test('legacy List נתמך כל עוד currentSchemaVersion == 1', () {
      // סנטינל: כשמעלים את currentSchemaVersion, ה-fallback הזה הופך
      // לדחיה אוטומטית של רשומות legacy. אם משנים את הקבוע, יש לוודא
      // שזו עדיין ההתנהגות הרצויה ולעדכן את הטסט הזה במודע.
      expect(PdfOutlineCacheEntry.currentSchemaVersion, equals(1));
    });
  });

  group('ReferenceBooksCache persistent PDF outline cache', () {
    test(
      'matching metadata loads outline from SQLite without parsing',
      () async {
        const expectedEntries = [
          ('ברכות', 'ברכות', 1),
          ('פרק א', 'פרק א', 3),
        ];
        await repository.upsertPdfOutlineCacheEntry(
          PdfOutlineCacheEntry(
            filePath: '/cached.pdf',
            fileSize: 10,
            lastModified: 20,
            outlineJson: PdfOutlineCacheEntry.encodeOutlineEntries(
              expectedEntries,
            ),
            createdAt: 1,
            accessedAt: 2,
          ),
        );

        cache.pdfFileMetadataProviderOverride = (_) async => (
          fileSize: 10,
          lastModified: 20,
        );
        var parserCalled = false;
        cache.pdfOutlineParser = (_) async {
          parserCalled = true;
          return const [('חדש', 'חדש', 9)];
        };

        final result = await cache.getPdfOutlineEntries('/cached.pdf');
        await Future<void>.delayed(Duration.zero);

        expect(result, equals(expectedEntries));
        expect(parserCalled, isFalse);
        final row = await repository.getPdfOutlineCacheEntry('/cached.pdf');
        expect(row, isNotNull);
        expect(row!.accessedAt, equals(123456789));
      },
    );

    test('metadata mismatch reparses and updates SQLite cache', () async {
      await repository.upsertPdfOutlineCacheEntry(
        PdfOutlineCacheEntry(
          filePath: '/stale.pdf',
          fileSize: 10,
          lastModified: 20,
          outlineJson: PdfOutlineCacheEntry.encodeOutlineEntries(
            const [('ישן', 'ישן', 1)],
          ),
          createdAt: 1,
          accessedAt: 2,
        ),
      );

      cache.pdfFileMetadataProviderOverride = (_) async => (
        fileSize: 11,
        lastModified: 21,
      );
      const reparsedEntries = [('חדש', 'חדש', 7)];
      cache.pdfOutlineParser = (_) async => reparsedEntries;

      final result = await cache.getPdfOutlineEntries('/stale.pdf');

      expect(result, equals(reparsedEntries));
      final row = await repository.getPdfOutlineCacheEntry('/stale.pdf');
      expect(row, isNotNull);
      expect(row!.fileSize, equals(11));
      expect(row.lastModified, equals(21));
      expect(row.decodeEntries(), equals(reparsedEntries));
      expect(row.createdAt, equals(123456789));
      expect(row.accessedAt, equals(123456789));
    });

    test('clear מנקה רק זיכרון — שליפה חוזרת נטענת מה-SQLite', () async {
      cache.pdfFileMetadataProviderOverride = (_) async => (
        fileSize: 5,
        lastModified: 6,
      );
      var parserCalls = 0;
      const expectedEntries = [('מסכת', 'מסכת', 4)];
      cache.pdfOutlineParser = (_) async {
        parserCalls++;
        return expectedEntries;
      };

      final first = await cache.getPdfOutlineEntries('/persisted.pdf');
      expect(first, equals(expectedEntries));
      expect(parserCalls, equals(1));

      cache.clear();
      cache.pdfOutlineCacheRepositoryOverride = repository;
      cache.pdfFileMetadataProviderOverride = (_) async => (
        fileSize: 5,
        lastModified: 6,
      );
      cache.nowProviderOverride = () => 123456789;
      cache.pdfOutlineParser = (_) async {
        parserCalls++;
        return const [('לא אמור', 'לא אמור', 99)];
      };

      final second = await cache.getPdfOutlineEntries('/persisted.pdf');

      expect(second, equals(expectedEntries));
      expect(
        parserCalls,
        equals(1),
        reason: 'השליפה השנייה צריכה להגיע מה-persistent cache',
      );
    });

    test('קובץ חסר מחזיר ריק ומוחק cache stale מה-SQLite', () async {
      await repository.upsertPdfOutlineCacheEntry(
        PdfOutlineCacheEntry(
          filePath: '/missing.pdf',
          fileSize: 10,
          lastModified: 20,
          outlineJson: PdfOutlineCacheEntry.encodeOutlineEntries(
            const [('ישן', 'ישן', 1)],
          ),
          createdAt: 1,
          accessedAt: 2,
        ),
      );

      cache.pdfFileMetadataProviderOverride = (_) async => null;
      cache.pdfOutlineParser = (_) async => throw StateError('must not parse');

      final result = await cache.getPdfOutlineEntries('/missing.pdf');

      expect(result, isEmpty);
      expect(await repository.getPdfOutlineCacheEntry('/missing.pdf'), isNull);
    });

    test(
      'כשל metadata זמני משתמש ב-persistent cache הקיים ואינו מוחק אותו',
      () async {
        const expectedEntries = [('שמור', 'שמור', 8)];
        await repository.upsertPdfOutlineCacheEntry(
          PdfOutlineCacheEntry(
            filePath: '/flaky.pdf',
            fileSize: 10,
            lastModified: 20,
            outlineJson: PdfOutlineCacheEntry.encodeOutlineEntries(
              expectedEntries,
            ),
            createdAt: 1,
            accessedAt: 2,
          ),
        );

        cache.pdfFileMetadataProviderOverride = (_) async {
          throw const FileSystemException('temporary I/O failure');
        };
        var parserCalled = false;
        cache.pdfOutlineParser = (_) async {
          parserCalled = true;
          return const [('חדש', 'חדש', 9)];
        };

        final result = await cache.getPdfOutlineEntries('/flaky.pdf');
        await Future<void>.delayed(Duration.zero);

        expect(result, equals(expectedEntries));
        expect(parserCalled, isFalse);
        expect(
          await repository.getPdfOutlineCacheEntry('/flaky.pdf'),
          isNotNull,
        );
      },
    );

    test('pruning לפי TTL מוחק entries ישנים ושומר חדשים', () async {
      final nowMillis = const Duration(days: 200).inMilliseconds;
      cache.nowProviderOverride = () => nowMillis;

      await repository.upsertPdfOutlineCacheEntry(
        PdfOutlineCacheEntry(
          filePath: '/old.pdf',
          fileSize: 10,
          lastModified: 20,
          outlineJson: PdfOutlineCacheEntry.encodeOutlineEntries(
            const [('ישן', 'ישן', 1)],
          ),
          createdAt: 1,
          accessedAt: nowMillis - const Duration(days: 91).inMilliseconds,
        ),
      );
      await repository.upsertPdfOutlineCacheEntry(
        PdfOutlineCacheEntry(
          filePath: '/recent.pdf',
          fileSize: 10,
          lastModified: 20,
          outlineJson: PdfOutlineCacheEntry.encodeOutlineEntries(
            const [('חדש', 'חדש', 2)],
          ),
          createdAt: 1,
          accessedAt: nowMillis - const Duration(days: 10).inMilliseconds,
        ),
      );

      await cache.prunePersistentPdfOutlineCacheForTesting(
        knownFilePaths: {'/old.pdf', '/recent.pdf'},
      );

      expect(await repository.getPdfOutlineCacheEntry('/old.pdf'), isNull);
      expect(
        await repository.getPdfOutlineCacheEntry('/recent.pdf'),
        isNotNull,
      );
    });

    test(
      'רשומה עם schemaVersion לא תואם נמחקת ונבנית מחדש דרך parser',
      () async {
        final forwardCompatibleJson = jsonEncode({
          'v': PdfOutlineCacheEntry.currentSchemaVersion + 1,
          'entries': [
            {'n': 'ישן', 'o': 'ישן', 'p': 1},
          ],
        });
        await repository.upsertPdfOutlineCacheEntry(
          PdfOutlineCacheEntry(
            filePath: '/incompatible.pdf',
            fileSize: 10,
            lastModified: 20,
            outlineJson: forwardCompatibleJson,
            createdAt: 1,
            accessedAt: 2,
          ),
        );

        cache.pdfFileMetadataProviderOverride = (_) async => (
          fileSize: 10,
          lastModified: 20,
        );
        const reparsedEntries = [('חדש', 'חדש', 7)];
        var parserCalls = 0;
        cache.pdfOutlineParser = (_) async {
          parserCalls++;
          return reparsedEntries;
        };

        final result = await cache.getPdfOutlineEntries('/incompatible.pdf');

        expect(result, equals(reparsedEntries));
        expect(parserCalls, equals(1));
        final row = await repository.getPdfOutlineCacheEntry(
          '/incompatible.pdf',
        );
        expect(row, isNotNull);
        expect(row!.decodeEntries(), equals(reparsedEntries));
      },
    );

    test('pruning לפי known file paths מוחק entries שכבר לא ידועים', () async {
      await repository.upsertPdfOutlineCacheEntry(
        PdfOutlineCacheEntry(
          filePath: '/keep.pdf',
          fileSize: 10,
          lastModified: 20,
          outlineJson: PdfOutlineCacheEntry.encodeOutlineEntries(
            const [('שמור', 'שמור', 1)],
          ),
          createdAt: 1,
          accessedAt: 100,
        ),
      );
      await repository.upsertPdfOutlineCacheEntry(
        PdfOutlineCacheEntry(
          filePath: '/gone.pdf',
          fileSize: 10,
          lastModified: 20,
          outlineJson: PdfOutlineCacheEntry.encodeOutlineEntries(
            const [('מחוק', 'מחוק', 2)],
          ),
          createdAt: 1,
          accessedAt: 100,
        ),
      );

      await cache.prunePersistentPdfOutlineCacheForTesting(
        knownFilePaths: {'/keep.pdf'},
        ttl: const Duration(days: 3650),
      );

      expect(await repository.getPdfOutlineCacheEntry('/keep.pdf'), isNotNull);
      expect(await repository.getPdfOutlineCacheEntry('/gone.pdf'), isNull);
    });
  });
}
