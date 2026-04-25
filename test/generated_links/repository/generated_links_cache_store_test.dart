import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/generated_links/models/generated_inline_link.dart';
import 'package:otzaria/generated_links/models/generated_link_target.dart';
import 'package:otzaria/generated_links/models/generated_links_cache.dart';
import 'package:otzaria/generated_links/models/generated_links_processing_status.dart';
import 'package:otzaria/generated_links/models/processed_range.dart';
import 'package:otzaria/generated_links/repository/generated_links_cache_store.dart';
import 'package:path/path.dart' as p;

GeneratedLinksCache _makeCache({
  int bookId = 42,
  String fingerprint = 'fp-abc',
  String rulesVersion = '1.0',
  GeneratedLinksProcessingStatus status =
      GeneratedLinksProcessingStatus.complete,
  List<ProcessedRange>? ranges,
  List<GeneratedInlineLink>? links,
}) =>
    GeneratedLinksCache(
      schemaVersion: GeneratedLinksCache.currentSchemaVersion,
      rulesVersion: rulesVersion,
      sourceBookId: bookId,
      sourceFingerprint: fingerprint,
      status: status,
      processedRanges: ranges ?? [const ProcessedRange(0, 99)],
      links: links ?? [],
      updatedAt: DateTime(2025, 1, 1),
    );

GeneratedInlineLink _makeLink(int lineIndex, int start, int end) =>
    GeneratedInlineLink(
      sourceBookId: 42,
      sourceLineIndex: lineIndex,
      start: start,
      end: end,
      matchedText: 'ברכות ב.',
      target: const GeneratedLinkTarget(
        bookTitle: 'ברכות',
        fileType: 'txt',
        targetIndex: 1,
        displayRef: 'ברכות דף ב עמוד א',
      ),
      ruleId: 'gemara.reference.v1',
      confidence: 0.95,
      createdAt: DateTime(2025, 1, 1),
    );

void main() {
  late Directory tmpDir;
  late GeneratedLinksCacheStore store;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('otzaria_cache_test_');
    store = GeneratedLinksCacheStore(basePath: tmpDir.path);
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  group('GeneratedLinksCacheStore', () {
    test('מחזיר null כאשר אין קובץ cache', () async {
      final result = await store.load(999);
      expect(result, isNull);
    });

    test('שמירה וטעינה של cache תקין', () async {
      final cache = _makeCache();
      await store.save(cache);

      final loaded = await store.load(42);
      expect(loaded, isNotNull);
      expect(loaded!.sourceBookId, equals(42));
      expect(loaded.sourceFingerprint, equals('fp-abc'));
      expect(loaded.status, equals(GeneratedLinksProcessingStatus.complete));
    });

    test('כתיבה אטומית: קובץ .tmp לא נשאר אחרי save מוצלח', () async {
      final cache = _makeCache();
      await store.save(cache);

      final tmpFile = File(p.join(tmpDir.path, '42.json.tmp'));
      expect(await tmpFile.exists(), isFalse);

      final finalFile = File(p.join(tmpDir.path, '42.json'));
      expect(await finalFile.exists(), isTrue);
    });

    test('קובץ .tmp שנשאר מ-crash לא מחזיר תוצאה תקינה', () async {
      // מדמה קובץ .tmp שנשאר מ-crash
      final tmpFile = File(p.join(tmpDir.path, '42.json.tmp'));
      await tmpFile.writeAsString('{"corrupt": true}');

      // load מחפש קובץ .json — לא .tmp
      final result = await store.load(42);
      expect(result, isNull);
    });

    test('שמירה עם קישורים ובדיקת סיריאליזציה מלאה', () async {
      final link = _makeLink(5, 10, 18);
      final cache = _makeCache(links: [link]);
      await store.save(cache);

      final loaded = await store.load(42);
      expect(loaded!.links, hasLength(1));
      expect(loaded.links.first.sourceLineIndex, equals(5));
      expect(loaded.links.first.start, equals(10));
      expect(loaded.links.first.end, equals(18));
      expect(loaded.links.first.matchedText, equals('ברכות ב.'));
      expect(loaded.links.first.target.bookTitle, equals('ברכות'));
    });

    test('דחיית cache עם fingerprint שונה', () async {
      final cache = _makeCache(fingerprint: 'fp-original');
      await store.save(cache);

      final loaded = await store.load(42);
      expect(loaded, isNotNull);
      final valid = loaded!.isValidFor('fp-different', '1.0');
      expect(valid, isFalse);
    });

    test('דחיית cache עם rulesVersion שונה', () async {
      final cache = _makeCache(rulesVersion: '1.0');
      await store.save(cache);

      final loaded = await store.load(42);
      final valid = loaded!.isValidFor('fp-abc', '2.0');
      expect(valid, isFalse);
    });

    test('קובץ processing לא נחשב complete', () async {
      final cache = _makeCache(
        status: GeneratedLinksProcessingStatus.processing,
      );
      await store.save(cache);

      final loaded = await store.load(42);
      expect(loaded!.status, equals(GeneratedLinksProcessingStatus.processing));
      expect(
        loaded.status == GeneratedLinksProcessingStatus.complete,
        isFalse,
      );
    });

    test('קובץ stale לא עובר isValidFor', () async {
      final cache = _makeCache(
        status: GeneratedLinksProcessingStatus.stale,
      );
      await store.save(cache);

      final loaded = await store.load(42);
      expect(loaded!.isValidFor('fp-abc', '1.0'), isFalse);
    });

    test('מחיקת cache', () async {
      await store.save(_makeCache());
      await store.delete(42);

      final finalFile = File(p.join(tmpDir.path, '42.json'));
      expect(await finalFile.exists(), isFalse);
    });

    test('listCachedBookIds מחזיר IDs נכונים', () async {
      await store.save(_makeCache(bookId: 1));
      await store.save(_makeCache(bookId: 2));
      await store.save(_makeCache(bookId: 7));

      final ids = await store.listCachedBookIds();
      expect(ids, containsAll([1, 2, 7]));
      expect(ids, hasLength(3));
    });

    test('cleanupStaleTemporaryFiles מנקה קבצי .tmp', () async {
      final tmp1 = File(p.join(tmpDir.path, '10.json.tmp'));
      final tmp2 = File(p.join(tmpDir.path, '20.json.tmp'));
      await tmp1.writeAsString('stale');
      await tmp2.writeAsString('stale');

      await store.cleanupStaleTemporaryFiles();

      expect(await tmp1.exists(), isFalse);
      expect(await tmp2.exists(), isFalse);
    });

    test('טעינת JSON פגום מחזירה null ולא קורסת', () async {
      final file = File(p.join(tmpDir.path, '99.json'));
      await file.writeAsString('{not valid json{{');

      final result = await store.load(99);
      expect(result, isNull);
    });
  });
}
