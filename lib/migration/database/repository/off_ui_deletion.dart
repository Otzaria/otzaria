import 'package:flutter/foundation.dart' show compute;

import '../daos/database.dart';
import '../query_loader.dart';
import 'seforim_repository.dart';

typedef OffUiDeletionResult = ({
  List<int> deletedBooks,
  List<(int, String)> failedBooks,
  List<String> deletedEmptyCategories,
});

/// מוחק ב-isolate נפרד ספרים, את [categoryIds] לפי הסדר וקטגוריות שהתרוקנו
/// מ-[emptyCategoryRoots] ומעלה. כשל בספר נאסף ב-failedBooks; כשל בקטגוריה נזרק.
Future<OffUiDeletionResult> deleteOffUi(
  SeforimRepository repository, {
  List<int> bookIds = const [],
  List<int> categoryIds = const [],
  Iterable<int> emptyCategoryRoots = const [],
  bool cleanupOrphans = true,
}) async {
  final roots = emptyCategoryRoots.toSet().toList();
  if (bookIds.isEmpty && categoryIds.isEmpty && roots.isEmpty) {
    return (
      deletedBooks: const <int>[],
      failedBooks: const <(int, String)>[],
      deletedEmptyCategories: const <String>[],
    );
  }
  await QueryLoader.initialize();
  try {
    return await compute(_deleteInWorker, (
      dbPath: repository.database.path,
      bookIds: bookIds,
      categoryIds: categoryIds,
      emptyCategoryRoots: roots,
      cleanupOrphans: cleanupOrphans,
      queries: QueryLoader.cacheSnapshot,
    ));
  } finally {
    bookIds.forEach(repository.invalidateExternalBookToc);
  }
}

typedef _DeletionBatch = ({
  String dbPath,
  List<int> bookIds,
  List<int> categoryIds,
  List<int> emptyCategoryRoots,
  bool cleanupOrphans,
  Map<String, Map<String, String>> queries,
});

Future<OffUiDeletionResult> _deleteInWorker(_DeletionBatch args) async {
  QueryLoader.seedCache(args.queries);
  final database = MyDatabase.withPath(args.dbPath);
  final repository = SeforimRepository(database);
  try {
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
  } finally {
    database.close();
  }
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
