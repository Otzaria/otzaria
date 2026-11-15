import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';

/// סמני החלוקה וכותרות הנושא והפרשה של [book] לפי שורה, להזרקה בטקסט
/// הראשי. מחזיר null כשאין להם מקור במסד; זורק [DbReadWorkerBusy].
Future<InlineSectionMarks?> loadInlineSectionMarks(
  TextBook book,
  String? Function(int lineIndex) lineAt,
) async {
  // הסימנים ממופים ל-lineIndex של הטקסט הממוזג במסד — מהדורה חלופית
  // (version_line) או ספר שתוכנו מוגש מקבצים ממוספרים אחרת.
  if (book.versionTitle != null) return null;
  if (book.isUserBook) {
    return DatabaseLibraryProvider.instance.getUserInlineSectionMarks(
      book,
      lineAt,
    );
  }
  if (book.source.isOfficial &&
      LibraryProviderManager.instance.getProviderForBook(
            book.title,
            categoryId: book.categoryId,
            fileType: book.fileType,
          )
          is! DatabaseLibraryProvider) {
    return null;
  }
  return DatabaseLibraryProvider.instance.getInlineSectionMarksByLineIndex(
    book.title,
    categoryId: book.categoryId,
    source: book.source,
  );
}
