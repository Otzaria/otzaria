import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/work_status/work_status_item.dart';

/// מזהה פריט חיווי העבודה של עדכון הספרייה.
const kLibraryUpdateWorkStatusId = 'library_update';

/// משך הצגת כשל בדיקת העדכונים לפני סגירה אוטומטית.
const kCheckFailureAutoDismiss = Duration(seconds: 8);

/// משך הצגת כרטיס העדכון לפני שהוא מצטמצם לגלולה בשורת הכותרת.
const kLibraryCardCollapseAfter = Duration(seconds: 6);

/// שם העבודה בגלולת שורת הכותרת.
const _kChipLabel = 'ספרייה';

/// פריט חיווי העבודה לעדכון הספרייה, או `null` כשאין מה להציג.
///
/// [collapsible] — יש שורת כותרת להציג בה גלולה (דסקטופ). בלעדיו הכרטיס אינו
/// מצטמצם, ואין לאן לחזור אחרי סגירה.
///
/// [LibraryUpdateStatus.checking] שקט; עבודה ממשית ממופה למצבים הפעילים.
///
/// [LibraryUpdateStatus.disconnected] מחזיר `null` בכוונה: היעדר אינטרנט אינו
/// כשל לדווח עליו, והסימון היחיד עליו הוא הסמל בכפתור עדכון הספרייה.
WorkStatusItem? libraryUpdateWorkStatusItem(
  LibraryUpdateState state, {
  required VoidCallback onRetry,
  required VoidCallback onChooseDelta,
  required VoidCallback onChooseFullDownload,
  bool collapsible = false,
}) {
  final chipLabel = collapsible ? _kChipLabel : null;
  // שתי אפשרויות שקולות — אין המלצה: הבחירה תלויה במהירות הרשת של המשתמש.
  if (state.status == LibraryUpdateStatus.needsRouteChoice) {
    return WorkStatusItem(
      id: kLibraryUpdateWorkStatusId,
      title: 'עדכון ספרייה',
      message: state.message,
      detail: 'בחר כיצד לעדכן',
      kind: WorkStatusKind.awaitingInput,
      chipLabel: chipLabel,
      actions: [
        WorkStatusAction(
          label: 'עדכון דלתא',
          icon: FluentIcons.arrow_download_24_regular,
          onPressed: onChooseDelta,
        ),
        WorkStatusAction(
          label: 'הורדה מלאה',
          icon: FluentIcons.database_24_regular,
          onPressed: onChooseFullDownload,
        ),
      ],
    );
  }

  if (state.isBusy && state.status != LibraryUpdateStatus.checking) {
    return WorkStatusItem(
      id: kLibraryUpdateWorkStatusId,
      title: 'עדכון ספרייה',
      message: state.message,
      progress: _busyProgress(state),
      chipLabel: chipLabel,
      collapseAfter: collapsible ? kLibraryCardCollapseAfter : null,
    );
  }

  if (state.status == LibraryUpdateStatus.error) {
    // כשל בבדיקה בלבד נסגר מעצמו — סמל הכשל בכפתור עדכון הספרייה נשאר
    // כעוגן לניסיון חוזר. כשל בהורדה/החלה נשאר עד סגירה ידנית.
    return WorkStatusItem(
      id: kLibraryUpdateWorkStatusId,
      title: 'עדכון ספרייה',
      message: _messageWithErrorDetail(state),
      detail: state.canResumeDownload
          ? LibraryMessages.tapToResumeDownload
          : 'לחץ לניסיון חוזר',
      kind: WorkStatusKind.failed,
      chipLabel: chipLabel,
      onTap: onRetry,
      autoDismissAfter: state.isCheckFailure ? kCheckFailureAutoDismiss : null,
    );
  }

  return null;
}

/// מצרף את סיבת הכשל להודעה — בלעדיה המשתמש נותר עם "שגיאה" בלי לדעת מה
/// נכשל. נחתך כדי שהחיווי לא יתנפח על הודעות שגיאה ארוכות.
String _messageWithErrorDetail(LibraryUpdateState state) {
  final error = state.errorMessage?.trim();
  if (error == null || error.isEmpty || error == state.message) {
    return state.message;
  }
  const maxChars = 200;
  final trimmed = error.length <= maxChars
      ? error
      : '${error.substring(0, maxChars)}…';
  return '${state.message}\n$trimmed';
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
