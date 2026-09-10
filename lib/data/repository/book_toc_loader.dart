import 'dart:io';
import 'dart:isolate';

import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/toc_parser.dart';

/// תוכן העניינים של [book] מספק הספרייה, ובכשלו — מ-[loadBookTocFallback].
/// המקור היחיד לטעינת TOC, כדי שכשל טעינה לא יתחזה לספר בלי תוכן עניינים.
Future<List<TocEntry>> loadBookToc(
  TextBook book, {
  SqliteDataProvider? sqliteProvider,
}) async {
  final providerToc = await LibraryProviderManager.instance.getBookToc(
    book.title,
    categoryId: book.categoryId,
    fileType: book.fileType ?? 'txt',
    preferUserBooks: book.isUserBook,
  );
  if (providerToc != null && providerToc.isNotEmpty) {
    return providerToc;
  }

  return loadBookTocFallback(book, sqliteProvider: sqliteProvider);
}

/// שליפת תוכן העניינים ישירות מה-DB, או פירוקו מהקובץ בספר חיצוני — כשספק
/// הספרייה לא זמין (מטמון קטלוג שטרם נבנה, DB שאינו עונה).
Future<List<TocEntry>> loadBookTocFallback(
  TextBook book, {
  SqliteDataProvider? sqliteProvider,
}) async {
  final provider = sqliteProvider ?? SqliteDataProvider.instance;
  final title = book.title;

  final dbBook = await BookLocator.getBookFromDatabase(
    title,
    category: book.category,
    categoryId: book.categoryId,
    fileType: book.fileType,
  );
  if (dbBook == null) {
    return [];
  }

  book.fileType ??= dbBook.fileType;
  book.filePath ??= dbBook.filePath;

  if (dbBook.isFileBacked && dbBook.filePath != null) {
    final file = File(dbBook.filePath!);
    if (await file.exists()) {
      final format = documentFormatOf(
        fileType: dbBook.fileType,
        path: file.path,
      );
      // PDF הוא file-backed אך אינו טקסט — הוא בונה TOC מה-outline שלו
      // במסלול נפרד, ושליחתו לממיר טקסט זורקת.
      final content = format == null || !format.isTextual
          ? ''
          // בלי תמונות: לתוכן העניינים נדרש רק מבנה הכותרות.
          : await convertDocumentForIndex(file, title, format);
      if (content.isNotEmpty) {
        return await Isolate.run(
          () => TocParser.parseEntriesFromContent(content),
        );
      }
    }
  }

  final dbToc = await provider.getBookTocFromDb(
    title,
    dbBook.categoryId,
    dbBook.fileType,
    book.isUserBook,
  );
  if (dbToc != null && dbToc.isNotEmpty) {
    return dbToc;
  }

  return [];
}
