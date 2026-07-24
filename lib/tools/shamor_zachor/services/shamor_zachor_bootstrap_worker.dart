import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Worker לטעינת עץ הספרים של שמור וזכור מחוץ ל-main isolate.
///
/// ה-worker מחזיר DTO-ים פשוטים בלבד כדי שלא להעביר מודלים של האפליקציה בין
/// isolates.
class ShamorZachorBootstrapWorker {
  const ShamorZachorBootstrapWorker._();

  static Future<Map<String, dynamic>> loadCategoryTree({
    required String dbPath,
    required List<int> trackedBookIds,
  }) {
    return Isolate.run(
      () => _loadCategoryTreeInWorker({
        'dbPath': dbPath,
        'trackedBookIds': trackedBookIds,
      }),
    );
  }
}

Map<String, dynamic> _loadCategoryTreeInWorker(Map<String, dynamic> request) {
  final dbPath = request['dbPath'] as String;
  final trackedBookIds = (request['trackedBookIds'] as List)
      .cast<int>()
      .toSet();

  final db = sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
  try {
    db.execute('PRAGMA query_only = ON');

    final allBooks = _selectMaps(db, '''
      SELECT id, categoryId, title, orderIndex, totalLines, isBaseBook
      FROM book
      ORDER BY orderIndex, title
    ''');
    final relevantBooks = allBooks.where((book) {
      final id = book['id'] as int;
      final isBaseBook = (book['isBaseBook'] as int? ?? 0) == 1;
      return isBaseBook || trackedBookIds.contains(id);
    }).toList();

    final allCategories = _selectMaps(db, '''
      SELECT id, parentId, title, level, orderIndex
      FROM category
      ORDER BY orderIndex, title
    ''');

    final booksByCatId = <int, List<Map<String, dynamic>>>{};
    for (final book in relevantBooks) {
      final categoryId = book['categoryId'] as int;
      booksByCatId.putIfAbsent(categoryId, () => []).add(book);
    }

    final categoriesByParentId = <int?, List<Map<String, dynamic>>>{};
    for (final category in allCategories) {
      final parentId = category['parentId'] as int?;
      categoriesByParentId.putIfAbsent(parentId, () => []).add(category);
    }

    for (final categories in categoriesByParentId.values) {
      categories.sort((a, b) {
        final orderCompare = (a['orderIndex'] as int).compareTo(
          b['orderIndex'] as int,
        );
        if (orderCompare != 0) return orderCompare;
        return (a['title'] as String).compareTo(b['title'] as String);
      });
    }

    final topCategories = <Map<String, dynamic>>[];
    for (final rootCat in categoriesByParentId[null] ?? const []) {
      final builtCat = _buildRecursiveCategory(
        db: db,
        currentCat: rootCat,
        categoriesByParentId: categoriesByParentId,
        booksByCatId: booksByCatId,
        inheritedContentType: null,
        parentPath: const [],
      );
      if (builtCat != null) {
        topCategories.add(builtCat);
      }
    }

    return {
      'categories': topCategories,
      'allBookCount': allBooks.length,
      'relevantBookCount': relevantBooks.length,
      'categoryCount': allCategories.length,
    };
  } finally {
    db.close();
  }
}

Map<String, dynamic>? _buildRecursiveCategory({
  required sqlite3.Database db,
  required Map<String, dynamic> currentCat,
  required Map<int?, List<Map<String, dynamic>>> categoriesByParentId,
  required Map<int, List<Map<String, dynamic>>> booksByCatId,
  required String? inheritedContentType,
  required List<String> parentPath,
}) {
  final title = currentCat['title'] as String;
  var contentType = inheritedContentType ?? 'text';

  if (title.contains('בבלי') || title.contains('ירושלמי')) {
    contentType = 'דף';
  } else if (title.contains('תנ"ך')) {
    contentType = 'text';
  }

  final currentPath = [...parentPath, title];
  final categoryId = currentCat['id'] as int;
  final directBooks = booksByCatId[categoryId] ?? const [];
  final validBooks = <String, dynamic>{};

  for (final dbBook in directBooks) {
    validBooks[dbBook['title'] as String] = _convertBookToDetails(
      db: db,
      dbBook: dbBook,
      contentType: contentType,
      categoryPath: currentPath,
    );
  }

  final validSubcategories = <Map<String, dynamic>>[];
  for (final child in categoriesByParentId[categoryId] ?? const []) {
    final subcategory = _buildRecursiveCategory(
      db: db,
      currentCat: child,
      categoriesByParentId: categoriesByParentId,
      booksByCatId: booksByCatId,
      inheritedContentType: contentType,
      parentPath: currentPath,
    );
    if (subcategory != null) {
      validSubcategories.add(subcategory);
    }
  }

  if (validBooks.isEmpty && validSubcategories.isEmpty) {
    return null;
  }

  return {
    'name': title,
    'contentType': contentType,
    'books': validBooks,
    'defaultStartPage': 1,
    'isCustom': false,
    'sourceFile': 'db',
    if (validSubcategories.isNotEmpty) 'subcategories': validSubcategories,
    'parentCategoryName': currentCat['parentId'] != null
        ? parentPath.last
        : null,
    'schemaVersion': 1,
  };
}

Map<String, dynamic> _convertBookToDetails({
  required sqlite3.Database db,
  required Map<String, dynamic> dbBook,
  required String contentType,
  required List<String> categoryPath,
}) {
  final totalLines = dbBook['totalLines'] as int? ?? 0;
  final endPage = totalLines > 0 ? totalLines : 1;
  final sections = _loadTocForBook(
    db,
    dbBook['id'] as int,
    totalLines > 0 ? totalLines : 100,
  );

  return {
    'contentType': contentType,
    'isCustom': (dbBook['isBaseBook'] as int? ?? 0) != 1,
    'id': dbBook['id'],
    'originalPageCount': totalLines,
    'parts': [
      {
        'name': 'ראשי',
        'start': 1,
        'end': endPage,
      },
    ],
    if (sections.isNotEmpty) 'sections': sections,
    'categoryPath': categoryPath.isNotEmpty ? categoryPath.first : '',
  };
}

List<Map<String, dynamic>> _loadTocForBook(
  sqlite3.Database db,
  int bookId,
  int totalLines,
) {
  final tocEntries = _selectMaps(
    db,
    '''
    SELECT t.*, tt.text, COALESCE(l.lineIndex, t.lineId) as lineIndex
    FROM tocEntry t
    JOIN tocText tt ON t.textId = tt.id
    LEFT JOIN line l ON t.lineId = l.id
    WHERE t.bookId = ?
    ORDER BY COALESCE(l.lineIndex, t.lineId) ASC,
             CASE WHEN t.id < 0 THEN -t.id ELSE t.id END ASC
  ''',
    [bookId],
  );

  if (tocEntries.isEmpty) {
    return const [];
  }

  return _buildSectionsFromToc(tocEntries, totalLines);
}

List<Map<String, dynamic>> _buildSectionsFromToc(
  List<Map<String, dynamic>> entries,
  int totalLines,
) {
  final childMap = <int, List<Map<String, dynamic>>>{};

  for (final entry in entries) {
    final parentId = entry['parentId'] as int?;
    if (parentId != null) {
      childMap.putIfAbsent(parentId, () => []).add(entry);
    }
  }

  final roots = entries.where((entry) => entry['parentId'] == null).toList()
    ..sort(
      (a, b) =>
          (a['lineIndex'] as int? ?? 0).compareTo(b['lineIndex'] as int? ?? 0),
    );

  final result = <Map<String, dynamic>>[];
  for (var i = 0; i < roots.length; i++) {
    final current = roots[i];
    final next = (i + 1 < roots.length) ? roots[i + 1] : null;
    final nextStart = next?['lineIndex'] as int? ?? totalLines;
    final currentLineIndex = current['lineIndex'] as int? ?? 0;
    final currentEnd =
        next != null && (next['lineIndex'] as int? ?? 0) > currentLineIndex
        ? (next['lineIndex'] as int) - 1
        : nextStart;

    result.add(
      _convertToSection(
        current,
        childMap,
        currentEnd > 0 ? currentEnd : totalLines,
      ),
    );
  }
  return result;
}

Map<String, dynamic> _convertToSection(
  Map<String, dynamic> entry,
  Map<int, List<Map<String, dynamic>>> childMap,
  int parentEndPage,
) {
  final children = [...childMap[entry['id'] as int] ?? const []];
  children.sort(
    (a, b) =>
        (a['lineIndex'] as int? ?? 0).compareTo(b['lineIndex'] as int? ?? 0),
  );

  final childSections = <Map<String, dynamic>>[];
  final entryStart = entry['lineIndex'] as int? ?? 0;

  for (var i = 0; i < children.length; i++) {
    final current = children[i];
    final next = (i + 1 < children.length) ? children[i + 1] : null;
    final nextStart = next?['lineIndex'] as int? ?? parentEndPage;
    final currentLineIndex = current['lineIndex'] as int? ?? 0;
    final currentEnd =
        next != null && (next['lineIndex'] as int? ?? 0) > currentLineIndex
        ? (next['lineIndex'] as int) - 1
        : nextStart;

    childSections.add(_convertToSection(current, childMap, currentEnd));
  }

  return {
    'id': (entry['id'] as int).toString(),
    'title': entry['text'] as String? ?? '',
    'level': entry['level'] as int? ?? 0,
    'startPage': entryStart,
    'endPage': parentEndPage > entryStart ? parentEndPage : entryStart,
    if (childSections.isNotEmpty) 'children': childSections,
  };
}

List<Map<String, dynamic>> _selectMaps(
  sqlite3.Database db,
  String sql, [
  List<Object?> parameters = const [],
]) {
  return db.select(sql, parameters).map((row) {
    return {
      for (final key in row.keys) key: row[key],
    };
  }).toList();
}
