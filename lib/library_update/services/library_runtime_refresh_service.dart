import 'package:otzaria/core/app_runtime_reset.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';

/// מרענן את מקור הספרייה והמטמונים אחרי עדכון המסד; האינדוקס באחריות ה-BLoC.
class LibraryRuntimeRefreshService {
  const LibraryRuntimeRefreshService();

  /// קוראים אחרי החלפת/עדכון `seforim.db`, בתוך אותו תור פעולות ה-DB.
  Future<void> refreshAfterDbUpdate() async {
    try {
      await resetLibraryRuntimeState();
    } on DbReadWorkerBusy catch (_, stackTrace) {
      Error.throwWithStackTrace(
        LibraryDbNotReleased(LibraryMessages.libraryRefreshDbBusy),
        stackTrace,
      );
    }

    // פתיחה מחדש של ה-DB החדש (read-only) לקריאות הבאות.
    await SqliteDataProvider.instance.initialize();
  }
}
