import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/attached_libraries/repository/external_link_repository.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/indexing/utils/book_facet_metadata_cache.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/divine_names/repository/divine_names_repository.dart';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/migration/sync/background_sync_initializer.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/marker/services/marker_book_cache.dart';
import 'package:otzaria/marker/storage/marker_database.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/services/target_line_links_service.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_client.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';

/// מאפס מצב runtime מקומי כדי שהאפליקציה תוכל להיבנות מחדש בלי סגירת תהליך.
Future<void> resetRuntimeStateForAppRestart({
  String? correctionStorageMoveRequestId,
}) async {
  await _prepareLibraryRuntimeReset(
    correctionStorageMoveRequestId: correctionStorageMoveRequestId,
  );
  await UserBooksDatabaseHolder.instance.close();
  await AttachedLibraryRegistry.instance.reset();
  await CacheDatabaseHolder.instance.close();
  await PersonalNotesDatabase.instance.close();
  MarkerDatabase.instance.close();
  MarkerBookCache.instance.clear();
  await PluginSystemDatabase.instance.close();
  await UserStateDatabase.instance.reopen();

  final libraryPath = await AppPaths.getLibraryPath();
  FileSystemData.instance.libraryPath = libraryPath;
  _invalidateLibraryRuntimeCaches();
  DataRepository.instance.invalidateExternalBooksCache();

  // תיקיות אישיות ששוחזרו מגיבוי צריכות להיסרק שוב לאחר הבנייה מחדש.
  BackgroundSyncInitializer.resetForAppRestart();
}

/// מאפס משאבים תלויי מקור ומטמוני ספרייה, בלי לסגור מסדי משתמש עצמאיים.
Future<void> resetLibraryRuntimeState() async {
  await _prepareLibraryRuntimeReset();
  _invalidateLibraryRuntimeCaches();
}

Future<void> _prepareLibraryRuntimeReset({
  String? correctionStorageMoveRequestId,
}) async {
  MultiWindowService.clearVisibilityRequestsForRestart();
  await PluginCorrectionSessionService.instance.prepareForRuntimeReset(
    requestId: correctionStorageMoveRequestId,
  );
  await const HiddenLibraryStore().resetRuntimeStateForAppRestart();
  await PluginRuntimeDispatcher.instance.prepareForAppRestart();
  await SqliteDataProvider.instance.dispose();
}

void _invalidateLibraryRuntimeCaches() {
  ExternalLinkRepository.instance.resetRuntime();
  FileSystemData.instance.clearBookCache();
  LibraryProviderManager.instance.resetRuntimeState();
  DataRepository.instance.invalidateLibraryCache();

  ReferenceBooksCache.instance.clear();
  BooksCache.instance.clear();
  AcronymsCache.instance.clear();
  GenerationCache.instance.clear();
  BookFacetMetadataCache.instance.clear();
  // מטמוני המפרשים וה-AltToc של האיתור נפרדים מהמטמונים המשותפים.
  FindRefRepository.clearAllCaches();
  FindRefBloc.clearAllSearches();
  CommentaryService.clearEraCache();
  TargetLineLinksService.instance.clearCache();
  DivineNamesRepository.instance.clear();
  BookNotesRepository.instance.clear();
}

/// אחרי איפוס הגדרות או שחזור גיבוי: בעל ההתראות מתיישר עם הערכים השמורים,
/// וחלון משני מקבל ממנו מחדש את המצב שנמחק אצלו.
Future<void> resetRuntimeStateAfterSettingsReset() async {
  await resetRuntimeStateForAppRestart();
  if (WindowRole.isSecondary) {
    RemoteCalendarAlertsClient.instance.forgetAppliedRevision();
    return;
  }
  try {
    await CalendarAlertsOwner.instance.handleSettingsReset();
  } catch (error, stackTrace) {
    NotificationService.logFailure(
      'יישור ההתראות אחרי איפוס נכשל',
      error,
      stackTrace,
    );
  }
}
