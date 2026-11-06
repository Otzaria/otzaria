import 'package:flutter/foundation.dart' show compute;

import '../../../data/data_providers/user_books_database_holder.dart';
import '../daos/database.dart';
import '../query_loader.dart';
import 'seforim_repository.dart';

typedef OffUiDeletionResult = ({
  List<int> deletedBooks,
  List<(int, String)> failedBooks,
  List<String> deletedEmptyCategories,
});

/// מוחק ספרים וקטגוריות מחוץ ל-UI; [useCurrentIsolate] מותר רק ב-worker ייעודי.
/// כשל בספר נאסף בתוצאה; כשל במחיקת קטגוריה נזרק.
Future<OffUiDeletionResult> deleteOffUi(
  SeforimRepository repository, {
  List<int> bookIds = const [],
  List<int> categoryIds = const [],
  Iterable<int> emptyCategoryRoots = const [],
  bool cleanupOrphans = true,
  bool useCurrentIsolate = false,
}) async {
  final roots = emptyCategoryRoots.toSet().toList();
  if (bookIds.isEmpty && categoryIds.isEmpty && roots.isEmpty) {
    return (
      deletedBooks: const <int>[],
      failedBooks: const <(int, String)>[],
      deletedEmptyCategories: const <String>[],
    );
  }
  final batch = (
    bookIds: bookIds,
    categoryIds: categoryIds,
    emptyCategoryRoots: roots,
    cleanupOrphans: cleanupOrphans,
  );
  try {
    if (useCurrentIsolate) return await _deleteBatch(repository, batch);
    OffUiDeletionResult? result;
    await UserBooksDatabaseHolder.instance.trackRead(() async {
      await QueryLoader.initialize();
      await repository.database.database;
      result = await compute(_deleteInWorker, (
        dbPath: repository.database.path,
        batch: batch,
        queries: QueryLoader.cacheSnapshot,
      ));
    });
    return result ?? (throw StateError('User books database is closing'));
  } finally {
    bookIds.forEach(repository.invalidateExternalBookToc);
  }
}

typedef _DeletionBatch = ({
  List<int> bookIds,
  List<int> categoryIds,
  List<int> emptyCategoryRoots,
  bool cleanupOrphans,
});

Future<OffUiDeletionResult> _deleteInWorker(
  ({
    String dbPath,
    _DeletionBatch batch,
    Map<String, Map<String, String>> queries,
  })
  args,
) async {
  QueryLoader.seedCache(args.queries);
  final database = MyDatabase.withPath(args.dbPath);
  final repository = SeforimRepository(database);
  try {
    return await _deleteBatch(repository, args.batch);
  } finally {
    database.close();
  }
}

Future<OffUiDeletionResult> _deleteBatch(
  SeforimRepository repository,
  _DeletionBatch args,
) async {
  final deleted = <int>[];
  final failed = <(int, String)>[];
  for (final bookId in args.bookIds) {
    try {
      await repository.deleteBookCompletely(bookId);
      deleted.add(bookId);
    } catch (e) {
      failed.add((bookId, e.toString()));
    }
  }
  if (args.cleanupOrphans && deleted.isNotEmpty) {
    await repository.deleteOrphanedTocTexts();
    await repository.deleteOrphanedLineToc();
  }
  for (final categoryId in args.categoryIds) {
    await repository.deleteCategory(categoryId);
  }
  final emptied = <String>[];
  for (final categoryId in args.emptyCategoryRoots) {
    await _deleteEmptyCategoryChain(repository, categoryId, emptied);
  }
  return (
    deletedBooks: deleted,
    failedBooks: failed,
    deletedEmptyCategories: emptied,
  );
}

Future<void> _deleteEmptyCategoryChain(
  SeforimRepository repository,
  int categoryId,
  List<String> emptied,
) async {
  for (int? id = categoryId; id != null;) {
    final category = await repository.getCategory(id);
    if (category == null ||
        (await repository.getBooksByCategory(id)).isNotEmpty ||
        (await repository.getCategoryChildren(id)).isNotEmpty) {
      return;
    }
    await repository.deleteCategory(id);
    emptied.add(category.title);
    id = category.parentId;
  }
}
