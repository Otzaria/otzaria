enum BookReadOperation {
  allBooks,
  allLocalBooks,
  localBooksSlim,
  allBooksWithRelations,
  byId,
  byCategory,
  byTitle,
  byTitleAndCategory,
  byTitleCategoryAndFileType,
  byFilePath,
  count,
}

/// קריאת ספרים על חיבור אחר; חיבורי כתיבה וחיבורי ה-worker נשארים מקומיים.
typedef BookReadDelegate =
    Future<Object?> Function(
      BookReadOperation operation,
      List<Object?> arguments, {
      required bool includeRelations,
    });
