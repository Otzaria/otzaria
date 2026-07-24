import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/migration/models/toc_entry.dart' as migration_models;

/// מודל לניהול קבצי headings של PDF
/// מקשר בין כותרות ב-PDF למספרי שורות בקובץ הטקסט
class PdfHeadings {
  final Map<String, int> headingsMap;
  final String bookTitle;

  PdfHeadings({
    required this.headingsMap,
    required this.bookTitle,
  });

  /// טוען headings עבור ספר PDF מתוך ה-DB (טבלת tocEntry).
  ///
  /// הנתונים נשענים על השדות: bookId, textId, lineIndex.
  static Future<PdfHeadings?> loadFromDatabase(
    String bookTitle, {
    int? categoryId,
    String? filePath,
    bool preferUserBooks = false,
  }) async {
    try {
      final resolvedBook = await BookDatabaseResolver.resolveBook(
        title: bookTitle,
        categoryId: categoryId,
        filePath: filePath,
        preferUserBooks: preferUserBooks,
      );
      if (resolvedBook == null) {
        debugPrint('Book not found in DB for headings: $bookTitle');
        return null;
      }

      return await _loadFromResolvedBook(
        resolvedBook,
        bookTitle: bookTitle,
      );
    } catch (e) {
      debugPrint('Error loading headings from DB for $bookTitle: $e');
      return null;
    }
  }

  static Future<PdfHeadings?> _loadFromResolvedBook(
    ResolvedDbBookRecord resolvedBook, {
    String? bookTitle,
  }) async {
    try {
      final tocEntries = await resolvedBook.repository.getBookTocs(
        resolvedBook.book.id,
      );
      final headingsMap = buildHeadingsMapFromTocEntries(tocEntries);

      if (headingsMap.isEmpty) {
        debugPrint(
          'No PDF headings found in DB for bookId: ${resolvedBook.book.id}',
        );
        return null;
      }

      return PdfHeadings(
        headingsMap: headingsMap,
        bookTitle: bookTitle ?? resolvedBook.book.title,
      );
    } catch (e) {
      debugPrint(
        'Error loading headings from DB for bookId ${resolvedBook.book.id}: $e',
      );
      return null;
    }
  }

  /// בונה מפת headings מתוך רשומות TOC מה-DB.
  static Map<String, int> buildHeadingsMapFromTocEntries(
    List<migration_models.TocEntry> entries,
  ) {
    final Map<String, int> headingsMap = {};

    for (final entry in entries) {
      final title = entry.text.trim();
      final lineIndex = entry.lineIndex;
      if (title.isEmpty || lineIndex == null) {
        continue;
      }

      final existing = headingsMap[title];
      if (existing == null || lineIndex < existing) {
        headingsMap[title] = lineIndex;
      }
    }

    return headingsMap;
  }

  /// מחזיר את מספר השורה בטקסט עבור כותרת מסוימת
  int? getLineNumberForHeading(String heading) {
    return headingsMap[heading];
  }

  /// מחזיר את הכותרת הקרובה ביותר למספר שורה נתון
  String? getClosestHeading(int lineNumber) {
    String? closestHeading;
    int closestDistance = double.maxFinite.toInt();

    for (final entry in headingsMap.entries) {
      final distance = (entry.value - lineNumber).abs();
      if (distance < closestDistance) {
        closestDistance = distance;
        closestHeading = entry.key;
      }
    }

    return closestHeading;
  }

  /// מחזיר רשימה של כותרות ממוינות לפי מספר השורה
  List<MapEntry<String, int>> getSortedHeadings() {
    final entries = headingsMap.entries.toList();
    entries.sort((a, b) => a.value.compareTo(b.value));
    return entries;
  }
}
