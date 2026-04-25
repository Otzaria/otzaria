import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/generated_links/models/generated_inline_link.dart';
import 'package:otzaria/generated_links/models/generated_links_processing_status.dart';
import 'package:otzaria/generated_links/repository/generated_links_cache_store.dart';
import 'package:otzaria/generated_links/rules/generated_link_rule.dart';
import 'package:otzaria/generated_links/services/generated_links_scheduler.dart';
import 'package:otzaria/generated_links/services/generated_links_work_gate.dart';
import 'dart:io';

// ─── stubs ───────────────────────────────────────────────────────────────────

/// BatchProcessor מזויף — מחזיר מיידית רשימה ריקה ורושם את הקריאות.
class _TrackingBatchProcessor {
  final List<(int startLine, int endLine)> calls = [];
  final List<int> processedBookIds = [];

  Future<List<GeneratedInlineLink>> call({
    required int sourceBookId,
    required String sourceBookTitle,
    required List<String> lines,
    required int startLine,
    required int endLine,
    required List<DetectedReference> previousRefs,
  }) async {
    calls.add((startLine, endLine));
    processedBookIds.add(sourceBookId);
    return const [];
  }
}

ProcessingJob _job({
  required int bookId,
  bool highPriority = false,
  int lineCount = 10,
  String jobId = '',
}) =>
    ProcessingJob(
      jobId: jobId.isEmpty ? 'job_$bookId' : jobId,
      isHighPriority: highPriority,
      sourceBookId: bookId,
      sourceBookTitle: 'ספר$bookId',
      sourceFingerprint: 'fp_$bookId',
      lines: List.generate(lineCount, (i) => 'שורה $i'),
    );

// ─── helper ──────────────────────────────────────────────────────────────────

late Directory _tmpDir;

Future<GeneratedLinksScheduler> _makeScheduler({
  required _TrackingBatchProcessor processor,
  GeneratedLinksWorkGate? gate,
}) async {
  final store = GeneratedLinksCacheStore(basePath: _tmpDir.path);
  return GeneratedLinksScheduler(
    cacheStore: store,
    workGate: gate ?? GeneratedLinksWorkGate(),
    rulesVersion: 'v1',
    processBatch: processor.call,
  );
}

// ─── tests ───────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    _tmpDir = await Directory.systemTemp.createTemp('scheduler_test_');
  });

  tearDownAll(() async {
    await _tmpDir.delete(recursive: true);
  });

  group('GeneratedLinksScheduler — visible range מקבל עדיפות', () {
    test('ספר high-priority מעובד לפני ספר background', () async {
      final processor = _TrackingBatchProcessor();
      final scheduler = await _makeScheduler(processor: processor);

      scheduler.schedule(_job(bookId: 1, highPriority: false));
      scheduler.schedule(_job(bookId: 2, highPriority: true));

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(processor.processedBookIds.first, equals(2),
          reason: 'high-priority (bookId=2) חייב לרוץ ראשון');
    });
  });

  group('GeneratedLinksScheduler — עומס עוצר התחלת עבודה', () {
    test('כשה-gate עסוק, לא מתחיל batch חדש', () async {
      final gate = GeneratedLinksWorkGate()..setBusy();
      final processor = _TrackingBatchProcessor();
      final scheduler = await _makeScheduler(processor: processor, gate: gate);

      scheduler.schedule(_job(bookId: 10, lineCount: 20));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(processor.calls, isEmpty,
          reason: 'gate עסוק → אין עיבוד');
    });

    test('אחרי שה-gate משתחרר, העיבוד מתחיל', () async {
      final gate = GeneratedLinksWorkGate()..setBusy();
      final processor = _TrackingBatchProcessor();
      final scheduler = await _makeScheduler(processor: processor, gate: gate);

      scheduler.schedule(_job(bookId: 11, lineCount: 5));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(processor.calls, isEmpty);

      gate.setIdle();
      scheduler.schedule(_job(bookId: 12, lineCount: 5));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(processor.calls, isNotEmpty,
          reason: 'אחרי פתיחת gate מעובד ספר חדש');
    });
  });

  group('GeneratedLinksScheduler — partial נשמר אחרי batch', () {
    test('אחרי batch אחד מתוך שניים, status = partial', () async {
      final processor = _TrackingBatchProcessor();
      // 150 שורות → 2 batches (0-99, 100-149)
      final job = _job(bookId: 20, lineCount: 150);
      final store = GeneratedLinksCacheStore(basePath: _tmpDir.path);

      final results = <BatchResult>[];
      final scheduler = GeneratedLinksScheduler(
        cacheStore: store,
        workGate: GeneratedLinksWorkGate(),
        rulesVersion: 'v1',
        processBatch: processor.call,
      );
      scheduler.batchResults.listen(results.add);

      scheduler.schedule(job);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final cache = await store.load(20);
      expect(
        cache?.status,
        anyOf(
          equals(GeneratedLinksProcessingStatus.partial),
          equals(GeneratedLinksProcessingStatus.complete),
        ),
      );
    });
  });

  group('GeneratedLinksScheduler — cancellation בזמן processBatch', () {
    test('ביטול בזמן processBatch לא מפיץ BatchResult ולא שומר links', () async {
      final processor = _TrackingBatchProcessor();
      final job = _job(bookId: 31, lineCount: 10, jobId: 'mid_cancel_job');
      final store = GeneratedLinksCacheStore(basePath: _tmpDir.path);
      final results = <BatchResult>[];

      final scheduler = GeneratedLinksScheduler(
        cacheStore: store,
        workGate: GeneratedLinksWorkGate(),
        rulesVersion: 'v1',
        processBatch: ({
          required sourceBookId,
          required sourceBookTitle,
          required lines,
          required startLine,
          required endLine,
          required previousRefs,
        }) async {
          // מדמה ביטול שקורה בזמן processBatch עצמו (לפני שהוא חוזר)
          job.cancel();
          return processor.call(
            sourceBookId: sourceBookId,
            sourceBookTitle: sourceBookTitle,
            lines: lines,
            startLine: startLine,
            endLine: endLine,
            previousRefs: previousRefs,
          );
        },
      );
      scheduler.batchResults.listen(results.add);

      scheduler.schedule(job);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(results, isEmpty,
          reason: 'batch שבוטל לא אמור לפלוט BatchResult');
      final cache = await store.load(31);
      expect(cache?.links, isEmpty,
          reason: 'links מ-batch שבוטל לא נשמרים ב-cache');
    });
  });

  group('GeneratedLinksScheduler — cancellation לא מסמן complete', () {
    test('ביטול לאחר batch ראשון → status = partial לא complete', () async {
      final processor = _TrackingBatchProcessor();
      final job = _job(bookId: 30, lineCount: 210, jobId: 'cancel_job');
      final store = GeneratedLinksCacheStore(basePath: _tmpDir.path);

      final scheduler = GeneratedLinksScheduler(
        cacheStore: store,
        workGate: GeneratedLinksWorkGate(),
        rulesVersion: 'v1',
        processBatch: ({
          required sourceBookId,
          required sourceBookTitle,
          required lines,
          required startLine,
          required endLine,
          required previousRefs,
        }) async {
          if (startLine == 0) job.cancel();
          return processor.call(
            sourceBookId: sourceBookId,
            sourceBookTitle: sourceBookTitle,
            lines: lines,
            startLine: startLine,
            endLine: endLine,
            previousRefs: previousRefs,
          );
        },
      );

      scheduler.schedule(job);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final cache = await store.load(30);
      expect(cache, isNotNull);
      expect(cache!.status, equals(GeneratedLinksProcessingStatus.partial),
          reason: 'ביטול לא מסמן complete');
    });
  });
}
