part of 'library_update_bloc.dart';

sealed class LibraryUpdateEvent extends Equatable {
  const LibraryUpdateEvent();
  @override
  List<Object?> get props => [];
}

/// בקשה לבדוק ולהחיל עדכון. מסלול דלתא מוחל אוטומטית; מסלול הורדה מלאה
/// עוצר וממתין ל-[ConfirmFullDownload].
class StartLibraryUpdate extends LibraryUpdateEvent {
  const StartLibraryUpdate();
}

/// אישור המשתמש לבצע הורדה מלאה (אחרי שהוצג גודל ההורדה).
class ConfirmFullDownload extends LibraryUpdateEvent {
  const ConfirmFullDownload();
}

/// המשתמש בחר לדחות הורדה מלאה ולהישאר עם הגרסה הנוכחית.
class DeclineFullDownload extends LibraryUpdateEvent {
  const DeclineFullDownload();
}

/// בקשה לעצור עדכון פעיל.
class CancelLibraryUpdate extends LibraryUpdateEvent {
  const CancelLibraryUpdate();
}

/// איפוס ה-state חזרה ל-idle (לניקוי הודעת סיום/שגיאה).
class ResetLibraryUpdate extends LibraryUpdateEvent {
  const ResetLibraryUpdate();
}

/// אירוע פנימי לעדכון התקדמות מתוך תהליך הריצה.
class _LibraryUpdateProgressed extends LibraryUpdateEvent {
  final LibraryUpdateProgress progress;

  /// מזהה הריצה שיצרה את העדכון — התקדמות מריצה שבוטלה/הוחלפה מתעלמים.
  final int opId;
  const _LibraryUpdateProgressed(this.progress, this.opId);
  @override
  List<Object?> get props => [
    progress.phase,
    progress.stepIndex,
    progress.bytesDownloaded,
    progress.bytesTotal,
    opId,
  ];
}
