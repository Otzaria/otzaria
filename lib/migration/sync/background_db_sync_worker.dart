import 'dart:isolate';

import '../../data/data_providers/database_library_provider.dart';
import '../database/daos/database.dart';
import '../database/repository/seforim_repository.dart';
import '../database/sql/query_loader.dart';
import '../../settings/services/custom_folders/custom_folder.dart';
import 'file_sync_service.dart';

/// Runs a full custom-folders DB sync inside a background isolate.
///
/// All calls are serialised through [DatabaseLibraryProvider.operationQueue]
/// so that concurrent writes to the same SQLite file are impossible,
/// regardless of which call site invokes this function.
///
/// [QueryLoader] is pre-initialised on the main isolate and its cache is
/// forwarded in the payload, avoiding any [rootBundle] access inside the
/// worker isolate.
///
/// [dbPath] — נתיב `seforim.db` (לתוכן רשמי + links).
/// [userBooksDbPath] — נתיב `user_books.db` (לתיקיות מותאמות אישית).
Future<FileSyncResult> runCustomFoldersDbSyncInIsolate({
  required String dbPath,
  required String userBooksDbPath,
  required String libraryPath,
  required List<CustomFolder> customFolders,
  String folderName = '',
}) {
  return DatabaseLibraryProvider.operationQueue.enqueue(() async {
    await QueryLoader.initialize();
    final payload = <String, Object?>{
      'queryCache': QueryLoader.cacheSnapshot,
      'dbPath': dbPath,
      'userBooksDbPath': userBooksDbPath,
      'libraryPath': libraryPath,
      'folderName': folderName,
      'customFolders': customFolders.map((f) => f.toJson()).toList(),
    };
    final resultMap = await Isolate.run(() => _syncWorkerEntryPoint(payload));
    return FileSyncResult(
      addedBooks: resultMap['addedBooks'] as int,
      updatedBooks: resultMap['updatedBooks'] as int,
      addedCategories: resultMap['addedCategories'] as int,
      addedLinks: resultMap['addedLinks'] as int,
      skippedFiles: resultMap['skippedFiles'] as int,
      errors: List<String>.from(resultMap['errors'] as List),
      duration: Duration(milliseconds: resultMap['durationMs'] as int),
    );
  });
}

/// Runs a folder-delete operation inside a background isolate.
///
/// [folderCategoryId] and [personalCategoryId] must be resolved by the
/// caller on the main isolate before invoking this function.
/// Serialised through the same [DatabaseLibraryProvider.operationQueue].
///
/// [userBooksDbPath] — נתיב `user_books.db` (שם נמצאות התיקיות המותאמות).
/// [dbPath] — נתיב `seforim.db`. נדרש כי `FileSyncService` מצפה לשני repos.
Future<void> runDeleteFolderFromDbInIsolate({
  required String dbPath,
  required String userBooksDbPath,
  required int folderCategoryId,
  required int personalCategoryId,
}) {
  return DatabaseLibraryProvider.operationQueue.enqueue(() async {
    await QueryLoader.initialize();
    // Build payload on the main isolate so cacheSnapshot is evaluated here,
    // not lazily inside the worker closure.
    final payload = <String, Object?>{
      'queryCache': QueryLoader.cacheSnapshot,
      'dbPath': dbPath,
      'userBooksDbPath': userBooksDbPath,
      'folderCategoryId': folderCategoryId,
      'personalCategoryId': personalCategoryId,
    };
    await Isolate.run(() => _deleteWorkerEntryPoint(payload));
  });
}

// ── worker entry points (top-level so they're transferable) ──────────────────

Future<Map<String, Object?>> _syncWorkerEntryPoint(
    Map<String, Object?> payload) async {
  QueryLoader.seedCache(
    (payload['queryCache'] as Map).cast<String, Map<String, String>>(),
  );

  final dbPath = payload['dbPath'] as String;
  final userBooksDbPath = payload['userBooksDbPath'] as String;
  final libraryPath = payload['libraryPath'] as String;
  final folderName = (payload['folderName'] as String?) ?? '';
  final rawFolders =
      (payload['customFolders'] as List).cast<Map<String, dynamic>>();
  final customFolders = rawFolders.map(CustomFolder.fromJson).toList();

  final database = MyDatabase.withPath(dbPath);
  final repository = SeforimRepository(database);
  await repository.ensureInitialized();

  final userBooksDatabase = MyDatabase.withPath(userBooksDbPath);
  final userBooksRepository = SeforimRepository(userBooksDatabase);
  await userBooksRepository.ensureInitialized();

  final service = FileSyncService.createForWorker(
    repository,
    userBooksRepository: userBooksRepository,
  );

  try {
    final result = await service.syncCustomFoldersWithInputs(
      libraryPath: libraryPath,
      customFolders: customFolders,
      folderName: folderName,
    );
    return {
      'addedBooks': result.addedBooks,
      'updatedBooks': result.updatedBooks,
      'addedCategories': result.addedCategories,
      'addedLinks': result.addedLinks,
      'skippedFiles': result.skippedFiles,
      'errors': result.errors,
      'durationMs': result.duration.inMilliseconds,
    };
  } finally {
    database.close();
    userBooksDatabase.close();
  }
}

Future<void> _deleteWorkerEntryPoint(Map<String, Object?> payload) async {
  QueryLoader.seedCache(
    (payload['queryCache'] as Map).cast<String, Map<String, String>>(),
  );

  final dbPath = payload['dbPath'] as String;
  final userBooksDbPath = payload['userBooksDbPath'] as String;
  final folderCategoryId = payload['folderCategoryId'] as int;
  final personalCategoryId = payload['personalCategoryId'] as int;

  final database = MyDatabase.withPath(dbPath);
  final repository = SeforimRepository(database);
  await repository.ensureInitialized();

  final userBooksDatabase = MyDatabase.withPath(userBooksDbPath);
  final userBooksRepository = SeforimRepository(userBooksDatabase);
  await userBooksRepository.ensureInitialized();

  final service = FileSyncService.createForWorker(
    repository,
    userBooksRepository: userBooksRepository,
  );

  try {
    await service.deleteFolderFromDatabase(
        folderCategoryId, personalCategoryId);
  } finally {
    database.close();
    userBooksDatabase.close();
  }
}
