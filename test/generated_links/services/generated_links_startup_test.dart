import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/generated_links/models/generated_inline_link.dart';
import 'package:otzaria/generated_links/repository/generated_links_cache_store.dart';
import 'package:otzaria/generated_links/rules/generated_link_rule.dart';
import 'package:otzaria/generated_links/services/generated_links_scheduler.dart';
import 'package:otzaria/generated_links/services/generated_links_work_gate.dart';

// ─── helpers ─────────────────────────────────────────────────────────────────

late Directory _tmpDir;

class _TrackingProcessor {
  final List<int> processedBookIds = [];

  Future<List<GeneratedInlineLink>> call({
    required int sourceBookId,
    required String sourceBookTitle,
    required List<String> lines,
    required int startLine,
    required int endLine,
    required List<DetectedReference> previousRefs,
  }) async {
    processedBookIds.add(sourceBookId);
    return const [];
  }
}

ProcessingJob _bgJob(int bookId, {int lines = 20}) => ProcessingJob(
      jobId: 'history_$bookId',
      isHighPriority: false,
      sourceBookId: bookId,
      sourceBookTitle: 'ספר$bookId',
      sourceFingerprint: '$bookId:$lines',
      lines: List.generate(lines, (i) => 'שורה $i'),
    );

ProcessingJob _hiJob(int bookId, {int lines = 20}) => ProcessingJob(
      jobId: 'book_${bookId}_open',
      isHighPriority: true,
      sourceBookId: bookId,
      sourceBookTitle: 'ספר$bookId',
      sourceFingerprint: '$bookId:$lines',
      lines: List.generate(lines, (i) => 'שורה $i'),
    );

// ─── tests ───────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _tmpDir = await Directory.systemTemp.createTemp('gl_startup_test_');
  });

  tearDownAll(() async {
    await _tmpDir.delete(recursive: true);
  });

  group('שלב 6 — GeneratedLinksWorkGate + scheduler startup', () {
    test('work gate עסוק: scheduler לא מתחיל batches', () async {
      final gate = GeneratedLinksWorkGate()..setBusy();
      final processor = _TrackingProcessor();
      final store = GeneratedLinksCacheStore(basePath: _tmpDir.path);

      final scheduler = GeneratedLinksScheduler(
        cacheStore: store,
        workGate: gate,
        rulesVersion: 'v1',
        processBatch: processor.call,
      );

      scheduler.schedule(_bgJob(10));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(processor.processedBookIds, isEmpty,
          reason: 'gate עסוק: scheduler אסור שיעבד');
    });

    test('לאחר setIdle: scheduler מעבד את התור', () async {
      final gate = GeneratedLinksWorkGate()..setBusy();
      final processor = _TrackingProcessor();
      final store = GeneratedLinksCacheStore(basePath: _tmpDir.path);

      final scheduler = GeneratedLinksScheduler(
        cacheStore: store,
        workGate: gate,
        rulesVersion: 'v1',
        processBatch: processor.call,
      );

      scheduler.schedule(_bgJob(11));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(processor.processedBookIds, isEmpty, reason: 'עדיין עסוק');

      gate.setIdle();
      scheduler.resume(); // מעיר את הלולאה מבלי לדרוש job נוסף
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(processor.processedBookIds, contains(11),
          reason: 'לאחר setIdle + resume, ה-job הישן חייב להיות מעובד');
    });

    test('ספר פתוח מקבל עדיפות על פני ספרי היסטוריה', () async {
      final gate = GeneratedLinksWorkGate();
      final processor = _TrackingProcessor();
      final store = GeneratedLinksCacheStore(basePath: _tmpDir.path);

      final results = <int>[];
      final scheduler = GeneratedLinksScheduler(
        cacheStore: store,
        workGate: gate,
        rulesVersion: 'v1',
        processBatch: ({
          required sourceBookId,
          required sourceBookTitle,
          required lines,
          required startLine,
          required endLine,
          required previousRefs,
        }) async {
          results.add(sourceBookId);
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

      // מתזמנים בגל אחד: background ראשון, אחר כך high-priority
      scheduler.schedule(_bgJob(20));
      scheduler.schedule(_bgJob(21));
      scheduler.schedule(_hiJob(99)); // ספר פתוח

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(results.isNotEmpty, isTrue);
      expect(results.first, equals(99),
          reason: 'ספר פתוח (high priority) חייב להיות ראשון');
    });
  });

  group('שלב 6 — work gate עם כמה מקורות עומס', () {
    test('שני setBusy דורשים שני setIdle לפני שה-gate נפתח', () async {
      final gate = GeneratedLinksWorkGate();
      gate.setBusy(); // indexing
      gate.setBusy(); // file sync

      expect(gate.isIdle, isFalse, reason: 'שניהם פעילים');

      gate.setIdle(); // indexing סיים
      expect(gate.isIdle, isFalse,
          reason: 'עדיין יש file sync פעיל — gate חייב להישאר סגור');

      gate.setIdle(); // file sync סיים
      expect(gate.isIdle, isTrue,
          reason: 'שניהם סיימו — gate חייב לפתוח');
    });

    test('scheduler לא מתעורר כשרק חלק ממקורות העומס סיימו', () async {
      final gate = GeneratedLinksWorkGate();
      gate.setBusy(); // indexing
      gate.setBusy(); // file sync
      final processor = _TrackingProcessor();
      final store = GeneratedLinksCacheStore(basePath: _tmpDir.path);

      final scheduler = GeneratedLinksScheduler(
        cacheStore: store,
        workGate: gate,
        rulesVersion: 'v1',
        processBatch: processor.call,
      );

      scheduler.schedule(_bgJob(30));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      gate.setIdle(); // indexing סיים
      scheduler.resume();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(processor.processedBookIds, isEmpty,
          reason: 'file sync עדיין רץ — scheduler אסור שיתעורר');

      gate.setIdle(); // file sync סיים
      scheduler.resume();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(processor.processedBookIds, contains(30),
          reason: 'כולם סיימו — scheduler חייב לעבד');
    });
  });
}
