import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/docx_text_cache_entry.dart';
import 'package:otzaria/migration/models/pdf_outline_cache_entry.dart';
import 'package:path/path.dart' as path;

/// #3676: כתיבת מטמון (PDF, docx) ב-cache.db רצה על ה-UI isolate. כשחיבור
/// אחר מחזיק את נעילת הכתיבה, היא אסורה להמתין עד busy_timeout (5 שניות).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;
  late MyDatabase database;
  late SeforimRepository repository;
  late sqlite3.Database otherWriter;

  const filePath = r'C:\books\missing.pdf';
  const maxWait = Duration(seconds: 1);

  PdfOutlineCacheEntry entry() => PdfOutlineCacheEntry(
    filePath: filePath,
    fileSize: 1,
    lastModified: 1,
    outlineJson: PdfOutlineCacheEntry.encodeOutlineEntries(const [
      ('ברכות', 'ברכות', 1),
    ]),
    createdAt: 1,
    accessedAt: 1,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file-cache-dao-busy-');
    dbPath = path.join(tempDir.path, 'cache.db');
    database = MyDatabase.withPath(dbPath);
    repository = SeforimRepository(database);
    await repository.ensureInitialized();
    await repository.upsertPdfOutlineCacheEntry(entry());

    otherWriter = sqlite3.sqlite3.open(dbPath)..execute('BEGIN IMMEDIATE');
  });

  tearDown(() async {
    ReferenceBooksCache.instance
      ..clear()
      ..pdfOutlineCacheRepositoryOverride = null
      ..pdfFileMetadataProviderOverride = null;
    try {
      otherWriter.execute('ROLLBACK');
    } catch (_) {}
    otherWriter.close();
    database.close();
    await tempDir.delete(recursive: true);
  });

  Future<Duration> timed(Future<void> Function() write) async {
    final stopwatch = Stopwatch()..start();
    await expectLater(
      write(),
      throwsA(
        isA<sqlite3.SqliteException>().having(
          (e) => e.resultCode,
          'resultCode',
          sqlite3.SqlError.SQLITE_BUSY,
        ),
      ),
    );
    return stopwatch.elapsed;
  }

  test('כתיבות המטמון נכשלות מיד מול נעילת כתיבה של חיבור אחר', () async {
    final writes = <String, Future<void> Function()>{
      'deleteByFilePath': () => repository.deletePdfOutlineCacheEntry(filePath),
      'upsert': () => repository.upsertPdfOutlineCacheEntry(entry()),
      'updateAccessedAt': () =>
          repository.touchPdfOutlineCacheEntry(filePath, 2),
      'deleteAccessedBefore': () =>
          repository.prunePdfOutlineCacheAccessedBefore(1 << 40),
      'deleteAllExceptFilePaths': () =>
          repository.prunePdfOutlineCacheExceptFilePaths(const {}),
      'docx upsert': () => repository.upsertDocxTextCacheEntry(
        const DocxTextCacheEntry(
          filePath: filePath,
          fileSize: 1,
          lastModified: 1,
          converterVersion: 1,
          text: 'טקסט',
          createdAt: 1,
          accessedAt: 1,
        ),
      ),
      'docx updateAccessedAt': () =>
          repository.touchDocxTextCacheEntry(filePath, 2),
      'docx deleteAccessedBefore': () =>
          repository.pruneDocxTextCacheAccessedBefore(1 << 40),
    };
    for (final MapEntry(key: name, value: write) in writes.entries) {
      expect(await timed(write), lessThan(maxWait), reason: name);
    }

    // ההמתנה לנעילה חוזרת אחרי הכתיבה, לשאר השימושים בחיבור.
    final db = await database.database;
    expect(db.select('PRAGMA busy_timeout').first.values.first, 5000);
  });

  test('ReferenceBooksCache: מחיקת outline של PDF חסר אינה ממתינה', () async {
    final cache = ReferenceBooksCache.instance
      ..clear()
      ..pdfOutlineCacheRepositoryOverride = repository
      ..pdfFileMetadataProviderOverride = (_) async => null;

    final stopwatch = Stopwatch()..start();
    expect(await cache.getPdfOutlineEntries(filePath), isEmpty);
    expect(stopwatch.elapsed, lessThan(maxWait));

    otherWriter.execute('ROLLBACK');
    expect(await repository.getPdfOutlineCacheEntry(filePath), isNotNull);
  });
}
