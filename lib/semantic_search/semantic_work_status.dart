import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/core/messages/semantic_search_messages.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_failure.dart';
import 'package:otzaria/work_status/work_status_item.dart';

/// מזהה פריט חיווי העבודה של הורדת נתוני החיפוש הסמנטי.
const kSemanticDataWorkStatusId = 'semantic_data';

/// האם [phase] הוא עבודת הורדה או התקנה שרצה.
bool isSemanticJobPhase(SemanticAvailabilityPhase phase) =>
    phase == SemanticAvailabilityPhase.downloading ||
    phase == SemanticAvailabilityPhase.installing;

/// פריט החיווי להורדת נתוני החיפוש הסמנטי, או `null` כשאין מה להציג.
///
/// כשל מוצג רק כש-[afterJob] — כלומר בסוף עבודה, ולא כשל פתיחה שאינו הורדה.
WorkStatusItem? semanticWorkStatusItem(
  SemanticAvailability availability, {
  required bool afterJob,
  required VoidCallback onCancel,
  required VoidCallback onRetry,
}) {
  final title = SemanticSearchMessages.withName('נתוני {name}');
  if (isSemanticJobPhase(availability.phase)) {
    final progress = availability.progress;
    final installing =
        availability.phase == SemanticAvailabilityPhase.installing;
    return WorkStatusItem(
      id: kSemanticDataWorkStatusId,
      title: title,
      // האחוז מוצג בכותרת הכרטיס מתוך progress; אחוז כפול כאן מתעגל אחרת ממנו.
      message: progress != null
          ? SemanticSearchMessages.progressAction(progress)
          : installing
          ? SemanticSearchMessages.installingData
          : SemanticSearchMessages.downloadingData,
      // בהתקנה אין מדידה — טבעת בלי ערך.
      progress: installing ? null : progress?.fraction,
      actions: [
        WorkStatusAction(
          label: 'ביטול',
          icon: FluentIcons.dismiss_24_regular,
          onPressed: onCancel,
        ),
      ],
    );
  }
  if (availability.phase == SemanticAvailabilityPhase.failed && afterJob) {
    return WorkStatusItem(
      id: kSemanticDataWorkStatusId,
      title: title,
      message: SemanticSearchMessages.withName(
        SemanticSearchMessages.failure(
          availability.failure?.kind ?? SemanticFailureKind.internal,
        ),
      ),
      detail: 'לחץ לניסיון חוזר',
      kind: WorkStatusKind.failed,
      onTap: onRetry,
      actions: [
        WorkStatusAction(
          label: 'נסה שוב',
          icon: FluentIcons.arrow_clockwise_24_regular,
          onPressed: onRetry,
        ),
      ],
    );
  }
  return null;
}

/// מתרגם את רצף מצבי הזמינות לפריט בחיווי העבודה: מוסיף/מעדכן בזמן עבודה,
/// משאיר כשל שבא אחריה, ומסיר בכל מצב אחר.
class SemanticWorkStatusReporter {
  SemanticWorkStatusReporter({
    required this.upsert,
    required this.remove,
    required this.onCancel,
    required this.onRetry,
  });

  final void Function(WorkStatusItem item) upsert;
  final void Function(String id) remove;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  bool _afterJob = false;

  void update(SemanticAvailability availability) {
    final running = isSemanticJobPhase(availability.phase);
    final item = semanticWorkStatusItem(
      availability,
      afterJob: _afterJob,
      onCancel: onCancel,
      onRetry: onRetry,
    );
    if (running) {
      _afterJob = true;
    } else if (availability.phase != SemanticAvailabilityPhase.failed) {
      _afterJob = false;
    }
    if (item == null) {
      remove(kSemanticDataWorkStatusId);
    } else {
      upsert(item);
    }
  }
}
