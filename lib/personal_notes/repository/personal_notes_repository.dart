import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/data/cache/books_cache.dart';
import 'package:otzaria/data/data_providers/book_database_resolver.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/utils/file/document_converter.dart';

typedef PersonalNotesLoader =
    Future<List<PersonalNote>> Function(
      String bookId, {
      int? categoryId,
    });

/// טוען הערות שמורות ללא קריאת תוכן הספר ויישוב מחדש של המיקומים.
Future<List<PersonalNote>> loadStoredPersonalNotes(
  String bookId, {
  int? categoryId,
}) => PersonalNotesDatabase.instance.loadNotes(bookId);

typedef _BookContentCacheKey = ({
  SeforimRepository repository,
  int bookId,
  String title,
  int categoryId,
  String fileType,
  int generation,
  int dataVersion,
});

class PersonalNotesRepository {
  final FileSystemData _fileSystem;
  final PersonalNotesService _service;
  final PersonalNotesDatabase _database;

  // רשומה יחידה לכל החלוניות; data_version מזהה גם commit בזמן עדכון WAL.
  // קבצים ומסדים אישיים/מצורפים יכולים להשתנות בין פעולות ולכן אינם נשמרים.
  static ({_BookContentCacheKey key, String content})? _lastContent;

  PersonalNotesRepository({
    FileSystemData? fileSystemData,
    PersonalNotesService? service,
    PersonalNotesDatabase? database,
  }) : _fileSystem = fileSystemData ?? FileSystemData.instance,
       _service = service ?? PersonalNotesService(),
       _database = database ?? PersonalNotesDatabase.instance;

  Future<List<PersonalNote>> loadNotes(
    String bookId, {
    int? categoryId,
  }) async {
    final content = await _loadBookContent(
      bookId,
      categoryId: categoryId,
      refresh: true,
    );
    return _service.loadNotes(bookId: bookId, bookContent: content);
  }

  /// ההערות כפי שנשמרו, בלי לקרוא את תוכן הספר ובלי ליישב מחדש את מיקומן.
  Future<List<PersonalNote>> loadStoredNotes(String bookId) =>
      _database.loadNotes(bookId);

  Future<List<PersonalNote>> addNote({
    required String bookId,
    required int lineNumber,
    required String content,
    required String contentPlain,
    required PersonalNoteContentFormat contentFormat,
    String? selectedText,
    int? selectionColumn,
    bool punctuationHidden = false,
    int? categoryId,
  }) async {
    final bookContent = await _loadBookContent(bookId, categoryId: categoryId);
    return _service.addNote(
      bookId: bookId,
      bookContent: bookContent,
      lineNumber: lineNumber,
      content: content,
      contentPlain: contentPlain,
      contentFormat: contentFormat,
      selectedText: selectedText,
      selectionColumn: selectionColumn,
      punctuationHidden: punctuationHidden,
    );
  }

  Future<List<PersonalNote>> updateNote({
    required String bookId,
    required String noteId,
    required String content,
    required String contentPlain,
    required PersonalNoteContentFormat contentFormat,
    int? categoryId,
  }) async {
    final bookContent = await _loadBookContent(bookId, categoryId: categoryId);
    return _service.updateNote(
      bookId: bookId,
      bookContent: bookContent,
      noteId: noteId,
      content: content,
      contentPlain: contentPlain,
      contentFormat: contentFormat,
    );
  }

  Future<List<PersonalNote>> deleteNote({
    required String bookId,
    required String noteId,
  }) => _service.deleteNote(bookId: bookId, noteId: noteId);

  Future<List<PersonalNote>> repositionNote({
    required String bookId,
    required String noteId,
    required int lineNumber,
    int? categoryId,
  }) async {
    final bookContent = await _loadBookContent(bookId, categoryId: categoryId);
    return _service.repositionNote(
      bookId: bookId,
      bookContent: bookContent,
      noteId: noteId,
      lineNumber: lineNumber,
    );
  }

  /// תוכן הספר של מפתח ההערות [bookId], כפי שההערות מעוגנות אליו.
  Future<String> loadBookContent(String bookId, {int? categoryId}) =>
      _loadBookContent(bookId, categoryId: categoryId, refresh: true);

  Future<List<BookNotesInfo>> listBooksWithNotes() {
    return _database.listBooksWithNotes();
  }

  Future<String> _loadBookContent(
    String bookId, {
    int? categoryId,
    bool refresh = false,
  }) async {
    final parsed = parsePersonalNotesBookKey(bookId);
    if (parsed.source case final source?) {
      _lastContent = null;
      return _loadSourceBookContent(parsed.title, source, categoryId);
    }
    try {
      final location = await BookLocator.locateBook(
        bookId,
        categoryId: categoryId,
      );
      if (location != null) {
        if (location.storage == BookStorageKind.database &&
            location.book != null) {
          final dbBook = location.book!;
          if (dbBook.isFileBacked && dbBook.filePath != null) {
            _lastContent = null;
            final file = File(dbBook.filePath!);
            if (await file.exists()) {
              // PDF מחזיר null — '' הוא הסיגנל לעיגון-לפי-עמוד בהמשך.
              return await readFileBackedBookText(
                    file,
                    dbBook.fileType,
                    bookId,
                  ) ??
                  '';
            }
          }

          final cacheRepository =
              location.source.isOfficial &&
                  !dbBook.isFileBacked &&
                  identical(
                    location.repository,
                    SqliteDataProvider.instance.repository,
                  )
              ? location.repository
              : null;
          final connection = cacheRepository == null
              ? null
              : await cacheRepository.database.database;
          int dataVersion() =>
              connection!.select('PRAGMA data_version').first.values.first
                  as int;
          final key =
              cacheRepository == null ||
                  !identical(
                    cacheRepository,
                    SqliteDataProvider.instance.repository,
                  )
              ? null
              : (
                  repository: cacheRepository,
                  bookId: dbBook.id,
                  title: bookId,
                  categoryId: dbBook.categoryId,
                  fileType: dbBook.fileType ?? 'txt',
                  generation: BooksCache.instance.generation,
                  dataVersion: dataVersion(),
                );
          final last = _lastContent;
          if (!refresh &&
              key != null &&
              identical(
                key.repository,
                SqliteDataProvider.instance.repository,
              ) &&
              last?.key == key) {
            return last!.content;
          }
          _lastContent = null;
          final fileType = dbBook.fileType ?? 'txt';
          final resolvedCategoryId = location.categoryId;
          final dbText = await SqliteDataProvider.instance.getBookTextFromDb(
            bookId,
            resolvedCategoryId,
            fileType,
          );
          if (dbText != null) {
            if (key != null &&
                dbText.isNotEmpty &&
                key.generation == BooksCache.instance.generation &&
                identical(
                  key.repository,
                  SqliteDataProvider.instance.repository,
                ) &&
                key.dataVersion == dataVersion()) {
              _lastContent = (key: key, content: dbText);
            }
            return dbText;
          }
        } else if (location.storage == BookStorageKind.fileSystem &&
            location.filePath != null) {
          _lastContent = null;
          final file = File(location.filePath!);
          if (await file.exists()) {
            return await readFileBackedBookText(file, null, bookId) ?? '';
          }
        }
      }

      _lastContent = null;
      return await _fileSystem.getBookText(bookId);
    } catch (e) {
      _lastContent = null;
      // ספרי PDF (וספרים שנמחקו) מגיעים לכאן דרך חריגה — '' הוא הסיגנל
      // לעיגון-לפי-עמוד ב-_reconcileLocation, ולכן אין rethrow. הלוג מבחין
      // כשל קריאה אמיתי ממצב ה-PDF הלגיטימי.
      debugPrint('[PersonalNotes] book content load failed for "$bookId": $e');
      return '';
    }
  }

  /// תוכן ספר אישי או ממסד מצורף — רק מאותו מסד, לעולם לא ספר רשמי באותה כותרת.
  Future<String> _loadSourceBookContent(
    String title,
    BookSource source,
    int? categoryId,
  ) async {
    try {
      final record = await BookDatabaseResolver.resolveBook(
        title: title,
        categoryId: categoryId,
        preferSource: source,
      );
      if (record == null || record.source != source) return '';
      final dbBook = record.book;
      if (dbBook.isFileBacked) {
        final path = dbBook.filePath;
        if (path == null || !await File(path).exists()) return '';
        return await readFileBackedBookText(
              File(path),
              dbBook.fileType,
              title,
            ) ??
            '';
      }
      return await DatabaseLibraryProvider.instance.getBookText(
            title,
            dbBook.categoryId,
            dbBook.fileType ?? 'txt',
            preferSource: source,
          ) ??
          '';
    } catch (e) {
      debugPrint(
        '[PersonalNotes] ${source.wireKey} content load failed for "$title": $e',
      );
      return '';
    }
  }
}
