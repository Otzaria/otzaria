import 'package:flutter/foundation.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/models/book_version.dart';
import 'package:otzaria/models/books.dart';

/// האם להציע לספר [book] את הפעולה "הצג נוסחאות נוספות".
///
/// בספר רשמי — כשיש מהדורה לבחירה בפועל (ראו
/// [DatabaseLibraryProvider.hasSelectableBookVersions]) או גרסה אישית שהוצהרה
/// עליו; בספר אישי — כשהוא חלק מקבוצת גרסאות.
Future<bool> hasBookVersionsToOpen(Book book) async {
  final probe = bookVersionsProbeForTesting;
  if (probe != null) return probe(book);

  if (book.isUserBook) {
    return DatabaseLibraryProvider.instance.getUserBookVersions(book).length >
        1;
  }
  if (!book.isOfficialLibraryBook && !book.source.isAttached) return false;
  if (DatabaseLibraryProvider.instance.getPersonalVersionsOf(book).isNotEmpty) {
    return true;
  }
  final categoryId = book.categoryId;
  if (book is! TextBook || categoryId == null) return false;
  if (book.versionTitle != null) {
    final probe = availableBookVersionsProbeForTesting;
    final versions =
        await (probe?.call(book) ??
            DatabaseLibraryProvider.instance.getBookVersions(
              book.title,
              categoryId,
              source: book.source,
            ));
    return versions.any((version) => version.versionTitle != book.versionTitle);
  }
  return DatabaseLibraryProvider.instance.hasSelectableBookVersions(
    book.title,
    categoryId,
    source: book.source,
  );
}

/// מחליף את שאילתת המהדורות בבדיקות widget שאין להן seforim.db.
@visibleForTesting
Future<bool> Function(Book book)? bookVersionsProbeForTesting;

/// מחליף את טעינת המהדורות כשכבר פתוח נוסח מסוים.
@visibleForTesting
Future<List<BookVersionInfo>> Function(TextBook book)?
availableBookVersionsProbeForTesting;
