import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/cache/acronyms_cache.dart';
import 'package:otzaria/data/cache/generation_cache.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/services/target_line_links_service.dart';

/// מאפס מצב runtime מקומי כדי שהאפליקציה תוכל להיבנות מחדש בלי סגירת תהליך.
Future<void> resetRuntimeStateForAppRestart() async {
  await PluginRuntimeDispatcher.instance.prepareForAppRestart();
  await SqliteDataProvider.instance.dispose();
  await UserBooksDatabaseHolder.instance.close();
  await CacheDatabaseHolder.instance.close();
  await PersonalNotesDatabase.instance.close();
  await PluginSystemDatabase.instance.close();

  final libraryPath = await AppPaths.getLibraryPath();
  FileSystemData.instance.libraryPath = libraryPath;
  FileSystemData.instance.clearBookCache();

  LibraryProviderManager.instance.resetRuntimeState();
  DataRepository.instance.invalidateExternalBooksCache();

  ReferenceBooksCache.instance.clear();
  BooksCache.instance.clear();
  AcronymsCache.instance.clear();
  GenerationCache.instance.clear();
  // ה-FindRefRepository מחזיק caches פנימיים (מפרשים, AltToc שטוח) שלא
  // ניזונים מהקאשים שלמעלה. בלי איפוס יזום הם ישרדו עד restart מלא.
  FindRefRepository.clearAllCaches();
  CommentaryService.clearEraCache();
  TargetLineLinksService.instance.clearCache();
}

/// תאימות לשם הישן במסלול איפוס הגדרות.
Future<void> resetRuntimeStateAfterSettingsReset() async {
  await resetRuntimeStateForAppRestart();
}
