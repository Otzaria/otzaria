import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';
import 'package:otzaria/models/books.dart';

/// האם שורות התוכן של [book] מתאימות למקור סמני החלוקה.
bool canLoadInlineSectionMarks(TextBook book) =>
    book.versionTitle == null &&
    (!book.source.isOfficial ||
        LibraryProviderManager.instance.getProviderForBook(
              book.title,
              categoryId: book.categoryId,
              fileType: book.fileType,
            )
            is DatabaseLibraryProvider);

/// סמני החלוקה והכותרות המוזרקות של [book] לפי שורה, להצגה בטקסט
/// הראשי. מחזיר null כשאין להם מקור במסד; זורק [DbReadWorkerBusy].
Future<InlineSectionMarks?> loadInlineSectionMarks(
  TextBook book,
  String? Function(int lineIndex) lineAt,
) async {
  // הסימנים ממופים ל-lineIndex של הטקסט הממוזג במסד — מהדורה חלופית
  // (version_line) או ספר שתוכנו מוגש מקבצים ממוספרים אחרת.
  if (!canLoadInlineSectionMarks(book)) return null;
  if (book.isUserBook) {
    return DatabaseLibraryProvider.instance.getUserInlineSectionMarks(
      book,
      lineAt,
    );
  }
  return DatabaseLibraryProvider.instance.getInlineSectionMarksByLineIndex(
    book.title,
    categoryId: book.categoryId,
    source: book.source,
  );
}
