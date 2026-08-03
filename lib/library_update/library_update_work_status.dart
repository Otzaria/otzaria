import 'package:flutter/foundation.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/work_status/work_status_item.dart';

/// מזהה פריט חיווי העבודה של עדכון הספרייה.
const kLibraryUpdateWorkStatusId = 'library_update';

/// פריט חיווי העבודה לעדכון הספרייה, או `null` כשאין מה להציג.
///
/// [LibraryUpdateStatus.disconnected] מחזיר `null` בכוונה: היעדר אינטרנט אינו
/// כשל לדווח עליו, והסימון היחיד עליו הוא הסמל בכפתור עדכון הספרייה.
WorkStatusItem? libraryUpdateWorkStatusItem(
  LibraryUpdateState state, {
  required VoidCallback onRetry,
}) {
  if (state.isBusy) {
    return WorkStatusItem(
      id: kLibraryUpdateWorkStatusId,
      title: 'עדכון ספרייה',
      message: state.message,
      progress: _busyProgress(state),
    );
  }

  if (state.status == LibraryUpdateStatus.error) {
    return WorkStatusItem(
      id: kLibraryUpdateWorkStatusId,
      title: 'עדכון ספרייה',
      message: state.message,
      detail: 'לחץ לניסיון חוזר',
      kind: WorkStatusKind.failed,
      onTap: onRetry,
    );
  }

  return null;
}

/// מד הבתים תקף רק בזמן ההורדה — בשלבים הבאים הוא שארית דבוקה על 100%.
/// ב-apply המדד הוא applyProgress (null = אין מדידה).
double? _busyProgress(LibraryUpdateState state) {
  switch (state.status) {
    case LibraryUpdateStatus.downloading:
      final total = state.bytesTotal ?? 0;
      return total > 0
          ? ((state.bytesDownloaded ?? 0) / total).clamp(0.0, 1.0)
          : null;
    case LibraryUpdateStatus.applying:
      return state.applyProgress;
    default:
      return null;
  }
}
