import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/generated_links/models/generated_inline_link.dart';
import 'package:otzaria/generated_links/models/generated_links_cache.dart';
import 'package:otzaria/generated_links/models/generated_links_processing_status.dart';
import 'package:otzaria/generated_links/models/processed_range.dart';
import 'package:otzaria/generated_links/repository/generated_links_cache_store.dart';
import 'package:otzaria/generated_links/rules/generated_link_rule.dart';
import 'package:otzaria/generated_links/services/generated_links_work_gate.dart';

/// תיאור עבודת עיבוד לספר אחד.
class ProcessingJob {
  final String jobId;

  /// true = ספר פתוח כרגע (visible range) — מקבל עדיפות.
  final bool isHighPriority;

  final int sourceBookId;
  final String sourceBookTitle;
  final String sourceFingerprint;
  final List<String> lines;

  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;

  ProcessingJob({
    required this.jobId,
    required this.isHighPriority,
    required this.sourceBookId,
    required this.sourceBookTitle,
    required this.sourceFingerprint,
    required this.lines,
  });
}

/// תוצאת batch — מועברת ל-callback אחרי שמירת ה-cache.
class BatchResult {
  final int sourceBookId;
  final List<GeneratedInlineLink> newLinks;
  const BatchResult(this.sourceBookId, this.newLinks);
}

/// מריץ עיבוד קישורים בתור עם עדיפות.
///
/// עבודות high-priority (ספר פתוח) נכנסות לראש התור.
/// אחרי כל batch נשמר cache חלקי ומוצא [batchResults].
/// כשה-[workGate] עסוק, ה-scheduler מפסיק לפני ה-batch הבא.
class GeneratedLinksScheduler {
  static const int defaultBatchSize = 100;

  final GeneratedLinksCacheStore cacheStore;
  final GeneratedLinksWorkGate workGate;
  final String rulesVersion;

  /// פונקציית עיבוד batch — ניתנת להזרקה לבדיקות.
  final Future<List<GeneratedInlineLink>> Function({
    required int sourceBookId,
    required String sourceBookTitle,
    required List<String> lines,
    required int startLine,
    required int endLine,
    required List<DetectedReference> previousRefs,
  }) processBatch;

  final _batchResultController =
      StreamController<BatchResult>.broadcast();

  /// Stream של תוצאות; ה-BLoC יכול להאזין ולהפיץ events.
  Stream<BatchResult> get batchResults => _batchResultController.stream;

  final List<ProcessingJob> _highQueue = [];
  final List<ProcessingJob> _backgroundQueue = [];
  bool _running = false;
  ProcessingJob? _currentJob;

  GeneratedLinksScheduler({
    required this.cacheStore,
    required this.workGate,
    required this.rulesVersion,
    required this.processBatch,
  });

  /// מוסיפה עבודה לתור. עדיפות גבוהה → ראש תור.
  void schedule(ProcessingJob job) {
    if (job.isHighPriority) {
      _highQueue.insert(0, job);
    } else {
      _backgroundQueue.add(job);
    }
    _maybeRun();
  }

  /// מבטלת עבודה לפי jobId — כולל עבודה שרצה כרגע.
  void cancel(String jobId) {
    if (_currentJob?.jobId == jobId) _currentJob!.cancel();
    for (final q in [_highQueue, _backgroundQueue]) {
      for (final job in q) {
        if (job.jobId == jobId) job.cancel();
      }
    }
  }

  /// מעיר את לולאת העיבוד לאחר שה-work gate חזר ל-idle.
  void resume() => _maybeRun();

  void dispose() {
    _batchResultController.close();
  }

  void _maybeRun() {
    if (_running) return;
    _running = true;
    // defer so callers that batch-schedule multiple jobs run first
    Future.microtask(() => _runLoop().whenComplete(() => _running = false));
  }

  Future<void> _runLoop() async {
    while (true) {
      if (!workGate.isIdle) break;

      final job = _nextJob();
      if (job == null) break;
      if (job.isCancelled) continue;

      _currentJob = job;
      await _processJob(job);
      _currentJob = null;
    }
  }

  ProcessingJob? _nextJob() {
    // הסר מבוטלים
    _highQueue.removeWhere((j) => j.isCancelled);
    _backgroundQueue.removeWhere((j) => j.isCancelled);

    if (_highQueue.isNotEmpty) return _highQueue.removeAt(0);
    if (_backgroundQueue.isNotEmpty) return _backgroundQueue.removeAt(0);
    return null;
  }

  Future<void> _processJob(ProcessingJob job) async {
    // טעינת cache קיים או יצירת חדש
    GeneratedLinksCache cache = await cacheStore.load(job.sourceBookId) ??
        GeneratedLinksCache(
          schemaVersion: GeneratedLinksCache.currentSchemaVersion,
          rulesVersion: rulesVersion,
          sourceBookId: job.sourceBookId,
          sourceFingerprint: job.sourceFingerprint,
          status: GeneratedLinksProcessingStatus.processing,
          processedRanges: [],
          links: [],
          updatedAt: DateTime.now(),
        );

    // פסילת cache ישן אם fingerprint או גרסת כללים השתנו
    if (!cache.isValidFor(job.sourceFingerprint, rulesVersion)) {
      cache = cache.copyWith(
        status: GeneratedLinksProcessingStatus.processing,
        links: [],
        processedRanges: [],
        rulesVersion: rulesVersion,
        updatedAt: DateTime.now(),
      );
    }

    await cacheStore.save(cache);

    final allLinks = List<GeneratedInlineLink>.from(cache.links);
    final processedRanges = List<ProcessedRange>.from(cache.processedRanges);
    final totalLines = job.lines.length;

    for (var start = 0; start < totalLines; start += defaultBatchSize) {
      // בדיקות ביטול ועומס לפני כל batch
      if (job.isCancelled) {
        await _saveAs(cache, allLinks, processedRanges,
            GeneratedLinksProcessingStatus.partial);
        return;
      }
      if (!workGate.isIdle) {
        await _saveAs(cache, allLinks, processedRanges,
            GeneratedLinksProcessingStatus.partial);
        return;
      }

      final end = (start + defaultBatchSize - 1).clamp(0, totalLines - 1);

      // דלג על טווחים שכבר עובדו
      if (processedRanges.any((r) => r.contains(start) && r.contains(end))) {
        continue;
      }

      // בנה previousRefs מ-links שכבר נוצרו
      final prevRefs = allLinks
          .map((l) => DetectedReference(
                sourceLineIndex: l.sourceLineIndex,
                start: l.start,
                end: l.end,
                matchedText: l.matchedText,
                targetBookTitle: l.target.bookTitle,
                targetRefText: l.target.displayRef,
                ruleId: l.ruleId,
                confidence: l.confidence,
              ))
          .toList();

      List<GeneratedInlineLink> batchLinks;
      try {
        batchLinks = await processBatch(
          sourceBookId: job.sourceBookId,
          sourceBookTitle: job.sourceBookTitle,
          lines: job.lines,
          startLine: start,
          endLine: end,
          previousRefs: prevRefs,
        );
      } catch (e) {
        debugPrint('[GeneratedLinksScheduler] batch error: $e');
        await _saveAs(cache, allLinks, processedRanges,
            GeneratedLinksProcessingStatus.failed);
        return;
      }

      // בדיקת ביטול/gate אחרי חזרת processBatch — מונע שמירת/פליטת תוצאות מ-batch שבוטל
      if (job.isCancelled || !workGate.isIdle) {
        await _saveAs(cache, allLinks, processedRanges,
            GeneratedLinksProcessingStatus.partial);
        return;
      }

      allLinks.addAll(batchLinks);
      processedRanges.add(ProcessedRange(start, end));

      final isLast = end >= totalLines - 1;
      final newStatus = isLast
          ? GeneratedLinksProcessingStatus.complete
          : GeneratedLinksProcessingStatus.partial;

      cache = await _saveAs(cache, allLinks, processedRanges, newStatus);
      _batchResultController.add(BatchResult(job.sourceBookId, batchLinks));
    }
  }

  Future<GeneratedLinksCache> _saveAs(
    GeneratedLinksCache cache,
    List<GeneratedInlineLink> links,
    List<ProcessedRange> ranges,
    GeneratedLinksProcessingStatus status,
  ) async {
    final updated = cache.copyWith(
      status: status,
      links: links,
      processedRanges: ranges,
      updatedAt: DateTime.now(),
    );
    await cacheStore.save(updated);
    return updated;
  }
}
