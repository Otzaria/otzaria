import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/semantic_search_messages.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/semantic_search/semantic_work_status.dart';
import 'package:otzaria/work_status/work_status_item.dart';

void main() {
  late List<WorkStatusItem> upserts;
  late List<String> removals;
  late int cancels;
  late int retries;
  late SemanticWorkStatusReporter reporter;

  setUp(() {
    upserts = [];
    removals = [];
    cancels = 0;
    retries = 0;
    reporter = SemanticWorkStatusReporter(
      upsert: upserts.add,
      remove: removals.add,
      onCancel: () => cancels++,
      onRetry: () => retries++,
    );
  });

  SemanticAvailability downloading(SemanticDownloadItem item, int step) =>
      SemanticAvailability(
        phase: SemanticAvailabilityPhase.downloading,
        consentGranted: true,
        progress: SemanticDownloadProgress(
          item: item,
          receivedBytes: 40,
          totalBytes: 100,
          step: step,
          stepCount: 3,
        ),
      );

  test('בזמן הורדה: התקדמות כוללת בלי שלבים, וביטול', () {
    reporter.update(downloading(SemanticDownloadItem.vectors, 2));

    final item = upserts.single;
    expect(item.id, kSemanticDataWorkStatusId);
    expect(item.title, contains('נתוני'));
    expect(item.message, 'מוריד את נתוני החיפוש');
    expect(item.progress, 0.4);
    expect(item.kind, WorkStatusKind.running);
    item.actions.single.onPressed();
    expect(cancels, 1);
  });

  test('האחוז מוצג רק בכותרת הכרטיס ולא שוב בתיאור (issue #1967)', () {
    const progress = SemanticDownloadProgress(
      item: SemanticDownloadItem.vectors,
      receivedBytes: 516,
      totalBytes: 1000,
      step: 2,
      stepCount: 3,
    );
    reporter.update(
      const SemanticAvailability(
        phase: SemanticAvailabilityPhase.downloading,
        consentGranted: true,
        progress: progress,
      ),
    );

    // הכותרת מציגה 51% מתוך progress; אחוז מעוגל בתיאור הציג 52%.
    expect(upserts.single.message, 'מוריד את נתוני החיפוש');
    expect(upserts.single.progress, 0.516);
    // ההגדרות וחלון החיפוש מציגים אחוז בטקסט — באותו עיגול כמו הכותרת.
    expect(SemanticSearchMessages.progressPercent(progress), '51');
  });

  test('בהתקנה: בלי אחוז ובלי ערך התקדמות', () {
    reporter.update(
      const SemanticAvailability(
        phase: SemanticAvailabilityPhase.installing,
        consentGranted: true,
        progress: SemanticDownloadProgress(
          item: SemanticDownloadItem.install,
          receivedBytes: 100,
          totalBytes: 100,
          step: 3,
          stepCount: 3,
        ),
      ),
    );

    expect(upserts.single.message, 'מתקין את נתוני החיפוש');
    expect(upserts.single.progress, isNull);
  });

  test('כשל אחרי הורדה נשאר עם ניסיון חוזר', () {
    reporter.update(downloading(SemanticDownloadItem.model, 1));
    reporter.update(
      const SemanticAvailability(
        phase: SemanticAvailabilityPhase.failed,
        consentGranted: true,
        failure: SemanticFailure(SemanticFailureKind.network),
      ),
    );

    final failed = upserts.last;
    expect(failed.kind, WorkStatusKind.failed);
    failed.onTap!();
    failed.actions.single.onPressed();
    expect(retries, 2);
  });

  test('סיום או מנוחה מסירים את הפריט; כשל שלא אחרי הורדה אינו מוצג', () {
    reporter.update(downloading(SemanticDownloadItem.vectors, 2));
    reporter.update(
      const SemanticAvailability(
        phase: SemanticAvailabilityPhase.ready,
        consentGranted: true,
      ),
    );
    expect(removals, [kSemanticDataWorkStatusId]);

    reporter.update(
      const SemanticAvailability(
        phase: SemanticAvailabilityPhase.failed,
        consentGranted: true,
        failure: SemanticFailure(SemanticFailureKind.onnxRuntimeMissing),
      ),
    );
    expect(upserts, hasLength(1));
    expect(removals, hasLength(2));
  });
}
